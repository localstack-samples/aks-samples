#!/bin/bash

# Variables
source ./00-variables.sh

# Change the current directory to the script's directory
cd "$CURRENT_DIR" || exit

# Build context: the src/ folder (contains VacationPlanner.csproj, Program.cs, Pages/, Services/, wwwroot/).
# The Dockerfile lives alongside this script, so we point -f at it explicitly.
BUILD_CONTEXT="../src"

# Build the docker image
docker build \
	-t $IMAGE_NAME:$IMAGE_TAG \
	-f Dockerfile \
	--build-arg PORT=$PORT \
	$BUILD_CONTEXT
