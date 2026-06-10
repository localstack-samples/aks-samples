#!/bin/bash

# Variables
namespace="starwars"

# Connect to pods and try to land
kubectl exec mediabot -n $namespace -- curl -I -s --connect-timeout 3 --max-time 5 https://api.github.com | head -1 # The api.github.com url does not exist
kubectl exec mediabot -n $namespace -- curl -I -s --connect-timeout 3 --max-time 5 http://api.github.com | head -1 # This call fails as the network policy allows only HTTPS traffic on port 443
kubectl exec mediabot -n $namespace -- curl -I -s --connect-timeout 3 --max-time 5 https://github.com | head -1 # This call is not allowed by the policy because the DNS whitelist does not contain github.com, only *.github.com
