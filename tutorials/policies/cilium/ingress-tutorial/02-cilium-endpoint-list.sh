#!/bin/bash

# Variables
namespace="starwars"
labels="class=deathstar"

# Get an array containing the nodes running a pod replica of the deathstar deployment
string=$(kubectl get pod -l $labels -n $namespace -o custom-columns=NODE:.spec.nodeName | grep -i -v node)
nodes=($string)

for node in ${nodes[@]}; do
    pod=$(kubectl get pods -n kube-system -l k8s-app=cilium -o name --field-selector spec.nodeName=$node | awk -F "/" '{print $2}')
    echo "Pod: $pod Node: $node"
    kubectl -n kube-system exec $pod -c cilium-agent -- cilium endpoint list
done
