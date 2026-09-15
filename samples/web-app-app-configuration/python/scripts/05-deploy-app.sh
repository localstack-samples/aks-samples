#!/bin/bash

# Variables
source ./00-variables.sh

# Change the current directory to the script's directory
cd "$CURRENT_DIR" || exit

#********************************************
# Container image
#********************************************

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

FULL_IMAGE="${ACR_LOGIN_SERVER}/${IMAGE_NAME,,}:${IMAGE_TAG}"

#********************************************
# Namespace
#********************************************

cat namespace.yml |
	yq "(.metadata.name)|="\""$NAMESPACE"\" |
	kubectl apply -f -

#********************************************
# Service account
#********************************************

# The client id and tenant id of the managed identity, read back from Azure rather than stored anywhere.
CLIENT_ID=$(az identity show \
	--name "$MANAGED_IDENTITY_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--query clientId \
	--output tsv \
	--only-show-errors)

if [[ -z $CLIENT_ID ]]; then
	echo "Failed to retrieve the clientId of the [$MANAGED_IDENTITY_NAME] managed identity. Run 01-deploy-resources.sh first."
	exit 1
fi

# An empty tenant id produces a service account that looks correct and fails the token exchange at
# runtime, so it is worth an explicit check.
if [[ -z $TENANT_ID ]]; then
	echo "Failed to resolve the tenant id from [az account show]. Sign in again and re-run."
	exit 1
fi

echo "Applying the [$SERVICE_ACCOUNT_NAME] service account with clientId [$CLIENT_ID] and tenantId [$TENANT_ID]..."

# Applied on every run, with no "already exists" short-circuit: if the managed identity was re-created,
# its client id changed, and a stale annotation would break the provider's token exchange.
cat serviceaccount.yml |
	yq "(.metadata.name)|="\""$SERVICE_ACCOUNT_NAME"\" |
	yq "(.metadata.namespace)|="\""$NAMESPACE"\" |
	yq "(.metadata.annotations.\"azure.workload.identity/client-id\")|="\""$CLIENT_ID"\" |
	yq "(.metadata.annotations.\"azure.workload.identity/tenant-id\")|="\""$TENANT_ID"\" |
	kubectl apply -f -

#********************************************
# Federated identity credential
#********************************************

# Check whether the federated identity credential already exists and still points at this namespace and
# service account: both are part of its subject, so a credential left behind by a deployment in another
# namespace (or with another service account) has to be recreated, or the token exchange fails.
echo "Checking if [$FEDERATED_IDENTITY_NAME] federated identity credential actually exists in the [$RESOURCE_GROUP_NAME] resource group..."

EXPECTED_SUBJECT="system:serviceaccount:$NAMESPACE:$SERVICE_ACCOUNT_NAME"
CURRENT_SUBJECT="$(az identity federated-credential show \
	--name "$FEDERATED_IDENTITY_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--identity-name "$MANAGED_IDENTITY_NAME" \
	--query subject \
	--output tsv 2>/dev/null)"

if [[ -n $CURRENT_SUBJECT && $CURRENT_SUBJECT != "$EXPECTED_SUBJECT" ]]; then
	echo "[$FEDERATED_IDENTITY_NAME] federated identity credential points at [$CURRENT_SUBJECT] instead of [$EXPECTED_SUBJECT]: deleting it"

	az identity federated-credential delete \
		--name "$FEDERATED_IDENTITY_NAME" \
		--identity-name "$MANAGED_IDENTITY_NAME" \
		--resource-group "$RESOURCE_GROUP_NAME" \
		--yes 1>/dev/null

	CURRENT_SUBJECT=""
fi

if [[ -z $CURRENT_SUBJECT ]]; then
	echo "No [$FEDERATED_IDENTITY_NAME] federated identity credential actually exists in the [$RESOURCE_GROUP_NAME] resource group"

	OIDC_ISSUER_URL="$(az aks show \
		--only-show-errors \
		--name "$AKS_CLUSTER_NAME" \
		--resource-group "$RESOURCE_GROUP_NAME" \
		--query oidcIssuerProfile.issuerUrl \
		--output tsv)"

	if [[ -z $OIDC_ISSUER_URL ]]; then
		echo "Failed to retrieve the OIDC issuer URL of the [$AKS_CLUSTER_NAME] cluster"
		exit 1
	fi

	echo "The OIDC Issuer URL of the $AKS_CLUSTER_NAME cluster is $OIDC_ISSUER_URL"
	echo "Creating [$FEDERATED_IDENTITY_NAME] federated identity credential in the [$RESOURCE_GROUP_NAME] resource group..."

	az identity federated-credential create \
		--name "$FEDERATED_IDENTITY_NAME" \
		--identity-name "$MANAGED_IDENTITY_NAME" \
		--resource-group "$RESOURCE_GROUP_NAME" \
		--issuer "$OIDC_ISSUER_URL" \
		--subject "$EXPECTED_SUBJECT" \
		--audiences "api://AzureADTokenExchange" 1>/dev/null

	if [[ $? == 0 ]]; then
		echo "[$FEDERATED_IDENTITY_NAME] federated identity credential successfully created"
	else
		echo "Failed to create [$FEDERATED_IDENTITY_NAME] federated identity credential"
		exit 1
	fi
