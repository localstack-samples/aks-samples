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

# Create the Cosmos DB account (NoSQL / SQL API - default kind GlobalDocumentDB)
echo "Checking if Cosmos DB account [$COSMOSDB_ACCOUNT_NAME] exists in the [$RESOURCE_GROUP_NAME] resource group..."
az cosmosdb show \
	--name "$COSMOSDB_ACCOUNT_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--only-show-errors &>/dev/null

if [[ $? != 0 ]]; then
	echo "No Cosmos DB account [$COSMOSDB_ACCOUNT_NAME] exists in the [$RESOURCE_GROUP_NAME] resource group"
	echo "Creating Cosmos DB account [$COSMOSDB_ACCOUNT_NAME] with NoSQL API..."
	az cosmosdb create \
		--name "$COSMOSDB_ACCOUNT_NAME" \
		--resource-group "$RESOURCE_GROUP_NAME" \
		--locations regionName="$LOCATION" \
		--default-consistency-level Session \
		--only-show-errors 1>/dev/null

	if [ $? -eq 0 ]; then
		echo "Cosmos DB account [$COSMOSDB_ACCOUNT_NAME] created successfully."
	else
		echo "Failed to create Cosmos DB account [$COSMOSDB_ACCOUNT_NAME]."
		exit 1
	fi
else
	echo "Cosmos DB account [$COSMOSDB_ACCOUNT_NAME] already exists in the [$RESOURCE_GROUP_NAME] resource group"
fi

# Retrieve the document endpoint
echo "Retrieving document endpoint for Cosmos DB account [$COSMOSDB_ACCOUNT_NAME]..."
AZURECOSMOSDB_ENDPOINT=$(az cosmosdb show \
	--name "$COSMOSDB_ACCOUNT_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--query "documentEndpoint" \
	--output tsv)

if [ -n "$AZURECOSMOSDB_ENDPOINT" ]; then
	echo "Document endpoint retrieved successfully: $AZURECOSMOSDB_ENDPOINT"
else
	echo "Failed to retrieve document endpoint."
	exit 1
fi

# Create the SQL database
echo "Checking if SQL database [$AZURECOSMOSDB_DATABASENAME] exists in account [$COSMOSDB_ACCOUNT_NAME]..."
az cosmosdb sql database show \
	--account-name "$COSMOSDB_ACCOUNT_NAME" \
	--name "$AZURECOSMOSDB_DATABASENAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--only-show-errors &>/dev/null

if [[ $? != 0 ]]; then
	echo "Creating SQL database [$AZURECOSMOSDB_DATABASENAME]..."
	az cosmosdb sql database create \
		--account-name "$COSMOSDB_ACCOUNT_NAME" \
		--name "$AZURECOSMOSDB_DATABASENAME" \
		--resource-group "$RESOURCE_GROUP_NAME" \
		--only-show-errors 1>/dev/null

	if [ $? -eq 0 ]; then
		echo "SQL database [$AZURECOSMOSDB_DATABASENAME] created successfully."
	else
		echo "Failed to create SQL database [$AZURECOSMOSDB_DATABASENAME]."
		exit 1
	fi
else
	echo "SQL database [$AZURECOSMOSDB_DATABASENAME] already exists in account [$COSMOSDB_ACCOUNT_NAME]"
fi

# Create the SQL container
echo "Checking if SQL container [$AZURECOSMOSDB_CONTAINERNAME] exists in database [$AZURECOSMOSDB_DATABASENAME]..."
az cosmosdb sql container show \
	--account-name "$COSMOSDB_ACCOUNT_NAME" \
	--database-name "$AZURECOSMOSDB_DATABASENAME" \
	--name "$AZURECOSMOSDB_CONTAINERNAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--only-show-errors &>/dev/null

if [[ $? != 0 ]]; then
	echo "Creating SQL container [$AZURECOSMOSDB_CONTAINERNAME]..."
	az cosmosdb sql container create \
		--account-name "$COSMOSDB_ACCOUNT_NAME" \
		--database-name "$AZURECOSMOSDB_DATABASENAME" \
		--name "$AZURECOSMOSDB_CONTAINERNAME" \
		--resource-group "$RESOURCE_GROUP_NAME" \
		--partition-key-path "$AZURECOSMOSDB_PARTITION_KEY" \
		--throughput "$THROUGHPUT" \
		--only-show-errors 1>/dev/null

	if [ $? -eq 0 ]; then
		echo "SQL container [$AZURECOSMOSDB_CONTAINERNAME] created successfully."
	else
		echo "Failed to create SQL container [$AZURECOSMOSDB_CONTAINERNAME]."
		exit 1
	fi
else
	echo "SQL container [$AZURECOSMOSDB_CONTAINERNAME] already exists in database [$AZURECOSMOSDB_DATABASENAME]"
fi

# Retrieve the primary master key
echo "Retrieving primary master key for Cosmos DB account [$COSMOSDB_ACCOUNT_NAME]..."
AZURECOSMOSDB_PRIMARY_KEY=$(az cosmosdb keys list \
	--name "$COSMOSDB_ACCOUNT_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--query "primaryMasterKey" \
	--output tsv)

if [ -n "$AZURECOSMOSDB_PRIMARY_KEY" ]; then
	echo "Primary master key retrieved successfully."
else
	echo "Failed to retrieve primary master key."
	exit 1
fi

export AZURECOSMOSDB_ENDPOINT
export AZURECOSMOSDB_PRIMARY_KEY
