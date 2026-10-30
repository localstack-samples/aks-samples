#!/bin/bash

# Deploy with Bicep the AKS cluster that scripts/01-system-assigned-managed-identity.sh creates or, with
# IDENTITY_TYPE=UserAssigned, the one of scripts/01-user-assigned-managed-identity.sh: the same resources, names
# and defaults, including the diagnostic settings. It works the same way against Azure and against the LocalStack
# for Azure emulator: see "Run against LocalStack" in the README at the root of the repository.

# Variables
# Every default below can be overridden through the environment, for example
#   IDENTITY_TYPE=UserAssigned NETWORK_OPTION=2 ./deploy.sh
# The container registry and the key vault have globally unique names on Azure, so a run against a real
# subscription normally needs its own SUFFIX (or PREFIX).
PREFIX="${PREFIX:-local}"
SUFFIX="${SUFFIX:-test}"
LOCATION="${LOCATION:-italynorth}"
RESOURCE_GROUP_NAME="${RESOURCE_GROUP_NAME:-${PREFIX}-rg}"
AKS_CLUSTER_NAME="${PREFIX}-aks-${SUFFIX}"
IDENTITY_TYPE="${IDENTITY_TYPE:-SystemAssigned}"
NETWORK_OPTION="${NETWORK_OPTION:-1}"
SYSTEM_NODE_COUNT="${SYSTEM_NODE_COUNT:-1}"
USER_NODE_COUNT="${USER_NODE_COUNT:-1}"
AAD_ADMIN_GROUP_OBJECT_IDS="${AAD_ADMIN_GROUP_OBJECT_IDS:-<your-admin-group-object-id>}"
SSH_PUBLIC_KEY_FILE="${SSH_PUBLIC_KEY_FILE:-$HOME/.ssh/id_rsa.pub}"
# main.bicepparam reads it from the environment
export WINDOWS_ADMIN_PASSWORD="${WINDOWS_ADMIN_PASSWORD:-Trustno123456!}"
TEMPLATE="main.bicep"
PARAMETERS="main.bicepparam"
VALIDATE_TEMPLATE="${VALIDATE_TEMPLATE:-1}"
USE_WHAT_IF="${USE_WHAT_IF:-0}"
CURRENT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Check prerequisites
for tool in az kubectl; do
	if ! command -v "$tool" >/dev/null 2>&1; then
		echo "Error: required tool '$tool' is not installed or not in PATH." >&2
		exit 1
	fi
done

# Change the current directory to the script's directory
cd "$CURRENT_DIR" || exit

SUBSCRIPTION_NAME=$(az account show --query name --output tsv --only-show-errors)

# Read the SSH public key of the Linux nodes, as the scripts pass ~/.ssh/id_rsa.pub
if [[ -f $SSH_PUBLIC_KEY_FILE ]]; then
	SSH_PUBLIC_KEY=$(tr -d '\r\n' <"$SSH_PUBLIC_KEY_FILE")
else
	echo "No SSH public key at [$SSH_PUBLIC_KEY_FILE]: the cluster is created without one"
	SSH_PUBLIC_KEY=""
fi

# The comma-separated object ids of the admin groups, as a JSON array
AAD_ADMIN_GROUP_OBJECT_IDS_JSON="[\"${AAD_ADMIN_GROUP_OBJECT_IDS//,/\",\"}\"]"

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

# The parameters that override main.bicepparam
parameters=(
	location="$LOCATION"
	prefix="$PREFIX"
	suffix="$SUFFIX"
	identityType="$IDENTITY_TYPE"
	networkOption="$NETWORK_OPTION"
	systemNodeCount="$SYSTEM_NODE_COUNT"
	userNodeCount="$USER_NODE_COUNT"
	kubernetesVersion="$KUBERNETES_VERSION"
	sshPublicKey="$SSH_PUBLIC_KEY"
	aadAdminGroupObjectIds="$AAD_ADMIN_GROUP_OBJECT_IDS_JSON"
)

# Validates if the resource group exists in the subscription, if not creates it
echo "Checking if resource group [$RESOURCE_GROUP_NAME] exists in the subscription [$SUBSCRIPTION_NAME]..."
az group show --name "$RESOURCE_GROUP_NAME" &>/dev/null

if [[ $? != 0 ]]; then
	echo "No resource group [$RESOURCE_GROUP_NAME] exists in the subscription [$SUBSCRIPTION_NAME]"
	echo "Creating resource group [$RESOURCE_GROUP_NAME] in the subscription [$SUBSCRIPTION_NAME]..."

	# Create the resource group
	az group create \
		--name "$RESOURCE_GROUP_NAME" \
		--location "$LOCATION" \
		--only-show-errors 1>/dev/null

	if [[ $? == 0 ]]; then
		echo "Resource group [$RESOURCE_GROUP_NAME] successfully created in the subscription [$SUBSCRIPTION_NAME]"
	else
		echo "Failed to create resource group [$RESOURCE_GROUP_NAME] in the subscription [$SUBSCRIPTION_NAME]"
		exit 1
	fi
else
	echo "Resource group [$RESOURCE_GROUP_NAME] already exists in the subscription [$SUBSCRIPTION_NAME]"
fi

# Validates the Bicep template
if [[ $VALIDATE_TEMPLATE == 1 ]]; then
	if [[ $USE_WHAT_IF == 1 ]]; then
		# Execute a deployment What-If operation at resource group scope
		echo "Previewing changes deployed by Bicep template [$TEMPLATE]..."
		az deployment group what-if \
			--resource-group "$RESOURCE_GROUP_NAME" \
			--template-file "$TEMPLATE" \
			--parameters "$PARAMETERS" \
			--parameters "${parameters[@]}" \
			--only-show-errors

		if [[ $? == 0 ]]; then
			echo "Bicep template [$TEMPLATE] validation succeeded"
		else
			echo "Failed to validate Bicep template [$TEMPLATE]"
			exit 1
		fi
	else
		# Validate the Bicep template
		echo "Validating Bicep template [$TEMPLATE]..."
		output=$(az deployment group validate \
			--resource-group "$RESOURCE_GROUP_NAME" \
			--template-file "$TEMPLATE" \
			--parameters "$PARAMETERS" \
			--parameters "${parameters[@]}" \
			--only-show-errors)

		if [[ $? == 0 ]]; then
			echo "Bicep template [$TEMPLATE] validation succeeded"
		else
			echo "Failed to validate Bicep template [$TEMPLATE]"
			echo "$output"
			exit 1
		fi
	fi
fi

# Deploy the Bicep template
echo "Deploying Bicep template [$TEMPLATE]..."
az deployment group create \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--template-file "$TEMPLATE" \
	--parameters "$PARAMETERS" \
	--parameters "${parameters[@]}" \
	--only-show-errors 1>/dev/null

if [[ $? == 0 ]]; then
	echo "Bicep template [$TEMPLATE] deployed successfully"
else
	echo "Failed to deploy Bicep template [$TEMPLATE]"
	exit 1
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
