#!/bin/bash

# Variables
source ./00-variables.sh

# Retrieve the Cosmos DB MongoDB connection string
echo "Retrieving Cosmos DB connection string for [$COSMOSDB_ACCOUNT_NAME]..."
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

# --network=host so endpoints like *.localhost.localstack.cloud resolve to the
# host's loopback (where LocalStack is listening), not the container's.
docker run -it \
	--rm \
	--network=host \
	-e PORT=$PORT \
	-e COSMOSDB_CONNECTION_STRING="$COSMOSDB_CONNECTION_STRING" \
	-e COSMOSDB_DATABASE_NAME="$COSMOSDB_DATABASE_NAME" \
	-e COSMOSDB_COLLECTION_NAME="$COSMOSDB_COLLECTION_NAME" \
	-e LOGIN_NAME="$LOGIN_NAME" \
	--name "$IMAGE_NAME" \
	"$IMAGE_NAME:$IMAGE_TAG"
