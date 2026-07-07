#!/bin/bash

# Step 2: install NGINX Gateway Fabric (NGF) from the official OCI registry as the bring-your-own
# Gateway API implementation. The Managed Gateway API installation (step 1) only manages the CRDs;
# an implementation must be deployed separately, exactly like on real AKS. The Helm chart registers
# the "nginx" GatewayClass. Idempotent: an existing release is left as is.
# https://docs.nginx.com/nginx-gateway-fabric/

# Variables
source ./00-variables.sh

# Make sure the Gateway API CRDs are installed (step 1)
CRD_COUNT=$(kubectl get crds -o name 2>/dev/null | grep -c "\.${GATEWAY_API_GROUP}$")
if [[ $CRD_COUNT -lt 5 ]]; then
  echo "The Gateway API CRDs are not installed (found $CRD_COUNT)"
  echo "Run ./01-enable-gateway-api.sh first"
  exit 1
fi

# Install NGF only when the release does not already exist
if helm status $NGF_RELEASE_NAME --namespace $NGF_NAMESPACE &>/dev/null; then
  echo "The [$NGF_RELEASE_NAME] NGINX Gateway Fabric release already exists in the [$NGF_NAMESPACE] namespace"
else
  echo "Installing the [$NGF_RELEASE_NAME] NGINX Gateway Fabric release in the [$NGF_NAMESPACE] namespace..."
  helm install $NGF_RELEASE_NAME $NGF_OCI_CHART \
    --namespace $NGF_NAMESPACE \
    --create-namespace \
    --set nginx.service.type=LoadBalancer \
    --wait \
    --timeout 10m
  if [[ $? -eq 0 ]]; then
    echo "[$NGF_RELEASE_NAME] NGINX Gateway Fabric release successfully installed"
  else
    echo "Failed to install the [$NGF_RELEASE_NAME] NGINX Gateway Fabric release"
    exit 1
  fi
fi

# The chart registers the GatewayClass; it is Accepted once the NGF control plane is running
echo "Waiting for the [$GATEWAY_CLASS_NAME] GatewayClass to be Accepted..."
kubectl wait --for=condition=Accepted gatewayclass/$GATEWAY_CLASS_NAME --timeout=120s
if [[ $? -ne 0 ]]; then
  echo "The [$GATEWAY_CLASS_NAME] GatewayClass was not Accepted within 120 seconds"
  exit 1
fi
kubectl get gatewayclass -o wide
