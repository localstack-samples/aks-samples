#!/bin/bash

# Step 6: deploy the consumer and the KEDA resources that scale it.
#
# The consumer Deployment starts at zero replicas: the ScaledObject activates it when the consumer
# group falls behind the event hub. Three values are derived at apply time rather than hardcoded, so
# the same manifests work against the emulator and against real Azure:
#
#  - the container image, from the registry's login server;
#  - the event hub connection string, from the hub's authorization rule;
#  - the storage connection string, from the storage account.
#
# Both connection strings are put in the same secret and reach the consumer container through envFrom,
# because the trigger reads them from the scale target's environment (connectionFromEnv,
# storageConnectionFromEnv) instead of from a TriggerAuthentication. There is no endpointSuffix to
# derive: unlike the Service Bus scaler, which polls an HTTPS management API, this one talks AMQP and
# takes its endpoint from the connection string.
# https://keda.sh/docs/2.20/scalers/azure-event-hub/

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

# Create the config map with the non-secret settings shared by the producer and the consumer
echo "Creating the [$CONFIG_MAP_NAME] config map in the [$NAMESPACE] namespace..."
cat configmap.yml |
  yq "(.metadata.name)|=\"$CONFIG_MAP_NAME\"" |
  yq "(.metadata.namespace)|=\"$NAMESPACE\"" |
  yq "(.data.EVENTHUB_NAME)|=\"$EVENT_HUB_NAME\"" |
  yq "(.data.CONSUMER_GROUP)|=\"$EVENT_HUB_CONSUMER_GROUP\"" |
  yq "(.data.CHECKPOINT_CONTAINER)|=\"$CHECKPOINT_CONTAINER\"" |
  yq "(.data.MESSAGE_COUNT)|=\"$MESSAGE_COUNT\"" |
  yq "(.data.WORK_SECONDS)|=\"$WORK_SECONDS\"" |
  kubectl apply -f -
if [[ $? -ne 0 ]]; then
  echo "Failed to create the [$CONFIG_MAP_NAME] config map"
  exit 1
fi

# Retrieve the connection string of the hub's authorization rule, used by the scaler, the producer and
# the consumer. Because the rule is on the event hub, the connection string carries EntityPath=<hub>.
echo "Retrieving the connection string of the [$EVENT_HUB_AUTHORIZATION_RULE] authorization rule of the [$EVENT_HUB_NAME] event hub..."
EVENT_HUB_CONNECTION=$(az eventhubs eventhub authorization-rule keys list \
  --eventhub-name $EVENT_HUB_NAME \
  --namespace-name $EVENT_HUBS_NAMESPACE_NAME \
  --resource-group $AKS_RESOURCE_GROUP_NAME \
  --name $EVENT_HUB_AUTHORIZATION_RULE \
  --query primaryConnectionString \
  --output tsv \
  --only-show-errors 2>/dev/null)
if [[ -z $EVENT_HUB_CONNECTION ]]; then
  echo "Failed to retrieve the connection string of the [$EVENT_HUB_AUTHORIZATION_RULE] authorization rule"
  echo "Run 03-create-resources.sh first"
  exit 1
fi

# Retrieve the connection string of the storage account holding the checkpoints
echo "Retrieving the connection string of the [$STORAGE_ACCOUNT_NAME] storage account..."
STORAGE_ACCOUNT_CONNECTION=$(az storage account show-connection-string \
  --name $STORAGE_ACCOUNT_NAME \
  --resource-group $AKS_RESOURCE_GROUP_NAME \
  --query connectionString \
  --output tsv \
  --only-show-errors 2>/dev/null)
if [[ -z $STORAGE_ACCOUNT_CONNECTION ]]; then
  echo "Failed to retrieve the connection string of the [$STORAGE_ACCOUNT_NAME] storage account"
  echo "Run 03-create-resources.sh first"
  exit 1
fi

# Create the secret with both connection strings, used verbatim as returned by Azure
echo "Creating the [$SECRET_NAME] secret in the [$NAMESPACE] namespace..."
cat secret.yml |
  yq "(.metadata.name)|=\"$SECRET_NAME\"" |
  yq "(.metadata.namespace)|=\"$NAMESPACE\"" |
  yq "(.data.EVENTHUB_CONNECTION)|=\"$(echo -n "$EVENT_HUB_CONNECTION" | base64 -w0)\"" |
  yq "(.data.STORAGE_CONNECTION)|=\"$(echo -n "$STORAGE_ACCOUNT_CONNECTION" | base64 -w0)\"" |
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

# Create the ScaledObject that scales the consumer on the consumer group's lag. connectionFromEnv and
# storageConnectionFromEnv stay as they are in the manifest: they are the names of the secret keys the
# Deployment injects, not values to patch.
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
  yq "(.spec.triggers[0].metadata.consumerGroup)|=\"$EVENT_HUB_CONSUMER_GROUP\"" |
  yq "(.spec.triggers[0].metadata.unprocessedEventThreshold)|=\"$SCALING_THRESHOLD\"" |
  yq "(.spec.triggers[0].metadata.blobContainer)|=\"$CHECKPOINT_CONTAINER\"" |
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
echo "The [$DEPLOYMENT_NAME] deployment is scaled to zero and waiting for events:"
kubectl get deployment $DEPLOYMENT_NAME --namespace $NAMESPACE
