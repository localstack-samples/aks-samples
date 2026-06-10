#!/bin/bash

# Variables
namespace="starwars"

# Connect to pods and try to land. The first call should succeed, while the second one should be blocked by Cilium's L7 policy.
kubectl exec tiefighter -n $namespace -- curl -s -XPOST deathstar.$namespace.svc.cluster.local/v1/request-landing
kubectl exec tiefighter -n $namespace -- curl -s -XPUT deathstar.$namespace.svc.cluster.local/v1/exhaust-port

# The following calls should timeout, as the xwing pod is not allowed to access the deathstar service.
kubectl exec xwing -n $namespace -- curl -s -XPOST --connect-timeout 3 deathstar.$namespace.svc.cluster.local/v1/request-landing
kubectl exec xwing -n $namespace -- curl -s -XPUT --connect-timeout 3 deathstar.$namespace.svc.cluster.local/v1/exhaust-port