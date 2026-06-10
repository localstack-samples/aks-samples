#!/bin/bash

# Variables
namespace="starwars"
template="dns-pattern.yaml"

# Create L3\L4 rule
kubectl apply -n $namespace -f $template
