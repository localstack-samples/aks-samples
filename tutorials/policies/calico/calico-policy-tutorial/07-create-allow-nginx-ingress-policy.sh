#!/bin/bash

# For more information, see:
# https://docs.tigera.io/calico/latest/network-policy/get-started/calico-policy/calico-policy-tutorial

# Variables
template="allow-nginx-ingress.yaml"

# Apply a namespaced Calico NetworkPolicy that allows ingress to the NGINX pods
# (app=nginx) from the "access" pod (run=access). Applied with calicoctl because
# it is a projectcalico.org/v3 resource.
calicoctl apply --allow-version-mismatch -f $template 2>/dev/null
