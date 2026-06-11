#!/bin/bash

# For more information, see:
# https://docs.cilium.io/en/latest/security/tutorial-toc/
# https://docs.cilium.io/en/latest/security/dns/
# https://docs.cilium.io/en/latest/security/policy/#id1
# https://cilium.io/blog/2017/5/4/demo-may-the-force-be-with-you/

# Variables
namespace="starwars"
template="dns-sw-app.yaml"

# Check if the namespace already exists in the cluster
result=$(kubectl get namespace -o 'jsonpath={.items[?(@.metadata.name=="'$namespace'")].metadata.name'})

if [[ -n $result ]]; then
    echo "[$namespace] namespace already exists in the cluster"
else
    # Create the namespace for your ingress resources
    echo "[$namespace] namespace does not exist in the cluster"
    echo "Creating [$namespace] namespace in the cluster..."
    kubectl create namespace $namespace
fi

# Deploy the demo
kubectl apply -n $namespace -f $template

# Wait for the pod to be ready before running the connectivity checks
echo "Waiting for the mediabot pod to be ready..."
kubectl wait --namespace $namespace --for=condition=Ready pod/mediabot --timeout=120s

# Check the status of the pods and services
kubectl get pods,svc -n $namespace
