#!/bin/bash

# Variables
source ./00-variables.sh

# Change the current directory to the script's directory
cd "$CURRENT_DIR" || exit

# Read one setting from the App Configuration store. --resolve-keyvault makes the CLI follow a Key Vault
# reference and return the secret behind it, so the same call works for a plain key-value and for a
# reference. Reading the settings from the store rather than from 00-variables.sh means this local run
# proves the store's contents, not just that the image starts.
# $1: the key
resolve_setting() {
	local key=$1
	local value

	value=$(az appconfig kv list \
		--name "$APP_CONFIG_NAME" \
		--key "$key" \
		--resolve-keyvault \
		--query "[0].value" \
		--output tsv \
		--only-show-errors 2>/dev/null)

	if [[ -z $value ]]; then
		echo "Failed to resolve the [$key] key from the [$APP_CONFIG_NAME] App Configuration store." >&2
		echo "Run 01-deploy-resources.sh first, and make sure you can read the key vault." >&2
		exit 1
	fi

	echo "$value"
}

echo "Resolving the application settings from the [$APP_CONFIG_NAME] App Configuration store..."

PG_HOST_VALUE=$(resolve_setting "PG_HOST")
PG_PORT_VALUE=$(resolve_setting "PG_PORT")
PG_DATABASE_VALUE=$(resolve_setting "PG_DATABASE")
LOGIN_NAME_VALUE=$(resolve_setting "LOGIN_NAME")
CONFIG_VERSION_VALUE=$(resolve_setting "$SENTINEL_KEY")
PG_USER_VALUE=$(resolve_setting "PG_USER")
PG_PASSWORD_VALUE=$(resolve_setting "PG_PASSWORD")
SECRET_KEY_VALUE=$(resolve_setting "SECRET_KEY")

# The credentials are resolved but never echoed.
echo "PG_HOST=$PG_HOST_VALUE PG_PORT=$PG_PORT_VALUE PG_DATABASE=$PG_DATABASE_VALUE LOGIN_NAME=$LOGIN_NAME_VALUE $SENTINEL_KEY=$CONFIG_VERSION_VALUE"
echo "PG_USER, PG_PASSWORD and SECRET_KEY resolved from Key Vault references"

# --network=host so endpoints like *.localhost.localstack.cloud resolve to the
# host's loopback (where LocalStack is listening), not the container's.
docker run -it \
	--rm \
	--network=host \
	-e PORT="$PORT" \
	-e PG_HOST="$PG_HOST_VALUE" \
	-e PG_PORT="$PG_PORT_VALUE" \
	-e PG_DATABASE="$PG_DATABASE_VALUE" \
	-e PG_USER="$PG_USER_VALUE" \
	-e PG_PASSWORD="$PG_PASSWORD_VALUE" \
	-e LOGIN_NAME="$LOGIN_NAME_VALUE" \
	-e SECRET_KEY="$SECRET_KEY_VALUE" \
	-e CONFIG_VERSION="$CONFIG_VERSION_VALUE" \
	--name "$IMAGE_NAME" \
	"$IMAGE_NAME:$IMAGE_TAG"
