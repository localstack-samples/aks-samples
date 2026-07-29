#!/bin/bash

# Step 4: build the producer and consumer container images from the sources under ../src. Each app
# has its own Dockerfile next to its code, so the build context is the app folder itself.

# Variables
source ./00-variables.sh

# Build the producer image
echo "Building the [$PRODUCER_IMAGE_NAME:$IMAGE_TAG] image from [../src/producer]..."
docker build \
  --tag ${PRODUCER_IMAGE_NAME}:${IMAGE_TAG} \
  --file ../src/producer/Dockerfile \
  ../src/producer

if [[ $? -eq 0 ]]; then
  echo "The [$PRODUCER_IMAGE_NAME:$IMAGE_TAG] image was successfully built"
else
  echo "Failed to build the [$PRODUCER_IMAGE_NAME:$IMAGE_TAG] image"
  exit 1
fi

# Build the consumer image
echo "Building the [$CONSUMER_IMAGE_NAME:$IMAGE_TAG] image from [../src/consumer]..."
docker build \
  --tag ${CONSUMER_IMAGE_NAME}:${IMAGE_TAG} \
  --file ../src/consumer/Dockerfile \
  ../src/consumer

if [[ $? -eq 0 ]]; then
  echo "The [$CONSUMER_IMAGE_NAME:$IMAGE_TAG] image was successfully built"
else
  echo "Failed to build the [$CONSUMER_IMAGE_NAME:$IMAGE_TAG] image"
  exit 1
fi
