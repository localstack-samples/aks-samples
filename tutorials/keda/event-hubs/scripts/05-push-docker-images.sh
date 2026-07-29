#!/bin/bash

# Step 5: push both images to the Azure Container Registry attached to the AKS cluster, so the nodes
# can pull them. The registry is created and attached by scripts/01-user-assigned-managed-identity.sh
# (--attach-acr), which is why no image pull secret is needed.

# Variables
source ./00-variables.sh

# Authenticate the Docker client to the registry. This is the step that fails first when the Azure CLI
# is not signed in to the right target: a credential for real Azure left in the CLI's token cache
# cannot log in to the emulated registry even when the rest of the CLI is pointed at the emulator.
# The failure is reported rather than fatal, because the emulated registry also accepts anonymous
# pushes, so the tutorial can still finish; on real Azure a failure here means the push will fail too.
echo "Logging into the [$ACR_NAME] container registry..."
az acr login --name $ACR_NAME --only-show-errors
if [[ $? -ne 0 ]]; then
  echo "Could not log into the [$ACR_NAME] container registry"
  echo "Check that the Azure CLI is signed in to the target you mean to use; continuing, because the emulated registry accepts anonymous pushes"
fi

# Each image must be tagged with the registry's login server. Real Azure returns
# {registry}.azurecr.io and the LocalStack emulator returns a localhost.localstack.cloud host with an
# explicit port, so the value is always read from the registry instead of being hardcoded.
ACR_LOGIN_SERVER=$(az acr show \
  --name $ACR_NAME \
  --query loginServer \
  --output tsv \
  --only-show-errors 2>/dev/null)
if [[ -z $ACR_LOGIN_SERVER ]]; then
  echo "Failed to retrieve the login server of the [$ACR_NAME] container registry"
  exit 1
fi
echo "The login server of the [$ACR_NAME] container registry is [$ACR_LOGIN_SERVER]"

# Tag and push both images
for IMAGE_NAME in $PRODUCER_IMAGE_NAME $CONSUMER_IMAGE_NAME; do
  FULL_IMAGE="${ACR_LOGIN_SERVER}/${IMAGE_NAME}:${IMAGE_TAG}"

  echo "Tagging the [$IMAGE_NAME:$IMAGE_TAG] image as [$FULL_IMAGE]..."
  docker tag ${IMAGE_NAME}:${IMAGE_TAG} $FULL_IMAGE
  if [[ $? -ne 0 ]]; then
    echo "Failed to tag the [$IMAGE_NAME:$IMAGE_TAG] image, run 04-build-docker-images.sh first"
    exit 1
  fi

  echo "Pushing [$FULL_IMAGE]..."
  docker push $FULL_IMAGE
  if [[ $? -eq 0 ]]; then
    echo "[$FULL_IMAGE] was successfully pushed"
  else
    echo "Failed to push [$FULL_IMAGE]"
    exit 1
  fi
done
