#!/bin/bash

# Step 3: create (or reuse) the Azure resources this tutorial scales on: the Event Hubs namespace, the
# event hub with its consumer group and authorization rule, and the storage account and blob container
# that hold the consumer group's checkpoints.
#
# The container has to exist before the consumer ever starts: the checkpoint store does not create it,
# and without checkpoints the scaler's lag never falls, so the workload never scales back to zero.
#
# The two role assignments at the end are made on the shared managed identity's principal (object) id,
# which is what Azure authorizes; the client id is only used for authentication. They are NOT exercised
# by this tutorial, which authenticates the scaler and the applications with connection strings,
# because the emulator's AMQP listener is plain TCP and has no Microsoft Entra variant. They are what
# lets a reader running against real Azure switch the trigger over to workload identity by adding a
# TriggerAuthentication with podIdentity provider azure-workload, as the Service Bus tutorial does.
# https://learn.microsoft.com/en-us/azure/event-hubs/authenticate-application

# Variables
source ./00-variables.sh

# Idempotently assign a role to the shared managed identity on a scope. Called twice below, once for
# Event Hubs and once for storage.
assign_role() {
  local role=$1
  local scope=$2
  local scope_description=$3

  echo "Checking if the [$MANAGED_IDENTITY_NAME] managed identity has the [$role] role on $scope_description..."
  local role_assignment=$(az role assignment list \
    --assignee $MANAGED_IDENTITY_PRINCIPAL_ID \
    --scope $scope \
    --query "[?roleDefinitionName=='$role'].roleDefinitionName" \
    --output tsv \
    --only-show-errors 2>/dev/null)

  if [[ -n $role_assignment ]]; then
    echo "The [$MANAGED_IDENTITY_NAME] managed identity already has the [$role] role on $scope_description"
    return 0
  fi

  echo "Assigning the [$role] role to the [$MANAGED_IDENTITY_NAME] managed identity on $scope_description..."

  # A freshly created identity may not be visible to the role-assignment API yet, hence the retries
  local i
  for i in $(seq 1 $RETRY_COUNT); do
    az role assignment create \
      --role "$role" \
      --assignee-object-id $MANAGED_IDENTITY_PRINCIPAL_ID \
      --assignee-principal-type ServicePrincipal \
      --scope $scope \
      --only-show-errors 1>/dev/null

    if [[ $? -eq 0 ]]; then
      echo "The [$role] role was successfully assigned to the [$MANAGED_IDENTITY_NAME] managed identity"
      return 0
    fi

    if [[ $i -eq $RETRY_COUNT ]]; then
      echo "Failed to assign the [$role] role to the [$MANAGED_IDENTITY_NAME] managed identity"
      return 1
    fi

    echo "Attempt [$i] of [$RETRY_COUNT] failed, retrying in [$SLEEP] seconds..."
    sleep $SLEEP
  done

  # Only reachable when RETRY_COUNT is not a positive number, so no attempt was ever made
  echo "No role-assignment attempt was made, [RETRY_COUNT] is [$RETRY_COUNT]"
  return 1
}

# Get or create the Event Hubs namespace
echo "Checking if the [$EVENT_HUBS_NAMESPACE_NAME] Event Hubs namespace exists in the [$AKS_RESOURCE_GROUP_NAME] resource group..."
az eventhubs namespace show \
  --name $EVENT_HUBS_NAMESPACE_NAME \
  --resource-group $AKS_RESOURCE_GROUP_NAME \
  --only-show-errors &>/dev/null

if [[ $? -ne 0 ]]; then
  echo "No [$EVENT_HUBS_NAMESPACE_NAME] Event Hubs namespace exists in the [$AKS_RESOURCE_GROUP_NAME] resource group"
  echo "Creating the [$EVENT_HUBS_NAMESPACE_NAME] Event Hubs namespace..."

  az eventhubs namespace create \
    --name $EVENT_HUBS_NAMESPACE_NAME \
    --resource-group $AKS_RESOURCE_GROUP_NAME \
    --location $LOCATION \
    --sku $EVENT_HUBS_SKU \
    --only-show-errors 1>/dev/null

  if [[ $? -eq 0 ]]; then
    echo "The [$EVENT_HUBS_NAMESPACE_NAME] Event Hubs namespace was successfully created"
  else
    echo "Failed to create the [$EVENT_HUBS_NAMESPACE_NAME] Event Hubs namespace"
    exit 1
  fi
else
  echo "The [$EVENT_HUBS_NAMESPACE_NAME] Event Hubs namespace already exists"
fi

# Get or create the event hub the producer fills and the consumer reads
echo "Checking if the [$EVENT_HUB_NAME] event hub exists in the [$EVENT_HUBS_NAMESPACE_NAME] Event Hubs namespace..."
az eventhubs eventhub show \
  --name $EVENT_HUB_NAME \
  --namespace-name $EVENT_HUBS_NAMESPACE_NAME \
  --resource-group $AKS_RESOURCE_GROUP_NAME \
  --only-show-errors &>/dev/null

