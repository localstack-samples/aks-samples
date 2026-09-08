#!/bin/bash

# Variables
source ./00-variables.sh

# Generate a stable SECRET_KEY shared by all replicas: the app derives its Data Protection key ring from it,
# so antiforgery tokens and flash messages are valid on every replica and survive pod restarts
SECRET_KEY=$(openssl rand -hex 32)

# Optional client secret for the ClientSecretCredential auth path.
# Leave empty when using Microsoft Entra Workload ID (the recommended option).
AZURE_CLIENT_SECRET="${AZURE_CLIENT_SECRET:-}"

# Get the storage account blob primary endpoint
AZURE_STORAGE_ACCOUNT_URL=$(az storage account show \
	--name $STORAGE_ACCOUNT_NAME \
	--resource-group $RESOURCE_GROUP_NAME \
	--query "primaryEndpoints.blob" \
	--output tsv \
	--only-show-errors)

if [ -n "$AZURE_STORAGE_ACCOUNT_URL" ]; then
	echo "Storage account blob primary endpoint retrieved successfully: $AZURE_STORAGE_ACCOUNT_URL"
else
	echo "Failed to retrieve storage account blob primary endpoint."
	exit 1
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

# Check if the service account already exists
RESULT=$(kubectl get sa -n $NAMESPACE -o 'jsonpath={.items[?(@.metadata.name=="'$SERVICE_ACCOUNT_NAME'")].metadata.name}')

if [[ -n $RESULT ]]; then
  echo "[$SERVICE_ACCOUNT_NAME] service account already exists"
else
  # Retrieve the resource id of the user-assigned managed identity
  echo "Retrieving clientId for [$MANAGED_IDENTITY_NAME] managed identity..."
  CLIENT_ID=$(az identity show \
    --name $MANAGED_IDENTITY_NAME \
    --resource-group $RESOURCE_GROUP_NAME \
    --query clientId \
    --output tsv)

  if [[ -n $CLIENT_ID ]]; then
    echo "[$CLIENT_ID] clientId  for the [$MANAGED_IDENTITY_NAME] managed identity successfully retrieved"
  else
    echo "Failed to retrieve clientId for the [$MANAGED_IDENTITY_NAME] managed identity"
    exit
  fi

  # Create the service account
  echo "[$SERVICE_ACCOUNT_NAME] service account does not exist"
  echo "Creating [$SERVICE_ACCOUNT_NAME] service account..."
  cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  annotations:
    azure.workload.identity/client-id: $CLIENT_ID
    azure.workload.identity/tenant-id: $TENANT_ID
  labels:
    azure.workload.identity/use: "true"
  name: $SERVICE_ACCOUNT_NAME
  namespace: $NAMESPACE
EOF
fi

# Show service account YAML manifest
echo "Service Account YAML manifest"
echo "-----------------------------"
kubectl get sa $SERVICE_ACCOUNT_NAME -n $NAMESPACE -o yaml

# Check if the federated identity credential already exists
echo "Checking if [$FEDERATED_IDENTITY_NAME] federated identity credential actually exists in the [$RESOURCE_GROUP_NAME] resource group..."

az identity federated-credential show \
  --name $FEDERATED_IDENTITY_NAME \
  --resource-group $RESOURCE_GROUP_NAME \
  --identity-name $MANAGED_IDENTITY_NAME &>/dev/null

if [[ $? != 0 ]]; then
  echo "No [$FEDERATED_IDENTITY_NAME] federated identity credential actually exists in the [$RESOURCE_GROUP_NAME] resource group"

  # Get the OIDC Issuer URL
  OIDC_ISSUER_URL="$(az aks show \
    --only-show-errors \
    --name $AKS_CLUSTER_NAME \
    --resource-group $RESOURCE_GROUP_NAME \
    --query oidcIssuerProfile.issuerUrl \
    --output tsv)"

  # Show OIDC Issuer URL
  if [[ -n $OIDC_ISSUER_URL ]]; then
    echo "The OIDC Issuer URL of the $AKS_CLUSTER_NAME cluster is $OIDC_ISSUER_URL"
  fi

  echo "Creating [$FEDERATED_IDENTITY_NAME] federated identity credential in the [$RESOURCE_GROUP_NAME] resource group..."

  # Establish the federated identity credential between the managed identity, the service account issuer, and the subject.
  az identity federated-credential create \
    --name $FEDERATED_IDENTITY_NAME \
    --identity-name $MANAGED_IDENTITY_NAME \
    --resource-group $RESOURCE_GROUP_NAME \
    --issuer $OIDC_ISSUER_URL \
    --subject system:serviceaccount:$NAMESPACE:$SERVICE_ACCOUNT_NAME 1>/dev/null

  if [[ $? == 0 ]]; then
    echo "[$FEDERATED_IDENTITY_NAME] federated identity credential successfully created in the [$RESOURCE_GROUP_NAME] resource group"
  else
    echo "Failed to create [$FEDERATED_IDENTITY_NAME] federated identity credential in the [$RESOURCE_GROUP_NAME] resource group"
    exit
  fi
