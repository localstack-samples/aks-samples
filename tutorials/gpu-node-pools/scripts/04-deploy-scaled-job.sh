#!/bin/bash

# Step 4: deploy the training job: the namespace, the job's service account bound to the managed identity, the training
# script as a config map, the TriggerAuthentication and the KEDA ScaledJob. Three values are derived at apply time rather
# than hardcoded, so the same manifests work against the emulator and against Azure:
#  - the identity's client id;
#  - the namespace's host name and, on the emulator, the custom endpoint address of its AMQP listener (functions.sh);
#  - the scaler's endpointSuffix: the KEDA scaler reads the message count over the HTTPS API, served on the Azure
#    Resource Manager port.
# https://keda.sh/docs/2.20/concepts/scaling-jobs/
# https://keda.sh/docs/2.20/scalers/azure-service-bus/

# Variables
source ./00-variables.sh
source ./functions.sh

# Wait for the ScaledJob custom resource definition, without which the ScaledJob can't be applied
echo "Waiting for the [$KEDA_SCALED_JOB_CRD] custom resource definition..."
if ! kubectl wait "crd/$KEDA_SCALED_JOB_CRD" --for=condition=Established --timeout=300s; then
  echo "The [$KEDA_SCALED_JOB_CRD] custom resource definition isn't established: is the KEDA add-on running?"
  exit 1
fi

# Read the identity's client id and the Service Bus endpoints
MANAGED_IDENTITY_CLIENT_ID=$(az identity show \
  --name "$MANAGED_IDENTITY_NAME" \
  --resource-group "$AKS_RESOURCE_GROUP_NAME" \
  --query clientId \
  --output tsv \
  --only-show-errors 2>/dev/null | tr -d '\r')
if [[ -z $MANAGED_IDENTITY_CLIENT_ID ]]; then
  echo "Failed to retrieve the client id of the [$MANAGED_IDENTITY_NAME] managed identity: run 03-create-resources.sh first"
  exit 1
fi
read_service_bus_endpoints || exit 1
echo "Service Bus host [$SERVICE_BUS_HOST], custom endpoint [${SERVICE_BUS_CUSTOM_ENDPOINT:-none}], scaler endpoint suffix [$SERVICE_BUS_ENDPOINT_SUFFIX]"

# Create the namespace if it does not already exist
if kubectl get namespace "$NAMESPACE" &>/dev/null; then
  echo "The [$NAMESPACE] namespace already exists"
else
  echo "Creating the [$NAMESPACE] namespace..."
  if ! kubectl create namespace "$NAMESPACE"; then
    echo "Failed to create the [$NAMESPACE] namespace"
    exit 1
  fi
fi

# The job's service account, bound to the managed identity
echo "Creating the [$SERVICE_ACCOUNT_NAME] service account in the [$NAMESPACE] namespace..."
cat serviceaccount.yml |
  yq "(.metadata.name)|=\"$SERVICE_ACCOUNT_NAME\"" |
  yq "(.metadata.namespace)|=\"$NAMESPACE\"" |
  yq "(.metadata.annotations.\"azure.workload.identity/client-id\")|=\"$MANAGED_IDENTITY_CLIENT_ID\"" |
  kubectl apply -f -
if [[ $? -ne 0 ]]; then
  echo "Failed to create the [$SERVICE_ACCOUNT_NAME] service account"
  exit 1
fi

# The training script, mounted into the job's pod
echo "Creating the [$SCRIPT_CONFIG_MAP_NAME] config map from src/train.py..."
kubectl create configmap "$SCRIPT_CONFIG_MAP_NAME" \
  --namespace "$NAMESPACE" \
  --from-file=train.py=../src/train.py \
  --dry-run=client \
  --output yaml |
  kubectl apply -f -
if [[ $? -ne 0 ]]; then
  echo "Failed to create the [$SCRIPT_CONFIG_MAP_NAME] config map"
  exit 1
fi

# The TriggerAuthentication: the KEDA operator reads the queue as the managed identity
echo "Creating the [$TRIGGER_AUTHENTICATION_NAME] TriggerAuthentication..."
cat triggerauthentication.yml |
  yq "(.metadata.name)|=\"$TRIGGER_AUTHENTICATION_NAME\"" |
  yq "(.metadata.namespace)|=\"$NAMESPACE\"" |
  yq "(.spec.podIdentity.identityId)|=\"$MANAGED_IDENTITY_CLIENT_ID\"" |
  kubectl apply -f -
if [[ $? -ne 0 ]]; then
  echo "Failed to create the [$TRIGGER_AUTHENTICATION_NAME] TriggerAuthentication"
  exit 1
fi

