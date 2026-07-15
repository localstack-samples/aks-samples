#!/bin/bash

# For more information, see:
# https://docs.tigera.io/calico/latest/network-policy/get-started/calico-policy/calico-policy-tutorial
# https://docs.tigera.io/calico/latest/network-policy/get-started/kubernetes-policy/kubernetes-policy-advanced

# Variables
namespace="advanced-policy-demo"
template="demo.yaml"

# Deploy the demo workloads (namespace, NGINX deployment + service, and the
# busybox "access" pod). The namespace is declared in the manifest itself.
kubectl apply -f $template

# Wait for the workloads to be ready before running the connectivity checks
kubectl wait --namespace $namespace --for=condition=Available deployment/nginx --timeout=120s
kubectl wait --namespace $namespace --for=condition=Ready pod/access --timeout=120s

# Check the status of the pods and services
kubectl get pods,svc -n $namespace
