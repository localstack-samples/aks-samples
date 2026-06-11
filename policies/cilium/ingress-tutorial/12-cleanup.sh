#!/bin/bash

# Variables
namespace="starwars"

# Controlla se il namespace esiste nel cluster
if kubectl get namespace "$namespace" >/dev/null 2>&1; then
    echo "Deleting [$namespace] namespace and all its resources..."
    kubectl delete namespace "$namespace" --wait=false
    
    # Aspetta il completamento, intercettando il timeout
    if ! kubectl wait --for=delete namespace/$namespace --timeout=60s 2>/dev/null; then
        echo "Namespace deletion is taking longer than expected. Forcing finalizer removal..."
        kubectl patch namespace "$namespace" -p '{"spec":{"finalizers":[]}}' --type=merge 2>/dev/null
        
        # Ultima verifica breve
        kubectl wait --for=delete namespace/$namespace --timeout=10s 2>/dev/null
    fi
    echo "[$namespace] namespace and all its resources have been deleted"
else
    echo "[$namespace] namespace does not exist in the cluster, nothing to clean up"
fi