#!/bin/bash

# Install NGINX Gateway Fabric from the official OCI registry.
# Gateway API CRDs must already be installed before running this script.
# The Helm chart automatically creates the "nginx" GatewayClass.
helm install ngf oci://ghcr.io/nginx/charts/nginx-gateway-fabric \
  --namespace nginx-gateway \
  --create-namespace \
  --set nginx.service.type=LoadBalancer

# Verify the GatewayClass is now registered
kubectl get gatewayclass -o wide