# The ScaledJob
JOB_COMMAND="pip install --quiet --no-cache-dir --target /tmp/pydeps $JOB_PYTHON_PACKAGES && exec python /app/train.py"
echo "Creating the [$SCALED_JOB_NAME] ScaledJob with image [$JOB_IMAGE]..."
cat scaledjob.yml |
  yq "(.metadata.name)|=\"$SCALED_JOB_NAME\"" |
  yq "(.metadata.namespace)|=\"$NAMESPACE\"" |
  yq "(.spec.jobTargetRef.backoffLimit)|=$JOB_BACKOFF_LIMIT" |
  yq "(.spec.jobTargetRef.template.spec.serviceAccountName)|=\"$SERVICE_ACCOUNT_NAME\"" |
  yq "(.spec.jobTargetRef.template.spec.nodeSelector)|={\"$GPU_NODE_LABEL_KEY\": \"$GPU_NODE_LABEL_VALUE\"}" |
  yq "(.spec.jobTargetRef.template.spec.tolerations[0].key)|=\"$GPU_NODE_TAINT_KEY\"" |
  yq "(.spec.jobTargetRef.template.spec.tolerations[0].value)|=\"$GPU_NODE_TAINT_VALUE\"" |
  yq "(.spec.jobTargetRef.template.spec.tolerations[1].key)|=\"$SPOT_KEY\"" |
  yq "(.spec.jobTargetRef.template.spec.tolerations[1].value)|=\"$SPOT_VALUE\"" |
  yq "(.spec.jobTargetRef.template.spec.containers[0].image)|=\"$JOB_IMAGE\"" |
  yq "(.spec.jobTargetRef.template.spec.containers[0].args[0])|=\"$JOB_COMMAND\"" |
  yq "(.spec.jobTargetRef.template.spec.containers[0].env[0].value)|=\"$SERVICE_BUS_HOST\"" |
  yq "(.spec.jobTargetRef.template.spec.containers[0].env[1].value)|=\"$SERVICE_BUS_CUSTOM_ENDPOINT\"" |
  yq "(.spec.jobTargetRef.template.spec.containers[0].env[2].value)|=\"$SERVICE_BUS_QUEUE_NAME\"" |
  yq "(.spec.jobTargetRef.template.spec.containers[0].env[3].value)|=\"$JOB_DEFAULT_TRAIN_SECONDS\"" |
  yq "(.spec.jobTargetRef.template.spec.containers[0].resources.requests.cpu)|=\"$JOB_CPU_REQUEST\"" |
  yq "(.spec.jobTargetRef.template.spec.containers[0].resources.requests.memory)|=\"$JOB_MEMORY_REQUEST\"" |
  yq "(.spec.jobTargetRef.template.spec.containers[0].resources.limits.memory)|=\"$JOB_MEMORY_LIMIT\"" |
  yq "(.spec.jobTargetRef.template.spec.volumes[1].configMap.name)|=\"$SCRIPT_CONFIG_MAP_NAME\"" |
  yq "(.spec.pollingInterval)|=$SCALED_JOB_POLLING_INTERVAL" |
  yq "(.spec.maxReplicaCount)|=$SCALED_JOB_MAX_REPLICAS" |
  yq "(.spec.triggers[0].authenticationRef.name)|=\"$TRIGGER_AUTHENTICATION_NAME\"" |
  yq "(.spec.triggers[0].metadata.queueName)|=\"$SERVICE_BUS_QUEUE_NAME\"" |
  yq "(.spec.triggers[0].metadata.namespace)|=\"$SERVICE_BUS_NAMESPACE_NAME\"" |
  yq "(.spec.triggers[0].metadata.endpointSuffix)|=\"$SERVICE_BUS_ENDPOINT_SUFFIX\"" |
  kubectl apply -f -
if [[ $? -ne 0 ]]; then
  echo "Failed to create the [$SCALED_JOB_NAME] ScaledJob"
  exit 1
fi

# KEDA reports the ScaledJob Ready once its trigger can read the queue
echo "Waiting for the [$SCALED_JOB_NAME] ScaledJob to be ready..."
if ! kubectl wait "scaledjob/$SCALED_JOB_NAME" --namespace "$NAMESPACE" --for=condition=Ready --timeout=300s; then
  echo "The [$SCALED_JOB_NAME] ScaledJob isn't ready; the KEDA operator's log says why:"
  kubectl logs "deployment/$KEDA_OPERATOR_DEPLOYMENT" --namespace "$KEDA_NAMESPACE" --tail=30
  exit 1
fi
kubectl get scaledjob "$SCALED_JOB_NAME" --namespace "$NAMESPACE"
