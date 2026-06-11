#!/bin/bash

# Variables
namespace="starwars"

# Connect to pods and try to land
kubectl exec tiefighter -n $namespace -- curl -s -XPUT --connect-timeout 3 --max-time 3 deathstar.$namespace.svc.cluster.local/v1/exhaust-port
kubectl exec xwing -n $namespace -- curl -s -XPUT --connect-timeout 3 --max-time 3 deathstar.$namespace.svc.cluster.local/v1/exhaust-port
