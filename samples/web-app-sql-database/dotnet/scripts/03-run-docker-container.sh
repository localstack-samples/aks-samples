#!/bin/bash

# Variables
source ./00-variables.sh

# Retrieve the SQL server FQDN
SQL_SERVER_FQDN=$(az sql server show \
	--name "$SQL_SERVER_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--query "fullyQualifiedDomainName" \
	--output tsv)

if [ -z "$SQL_SERVER_FQDN" ]; then
	echo "Failed to retrieve SQL server FQDN. Run 01-deploy-resources.sh first."
	exit 1
fi

# --network=host so endpoints like *.localhost.localstack.cloud resolve to the
# host's loopback (where LocalStack is listening), not the container's.
docker run -it \
	--rm \
	--network=host \
	-e PORT=$PORT \
	-e SQL_SERVER="$SQL_SERVER_FQDN" \
	-e SQL_DATABASE="$SQL_DATABASE_NAME" \
	-e SQL_USERNAME="$DATABASE_USER_NAME" \
	-e SQL_PASSWORD="$DATABASE_USER_PASSWORD" \
	-e LOGIN_NAME="$LOGIN_NAME" \
	--name "$IMAGE_NAME" \
	"$IMAGE_NAME:$IMAGE_TAG"