else
  echo "[$FEDERATED_IDENTITY_NAME] federated identity credential already exists in the [$RESOURCE_GROUP_NAME] resource group"
fi

# Create secret with the storage connection string, client secret and SECRET_KEY
cat secret.yml |
yq "(.metadata.namespace)|="\""$NAMESPACE"\" |
yq "(.data.AZURE_STORAGE_ACCOUNT_CONNECTION_STRING)|="\""$(echo -n $AZURE_STORAGE_ACCOUNT_CONNECTION_STRING | base64 -w0)"\" |
yq "(.data.AZURE_CLIENT_SECRET)|="\""$(echo -n $AZURE_CLIENT_SECRET | base64 -w0)"\" |
yq "(.data.SECRET_KEY)|="\""$(echo -n $SECRET_KEY | base64 -w0)"\" |
kubectl apply -f -

# Retrieve the clientId of the user-assigned managed identity for the configmap
echo "Retrieving clientId for [$MANAGED_IDENTITY_NAME] managed identity..."
CLIENT_ID=$(az identity show \
  --name $MANAGED_IDENTITY_NAME \
  --resource-group $RESOURCE_GROUP_NAME \
  --query clientId \
  --output tsv)

if [[ -z $CLIENT_ID ]]; then
  echo "Failed to retrieve clientId for the [$MANAGED_IDENTITY_NAME] managed identity"
  exit 1
fi

# Create configmap with environment variables
cat configmap.yml |
yq "(.metadata.namespace)|="\""$NAMESPACE"\" |
yq "(.data.CONTAINER_NAME)|="\""$CONTAINER_NAME"\" |
yq "(.data.AZURE_CLIENT_ID)|="\""$CLIENT_ID"\" |
yq "(.data.AZURE_TENANT_ID)|="\""$TENANT_ID"\" |
yq "(.data.AZURE_STORAGE_ACCOUNT_URL)|="\""$AZURE_STORAGE_ACCOUNT_URL"\" |
kubectl apply -f -

if [[ $DEPLOY_GATEWAY == "true" ]]; then
	# Create Issuer for Gateway API HTTP-01 solver (before gateway to avoid race condition)
	cat issuer.yml |
	yq "(.spec.acme.solvers[0].http01.gatewayHTTPRoute.parentRefs[0].name)|=\"$NAME\"" |
	yq "(.spec.acme.solvers[0].http01.gatewayHTTPRoute.parentRefs[0].namespace)|=\"$NAMESPACE\"" |
	kubectl apply -f -
fi

# Create deployment
cat deployment.yml |
yq "(.metadata.namespace)|="\""$NAMESPACE"\" |
yq "(.spec.template.spec.containers[0].image)|="\""$FULL_IMAGE"\" |
yq "(.spec.template.spec.containers[0].imagePullPolicy)|="\""$IMAGE_PULL_POLICY"\" |
yq "(.spec.template.spec.serviceAccountName)|="\""$SERVICE_ACCOUNT_NAME"\" |
yq "(.spec.template.spec.containers[0].ports[0].containerPort)|=$PORT" |
kubectl apply -f -

# Create service
cat service.yml |
yq "(.metadata.namespace)|="\""$NAMESPACE"\" |
kubectl apply -f -

