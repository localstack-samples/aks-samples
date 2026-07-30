#!/bin/bash

# Step 3: create (or reuse) the Azure storage account and queue this tutorial scales on, and grant the
# shared managed identity the role that the KEDA scaler, the producer and the consumer all need. The
# role assignment is made on the identity's principal (object) id, which is what Azure authorizes; the
# client id is only used for authentication.
# https://learn.microsoft.com/en-us/azure/storage/queues/assign-azure-role-data-access

# Variables
source ./00-variables.sh

# Get or create the storage account
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

# Get or create the queue the producer fills and the consumer drains.
#
# A queue is a data-plane resource, so the az CLI has to authenticate to the queue endpoint rather than
# to ARM. Microsoft Entra (--auth-mode login) is tried first, which is the same way the applications and
# the KEDA scaler authenticate and what keeps this tutorial free of account keys. If the signed-in
# principal holds no data role on the account, or the target does not accept bearer tokens on the queue
# endpoint, the script falls back to an account key explicitly and says so, instead of ignoring the
# error. https://learn.microsoft.com/en-us/azure/storage/queues/authorize-data-operations-cli
#
# `az storage queue exists` returns true or false when the call is authorized and prints nothing when it
# is not, so the same probe reports both the authentication mode to use and whether the queue is there.
echo "Checking if the [$STORAGE_QUEUE_NAME] queue exists in the [$STORAGE_ACCOUNT_NAME] storage account..."
QUEUE_AUTHENTICATION=(--auth-mode login)
QUEUE_EXISTS=$(az storage queue exists \
  --name $STORAGE_QUEUE_NAME \
  --account-name $STORAGE_ACCOUNT_NAME \
  "${QUEUE_AUTHENTICATION[@]}" \
  --query exists \
  --output tsv \
  --only-show-errors 2>/dev/null)

if [[ -z $QUEUE_EXISTS ]]; then
  echo "Microsoft Entra authentication to the queue endpoint of the [$STORAGE_ACCOUNT_NAME] storage account did not work"
  echo "Falling back to an account key. Grant your own principal the [$ROLE] role on the storage account to avoid this."

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

  QUEUE_AUTHENTICATION=(--account-key "$STORAGE_ACCOUNT_KEY")
  QUEUE_EXISTS=$(az storage queue exists \
    --name $STORAGE_QUEUE_NAME \
    --account-name $STORAGE_ACCOUNT_NAME \
    "${QUEUE_AUTHENTICATION[@]}" \
    --query exists \
    --output tsv \
    --only-show-errors 2>/dev/null)
  if [[ -z $QUEUE_EXISTS ]]; then
    echo "Failed to determine whether the [$STORAGE_QUEUE_NAME] queue exists in the [$STORAGE_ACCOUNT_NAME] storage account"
    exit 1
  fi
fi

if [[ "$QUEUE_EXISTS" == "true" ]]; then
  echo "The [$STORAGE_QUEUE_NAME] queue already exists in the [$STORAGE_ACCOUNT_NAME] storage account"
else
  echo "No [$STORAGE_QUEUE_NAME] queue exists in the [$STORAGE_ACCOUNT_NAME] storage account"
  echo "Creating the [$STORAGE_QUEUE_NAME] queue..."

  az storage queue create \
    --name $STORAGE_QUEUE_NAME \
    --account-name $STORAGE_ACCOUNT_NAME \
    "${QUEUE_AUTHENTICATION[@]}" \
    --only-show-errors 1>/dev/null

  if [[ $? -eq 0 ]]; then
    echo "The [$STORAGE_QUEUE_NAME] queue was successfully created"
  else
    echo "Failed to create the [$STORAGE_QUEUE_NAME] queue"
    exit 1
  fi
fi

# Retrieve the resource id of the storage account, the scope of the role assignment
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

# Assign the role only if it is not assigned yet
echo "Checking if the [$MANAGED_IDENTITY_NAME] managed identity has the [$ROLE] role on the [$STORAGE_ACCOUNT_NAME] storage account..."
ROLE_ASSIGNMENT=$(az role assignment list \
  --assignee $MANAGED_IDENTITY_PRINCIPAL_ID \
  --scope $STORAGE_ACCOUNT_ID \
  --query "[?roleDefinitionName=='$ROLE'].roleDefinitionName" \
  --output tsv \
  --only-show-errors 2>/dev/null)

if [[ -n $ROLE_ASSIGNMENT ]]; then
  echo "The [$MANAGED_IDENTITY_NAME] managed identity already has the [$ROLE] role on the [$STORAGE_ACCOUNT_NAME] storage account"
else
  echo "Assigning the [$ROLE] role to the [$MANAGED_IDENTITY_NAME] managed identity on the [$STORAGE_ACCOUNT_NAME] storage account..."

  # A freshly created identity may not be visible to the role-assignment API yet, hence the retries
  for i in $(seq 1 $RETRY_COUNT); do
    az role assignment create \
      --role "$ROLE" \
      --assignee-object-id $MANAGED_IDENTITY_PRINCIPAL_ID \
      --assignee-principal-type ServicePrincipal \
      --scope $STORAGE_ACCOUNT_ID \
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

# Print all the queues in the storage account, so the user can see what was created and what already existed
echo "The [$STORAGE_ACCOUNT_NAME] storage account contains the following queues:"
az storage queue list \
	--account-name $STORAGE_ACCOUNT_NAME \
	"${QUEUE_AUTHENTICATION[@]}" \
	--output table