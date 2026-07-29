#!/bin/bash

# Step 9: remove what this tutorial created in the cluster: the namespace with the consumer, the
# producer Job, the application service account and the KEDA resources. Pass --disable-keda to also
# turn the add-on off on the cluster (az aks update --disable-keda), which removes the KEDA components
# and CRDs.
#
# The shared managed identity, its two federated credentials, its role assignments and the
# keda-operator annotation are left in place on purpose: the other two KEDA tutorials use the identity
# and the operator binding. Delete the Azure resources with `az group delete --name local-rg` when you
# are done with all of them.

# Variables
source ./00-variables.sh

# Merge the cluster credentials into kubeconfig and set it as the current context
az aks get-credentials \
  --name $AKS_NAME \
  --resource-group $AKS_RESOURCE_GROUP_NAME \
  --overwrite-existing \
  --only-show-errors 1>/dev/null

# Delete the namespace, and with it the deployment, job, service account, config map, and KEDA resources
if kubectl get namespace $NAMESPACE &>/dev/null; then
  echo "Deleting the [$NAMESPACE] namespace..."
  kubectl delete namespace $NAMESPACE --ignore-not-found --wait=true
  if [[ $? -eq 0 ]]; then
    echo "The [$NAMESPACE] namespace was successfully deleted"
  else
    echo "Failed to delete the [$NAMESPACE] namespace"
    exit 1
  fi
else
  echo "The [$NAMESPACE] namespace does not exist"
fi

# Optionally disable the add-on
if [[ "$1" == "--disable-keda" ]]; then
  echo "Disabling the KEDA add-on on the [$AKS_NAME] AKS cluster..."
  az aks update \
    --name $AKS_NAME \
    --resource-group $AKS_RESOURCE_GROUP_NAME \
    --disable-keda \
    --only-show-errors 1>/dev/null
  if [[ $? -eq 0 ]]; then
    echo "The KEDA add-on was successfully disabled on the [$AKS_NAME] AKS cluster"
  else
    echo "Failed to disable the KEDA add-on on the [$AKS_NAME] AKS cluster"
    exit 1
  fi
else
  echo "Leaving the KEDA add-on enabled (pass --disable-keda to remove it)"
fi

echo "Cleanup complete"
