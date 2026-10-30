#!/bin/bash

# Deploy with Terraform the AKS cluster that scripts/01-system-assigned-managed-identity.sh creates or, with
# IDENTITY_TYPE=UserAssigned, the one of scripts/01-user-assigned-managed-identity.sh: the same resources, names
# and defaults, including the diagnostic settings. It works the same way against Azure and against the LocalStack
# for Azure emulator, whichever the Azure CLI targets: see "Run against LocalStack" in the README at the root of the
# repository.

# Variables
# Every default below can be overridden through the environment, for example
#   IDENTITY_TYPE=UserAssigned NETWORK_OPTION=2 ./deploy.sh
# The container registry and the key vault have globally unique names on Azure, so a run against a real
# subscription normally needs its own SUFFIX (or PREFIX).
PREFIX="${PREFIX:-local}"
SUFFIX="${SUFFIX:-test}"
LOCATION="${LOCATION:-italynorth}"
RESOURCE_GROUP_NAME="${PREFIX}-rg"
AKS_CLUSTER_NAME="${PREFIX}-aks-${SUFFIX}"
IDENTITY_TYPE="${IDENTITY_TYPE:-SystemAssigned}"
NETWORK_OPTION="${NETWORK_OPTION:-1}"
SYSTEM_NODE_COUNT="${SYSTEM_NODE_COUNT:-1}"
USER_NODE_COUNT="${USER_NODE_COUNT:-1}"
# Comma-separated object ids of the Entra ID admin groups; azurerm accepts only GUIDs, so the default is none
AAD_ADMIN_GROUP_OBJECT_IDS="${AAD_ADMIN_GROUP_OBJECT_IDS:-}"
SSH_PUBLIC_KEY_FILE="${SSH_PUBLIC_KEY_FILE:-$HOME/.ssh/id_rsa.pub}"
# The windows_admin_password variable reads it from the environment
export TF_VAR_windows_admin_password="${WINDOWS_ADMIN_PASSWORD:-Trustno123456!}"
EMULATOR_GUID="00000000-0000-0000-0000-000000000000"
EMULATOR_METADATA_HOST="localhost.localstack.cloud:4566"
CURRENT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Check prerequisites
for tool in az kubectl terraform; do
	if ! command -v "$tool" >/dev/null 2>&1; then
		echo "Error: required tool '$tool' is not installed or not in PATH." >&2
		exit 1
	fi
done

# Change the current directory to the script's directory
cd "$CURRENT_DIR" || exit

# Target the emulator when the Azure CLI does, as lstk az start-interception configures it
RESOURCE_MANAGER_ENDPOINT=$(az cloud show --query endpoints.resourceManager --output tsv --only-show-errors | tr -d '\r')
if [[ $RESOURCE_MANAGER_ENDPOINT == *localhost* || $RESOURCE_MANAGER_ENDPOINT == *localstack* ]]; then
	IS_EMULATOR=1
	echo "The Azure CLI targets the LocalStack for Azure emulator at [$RESOURCE_MANAGER_ENDPOINT]"
else
	IS_EMULATOR=0
	echo "The Azure CLI targets Azure at [$RESOURCE_MANAGER_ENDPOINT]"
fi

