#!/bin/bash

# For more information, see:
# https://docs.tigera.io/calico/latest/network-policy/get-started/calico-policy/calico-policy-tutorial

# Variables
namespace="advanced-policy-demo"

# Delete the namespaced Calico NetworkPolicies
calicoctl delete networkpolicy allow-busybox-egress -n $namespace
calicoctl delete networkpolicy allow-nginx-ingress -n $namespace

# Delete the global default-deny policy (gnp is the short name for GlobalNetworkPolicy)
calicoctl delete gnp default-deny

# Delete the demo namespace and all the workloads it contains
kubectl delete ns $namespace
