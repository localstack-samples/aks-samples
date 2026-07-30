#!/bin/bash

# Step 6: deploy the application service account, the consumer, and the KEDA resources that scale it.
#
# The consumer Deployment starts at zero replicas: the ScaledObject activates it when the queue has
# messages. Nothing here carries a credential. The service account is annotated with the shared managed
# identity's client id and the signed-in tenant id, and the pod templates carry the
# azure.workload.identity/use: "true" label, so the workload-identity webhook projects a token into the
# pods and DefaultAzureCredential does the rest. There is no secret in this tutorial.
# https://learn.microsoft.com/en-us/azure/aks/workload-identity-deploy-cluster
#
# Three values are derived at apply time rather than hardcoded, so the same manifests work against the
# emulator and against real Azure:
#
#  - the container image, from the registry's login server;
#  - the applications' QUEUE_ENDPOINT, from the ARM-returned primaryEndpoints.queue of the storage
#    account, with its trailing slash stripped;
#  - the trigger's endpointSuffix, from the authority of that same endpoint minus the account label. The
#    KEDA azure-queue scaler builds its URL as https://{accountName}.{endpointSuffix}/{queueName}, so the
#    suffix is queue.core.windows.net on real Azure and the emulator's queue host and gateway port on
#    LocalStack. Unlike Service Bus, whose AMQP data port differs from its management port, the queue
#    endpoint already carries the port that serves the queue REST API, so no port substitution is needed.
# https://keda.sh/docs/2.20/scalers/azure-storage-queue/

# Variables
source ./00-variables.sh

# Create the namespace if it does not already exist
RESULT=$(kubectl get namespace $NAMESPACE --output jsonpath='{.metadata.name}' 2>/dev/null)
if [[ -n $RESULT ]]; then
  echo "The [$NAMESPACE] namespace already exists"
else
  echo "Creating the [$NAMESPACE] namespace..."
  cat namespace.yml |
    yq "(.metadata.name)|=\"$NAMESPACE\"" |
    kubectl apply -f -
  if [[ $? -ne 0 ]]; then
    echo "Failed to create the [$NAMESPACE] namespace"
    exit 1
  fi
fi

# Retrieve the client id of the shared managed identity, used by the service account and by the
# TriggerAuthentication. The client id is what a workload authenticates with; the principal id used for
# the role assignment in 03-create-resources.sh is a different value.
MANAGED_IDENTITY_CLIENT_ID=$(az identity show \
  --name $MANAGED_IDENTITY_NAME \
  --resource-group $AKS_RESOURCE_GROUP_NAME \
  --query clientId \
  --output tsv \
  --only-show-errors 2>/dev/null)
if [[ -z $MANAGED_IDENTITY_CLIENT_ID ]]; then
  echo "Failed to retrieve the client id of the [$MANAGED_IDENTITY_NAME] managed identity"
  echo "Run 02-create-managed-identity.sh first"
  exit 1
fi

# TENANT_ID is read from the signed-in account by ../../00-variables.sh and annotated on the service
# account, so the webhook knows which tenant to request the token from
if [[ -z $TENANT_ID ]]; then
  echo "Failed to retrieve the tenant id of the signed-in account, run az login first"
  exit 1
fi

# Create the service account the producer and the consumer run as
echo "Creating the [$SERVICE_ACCOUNT_NAME] service account in the [$NAMESPACE] namespace..."
cat serviceaccount.yml |
  yq "(.metadata.name)|=\"$SERVICE_ACCOUNT_NAME\"" |
  yq "(.metadata.namespace)|=\"$NAMESPACE\"" |
  yq "(.metadata.annotations.\"azure.workload.identity/client-id\")|=\"$MANAGED_IDENTITY_CLIENT_ID\"" |
  yq "(.metadata.annotations.\"azure.workload.identity/tenant-id\")|=\"$TENANT_ID\"" |
  kubectl apply -f -
if [[ $? -ne 0 ]]; then
  echo "Failed to create the [$SERVICE_ACCOUNT_NAME] service account"
  exit 1
fi

# Retrieve the queue endpoint of the storage account, the account URL the applications talk to
QUEUE_ENDPOINT=$(az storage account show \
  --name $STORAGE_ACCOUNT_NAME \
  --resource-group $AKS_RESOURCE_GROUP_NAME \
  --query primaryEndpoints.queue \
  --output tsv \
  --only-show-errors 2>/dev/null)
