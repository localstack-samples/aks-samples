#!/bin/bash

# For more information, see:
# https://docs.tigera.io/calico/latest/network-policy/get-started/calico-policy/calico-policy-tutorial

# Variables
template="allow-busybox-egress.yaml"

# Apply a namespaced Calico NetworkPolicy that allows all egress traffic from the
# busybox "access" pod (run=access), overriding the default-deny for egress on
# that pod. Applied with calicoctl because it is a projectcalico.org/v3 resource.
calicoctl apply --allow-version-mismatch -f $template 2>/dev/null
