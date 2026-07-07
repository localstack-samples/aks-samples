#!/bin/bash

# Step 5: remove everything the sample created: the echo-server namespace (Deployment, Service,
# Gateway, HTTPRoute) and the NGINX Gateway Fabric release. Pass --disable-gateway-api to also turn
# off the Managed Gateway API installation on the cluster (removes the CRDs, like real AKS).
# Every step is idempotent and tolerates already-deleted resources.

# Variables
source ./00-variables.sh

# Delete the sample namespace (removes the Deployment, Service, Gateway, and HTTPRoute)
if kubectl get namespace $NAMESPACE &>/dev/null; then
  echo "Deleting the [$NAMESPACE] namespace..."
  kubectl delete namespace $NAMESPACE --wait=true
else
  echo "The [$NAMESPACE] namespace does not exist"
fi

# Uninstall NGINX Gateway Fabric
if helm status $NGF_RELEASE_NAME --namespace $NGF_NAMESPACE &>/dev/null; then
  echo "Uninstalling the [$NGF_RELEASE_NAME] NGINX Gateway Fabric release..."
  helm uninstall $NGF_RELEASE_NAME --namespace $NGF_NAMESPACE --wait
  kubectl delete namespace $NGF_NAMESPACE --ignore-not-found --wait=true
else
  echo "The [$NGF_RELEASE_NAME] NGINX Gateway Fabric release does not exist"
fi

# Optionally disable the Managed Gateway API installation (removes the CRDs and, with them, any
# remaining Gateway API resources)
if [[ "$1" == "--disable-gateway-api" ]]; then
  echo "Disabling the Managed Gateway API on the [$AKS_NAME] AKS cluster..."
  az aks update \
    --name $AKS_NAME \
    --resource-group $AKS_RESOURCE_GROUP_NAME \
    --disable-gateway-api \
    --only-show-errors 1>/dev/null
  if [[ $? -eq 0 ]]; then
    echo "Managed Gateway API successfully disabled on the [$AKS_NAME] AKS cluster"
  else
    echo "Failed to disable the Managed Gateway API on the [$AKS_NAME] AKS cluster"
    exit 1
  fi
else
  echo "Leaving the Managed Gateway API enabled (pass --disable-gateway-api to remove the CRDs)"
fi

echo "Cleanup complete"
