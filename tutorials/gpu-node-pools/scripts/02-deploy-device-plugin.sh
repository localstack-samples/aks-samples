#!/bin/bash

# Step 2: deploy the NVIDIA device plugin DaemonSet. AKS installs the NVIDIA driver on the nodes of the GPU pool, and the
# plugin advertises their GPUs to Kubernetes as nvidia.com/gpu: until it runs on a node, the scheduler sees no GPU
# there. The DaemonSet selects the nodes AKS labels accelerator=nvidia and tolerates the GPU pool's taints, so it
# starts on each GPU node the cluster autoscaler adds. The GPU pool has no node yet, so it schedules no pod for now.
# https://learn.microsoft.com/en-us/azure/aks/use-nvidia-gpu#manually-install-the-nvidia-device-plugin

# Variables
source ./00-variables.sh

# Create the namespace if it does not already exist
if kubectl get namespace "$DEVICE_PLUGIN_NAMESPACE" &>/dev/null; then
  echo "The [$DEVICE_PLUGIN_NAMESPACE] namespace already exists"
else
  echo "Creating the [$DEVICE_PLUGIN_NAMESPACE] namespace..."
  if ! kubectl create namespace "$DEVICE_PLUGIN_NAMESPACE"; then
    echo "Failed to create the [$DEVICE_PLUGIN_NAMESPACE] namespace"
    exit 1
  fi
fi

# Deploy the DaemonSet
echo "Deploying the [$DEVICE_PLUGIN_NAME] DaemonSet with image [$DEVICE_PLUGIN_IMAGE] to the [$DEVICE_PLUGIN_NAMESPACE] namespace..."
cat nvidia-device-plugin.yml |
  yq "(.metadata.name)|=\"$DEVICE_PLUGIN_NAME\"" |
  yq "(.metadata.namespace)|=\"$DEVICE_PLUGIN_NAMESPACE\"" |
  yq "(.spec.template.spec.containers[0].image)|=\"$DEVICE_PLUGIN_IMAGE\"" |
  yq "(.spec.template.spec.tolerations[0].key)|=\"$GPU_NODE_TAINT_KEY\"" |
  yq "(.spec.template.spec.tolerations[0].value)|=\"$GPU_NODE_TAINT_VALUE\"" |
  yq "(.spec.template.spec.tolerations[1].key)|=\"$SPOT_KEY\"" |
  yq "(.spec.template.spec.tolerations[1].value)|=\"$SPOT_VALUE\"" |
  kubectl apply -f -
if [[ $? -ne 0 ]]; then
  echo "Failed to deploy the [$DEVICE_PLUGIN_NAME] DaemonSet"
  exit 1
fi

kubectl get daemonset "$DEVICE_PLUGIN_NAME" --namespace "$DEVICE_PLUGIN_NAMESPACE"
