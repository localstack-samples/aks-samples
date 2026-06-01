#!/bin/bash

helm upgrade \
  --install cert-manager oci://quay.io/jetstack/charts/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --set crds.enabled=true \
  --set config.enableGatewayAPI=true \
  --set config.enableGatewayAPIListenerSet=true \
  --set config.featureGates.ListenerSets=true

# Create the cluster issuer
echo "Creating cluster issuer..."
kubectl apply -f nginx-cluster-issuer.yml
