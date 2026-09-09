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

# Generate a stable Flask SECRET_KEY (sessions survive pod restarts)
# Reuse the key already stored in the Secret, when there is one. A new key on every run would leave the
# running pods signing with the old one, so their sessions, flash messages and antiforgery tokens break
# across replicas until every pod has restarted.
FLASK_SECRET_KEY=$(kubectl get secret vacation-planner-mysql-secrets --namespace $NAMESPACE --output jsonpath='{.data.SECRET_KEY}' 2>/dev/null | base64 --decode 2>/dev/null)

if [[ -z $FLASK_SECRET_KEY ]]; then
	FLASK_SECRET_KEY=$(openssl rand -hex 32)
fi

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

# Create secret with the MySQL password and the Flask secret key
cat secret.yml |
yq "(.metadata.namespace)|="\""$NAMESPACE"\" |
yq "(.data.MYSQL_PASSWORD)|="\""$(echo -n $MYSQL_USER_PASSWORD | base64 -w0)"\" |
yq "(.data.SECRET_KEY)|="\""$(echo -n $FLASK_SECRET_KEY | base64 -w0)"\" |
kubectl apply -f -

# Create configmap with environment variables
cat configmap.yml |
yq "(.metadata.namespace)|="\""$NAMESPACE"\" |
yq "(.data.MYSQL_HOST)|="\""$MYSQL_FQDN"\" |
yq "(.data.MYSQL_PORT)|="\""$MYSQL_PORT"\" |
yq "(.data.MYSQL_DATABASE)|="\""$MYSQL_DATABASE_NAME"\" |
yq "(.data.MYSQL_USER)|="\""$MYSQL_USER_NAME"\" |
yq "(.data.MYSQL_SSL)|="\""$MYSQL_SSL"\" |
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

# Roll the pods so a re-push of the same image tag actually takes effect: the pod template is unchanged,
# so kubectl apply reports no change and leaves the running pods on the image they started with.
kubectl rollout restart deployment/$DEPLOYMENT_NAME --namespace $NAMESPACE
