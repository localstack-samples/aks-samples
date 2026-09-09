#!/bin/bash

# Variables
source ./00-variables.sh

# Change the current directory to the script's directory
cd "$CURRENT_DIR" || exit

# Create a resource group
echo "Checking if resource group [$RESOURCE_GROUP_NAME] exists in the subscription [$SUBSCRIPTION_NAME]..."
az group show --name $RESOURCE_GROUP_NAME &>/dev/null

if [[ $? != 0 ]]; then
	echo "No resource group [$RESOURCE_GROUP_NAME] exists in the subscription [$SUBSCRIPTION_NAME]"
	echo "Creating resource group [$RESOURCE_GROUP_NAME] in the subscription [$SUBSCRIPTION_NAME]..."

	az group create \
		--name $RESOURCE_GROUP_NAME \
		--location "$LOCATION" \
		--only-show-errors 1>/dev/null

	if [[ $? == 0 ]]; then
		echo "Resource group [$RESOURCE_GROUP_NAME] successfully created in the subscription [$SUBSCRIPTION_NAME]"
	else
		echo "Failed to create resource group [$RESOURCE_GROUP_NAME] in the subscription [$SUBSCRIPTION_NAME]"
		exit 1
	fi
else
	echo "Resource group [$RESOURCE_GROUP_NAME] already exists in the subscription [$SUBSCRIPTION_NAME]"
fi

# Create the Azure Container Registry
echo "Checking if [$ACR_NAME] Azure Container Registry already exists in the [$RESOURCE_GROUP_NAME] resource group..."
az acr show \
	--name "$ACR_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--only-show-errors &>/dev/null

if [[ $? != 0 ]]; then
	echo "No [$ACR_NAME] Azure Container Registry exists in the [$RESOURCE_GROUP_NAME] resource group"
	echo "Creating Azure Container Registry [$ACR_NAME]..."
	az acr create \
		--name "$ACR_NAME" \
		--resource-group "$RESOURCE_GROUP_NAME" \
		--location "$LOCATION" \
		--sku "$ACR_SKU" \
		--admin-enabled "true" \
		--only-show-errors 1>/dev/null

	if [ $? -eq 0 ]; then
		echo "Azure Container Registry [$ACR_NAME] created successfully."
	else
		echo "Failed to create Azure Container Registry [$ACR_NAME]."
		exit 1
	fi
else
	echo "[$ACR_NAME] Azure Container Registry already exists in the [$RESOURCE_GROUP_NAME] resource group"
fi

# Create the Storage Account
echo "Checking if storage account [$STORAGE_ACCOUNT_NAME] exists in the resource group [$RESOURCE_GROUP_NAME]..."
az storage account show \
	--name $STORAGE_ACCOUNT_NAME \
	--resource-group $RESOURCE_GROUP_NAME &>/dev/null

if [[ $? != 0 ]]; then
	echo "Creating storage account [$STORAGE_ACCOUNT_NAME]..."
	az storage account create \
		--name $STORAGE_ACCOUNT_NAME \
		--location "$LOCATION" \
		--resource-group $RESOURCE_GROUP_NAME \
		--sku Standard_LRS \
		--allow-blob-public-access true \
		--only-show-errors 1>/dev/null

	if [ $? -eq 0 ]; then
		echo "Storage account [$STORAGE_ACCOUNT_NAME] created successfully."
	else
		echo "Failed to create storage account [$STORAGE_ACCOUNT_NAME]."
		exit 1
	fi
else
	echo "Storage account [$STORAGE_ACCOUNT_NAME] already exists in the [$RESOURCE_GROUP_NAME] resource group"
fi

# Get the storage account key
STORAGE_ACCOUNT_KEY=$(az storage account keys list \
	--account-name $STORAGE_ACCOUNT_NAME \
	--resource-group $RESOURCE_GROUP_NAME \
	--query "[0].value" \
	--output tsv)

if [ -z "$STORAGE_ACCOUNT_KEY" ]; then
	echo "Failed to retrieve storage account key."
	exit 1
fi

# Get the storage account resource ID
STORAGE_ACCOUNT_RESOURCE_ID=$(az storage account show \
	--name $STORAGE_ACCOUNT_NAME \
	--resource-group $RESOURCE_GROUP_NAME \
	--query "id" \
	--output tsv \
	--only-show-errors)

if [ -n "$STORAGE_ACCOUNT_RESOURCE_ID" ]; then
	echo "Storage account resource ID retrieved successfully: $STORAGE_ACCOUNT_RESOURCE_ID"
else
	echo "Failed to retrieve storage account resource ID."
	exit 1
fi

# Create the blob container
echo "Checking if blob container [$CONTAINER_NAME] exists in storage account [$STORAGE_ACCOUNT_NAME]..."
EXISTS=$(az storage container exists \
	--account-name $STORAGE_ACCOUNT_NAME \
	--account-key $STORAGE_ACCOUNT_KEY \
	--name $CONTAINER_NAME \
	--query exists \
	--output tsv 2>/dev/null)

if [[ "$EXISTS" != "true" ]]; then
	echo "Creating blob container [$CONTAINER_NAME]..."
	az storage container create \
		--account-name $STORAGE_ACCOUNT_NAME \
		--account-key $STORAGE_ACCOUNT_KEY \
		--name $CONTAINER_NAME \
		--only-show-errors 1>/dev/null

	if [ $? -eq 0 ]; then
		echo "Blob container [$CONTAINER_NAME] created successfully."
	else
		echo "Failed to create blob container [$CONTAINER_NAME]."
		exit 1
	fi
