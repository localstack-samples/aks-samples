#!/bin/bash

# Variables
namespace="starwars"
template="dns-port.yaml"

# Create L3\L4 rule
kubectl apply -n $namespace -f $template
