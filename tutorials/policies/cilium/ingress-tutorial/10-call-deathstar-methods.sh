#!/bin/bash

# Variables
namespace="starwars"

# Connect to pods and try to land. The first call should succeed, while the second one should be blocked by Cilium's L7 policy.
echo "Calling /v1/request-landing and /v1/exhaust-port from the tiefighter pod..."
kubectl exec tiefighter -n $namespace -- curl -s -XPOST --connect-timeout 3 --max-time 3 deathstar.$namespace.svc.cluster.local/v1/request-landing
echo "Calling /v1/exhaust-port from the tiefighter pod..."
kubectl exec tiefighter -n $namespace -- curl -s -XPUT --connect-timeout 3 --max-time 3 deathstar.$namespace.svc.cluster.local/v1/exhaust-port

# The following calls should timeout, as the xwing pod is not allowed to access the deathstar service.
echo "Calling /v1/request-landing and /v1/exhaust-port from the xwing pod..."
kubectl exec xwing -n $namespace -- curl -s -XPOST --connect-timeout 3 --max-time 3 deathstar.$namespace.svc.cluster.local/v1/request-landing
echo "Calling /v1/exhaust-port from the xwing pod..."
kubectl exec xwing -n $namespace -- curl -s -XPUT --connect-timeout 3 --max-time 3 deathstar.$namespace.svc.cluster.local/v1/exhaust-port