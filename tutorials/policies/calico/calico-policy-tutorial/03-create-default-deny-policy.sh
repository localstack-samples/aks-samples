#!/bin/bash

# For more information, see:
# https://docs.tigera.io/calico/latest/network-policy/get-started/calico-policy/calico-policy-tutorial

# Variables
template="default-deny.yaml"

# Apply the default-deny GlobalNetworkPolicy to lock down all ingress and egress
# traffic for every namespace except kube-system, calico-system and calico-apiserver.
# GlobalNetworkPolicy is a Calico v3 resource, so it is applied with calicoctl.
calicoctl apply --allow-version-mismatch -f $template 2>/dev/null