else
	echo "Blob container [$CONTAINER_NAME] already exists."
fi

# Check if the user-assigned managed identity already exists
echo "Checking if [$MANAGED_IDENTITY_NAME] user-assigned managed identity actually exists in the [$RESOURCE_GROUP_NAME] resource group..."

az identity show \
  --name $MANAGED_IDENTITY_NAME \
  --resource-group $RESOURCE_GROUP_NAME &>/dev/null

if [[ $? != 0 ]]; then
  echo "No [$MANAGED_IDENTITY_NAME] user-assigned managed identity actually exists in the [$RESOURCE_GROUP_NAME] resource group"
  echo "Creating [$MANAGED_IDENTITY_NAME] user-assigned managed identity in the [$RESOURCE_GROUP_NAME] resource group..."

  # Create the user-assigned managed identity
  az identity create \
    --name $MANAGED_IDENTITY_NAME \
    --resource-group $RESOURCE_GROUP_NAME \
    --location $LOCATION \
    --subscription $SUBSCRIPTION_ID 1>/dev/null

  if [[ $? == 0 ]]; then
    echo "[$MANAGED_IDENTITY_NAME] user-assigned managed identity successfully created in the [$RESOURCE_GROUP_NAME] resource group"
  else
    echo "Failed to create [$MANAGED_IDENTITY_NAME] user-assigned managed identity in the [$RESOURCE_GROUP_NAME] resource group"
    exit
  fi
else
  echo "[$MANAGED_IDENTITY_NAME] user-assigned managed identity already exists in the [$RESOURCE_GROUP_NAME] resource group"
fi

# Retrieve the clientId of the user-assigned managed identity
echo "Retrieving clientId for [$MANAGED_IDENTITY_NAME] managed identity..."
CLIENT_ID=$(az identity show \
  --name $MANAGED_IDENTITY_NAME \
  --resource-group $RESOURCE_GROUP_NAME \
  --query clientId \
  --output tsv)

if [[ -n $CLIENT_ID ]]; then
  echo "[$CLIENT_ID] clientId  for the [$MANAGED_IDENTITY_NAME] managed identity successfully retrieved"
else
  echo "Failed to retrieve clientId for the [$MANAGED_IDENTITY_NAME] managed identity"
  exit
fi

# Retrieve the principalId of the user-assigned managed identity
echo "Retrieving principalId for [$MANAGED_IDENTITY_NAME] managed identity..."
PRINCIPAL_ID=$(az identity show \
  --name $MANAGED_IDENTITY_NAME \
  --resource-group $RESOURCE_GROUP_NAME \
  --query principalId \
  --output tsv)

if [[ -n $PRINCIPAL_ID ]]; then
  echo "[$PRINCIPAL_ID] principalId  for the [$MANAGED_IDENTITY_NAME] managed identity successfully retrieved"
else
  echo "Failed to retrieve principalId for the [$MANAGED_IDENTITY_NAME] managed identity"
  exit
fi

# Assign the Storage Blob Data Contributor role to the managed identity with the storage account as scope
ROLE="Storage Blob Data Contributor"
SCOPE_ID="$STORAGE_ACCOUNT_RESOURCE_ID"
SCOPE_NAME="$STORAGE_ACCOUNT_NAME"
SCOPE_TYPE="storage account"
echo "Checking if the [$MANAGED_IDENTITY_NAME] managed identity has the [$ROLE] role assignment on the [$SCOPE_NAME] $SCOPE_TYPE..."
current=$(az role assignment list \
  --assignee "$PRINCIPAL_ID" \
  --scope "$SCOPE_ID" \
  --query "[?roleDefinitionName=='$ROLE'].roleDefinitionName" \
  --output tsv 2>/dev/null)

if [[ $current == "$ROLE" ]]; then
  echo "Managed identity [$MANAGED_IDENTITY_NAME] already has the [$ROLE] role assignment on the [$SCOPE_NAME] $SCOPE_TYPE"
else
  echo "Managed identity [$MANAGED_IDENTITY_NAME] does not have the [$ROLE] role assignment on the [$SCOPE_NAME] $SCOPE_TYPE"
  echo "Creating role assignment: assigning [$ROLE] role to managed identity [$MANAGED_IDENTITY_NAME] on the [$SCOPE_NAME] $SCOPE_TYPE..."
  ATTEMPT=1
	RETRY_COUNT=5
	SLEEP=3
  while [ $ATTEMPT -le $RETRY_COUNT ]; do
    echo "Attempt $ATTEMPT of $RETRY_COUNT to assign role..."
    az role assignment create \
      --assignee "$PRINCIPAL_ID" \
      --role "$ROLE" \
      --scope "$SCOPE_ID" 1>/dev/null

    if [[ $? == 0 ]]; then
      break
    else
      if [ $ATTEMPT -lt $RETRY_COUNT ]; then
        echo "Role assignment failed. Waiting [$SLEEP] seconds before retry..."
        sleep $SLEEP
      fi
      ATTEMPT=$((ATTEMPT + 1))
    fi
  done

  if [[ $? == 0 ]]; then
    echo "Successfully assigned [$ROLE] role to managed identity [$MANAGED_IDENTITY_NAME] on the [$SCOPE_NAME] $SCOPE_TYPE"
  else
    echo "Failed to assign [$ROLE] role to managed identity [$MANAGED_IDENTITY_NAME] on the [$SCOPE_NAME] $SCOPE_TYPE"
    exit 1
  fi
fi