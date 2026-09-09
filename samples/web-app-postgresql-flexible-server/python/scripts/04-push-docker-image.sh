#!/bin/bash

# Variables
source ./00-variables.sh

# Login to ACR
echo "Logging into Azure Container Registry [$ACR_NAME]..."
az acr login --name $ACR_NAME

# Retrieve ACR login server. Each container image needs to be tagged with the loginServer name of the registry.
ACR_LOGIN_SERVER=$(az acr show --name $ACR_NAME --query loginServer --output tsv)

if [ $? -eq 0 ]; then
	echo "Logged into Azure Container Registry [$ACR_NAME] successfully."
else
	echo "Failed to log into Azure Container Registry [$ACR_NAME]."
	exit 1
fi

FULL_IMAGE="${ACR_LOGIN_SERVER}/${IMAGE_NAME}:${IMAGE_TAG}"

# Tag the local image with the loginServer of ACR
docker tag ${IMAGE_NAME,,}:$IMAGE_TAG $ACR_LOGIN_SERVER/${IMAGE_NAME,,}:$IMAGE_TAG

if [ $? -eq 0 ]; then
	echo "Docker image [$IMAGE_NAME] tagged as [$FULL_IMAGE] successfully."
else
	echo "Failed to tag Docker image [$IMAGE_NAME] as [$FULL_IMAGE]."
	exit 1
fi

# Push the container image to ACR
docker push $ACR_LOGIN_SERVER/${IMAGE_NAME,,}:$IMAGE_TAG

if [ $? -eq 0 ]; then
	echo "Docker image [$FULL_IMAGE] pushed to ACR successfully."
else
	echo "Failed to push Docker image [$FULL_IMAGE] to ACR."
	exit 1
fi
