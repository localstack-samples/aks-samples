#!/bin/bash

# Step 3: create (or reuse) the Azure Service Bus namespace and queue this tutorial scales on, and
# grant the shared managed identity the role the KEDA operator needs to read the queue's message
# count. The role assignment is made on the identity's principal (object) id, which is what Azure
# authorizes; the client id is only used for authentication.
# https://learn.microsoft.com/en-us/azure/aks/keda-workload-identity

# Variables
source ./00-variables.sh

# Get or create the Service Bus namespace
echo "Checking if the [$SERVICE_BUS_NAMESPACE_NAME] Service Bus namespace exists in the [$AKS_RESOURCE_GROUP_NAME] resource group..."
az servicebus namespace show \
  --name $SERVICE_BUS_NAMESPACE_NAME \
  --resource-group $AKS_RESOURCE_GROUP_NAME \
  --only-show-errors &>/dev/null

if [[ $? -ne 0 ]]; then
  echo "No [$SERVICE_BUS_NAMESPACE_NAME] Service Bus namespace exists in the [$AKS_RESOURCE_GROUP_NAME] resource group"
  echo "Creating the [$SERVICE_BUS_NAMESPACE_NAME] Service Bus namespace..."

  az servicebus namespace create \
    --name $SERVICE_BUS_NAMESPACE_NAME \
    --resource-group $AKS_RESOURCE_GROUP_NAME \
    --location $LOCATION \
    --sku $SERVICE_BUS_SKU \
    --only-show-errors 1>/dev/null

  if [[ $? -eq 0 ]]; then
    echo "The [$SERVICE_BUS_NAMESPACE_NAME] Service Bus namespace was successfully created"
  else
    echo "Failed to create the [$SERVICE_BUS_NAMESPACE_NAME] Service Bus namespace"
    exit 1
  fi
else
  echo "The [$SERVICE_BUS_NAMESPACE_NAME] Service Bus namespace already exists"
fi

# Get or create the queue the producer fills and the consumer drains
echo "Checking if the [$SERVICE_BUS_QUEUE_NAME] queue exists in the [$SERVICE_BUS_NAMESPACE_NAME] Service Bus namespace..."
az servicebus queue show \
  --name $SERVICE_BUS_QUEUE_NAME \
  --namespace-name $SERVICE_BUS_NAMESPACE_NAME \
  --resource-group $AKS_RESOURCE_GROUP_NAME \
  --only-show-errors &>/dev/null

if [[ $? -ne 0 ]]; then
  echo "No [$SERVICE_BUS_QUEUE_NAME] queue exists in the [$SERVICE_BUS_NAMESPACE_NAME] Service Bus namespace"
  echo "Creating the [$SERVICE_BUS_QUEUE_NAME] queue..."

  az servicebus queue create \
    --name $SERVICE_BUS_QUEUE_NAME \
    --namespace-name $SERVICE_BUS_NAMESPACE_NAME \
    --resource-group $AKS_RESOURCE_GROUP_NAME \
    --only-show-errors 1>/dev/null

  if [[ $? -eq 0 ]]; then
    echo "The [$SERVICE_BUS_QUEUE_NAME] queue was successfully created"
  else
    echo "Failed to create the [$SERVICE_BUS_QUEUE_NAME] queue"
    exit 1
  fi
else
  echo "The [$SERVICE_BUS_QUEUE_NAME] queue already exists"
fi

# Retrieve the resource id of the namespace, the scope of the role assignment
SERVICE_BUS_NAMESPACE_ID=$(az servicebus namespace show \
  --name $SERVICE_BUS_NAMESPACE_NAME \
  --resource-group $AKS_RESOURCE_GROUP_NAME \
  --query id \
  --output tsv \
  --only-show-errors 2>/dev/null)
if [[ -z $SERVICE_BUS_NAMESPACE_ID ]]; then
  echo "Failed to retrieve the resource id of the [$SERVICE_BUS_NAMESPACE_NAME] Service Bus namespace"
  exit 1
fi

# Retrieve the principal id of the shared managed identity, created by 02-create-managed-identity.sh
MANAGED_IDENTITY_PRINCIPAL_ID=$(az identity show \
  --name $MANAGED_IDENTITY_NAME \
  --resource-group $AKS_RESOURCE_GROUP_NAME \
  --query principalId \
  --output tsv \
  --only-show-errors 2>/dev/null)
if [[ -z $MANAGED_IDENTITY_PRINCIPAL_ID ]]; then
  echo "Failed to retrieve the principal id of the [$MANAGED_IDENTITY_NAME] managed identity"
  echo "Run 02-create-managed-identity.sh first"
  exit 1
fi

# Assign the role only if it is not assigned yet
echo "Checking if the [$MANAGED_IDENTITY_NAME] managed identity has the [$ROLE] role on the [$SERVICE_BUS_NAMESPACE_NAME] Service Bus namespace..."
ROLE_ASSIGNMENT=$(az role assignment list \
  --assignee $MANAGED_IDENTITY_PRINCIPAL_ID \
  --scope $SERVICE_BUS_NAMESPACE_ID \
  --query "[?roleDefinitionName=='$ROLE'].roleDefinitionName" \
  --output tsv \
  --only-show-errors 2>/dev/null)

if [[ -n $ROLE_ASSIGNMENT ]]; then
  echo "The [$MANAGED_IDENTITY_NAME] managed identity already has the [$ROLE] role on the [$SERVICE_BUS_NAMESPACE_NAME] Service Bus namespace"
else
  echo "Assigning the [$ROLE] role to the [$MANAGED_IDENTITY_NAME] managed identity on the [$SERVICE_BUS_NAMESPACE_NAME] Service Bus namespace..."

  # A freshly created identity may not be visible to the role-assignment API yet, hence the retries
  for i in $(seq 1 $RETRY_COUNT); do
    az role assignment create \
      --role "$ROLE" \
      --assignee-object-id $MANAGED_IDENTITY_PRINCIPAL_ID \
      --assignee-principal-type ServicePrincipal \
      --scope $SERVICE_BUS_NAMESPACE_ID \
      --only-show-errors 1>/dev/null

    if [[ $? -eq 0 ]]; then
      echo "The [$ROLE] role was successfully assigned to the [$MANAGED_IDENTITY_NAME] managed identity"
      break
    fi

    if [[ $i -eq $RETRY_COUNT ]]; then
      echo "Failed to assign the [$ROLE] role to the [$MANAGED_IDENTITY_NAME] managed identity"
      exit 1
    fi

    echo "Attempt [$i] of [$RETRY_COUNT] failed, retrying in [$SLEEP] seconds..."
    sleep $SLEEP
  done
fi

# Print all the resources in the resource group, so the user can see what was created and what already existed
echo "The [$AKS_RESOURCE_GROUP_NAME] resource group contains the following resources:"
az resource list \
	--resource-group $AKS_RESOURCE_GROUP_NAME \
	--output table

# Print all the queues in the namespace, so the user can see what was created and what already existed
echo "The [$SERVICE_BUS_NAMESPACE_NAME] Service Bus namespace contains the following queues:"
az servicebus queue list \
	--namespace-name $SERVICE_BUS_NAMESPACE_NAME \
	--resource-group $AKS_RESOURCE_GROUP_NAME \
	--output table \
	--query "[].{Name:name,MessageCount:messageCount,Location:location,MaxDeliveryCount:maxDeliveryCount}" \
	--only-show-errors