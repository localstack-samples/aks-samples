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

# Generate a stable SECRET_KEY shared by all replicas: the app derives its Data Protection key ring from it,
# so antiforgery tokens and flash messages are valid on every replica and survive pod restarts
# Reuse the key already stored in the Secret, when there is one. A new key on every run would leave the
# running pods signing with the old one, so their sessions, flash messages and antiforgery tokens break
# across replicas until every pod has restarted.
SECRET_KEY=$(kubectl get secret $SECRET_NAME --namespace $NAMESPACE --output jsonpath='{.data.SECRET_KEY}' 2>/dev/null | base64 --decode 2>/dev/null)

if [[ -z $SECRET_KEY ]]; then
	SECRET_KEY=$(openssl rand -hex 32)
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

# Create the LocalStack root CA configmap so the app can verify the cosmos endpoint's
# TLS chain. The cert is signed by LocalStack's root CA at emulator startup — see
# localstack-pro-azure/.../cosmos/nosql/emulator.py default_cert_store().get_or_create.
# Skipped when LOCALSTACK_URL is empty (real-Azure mode).
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

	# Generate and apply the configmap from a literal string (avoid issues with newlines in the PEM data when using --from-file or --from-env-file)
	kubectl -n "$NAMESPACE" create configmap localstack-ca \
		--from-literal=localstack.crt="$PEM_DATA" \
		--dry-run=client -o yaml | kubectl apply -f -
fi

# Create secret with the Cosmos DB primary key and SECRET_KEY
cat secret.yml |
yq "(.metadata.namespace)|="\""$NAMESPACE"\" |
yq "(.data.AZURECOSMOSDB_PRIMARY_KEY)|="\""$(echo -n $AZURECOSMOSDB_PRIMARY_KEY | base64 -w0)"\" |
yq "(.data.SECRET_KEY)|="\""$(echo -n $SECRET_KEY | base64 -w0)"\" |
kubectl apply -f -

# Create configmap with environment variables
cat configmap.yml |
yq "(.metadata.namespace)|="\""$NAMESPACE"\" |
yq "(.data.AZURECOSMOSDB_ENDPOINT)|="\""$AZURECOSMOSDB_ENDPOINT"\" |
yq "(.data.AZURECOSMOSDB_DATABASENAME)|="\""$AZURECOSMOSDB_DATABASENAME"\" |
yq "(.data.AZURECOSMOSDB_CONTAINERNAME)|="\""$AZURECOSMOSDB_CONTAINERNAME"\" |
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

# Wait for the rollout so a pod stuck in ImagePullBackOff or CrashLoopBackOff is reported here, not discovered later
echo "Waiting for deployment [$DEPLOYMENT_NAME] to roll out..."
if kubectl rollout status deployment/$DEPLOYMENT_NAME -n $NAMESPACE --timeout=600s; then
	echo "Deployment [$DEPLOYMENT_NAME] is ready. To reach the web app, run:"
	echo "  kubectl port-forward service/$SERVICE_NAME 8080:80 -n $NAMESPACE"
	echo "and browse to http://localhost:8080 (health: http://localhost:8080/health)."
else
	echo "Deployment [$DEPLOYMENT_NAME] did not become ready. Inspect it with:"
	echo "  kubectl get pods -n $NAMESPACE"
	echo "  kubectl describe pod -n $NAMESPACE --selector app=$DEPLOYMENT_NAME"
	exit 1
fi
