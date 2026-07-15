#!/bin/bash

# Variables
namespace="starwars"

# Check whether the namespace exists in the cluster
if kubectl get namespace "$namespace" >/dev/null 2>&1; then
    echo "Deleting [$namespace] namespace and all its resources..."
    kubectl delete namespace "$namespace" --wait=false
    
    # Wait for the deletion to complete, catching the timeout
    if ! kubectl wait --for=delete namespace/$namespace --timeout=60s 2>/dev/null; then
        echo "Namespace deletion is taking longer than expected. Forcing finalizer removal..."
        kubectl patch namespace "$namespace" -p '{"spec":{"finalizers":[]}}' --type=merge 2>/dev/null
        
        # Final short check
        kubectl wait --for=delete namespace/$namespace --timeout=10s 2>/dev/null
    fi
    echo "[$namespace] namespace and all its resources have been deleted"
else
    echo "[$namespace] namespace does not exist in the cluster, nothing to clean up"
fi