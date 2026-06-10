#!/bin/bash

# Variables
namespace="starwars"
template="sw-l3-l4-policy.yaml"

# Create L3\L4 rule
kubectl apply -n $namespace -f $template
