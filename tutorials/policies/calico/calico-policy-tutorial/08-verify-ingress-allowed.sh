#!/bin/bash

# For more information, see:
# https://docs.tigera.io/calico/latest/network-policy/get-started/calico-policy/calico-policy-tutorial

# Both policies are now in place: egress from "access" is allowed and ingress to
# NGINX from "access" is allowed. The "access" pod can therefore reach both the
# NGINX service and the public internet, while all other traffic stays denied by
# the default-deny GlobalNetworkPolicy.

# Variables
namespace="advanced-policy-demo"

# Access the NGINX service. Expected: NGINX welcome page HTML (ALLOWED).
echo "Testing access -> nginx (expected: ALLOWED)"
kubectl exec -n $namespace access -- wget -q --timeout=5 nginx -O - | head -5

# Access the public internet. Expected: google.com home page HTML (ALLOWED).
echo "Testing access -> google.com (expected: ALLOWED)"
kubectl exec -n $namespace access -- wget -q --timeout=5 google.com -O - | head -5
