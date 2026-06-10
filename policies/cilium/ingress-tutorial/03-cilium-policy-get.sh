#!/bin/bash

# Each pod is represented in Cilium as an Endpoint. We can invoke the cilium tool inside the Cilium agent pod to list them.
# Cilium uses an daemonset to run an agent pod on every cluster node.
string=$(kubectl get pods -n kube-system -l k8s-app=cilium -o name | awk -F "/" '{print $2}')
pods=($string)
kubectl -n kube-system exec ${pods[0]} -c cilium-agent -- cilium policy get
