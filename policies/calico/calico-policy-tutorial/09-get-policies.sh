#!/bin/bash

# For more information, see:
# https://docs.tigera.io/calico/latest/network-policy/get-started/calico-policy/calico-policy-tutorial

# Variables
namespace="advanced-policy-demo"

# List the global (non-namespaced) default-deny policy
echo "GlobalNetworkPolicy:"
calicoctl get globalnetworkpolicy -o wide

# List the namespaced Calico NetworkPolicies in the demo namespace
echo "NetworkPolicy in namespace [$namespace]:"
calicoctl get networkpolicy -n $namespace -o wide

# Show the full YAML definition of the default-deny global policy
echo "default-deny definition:"
calicoctl get globalnetworkpolicy default-deny -o yaml
