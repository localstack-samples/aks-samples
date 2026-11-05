#!/bin/bash

# Step 7: delete what this tutorial created: the training job's namespace, the device plugin's namespace, the GPU node
# pool, the Service Bus namespace with the identity's role on it, and the identity's federation with the training job.
# The managed identity, its federation with the KEDA operator and the operator's binding to it are left in place for
# the KEDA tutorials, which share them.

# Variables
source ./00-variables.sh

for KUBERNETES_NAMESPACE in "$NAMESPACE" "$DEVICE_PLUGIN_NAMESPACE"; do
  echo "Deleting the [$KUBERNETES_NAMESPACE] namespace..."
  if ! kubectl delete namespace "$KUBERNETES_NAMESPACE" --ignore-not-found --wait=true --timeout=600s; then
    echo "Failed to delete the [$KUBERNETES_NAMESPACE] namespace"
    exit 1
  fi
done

if az identity federated-credential show \
  --name "$FEDERATED_IDENTITY_NAME_JOB" \
  --identity-name "$MANAGED_IDENTITY_NAME" \
  --resource-group "$AKS_RESOURCE_GROUP_NAME" \
  --only-show-errors &>/dev/null; then
  echo "Deleting the [$FEDERATED_IDENTITY_NAME_JOB] federated identity credential of the [$MANAGED_IDENTITY_NAME] managed identity..."
  if ! az identity federated-credential delete \
    --name "$FEDERATED_IDENTITY_NAME_JOB" \
    --identity-name "$MANAGED_IDENTITY_NAME" \
    --resource-group "$AKS_RESOURCE_GROUP_NAME" \
    --yes \
    --only-show-errors; then
    echo "Failed to delete the [$FEDERATED_IDENTITY_NAME_JOB] federated identity credential"
    exit 1
  fi
else
  echo "The [$FEDERATED_IDENTITY_NAME_JOB] federated identity credential does not exist"
fi

SERVICE_BUS_NAMESPACE_ID=$(az servicebus namespace show \
  --name "$SERVICE_BUS_NAMESPACE_NAME" \
  --resource-group "$AKS_RESOURCE_GROUP_NAME" \
  --query id \
  --output tsv \
  --only-show-errors 2>/dev/null | tr -d '\r')
if [[ -n $SERVICE_BUS_NAMESPACE_ID ]]; then
  MANAGED_IDENTITY_PRINCIPAL_ID=$(az identity show \
    --name "$MANAGED_IDENTITY_NAME" \
    --resource-group "$AKS_RESOURCE_GROUP_NAME" \
    --query principalId \
    --output tsv \
    --only-show-errors 2>/dev/null | tr -d '\r')
  if [[ -n $MANAGED_IDENTITY_PRINCIPAL_ID ]]; then
    echo "Removing the [$ROLE] role of the [$MANAGED_IDENTITY_NAME] managed identity on the [$SERVICE_BUS_NAMESPACE_NAME] namespace..."
    if ! az role assignment delete \
      --assignee "$MANAGED_IDENTITY_PRINCIPAL_ID" \
      --role "$ROLE" \
      --scope "$SERVICE_BUS_NAMESPACE_ID" \
      --only-show-errors; then
      echo "Failed to remove the [$ROLE] role of the [$MANAGED_IDENTITY_NAME] managed identity"
      exit 1
    fi
  fi
  echo "Deleting the [$SERVICE_BUS_NAMESPACE_NAME] Service Bus namespace..."
  if ! az servicebus namespace delete \
    --name "$SERVICE_BUS_NAMESPACE_NAME" \
    --resource-group "$AKS_RESOURCE_GROUP_NAME" \
    --only-show-errors; then
    echo "Failed to delete the [$SERVICE_BUS_NAMESPACE_NAME] Service Bus namespace"
    exit 1
  fi
else
  echo "The [$SERVICE_BUS_NAMESPACE_NAME] Service Bus namespace does not exist"
fi

if az aks nodepool show \
  --name "$GPU_NODE_POOL_NAME" \
  --cluster-name "$AKS_NAME" \
  --resource-group "$AKS_RESOURCE_GROUP_NAME" \
  --only-show-errors &>/dev/null; then
  echo "Deleting the [$GPU_NODE_POOL_NAME] node pool of the [$AKS_NAME] AKS cluster..."
  if ! az aks nodepool delete \
    --name "$GPU_NODE_POOL_NAME" \
    --cluster-name "$AKS_NAME" \
    --resource-group "$AKS_RESOURCE_GROUP_NAME" \
    --only-show-errors; then
    echo "Failed to delete the [$GPU_NODE_POOL_NAME] node pool"
    exit 1
  fi
else
  echo "The [$GPU_NODE_POOL_NAME] node pool does not exist"
fi
echo "Cleanup complete"
