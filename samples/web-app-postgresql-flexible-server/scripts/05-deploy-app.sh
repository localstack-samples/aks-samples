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

# Generate a stable Flask SECRET_KEY (sessions survive pod restarts)
FLASK_SECRET_KEY=$(openssl rand -hex 32)

# Get the login server for the Azure Container Registry
echo "Getting login server for Azure Container Registry [$ACR_NAME]..."
ACR_LOGIN_SERVER=$(az acr show \
	--name "$ACR_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--query "loginServer" \
	--output tsv \
	--only-show-errors)

if [ -n "$ACR_LOGIN_SERVER" ]; then
	echo "Login server retrieved successfully: $ACR_LOGIN_SERVER"
else
	echo "Failed to retrieve login server for Azure Container Registry [$ACR_NAME]."
	exit 1
fi

FULL_IMAGE="${ACR_LOGIN_SERVER}/${IMAGE_NAME}:${IMAGE_TAG}"

# Create namespace
cat namespace.yml |
yq "(.metadata.name)|="\""$NAMESPACE"\" |
kubectl apply -f -

# Create secret with the PostgreSQL password and the Flask secret key
cat secret.yml |
yq "(.metadata.namespace)|="\""$NAMESPACE"\" |
yq "(.data.PG_PASSWORD)|="\""$(echo -n $PG_USER_PASSWORD | base64 -w0)"\" |
yq "(.data.SECRET_KEY)|="\""$(echo -n $FLASK_SECRET_KEY | base64 -w0)"\" |
kubectl apply -f -

# Create configmap with environment variables
cat configmap.yml |
yq "(.metadata.namespace)|="\""$NAMESPACE"\" |
yq "(.data.PG_HOST)|="\""$PG_FQDN"\" |
yq "(.data.PG_PORT)|="\""$PG_PORT"\" |
yq "(.data.PG_DATABASE)|="\""$PG_DATABASE_NAME"\" |
yq "(.data.PG_USER)|="\""$PG_USER_NAME"\" |
yq "(.data.LOGIN_NAME)|="\""$LOGIN_NAME"\" |
kubectl apply -f -

# Create deployment
cat deployment.yml |
yq "(.metadata.namespace)|="\""$NAMESPACE"\" |
yq "(.spec.template.spec.containers[0].image)|="\""$FULL_IMAGE"\" |
yq "(.spec.template.spec.containers[0].imagePullPolicy)|="\""$IMAGE_PULL_POLICY"\" |
yq "(.spec.template.spec.containers[0].ports[0].containerPort)|=$PORT" |
kubectl apply -f -

# Create service
cat service.yml |
yq "(.metadata.namespace)|="\""$NAMESPACE"\" |
kubectl apply -f -
