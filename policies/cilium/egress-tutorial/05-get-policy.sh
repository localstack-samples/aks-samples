#!/bin/bash

# Variables
namespace="starwars"
policy="fqdn"

# Describe Cilium network policy
kubectl get cnp -n $namespace $policy -o yaml
