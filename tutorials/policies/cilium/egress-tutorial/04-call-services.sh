#!/bin/bash

# Variables
namespace="starwars"

# Connect to pods and try to land
echo "Calling https://api.github.com from mediabot pod..."
kubectl exec mediabot -n $namespace -- curl -I -s --connect-timeout 3 --max-time 5 https://api.github.com | head -1 # This call should succeed as api.github.com is allowed by the DNS whitelist
echo "Calling http://api.github.com from mediabot pod..."
kubectl exec mediabot -n $namespace -- curl -I -s --connect-timeout 3 --max-time 5 http://api.github.com | head -1 # This call should succeed as api.github.com is allowed by the DNS whitelist and HTTP is redirected to HTTPS
echo "Calling https://status.github.com from mediabot pod..."
kubectl exec mediabot -n $namespace -- curl -I -s --connect-timeout 3 --max-time 5 https://status.github.com | head -1 # This call should fails as status.github.com is not allowed by the DNS whitelist
echo "Calling https://github.com from mediabot pod..."
kubectl exec mediabot -n $namespace -- curl -I -s --connect-timeout 3 --max-time 5 https://github.com | head -1 # This call should fail as github.com is not allowed by the DNS whitelist