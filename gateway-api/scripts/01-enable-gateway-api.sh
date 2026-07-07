#!/bin/bash

# Step 1: enable the Managed Gateway API installation on the existing AKS cluster (the live
# update-enable path: az aks update --enable-gateway-api) and verify the standard-channel Gateway
# API CRDs are installed. Idempotent: a cluster that already has the installation is left as is.
# https://learn.microsoft.com/en-us/azure/aks/managed-gateway-api

# Variables
source ./00-variables.sh

# Make sure the AKS cluster exists (it is created by 01-user-assigned-managed-identity.sh)
NODE_RESOURCE_GROUP=$(az aks show \
  --name $AKS_NAME \
  --resource-group $AKS_RESOURCE_GROUP_NAME \
  --query nodeResourceGroup \
  --output tsv \
  --only-show-errors 2>/dev/null)
if [[ -z $NODE_RESOURCE_GROUP ]]; then
  echo "Could not resolve the node resource group for the [$AKS_NAME] AKS cluster"
  echo "Create the cluster first with /home/paolo/azure/aks/scripts/01-user-assigned-managed-identity.sh"
  exit 1
fi

# Enable the Managed Gateway API only when it is not already enabled (the query falls back across
# JMESPath key casings, which vary across CLI payload versions)
INSTALLATION=$(az aks show \
  --name $AKS_NAME \
  --resource-group $AKS_RESOURCE_GROUP_NAME \
  --query 'ingressProfile.gatewayApi.installation' \
  --output tsv \
  --only-show-errors 2>/dev/null)
if [[ "$INSTALLATION" == "Standard" ]]; then
  echo "The Managed Gateway API is already enabled on the [$AKS_NAME] AKS cluster"
else
  echo "Enabling the Managed Gateway API on the [$AKS_NAME] AKS cluster..."
  az aks update \
    --name $AKS_NAME \
    --resource-group $AKS_RESOURCE_GROUP_NAME \
    --enable-gateway-api \
    --only-show-errors 1>/dev/null
  if [[ $? -eq 0 ]]; then
    echo "Managed Gateway API successfully enabled on the [$AKS_NAME] AKS cluster"
  else
    echo "Failed to enable the Managed Gateway API on the [$AKS_NAME] AKS cluster"
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

# Verify the standard-channel CRDs are installed (5 CRDs: gatewayclasses, gateways, grpcroutes,
# httproutes, referencegrants). The update LRO completes after the install, but poll defensively.
echo "Verifying the Gateway API CRDs are installed..."
ELAPSED=0
while true; do
  CRD_COUNT=$(kubectl get crds -o name 2>/dev/null | grep -c "\.${GATEWAY_API_GROUP}$")
  if [[ $CRD_COUNT -ge 5 ]]; then
    break
  fi
  if [[ $ELAPSED -ge $TIMEOUT_SECONDS ]]; then
    echo "Gateway API CRDs did not appear within $TIMEOUT_SECONDS seconds (found $CRD_COUNT)"
    exit 1
  fi
  sleep $SLEEP
  ELAPSED=$((ELAPSED + SLEEP))
done
echo "Found [$CRD_COUNT] Gateway API CRDs:"
kubectl get crds -o name | grep "\.${GATEWAY_API_GROUP}$"
echo "Found the following Gateway API resources:"
kubectl api-resources | grep ${GATEWAY_API_GROUP}

# Show the bundle version and channel annotations the managed installation stamps on the CRDs
BUNDLE_VERSION=$(kubectl get crd gateways.${GATEWAY_API_GROUP} \
  -o jsonpath="{.metadata.annotations.gateway\.networking\.k8s\.io/bundle-version}" 2>/dev/null)
CHANNEL=$(kubectl get crd gateways.${GATEWAY_API_GROUP} \
  -o jsonpath="{.metadata.annotations.gateway\.networking\.k8s\.io/channel}" 2>/dev/null)
echo "Gateway API bundle version: [$BUNDLE_VERSION], channel: [$CHANNEL]"
