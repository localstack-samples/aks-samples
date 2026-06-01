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

# Create the Cosmos DB account (MongoDB API)
echo "Checking if Cosmos DB account [$COSMOSDB_ACCOUNT_NAME] exists in the [$RESOURCE_GROUP_NAME] resource group..."
az cosmosdb show \
	--name "$COSMOSDB_ACCOUNT_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--only-show-errors &>/dev/null

if [[ $? != 0 ]]; then
	echo "No Cosmos DB account [$COSMOSDB_ACCOUNT_NAME] exists in the [$RESOURCE_GROUP_NAME] resource group"
	echo "Creating Cosmos DB account [$COSMOSDB_ACCOUNT_NAME] with MongoDB API..."
	az cosmosdb create \
		--name "$COSMOSDB_ACCOUNT_NAME" \
		--resource-group "$RESOURCE_GROUP_NAME" \
		--kind MongoDB \
		--server-version "$MONGODB_API_VERSION" \
		--default-consistency-level Session \
		--locations regionName="$LOCATION" \
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

# Create the MongoDB database
echo "Checking if MongoDB database [$COSMOSDB_DATABASE_NAME] exists in account [$COSMOSDB_ACCOUNT_NAME]..."
az cosmosdb mongodb database show \
	--account-name "$COSMOSDB_ACCOUNT_NAME" \
	--name "$COSMOSDB_DATABASE_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--only-show-errors &>/dev/null

if [[ $? != 0 ]]; then
	echo "Creating MongoDB database [$COSMOSDB_DATABASE_NAME]..."
	az cosmosdb mongodb database create \
		--account-name "$COSMOSDB_ACCOUNT_NAME" \
		--name "$COSMOSDB_DATABASE_NAME" \
		--resource-group "$RESOURCE_GROUP_NAME" \
		--only-show-errors 1>/dev/null

	if [ $? -eq 0 ]; then
		echo "MongoDB database [$COSMOSDB_DATABASE_NAME] created successfully."
	else
		echo "Failed to create MongoDB database [$COSMOSDB_DATABASE_NAME]."
		exit 1
	fi
else
	echo "MongoDB database [$COSMOSDB_DATABASE_NAME] already exists in account [$COSMOSDB_ACCOUNT_NAME]"
fi

# Create the MongoDB collection
echo "Checking if MongoDB collection [$COSMOSDB_COLLECTION_NAME] exists in database [$COSMOSDB_DATABASE_NAME]..."
az cosmosdb mongodb collection show \
	--account-name "$COSMOSDB_ACCOUNT_NAME" \
	--database-name "$COSMOSDB_DATABASE_NAME" \
	--name "$COSMOSDB_COLLECTION_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--only-show-errors &>/dev/null

if [[ $? != 0 ]]; then
	echo "Creating MongoDB collection [$COSMOSDB_COLLECTION_NAME]..."
	az cosmosdb mongodb collection create \
		--account-name "$COSMOSDB_ACCOUNT_NAME" \
		--database-name "$COSMOSDB_DATABASE_NAME" \
		--name "$COSMOSDB_COLLECTION_NAME" \
		--resource-group "$RESOURCE_GROUP_NAME" \
		--shard "$SHARD" \
		--throughput "$THROUGHPUT" \
		--idx "$INDEXES" \
		--only-show-errors 1>/dev/null

	if [ $? -eq 0 ]; then
		echo "MongoDB collection [$COSMOSDB_COLLECTION_NAME] created successfully."
	else
		echo "Failed to create MongoDB collection [$COSMOSDB_COLLECTION_NAME]."
		exit 1
	fi
else
	echo "MongoDB collection [$COSMOSDB_COLLECTION_NAME] already exists in database [$COSMOSDB_DATABASE_NAME]"
fi

# Retrieve the Cosmos DB MongoDB connection string
echo "Retrieving Cosmos DB MongoDB connection string for [$COSMOSDB_ACCOUNT_NAME]..."
COSMOSDB_CONNECTION_STRING=$(az cosmosdb keys list \
	--name "$COSMOSDB_ACCOUNT_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--type connection-strings \
	--query "connectionStrings[0].connectionString" \
	--output tsv)

if [ -n "$COSMOSDB_CONNECTION_STRING" ]; then
	echo "Cosmos DB connection string retrieved successfully."
else
	echo "Failed to retrieve Cosmos DB connection string."
	exit 1
fi

export COSMOSDB_CONNECTION_STRING
