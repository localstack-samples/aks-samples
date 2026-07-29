#!/bin/bash

# Step 7: fill the event hub by running the producer as a Kubernetes Job.
#
# A Job's pod template is immutable once the Job exists, so a previous run is deleted before this one
# is applied; that is what makes the script re-runnable. The Job also carries ttlSecondsAfterFinished
# so the TTL-after-finished controller reaps it on its own.
# https://kubernetes.io/docs/concepts/workloads/controllers/job/

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

# The consumer should be idle before the events are sent, so the scale-out from zero is visible
REPLICAS=$(kubectl get deployment $DEPLOYMENT_NAME \
  --namespace $NAMESPACE \
  --output jsonpath='{.spec.replicas}' 2>/dev/null)
if [[ -z $REPLICAS ]]; then
  echo "The [$DEPLOYMENT_NAME] deployment does not exist in the [$NAMESPACE] namespace"
  echo "Run 06-deploy-consumer.sh first"
  exit 1
fi
echo "The [$DEPLOYMENT_NAME] deployment currently has [$REPLICAS] replicas"

# Delete a previous run of the producer Job, if any
kubectl get job $PRODUCER_JOB_NAME --namespace $NAMESPACE &>/dev/null
if [[ $? -eq 0 ]]; then
  echo "Deleting the previous [$PRODUCER_JOB_NAME] job (a job's pod template cannot be updated in place)..."
  kubectl delete job $PRODUCER_JOB_NAME --namespace $NAMESPACE --ignore-not-found --wait=true
  if [[ $? -ne 0 ]]; then
    echo "Failed to delete the previous [$PRODUCER_JOB_NAME] job"
    exit 1
  fi
fi

# Derive the producer image from the registry's login server
ACR_LOGIN_SERVER=$(az acr show \
  --name $ACR_NAME \
  --query loginServer \
  --output tsv \
  --only-show-errors 2>/dev/null)
if [[ -z $ACR_LOGIN_SERVER ]]; then
  echo "Failed to retrieve the login server of the [$ACR_NAME] container registry"
  exit 1
fi
PRODUCER_IMAGE="${ACR_LOGIN_SERVER}/${PRODUCER_IMAGE_NAME}:${IMAGE_TAG}"

# Run the producer
echo "Creating the [$PRODUCER_JOB_NAME] job in the [$NAMESPACE] namespace with image [$PRODUCER_IMAGE]..."
cat producer-job.yml |
  yq "(.metadata.name)|=\"$PRODUCER_JOB_NAME\"" |
  yq "(.metadata.namespace)|=\"$NAMESPACE\"" |
  yq "(.spec.template.spec.containers[0].image)|=\"$PRODUCER_IMAGE\"" |
  yq "(.spec.template.spec.containers[0].imagePullPolicy)|=\"$IMAGE_PULL_POLICY\"" |
  yq "(.spec.template.spec.containers[0].envFrom[0].configMapRef.name)|=\"$CONFIG_MAP_NAME\"" |
  yq "(.spec.template.spec.containers[0].envFrom[1].secretRef.name)|=\"$SECRET_NAME\"" |
  kubectl apply -f -
if [[ $? -ne 0 ]]; then
  echo "Failed to create the [$PRODUCER_JOB_NAME] job"
  exit 1
fi

# Wait for the producer to finish sending
echo "Waiting for the [$PRODUCER_JOB_NAME] job to send [$MESSAGE_COUNT] events..."
kubectl wait job/$PRODUCER_JOB_NAME \
  --namespace $NAMESPACE \
  --for=condition=complete \
  --timeout=${TIMEOUT_SECONDS}s
if [[ $? -ne 0 ]]; then
  echo "The [$PRODUCER_JOB_NAME] job did not complete"
  kubectl describe job $PRODUCER_JOB_NAME --namespace $NAMESPACE
  kubectl logs job/$PRODUCER_JOB_NAME --namespace $NAMESPACE --tail=40
  exit 1
fi

echo "The [$PRODUCER_JOB_NAME] job completed:"
kubectl logs job/$PRODUCER_JOB_NAME --namespace $NAMESPACE --tail=5
echo "Run 08-watch-scaling.sh now to watch KEDA scale the [$DEPLOYMENT_NAME] deployment out and back to zero"
