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

# When running against LocalStack, fetch its root CA so the container can verify
# the cosmos endpoint's TLS chain (cert is signed by LocalStack's root CA — see
# localstack-pro-azure/.../cosmos/nosql/emulator.py default_cert_store().get_or_create).
CA_MOUNT_ARGS=()
EXTRA_ENV_ARGS=()
if [ -n "$LOCALSTACK_URL" ]; then
	echo "Fetching LocalStack root CA from $LOCALSTACK_URL..."

	# Fetch the target CA URL
	CA_URL=$(curl -sf "$LOCALSTACK_URL/_localstack/certs" | jq -r .ca.url)

	if [ -z "$CA_URL" ] || [ "$CA_URL" = "null" ]; then
		echo "Error: Failed to extract CA URL from LocalStack endpoint." >&2
		exit 1
	fi

	# Fetch the actual PEM payload
	PEM_DATA=$(curl -sf "$CA_URL")

	if [ -z "$PEM_DATA" ]; then
		echo "Error: Retrieved empty CA certificate payload." >&2
		exit 1
	fi

	# Write next to the script (in $CURRENT_DIR exported by 00-variables.sh). Avoid /tmp:
	# on rootless / Docker Desktop / WSL2 setups, /tmp may be outside the daemon's reachable
	# filesystem — in that case `-v` silently creates an empty directory at the destination
	# instead of bind-mounting the file, and SSL_CERT_FILE ends up pointing at a dir.
	HOST_CA_PATH="$CURRENT_DIR/.localstack-ca.crt"
	# Remove the CA file on script exit (Ctrl-C, normal exit, error) so we don't leave
	# it lying next to the script after the container stops.
	trap 'rm -f "$HOST_CA_PATH"' EXIT
	printf '%s\n' "$PEM_DATA" > "$HOST_CA_PATH"
	# Container runs as a non-root `app` user; make sure it can read the bind-mounted file.
	chmod 644 "$HOST_CA_PATH"
	echo "LocalStack root CA written to $HOST_CA_PATH"
	# Use `--mount type=bind` instead of `-v`: if the source is unreachable the daemon
	# errors out instead of creating a phantom empty directory at the target.
	CA_MOUNT_ARGS=(--mount "type=bind,source=$HOST_CA_PATH,target=/etc/ssl/certs/localstack.crt,readonly")
	EXTRA_ENV_ARGS=(-e SSL_CERT_FILE=/etc/ssl/certs/localstack.crt)
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
	"${EXTRA_ENV_ARGS[@]}" \
	"${CA_MOUNT_ARGS[@]}" \
	--name "$IMAGE_NAME" \
	"$IMAGE_NAME:$IMAGE_TAG"
