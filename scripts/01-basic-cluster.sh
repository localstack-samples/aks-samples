#!/bin/bash

# Create the smallest, fastest AKS cluster for demos, without asking anything: a system-assigned identity, Azure CNI
# Overlay with the Azure network policy, one node, Microsoft Entra Workload ID, Microsoft Entra ID authentication with
# Azure RBAC, Advanced Container Networking Services and the attached container registry. To save provisioning time,
# the Azure Files and Azure Disk CSI drivers and the CSI snapshot controller are turned off, so
# samples/web-app-file-storage and samples/web-app-in-cluster-postgresql do not run on this cluster. There is no custom
# virtual network, Bastion, Key Vault, Log Analytics, user node pool, KEDA or Gateway API either: create any of those
# with 01-configurable-cluster.sh instead.
#
# Entra ID makes the cluster's admin groups the ones in AAD_ADMIN_GROUP_OBJECT_IDS (comma-separated object IDs). The
# default is the original scripts' placeholder, which the emulator accepts; on Azure, set real group object IDs.
#
# The samples create their own workload identities and federated credentials when they are deployed, so the
# cluster only needs the OIDC issuer and Workload ID enabled.
#
# Usage: ./01-basic-cluster.sh [--dry-run] [--yes] [--help]

set -euo pipefail

# Variables: the same names as the other cluster scripts, which every sample relies on

# Azure Kubernetes Service (AKS) cluster
prefix="local"
suffix="test"
aks_cluster_name="$prefix-aks-$suffix"
resource_group_name="$prefix-rg"
location="ItalyNorth"
os_sku="AzureLinux"
os_disk_size=50
os_disk_type="Ephemeral"
system_node_pool_name="system"
user_node_pool_name="user"

# Object IDs of the Microsoft Entra ID admin groups: the original scripts' placeholder unless AAD_ADMIN_GROUP_OBJECT_IDS
# is set
aad_profile_admin_group_object_ids=${AAD_ADMIN_GROUP_OBJECT_IDS:-"<your-admin-group-object-id>"}
guid_re='[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}'
guid_list_re="^$guid_re(,$guid_re)*$"

# Azure Container Registry
acr_name="${prefix}acr${suffix}"
acr_sku="Basic"

# AKS variables
network_plugin="azure"
network_plugin_mode="overlay"
network_policy="azure"
network_dataplane="azure"
pod_cidr="192.168.0.0/16"
dns_service_ip="172.16.0.10"
service_cidr="172.16.0.0/16"

# Node count, node size, and ssh key location for AKS nodes. Without the key file the cluster is created with
# --no-ssh-key: az aks create refuses to run with neither.
node_count=1
max_pods=100
node_size="Standard_D4ds_v5"
os_type="Linux"
ssh_key_value="$HOME/.ssh/id_rsa.pub"

# Command-line options, also settable as DRY_RUN=true and ASSUME_YES=true
DRY_RUN=${DRY_RUN:-false}
ASSUME_YES=${ASSUME_YES:-false}

usage() {
	cat <<EOF
Usage: ./01-basic-cluster.sh [--dry-run] [--yes] [--help]

Creates the [$aks_cluster_name] AKS cluster in the [$resource_group_name] resource group with the fewest resources:
one node, Workload ID, Entra ID with Azure RBAC and the attached [$acr_name] container registry. The Azure Files and
Azure Disk CSI drivers and the CSI snapshot controller are turned off to save provisioning time.

Set AAD_ADMIN_GROUP_OBJECT_IDS to the object IDs of the Entra ID admin groups (required on Azure).

Options:
  --dry-run   Print every command instead of running it. Nothing is executed, so no az login is needed.
  --yes       Skip the confirmation prompt.
  --help      Show this help.

For the CSI drivers, a custom virtual network, Bastion, Key Vault, monitoring, a user node pool, KEDA or Gateway API,
use 01-configurable-cluster.sh.
EOF
}

die() {
	echo "$*" >&2
	exit 1
}

# Print $1 without leading and trailing whitespace
trim() {
	local value=$1
	value=${value#"${value%%[![:space:]]*}"}
	value=${value%"${value##*[![:space:]]}"}
	printf '%s' "$value"
}

# Print true or false for a yes/no answer, case-insensitive; fail for anything else
parse_bool() {
	local value
	value=$(trim "$1")
	case ${value,,} in
	true | yes | y) echo true ;;
	false | no | n) echo false ;;
	*) return 1 ;;
	esac
}