if [[ -z $QUEUE_ENDPOINT ]]; then
  echo "Failed to retrieve the queue endpoint of the [$STORAGE_ACCOUNT_NAME] storage account"
  echo "Run 03-create-resources.sh first"
  exit 1
fi

# Real Azure returns the endpoint with a trailing slash and the emulator without one; the SDK appends
# the queue name to it, so it is normalized here
QUEUE_ENDPOINT="${QUEUE_ENDPOINT%/}"
echo "The queue endpoint of the [$STORAGE_ACCOUNT_NAME] storage account is [$QUEUE_ENDPOINT]"

# Create the config map with the settings shared by the producer and the consumer. It is the only thing
# injected into the pods: the applications authenticate with workload identity, so there is no secret.
echo "Creating the [$CONFIG_MAP_NAME] config map in the [$NAMESPACE] namespace..."
cat configmap.yml |
  yq "(.metadata.name)|=\"$CONFIG_MAP_NAME\"" |
  yq "(.metadata.namespace)|=\"$NAMESPACE\"" |
  yq "(.data.QUEUE_ENDPOINT)|=\"$QUEUE_ENDPOINT\"" |
  yq "(.data.QUEUE_NAME)|=\"$STORAGE_QUEUE_NAME\"" |
  yq "(.data.MESSAGE_COUNT)|=\"$MESSAGE_COUNT\"" |
  yq "(.data.WORK_SECONDS)|=\"$WORK_SECONDS\"" |
  yq "(.data.BATCH_SIZE)|=\"$BATCH_SIZE\"" |
  kubectl apply -f -
if [[ $? -ne 0 ]]; then
  echo "Failed to create the [$CONFIG_MAP_NAME] config map"
  exit 1
fi

# Derive the container image from the registry's login server
ACR_LOGIN_SERVER=$(az acr show \
  --name $ACR_NAME \
  --query loginServer \
  --output tsv \
  --only-show-errors 2>/dev/null)
if [[ -z $ACR_LOGIN_SERVER ]]; then
  echo "Failed to retrieve the login server of the [$ACR_NAME] container registry"
  exit 1
fi
CONSUMER_IMAGE="${ACR_LOGIN_SERVER}/${CONSUMER_IMAGE_NAME}:${IMAGE_TAG}"

# Deploy the consumer
echo "Creating the [$DEPLOYMENT_NAME] deployment in the [$NAMESPACE] namespace with image [$CONSUMER_IMAGE]..."
cat deployment.yml |
  yq "(.metadata.namespace)|=\"$NAMESPACE\"" |
  yq "(.spec.template.spec.serviceAccountName)|=\"$SERVICE_ACCOUNT_NAME\"" |
  yq "(.spec.template.spec.containers[0].image)|=\"$CONSUMER_IMAGE\"" |
  yq "(.spec.template.spec.containers[0].imagePullPolicy)|=\"$IMAGE_PULL_POLICY\"" |
  yq "(.spec.template.spec.containers[0].envFrom[0].configMapRef.name)|=\"$CONFIG_MAP_NAME\"" |
  yq "(.spec.replicas)|=$MIN_REPLICAS" |
  kubectl apply -f -
if [[ $? -ne 0 ]]; then
  echo "Failed to create the [$DEPLOYMENT_NAME] deployment"
  exit 1
fi

# Tell KEDA to authenticate with workload identity, using the same shared managed identity
echo "Creating the [$TRIGGER_AUTHENTICATION_NAME] trigger authentication in the [$NAMESPACE] namespace..."
cat triggerauthentication.yml |
  yq "(.metadata.name)|=\"$TRIGGER_AUTHENTICATION_NAME\"" |
  yq "(.metadata.namespace)|=\"$NAMESPACE\"" |
  yq "(.spec.podIdentity.identityId)|=\"$MANAGED_IDENTITY_CLIENT_ID\"" |
  kubectl apply -f -
if [[ $? -ne 0 ]]; then
  echo "Failed to create the [$TRIGGER_AUTHENTICATION_NAME] trigger authentication"
  exit 1
fi

