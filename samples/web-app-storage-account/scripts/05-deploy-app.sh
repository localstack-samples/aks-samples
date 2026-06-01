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

# Generate a stable Flask SECRET_KEY (sessions survive pod restarts)
SECRET_KEY=$(openssl rand -hex 32)

# Get the login server for the Azure Container Registry
echo "Getting login server for Azure Container Registry [$ACR_NAME]..."
ACR_LOGIN_SERVER=$(az acr show \
	--name "$ACR_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--query "loginServer" \
	--output tsv \
	--only-show-errors)

if [ -n "$ACR_LOGIN_SERVER" ]; then
	echo "Login server retrieved successfully: $ACR_LOGIN_SERVER"
else
	echo "Failed to retrieve login server for Azure Container Registry [$ACR_NAME]."
	exit 1
fi

FULL_IMAGE="${ACR_LOGIN_SERVER}/${IMAGE_NAME}:${IMAGE_TAG}"

# Create namespace
cat namespace.yml |
yq "(.metadata.name)|="\""$NAMESPACE"\" |
kubectl apply -f -

# Create secret with the storage connection string and Flask secret key
cat secret.yml |
yq "(.metadata.namespace)|="\""$NAMESPACE"\" |
yq "(.data.AZURE_STORAGE_ACCOUNT_CONNECTION_STRING)|="\""$(echo -n $AZURE_STORAGE_ACCOUNT_CONNECTION_STRING | base64 -w0)"\" |
yq "(.data.SECRET_KEY)|="\""$(echo -n $SECRET_KEY | base64 -w0)"\" |
kubectl apply -f -

# Create configmap with environment variables
cat configmap.yml |
yq "(.metadata.namespace)|="\""$NAMESPACE"\" |
yq "(.data.CONTAINER_NAME)|="\""$CONTAINER_NAME"\" |
kubectl apply -f -

# Create deployment
cat deployment.yml |
yq "(.metadata.namespace)|="\""$NAMESPACE"\" |
yq "(.spec.template.spec.containers[0].image)|="\""$FULL_IMAGE"\" |
yq "(.spec.template.spec.containers[0].imagePullPolicy)|="\""$IMAGE_PULL_POLICY"\" |
yq "(.spec.template.spec.containers[0].ports[0].containerPort)|=$PORT" |
kubectl apply -f -

# Create service
cat service.yml |
yq "(.metadata.namespace)|="\""$NAMESPACE"\" |
kubectl apply -f -
