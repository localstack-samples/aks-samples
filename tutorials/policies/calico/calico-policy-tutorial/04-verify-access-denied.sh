#!/bin/bash

# For more information, see:
# https://docs.tigera.io/calico/latest/network-policy/get-started/calico-policy/calico-policy-tutorial

# With the default-deny GlobalNetworkPolicy in place, all traffic that is not
# explicitly allowed is now blocked. From the "access" pod neither the NGINX
# service nor the public internet should be reachable.
#
# DNS resolution itself is blocked too, so name lookups fail with "bad address"
# rather than a timeout.

# Variables
namespace="advanced-policy-demo"

# Access the NGINX service by name. Expected: wget: bad address 'nginx'
echo "Testing access -> nginx (expected: bad address 'nginx')"
kubectl exec -n $namespace access -- wget -q --timeout=5 nginx -O - | head -5

# Access the public internet. Expected: wget: bad address 'google.com'
echo "Testing access -> google.com (expected: bad address 'google.com')"
kubectl exec -n $namespace access -- wget -q --timeout=5 google.com -O - | head -5
