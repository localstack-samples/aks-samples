#!/bin/bash

# Variables
namespace="starwars"
labels="class=deathstar"

# Get an array containing the nodes running a pod replica of the deathstar deployment
string=$(kubectl get pod -l $labels -n $namespace -o custom-columns=NODE:.spec.nodeName | grep -i -v node)
nodes=($string)

# Prompt the user to select one of the nodes
echo "Please select a node to monitor between those running a pod replica of the deathstar deployment:"
select node in "${nodes[@]}"; do
    [[ -n $node ]] || {
        echo "Invalid node. Please try again." >&2
        continue
    }
    break # valid node was made; exit prompt.
done

echo "Monitoring node $node"
kubectl -n kube-system exec -it -c cilium-agent $(kubectl get pod -n kube-system -l k8s-app=cilium -o name --field-selector spec.nodeName=$node | awk -F "/" '{print $2}') -- cilium monitor -v --type l7
