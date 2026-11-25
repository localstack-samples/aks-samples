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

# Check if the resource group already exists
echo "Checking if [$KEY_VAULT_RESOURCE_GROUP_NAME] resource group actually exists in the [$SUBSCRIPTION_NAME] subscription..."

az group show --name $KEY_VAULT_RESOURCE_GROUP_NAME &>/dev/null

if [[ $? != 0 ]]; then
  echo "No [$KEY_VAULT_RESOURCE_GROUP_NAME] resource group actually exists in the [$SUBSCRIPTION_NAME] subscription"
  echo "Creating [$KEY_VAULT_RESOURCE_GROUP_NAME] resource group in the [$SUBSCRIPTION_NAME] subscription..."

  # create the resource group
  az group create --name $KEY_VAULT_RESOURCE_GROUP_NAME --location $LOCATION 1>/dev/null

  if [[ $? == 0 ]]; then
    echo "[$KEY_VAULT_RESOURCE_GROUP_NAME] resource group successfully created in the [$SUBSCRIPTION_NAME] subscription"
  else
    echo "Failed to create [$KEY_VAULT_RESOURCE_GROUP_NAME] resource group in the [$SUBSCRIPTION_NAME] subscription"
    exit
  fi
else
  echo "[$KEY_VAULT_RESOURCE_GROUP_NAME] resource group already exists in the [$SUBSCRIPTION_NAME] subscription"
fi

# Check if the key vault already exists
echo "Checking if [$KEY_VAULT_NAME] key vault actually exists in the [$SUBSCRIPTION_NAME] subscription..."

az keyvault show --name $KEY_VAULT_NAME --resource-group $KEY_VAULT_RESOURCE_GROUP_NAME &>/dev/null

if [[ $? != 0 ]]; then
  echo "No [$KEY_VAULT_NAME] key vault actually exists in the [$SUBSCRIPTION_NAME] subscription"
  echo "Creating [$KEY_VAULT_NAME] key vault in the [$SUBSCRIPTION_NAME] subscription..."

  # create the key vault
  az keyvault create \
    --name $KEY_VAULT_NAME \
    --resource-group $KEY_VAULT_RESOURCE_GROUP_NAME \
    --location $LOCATION \
    --enabled-for-deployment \
    --enabled-for-disk-encryption \
    --enabled-for-template-deployment \
    --enable-rbac-authorization true \
    --sku $KEY_VAULT_SKU 1>/dev/null

  if [[ $? == 0 ]]; then
    echo "[$KEY_VAULT_NAME] key vault successfully created in the [$SUBSCRIPTION_NAME] subscription"
  else
    echo "Failed to create [$KEY_VAULT_NAME] key vault in the [$SUBSCRIPTION_NAME] subscription"
    exit
  fi
else
  echo "[$KEY_VAULT_NAME] key vault already exists in the [$SUBSCRIPTION_NAME] subscription"
fi

# Retrieve the resource id of the Key Vault resource
echo "Retrieving the resource id for the [$KEY_VAULT_NAME] key vault..."
KEY_VAULT_ID=$(az keyvault show \
  --name $KEY_VAULT_NAME \
  --resource-group $KEY_VAULT_RESOURCE_GROUP_NAME \
  --query id \
  --output tsv)

if [[ -n $KEY_VAULT_ID ]]; then
  echo "[$KEY_VAULT_ID] resource id for the [$KEY_VAULT_NAME] key vault successfully retrieved"
else
  echo "Failed to retrieve the resource id for the [$KEY_VAULT_NAME] key vault"
  exit
fi

if [[ "$ENVIRONMENT_NAME" == "AzureCloud" ]]; then
	# Get the signed-in user object id
	LOGGED_IN_USER_ID=$(az ad signed-in-user show --query id --output tsv)
	LOGGED_IN_USER_DISPLAY_NAME=$(az ad signed-in-user show --query displayName --output tsv)

	# Assign the Key Vault Administrator role to the user on the key vault
	ensure_role_assignment "$LOGGED_IN_USER_ID" "User" "Key Vault Administrator" \
		"$KEY_VAULT_ID" "[$LOGGED_IN_USER_DISPLAY_NAME] user" "[$KEY_VAULT_NAME] key vault"
fi

# Create secrets
for INDEX in ${!SECRETS[@]}; do
  # Check if the secret already exists
  echo "Checking if [${SECRETS[$INDEX]}] secret actually exists in the [$KEY_VAULT_NAME] key vault..."

  az keyvault secret show --name ${SECRETS[$INDEX]} --vault-name $KEY_VAULT_NAME &>/dev/null

  if [[ $? != 0 ]]; then
		echo "No [${SECRETS[$INDEX]}] secret actually exists in the [$KEY_VAULT_NAME] key vault"
		ATTEMPT=1
		while [ $ATTEMPT -le $RETRY_COUNT ]; do
			echo "Attempt $ATTEMPT of $RETRY_COUNT to create [${SECRETS[$INDEX]}] secret in the [$KEY_VAULT_NAME] key vault..."
			
			# Create the secret
			az keyvault secret set \
				--name ${SECRETS[$INDEX]} \
				--vault-name $KEY_VAULT_NAME \
				--value ${VALUES[$INDEX]} 1>/dev/null

			if [[ $? == 0 ]]; then
				echo "[${SECRETS[$INDEX]}] secret successfully created in the [$KEY_VAULT_NAME] key vault"
				break
			else
				if [ $ATTEMPT -lt $RETRY_COUNT ]; then
					echo "Failed to create [${SECRETS[$INDEX]}] secret in the [$KEY_VAULT_NAME] key vault. Waiting [$SLEEP] seconds before retry..."
					sleep $SLEEP
				else
					echo "Failed to create [${SECRETS[$INDEX]}] secret in the [$KEY_VAULT_NAME] key vault"
					exit 1
				fi
				ATTEMPT=$((ATTEMPT + 1))
			fi
		done
  else
    echo "[${SECRETS[$INDEX]}] secret already exists in the [$KEY_VAULT_NAME] key vault"
  fi
done

# Show secrets
for INDEX in ${!SECRETS[@]}; do
	# retrieve the secret
	echo "Retrieving [${SECRETS[$INDEX]}] secret from the [$KEY_VAULT_NAME] key vault..."
	VALUE=$(az keyvault secret show \
		--name ${SECRETS[$INDEX]} \
		--vault-name $KEY_VAULT_NAME \
		--query value \
		--output tsv)
	
	if [[ -n $VALUE ]]; then
		echo "[$VALUE] value for [${SECRETS[$INDEX]}] secret successfully retrieved from the [$KEY_VAULT_NAME] key vault"
	else
		echo "Failed to retrieve [${SECRETS[$INDEX]}] secret from the [$KEY_VAULT_NAME] key vault"
		exit
	fi
done