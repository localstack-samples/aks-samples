#!/bin/bash

# Variables

# Azure Kubernetes Service (AKS) cluster
prefix="local" # horus, zeus, poseidon, hades, demeter, apollo, artemis, ares, athena, hephaestus, hermes
suffix="test"
aks_cluster_name="$prefix-aks-$suffix"
aks_managed_identity_name="$prefix-aks-identity-$suffix"
resource_group_name="$prefix-rg"
location="ItalyNorth"
os_sku="AzureLinux"
os_disk_size=50
os_disk_type="Ephemeral"
system_node_pool_name="system"

# Azure Key Vault
key_vault_name="$prefix-kv-$suffix"

# Azure Container Registry
acr_name="${prefix}acr${suffix}"
acr_sku="Basic"

# Virtual Network
virtual_network_name="$prefix-vnet-$suffix"
virtual_network_address_prefix="10.0.0.0/8"
system_subnet_name="SystemSubnet"
system_subnet_prefix="10.240.0.0/16"
user_subnet_name="UserSubnet"
user_subnet_prefix="10.241.0.0/16"
bastion_subnet_name="AzureBastionSubnet"
bastion_subnet_prefix="10.242.2.0/24"

# AKS variables
pod_cidr="192.168.0.0/16"
dns_service_ip="172.16.0.10"
service_cidr="172.16.0.0/16"

aad_profile_admin_group_object_ids="53b42cac-2058-4fc9-8ee2-b29f7ad797d7" # Smurf Team group

# Log Analytics
log_analytics_name="$prefix-log-analytics-$suffix"
log_analytics_sku="PerGB2018"

# Node count, node size, and ssh key location for AKS nodes
node_size="Standard_D4ds_v5" # Standard_D4ds_v4
ssh_key_value="$HOME/.ssh/id_rsa.pub"

# Windows nodes credentials
windows_admin_username="azadmin"
windows_admin_password="Trustno123456!"

# Node count variables
node_count=1
min_count=1
max_count=3
max_pods=100

# Node pool variables
user_node_pool_name="user"
vm_size="Standard_D4ds_v5" # Standard_D4ds_v4
os_type="Linux"
mode="User"
node_pool_node_count=1
node_pool_min_count=1
node_pool_max_count=3
node_pool_max_pods=100

# SubscriptionName of the current subscription
subscription_name=$(az account show --query name --output tsv)

# Role assignment retry settings
RETRY_COUNT=3
SLEEP=5

# Extensions to register
install_extensions_and_features=0
aks_features=("ManagedGatewayAPIPreview")
registering_extensions=()
ok=0

# Print the menu
echo "===================================="
echo "Run Docker Container (1-3): "
echo "===================================="
options=(
	"Azure Network Plugin + Azure Network Policy"
	"Azure Network Plugin + Cilium Network Policy"
	"Azure Network Plugin + Calico Network Policy"
	"Quit"
)
name=""
# Select an option
COLUMNS=0
select option in "${options[@]}"; do
	case $option in
	"Azure Network Plugin + Azure Network Policy")
		# Network policy
		network_plugin="azure" #azure, kubenet, none
		network_policy="azure" #calico, azure, cilium, none
		network_plugin_mode="overlay"
		network_dataplane="azure" #cilium, azure
		break
		;;
	"Azure Network Plugin + Cilium Network Policy")
		# Network policy
		network_plugin="azure"  #azure, kubenet, none
		network_policy="cilium" #calico, azure, cilium, none
		network_plugin_mode="overlay"
		network_dataplane="cilium" #cilium, azure
		break
		;;
	"Azure Network Plugin + Calico Network Policy")
		# Network policy
		network_plugin="azure"  #azure, kubenet, none
		network_policy="calico" #calico, azure, cilium, none
		network_plugin_mode="overlay"
		network_dataplane="azure" #cilium, azure
		break
		;;
	"Quit")
		exit
		;;
	*) echo "invalid option $REPLY" ;;
	esac
done

# Prompt for a node count (positive integer); an empty answer keeps the default
read_node_count() {
	local prompt=$1
	local default_count=$2
	local value
	while true; do
		read -r -p "$prompt [default: $default_count]: " value
		value=${value:-$default_count}
		if [[ $value =~ ^[1-9][0-9]*$ ]]; then
			echo "$value"
			return 0
		fi
		echo "Invalid value [$value]: please enter a positive integer" >&2
	done
}

