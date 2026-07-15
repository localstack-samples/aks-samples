#!/bin/bash

# Variables
source ./00-variables.sh

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
	ROLE="Key Vault Administrator"
	USER_DISPLAY_NAME="$LOGGED_IN_USER_DISPLAY_NAME"
	PRINCIPAL_ID="$LOGGED_IN_USER_ID"
	SCOPE_ID="$KEY_VAULT_ID"
	SCOPE_NAME="$KEY_VAULT_NAME"
	SCOPE_TYPE="key vault"
	echo "Checking if the [$USER_DISPLAY_NAME] user has the [$ROLE] role assignment on the [$SCOPE_NAME] $SCOPE_TYPE..."
	current=$(az role assignment list \
		--assignee "$PRINCIPAL_ID" \
		--scope "$SCOPE_ID" \
		--query "[?roleDefinitionName=='$ROLE'].roleDefinitionName" \
		--output tsv 2>/dev/null)

	if [[ $current == "$ROLE" ]]; then
		echo "User [$USER_DISPLAY_NAME] already has the [$ROLE] role assignment on the [$SCOPE_NAME] $SCOPE_TYPE"
	else
		echo "User [$USER_DISPLAY_NAME] does not have the [$ROLE] role assignment on the [$SCOPE_NAME] $SCOPE_TYPE"
		echo "Creating role assignment: assigning [$ROLE] role to user [$USER_DISPLAY_NAME] on the [$SCOPE_NAME] $SCOPE_TYPE..."
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
			echo "Successfully assigned [$ROLE] role to user [$USER_DISPLAY_NAME] on the [$SCOPE_NAME] $SCOPE_TYPE"
		else
			echo "Failed to assign [$ROLE] role to user [$USER_DISPLAY_NAME] on the [$SCOPE_NAME] $SCOPE_TYPE"
			exit 1
		fi
	fi
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