else
	echo "[$FEDERATED_IDENTITY_NAME] federated identity credential already exists and points at [$EXPECTED_SUBJECT]"
fi

#********************************************
# AzureAppConfigurationProvider
#********************************************

# The endpoint is read back from the service: https://<store>.azconfig.io on Azure,
# https://<store>.azure.localhost.localstack.cloud:4566 on the emulator.
APP_CONFIG_ENDPOINT=$(az appconfig show \
	--name "$APP_CONFIG_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--query endpoint \
	--output tsv \
	--only-show-errors)

if [[ -z $APP_CONFIG_ENDPOINT ]]; then
	echo "Failed to retrieve the endpoint of the [$APP_CONFIG_NAME] App Configuration store. Run 01-deploy-resources.sh first."
	exit 1
fi

echo "Applying the [$PROVIDER_NAME] AzureAppConfigurationProvider against [$APP_CONFIG_ENDPOINT]..."

cat appconfigurationprovider.yml |
	yq "(.metadata.name)|="\""$PROVIDER_NAME"\" |
	yq "(.metadata.namespace)|="\""$NAMESPACE"\" |
	yq "(.spec.endpoint)|="\""$APP_CONFIG_ENDPOINT"\" |
	yq "(.spec.target.configMapName)|="\""$CONFIGMAP_NAME"\" |
	yq "(.spec.auth.workloadIdentity.serviceAccountName)|="\""$SERVICE_ACCOUNT_NAME"\" |
	yq "(.spec.configuration.refresh.interval)|="\""$REFRESH_INTERVAL"\" |
	yq "(.spec.configuration.refresh.monitoring.keyValues[0].key)|="\""$SENTINEL_KEY"\" |
	yq "(.spec.secret.target.secretName)|="\""$K8S_SECRET_NAME"\" |
	yq "(.spec.secret.auth.workloadIdentity.serviceAccountName)|="\""$SERVICE_ACCOUNT_NAME"\" |
	kubectl apply -f -

if [[ $? != 0 ]]; then
	echo "Failed to apply the [$PROVIDER_NAME] AzureAppConfigurationProvider"
	exit 1
fi

# Wait for the first reconcile. Until it completes there is no ConfigMap and no Secret, so the deployment
# below would start pods that crash on a missing PG_HOST.
# A Failed phase here is not terminal, so the wait must not give up on it. On Azure the first reconcile
# regularly reports Failed for a minute or two: a federated identity credential created moments earlier is
# not usable yet (AADSTS70025), and role assignments take up to ten minutes to propagate. The controller
# requeues and recovers on its own. Only the timeout is terminal.
echo "Waiting for the [$PROVIDER_NAME] provider to reconcile (up to 10 minutes)..."
PHASE=""
for attempt in $(seq 1 120); do
	PHASE=$(kubectl get azureappconfigurationprovider "$PROVIDER_NAME" \
		--namespace "$NAMESPACE" \
		--output jsonpath='{.status.phase}' 2>/dev/null)

	[[ $PHASE == "Complete" ]] && break
	if [[ $((attempt % 12)) == 0 ]]; then
		echo "  still [${PHASE:-unknown}] after $((attempt * 5))s; the controller keeps retrying..."
	fi
	sleep 5
done

if [[ $PHASE != "Complete" ]]; then
	echo "The [$PROVIDER_NAME] provider is [${PHASE:-unknown}] instead of [Complete]."
	kubectl get azureappconfigurationprovider "$PROVIDER_NAME" --namespace "$NAMESPACE" \
		--output jsonpath='{.status.message}{"\n"}' 2>/dev/null
	kubectl describe azureappconfigurationprovider "$PROVIDER_NAME" --namespace "$NAMESPACE" 2>/dev/null | tail -20
	echo "Provider controller logs:"
	kubectl logs --namespace "$APP_CONFIG_EXTENSION_NAMESPACE" \
		"deployment/$APP_CONFIG_PROVIDER_DEPLOYMENT" --tail=50 2>/dev/null
	echo
	echo "Most common causes:"
	echo "  - the role assignments have not propagated yet (up to 10 minutes on Azure): re-run this script"
	echo "  - a 401 or 403 in the message: the managed identity is missing [$APP_CONFIG_DATA_READER_ROLE] on the store or [$KEY_VAULT_SECRETS_USER_ROLE] on the vault"
	echo "  - an AADSTS error: the federated credential subject or issuer does not match the service account"
	exit 1
fi

echo "The [$PROVIDER_NAME] provider reconciled successfully"

# Confirm both generated objects exist, and show what landed in the ConfigMap. The Secret's keys are
# listed, never its values.
echo
if ! kubectl get configmap "$CONFIGMAP_NAME" --namespace "$NAMESPACE" &>/dev/null; then
	echo "The [$CONFIGMAP_NAME] ConfigMap was not generated"
	exit 1
fi

# go-template rather than jsonpath: kubectl's jsonpath cannot iterate a map's keys and values.
# The ConfigMap holds only non-secret values, so printing them is useful rather than a leak.
echo "Contents of the generated [$CONFIGMAP_NAME] ConfigMap:"
kubectl get configmap "$CONFIGMAP_NAME" --namespace "$NAMESPACE" \
	--output go-template='{{range $k, $v := .data}}{{$k}}={{$v}}{{"\n"}}{{end}}'

echo
if ! kubectl get secret "$K8S_SECRET_NAME" --namespace "$NAMESPACE" &>/dev/null; then
	echo "The [$K8S_SECRET_NAME] Secret was not generated: check that the Key Vault references resolved"
	exit 1
fi

echo "Keys in the generated [$K8S_SECRET_NAME] Secret (values withheld):"
kubectl get secret "$K8S_SECRET_NAME" --namespace "$NAMESPACE" \
	--output go-template='{{range $k, $v := .data}}{{$k}}{{"\n"}}{{end}}'

#********************************************
# Deployment and service
#********************************************

cat deployment.yml |
	yq "(.metadata.namespace)|="\""$NAMESPACE"\" |
	yq "(.spec.template.spec.serviceAccountName)|="\""$SERVICE_ACCOUNT_NAME"\" |
	yq "(.spec.template.spec.containers[0].image)|="\""$FULL_IMAGE"\" |
	yq "(.spec.template.spec.containers[0].imagePullPolicy)|="\""$IMAGE_PULL_POLICY"\" |
	yq "(.spec.template.spec.containers[0].ports[0].containerPort)|=$PORT" |
	yq "(.spec.template.spec.containers[0].envFrom[0].configMapRef.name)|="\""$CONFIGMAP_NAME"\" |
	yq "(.spec.template.spec.containers[0].envFrom[1].secretRef.name)|="\""$K8S_SECRET_NAME"\" |
	kubectl apply -f -

cat service.yml |
	yq "(.metadata.namespace)|="\""$NAMESPACE"\" |
	kubectl apply -f -

# Roll the pods so a re-push of the same image tag actually takes effect: the pod template is unchanged,
# so kubectl apply reports no change and leaves the running pods on the image they started with.
kubectl rollout restart "deployment/$DEPLOYMENT_NAME" --namespace "$NAMESPACE"

# Wait for the rollout so a pod stuck in ImagePullBackOff or CrashLoopBackOff is reported here, not discovered later
echo "Waiting for deployment [$DEPLOYMENT_NAME] to roll out..."
if kubectl rollout status "deployment/$DEPLOYMENT_NAME" --namespace "$NAMESPACE" --timeout=600s; then
	echo "Deployment [$DEPLOYMENT_NAME] is ready. To reach the web app, run:"
	echo "  kubectl port-forward service/$SERVICE_NAME 8080:80 -n $NAMESPACE"
	echo "and browse to http://localhost:8080 (health: http://localhost:8080/health)."
else
	echo "Deployment [$DEPLOYMENT_NAME] did not become ready. Inspect it with:"
	echo "  kubectl get pods -n $NAMESPACE"
	echo "  kubectl describe pod -n $NAMESPACE --selector app=$DEPLOYMENT_NAME"
	echo "  kubectl logs -n $NAMESPACE --selector app=$DEPLOYMENT_NAME --tail=50"
	exit 1
fi
