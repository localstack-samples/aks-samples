#!/bin/bash

# Variables
source ./00-variables.sh

# Retrieve the MySQL server FQDN
MYSQL_FQDN_FULL=$(az mysql flexible-server show \
	--name "$MYSQL_SERVER_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--query "fullyQualifiedDomainName" \
	--output tsv)

if [ -z "$MYSQL_FQDN_FULL" ]; then
	echo "Failed to retrieve MySQL server FQDN. Run 01-deploy-resources.sh first."
	exit 1
fi

# Split host:port (LocalStack emulator embeds the dynamic TCP-proxy port in fullyQualifiedDomainName;
# real Azure returns just the bare host, so MYSQL_PORT stays at the value from 00-variables.sh (3306)).
MYSQL_FQDN="${MYSQL_FQDN_FULL%%:*}"
if [[ "$MYSQL_FQDN_FULL" == *:* ]]; then
	MYSQL_PORT="${MYSQL_FQDN_FULL##*:}"
fi

# --network=host so endpoints like *.localhost.localstack.cloud resolve to the
# host's loopback (where LocalStack is listening), not the container's.
docker run -it \
	--rm \
	--network=host \
	-e PORT=$PORT \
	-e MYSQL_HOST="$MYSQL_FQDN" \
	-e MYSQL_PORT="$MYSQL_PORT" \
	-e MYSQL_DATABASE="$MYSQL_DATABASE_NAME" \
	-e MYSQL_USER="$MYSQL_USER_NAME" \
	-e MYSQL_PASSWORD="$MYSQL_USER_PASSWORD" \
	-e MYSQL_SSL="$MYSQL_SSL" \
	-e LOGIN_NAME="$LOGIN_NAME" \
	--name "$IMAGE_NAME" \
	"$IMAGE_NAME:$IMAGE_TAG"