parse_args() {
	local flag value
	for flag in DRY_RUN ASSUME_YES; do
		value=$(parse_bool "${!flag}") || die "Error: $flag=[${!flag}] is not valid: expected true or false"
		printf -v "$flag" '%s' "$value"
	done
	while (($#)); do
		case $1 in
		--dry-run) DRY_RUN=true ;;
		--yes) ASSUME_YES=true ;;
		--help | -h)
			usage
			exit 0
			;;
		*)
			echo "Error: unknown option [$1]" >&2
			usage >&2
			exit 2
			;;
		esac
		shift
	done
}

# Progress messages, shown on real runs only: a dry run prints just the configuration and the commands
log() {
	if [[ $DRY_RUN != true ]]; then
		echo "$*"
	fi
}

# Print one command word: bare when it reads unambiguously, otherwise quoted the way it could be pasted into a
# shell. Placeholders such as <kubernetes-version> stand for values a real run reads from Azure.
quote_arg() {
	local safe_re='^[A-Za-z0-9_./:=,@%+-]+$' placeholder_re='^<[^>]+>$' double_quote_unsafe_re='["$`\\!]'
	if [[ $1 =~ $safe_re || $1 =~ $placeholder_re ]]; then
		printf '%s' "$1"
	elif [[ $1 == *\'* && ! $1 =~ $double_quote_unsafe_re ]]; then
		printf '"%s"' "$1"
	else
		printf "'%s'" "${1//\'/\'\\\'\'}"
	fi
}

# Print a command as one "+ ..." line on fd 3, the script's stdout, so lines printed inside $(...) are shown too
print_cmd() {
	local words=() word
	for word in "$@"; do
		words+=("$(quote_arg "$word")")
	done
	printf '+ %s\n' "${words[*]}" >&3
}

# run CMD...: run a command that changes something, or print it in a dry run
run() {
	if [[ $DRY_RUN == true ]]; then
		print_cmd "$@"
		return 0
	fi
	"$@"
}

# query PLACEHOLDER CMD...: run a lookup and print its result; a dry run prints the command and the placeholder
query() {
	local placeholder=$1
	shift
	if [[ $DRY_RUN == true ]]; then
		print_cmd "$@"
		if [[ -n $placeholder ]]; then
			printf '%s\n' "$placeholder"
		fi
		return 0
	fi
	"$@"
}

# exists CMD...: succeed when the resource CMD shows exists; a dry run prints the check and answers "missing"
exists() {
	if [[ $DRY_RUN == true ]]; then
		print_cmd "$@"
		return 1
	fi
	"$@" &>/dev/null
}

# Read one answer from stdin, trimmed; at the end of the input it prints nothing, so the default applies
read_answer() {
	local answer=""
	IFS= read -r -p "$1" answer || true
	trim "$answer"
}

summary_line() {
	printf '  %-36s %s\n' "$1:" "$2"
}

print_summary() {
	echo "Configuration of the [$aks_cluster_name] AKS cluster in the [$resource_group_name] resource group:"
	summary_line "Subscription" "$subscription_name"
	summary_line "Cluster identity" "system"
	summary_line "Network" "1 (Azure CNI Overlay + Azure network policy)"
	summary_line "System pool nodes" "$node_count"
	summary_line "Cluster autoscaler" "no"
	summary_line "Workload ID" "yes"
	summary_line "Key Vault + CSI secrets provider" "no"
	summary_line "Monitoring (Container Insights)" "no"
	summary_line "Azure Files CSI driver" "no"
	summary_line "Azure Disk CSI driver" "no"
	summary_line "CSI snapshot controller" "no"
	summary_line "Custom virtual network" "no"
	summary_line "Azure Bastion" "-"
	summary_line "User node pool" "no"
	summary_line "User pool nodes" "-"
	summary_line "User pool zones" "-"
	summary_line "KEDA" "no"
	summary_line "Gateway API (managed CRDs)" "no"
	summary_line "NGINX Gateway Fabric + cert-manager" "-"
	summary_line "Entra ID + Azure RBAC" "yes"
	summary_line "Entra ID admin groups" "$aad_profile_admin_group_object_ids"
	summary_line "ACNS" "yes (always)"
	echo "Resources (existing ones are kept):"
	echo "  - Resource group [$resource_group_name]"
	echo "  - Container registry [$acr_name]"
	echo "  - AKS cluster [$aks_cluster_name] with the node pool $system_node_pool_name"
	echo "WARNING: without the Azure Files CSI driver, samples/web-app-file-storage does not work: it mounts its" \
		"Azure file share through that driver."
	echo "WARNING: without the Azure Disk CSI driver, samples/web-app-in-cluster-postgresql does not work: its" \
		"database volume uses the managed-csi-premium storage class that driver provides."
	if [[ ! $aad_profile_admin_group_object_ids =~ $guid_list_re ]]; then
		echo "WARNING: AAD_ADMIN_GROUP_OBJECT_IDS is [$aad_profile_admin_group_object_ids]: on Azure, set it to the object" \
			"IDs of real Entra ID groups, or nobody can administer the cluster."
	fi
}

confirm_or_exit() {
	local answer value
	if [[ $ASSUME_YES == true || $DRY_RUN == true ]]; then
		return
	fi
	while true; do
		answer=$(read_answer "Proceed with this configuration? [Y/n]: ")
		if [[ -z $answer ]]; then
			return
		fi
		if value=$(parse_bool "$answer"); then
			if [[ $value == true ]]; then
				return
			fi
			echo "Aborted: nothing was created."
			exit 0
		fi
		echo "Invalid value [$answer]: please answer yes or no" >&2
	done
}

# Check the tools a real run needs, before anything is created
check_prerequisites() {
	local tool missing=0
	for tool in az kubectl; do
		if ! command -v "$tool" >/dev/null 2>&1; then
			echo "Error: required tool '$tool' is not installed or not in PATH." >&2
			missing=1
		fi
	done
	if ((missing)); then
		echo "Please install the missing tool(s) and re-run the script." >&2
		echo "  az:      https://learn.microsoft.com/cli/azure/install-azure-cli" >&2
		echo "  kubectl: https://kubernetes.io/docs/tasks/tools/ (or: az aks install-cli)" >&2
		exit 1
	fi
}

# compare_setting LABEL CLUSTER_VALUE WANTED_VALUE: record a difference between the cluster and this script
compare_setting() {
	if [[ $2 != "$3" ]]; then
		differences+=("  - $1: cluster has [$2], this run wants [$3]")
	fi
}

# yes or no for a value az prints for a boolean, where an empty value or None means false
cluster_bool() {
	if [[ ${1,,} == true ]]; then
		echo yes
	else
		echo no
	fi
}

# yes when both values are true, no when neither is, partial otherwise
cluster_pair() {
	local first second
	first=$(cluster_bool "$1")
	second=$(cluster_bool "$2")
	if [[ $first == "$second" ]]; then
		echo "$first"
	else
		echo partial
	fi
}

# When the cluster already exists, stop before creating anything if it is not the basic cluster: another script
# built it with features this one would silently leave in place. Sets cluster_exists.
check_existing_cluster() {
	local fields=() differences=() cluster_identity cluster_vnet cluster_user_pool cluster_gateway
	cluster_exists=false
	log "Checking if [$aks_cluster_name] aks cluster actually exists in the [$resource_group_name] resource group..."
	if ! exists az aks show --name "$aks_cluster_name" --resource-group "$resource_group_name" --only-show-errors; then
		return
	fi
	cluster_exists=true

	mapfile -t fields < <(query "" az aks show \
		--name "$aks_cluster_name" \
		--resource-group "$resource_group_name" \
		--query "[identity.type, networkProfile.networkPlugin, networkProfile.networkPluginMode, networkProfile.networkPolicy, networkProfile.networkDataplane, agentPoolProfiles[?name=='$system_node_pool_name'] | [0].vnetSubnetId, agentPoolProfiles[?name=='$system_node_pool_name'] | [0].enableAutoScaling, addonProfiles.azureKeyvaultSecretsProvider.enabled, addonProfiles.omsagent.enabled, oidcIssuerProfile.enabled, securityProfile.workloadIdentity.enabled, workloadAutoScalerProfile.keda.enabled, ingressProfile.gatewayApi.installation, aadProfile.managed, aadProfile.enableAzureRbac, networkProfile.advancedNetworking.enabled, length(agentPoolProfiles[?name=='$user_node_pool_name']), length(agentPoolProfiles[?name=='$user_node_pool_name'] | [0].availabilityZones || \`[]\`), storageProfile.fileCsiDriver.enabled, storageProfile.diskCsiDriver.enabled]" \
		--output tsv \
		--only-show-errors)
	((${#fields[@]} == 20)) || die "Failed to read the configuration of the existing [$aks_cluster_name] AKS cluster"

	case ${fields[0]} in
	SystemAssigned) cluster_identity=system ;;
	UserAssigned) cluster_identity=user ;;
	*) cluster_identity=${fields[0]} ;;
	esac
	cluster_vnet=no
	if [[ -n ${fields[5]} && ${fields[5]} != None ]]; then
		cluster_vnet=yes
	fi
	cluster_user_pool=no
	if [[ ${fields[16]} != 0 ]]; then
		cluster_user_pool=yes
	fi
	cluster_gateway=no
	if [[ ${fields[12]} == Standard ]]; then
		cluster_gateway=yes
	fi

	compare_setting "Cluster identity" "$cluster_identity" system
	compare_setting "Network" "${fields[1]}/${fields[2]}/${fields[3]}/${fields[4]}" \
		"$network_plugin/$network_plugin_mode/$network_policy/$network_dataplane"
	compare_setting "Cluster autoscaler" "$(cluster_bool "${fields[6]}")" no
	# Workload ID alone: AKS turns the OIDC issuer (fields[9]) on for every new cluster from Kubernetes 1.34, and
	# it cannot be turned off, so it says nothing about how the cluster was created
	compare_setting "Workload ID" "$(cluster_bool "${fields[10]}")" yes
	compare_setting "Key Vault + CSI secrets provider" "$(cluster_bool "${fields[7]}")" no
	compare_setting "Monitoring (Container Insights)" "$(cluster_bool "${fields[8]}")" no
	compare_setting "Azure Files CSI driver" "$(cluster_bool "${fields[18]}")" no
	compare_setting "Azure Disk CSI driver" "$(cluster_bool "${fields[19]}")" no
	compare_setting "Custom virtual network" "$cluster_vnet" no
	compare_setting "User node pool" "$cluster_user_pool" no
	compare_setting "KEDA" "$(cluster_bool "${fields[11]}")" no
	compare_setting "Gateway API (managed CRDs)" "$cluster_gateway" no
	compare_setting "Entra ID + Azure RBAC" "$(cluster_pair "${fields[13]}" "${fields[14]}")" yes
	compare_setting "ACNS" "$(cluster_bool "${fields[15]}")" yes

	if ((${#differences[@]} > 0)); then
		echo "The [$aks_cluster_name] cluster already exists with a different configuration:" >&2
		printf '%s\n' "${differences[@]}" >&2
		echo "Delete it first: az group delete --name $resource_group_name --yes" >&2
		echo "or keep it and skip this script." >&2
		exit 1
	fi
	log "The existing [$aks_cluster_name] AKS cluster is the basic cluster: provisioning what is missing"
}

ensure_resource_group() {
	log "Checking if [$resource_group_name] resource group actually exists in the [$subscription_name] subscription..."
	if exists az group show --name "$resource_group_name" --only-show-errors; then
		log "[$resource_group_name] resource group already exists in the [$subscription_name] subscription"
		return
	fi
	log "Creating [$resource_group_name] resource group in the [$subscription_name] subscription..."
	run az group create \
		--name "$resource_group_name" \
		--location "$location" \
		--only-show-errors >/dev/null ||
		die "Failed to create [$resource_group_name] resource group in the [$subscription_name] subscription"
	log "[$resource_group_name] resource group successfully created in the [$subscription_name] subscription"
}

ensure_acr() {
	log "Checking if [$acr_name] container registry actually exists in the [$resource_group_name] resource group..."
	if exists az acr show --name "$acr_name" --resource-group "$resource_group_name" --only-show-errors; then
		log "[$acr_name] container registry already exists in the [$resource_group_name] resource group"
		return
	fi
	log "Creating [$acr_name] container registry in the [$resource_group_name] resource group..."
	run az acr create \
		--name "$acr_name" \
		--resource-group "$resource_group_name" \
		--location "$location" \
		--sku "$acr_sku" \
		--admin-enabled true \
		--only-show-errors >/dev/null ||
		die "Failed to create [$acr_name] container registry in the [$resource_group_name] resource group"
	log "[$acr_name] container registry successfully created in the [$resource_group_name] resource group"
}

ensure_cluster() {
	local kubernetes_version aks_create_args
	if [[ $cluster_exists == true ]]; then
		log "[$aks_cluster_name] aks cluster already exists in the [$resource_group_name] resource group"
		return
	fi

	# The latest Kubernetes version available in the region
	kubernetes_version=$(query "<kubernetes-version>" az aks get-versions \
		--location "$location" \
		--query "values[?isPreview==null].version | sort(@) | [-1]" \
		--output tsv \
		--only-show-errors)
	[[ -n $kubernetes_version ]] || die "Failed to retrieve the latest Kubernetes version available in [$location]"

	aks_create_args=(
		--name "$aks_cluster_name"
		--resource-group "$resource_group_name"
		--os-sku "$os_sku"
		--node-osdisk-size "$os_disk_size"
		--node-osdisk-type "$os_disk_type"
		--nodepool-name "$system_node_pool_name"
		--node-count "$node_count"
		--max-pods "$max_pods"
		--location "$location"
		--kubernetes-version "$kubernetes_version"
	)
	if [[ -f $ssh_key_value ]]; then
		aks_create_args+=(--ssh-key-value "$ssh_key_value")
	else
		aks_create_args+=(--no-ssh-key)
	fi
	aks_create_args+=(
		--node-vm-size "$node_size"
		--disable-file-driver
		--disable-disk-driver
		--disable-snapshot-controller
		--network-dataplane "$network_dataplane"
		--network-policy "$network_policy"
		--network-plugin "$network_plugin"
		--network-plugin-mode "$network_plugin_mode"
		--pod-cidr "$pod_cidr"
		--dns-service-ip "$dns_service_ip"
		--service-cidr "$service_cidr"
		--enable-acns
		--enable-managed-identity
		--enable-workload-identity
		--enable-oidc-issuer
		--enable-aad
		--enable-azure-rbac
		--aad-admin-group-object-ids "$aad_profile_admin_group_object_ids"
		--attach-acr "$acr_name"
		--tier free
		--auto-upgrade-channel none
		--node-os-upgrade-channel None
		--tags provisioning=az-cli
		--nodepool-tags "os_disk_type=$os_disk_type" "os_type=$os_type"
		--nodepool-labels "os_disk_type=$os_disk_type" "os_type=$os_type"
		--only-show-errors
	)
	log "Creating [$aks_cluster_name] aks cluster in the [$resource_group_name] resource group..."
	run az aks create "${aks_create_args[@]}" >/dev/null ||
		die "Failed to create [$aks_cluster_name] aks cluster in the [$resource_group_name] resource group"
	log "[$aks_cluster_name] aks cluster successfully created in the [$resource_group_name] resource group"
}

# Merge the cluster context into the local kubeconfig so kubectl is ready to use
get_credentials() {
	log "Getting access credentials configure kubectl to connect to the [$aks_cluster_name] AKS cluster..."
	run az aks get-credentials \
		--name "$aks_cluster_name" \
		--resource-group "$resource_group_name" \
		--overwrite-existing \
		--only-show-errors ||
		die "Failed to retrieve the credentials for the [$aks_cluster_name] cluster"
}

# Print the storage drivers enabled on the cluster, then the storage classes they provide
print_storage() {
	log "Storage profile of the [$aks_cluster_name] AKS cluster:"
	run az aks show \
		--name "$aks_cluster_name" \
		--resource-group "$resource_group_name" \
		--query storageProfile \
		--output yaml \
		--only-show-errors
	log "Storage classes of the [$aks_cluster_name] AKS cluster:"
	run kubectl get storageclass
}

main() {
	# fd 3 is where dry-run commands are printed: the real stdout, even inside $(...)
	exec 3>&1
	parse_args "$@"
	if [[ $DRY_RUN != true ]]; then
		check_prerequisites
	fi
	# Read before the summary, so the confirmation names where the resources go: the same command line reaches
	# Azure or the LocalStack emulator, depending on the Azure CLI configuration
	subscription_name=$(query "<subscription-name>" az account show --query name --output tsv --only-show-errors)
	print_summary
	confirm_or_exit

	check_existing_cluster
	ensure_resource_group
	ensure_acr
	ensure_cluster
	get_credentials
	print_storage
}

main "$@"