if [[ $DEPLOY_GATEWAY == "true" ]]; then
	# Create gateway
	cat gateway.yml |
	yq "(.metadata.namespace)|="\""$NAMESPACE"\" |
	yq "(.spec.listeners[0].hostname)|="\""$SUBDOMAIN.$DNS_ZONE_NAME"\" |
	yq "(.spec.listeners[1].hostname)|="\""$SUBDOMAIN.$DNS_ZONE_NAME"\" |
	kubectl apply -f -

	# Create httproute
	cat httproute.yml |
	yq "(.metadata.namespace)|="\""$NAMESPACE"\" |
	yq "(.spec.hostnames[0])|="\""$SUBDOMAIN.$DNS_ZONE_NAME"\" |
	kubectl apply -f -

	# Retrieve the public IP address from the gateway
	echo -n "Retrieving the external IP address from the [$NAME] gateway..."
	while [[ -z $PUBLIC_IP_ADDRESS ]]; do
		PUBLIC_IP_ADDRESS=$(kubectl get gateway $NAME -n $NAMESPACE -o jsonpath='{.status.addresses[0].value}')
		if [[ -n $PUBLIC_IP_ADDRESS ]]; then
			echo ''
			break
		else
			echo -n "." # Progress indicator
			sleep 1
		fi
	done

	if [[ -n $PUBLIC_IP_ADDRESS ]]; then
		echo "[$PUBLIC_IP_ADDRESS] external IP address successfully retrieved from the [$NAME] gateway"
	else
		echo "Failed to retrieve the external IP address from the [$NAME] gateway"
		exit
	fi

	# Check if an A record for todolist subdomain exists in the DNS Zone
	echo "Retrieving the A record for the [$SUBDOMAIN] subdomain from the [$DNS_ZONE_NAME] DNS zone..."
	IPV4_ADDRESS=$(az network dns record-set a list \
		--zone-name $DNS_ZONE_NAME \
		--resource-group $DNS_ZONE_RESOURCE_GROUP_NAME \
		--query "[?name=='$SUBDOMAIN'].ARecords[].ipv4Address" \
		--output tsv \
		--only-show-errors)

	if [[ -n $IPV4_ADDRESS ]]; then
		echo "An A record already exists in [$DNS_ZONE_NAME] DNS zone for the [$SUBDOMAIN] subdomain with [$IPV4_ADDRESS] IP address"

		if [[ $IPV4_ADDRESS == "$PUBLIC_IP_ADDRESS" ]]; then
			echo "The [$IPV4_ADDRESS] ip address of the existing A record is equal to the ip address of the [$NAME] gateway"
			echo "No additional step is required"
			exit
		else
			echo "The [$IPV4_ADDRESS] ip address of the existing A record is different than the ip address of the [$NAME] gateway"
		fi

		# Retrieving name of the record set relative to the zone
		echo "Retrieving the name of the record set relative to the [$DNS_ZONE_NAME] zone..."

		RECORD_SET_NAME=$(az network dns record-set a list \
			--zone-name $DNS_ZONE_NAME \
			--resource-group $DNS_ZONE_RESOURCE_GROUP_NAME \
			--query "[?name=='$SUBDOMAIN'].name" \
			--output tsv \
			--only-show-errors 2>/dev/null)

		if [[ -n $RECORD_SET_NAME ]]; then
			echo "[$RECORD_SET_NAME] record set name successfully retrieved"
		else
			echo "Failed to retrieve the name of the record set relative to the [$DNS_ZONE_NAME] zone"
			exit
		fi

		# Remove the a record
		echo "Removing the A record from the record set relative to the [$DNS_ZONE_NAME] zone..."

		az network dns record-set a remove-record \
			--ipv4-address "$IPV4_ADDRESS" \
			--record-set-name "$RECORD_SET_NAME" \
			--zone-name "$DNS_ZONE_NAME" \
			--resource-group "$DNS_ZONE_RESOURCE_GROUP_NAME" \
			--only-show-errors 2>/dev/null

		if [[ $? == 0 ]]; then
			echo "[$IPV4_ADDRESS] ip address successfully removed from the [$RECORD_SET_NAME] record set"
		else
			echo "Failed to remove the [$IPV4_ADDRESS] ip address from the [$RECORD_SET_NAME] record set"
			exit
		fi
	fi

	# Create the a record
	echo "Creating an A record in [$DNS_ZONE_NAME] DNS zone for the [$SUBDOMAIN] subdomain with [$PUBLIC_IP_ADDRESS] IP address..."
	az network dns record-set a add-record \
		--zone-name "$DNS_ZONE_NAME" \
		--resource-group "$DNS_ZONE_RESOURCE_GROUP_NAME" \
		--record-set-name "$SUBDOMAIN" \
		--ipv4-address "$PUBLIC_IP_ADDRESS" \
		--only-show-errors 1>/dev/null

	if [[ $? == 0 ]]; then
		echo "A record for the [$SUBDOMAIN] subdomain with [$PUBLIC_IP_ADDRESS] IP address successfully created in [$DNS_ZONE_NAME] DNS zone"
	else
		echo "Failed to create an A record for the [$SUBDOMAIN] subdomain with [$PUBLIC_IP_ADDRESS] IP address in [$DNS_ZONE_NAME] DNS zone"
	fi
fi

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
