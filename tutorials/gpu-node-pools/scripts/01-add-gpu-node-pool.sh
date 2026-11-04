#!/bin/bash

# Step 1: make sure the cluster runs the KEDA add-on, merge its credentials into kubeconfig, and add a Spot GPU node
# pool that starts with no node and that the cluster autoscaler grows to one node when a pod asks for a GPU.
#
# The cluster-creation scripts already pass --enable-keda, --enable-oidc-issuer and --enable-workload-identity, so on
# such a cluster this script only adds the node pool. The pool's VM size and priority can't change after it is
# created, so an existing pool with other values stops the script rather than being reused.
# https://learn.microsoft.com/en-us/azure/aks/use-nvidia-gpu
# https://learn.microsoft.com/en-us/azure/aks/spot-node-pool

# Variables
source ./00-variables.sh

# Make sure the AKS cluster exists (it is created by scripts/01-user-assigned-managed-identity.sh)
OIDC_ISSUER_ENABLED=$(az aks show \
  --name "$AKS_NAME" \
  --resource-group "$AKS_RESOURCE_GROUP_NAME" \
  --query oidcIssuerProfile.enabled \
  --output tsv \
  --only-show-errors 2>/dev/null | tr -d '\r')
if [[ -z $OIDC_ISSUER_ENABLED ]]; then
  echo "The [$AKS_NAME] AKS cluster doesn't exist in the [$AKS_RESOURCE_GROUP_NAME] resource group"
  echo "Create the cluster first with scripts/01-user-assigned-managed-identity.sh"
  exit 1
fi
if [[ $OIDC_ISSUER_ENABLED != "true" ]]; then
  echo "The [$AKS_NAME] AKS cluster has no OIDC issuer, which workload identity needs"
  echo "Create the cluster with scripts/01-user-assigned-managed-identity.sh, which enables it"
  exit 1
fi

# Enable the KEDA add-on only if it is not enabled yet
echo "Checking if the KEDA add-on is enabled in the [$AKS_NAME] AKS cluster..."
KEDA_ENABLED=$(az aks show \
  --name "$AKS_NAME" \
  --resource-group "$AKS_RESOURCE_GROUP_NAME" \
  --query workloadAutoScalerProfile.keda.enabled \
  --output tsv \
  --only-show-errors 2>/dev/null | tr -d '\r')
if [[ $KEDA_ENABLED == "true" ]]; then
  echo "The KEDA add-on is already enabled in the [$AKS_NAME] AKS cluster"
else
  echo "Enabling the KEDA add-on in the [$AKS_NAME] AKS cluster..."
  if ! az aks update \
    --name "$AKS_NAME" \
    --resource-group "$AKS_RESOURCE_GROUP_NAME" \
    --enable-keda \
    --only-show-errors 1>/dev/null; then
    echo "Failed to enable the KEDA add-on in the [$AKS_NAME] AKS cluster"
    exit 1
  fi
  echo "The KEDA add-on was successfully enabled in the [$AKS_NAME] AKS cluster"
fi

# Merge the cluster credentials into kubeconfig and set it as the current context
echo "Merging credentials for the [$AKS_NAME] AKS cluster into kubeconfig..."
if ! az aks get-credentials \
  --name "$AKS_NAME" \
  --resource-group "$AKS_RESOURCE_GROUP_NAME" \
  --overwrite-existing \
  --only-show-errors; then
  echo "Failed to merge the credentials for the [$AKS_NAME] AKS cluster"
  exit 1
fi

# Add the Spot GPU node pool unless it exists
echo "Checking if the [$GPU_NODE_POOL_NAME] node pool exists in the [$AKS_NAME] AKS cluster..."
EXISTING_POOL=$(az aks nodepool show \
  --name "$GPU_NODE_POOL_NAME" \
  --cluster-name "$AKS_NAME" \
  --resource-group "$AKS_RESOURCE_GROUP_NAME" \
  --query "[vmSize, scaleSetPriority]" \
  --output tsv \
  --only-show-errors 2>/dev/null | tr -d '\r' | tr '\t\n' '  ')
if [[ -n $EXISTING_POOL ]]; then
  if [[ $EXISTING_POOL != "$GPU_NODE_VM_SIZE $GPU_NODE_PRIORITY " ]]; then
    echo "The [$GPU_NODE_POOL_NAME] node pool exists with VM size and priority [$EXISTING_POOL], not [$GPU_NODE_VM_SIZE $GPU_NODE_PRIORITY]"
    echo "Delete it with 07-cleanup.sh, or change GPU_NODE_POOL_NAME in 00-variables.sh"
    exit 1
  fi
  echo "The [$GPU_NODE_POOL_NAME] node pool already exists"
else
  echo "Adding the [$GPU_NODE_POOL_NAME] Spot node pool of [$GPU_NODE_VM_SIZE] VMs, with $GPU_NODE_MIN_COUNT to $GPU_NODE_MAX_COUNT nodes, to the [$AKS_NAME] AKS cluster..."
  if ! az aks nodepool add \
    --name "$GPU_NODE_POOL_NAME" \
    --cluster-name "$AKS_NAME" \
    --resource-group "$AKS_RESOURCE_GROUP_NAME" \
    --mode User \
    --node-vm-size "$GPU_NODE_VM_SIZE" \
    --os-sku "$GPU_NODE_OS_SKU" \
    --priority "$GPU_NODE_PRIORITY" \
    --eviction-policy "$GPU_NODE_EVICTION_POLICY" \
    --spot-max-price "$GPU_NODE_SPOT_MAX_PRICE" \
    --enable-cluster-autoscaler \
    --node-count "$GPU_NODE_MIN_COUNT" \
    --min-count "$GPU_NODE_MIN_COUNT" \
    --max-count "$GPU_NODE_MAX_COUNT" \
    --labels "$GPU_NODE_LABEL_KEY=$GPU_NODE_LABEL_VALUE" \
    --node-taints "$GPU_NODE_TAINT_KEY=$GPU_NODE_TAINT_VALUE:NoSchedule" \
    --only-show-errors 1>/dev/null; then
    echo "Failed to add the [$GPU_NODE_POOL_NAME] node pool to the [$AKS_NAME] AKS cluster"
    exit 1
  fi
  echo "The [$GPU_NODE_POOL_NAME] node pool was successfully added to the [$AKS_NAME] AKS cluster"
fi

# Print the node pool as AKS stores it: AKS adds the Spot label and taint, and reports the GPU driver it installs
az aks nodepool show \
  --name "$GPU_NODE_POOL_NAME" \
  --cluster-name "$AKS_NAME" \
  --resource-group "$AKS_RESOURCE_GROUP_NAME" \
  --query "{name: name, vmSize: vmSize, count: count, minCount: minCount, maxCount: maxCount, scaleSetPriority: scaleSetPriority, scaleSetEvictionPolicy: scaleSetEvictionPolicy, spotMaxPrice: spotMaxPrice, gpuProfile: gpuProfile, nodeLabels: nodeLabels, nodeTaints: nodeTaints}" \
  --output json \
  --only-show-errors
