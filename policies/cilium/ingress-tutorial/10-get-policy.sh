#!/bin/bash

# Variables
namespace="starwars"
policy="rule1"

# Describe Cilium network policy
kubectl get cnp -n $namespace $policy -o yaml
