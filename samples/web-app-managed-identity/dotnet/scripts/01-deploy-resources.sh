#!/bin/bash

# Variables
source ./00-variables.sh

# On Windows, Git Bash and MSYS2 shells pass a path such as /tmp/... unconverted to Windows programs
# (az, curl, jq, python, docker) when MSYS_NO_PATHCONV=1 is set, as the README asks. cygpath, which
# those shells provide, returns the C:/... form those programs can open; elsewhere the path is unchanged.
native_path() {
	if command -v cygpath >/dev/null 2>&1; then
		cygpath -m "$1"
	else
		echo "$1"
	fi
}

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
		--admin-enabled true \
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

# Upload the sample activities, so the app does not start with an empty list. Each activity is a blob named
# YYYY-MM-DD-HH-MM-SS-activity.txt holding the activity text, the format the app itself reads and writes; these
# are the activities the web-app-file-storage sample seeds. The names are fixed, so a re-run uploads only the
# missing ones.
SAMPLE_ACTIVITIES=(
	"2026-01-05-09-00-00-activity.txt|Snorkelling at Coral Bay"
	"2026-01-05-09-05-00-activity.txt|Sunset hike to the Cape lighthouse"
	"2026-01-05-09-10-00-activity.txt|Cooking class: pasta from scratch"
)
SAMPLE_ACTIVITIES_DIR=$(native_path "$(mktemp -d)")

for SAMPLE_ACTIVITY in "${SAMPLE_ACTIVITIES[@]}"; do
	BLOB_NAME="${SAMPLE_ACTIVITY%%|*}"
	ACTIVITY="${SAMPLE_ACTIVITY#*|}"

	echo "Checking if blob [$BLOB_NAME] exists in blob container [$CONTAINER_NAME]..."
	EXISTS=$(az storage blob exists \
		--account-name $STORAGE_ACCOUNT_NAME \
		--account-key $STORAGE_ACCOUNT_KEY \
		--container-name $CONTAINER_NAME \
		--name $BLOB_NAME \
		--query exists \
		--output tsv 2>/dev/null)

	if [[ "$EXISTS" == "true" ]]; then
		echo "Blob [$BLOB_NAME] already exists."
		continue
	fi

	# The file has the blob's name, so az storage blob upload gives the blob the text/plain type of a .txt file
	echo "Uploading sample activity [$ACTIVITY] as blob [$BLOB_NAME]..."
	printf '%s' "$ACTIVITY" >"$SAMPLE_ACTIVITIES_DIR/$BLOB_NAME"
	az storage blob upload \
		--account-name $STORAGE_ACCOUNT_NAME \
		--account-key $STORAGE_ACCOUNT_KEY \
		--container-name $CONTAINER_NAME \
		--name $BLOB_NAME \
		--file "$SAMPLE_ACTIVITIES_DIR/$BLOB_NAME" \
		--only-show-errors 1>/dev/null

	if [ $? -eq 0 ]; then
		echo "Blob [$BLOB_NAME] uploaded successfully."
	else
		echo "Failed to upload blob [$BLOB_NAME]."
		rm -rf "$SAMPLE_ACTIVITIES_DIR"
		exit 1
	fi
done

rm -rf "$SAMPLE_ACTIVITIES_DIR"

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

# Assign the Storage Blob Data Contributor role to the managed identity on the storage account
ensure_role_assignment "$PRINCIPAL_ID" "ServicePrincipal" "Storage Blob Data Contributor" \
	"$STORAGE_ACCOUNT_RESOURCE_ID" "[$MANAGED_IDENTITY_NAME] managed identity" "[$STORAGE_ACCOUNT_NAME] storage account"