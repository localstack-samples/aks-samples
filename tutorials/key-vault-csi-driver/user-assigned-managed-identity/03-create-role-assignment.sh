#!/bin/bash

# Variables
source ./00-variables.sh

# Retrieve the resource id of the Key Vault resource
echo "Retrieving the resource id for the [$KEY_VAULT_NAME] key vault..."
KEY_VAULT_ID=$(az keyvault show \
  --name $KEY_VAULT_NAME \
  --resource-group $KEY_VAULT_RESOURCE_GROUP_NAME \
  --query id \
  --output tsv \
  --only-show-errors)

if [[ -n $KEY_VAULT_ID ]]; then
  echo "[$KEY_VAULT_ID] resource id for the [$KEY_VAULT_NAME] key vault successfully retrieved"
else
  echo "Failed to retrieve the resource id for the [$KEY_VAULT_NAME] key vault"
  exit
fi

# Get the objectId of the Azure Key Vault Secrets Provider identity
KV_IDENTITY_OBJECT_ID=$(az aks show \
	--resource-group $AKS_RESOURCE_GROUP_NAME \
	--name $AKS_NAME \
	--query addonProfiles.azureKeyvaultSecretsProvider.identity.objectId \
	--output tsv \
	--only-show-errors)

if [[ -n $KV_IDENTITY_OBJECT_ID ]]; then
	echo "Successfully retrieved the objectId for the Azure Key Vault Secrets Provider identity in the [$AKS_NAME] AKS cluster"
else
	echo "Failed to retrieve the objectId for the Azure Key Vault Secrets Provider identity in the [$AKS_NAME] AKS cluster"
	exit
fi

# Get the resourceId of the Azure Key Vault Secrets Provider identity
KV_IDENTITY_RESOURCE_ID=$(az aks show \
	--resource-group $AKS_RESOURCE_GROUP_NAME \
	--name $AKS_NAME \
	--query addonProfiles.azureKeyvaultSecretsProvider.identity.resourceId \
	--output tsv \
	--only-show-errors)

if [[ -n $KV_IDENTITY_RESOURCE_ID ]]; then
	echo "Successfully retrieved the resourceId for the Azure Key Vault Secrets Provider identity in the [$AKS_NAME] AKS cluster"
else
	echo "Failed to retrieve the resourceId for the Azure Key Vault Secrets Provider identity in the [$AKS_NAME] AKS cluster"
	exit
fi

# Get the name of the Azure Key Vault Secrets Provider identity from the resourceId
KV_IDENTITY_NAME=$(basename $KV_IDENTITY_RESOURCE_ID)

# Assign the Key Vault Administrator role to the managed identity on the node resource group
ROLE="Key Vault Administrator"
MANAGED_IDENTITY_NAME="$KV_IDENTITY_NAME"
PRINCIPAL_ID="$KV_IDENTITY_OBJECT_ID"
SCOPE_ID="$KEY_VAULT_ID"
SCOPE_NAME="$KEY_VAULT_NAME"
SCOPE_TYPE="key vault"
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
