#!/bin/bash

# Step 6: deploy the consumer and the KEDA resources that scale it.
#
# The consumer Deployment starts at zero replicas: the ScaledObject activates it when the queue has
# messages. Two values are derived at apply time rather than hardcoded, so the same manifests work
# against the emulator and against real Azure:
#
#  - the container image, from the registry's login server;
#  - the trigger's endpointSuffix, from the ARM-returned serviceBusEndpoint. The KEDA scaler reads
#    the queue's message count over the HTTPS management API, which is served on the same port as
#    ARM (443 on real Azure, the gateway port on the emulator), while the serviceBusEndpoint port is
#    the AMQP data port. Hence the host comes from serviceBusEndpoint and the port from ARM.
# https://keda.sh/docs/2.20/scalers/azure-service-bus/

# Variables
source ./00-variables.sh

# Merge the cluster credentials into kubeconfig and set it as the current context
echo "Merging credentials for the [$AKS_NAME] AKS cluster into kubeconfig..."
az aks get-credentials \
  --name $AKS_NAME \
  --resource-group $AKS_RESOURCE_GROUP_NAME \
  --overwrite-existing \
  --only-show-errors
if [[ $? -ne 0 ]]; then
  echo "Failed to merge the credentials for the [$AKS_NAME] AKS cluster"
  exit 1
fi

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

# Create the config map with the non-secret settings shared by the producer and the consumer
echo "Creating the [$CONFIG_MAP_NAME] config map in the [$NAMESPACE] namespace..."
cat configmap.yml |
  yq "(.metadata.name)|=\"$CONFIG_MAP_NAME\"" |
  yq "(.metadata.namespace)|=\"$NAMESPACE\"" |
  yq "(.data.QUEUE_NAME)|=\"$SERVICE_BUS_QUEUE_NAME\"" |
  yq "(.data.MESSAGE_COUNT)|=\"$MESSAGE_COUNT\"" |
  yq "(.data.WORK_SECONDS)|=\"$WORK_SECONDS\"" |
  yq "(.data.BATCH_SIZE)|=\"$BATCH_SIZE\"" |
  kubectl apply -f -
if [[ $? -ne 0 ]]; then
  echo "Failed to create the [$CONFIG_MAP_NAME] config map"
  exit 1
fi

# Retrieve the namespace connection string used by the producer and consumer applications
echo "Retrieving the connection string of the [$SERVICE_BUS_NAMESPACE_NAME] Service Bus namespace..."
SERVICE_BUS_CONNECTION=$(az servicebus namespace authorization-rule keys list \
  --namespace-name $SERVICE_BUS_NAMESPACE_NAME \
  --resource-group $AKS_RESOURCE_GROUP_NAME \
  --name $SERVICE_BUS_AUTHORIZATION_RULE \
  --query primaryConnectionString \
  --output tsv \
  --only-show-errors 2>/dev/null)
if [[ -z $SERVICE_BUS_CONNECTION ]]; then
  echo "Failed to retrieve the connection string of the [$SERVICE_BUS_NAMESPACE_NAME] Service Bus namespace"
  exit 1
fi

# Create the secret with the connection string, used verbatim as returned by Azure
echo "Creating the [$SECRET_NAME] secret in the [$NAMESPACE] namespace..."
cat secret.yml |
  yq "(.metadata.name)|=\"$SECRET_NAME\"" |
  yq "(.metadata.namespace)|=\"$NAMESPACE\"" |
  yq "(.data.SERVICEBUS_CONNECTION)|=\"$(echo -n $SERVICE_BUS_CONNECTION | base64 -w0)\"" |
  kubectl apply -f -
if [[ $? -ne 0 ]]; then
  echo "Failed to create the [$SECRET_NAME] secret"
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
  yq "(.spec.template.spec.containers[0].image)|=\"$CONSUMER_IMAGE\"" |
  yq "(.spec.template.spec.containers[0].imagePullPolicy)|=\"$IMAGE_PULL_POLICY\"" |
  yq "(.spec.template.spec.containers[0].envFrom[0].configMapRef.name)|=\"$CONFIG_MAP_NAME\"" |
  yq "(.spec.template.spec.containers[0].envFrom[1].secretRef.name)|=\"$SECRET_NAME\"" |
  yq "(.spec.replicas)|=$MIN_REPLICAS" |
  kubectl apply -f -
if [[ $? -ne 0 ]]; then
  echo "Failed to create the [$DEPLOYMENT_NAME] deployment"
  exit 1
fi

# Retrieve the client id of the shared managed identity for the TriggerAuthentication
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

# Tell KEDA to authenticate with workload identity, using the shared managed identity
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

# Derive the trigger's endpointSuffix (see the header comment)
SERVICE_BUS_ENDPOINT=$(az servicebus namespace show \
  --name $SERVICE_BUS_NAMESPACE_NAME \
  --resource-group $AKS_RESOURCE_GROUP_NAME \
  --query serviceBusEndpoint \
  --output tsv \
  --only-show-errors 2>/dev/null)
if [[ -z $SERVICE_BUS_ENDPOINT ]]; then
  echo "Failed to retrieve the endpoint of the [$SERVICE_BUS_NAMESPACE_NAME] Service Bus namespace"
  exit 1
fi

# Strip the scheme, any path and any port to get the bare host
SERVICE_BUS_HOST="${SERVICE_BUS_ENDPOINT#*://}"
SERVICE_BUS_HOST="${SERVICE_BUS_HOST%%/*}"
SERVICE_BUS_HOST="${SERVICE_BUS_HOST%%:*}"

# The management API answers on the ARM port: 443 on real Azure, the gateway port on the emulator
ARM_ENDPOINT=$(az cloud show --query endpoints.resourceManager --output tsv --only-show-errors 2>/dev/null)
ARM_ENDPOINT="${ARM_ENDPOINT%/}"
ARM_PORT="${ARM_ENDPOINT##*:}"
if [[ "$ARM_PORT" == "$ARM_ENDPOINT" || "$ARM_PORT" == *"/"* ]]; then
  ARM_PORT=443
fi

ENDPOINT_SUFFIX="${SERVICE_BUS_HOST#${SERVICE_BUS_NAMESPACE_NAME}.}:${ARM_PORT}"
echo "The KEDA trigger will reach the Service Bus management API at [https://${SERVICE_BUS_NAMESPACE_NAME}.${ENDPOINT_SUFFIX}]"

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
  yq "(.spec.triggers[0].metadata.queueName)|=\"$SERVICE_BUS_QUEUE_NAME\"" |
  yq "(.spec.triggers[0].metadata.namespace)|=\"$SERVICE_BUS_NAMESPACE_NAME\"" |
  yq "(.spec.triggers[0].metadata.messageCount)|=\"$SCALING_THRESHOLD\"" |
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
