#!/bin/bash

# For more information, see:
# https://docs.tigera.io/calico/latest/network-policy/get-started/calico-policy/calico-policy-tutorial

# Before any policy is applied, all ingress and egress traffic is allowed.
# From the "access" pod both the in-cluster NGINX service and the public internet
# (google.com) should be reachable.

# Variables
namespace="advanced-policy-demo"

# Access the NGINX service by name (in-cluster). Expected: NGINX welcome page HTML.
echo "Testing access -> nginx (expected: ALLOWED)"
kubectl exec -n $namespace access -- wget -q --timeout=5 nginx -O - | head -5

# Access the public internet. Expected: google.com home page HTML.
echo "Testing access -> google.com (expected: ALLOWED)"
kubectl exec -n $namespace access -- wget -q --timeout=5 google.com -O - | head -5