# Derive the trigger's endpointSuffix (see the header comment): the authority of the queue endpoint,
# host and port included, with the account label removed. The port is kept exactly as ARM returned it.
QUEUE_AUTHORITY="${QUEUE_ENDPOINT#*://}"
QUEUE_AUTHORITY="${QUEUE_AUTHORITY%%/*}"
ENDPOINT_SUFFIX="${QUEUE_AUTHORITY#${STORAGE_ACCOUNT_NAME}.}"
if [[ "$ENDPOINT_SUFFIX" == "$QUEUE_AUTHORITY" ]]; then
  echo "The queue endpoint [$QUEUE_ENDPOINT] does not start with the [$STORAGE_ACCOUNT_NAME] account name"
  echo "The trigger's endpointSuffix cannot be derived from it"
  exit 1
fi
echo "The KEDA trigger will reach the queue at [https://${STORAGE_ACCOUNT_NAME}.${ENDPOINT_SUFFIX}/${STORAGE_QUEUE_NAME}]"

# Create the ScaledObject that scales the consumer on the queue backlog
echo "Creating the [$SCALED_OBJECT_NAME] scaled object in the [$NAMESPACE] namespace..."
cat scaledobject.yml |
  yq "(.metadata.name)|=\"$SCALED_OBJECT_NAME\"" |
  yq "(.metadata.namespace)|=\"$NAMESPACE\"" |
  yq "(.spec.scaleTargetRef.name)|=\"$DEPLOYMENT_NAME\"" |
  yq "(.spec.pollingInterval)|=$POLLING_INTERVAL" |
  yq "(.spec.cooldownPeriod)|=$COOLDOWN_PERIOD" |
  yq "(.spec.minReplicaCount)|=$MIN_REPLICAS" |
  yq "(.spec.maxReplicaCount)|=$MAX_REPLICAS" |
  yq "(.spec.advanced.horizontalPodAutoscalerConfig.behavior.scaleDown.stabilizationWindowSeconds)|=$SCALE_DOWN_STABILIZATION_SECONDS" |
  yq "(.spec.advanced.horizontalPodAutoscalerConfig.behavior.scaleUp.policies[0].value)|=$SCALE_UP_PODS" |
  yq "(.spec.advanced.horizontalPodAutoscalerConfig.behavior.scaleUp.policies[0].periodSeconds)|=$SCALE_UP_PERIOD_SECONDS" |
  yq "(.spec.triggers[0].metadata.queueName)|=\"$STORAGE_QUEUE_NAME\"" |
  yq "(.spec.triggers[0].metadata.accountName)|=\"$STORAGE_ACCOUNT_NAME\"" |
  yq "(.spec.triggers[0].metadata.queueLength)|=\"$SCALING_THRESHOLD\"" |
  yq "(.spec.triggers[0].metadata.endpointSuffix)|=\"$ENDPOINT_SUFFIX\"" |
  yq "(.spec.triggers[0].authenticationRef.name)|=\"$TRIGGER_AUTHENTICATION_NAME\"" |
  kubectl apply -f -
if [[ $? -ne 0 ]]; then
  echo "Failed to create the [$SCALED_OBJECT_NAME] scaled object"
  exit 1
fi

# KEDA creates a HorizontalPodAutoscaler for the ScaledObject; its presence means KEDA accepted it
echo "Waiting for KEDA to create the [$HPA_NAME] horizontal pod autoscaler..."
HPA_READY=""
for i in $(seq 1 $(($TIMEOUT_SECONDS / $SLEEP))); do
  kubectl get hpa $HPA_NAME --namespace $NAMESPACE &>/dev/null
  if [[ $? -eq 0 ]]; then
    HPA_READY="true"
    break
  fi
  sleep $SLEEP
done

if [[ -z $HPA_READY ]]; then
  echo "KEDA did not create the [$HPA_NAME] horizontal pod autoscaler"
  kubectl get scaledobject --namespace $NAMESPACE
  kubectl logs deployment/$KEDA_OPERATOR_DEPLOYMENT --namespace $KEDA_NAMESPACE --tail=40
  exit 1
fi

echo "KEDA created the [$HPA_NAME] horizontal pod autoscaler:"
kubectl get hpa $HPA_NAME --namespace $NAMESPACE
echo "The [$DEPLOYMENT_NAME] deployment is scaled to zero and waiting for messages:"
kubectl get deployment $DEPLOYMENT_NAME --namespace $NAMESPACE
