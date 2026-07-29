#!/bin/bash

# Step 1: make sure the AKS cluster has the managed KEDA add-on enabled, then wait until the add-on
# is actually serving. The cluster-creation scripts already pass --enable-keda, so on such a cluster
# this script detects the add-on and leaves it in place. It still runs cleanly on a cluster created
# without it, enabling it through the live az aks update path.
# https://learn.microsoft.com/en-us/azure/aks/keda-deploy-add-on-cli

# Variables
source ./00-variables.sh

# Make sure the AKS cluster exists (it is created by scripts/01-user-assigned-managed-identity.sh)
NODE_RESOURCE_GROUP=$(az aks show \
  --name $AKS_NAME \
  --resource-group $AKS_RESOURCE_GROUP_NAME \
  --query nodeResourceGroup \
  --output tsv \
  --only-show-errors 2>/dev/null)
if [[ -z $NODE_RESOURCE_GROUP ]]; then
  echo "Could not resolve the node resource group for the [$AKS_NAME] AKS cluster"
  echo "Create the cluster first with scripts/01-user-assigned-managed-identity.sh"
  exit 1
fi

# Enable the add-on only if it is not enabled yet
echo "Checking if the KEDA add-on is enabled in the [$AKS_NAME] AKS cluster..."
KEDA_ENABLED=$(az aks show \
  --name $AKS_NAME \
  --resource-group $AKS_RESOURCE_GROUP_NAME \
  --query workloadAutoScalerProfile.keda.enabled \
  --output tsv \
  --only-show-errors 2>/dev/null)

if [[ "$KEDA_ENABLED" == "true" ]]; then
  echo "The KEDA add-on is already enabled in the [$AKS_NAME] AKS cluster"
else
  echo "The KEDA add-on is not enabled in the [$AKS_NAME] AKS cluster"
  echo "Enabling the KEDA add-on in the [$AKS_NAME] AKS cluster..."

  az aks update \
    --name $AKS_NAME \
    --resource-group $AKS_RESOURCE_GROUP_NAME \
    --enable-keda \
    --only-show-errors 1>/dev/null

  if [[ $? -eq 0 ]]; then
    echo "The KEDA add-on was successfully enabled in the [$AKS_NAME] AKS cluster"
  else
    echo "Failed to enable the KEDA add-on in the [$AKS_NAME] AKS cluster"
    exit 1
  fi
fi

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

# Wait for the KEDA operator, the component that evaluates the scaling triggers
echo "Waiting for the [$KEDA_OPERATOR_DEPLOYMENT] deployment in the [$KEDA_NAMESPACE] namespace..."
kubectl wait deployment/$KEDA_OPERATOR_DEPLOYMENT \
  --namespace $KEDA_NAMESPACE \
  --for=condition=Available \
  --timeout=${TIMEOUT_SECONDS}s
if [[ $? -ne 0 ]]; then
  echo "The [$KEDA_OPERATOR_DEPLOYMENT] deployment did not become available"
  kubectl get deployments --namespace $KEDA_NAMESPACE
  exit 1
fi

# Wait for the ScaledObject custom resource definition, without which the ScaledObject cannot be applied
echo "Waiting for the [$KEDA_SCALED_OBJECT_CRD] custom resource definition..."
kubectl wait crd/$KEDA_SCALED_OBJECT_CRD \
  --for=condition=Established \
  --timeout=${TIMEOUT_SECONDS}s
if [[ $? -ne 0 ]]; then
  echo "The [$KEDA_SCALED_OBJECT_CRD] custom resource definition was not established"
  kubectl get crd | grep keda
  exit 1
fi

# The add-on publishes its KEDA version as a label on the CRD
# https://learn.microsoft.com/en-us/azure/aks/keda-deploy-add-on-cli
KEDA_VERSION=$(kubectl get crd/$KEDA_SCALED_OBJECT_CRD \
  --output jsonpath='{.metadata.labels.app\.kubernetes\.io/version}' 2>/dev/null)
echo "KEDA [$KEDA_VERSION] is running in the [$KEDA_NAMESPACE] namespace:"

# The component deployment names differ between the AKS managed add-on
# (keda-operator-metrics-apiserver, keda-admission-webhooks) and the upstream bundle the LocalStack
# emulator installs (keda-metrics-apiserver, keda-admission), so they are listed, not asserted.
kubectl get deployments --namespace $KEDA_NAMESPACE --no-headers 2>/dev/null | grep keda
