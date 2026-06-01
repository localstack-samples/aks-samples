#!/bin/bash

# Install the Gateway API CRDs from the official Kubernetes SIGs repository.
kubectl apply --server-side -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.5.1/standard-install.yaml