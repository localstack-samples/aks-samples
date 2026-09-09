#!/bin/bash

# Variables
source ./00-variables.sh

# Retrieve the PostgreSQL server FQDN
PG_FQDN_FULL=$(az postgres flexible-server show \
	--name "$PG_SERVER_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--query "fullyQualifiedDomainName" \
	--output tsv)

if [ -z "$PG_FQDN_FULL" ]; then
	echo "Failed to retrieve PostgreSQL server FQDN. Run 01-deploy-resources.sh first."
	exit 1
fi

# Split host:port (LocalStack emulator embeds the dynamic TCP-proxy port in fullyQualifiedDomainName;
# real Azure returns just the bare host).
PG_FQDN="${PG_FQDN_FULL%%:*}"
if [[ "$PG_FQDN_FULL" == *:* ]]; then
	PG_PORT="${PG_FQDN_FULL##*:}"
fi

# --network=host so endpoints like *.localhost.localstack.cloud resolve to the
# host's loopback (where LocalStack is listening), not the container's.
docker run -it \
	--rm \
	--network=host \
	-e PORT=$PORT \
	-e PG_HOST="$PG_FQDN" \
	-e PG_PORT="$PG_PORT" \
	-e PG_DATABASE="$PG_DATABASE_NAME" \
	-e PG_USER="$PG_USER_NAME" \
	-e PG_PASSWORD="$PG_USER_PASSWORD" \
	-e LOGIN_NAME="$LOGIN_NAME" \
	--name "$IMAGE_NAME" \
	"$IMAGE_NAME:$IMAGE_TAG"