if [[ $? -ne 0 ]]; then
  echo "No [$EVENT_HUB_NAME] event hub exists in the [$EVENT_HUBS_NAMESPACE_NAME] Event Hubs namespace"
  echo "Creating the [$EVENT_HUB_NAME] event hub with [$EVENT_HUB_PARTITION_COUNT] partitions..."

  az eventhubs eventhub create \
    --name $EVENT_HUB_NAME \
    --namespace-name $EVENT_HUBS_NAMESPACE_NAME \
    --resource-group $AKS_RESOURCE_GROUP_NAME \
    --partition-count $EVENT_HUB_PARTITION_COUNT \
    --only-show-errors 1>/dev/null

  if [[ $? -eq 0 ]]; then
    echo "The [$EVENT_HUB_NAME] event hub was successfully created"
  else
    echo "Failed to create the [$EVENT_HUB_NAME] event hub"
    exit 1
  fi
else
  echo "The [$EVENT_HUB_NAME] event hub already exists"
fi

# Get or create the consumer group whose checkpoints the scaler reads
echo "Checking if the [$EVENT_HUB_CONSUMER_GROUP] consumer group exists in the [$EVENT_HUB_NAME] event hub..."
az eventhubs eventhub consumer-group show \
  --name $EVENT_HUB_CONSUMER_GROUP \
  --eventhub-name $EVENT_HUB_NAME \
  --namespace-name $EVENT_HUBS_NAMESPACE_NAME \
  --resource-group $AKS_RESOURCE_GROUP_NAME \
  --only-show-errors &>/dev/null

if [[ $? -ne 0 ]]; then
  echo "No [$EVENT_HUB_CONSUMER_GROUP] consumer group exists in the [$EVENT_HUB_NAME] event hub"
  echo "Creating the [$EVENT_HUB_CONSUMER_GROUP] consumer group..."

  az eventhubs eventhub consumer-group create \
    --name $EVENT_HUB_CONSUMER_GROUP \
    --eventhub-name $EVENT_HUB_NAME \
    --namespace-name $EVENT_HUBS_NAMESPACE_NAME \
    --resource-group $AKS_RESOURCE_GROUP_NAME \
    --only-show-errors 1>/dev/null

  if [[ $? -eq 0 ]]; then
    echo "The [$EVENT_HUB_CONSUMER_GROUP] consumer group was successfully created"
  else
    echo "Failed to create the [$EVENT_HUB_CONSUMER_GROUP] consumer group"
    exit 1
  fi
else
  echo "The [$EVENT_HUB_CONSUMER_GROUP] consumer group already exists"
fi

# Get or create the authorization rule whose connection string the scaler and the applications use.
# It is created on the event hub, so the connection string carries EntityPath=<hub>.
echo "Checking if the [$EVENT_HUB_AUTHORIZATION_RULE] authorization rule exists on the [$EVENT_HUB_NAME] event hub..."
az eventhubs eventhub authorization-rule show \
  --name $EVENT_HUB_AUTHORIZATION_RULE \
  --eventhub-name $EVENT_HUB_NAME \
  --namespace-name $EVENT_HUBS_NAMESPACE_NAME \
  --resource-group $AKS_RESOURCE_GROUP_NAME \
  --only-show-errors &>/dev/null

if [[ $? -ne 0 ]]; then
  echo "No [$EVENT_HUB_AUTHORIZATION_RULE] authorization rule exists on the [$EVENT_HUB_NAME] event hub"
  echo "Creating the [$EVENT_HUB_AUTHORIZATION_RULE] authorization rule..."

  az eventhubs eventhub authorization-rule create \
    --name $EVENT_HUB_AUTHORIZATION_RULE \
    --eventhub-name $EVENT_HUB_NAME \
    --namespace-name $EVENT_HUBS_NAMESPACE_NAME \
    --resource-group $AKS_RESOURCE_GROUP_NAME \
    --rights Listen Send Manage \
    --only-show-errors 1>/dev/null

  if [[ $? -eq 0 ]]; then
    echo "The [$EVENT_HUB_AUTHORIZATION_RULE] authorization rule was successfully created"
  else
    echo "Failed to create the [$EVENT_HUB_AUTHORIZATION_RULE] authorization rule"
    exit 1
  fi
else
  echo "The [$EVENT_HUB_AUTHORIZATION_RULE] authorization rule already exists"
fi

# Get or create the storage account that holds the checkpoints
echo "Checking if the [$STORAGE_ACCOUNT_NAME] storage account exists in the [$AKS_RESOURCE_GROUP_NAME] resource group..."
az storage account show \
  --name $STORAGE_ACCOUNT_NAME \
  --resource-group $AKS_RESOURCE_GROUP_NAME \
  --only-show-errors &>/dev/null

