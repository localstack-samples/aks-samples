#!/bin/bash

# Variables
namespace="starwars"

# Connect to pods and try to land
echo "Calling https://api.github.com from mediabot pod..."
kubectl exec mediabot -n $namespace -- curl -I -s --connect-timeout 3 --max-time 5 https://api.github.com | head -1 # This call should succeed as no network policy is applied yet
echo "Calling http://api.github.com from mediabot pod..."
kubectl exec mediabot -n $namespace -- curl -I -s --connect-timeout 3 --max-time 5 http://api.github.com | head -1 # This call should succeed as no network policy is applied yet and HTTP is redirected to HTTPS
echo "Calling https://status.github.com from mediabot pod..."
kubectl exec mediabot -n $namespace -- curl -I -s --connect-timeout 3 --max-time 5 https://status.github.com | head -1 # This call should succeed as no network policy is applied yet
echo "Calling https://github.com from mediabot pod..."
kubectl exec mediabot -n $namespace -- curl -I -s --connect-timeout 3 --max-time 5 https://github.com | head -1 # This call should succeed as no network policy is applied yet