#!/bin/bash

# Variables
source ./00-variables.sh

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

# --network=host so endpoints like *.localhost.localstack.cloud resolve to the
# host's loopback (where LocalStack is listening), not the container's.
docker run -it \
	--rm \
	--network=host \
	-e PORT=$PORT \
	-e AZURECOSMOSDB_ENDPOINT="$AZURECOSMOSDB_ENDPOINT" \
	-e AZURECOSMOSDB_PRIMARY_KEY="$AZURECOSMOSDB_PRIMARY_KEY" \
	-e AZURECOSMOSDB_DATABASENAME="$AZURECOSMOSDB_DATABASENAME" \
	-e AZURECOSMOSDB_CONTAINERNAME="$AZURECOSMOSDB_CONTAINERNAME" \
	-e LOGIN_NAME="$LOGIN_NAME" \
	--name "$IMAGE_NAME" \
	"$IMAGE_NAME:$IMAGE_TAG"
