#!/bin/bash

# Variables
source ./00-variables.sh

# Change the current directory to the script's directory
cd "$CURRENT_DIR" || exit

# Local smoke test: no Azure resource is involved. In the cluster the app writes to an Azure file
# share mounted by the Azure Files CSI driver, and here it writes to a directory on the host mounted
# at the same path, which is all the app knows about its storage.
ACTIVITIES_HOST_DIR="${TMPDIR:-/tmp}/${IMAGE_NAME}-activities"

echo "Creating the local activities directory [$ACTIVITIES_HOST_DIR]..."
mkdir -p "$ACTIVITIES_HOST_DIR"

if [[ $? != 0 ]]; then
	echo "Failed to create the local activities directory [$ACTIVITIES_HOST_DIR]."
	exit 1
fi

# The container runs as uid 1000, which is not necessarily the owner of a directory on the host
chmod 0777 "$ACTIVITIES_HOST_DIR"

if [[ $? != 0 ]]; then
	echo "Failed to make the local activities directory [$ACTIVITIES_HOST_DIR] writable."
	exit 1
fi

echo "The activities are stored as text files in [$ACTIVITIES_HOST_DIR]."

# --network=host so endpoints like *.localhost.localstack.cloud resolve to the
# host's loopback (where LocalStack is listening), not the container's.
docker run -it \
	--rm \
	--network=host \
	-e PORT=$PORT \
	-e ACTIVITIES_DIR="$ACTIVITIES_DIR" \
	-v "$ACTIVITIES_HOST_DIR:$ACTIVITIES_DIR" \
	--name "$IMAGE_NAME" \
	"$IMAGE_NAME:$IMAGE_TAG"
