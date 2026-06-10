#!/bin/bash

# For more information, see:
# https://docs.tigera.io/calico/latest/network-policy/get-started/calico-policy/calico-policy-tutorial

# Egress from the "access" pod is now allowed, so the public internet is reachable.
# However the NGINX service is still NOT reachable: although egress from "access"
# is permitted, the default-deny still blocks ingress to the NGINX pod (which we
# open up in the next step).

# Variables
namespace="advanced-policy-demo"

# Access the public internet. Expected: google.com home page HTML (ALLOWED).
echo "Testing access -> google.com (expected: ALLOWED)"
kubectl exec -n $namespace access -- wget -q --timeout=5 google.com -O - | head -5

# Access the NGINX service. Expected: wget: download timed out (ingress still denied).
echo "Testing access -> nginx (expected: DENIED - ingress to nginx not yet allowed)"
kubectl exec -n $namespace access -- wget -q --timeout=5 nginx -O - | head -5