if [[ $? -ne 0 ]]; then
  echo "No [$STORAGE_ACCOUNT_NAME] storage account exists in the [$AKS_RESOURCE_GROUP_NAME] resource group"
  echo "Creating the [$STORAGE_ACCOUNT_NAME] storage account..."

  az storage account create \
    --name $STORAGE_ACCOUNT_NAME \
    --resource-group $AKS_RESOURCE_GROUP_NAME \
    --location $LOCATION \
    --sku $STORAGE_ACCOUNT_SKU \
    --kind $STORAGE_ACCOUNT_KIND \
    --only-show-errors 1>/dev/null

  if [[ $? -eq 0 ]]; then
    echo "The [$STORAGE_ACCOUNT_NAME] storage account was successfully created"
  else
    echo "Failed to create the [$STORAGE_ACCOUNT_NAME] storage account"
    exit 1
  fi
else
  echo "The [$STORAGE_ACCOUNT_NAME] storage account already exists"
fi

# Blob operations are data-plane calls and need a credential of their own, so the account key is read
# from the control plane and passed explicitly instead of relying on the logged-in principal.
STORAGE_ACCOUNT_KEY=$(az storage account keys list \
  --account-name $STORAGE_ACCOUNT_NAME \
  --resource-group $AKS_RESOURCE_GROUP_NAME \
  --query "[0].value" \
  --output tsv \
  --only-show-errors 2>/dev/null)
if [[ -z $STORAGE_ACCOUNT_KEY ]]; then
  echo "Failed to retrieve an access key of the [$STORAGE_ACCOUNT_NAME] storage account"
  exit 1
fi

# Get or create the container the consumer checkpoints into. az storage container exists succeeds even
# when the container is missing, so its result is read from the payload, not from the exit code.
echo "Checking if the [$CHECKPOINT_CONTAINER] container exists in the [$STORAGE_ACCOUNT_NAME] storage account..."
CONTAINER_EXISTS=$(az storage container exists \
  --name $CHECKPOINT_CONTAINER \
  --account-name $STORAGE_ACCOUNT_NAME \
  --account-key $STORAGE_ACCOUNT_KEY \
  --query exists \
  --output tsv \
  --only-show-errors 2>/dev/null)

if [[ "${CONTAINER_EXISTS,,}" == "true" ]]; then
  echo "The [$CHECKPOINT_CONTAINER] container already exists"
else
  echo "No [$CHECKPOINT_CONTAINER] container exists in the [$STORAGE_ACCOUNT_NAME] storage account"
  echo "Creating the [$CHECKPOINT_CONTAINER] container..."

  az storage container create \
    --name $CHECKPOINT_CONTAINER \
    --account-name $STORAGE_ACCOUNT_NAME \
    --account-key $STORAGE_ACCOUNT_KEY \
    --only-show-errors 1>/dev/null

  if [[ $? -eq 0 ]]; then
    echo "The [$CHECKPOINT_CONTAINER] container was successfully created"
  else
    echo "Failed to create the [$CHECKPOINT_CONTAINER] container"
    exit 1
  fi
fi

# Retrieve the resource ids of the two role-assignment scopes
EVENT_HUBS_NAMESPACE_ID=$(az eventhubs namespace show \
  --name $EVENT_HUBS_NAMESPACE_NAME \
  --resource-group $AKS_RESOURCE_GROUP_NAME \
  --query id \
  --output tsv \
  --only-show-errors 2>/dev/null)
if [[ -z $EVENT_HUBS_NAMESPACE_ID ]]; then
  echo "Failed to retrieve the resource id of the [$EVENT_HUBS_NAMESPACE_NAME] Event Hubs namespace"
  exit 1
fi

STORAGE_ACCOUNT_ID=$(az storage account show \
  --name $STORAGE_ACCOUNT_NAME \
  --resource-group $AKS_RESOURCE_GROUP_NAME \
  --query id \
  --output tsv \
  --only-show-errors 2>/dev/null)
if [[ -z $STORAGE_ACCOUNT_ID ]]; then
  echo "Failed to retrieve the resource id of the [$STORAGE_ACCOUNT_NAME] storage account"
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

# Grant the identity the Event Hubs data role on the namespace and the blob data role on the storage
# account, the two grants a workload-identity trigger would need on real Azure
assign_role "$EVENT_HUBS_ROLE" "$EVENT_HUBS_NAMESPACE_ID" "the [$EVENT_HUBS_NAMESPACE_NAME] Event Hubs namespace"
if [[ $? -ne 0 ]]; then
  exit 1
fi

assign_role "$STORAGE_ROLE" "$STORAGE_ACCOUNT_ID" "the [$STORAGE_ACCOUNT_NAME] storage account"
if [[ $? -ne 0 ]]; then
  exit 1
fi