# Keep the Kubernetes version of an existing cluster: like the scripts, use the latest version only to create one,
# so that a re-deployment does not upgrade the cluster
KUBERNETES_VERSION=$(az aks show \
	--name "$AKS_CLUSTER_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--query kubernetesVersion \
	--output tsv \
	--only-show-errors 2>/dev/null | tr -d '\r')

if [[ -n $KUBERNETES_VERSION ]]; then
	echo "The [$AKS_CLUSTER_NAME] AKS cluster exists and runs Kubernetes [$KUBERNETES_VERSION]: keeping that version"
else
	# Get the last Kubernetes version available in the region, as the scripts do
	KUBERNETES_VERSION=$(az aks get-versions \
		--location "$LOCATION" \
		--query "values[?isPreview==null].version | sort(@) | [-1]" \
		--output tsv \
		--only-show-errors 2>/dev/null | tr -d '\r')

	if [[ -n $KUBERNETES_VERSION ]]; then
		echo "The latest Kubernetes version available in the [$LOCATION] region is [$KUBERNETES_VERSION]"
	else
		echo "Failed to retrieve the latest Kubernetes version available in the [$LOCATION] region: AKS picks its default"
	fi
fi

# Read the SSH public key of the Linux nodes, as the scripts pass ~/.ssh/id_rsa.pub
if [[ -f $SSH_PUBLIC_KEY_FILE ]]; then
	SSH_PUBLIC_KEY=$(tr -d '\r\n' <"$SSH_PUBLIC_KEY_FILE")
else
	echo "No SSH public key at [$SSH_PUBLIC_KEY_FILE]: the cluster is created without one"
	SSH_PUBLIC_KEY=""
fi

# The comma-separated object ids of the admin groups, as a list
if [[ -n $AAD_ADMIN_GROUP_OBJECT_IDS ]]; then
	AAD_ADMIN_GROUP_OBJECT_IDS_LIST="[\"${AAD_ADMIN_GROUP_OBJECT_IDS//,/\",\"}\"]"
else
	AAD_ADMIN_GROUP_OBJECT_IDS_LIST="[]"
fi

# The variables that override terraform.tfvars
tf_vars=(
	-var "prefix=$PREFIX"
	-var "suffix=$SUFFIX"
	-var "location=$LOCATION"
	-var "identity_type=$IDENTITY_TYPE"
	-var "network_option=$NETWORK_OPTION"
	-var "system_node_count=$SYSTEM_NODE_COUNT"
	-var "user_node_count=$USER_NODE_COUNT"
	-var "aad_admin_group_object_ids=$AAD_ADMIN_GROUP_OBJECT_IDS_LIST"
	-var "ssh_public_key=$SSH_PUBLIC_KEY"
)
if [[ -n $KUBERNETES_VERSION ]]; then
	tf_vars+=(-var "kubernetes_version=$KUBERNETES_VERSION")
fi
if [[ $IS_EMULATOR == 1 ]]; then
	# The emulator's endpoints and placeholder credentials. The Gateway API is enabled with az aks update after the
	# apply instead of azapi, because the emulator does not persist it from azapi's PUT.
	tf_vars+=(
		-var "metadata_host=$EMULATOR_METADATA_HOST"
		-var "resource_manager_endpoint=$RESOURCE_MANAGER_ENDPOINT"
		-var "subscription_id=$EMULATOR_GUID"
		-var "tenant_id=$EMULATOR_GUID"
		-var "client_id=$EMULATOR_GUID"
		-var "client_secret=fake-secret"
		-var "gateway_api_enabled=false"
	)
else
	tf_vars+=(-var "subscription_id=$(az account show --query id --output tsv --only-show-errors | tr -d '\r')")
fi

# Initialize Terraform
echo "Initializing Terraform..."
terraform init -upgrade -input=false 1>/dev/null

if [[ $? == 0 ]]; then
	echo "Terraform successfully initialized"
else
	echo "Failed to initialize Terraform"
	exit 1
fi

# Validate the Terraform configuration
echo "Validating the Terraform configuration..."
terraform validate 1>/dev/null

if [[ $? == 0 ]]; then
	echo "Terraform configuration is valid"
else
	echo "Terraform configuration is not valid"
	exit 1
fi

# Run terraform plan and check for errors
echo "Planning the Terraform deployment..."
terraform plan -input=false -out=tfplan "${tf_vars[@]}" 1>/dev/null

if [[ $? == 0 ]]; then
	echo "Terraform plan successfully created"
else
	echo "Failed to create the Terraform plan"
	exit 1
fi

# Apply the Terraform plan
echo "Applying the Terraform plan..."
terraform apply -input=false -auto-approve tfplan

if [[ $? == 0 ]]; then
	echo "Terraform plan successfully applied"
else
	echo "Failed to apply the Terraform plan"
	exit 1
fi

# Enable the managed Gateway API CRDs on the emulator, which does not persist them from azapi's PUT
if [[ $IS_EMULATOR == 1 ]]; then
	echo "Enabling the managed Gateway API CRDs on the [$AKS_CLUSTER_NAME] AKS cluster..."
	az aks update \
		--name "$AKS_CLUSTER_NAME" \
		--resource-group "$RESOURCE_GROUP_NAME" \
		--enable-gateway-api \
		--only-show-errors 1>/dev/null

	if [[ $? == 0 ]]; then
		echo "The managed Gateway API CRDs were successfully enabled on the [$AKS_CLUSTER_NAME] AKS cluster"
	else
		echo "Failed to enable the managed Gateway API CRDs on the [$AKS_CLUSTER_NAME] AKS cluster"
		exit 1
	fi
fi

# Use the following command to configure kubectl to connect to the new Kubernetes cluster
echo "Getting access credentials configure kubectl to connect to the [$AKS_CLUSTER_NAME] AKS cluster..."
az aks get-credentials \
	--name "$AKS_CLUSTER_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--overwrite-existing \
	--only-show-errors

if [[ $? == 0 ]]; then
	echo "Credentials for the [$AKS_CLUSTER_NAME] cluster successfully retrieved"
else
	echo "Failed to retrieve the credentials for the [$AKS_CLUSTER_NAME] cluster"
	exit 1
fi

# Print the storage drivers enabled on the cluster, followed by the storage classes they provide, as the scripts do
echo "Storage profile of the [$AKS_CLUSTER_NAME] AKS cluster:"
az aks show \
	--name "$AKS_CLUSTER_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--query storageProfile \
	--output yaml \
	--only-show-errors
echo "Storage classes of the [$AKS_CLUSTER_NAME] AKS cluster:"
kubectl get storageclass