# Ask for the number of nodes of the system node pool and user node pool
node_count=$(read_node_count "Enter the number of nodes for the [$system_node_pool_name] system node pool" "$node_count")
if [[ $node_count -lt $min_count ]]; then
	min_count=$node_count
fi
if [[ $node_count -gt $max_count ]]; then
	max_count=$node_count
fi
echo "The [$system_node_pool_name] system node pool will have [$node_count] nodes (autoscaler min: $min_count, max: $max_count)"

node_pool_node_count=$(read_node_count "Enter the number of nodes for the [$user_node_pool_name] user node pool" "$node_pool_node_count")
if [[ $node_pool_node_count -lt $node_pool_min_count ]]; then
	node_pool_min_count=$node_pool_node_count
fi
if [[ $node_pool_node_count -gt $node_pool_max_count ]]; then
	node_pool_max_count=$node_pool_node_count
fi
echo "The [$user_node_pool_name] user node pool will have [$node_pool_node_count] nodes (autoscaler min: $node_pool_min_count, max: $node_pool_max_count)"

# Install aks-preview Azure extension
if [[ $install_extensions_and_features == 1 ]]; then
	echo "Adding or upgrading [aks-preview] extension..."
	az extension add --upgrade --name aks-preview &>/dev/null

	if [[ $? == 0 ]]; then
		echo "[aks-preview] extension successfully installed or upgraded"
	else
		echo "Failed to install or upgrade [aks-preview] extension"
		exit
	fi

	# Registering AKS features
	for aks_feature in "${aks_features[@]}"; do
		echo "Checking if [$aks_feature] extension is already registered..."
		extension=$(az feature list -o table --query "[?contains(name, 'Microsoft.ContainerService/$aks_feature') && @.properties.state == 'Registered'].{Name:name}" --output tsv)
		if [[ -z $extension ]]; then
			echo "[$aks_feature] extension is not registered."
			echo "Registering [$aks_feature] extension..."
			az feature register \
				--name "$aks_feature" \
				--namespace Microsoft.ContainerService \
				--only-show-errors 1>/dev/null
			registering_extensions+=("$aks_feature")
			ok=1
		else
			echo "[$aks_feature] extension is already registered."
		fi
	done
	if [[ ${#registering_extensions[@]} -gt 0 ]]; then
		echo "${registering_extensions[@]}"
	fi
	delay=1
	for aks_feature in "${registering_extensions[@]}"; do
		echo -n "Checking if [$aks_feature] extension is already registered..."
		while true; do
			extension=$(az feature list -o table --query "[?contains(name, 'Microsoft.ContainerService/$aks_feature') && @.properties.state == 'Registered'].{Name:name}" --output tsv)
			if [[ -z $extension ]]; then
				echo -n "."
				sleep $delay
			else
				echo "."
				break
			fi
		done
	done

	if [[ $ok == 1 ]]; then
		echo "Refreshing the registration of the Microsoft.ContainerService resource provider..."
		az provider register --namespace Microsoft.ContainerService --only-show-errors 1>/dev/null
		echo "Microsoft.ContainerService resource provider registration successfully refreshed"
	fi
fi

# Check if the resource group already exists
echo "Checking if [$resource_group_name] resource group actually exists in the [$subscription_name] subscription..."

az group show --name $resource_group_name --only-show-errors &>/dev/null

if [[ $? != 0 ]]; then
	echo "No [$resource_group_name] resource group actually exists in the [$subscription_name] subscription"
	echo "Creating [$resource_group_name] resource group in the [$subscription_name] subscription..."

	# create the resource group
	az group create \
		--name $resource_group_name \
		--location $location \
		--only-show-errors 1>/dev/null

	if [[ $? == 0 ]]; then
		echo "[$resource_group_name] resource group successfully created in the [$subscription_name] subscription"
	else
		echo "Failed to create [$resource_group_name] resource group in the [$subscription_name] subscription"
		exit
	fi
else
	echo "[$resource_group_name] resource group already exists in the [$subscription_name] subscription"
fi

# Create Key Vault
echo "Checking if [$key_vault_name] key vault actually exists in the [$resource_group_name] resource group..."
az keyvault show \
	--name $key_vault_name \
	--resource-group $resource_group_name \
	--only-show-errors &>/dev/null

if [[ $? != 0 ]]; then
	echo "No [$key_vault_name] key vault actually exists in the [$resource_group_name] resource group"
	echo "Creating Key Vault [$key_vault_name]..."
	az keyvault create \
		--name "$key_vault_name" \
		--resource-group "$resource_group_name" \
		--location "$location" \
		--enable-rbac-authorization true \
		--only-show-errors 1>/dev/null

	if [ $? -eq 0 ]; then
		echo "Key Vault [$key_vault_name] created successfully."
	else
		echo "Failed to create Key Vault [$key_vault_name]."
		exit 1
	fi
else
	echo "[$key_vault_name] key vault already exists in the [$resource_group_name] resource group"
fi

# Retrieve the Key Vault id
key_vault_id=$(az keyvault show \
	--name $key_vault_name \
	--resource-group $resource_group_name \
	--query id \
	--output tsv \
	--only-show-errors 2>/dev/null)

if [[ -n $key_vault_id ]]; then
	echo "Successfully retrieved the id for the [$key_vault_name] key vault"
else
	echo "Failed to retrieve the id for the [$key_vault_name] key vault"
	exit
fi

# Check if log analytics workspace exists and retrieve its resource id
echo "Retrieving [$log_analytics_name] Log Analytics resource id..."
az monitor log-analytics workspace show \
	--name $log_analytics_name \
	--resource-group $resource_group_name \
	--query id \
	--output tsv \
	--only-show-errors &>/dev/null

if [[ $? != 0 ]]; then
	echo "No [$log_analytics_name] log analytics workspace actually exists in the [$resource_group_name] resource group"
	echo "Creating [$log_analytics_name] log analytics workspace in the [$resource_group_name] resource group..."

	# Create the log analytics workspace
	az monitor log-analytics workspace create \
		--name $log_analytics_name \
		--resource-group $resource_group_name \
		--identity-type SystemAssigned \
		--sku $log_analytics_sku \
		--location $location \
		--only-show-errors 1>/dev/null

	if [[ $? == 0 ]]; then
		echo "[$log_analytics_name] log analytics workspace successfully created in the [$resource_group_name] resource group"
	else
		echo "Failed to create [$log_analytics_name] log analytics workspace in the [$resource_group_name] resource group"
		exit
	fi
else
	echo "Successfully retrieved the resource id for the [$log_analytics_name] log analytics workspace"
fi

# Retrieve the log analytics workspace id
workspace_resource_id=$(az monitor log-analytics workspace show \
	--name $log_analytics_name \
	--resource-group $resource_group_name \
	--query id \
	--output tsv \
	--only-show-errors 2>/dev/null)

if [[ -n $workspace_resource_id ]]; then
	echo "Successfully retrieved the id for the [$log_analytics_name] log analytics workspace"
else
	echo "Failed to retrieve the id for the [$log_analytics_name] log analytics workspace"
	exit
fi

# Check if the client virtual network already exists
echo "Checking if [$virtual_network_name] virtual network actually exists in the [$resource_group_name] resource group..."
az network vnet show \
	--name $virtual_network_name \
	--resource-group $resource_group_name \
	--only-show-errors &>/dev/null

if [[ $? != 0 ]]; then
	echo "No [$virtual_network_name] virtual network actually exists in the [$resource_group_name] resource group"
	echo "Creating [$virtual_network_name] virtual network in the [$resource_group_name] resource group..."

	# Create the client virtual network
	az network vnet create \
		--name $virtual_network_name \
		--resource-group $resource_group_name \
		--location $location \
		--address-prefixes $virtual_network_address_prefix \
		--subnet-name $system_subnet_name \
		--subnet-prefix $system_subnet_prefix \
		--only-show-errors 1>/dev/null

	if [[ $? == 0 ]]; then
		echo "[$virtual_network_name] virtual network successfully created in the [$resource_group_name] resource group"
	else
		echo "Failed to create [$virtual_network_name] virtual network in the [$resource_group_name] resource group"
		exit
	fi
else
	echo "[$virtual_network_name] virtual network already exists in the [$resource_group_name] resource group"
fi

# Check if the user subnet already exists
echo "Checking if [$user_subnet_name] user subnet actually exists in the [$virtual_network_name] virtual network..."
az network vnet subnet show \
	--name $user_subnet_name \
	--vnet-name $virtual_network_name \
	--resource-group $resource_group_name \
	--only-show-errors &>/dev/null

if [[ $? != 0 ]]; then
	echo "No [$user_subnet_name] user subnet actually exists in the [$virtual_network_name] virtual network"
	echo "Creating [$user_subnet_name] user subnet in the [$virtual_network_name] virtual network..."

	# Create the user subnet
	az network vnet subnet create \
		--name $user_subnet_name \
		--vnet-name $virtual_network_name \
		--resource-group $resource_group_name \
		--address-prefix $user_subnet_prefix \
		--only-show-errors 1>/dev/null

	if [[ $? == 0 ]]; then
		echo "[$user_subnet_name] user subnet successfully created in the [$virtual_network_name] virtual network"
	else
		echo "Failed to create [$user_subnet_name] user subnet in the [$virtual_network_name] virtual network"
		exit
	fi
else
	echo "[$user_subnet_name] user subnet already exists in the [$virtual_network_name] virtual network"
fi

# Check if the bastion subnet already exists
echo "Checking if [$bastion_subnet_name] bastion subnet actually exists in the [$virtual_network_name] virtual network..."
az network vnet subnet show \
	--name $bastion_subnet_name \
	--vnet-name $virtual_network_name \
	--resource-group $resource_group_name \
	--only-show-errors &>/dev/null

if [[ $? != 0 ]]; then
	echo "No [$bastion_subnet_name] bastion subnet actually exists in the [$virtual_network_name] virtual network"
	echo "Creating [$bastion_subnet_name] bastion subnet in the [$virtual_network_name] virtual network..."

	# Create the bastion subnet
	az network vnet subnet create \
		--name $bastion_subnet_name \
		--vnet-name $virtual_network_name \
		--resource-group $resource_group_name \
		--address-prefix $bastion_subnet_prefix \
		--only-show-errors 1>/dev/null

	if [[ $? == 0 ]]; then
		echo "[$bastion_subnet_name] bastion subnet successfully created in the [$virtual_network_name] virtual network"
	else
		echo "Failed to create [$bastion_subnet_name] bastion subnet in the [$virtual_network_name] virtual network"
		exit
	fi
else
	echo "[$bastion_subnet_name] bastion subnet already exists in the [$virtual_network_name] virtual network"
fi

# Retrieve the virtual network resource ID
virtual_network_id=$(az network vnet show \
	--name $virtual_network_name \
	--resource-group $resource_group_name \
	--query id \
	--output tsv \
	--only-show-errors 2>/dev/null)

if [[ -n $virtual_network_id ]]; then
	echo "Successfully retrieved the resource ID for the [$virtual_network_name] virtual network"
else
	echo "Failed to retrieve the resource ID for the [$virtual_network_name] virtual network"
	exit
fi

# Retrieve the system subnet id
system_subnet_id=$(az network vnet subnet show \
	--name $system_subnet_name \
	--vnet-name $virtual_network_name \
	--resource-group $resource_group_name \
	--query id \
	--output tsv \
	--only-show-errors 2>/dev/null)

if [[ -n $system_subnet_id ]]; then
	echo "Successfully retrieved the id for the [$system_subnet_name] subnet"
else
	echo "Failed to retrieve the id for the [$system_subnet_name] subnet"
	exit
fi

# Retrieve the user subnet id
user_subnet_id=$(az network vnet subnet show \
	--name $user_subnet_name \
	--vnet-name $virtual_network_name \
	--resource-group $resource_group_name \
	--query id \
	--output tsv \
	--only-show-errors 2>/dev/null)

if [[ -n $user_subnet_id ]]; then
	echo "Successfully retrieved the id for the [$user_subnet_name] subnet"
else
	echo "Failed to retrieve the id for the [$user_subnet_name] subnet"
	exit
fi

# Check if the user-defined managed identity of the AKS cluster already exists
echo "Checking if [$aks_managed_identity_name] user-defined managed identity actually exists in the [$resource_group_name] resource group..."
aksManagedIdentityId=$(az identity show \
	--name "$aks_managed_identity_name" \
	--resource-group "$resource_group_name" \
	--query id \
	--output tsv 2>/dev/null)

if [[ -z $aksManagedIdentityId ]]; then
	echo "No [$aks_managed_identity_name] user-defined managed identity actually exists in the [$resource_group_name] resource group"
	aksManagedIdentityId=$(az identity create \
		--name "$aks_managed_identity_name" \
		--resource-group "$resource_group_name" \
		--query id \
		--output tsv)

	if [[ -n $aksManagedIdentityId ]]; then
		echo "[$aks_managed_identity_name] user-defined managed identity successfully created"
	else
		echo "Failed to create [$aks_managed_identity_name] user-defined managed identity in the [$resource_group_name] resource group"
		exit
	fi
else
	echo "[$aks_managed_identity_name] user-defined managed identity already exists in the [$resource_group_name] resource group"
fi

# Retrieve the cluster identity resource ID
echo "Retrieving the id for the [$aks_managed_identity_name] managed identity..."
managed_identity_id=$(az identity show \
	--name "$aks_managed_identity_name" \
	--resource-group "$resource_group_name" \
	--query id \
	--output tsv \
	--only-show-errors 2>/dev/null)

if [[ -n $managed_identity_id ]]; then
	echo "Successfully retrieved the id for the [$aks_managed_identity_name] managed identity"
else
	echo "Failed to retrieve the id for the [$aks_managed_identity_name] managed identity"
	exit
fi

# Retrieve the cluster identity principal ID
echo "Retrieving the principalId for the [$aks_managed_identity_name] managed identity..."
managed_identity_principal_id=$(az identity show \
	--name "$aks_managed_identity_name" \
	--resource-group "$resource_group_name" \
	--query principalId \
	--output tsv \
	--only-show-errors 2>/dev/null)

if [[ -n $managed_identity_principal_id ]]; then
	echo "Successfully retrieved the principalId for the [$aks_managed_identity_name] managed identity"
else
	echo "Failed to retrieve the principalId for the [$aks_managed_identity_name] managed identity"
	exit
fi

# Check if the Azure Container Registry already exists
echo "Checking if [$acr_name] container registry actually exists in the [$resource_group_name] resource group..."
az acr show \
	--name $acr_name \
	--resource-group $resource_group_name \
	--only-show-errors &>/dev/null

if [[ $? != 0 ]]; then
	echo "No [$acr_name] container registry actually exists in the [$resource_group_name] resource group"
	echo "Creating [$acr_name] container registry in the [$resource_group_name] resource group..."

	az acr create \
		--name $acr_name \
		--resource-group $resource_group_name \
		--location $location \
		--sku $acr_sku \
		--admin-enabled true \
		--only-show-errors 1>/dev/null

	if [[ $? == 0 ]]; then
		echo "[$acr_name] container registry successfully created in the [$resource_group_name] resource group"
	else
		echo "Failed to create [$acr_name] container registry in the [$resource_group_name] resource group"
		exit
	fi
else
	echo "[$acr_name] container registry already exists in the [$resource_group_name] resource group"
fi

# Get the last Kubernetes version available in the region
kubernetes_version=$(az aks get-versions \
	--location $location \
	--query "values[?isPreview==null].version | sort(@) | [-1]" \
	--output tsv \
	--only-show-errors 2>/dev/null)

# Create AKS cluster
echo "Checking if [$aks_cluster_name] aks cluster actually exists in the [$resource_group_name] resource group..."

az aks show --name $aks_cluster_name --resource-group $resource_group_name &>/dev/null

if [[ $? != 0 ]]; then
	echo "No [$aks_cluster_name] aks cluster actually exists in the [$resource_group_name] resource group"
	echo "Creating [$aks_cluster_name] aks cluster in the [$resource_group_name] resource group..."

	# Create the aks cluster
	az aks create \
		--name $aks_cluster_name \
		--resource-group $resource_group_name \
		--os-sku $os_sku \
		--node-osdisk-size $os_disk_size \
		--node-osdisk-type $os_disk_type \
		--vnet-subnet-id $system_subnet_id \
		--nodepool-name $system_node_pool_name \
		--enable-cluster-autoscaler \
		--node-count $node_count \
		--min-count $min_count \
		--max-count $max_count \
		--max-pods $max_pods \
		--location $location \
		--kubernetes-version $kubernetes_version \
		--ssh-key-value $ssh_key_value \
		--windows-admin-username $windows_admin_username \
		--windows-admin-password $windows_admin_password \
		--node-vm-size $node_size \
		--enable-addons monitoring,azure-keyvault-secrets-provider \
		--workspace-resource-id $workspace_resource_id \
		--network-dataplane $network_dataplane \
		--network-policy $network_policy \
		--network-plugin $network_plugin \
		--network-plugin-mode $network_plugin_mode \
		--pod-cidr $pod_cidr \
		--dns-service-ip $dns_service_ip \
		--service-cidr $service_cidr \
		--enable-acns \
		--enable-gateway-api \
		--enable-managed-identity \
		--assign-identity "$managed_identity_id" \
		--enable-workload-identity \
		--enable-oidc-issuer \
		--enable-aad \
		--enable-azure-rbac \
		--aad-admin-group-object-ids $aad_profile_admin_group_object_ids \
		--attach-acr $acr_name \
		--only-show-errors 1>/dev/null

	if [[ $? == 0 ]]; then
		echo "[$aks_cluster_name] aks cluster successfully created in the [$resource_group_name] resource group"
	else
		echo "Failed to create [$aks_cluster_name] aks cluster in the [$resource_group_name] resource group"
		exit
	fi
else
	echo "[$aks_cluster_name] aks cluster already exists in the [$resource_group_name] resource group"
fi

# Retrieve the node resource group name and ID
echo "Retrieving the node resource group name for the [$aks_cluster_name] AKS cluster..."
node_resource_group_name=$(az aks show \
	--name $aks_cluster_name \
	--resource-group $resource_group_name \
	--query nodeResourceGroup \
	--output tsv \
	--only-show-errors 2>/dev/null)

if [[ -n $node_resource_group_name ]]; then
	echo "Successfully retrieved the node resource group [$node_resource_group_name] for the [$aks_cluster_name] AKS cluster"
else
	echo "Failed to retrieve the node resource group for the [$aks_cluster_name] AKS cluster"
	exit
fi

# Retrieve the node resource group ID
echo "Retrieving the node resource group ID for the [$node_resource_group_name] resource group..."
node_resource_group_id=$(az group show \
	--name "$node_resource_group_name" \
	--query id \
	--output tsv \
	--only-show-errors 2>/dev/null)

if [[ -n $node_resource_group_id ]]; then
	echo "Successfully retrieved the resource ID for the [$node_resource_group_name] resource group"
else
	echo "Failed to retrieve the resource ID for the [$node_resource_group_name] resource group"
	exit
fi

# Assign the Contributor role to the managed identity on the node resource group
role="Contributor"
managed_identity_name="$aks_managed_identity_name"
principal_id="$managed_identity_principal_id"
scope_id="$node_resource_group_id"
scope_name="$node_resource_group_name"
scope_type="node resource group"
echo "Checking if the [$managed_identity_name] managed identity has the [$role] role assignment on the [$scope_name] $scope_type..."
current=$(az role assignment list \
	--assignee "$principal_id" \
	--scope "$scope_id" \
	--query "[?roleDefinitionName=='$role'].roleDefinitionName" \
	--output tsv 2>/dev/null)

if [[ $current == "$role" ]]; then
	echo "Managed identity [$managed_identity_name] already has the [$role] role assignment on the [$scope_name] $scope_type"
else
	echo "Managed identity [$managed_identity_name] does not have the [$role] role assignment on the [$scope_name] $scope_type"
	echo "Creating role assignment: assigning [$role] role to managed identity [$managed_identity_name] on the [$scope_name] $scope_type..."
	ATTEMPT=1
	while [ $ATTEMPT -le $RETRY_COUNT ]; do
		echo "Attempt $ATTEMPT of $RETRY_COUNT to assign role..."
		az role assignment create \
			--assignee "$principal_id" \
			--role "$role" \
			--scope "$scope_id" 1>/dev/null

		if [[ $? == 0 ]]; then
			break
		else
			if [ $ATTEMPT -lt $RETRY_COUNT ]; then
				echo "Role assignment failed. Waiting [$SLEEP] seconds before retry..."
				sleep $SLEEP
			fi
			ATTEMPT=$((ATTEMPT + 1))
		fi
	done

	if [[ $? == 0 ]]; then
		echo "Successfully assigned [$role] role to managed identity [$managed_identity_name] on the [$scope_name] $scope_type"
	else
		echo "Failed to assign [$role] role to managed identity [$managed_identity_name] on the [$scope_name] $scope_type"
		exit 1
	fi
fi

# Assign the Network Contributor role to the managed identity on the virtual network
role="Network Contributor"
managed_identity_name="$aks_managed_identity_name"
principal_id="$managed_identity_principal_id"
scope_id="$virtual_network_id"
scope_name="$virtual_network_name"
scope_type="virtual network"
echo "Checking if the [$managed_identity_name] managed identity has the [$role] role assignment on the [$scope_name] $scope_type..."
current=$(az role assignment list \
	--assignee "$principal_id" \
	--scope "$scope_id" \
	--query "[?roleDefinitionName=='$role'].roleDefinitionName" \
	--output tsv 2>/dev/null)

if [[ $current == "$role" ]]; then
	echo "Managed identity [$managed_identity_name] already has the [$role] role assignment on the [$scope_name] $scope_type"
else
	echo "Managed identity [$managed_identity_name] does not have the [$role] role assignment on the [$scope_name] $scope_type"
	echo "Creating role assignment: assigning [$role] role to managed identity [$managed_identity_name] on the [$scope_name] $scope_type..."
	ATTEMPT=1
	while [ $ATTEMPT -le $RETRY_COUNT ]; do
		echo "Attempt $ATTEMPT of $RETRY_COUNT to assign role..."
		az role assignment create \
			--assignee "$principal_id" \
			--role "$role" \
			--scope "$scope_id" 1>/dev/null

		if [[ $? == 0 ]]; then
			break
		else
			if [ $ATTEMPT -lt $RETRY_COUNT ]; then
				echo "Role assignment failed. Waiting [$SLEEP] seconds before retry..."
				sleep $SLEEP
			fi
			ATTEMPT=$((ATTEMPT + 1))
		fi
	done

	if [[ $? == 0 ]]; then
		echo "Successfully assigned [$role] role to managed identity [$managed_identity_name] on the [$scope_name] $scope_type"
	else
		echo "Failed to assign [$role] role to managed identity [$managed_identity_name] on the [$scope_name] $scope_type"
		exit 1
	fi
fi

# Check if the user node pool exists
echo "Checking if [$aks_cluster_name] aks cluster actually has a user node pool..."
az aks nodepool show \
	--name $user_node_pool_name \
	--cluster-name $aks_cluster_name \
	--resource-group $resource_group_name &>/dev/null

if [[ $? == 0 ]]; then
	echo "A node pool called [$user_node_pool_name] already exists in the [$aks_cluster_name] AKS cluster"
else
	echo "No node pool called [$user_node_pool_name] actually exists in the [$aks_cluster_name] AKS cluster"
	echo "Creating [$user_node_pool_name] node pool in the [$aks_cluster_name] AKS cluster..."

	az aks nodepool add \
		--name $user_node_pool_name \
		--mode $mode \
		--cluster-name $aks_cluster_name \
		--resource-group $resource_group_name \
		--enable-cluster-autoscaler \
		--os-type $os_type \
		--os-sku $os_sku \
		--node-vm-size $vm_size \
		--node-osdisk-size $os_disk_size \
		--node-osdisk-type $os_disk_type \
		--node-count $node_pool_node_count \
		--min-count $node_pool_min_count \
		--max-count $node_pool_max_count \
		--max-pods $node_pool_max_pods \
		--tags os_disk_type=$os_disk_type os_type=Linux \
		--labels os_disk_type=$os_disk_type os_type=Linux \
		--vnet-subnet-id $user_subnet_id \
		--zones 1 2 3 \
		--only-show-errors 1>/dev/null

	if [[ $? == 0 ]]; then
		echo "[$user_node_pool_name] node pool successfully created in the [$aks_cluster_name] AKS cluster"
	else
		echo "Failed to create the [$user_node_pool_name] node pool in the [$aks_cluster_name] AKS cluster"
	fi
fi

# Retrieve the objectId of the Azure Key Vault Secrets Provider identity
kv_secret_provider_managed_identity_object_id=$(az aks show \
	--resource-group $resource_group_name \
	--name $aks_cluster_name \
	--query addonProfiles.azureKeyvaultSecretsProvider.identity.objectId \
	--output tsv \
	--only-show-errors 2>/dev/null)

if [[ -n $kv_secret_provider_managed_identity_object_id ]]; then
	echo "Successfully retrieved the objectId for the Azure Key Vault Secrets Provider identity in the [$aks_cluster_name] AKS cluster"
else
	echo "Failed to retrieve the objectId for the Azure Key Vault Secrets Provider identity in the [$aks_cluster_name] AKS cluster"
	exit
fi

# Retrieve the resourceId of the Azure Key Vault Secrets Provider identity
kv_secret_provider_managed_identity_resource_id=$(az aks show \
	--resource-group $resource_group_name \
	--name $aks_cluster_name \
	--query addonProfiles.azureKeyvaultSecretsProvider.identity.resourceId \
	--output tsv \
	--only-show-errors 2>/dev/null)

if [[ -n $kv_secret_provider_managed_identity_resource_id ]]; then
	echo "Successfully retrieved the resourceId for the Azure Key Vault Secrets Provider identity in the [$aks_cluster_name] AKS cluster"
else
	echo "Failed to retrieve the resourceId for the Azure Key Vault Secrets Provider identity in the [$aks_cluster_name] AKS cluster"
	exit
fi

# Get the name of the Azure Key Vault Secrets Provider identity from the resourceId
kv_secret_provider_managed_identity_name=$(basename $kv_secret_provider_managed_identity_resource_id)

# Assign the Key Vault Administrator role to the managed identity on the node resource group
role="Key Vault Administrator"
managed_identity_name="$kv_secret_provider_managed_identity_name"
principal_id="$kv_secret_provider_managed_identity_object_id"
scope_id="$key_vault_id"
scope_name="$key_vault_name"
scope_type="key vault"
echo "Checking if the [$managed_identity_name] managed identity has the [$role] role assignment on the [$scope_name] $scope_type..."
current=$(az role assignment list \
	--assignee "$principal_id" \
	--scope "$scope_id" \
	--query "[?roleDefinitionName=='$role'].roleDefinitionName" \
	--output tsv 2>/dev/null)

if [[ $current == "$role" ]]; then
	echo "Managed identity [$managed_identity_name] already has the [$role] role assignment on the [$scope_name] $scope_type"
else
	echo "Managed identity [$managed_identity_name] does not have the [$role] role assignment on the [$scope_name] $scope_type"
	echo "Creating role assignment: assigning [$role] role to managed identity [$managed_identity_name] on the [$scope_name] $scope_type..."
	ATTEMPT=1
	while [ $ATTEMPT -le $RETRY_COUNT ]; do
		echo "Attempt $ATTEMPT of $RETRY_COUNT to assign role..."
		az role assignment create \
			--assignee "$principal_id" \
			--role "$role" \
			--scope "$scope_id" 1>/dev/null

		if [[ $? == 0 ]]; then
			break
		else
			if [ $ATTEMPT -lt $RETRY_COUNT ]; then
				echo "Role assignment failed. Waiting [$SLEEP] seconds before retry..."
				sleep $SLEEP
			fi
			ATTEMPT=$((ATTEMPT + 1))
		fi
	done

	if [[ $? == 0 ]]; then
		echo "Successfully assigned [$role] role to managed identity [$managed_identity_name] on the [$scope_name] $scope_type"
	else
		echo "Failed to assign [$role] role to managed identity [$managed_identity_name] on the [$scope_name] $scope_type"
		exit 1
	fi
fi

# Use the following command to configure kubectl to connect to the new Kubernetes cluster
echo "Getting access credentials configure kubectl to connect to the [$aks_cluster_name] AKS cluster..."
az aks get-credentials \
	--name $aks_cluster_name \
	--resource-group $resource_group_name \
	--overwrite-existing \
	--only-show-errors

if [[ $? == 0 ]]; then
	echo "Credentials for the [$aks_cluster_name] cluster successfully retrieved"
else
	echo "Failed to retrieve the credentials for the [$aks_cluster_name] cluster"
	exit
fi
