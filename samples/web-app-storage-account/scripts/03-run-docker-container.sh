#!/bin/bash

# Variables
source ./00-variables.sh

# Retrieve the storage account connection string
echo "Retrieving storage account connection string for [$STORAGE_ACCOUNT_NAME]..."
AZURE_STORAGE_ACCOUNT_CONNECTION_STRING=$(az storage account show-connection-string \
	--name $STORAGE_ACCOUNT_NAME \
	--resource-group $RESOURCE_GROUP_NAME \
	--query "connectionString" \
	--output tsv \
	--only-show-errors)

if [ -n "$AZURE_STORAGE_ACCOUNT_CONNECTION_STRING" ]; then
	echo "Storage account connection string retrieved successfully."
else
	echo "Failed to retrieve storage account connection string."
	exit 1
fi

# --network=host so endpoints like *.localhost.localstack.cloud resolve to the
# host's loopback (where LocalStack is listening), not the container's.
docker run -it \
	--rm \
	--network=host \
	-e PORT=$PORT \
	-e AZURE_STORAGE_ACCOUNT_CONNECTION_STRING="$AZURE_STORAGE_ACCOUNT_CONNECTION_STRING" \
	-e CONTAINER_NAME="$CONTAINER_NAME" \
	--name "$IMAGE_NAME" \
	"$IMAGE_NAME:$IMAGE_TAG"
