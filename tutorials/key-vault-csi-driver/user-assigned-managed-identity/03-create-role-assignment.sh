#!/bin/bash

# Variables
source ./00-variables.sh

# Assign a role to a principal on a scope, unless it already has it. Azure needs a moment to propagate a
# freshly created principal, so the create is retried.
# $1: the principal (object) id  $2: the principal type  $3: the role  $4: the scope
# $5: a description of the principal  $6: a description of the scope
ensure_role_assignment() {
	local principal_id=$1
	local principal_type=$2
	local role=$3
	local scope=$4
	local principal_description=$5
	local scope_description=$6
	local current attempt

	echo "Checking if the $principal_description has the [$role] role assignment on the $scope_description..."
	current=$(az role assignment list \
		--assignee "$principal_id" \
		--scope "$scope" \
		--query "[?roleDefinitionName=='$role'].roleDefinitionName" \
		--output tsv \
		--only-show-errors 2>/dev/null)

	if [[ $current == "$role" ]]; then
		echo "The $principal_description already has the [$role] role assignment on the $scope_description"
		return 0
	fi

	echo "Assigning the [$role] role to the $principal_description on the $scope_description..."
	for attempt in $(seq 1 "$ROLE_ASSIGNMENT_RETRY_COUNT"); do
		if az role assignment create \
			--assignee-object-id "$principal_id" \
			--assignee-principal-type "$principal_type" \
			--role "$role" \
			--scope "$scope" \
			--only-show-errors 1>/dev/null; then
			echo "[$role] role successfully assigned to the $principal_description on the $scope_description"
			return 0
		fi

		if [ "$attempt" -lt "$ROLE_ASSIGNMENT_RETRY_COUNT" ]; then
			echo "Attempt $attempt of $ROLE_ASSIGNMENT_RETRY_COUNT to assign the [$role] role failed; retrying in $ROLE_ASSIGNMENT_RETRY_SLEEP seconds..."
			sleep "$ROLE_ASSIGNMENT_RETRY_SLEEP"
		fi
	done

	echo "Failed to assign the [$role] role to the $principal_description on the $scope_description"
	exit 1
}

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

# Assign the Key Vault Administrator role to the Azure Key Vault Secrets Provider identity on the key vault
ensure_role_assignment "$KV_IDENTITY_OBJECT_ID" "ServicePrincipal" "Key Vault Administrator" \
	"$KEY_VAULT_ID" "[$KV_IDENTITY_NAME] managed identity" "[$KEY_VAULT_NAME] key vault"
