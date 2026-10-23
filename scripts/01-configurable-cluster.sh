#!/bin/bash

# Create an AKS cluster with the optional features you choose.
#
# Every question shows its default in brackets, and pressing Enter at every prompt provisions the same features
# as 01-system-assigned-managed-identity.sh and 01-user-assigned-managed-identity.sh. Each question can also be
# answered by an environment variable (see README.md in this folder), so the script can run unattended:
#
#   CREATE_KEY_VAULT=false ENABLE_KEDA=false ./01-configurable-cluster.sh --yes </dev/null
#
# Usage: ./01-configurable-cluster.sh [--dry-run] [--yes] [--help]

set -euo pipefail

# On Windows, Git Bash and MSYS2 shells pass a path such as /tmp/... unconverted to Windows programs
# (az, curl, jq, python, docker) when MSYS_NO_PATHCONV=1 is set, as the README asks. cygpath, which
# those shells provide, returns the C:/... form those programs can open; elsewhere the path is unchanged.
native_path() {
	if command -v cygpath >/dev/null 2>&1; then
		cygpath -m "$1"
	else
		echo "$1"
	fi
}

# Variables

# Azure Kubernetes Service (AKS) cluster
prefix="local"
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
bastion_public_ip_name="$prefix-bastion-ip-$suffix"
bastion_host_name="$prefix-bastion-$suffix"

# AKS variables
network_plugin="azure"
network_plugin_mode="overlay"
pod_cidr="192.168.0.0/16"
dns_service_ip="172.16.0.10"
service_cidr="172.16.0.0/16"

# Object ID of the Microsoft Entra ID admin group: the same placeholder the original scripts use
default_aad_admin_group_object_ids="<your-admin-group-object-id>"
guid_re='[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}'
guid_list_re="^$guid_re(,$guid_re)*$"

# The first Azure CLI version with the managed Gateway API (--enable-gateway-api) in its core commands
minimum_gateway_api_cli_version="2.86.0"

# Log Analytics
log_analytics_name="$prefix-log-analytics-$suffix"
log_analytics_sku="PerGB2018"

# Node size and ssh key location for AKS nodes. Without the key file the cluster is created with --no-ssh-key:
# az aks create refuses to run with neither.
node_size="Standard_D4ds_v5"
ssh_key_value="$(native_path "$HOME/.ssh/id_rsa.pub")"

# Node count variables
min_count=1
max_count=3
max_pods=100

# Node pool variables
user_node_pool_name="user"
vm_size="Standard_D4ds_v5"
os_type="Linux"
mode="User"
node_pool_min_count=1
node_pool_max_count=3
node_pool_max_pods=100

# Role assignment retry settings
RETRY_COUNT=3
SLEEP=5

# Command-line options, also settable as DRY_RUN=true and ASSUME_YES=true
DRY_RUN=${DRY_RUN:-false}
ASSUME_YES=${ASSUME_YES:-false}

# Answers: each one comes from its environment variable when that is set, otherwise from a question
CLUSTER_IDENTITY=${CLUSTER_IDENTITY:-}
NETWORK_OPTION=${NETWORK_OPTION:-}
SYSTEM_NODE_COUNT=${SYSTEM_NODE_COUNT:-}
ENABLE_CLUSTER_AUTOSCALER=${ENABLE_CLUSTER_AUTOSCALER:-}
ENABLE_WORKLOAD_IDENTITY=${ENABLE_WORKLOAD_IDENTITY:-}
CREATE_KEY_VAULT=${CREATE_KEY_VAULT:-}
ENABLE_MONITORING=${ENABLE_MONITORING:-}
ENABLE_FILE_CSI_DRIVER=${ENABLE_FILE_CSI_DRIVER:-}
ENABLE_DISK_CSI_DRIVER=${ENABLE_DISK_CSI_DRIVER:-}
CREATE_VNET=${CREATE_VNET:-}
CREATE_BASTION=${CREATE_BASTION:-}
CREATE_USER_NODE_POOL=${CREATE_USER_NODE_POOL:-}
USER_NODE_COUNT=${USER_NODE_COUNT:-}
USE_AVAILABILITY_ZONES=${USE_AVAILABILITY_ZONES:-}
ENABLE_KEDA=${ENABLE_KEDA:-}
ENABLE_GATEWAY_API=${ENABLE_GATEWAY_API:-}
INSTALL_GATEWAY_CONTROLLERS=${INSTALL_GATEWAY_CONTROLLERS:-}
ENABLE_ENTRA_RBAC=${ENABLE_ENTRA_RBAC:-}
AAD_ADMIN_GROUP_OBJECT_IDS=${AAD_ADMIN_GROUP_OBJECT_IDS:-}

usage() {
	cat <<EOF
Usage: ./01-configurable-cluster.sh [--dry-run] [--yes] [--help]

Creates the [$aks_cluster_name] AKS cluster in the [$resource_group_name] resource group with the optional
features you choose. Pressing Enter at every question provisions the same features as the original
01-*-managed-identity.sh scripts.

Options:
  --dry-run   Print every command instead of running it. Nothing is executed, so no az login is needed.
  --yes       Skip the confirmation prompt.
  --help      Show this help.

Every question can be answered by an environment variable instead: see README.md in this folder.
EOF
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

yes_no() {
	if [[ $1 == true ]]; then
		echo yes
	else
		echo no
	fi
}

# Progress messages, shown on real runs only: a dry run prints just the configuration and the commands
log() {
	if [[ $DRY_RUN != true ]]; then
		echo "$*"
	fi
}

# Print one command word: bare when it reads unambiguously, otherwise quoted the way it could be pasted into a
# shell. Placeholders such as <system-subnet-id> stand for values a real run reads from Azure.
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

# Read one answer from stdin, trimmed. At the end of the input it prints nothing, so the caller takes the default:
# that is what lets the script run unattended with stdin closed.
read_answer() {
	local answer=""
	IFS= read -r -p "$1" answer || true
	trim "$answer"
}

# ask_bool VAR PROMPT DEFAULT: set VAR to true or false
ask_bool() {
	local var=$1 prompt=$2 default=$3 answer value hint="[Y/n]"
	if [[ -n ${!var:-} ]]; then
		value=$(parse_bool "${!var}") || die "Error: $var=[${!var}] is not valid: expected true or false"
		printf -v "$var" '%s' "$value"
		return
	fi
	if [[ $default == false ]]; then
		hint="[y/N]"
	fi
	while true; do
		answer=$(read_answer "$prompt $hint: ")
		if [[ -z $answer ]]; then
			printf -v "$var" '%s' "$default"
			return
		fi
		if value=$(parse_bool "$answer"); then
			printf -v "$var" '%s' "$value"
			return
		fi
		echo "Invalid value [$answer]: please answer yes or no" >&2
	done
}

# ask_count VAR PROMPT DEFAULT: set VAR to a positive integer
ask_count() {
	local var=$1 prompt=$2 default=$3 answer
	if [[ -n ${!var:-} ]]; then
		answer=$(trim "${!var}")
		[[ $answer =~ ^[1-9][0-9]*$ ]] || die "Error: $var=[${!var}] is not valid: expected a positive integer"
		printf -v "$var" '%s' "$answer"
		return
	fi
	while true; do
		answer=$(read_answer "$prompt [default: $default]: ")
		answer=${answer:-$default}
		if [[ $answer =~ ^[1-9][0-9]*$ ]]; then
			printf -v "$var" '%s' "$answer"
			return
		fi
		echo "Invalid value [$answer]: please enter a positive integer" >&2
	done
}

# ask_choice VAR PROMPT DEFAULT ALLOWED...: set VAR to one of the allowed values, case-insensitive
ask_choice() {
	local var=$1 prompt=$2 default=$3
	shift 3
	local allowed=("$@") answer choice
	if [[ -n ${!var:-} ]]; then
		answer=$(trim "${!var}")
		for choice in "${allowed[@]}"; do
			if [[ ${answer,,} == "$choice" ]]; then
				printf -v "$var" '%s' "$choice"
				return
			fi
		done
		die "Error: $var=[${!var}] is not valid: expected one of: ${allowed[*]}"
	fi
	while true; do
		answer=$(read_answer "$prompt [$default]: ")
		answer=${answer:-$default}
		for choice in "${allowed[@]}"; do
			if [[ ${answer,,} == "$choice" ]]; then
				printf -v "$var" '%s' "$choice"
				return
			fi
		done
		echo "Invalid value [$answer]: please enter one of: ${allowed[*]}" >&2
	done
}

# ask_text VAR PROMPT DEFAULT: set VAR to the answer, or to the default when there is none
ask_text() {
	local var=$1 prompt=$2 default=$3 answer
	if [[ -n ${!var:-} ]]; then
		printf -v "$var" '%s' "$(trim "${!var}")"
		return
	fi
	answer=$(read_answer "$prompt [$default]: ")
	printf -v "$var" '%s' "${answer:-$default}"
}

# forbid_child CHILD PARENT [bool]: fail when CHILD is set although PARENT was answered no.
# A boolean child set to false agrees with its parent and is accepted.
forbid_child() {
	local child=$1 parent=$2 kind=${3:-text} value
	if [[ -z ${!child:-} ]]; then
		return 0
	fi
	if [[ $kind == bool ]] && value=$(parse_bool "${!child}") && [[ $value == false ]]; then
		return 0
	fi
	die "Error: $child is set but $parent is false"
}

ask_questions() {
	ask_choice CLUSTER_IDENTITY "Cluster identity (system/user)" system system user

	if [[ -z $NETWORK_OPTION && -t 0 ]]; then
		echo "Network plugin and policy:" >&2
		echo "  1) Azure CNI Overlay + Azure network policy" >&2
		echo "  2) Azure CNI Overlay + Cilium dataplane and network policy" >&2
		echo "  3) Azure CNI Overlay + Calico network policy" >&2
	fi
	ask_choice NETWORK_OPTION "Network plugin and policy (1-3)" 1 1 2 3

	ask_count SYSTEM_NODE_COUNT "Nodes in the [$system_node_pool_name] system node pool" 1
	ask_bool ENABLE_CLUSTER_AUTOSCALER "Enable the cluster autoscaler on the node pools?" true
	ask_bool ENABLE_WORKLOAD_IDENTITY "Enable Microsoft Entra Workload ID?" true
	ask_bool CREATE_KEY_VAULT "Create a Key Vault with the CSI secrets provider?" true
	ask_bool ENABLE_MONITORING "Enable Container Insights with Log Analytics?" true
	ask_bool ENABLE_FILE_CSI_DRIVER "Enable the Azure Files CSI driver?" true
	ask_bool ENABLE_DISK_CSI_DRIVER "Enable the Azure Disk CSI driver?" true

	ask_bool CREATE_VNET "Create a custom virtual network?" true
	if [[ $CREATE_VNET == true ]]; then
		ask_bool CREATE_BASTION "Create an Azure Bastion host?" true
	else
		forbid_child CREATE_BASTION CREATE_VNET bool
		CREATE_BASTION=false
	fi

	ask_bool CREATE_USER_NODE_POOL "Add a user-mode node pool?" true
	if [[ $CREATE_USER_NODE_POOL == true ]]; then
		ask_count USER_NODE_COUNT "Nodes in the [$user_node_pool_name] user node pool" 1
		ask_bool USE_AVAILABILITY_ZONES "Spread the user node pool across availability zones 1-3?" true
	else
		forbid_child USER_NODE_COUNT CREATE_USER_NODE_POOL
		forbid_child USE_AVAILABILITY_ZONES CREATE_USER_NODE_POOL bool
		USER_NODE_COUNT=""
		USE_AVAILABILITY_ZONES=false
	fi

	ask_bool ENABLE_KEDA "Enable KEDA?" true

	ask_bool ENABLE_GATEWAY_API "Enable the managed Gateway API CRDs?" true
	if [[ $ENABLE_GATEWAY_API == true ]]; then
		ask_bool INSTALL_GATEWAY_CONTROLLERS "Install NGINX Gateway Fabric and cert-manager with Helm?" false
	else
		forbid_child INSTALL_GATEWAY_CONTROLLERS ENABLE_GATEWAY_API bool
		INSTALL_GATEWAY_CONTROLLERS=false
	fi

	ask_bool ENABLE_ENTRA_RBAC "Enable Microsoft Entra ID authentication with Azure RBAC?" true
	if [[ $ENABLE_ENTRA_RBAC == true ]]; then
		ask_text AAD_ADMIN_GROUP_OBJECT_IDS "Object IDs of the Entra ID admin groups, comma-separated" \
			"$default_aad_admin_group_object_ids"
	else
		forbid_child AAD_ADMIN_GROUP_OBJECT_IDS ENABLE_ENTRA_RBAC
		AAD_ADMIN_GROUP_OBJECT_IDS=""
	fi
}

# Values that follow from the answers
derive_settings() {
	case $NETWORK_OPTION in
	1)
		network_policy="azure"
		network_dataplane="azure"
		network_description="Azure CNI Overlay + Azure network policy"
		;;
	2)
		network_policy="cilium"
		network_dataplane="cilium"
		network_description="Azure CNI Overlay + Cilium dataplane and network policy"
		;;
	3)
		network_policy="calico"
		network_dataplane="azure"
		network_description="Azure CNI Overlay + Calico network policy"
		;;
	esac

	# The autoscaler range always includes the requested node count
	if ((SYSTEM_NODE_COUNT < min_count)); then
		min_count=$SYSTEM_NODE_COUNT
	fi
	if ((SYSTEM_NODE_COUNT > max_count)); then
		max_count=$SYSTEM_NODE_COUNT
	fi
	if [[ $CREATE_USER_NODE_POOL == true ]]; then
		if ((USER_NODE_COUNT < node_pool_min_count)); then
			node_pool_min_count=$USER_NODE_COUNT
		fi
		if ((USER_NODE_COUNT > node_pool_max_count)); then
			node_pool_max_count=$USER_NODE_COUNT
		fi
	fi
}

summary_line() {
	printf '  %-36s %s\n' "$1:" "$2"
}

# The value of a question that depends on another one, or - when that one was answered no
child_value() {
	if [[ $1 == true ]]; then
		echo "$2"
	else
		echo "-"
	fi
}

print_resources() {
	local subnets=$system_subnet_name pools=$system_node_pool_name
	echo "  - Resource group [$resource_group_name]"
	echo "  - Container registry [$acr_name]"
	if [[ $CLUSTER_IDENTITY == user ]]; then
		echo "  - Managed identity [$aks_managed_identity_name]"
	fi
	if [[ $ENABLE_MONITORING == true ]]; then
		echo "  - Log Analytics workspace [$log_analytics_name]"
	fi
	if [[ $CREATE_KEY_VAULT == true ]]; then
		echo "  - Key Vault [$key_vault_name]"
	fi
	if [[ $CREATE_VNET == true ]]; then
		if [[ $CREATE_USER_NODE_POOL == true ]]; then
			subnets="$subnets, $user_subnet_name"
		fi
		if [[ $CREATE_BASTION == true ]]; then
			subnets="$subnets, $bastion_subnet_name"
		fi
		echo "  - Virtual network [$virtual_network_name] with the subnets $subnets"
	fi
	if [[ $CREATE_BASTION == true ]]; then
		echo "  - Bastion host [$bastion_host_name] and its public IP address"
	fi
	if [[ $CREATE_USER_NODE_POOL == true ]]; then
		pools="$pools, $user_node_pool_name"
	fi
	echo "  - AKS cluster [$aks_cluster_name] with the node pools $pools"
	if [[ $INSTALL_GATEWAY_CONTROLLERS == true ]]; then
		echo "  - Helm releases of NGINX Gateway Fabric and cert-manager"
	fi
}

print_warnings() {
	if [[ $ENABLE_WORKLOAD_IDENTITY == false ]]; then
		echo "WARNING: without Workload ID these samples and tutorials do not work: samples/web-app-managed-identity and" \
			"samples/web-app-app-configuration (Python and .NET), tutorials/keda/event-hubs, tutorials/keda/queue-storage," \
			"tutorials/keda/service-bus and tutorials/key-vault-csi-driver/workload-identity."
	fi
	if [[ $ENABLE_FILE_CSI_DRIVER == false ]]; then
		echo "WARNING: without the Azure Files CSI driver, samples/web-app-file-storage does not work: it mounts its" \
			"Azure file share through that driver."
	elif [[ $CREATE_VNET == false ]]; then
		echo "WARNING: without the custom virtual network, samples/web-app-file-storage works over SMB only: its NFS mode" \
			"needs node subnets with the Microsoft.Storage service endpoint."
	fi
	if [[ $ENABLE_DISK_CSI_DRIVER == false ]]; then
		echo "WARNING: without the Azure Disk CSI driver, samples/web-app-in-cluster-postgresql does not work: its" \
			"database volume uses the managed-csi-premium storage class that driver provides."
	fi
	if [[ $ENABLE_ENTRA_RBAC == true && ! $AAD_ADMIN_GROUP_OBJECT_IDS =~ $guid_list_re ]]; then
		echo "WARNING: AAD_ADMIN_GROUP_OBJECT_IDS is [$AAD_ADMIN_GROUP_OBJECT_IDS]: on Azure, set it to the object IDs of" \
			"real Entra ID groups, or nobody can administer the cluster."
	fi
}

print_summary() {
	echo "Configuration of the [$aks_cluster_name] AKS cluster in the [$resource_group_name] resource group:"
	summary_line "Subscription" "$subscription_name"
	summary_line "Cluster identity" "$CLUSTER_IDENTITY"
	summary_line "Network" "$NETWORK_OPTION ($network_description)"
	summary_line "System pool nodes" "$SYSTEM_NODE_COUNT"
	summary_line "Cluster autoscaler" "$(yes_no "$ENABLE_CLUSTER_AUTOSCALER")"
	summary_line "Workload ID" "$(yes_no "$ENABLE_WORKLOAD_IDENTITY")"
	summary_line "Key Vault + CSI secrets provider" "$(yes_no "$CREATE_KEY_VAULT")"
	summary_line "Monitoring (Container Insights)" "$(yes_no "$ENABLE_MONITORING")"
	summary_line "Azure Files CSI driver" "$(yes_no "$ENABLE_FILE_CSI_DRIVER")"
	summary_line "Azure Disk CSI driver" "$(yes_no "$ENABLE_DISK_CSI_DRIVER")"
	summary_line "Custom virtual network" "$(yes_no "$CREATE_VNET")"
	summary_line "Azure Bastion" "$(child_value "$CREATE_VNET" "$(yes_no "$CREATE_BASTION")")"
	summary_line "User node pool" "$(yes_no "$CREATE_USER_NODE_POOL")"
	summary_line "User pool nodes" "$(child_value "$CREATE_USER_NODE_POOL" "$USER_NODE_COUNT")"
	summary_line "User pool zones" "$(child_value "$CREATE_USER_NODE_POOL" "$(yes_no "$USE_AVAILABILITY_ZONES")")"
	summary_line "KEDA" "$(yes_no "$ENABLE_KEDA")"
	summary_line "Gateway API (managed CRDs)" "$(yes_no "$ENABLE_GATEWAY_API")"
	summary_line "NGINX Gateway Fabric + cert-manager" \
		"$(child_value "$ENABLE_GATEWAY_API" "$(yes_no "$INSTALL_GATEWAY_CONTROLLERS")")"
	summary_line "Entra ID + Azure RBAC" "$(yes_no "$ENABLE_ENTRA_RBAC")"
	summary_line "Entra ID admin groups" "$(child_value "$ENABLE_ENTRA_RBAC" "$AAD_ADMIN_GROUP_OBJECT_IDS")"
	summary_line "ACNS" "yes (always)"
	echo "Resources (existing ones are kept):"
	print_resources
	print_warnings
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

# start_job NAME FUNCTION: run FUNCTION in the background, its output kept in a log until wait_job NAME prints it,
# so the jobs never interleave their messages. A dry run runs FUNCTION in place, which keeps its output in order.
declare -A job_pids=() job_logs=()

start_job() {
	local name=$1 function=$2 log_file
	if [[ $DRY_RUN == true ]]; then
		"$function"
		return
	fi
	log_file=$(mktemp)
	job_logs[$name]=$log_file
	("$function") >"$log_file" 2>&1 &
	job_pids[$name]=$!
	log "Started the [$name] job in the background"
}

# wait_job NAME: wait for a job started with start_job and print its output; a failed job stops the script
wait_job() {
	local name=$1 pid log_file
	pid=${job_pids[$name]:-}
	if [[ -z $pid ]]; then
		return 0
	fi
	log_file=${job_logs[$name]}
	unset "job_pids[$name]"
	if wait "$pid"; then
		cat "$log_file"
		rm -f "$log_file"
		return 0
	fi
	cat "$log_file" >&2
	rm -f "$log_file"
	die "Error: [$name] failed"
}

# On exit, stop the jobs still running (an error elsewhere ends the script early) and remove their logs
cleanup_jobs() {
	local name
	for name in "${!job_pids[@]}"; do
		kill "${job_pids[$name]}" 2>/dev/null || true
	done
	for name in "${!job_logs[@]}"; do
		rm -f "${job_logs[$name]}"
	done
}

# Check the tools a real run needs, before anything is created
check_prerequisites() {
	local tools=(az kubectl) tool missing=0 cli_version lowest
	if [[ $INSTALL_GATEWAY_CONTROLLERS == true ]]; then
		tools+=(helm)
	fi
	for tool in "${tools[@]}"; do
		if ! command -v "$tool" >/dev/null 2>&1; then
			echo "Error: required tool '$tool' is not installed or not in PATH." >&2
			missing=1
		fi
	done
	if ((missing)); then
		echo "Please install the missing tool(s) and re-run the script." >&2
		echo "  az:      https://learn.microsoft.com/cli/azure/install-azure-cli" >&2
		echo "  kubectl: https://kubernetes.io/docs/tasks/tools/ (or: az aks install-cli)" >&2
		echo "  helm:    https://helm.sh/docs/intro/install/" >&2
		exit 1
	fi
	# On Azure, the kubeconfig of a cluster with Entra ID signs in through kubelogin; the emulator's does not
	if [[ $ENABLE_ENTRA_RBAC == true ]] && ! command -v kubelogin >/dev/null 2>&1; then
		echo "WARNING: kubelogin is not installed: on Azure, kubectl needs it to sign in to a cluster with Entra ID" \
			"(install it with: az aks install-cli). The LocalStack emulator does not need it."
	fi

	# The managed Gateway API is part of the core Azure CLI from version 2.86.0: no aks-preview extension needed
	if [[ $ENABLE_GATEWAY_API == true ]]; then
		cli_version=$(az version --query '"azure-cli"' --output tsv 2>/dev/null) || cli_version=""
		lowest=$(printf '%s\n' "$minimum_gateway_api_cli_version" "$cli_version" | sort -V)
		if [[ -z $cli_version || ${lowest%%$'\n'*} != "$minimum_gateway_api_cli_version" ]]; then
			die "Error: Gateway API needs azure-cli $minimum_gateway_api_cli_version or later; found [$cli_version]."
		fi
	fi
}

# compare_setting LABEL CLUSTER_VALUE WANTED_VALUE: record a difference between the cluster and the answers
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

# A comma-separated list of object IDs without spaces, in lower case and sorted, so that two lists compare equal
# whatever their order and letter case
normalize_ids() {
	printf '%s\n' "$1" | tr ',' '\n' | awk '{ gsub(/[[:space:]]/, ""); if ($0 != "") print tolower($0) }' |
		sort | paste -sd, -
}

# compare_admin_groups WANTED: record a difference between the Entra ID admin groups of the existing cluster and
# WANTED, a comma-separated list of object IDs
compare_admin_groups() {
	local cluster_groups
	cluster_groups=$(query "" az aks show \
		--name "$aks_cluster_name" \
		--resource-group "$resource_group_name" \
		--query "join(',', aadProfile.adminGroupObjectIDs || \`[]\`)" \
		--output tsv \
		--only-show-errors)
	compare_setting "Entra ID admin groups" "$(normalize_ids "$cluster_groups")" "$(normalize_ids "$1")"
}

# compare_pool_size LABEL POOL NODE_COUNT MIN_COUNT MAX_COUNT: record a difference in the size of a node pool of the
# existing cluster: its autoscaler range when the autoscaler is on, since the autoscaler itself changes the node
# count, and its node count when the autoscaler is off
compare_pool_size() {
	local size=() autoscaler
	mapfile -t size < <(query "" az aks show \
		--name "$aks_cluster_name" \
		--resource-group "$resource_group_name" \
		--query "agentPoolProfiles[?name=='$2'] | [0].[count, minCount, maxCount, enableAutoScaling]" \
		--output tsv \
		--only-show-errors)
	((${#size[@]} == 4)) || die "Failed to read the size of the [$2] node pool of the existing [$aks_cluster_name] AKS cluster"
	autoscaler=$(cluster_bool "${size[3]}")
	if [[ $autoscaler != "$(yes_no "$ENABLE_CLUSTER_AUTOSCALER")" ]]; then
		compare_setting "$1 autoscaler" "$autoscaler" "$(yes_no "$ENABLE_CLUSTER_AUTOSCALER")"
	elif [[ $ENABLE_CLUSTER_AUTOSCALER == true ]]; then
		compare_setting "$1 autoscaler range" "${size[1]}-${size[2]}" "$4-$5"
	else
		compare_setting "$1 nodes" "${size[0]}" "$3"
	fi
}

# When the cluster already exists, stop before creating anything if it was built with different answers: most of
# them cannot be changed on an existing cluster, and the later steps would fail half way. Sets cluster_exists.
check_existing_cluster() {
	local fields=() differences=() cluster_identity cluster_vnet cluster_user_pool cluster_zones cluster_gateway
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
	cluster_zones=no
	if [[ ${fields[17]} != 0 ]]; then
		cluster_zones=yes
	fi
	cluster_gateway=no
	if [[ ${fields[12]} == Standard ]]; then
		cluster_gateway=yes
	fi

	compare_setting "Cluster identity" "$cluster_identity" "$CLUSTER_IDENTITY"
	compare_setting "Network" "${fields[1]}/${fields[2]}/${fields[3]}/${fields[4]}" \
		"$network_plugin/$network_plugin_mode/$network_policy/$network_dataplane"
	compare_setting "Cluster autoscaler" "$(cluster_bool "${fields[6]}")" "$(yes_no "$ENABLE_CLUSTER_AUTOSCALER")"
	# Workload ID alone: AKS turns the OIDC issuer (fields[9]) on for every new cluster from Kubernetes 1.34, and
	# it cannot be turned off, so it is on even when Workload ID was not requested
	compare_setting "Workload ID" "$(cluster_bool "${fields[10]}")" "$(yes_no "$ENABLE_WORKLOAD_IDENTITY")"
	compare_setting "Key Vault + CSI secrets provider" "$(cluster_bool "${fields[7]}")" "$(yes_no "$CREATE_KEY_VAULT")"
	compare_setting "Monitoring (Container Insights)" "$(cluster_bool "${fields[8]}")" "$(yes_no "$ENABLE_MONITORING")"
	# A Files driver that is off is fine when it is wanted: ensure_storage_drivers turns it on below
	if [[ $(cluster_bool "${fields[18]}") == yes ]]; then
		compare_setting "Azure Files CSI driver" yes "$(yes_no "$ENABLE_FILE_CSI_DRIVER")"
	fi
	compare_setting "Azure Disk CSI driver" "$(cluster_bool "${fields[19]}")" "$(yes_no "$ENABLE_DISK_CSI_DRIVER")"
	compare_setting "Custom virtual network" "$cluster_vnet" "$(yes_no "$CREATE_VNET")"
	# A missing user pool is fine when one is wanted: it is added below
	if [[ $cluster_user_pool == yes ]]; then
		compare_setting "User node pool" yes "$(yes_no "$CREATE_USER_NODE_POOL")"
		if [[ $CREATE_USER_NODE_POOL == true ]]; then
			compare_setting "User pool zones" "$cluster_zones" "$(yes_no "$USE_AVAILABILITY_ZONES")"
		fi
	fi
	compare_setting "KEDA" "$(cluster_bool "${fields[11]}")" "$(yes_no "$ENABLE_KEDA")"
	compare_setting "Gateway API (managed CRDs)" "$cluster_gateway" "$(yes_no "$ENABLE_GATEWAY_API")"
	compare_setting "Entra ID + Azure RBAC" "$(cluster_pair "${fields[13]}" "${fields[14]}")" "$(yes_no "$ENABLE_ENTRA_RBAC")"
	compare_setting "ACNS" "$(cluster_bool "${fields[15]}")" yes
	# The admin groups only when both sides have Entra ID; otherwise the Entra ID line above already differs
	if [[ $(cluster_bool "${fields[13]}") == yes && $ENABLE_ENTRA_RBAC == true ]]; then
		compare_admin_groups "$AAD_ADMIN_GROUP_OBJECT_IDS"
	fi
	# Node pool sizes. The system pool only when its autoscaler matches, which the autoscaler line above compares
	if [[ $(cluster_bool "${fields[6]}") == "$(yes_no "$ENABLE_CLUSTER_AUTOSCALER")" ]]; then
		compare_pool_size "System pool" "$system_node_pool_name" "$SYSTEM_NODE_COUNT" "$min_count" "$max_count"
	fi
	if [[ $cluster_user_pool == yes && $CREATE_USER_NODE_POOL == true ]]; then
		compare_pool_size "User pool" "$user_node_pool_name" "$USER_NODE_COUNT" "$node_pool_min_count" \
			"$node_pool_max_count"
	fi

	if ((${#differences[@]} > 0)); then
		echo "The [$aks_cluster_name] cluster already exists with a different configuration:" >&2
		printf '%s\n' "${differences[@]}" >&2
		echo "Delete it first: az group delete --name $resource_group_name --yes" >&2
		echo "or re-run with answers that match the cluster." >&2
		exit 1
	fi
	log "The existing [$aks_cluster_name] AKS cluster matches this configuration: provisioning what is missing"
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

# The bastion commands live in the bastion CLI extension. It is added before any background job starts:
# installing an extension while other az processes load theirs is not safe.
add_bastion_extension() {
	log "Adding or upgrading the [bastion] Azure CLI extension..."
	run az extension add --upgrade --name bastion --only-show-errors ||
		log "Could not add or upgrade the [bastion] extension: the installed version, if any, is used"
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

ensure_cluster_identity() {
	log "Checking if [$aks_managed_identity_name] user-assigned managed identity actually exists in the [$resource_group_name] resource group..."
	if exists az identity show --name "$aks_managed_identity_name" --resource-group "$resource_group_name" --only-show-errors; then
		log "[$aks_managed_identity_name] user-assigned managed identity already exists in the [$resource_group_name] resource group"
		return
	fi
	log "Creating [$aks_managed_identity_name] user-assigned managed identity in the [$resource_group_name] resource group..."
	run az identity create \
		--name "$aks_managed_identity_name" \
		--resource-group "$resource_group_name" \
		--only-show-errors >/dev/null ||
		die "Failed to create [$aks_managed_identity_name] user-assigned managed identity in the [$resource_group_name] resource group"
	log "[$aks_managed_identity_name] user-assigned managed identity successfully created"
}

ensure_log_analytics() {
	log "Checking if [$log_analytics_name] log analytics workspace actually exists in the [$resource_group_name] resource group..."
	if exists az monitor log-analytics workspace show --name "$log_analytics_name" --resource-group "$resource_group_name" --only-show-errors; then
		log "[$log_analytics_name] log analytics workspace already exists in the [$resource_group_name] resource group"
		return
	fi
	log "Creating [$log_analytics_name] log analytics workspace in the [$resource_group_name] resource group..."
	run az monitor log-analytics workspace create \
		--name "$log_analytics_name" \
		--resource-group "$resource_group_name" \
		--identity-type SystemAssigned \
		--sku "$log_analytics_sku" \
		--location "$location" \
		--only-show-errors >/dev/null ||
		die "Failed to create [$log_analytics_name] log analytics workspace in the [$resource_group_name] resource group"
	log "[$log_analytics_name] log analytics workspace successfully created in the [$resource_group_name] resource group"
}

ensure_key_vault() {
	local deleted_key_vault_location

	# Recover the key vault if a previous run left it soft-deleted: the name stays reserved for the retention
	# period, so creating it again fails. Recovering keeps its contents, which is what a re-run wants. The
	# vault's own location is used, not $location: a soft-deleted vault stays in the region it was deleted in.
	deleted_key_vault_location=$(query "" az keyvault list-deleted \
		--query "[?name=='$key_vault_name'].properties.location | [0]" \
		--output tsv \
		--only-show-errors 2>/dev/null) || deleted_key_vault_location=""
	if [[ -n $deleted_key_vault_location ]]; then
		log "[$key_vault_name] key vault exists in a soft-deleted state in [$deleted_key_vault_location]: recovering it..."
		run az keyvault recover \
			--name "$key_vault_name" \
			--location "$deleted_key_vault_location" \
			--only-show-errors >/dev/null ||
			die "Failed to recover the soft-deleted [$key_vault_name] key vault; discard it with: az keyvault purge --name $key_vault_name --location $deleted_key_vault_location"
		log "[$key_vault_name] key vault successfully recovered"
	fi

	log "Checking if [$key_vault_name] key vault actually exists in the [$resource_group_name] resource group..."
	if exists az keyvault show --name "$key_vault_name" --resource-group "$resource_group_name" --only-show-errors; then
		log "[$key_vault_name] key vault already exists in the [$resource_group_name] resource group"
		return
	fi
	log "Creating [$key_vault_name] key vault in the [$resource_group_name] resource group..."
	run az keyvault create \
		--name "$key_vault_name" \
		--resource-group "$resource_group_name" \
		--location "$location" \
		--enable-rbac-authorization true \
		--only-show-errors >/dev/null ||
		die "Failed to create [$key_vault_name] key vault in the [$resource_group_name] resource group"
	log "[$key_vault_name] key vault successfully created"
}

# ensure_subnet NAME PREFIX: create a subnet of the virtual network unless it exists
ensure_subnet() {
	local name=$1 prefix=$2
	log "Checking if [$name] subnet actually exists in the [$virtual_network_name] virtual network..."
	if exists az network vnet subnet show --name "$name" --vnet-name "$virtual_network_name" --resource-group "$resource_group_name" --only-show-errors; then
		log "[$name] subnet already exists in the [$virtual_network_name] virtual network"
		return
	fi
	log "Creating [$name] subnet in the [$virtual_network_name] virtual network..."
	run az network vnet subnet create \
		--name "$name" \
		--vnet-name "$virtual_network_name" \
		--resource-group "$resource_group_name" \
		--address-prefix "$prefix" \
		--only-show-errors >/dev/null ||
		die "Failed to create [$name] subnet in the [$virtual_network_name] virtual network"
	log "[$name] subnet successfully created in the [$virtual_network_name] virtual network"
}

# Enable the Microsoft.Storage service endpoint on a node subnet. An Azure Files NFS share can only be reached
# from a virtual network, so the Azure Files CSI driver needs this endpoint to mount an NFS volume on a node.
ensure_storage_service_endpoint() {
	local subnet=$1 current_service_endpoints=() service
	mapfile -t current_service_endpoints < <(query "" az network vnet subnet show \
		--name "$subnet" \
		--vnet-name "$virtual_network_name" \
		--resource-group "$resource_group_name" \
		--query "serviceEndpoints[].service" \
		--output tsv \
		--only-show-errors 2>/dev/null)
	for service in "${current_service_endpoints[@]}"; do
		if [[ $service == Microsoft.Storage ]]; then
			log "The [Microsoft.Storage] service endpoint is already enabled on the [$subnet] subnet"
			return
		fi
	done
	log "Enabling the [Microsoft.Storage] service endpoint on the [$subnet] subnet..."
	# --service-endpoints replaces the whole list, so the endpoints already on the subnet are passed along
	run az network vnet subnet update \
		--name "$subnet" \
		--vnet-name "$virtual_network_name" \
		--resource-group "$resource_group_name" \
		--service-endpoints "${current_service_endpoints[@]}" Microsoft.Storage \
		--only-show-errors >/dev/null ||
		die "Failed to enable the [Microsoft.Storage] service endpoint on the [$subnet] subnet"
	log "The [Microsoft.Storage] service endpoint was successfully enabled on the [$subnet] subnet"
}

ensure_virtual_network() {
	local node_subnets=("$system_subnet_name") subnet
	log "Checking if [$virtual_network_name] virtual network actually exists in the [$resource_group_name] resource group..."
	if exists az network vnet show --name "$virtual_network_name" --resource-group "$resource_group_name" --only-show-errors; then
		log "[$virtual_network_name] virtual network already exists in the [$resource_group_name] resource group"
	else
		log "Creating [$virtual_network_name] virtual network in the [$resource_group_name] resource group..."
		run az network vnet create \
			--name "$virtual_network_name" \
			--resource-group "$resource_group_name" \
			--location "$location" \
			--address-prefixes "$virtual_network_address_prefix" \
			--subnet-name "$system_subnet_name" \
			--subnet-prefix "$system_subnet_prefix" \
			--only-show-errors >/dev/null ||
			die "Failed to create [$virtual_network_name] virtual network in the [$resource_group_name] resource group"
		log "[$virtual_network_name] virtual network successfully created in the [$resource_group_name] resource group"
	fi
	if [[ $CREATE_USER_NODE_POOL == true ]]; then
		ensure_subnet "$user_subnet_name" "$user_subnet_prefix"
		node_subnets+=("$user_subnet_name")
	fi
	if [[ $CREATE_BASTION == true ]]; then
		ensure_subnet "$bastion_subnet_name" "$bastion_subnet_prefix"
	fi
	if [[ $ENABLE_FILE_CSI_DRIVER == true ]]; then
		for subnet in "${node_subnets[@]}"; do
			ensure_storage_service_endpoint "$subnet"
		done
	fi
}

# The bastion host goes into the AzureBastionSubnet created with the virtual network: Azure looks that subnet up
# by name. Nothing else waits for it, so it is created while the cluster is.
ensure_bastion() {
	log "Checking if [$bastion_public_ip_name] public IP address actually exists in the [$resource_group_name] resource group..."
	if exists az network public-ip show --name "$bastion_public_ip_name" --resource-group "$resource_group_name" --only-show-errors; then
		log "[$bastion_public_ip_name] public IP address already exists in the [$resource_group_name] resource group"
	else
		# Azure Bastion requires a Standard SKU public IP with a static allocation method
		log "Creating [$bastion_public_ip_name] public IP address in the [$resource_group_name] resource group..."
		run az network public-ip create \
			--name "$bastion_public_ip_name" \
			--resource-group "$resource_group_name" \
			--location "$location" \
			--sku Standard \
			--allocation-method Static \
			--only-show-errors >/dev/null ||
			die "Failed to create [$bastion_public_ip_name] public IP address in the [$resource_group_name] resource group"
		log "[$bastion_public_ip_name] public IP address successfully created in the [$resource_group_name] resource group"
	fi

	log "Checking if [$bastion_host_name] bastion host actually exists in the [$resource_group_name] resource group..."
	if exists az network bastion show --name "$bastion_host_name" --resource-group "$resource_group_name" --only-show-errors; then
		log "[$bastion_host_name] bastion host already exists in the [$resource_group_name] resource group"
		return
	fi
	log "Creating [$bastion_host_name] bastion host in the [$resource_group_name] resource group (this takes several minutes)..."
	run az network bastion create \
		--name "$bastion_host_name" \
		--resource-group "$resource_group_name" \
		--location "$location" \
		--vnet-name "$virtual_network_name" \
		--public-ip-address "$bastion_public_ip_name" \
		--sku Basic \
		--only-show-errors >/dev/null ||
		die "Failed to create [$bastion_host_name] bastion host in the [$resource_group_name] resource group"
	log "[$bastion_host_name] bastion host successfully created in the [$resource_group_name] resource group"
}

# Read the IDs the cluster needs, once the jobs that create those resources are done
read_resource_ids() {
	if [[ $ENABLE_MONITORING == true ]]; then
		workspace_resource_id=$(query "<log-analytics-workspace-id>" az monitor log-analytics workspace show \
			--name "$log_analytics_name" \
			--resource-group "$resource_group_name" \
			--query id \
			--output tsv \
			--only-show-errors)
		[[ -n $workspace_resource_id ]] || die "Failed to retrieve the id for the [$log_analytics_name] log analytics workspace"
	fi
	if [[ $CREATE_VNET == true ]]; then
		virtual_network_id=$(query "<virtual-network-id>" az network vnet show \
			--name "$virtual_network_name" \
			--resource-group "$resource_group_name" \
			--query id \
			--output tsv \
			--only-show-errors)
		[[ -n $virtual_network_id ]] || die "Failed to retrieve the resource ID for the [$virtual_network_name] virtual network"
		system_subnet_id=$(query "<system-subnet-id>" az network vnet subnet show \
			--name "$system_subnet_name" \
			--vnet-name "$virtual_network_name" \
			--resource-group "$resource_group_name" \
			--query id \
			--output tsv \
			--only-show-errors)
		[[ -n $system_subnet_id ]] || die "Failed to retrieve the id for the [$system_subnet_name] subnet"
		if [[ $CREATE_USER_NODE_POOL == true ]]; then
			user_subnet_id=$(query "<user-subnet-id>" az network vnet subnet show \
				--name "$user_subnet_name" \
				--vnet-name "$virtual_network_name" \
				--resource-group "$resource_group_name" \
				--query id \
				--output tsv \
				--only-show-errors)
			[[ -n $user_subnet_id ]] || die "Failed to retrieve the id for the [$user_subnet_name] subnet"
		fi
	fi
	if [[ $CLUSTER_IDENTITY == user ]]; then
		managed_identity_id=$(query "<cluster-identity-id>" az identity show \
			--name "$aks_managed_identity_name" \
			--resource-group "$resource_group_name" \
			--query id \
			--output tsv \
			--only-show-errors)
		[[ -n $managed_identity_id ]] || die "Failed to retrieve the id for the [$aks_managed_identity_name] managed identity"
		managed_identity_principal_id=$(query "<cluster-identity-principal-id>" az identity show \
			--name "$aks_managed_identity_name" \
			--resource-group "$resource_group_name" \
			--query principalId \
			--output tsv \
			--only-show-errors)
		[[ -n $managed_identity_principal_id ]] || die "Failed to retrieve the principalId for the [$aks_managed_identity_name] managed identity"
	fi
}

# Fill aks_create_args with the az aks create arguments for the chosen features
build_aks_create_args() {
	local addons=() addon_list
	if [[ $ENABLE_MONITORING == true ]]; then
		addons+=(monitoring)
	fi
	if [[ $CREATE_KEY_VAULT == true ]]; then
		addons+=(azure-keyvault-secrets-provider)
	fi

	aks_create_args=(
		--name "$aks_cluster_name"
		--resource-group "$resource_group_name"
		--os-sku "$os_sku"
		--node-osdisk-size "$os_disk_size"
		--node-osdisk-type "$os_disk_type"
	)
	if [[ $CREATE_VNET == true ]]; then
		aks_create_args+=(--vnet-subnet-id "$system_subnet_id")
	fi
	aks_create_args+=(--nodepool-name "$system_node_pool_name")
	if [[ $ENABLE_CLUSTER_AUTOSCALER == true ]]; then
		aks_create_args+=(--enable-cluster-autoscaler --node-count "$SYSTEM_NODE_COUNT" --min-count "$min_count" --max-count "$max_count")
	else
		aks_create_args+=(--node-count "$SYSTEM_NODE_COUNT")
	fi
	aks_create_args+=(
		--max-pods "$max_pods"
		--location "$location"
		--kubernetes-version "$kubernetes_version"
	)
	if [[ -f $ssh_key_value ]]; then
		aks_create_args+=(--ssh-key-value "$ssh_key_value")
	else
		aks_create_args+=(--no-ssh-key)
	fi
	aks_create_args+=(--node-vm-size "$node_size")
	if [[ $ENABLE_FILE_CSI_DRIVER == false ]]; then
		aks_create_args+=(--disable-file-driver)
	fi
	if [[ $ENABLE_DISK_CSI_DRIVER == false ]]; then
		aks_create_args+=(--disable-disk-driver)
	fi
	if ((${#addons[@]} > 0)); then
		addon_list=$(
			IFS=,
			echo "${addons[*]}"
		)
		aks_create_args+=(--enable-addons "$addon_list")
	fi
	if [[ $ENABLE_MONITORING == true ]]; then
		aks_create_args+=(--workspace-resource-id "$workspace_resource_id")
	fi
	aks_create_args+=(
		--network-dataplane "$network_dataplane"
		--network-policy "$network_policy"
		--network-plugin "$network_plugin"
		--network-plugin-mode "$network_plugin_mode"
		--pod-cidr "$pod_cidr"
		--dns-service-ip "$dns_service_ip"
		--service-cidr "$service_cidr"
		--enable-acns
	)
	if [[ $ENABLE_GATEWAY_API == true ]]; then
		aks_create_args+=(--enable-gateway-api)
	fi
	if [[ $ENABLE_KEDA == true ]]; then
		aks_create_args+=(--enable-keda)
	fi
	aks_create_args+=(--enable-managed-identity)
	if [[ $CLUSTER_IDENTITY == user ]]; then
		aks_create_args+=(--assign-identity "$managed_identity_id")
	fi
	if [[ $ENABLE_WORKLOAD_IDENTITY == true ]]; then
		aks_create_args+=(--enable-workload-identity --enable-oidc-issuer)
	fi
	if [[ $ENABLE_ENTRA_RBAC == true ]]; then
		aks_create_args+=(--enable-aad --enable-azure-rbac --aad-admin-group-object-ids "$AAD_ADMIN_GROUP_OBJECT_IDS")
	fi
	aks_create_args+=(
		--attach-acr "$acr_name"
		--tier free
		--auto-upgrade-channel none
		--node-os-upgrade-channel None
		--tags provisioning=az-cli
		--nodepool-tags "os_disk_type=$os_disk_type" "os_type=$os_type"
		--nodepool-labels "os_disk_type=$os_disk_type" "os_type=$os_type"
		--only-show-errors
	)
}

ensure_cluster() {
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

	build_aks_create_args
	log "Creating [$aks_cluster_name] aks cluster in the [$resource_group_name] resource group..."
	run az aks create "${aks_create_args[@]}" >/dev/null ||
		die "Failed to create [$aks_cluster_name] aks cluster in the [$resource_group_name] resource group"
	log "[$aks_cluster_name] aks cluster successfully created in the [$resource_group_name] resource group"
}

# Make sure the Azure Files CSI driver and the CSI snapshot controller are enabled, when the driver is wanted. AKS
# enables both by default; samples/web-app-file-storage depends on the driver, so a cluster where it was turned off is
# repaired. The update runs only when needed, because az aks update is a long-running operation.
ensure_storage_drivers() {
	local file_csi_driver_enabled snapshot_controller_enabled
	log "Checking if the Azure Files CSI driver is enabled on the [$aks_cluster_name] AKS cluster..."
	file_csi_driver_enabled=$(query "true" az aks show \
		--name "$aks_cluster_name" \
		--resource-group "$resource_group_name" \
		--query storageProfile.fileCsiDriver.enabled \
		--output tsv \
		--only-show-errors)
	snapshot_controller_enabled=$(query "true" az aks show \
		--name "$aks_cluster_name" \
		--resource-group "$resource_group_name" \
		--query storageProfile.snapshotController.enabled \
		--output tsv \
		--only-show-errors)
	if [[ ${file_csi_driver_enabled,,} == true && ${snapshot_controller_enabled,,} == true ]]; then
		log "The Azure Files CSI driver and the CSI snapshot controller are already enabled on the [$aks_cluster_name] AKS cluster"
		return
	fi
	log "Enabling the Azure Files CSI driver and the CSI snapshot controller on the [$aks_cluster_name] AKS cluster..."
	run az aks update \
		--name "$aks_cluster_name" \
		--resource-group "$resource_group_name" \
		--enable-file-driver \
		--enable-snapshot-controller \
		--yes \
		--only-show-errors >/dev/null ||
		die "Failed to enable the Azure Files CSI driver on the [$aks_cluster_name] AKS cluster"
	log "The Azure Files CSI driver and the CSI snapshot controller were successfully enabled on the [$aks_cluster_name] AKS cluster"
}

# assign_role ROLE PRINCIPAL_ID SCOPE_ID SCOPE_DESCRIPTION: create the role assignment unless it exists, retrying
# because a new identity can take a few seconds to become visible to Azure RBAC
assign_role() {
	local role=$1 principal_id=$2 scope_id=$3 scope_description=$4 current attempt
	log "Checking if the [$principal_id] principal has the [$role] role assignment on the $scope_description..."
	current=$(query "" az role assignment list \
		--assignee "$principal_id" \
		--scope "$scope_id" \
		--query "[?roleDefinitionName=='$role'].roleDefinitionName" \
		--output tsv 2>/dev/null) || current=""
	if [[ $current == "$role" ]]; then
		log "The [$principal_id] principal already has the [$role] role assignment on the $scope_description"
		return
	fi
	for ((attempt = 1; attempt <= RETRY_COUNT; attempt++)); do
		log "Attempt $attempt of $RETRY_COUNT to assign the [$role] role on the $scope_description..."
		if run az role assignment create \
			--assignee "$principal_id" \
			--role "$role" \
			--scope "$scope_id" \
			--only-show-errors >/dev/null; then
			log "Successfully assigned the [$role] role to the [$principal_id] principal on the $scope_description"
			return
		fi
		if ((attempt < RETRY_COUNT)); then
			log "Role assignment failed. Waiting [$SLEEP] seconds before retry..."
			sleep "$SLEEP"
		fi
	done
	die "Failed to assign the [$role] role to the [$principal_id] principal on the $scope_description"
}

ensure_role_assignments() {
	local cluster_principal_id node_resource_group_name node_resource_group_id kv_secret_provider_object_id

	# A user-assigned cluster identity gets Contributor on the node resource group, as in the original script
	if [[ $CLUSTER_IDENTITY == user ]]; then
		node_resource_group_name=$(query "<node-resource-group>" az aks show \
			--name "$aks_cluster_name" \
			--resource-group "$resource_group_name" \
			--query nodeResourceGroup \
			--output tsv \
			--only-show-errors)
		[[ -n $node_resource_group_name ]] || die "Failed to retrieve the node resource group for the [$aks_cluster_name] AKS cluster"
		node_resource_group_id=$(query "<node-resource-group-id>" az group show \
			--name "$node_resource_group_name" \
			--query id \
			--output tsv \
			--only-show-errors)
		[[ -n $node_resource_group_id ]] || die "Failed to retrieve the resource ID for the [$node_resource_group_name] resource group"
		assign_role "Contributor" "$managed_identity_principal_id" "$node_resource_group_id" \
			"[$node_resource_group_name] node resource group"
	fi

	# The cluster identity manages the node subnets of the custom virtual network
	if [[ $CREATE_VNET == true ]]; then
		if [[ $CLUSTER_IDENTITY == user ]]; then
			cluster_principal_id=$managed_identity_principal_id
		else
			cluster_principal_id=$(query "<cluster-principal-id>" az aks show \
				--name "$aks_cluster_name" \
				--resource-group "$resource_group_name" \
				--query identity.principalId \
				--output tsv \
				--only-show-errors)
			[[ -n $cluster_principal_id ]] || die "Failed to retrieve the principalId for the [$aks_cluster_name] AKS cluster identity"
		fi
		assign_role "Network Contributor" "$cluster_principal_id" "$virtual_network_id" \
			"[$virtual_network_name] virtual network"
	fi

	# The Key Vault Secrets Provider add-on identity reads the vault
	if [[ $CREATE_KEY_VAULT == true ]]; then
		wait_job key-vault
		key_vault_id=$(query "<key-vault-id>" az keyvault show \
			--name "$key_vault_name" \
			--resource-group "$resource_group_name" \
			--query id \
			--output tsv \
			--only-show-errors)
		[[ -n $key_vault_id ]] || die "Failed to retrieve the id for the [$key_vault_name] key vault"
		kv_secret_provider_object_id=$(query "<keyvault-addon-object-id>" az aks show \
			--name "$aks_cluster_name" \
			--resource-group "$resource_group_name" \
			--query addonProfiles.azureKeyvaultSecretsProvider.identity.objectId \
			--output tsv \
			--only-show-errors)
		[[ -n $kv_secret_provider_object_id ]] ||
			die "Failed to retrieve the objectId for the Azure Key Vault Secrets Provider identity in the [$aks_cluster_name] AKS cluster"
		assign_role "Key Vault Administrator" "$kv_secret_provider_object_id" "$key_vault_id" "[$key_vault_name] key vault"
	fi
}

ensure_user_node_pool() {
	local args
	log "Checking if [$aks_cluster_name] aks cluster actually has a user node pool..."
	if exists az aks nodepool show --name "$user_node_pool_name" --cluster-name "$aks_cluster_name" --resource-group "$resource_group_name" --only-show-errors; then
		log "A node pool called [$user_node_pool_name] already exists in the [$aks_cluster_name] AKS cluster"
		return
	fi
	args=(
		--name "$user_node_pool_name"
		--mode "$mode"
		--cluster-name "$aks_cluster_name"
		--resource-group "$resource_group_name"
		--os-type "$os_type"
		--os-sku "$os_sku"
		--node-vm-size "$vm_size"
		--node-osdisk-size "$os_disk_size"
		--node-osdisk-type "$os_disk_type"
	)
	if [[ $ENABLE_CLUSTER_AUTOSCALER == true ]]; then
		args+=(--enable-cluster-autoscaler --node-count "$USER_NODE_COUNT" --min-count "$node_pool_min_count" --max-count "$node_pool_max_count")
	else
		args+=(--node-count "$USER_NODE_COUNT")
	fi
	args+=(
		--max-pods "$node_pool_max_pods"
		--tags provisioning=az-cli
		--labels "os_disk_type=$os_disk_type" "os_type=$os_type"
	)
	if [[ $CREATE_VNET == true ]]; then
		args+=(--vnet-subnet-id "$user_subnet_id")
	fi
	if [[ $USE_AVAILABILITY_ZONES == true ]]; then
		args+=(--zones 1 2 3)
	fi
	args+=(--only-show-errors)
	log "Creating [$user_node_pool_name] node pool in the [$aks_cluster_name] AKS cluster..."
	run az aks nodepool add "${args[@]}" >/dev/null ||
		die "Failed to create the [$user_node_pool_name] node pool in the [$aks_cluster_name] AKS cluster"
	log "[$user_node_pool_name] node pool successfully created in the [$aks_cluster_name] AKS cluster"
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

# The Gateway API implementation the samples use: NGINX Gateway Fabric creates the nginx GatewayClass, and
# cert-manager issues the TLS certificates of the Gateway listeners. Both run on the managed Gateway API CRDs.
# helm_release_deployed NAME NAMESPACE: succeed when the Helm release is installed and deployed. A release left
# failed by an earlier run does not count, so it is installed again.
helm_release_deployed() {
	local deployed
	deployed=$(query "" helm list --namespace "$2" --deployed --filter "^$1\$" --short 2>/dev/null) || deployed=""
	[[ $deployed == "$1" ]]
}

install_gateway_controllers() {
	local cert_manager_args

	# A deployed release is kept: a re-run only adds what is missing, and upgrading NGINX Gateway Fabric with helm
	# alone would leave its CRDs behind, because helm never upgrades the CRDs a chart ships
	if helm_release_deployed ngf nginx-gateway; then
		log "NGINX Gateway Fabric is already installed in the [nginx-gateway] namespace"
	else
		log "Installing NGINX Gateway Fabric..."
		run helm upgrade --install ngf oci://ghcr.io/nginx/charts/nginx-gateway-fabric \
			--namespace nginx-gateway \
			--create-namespace \
			--set nginx.service.type=LoadBalancer \
			--wait ||
			die "Failed to install NGINX Gateway Fabric"
	fi

	if helm_release_deployed cert-manager cert-manager; then
		log "cert-manager is already installed in the [cert-manager] namespace"
	else
		cert_manager_args=(
			upgrade --install cert-manager oci://quay.io/jetstack/charts/cert-manager
			--namespace cert-manager
			--create-namespace
			--set crds.enabled=true
			--set config.enableGatewayAPI=true
		)
		# ListenerSet support needs the ListenerSet CRD, which the managed standard bundle may not ship
		if exists kubectl get crd listenersets.gateway.networking.k8s.io; then
			cert_manager_args+=(--set config.enableGatewayAPIListenerSet=true --set config.featureGates.ListenerSets=true)
		fi
		cert_manager_args+=(--wait)
		log "Installing cert-manager..."
		run helm "${cert_manager_args[@]}" || die "Failed to install cert-manager"
	fi

	log "Waiting for the [nginx] GatewayClass to be accepted..."
	run kubectl wait --for=condition=Accepted gatewayclass/nginx --timeout=300s ||
		die "The [nginx] GatewayClass was not accepted: check the NGINX Gateway Fabric pods in the [nginx-gateway] namespace"
}

# Print the storage drivers enabled on the cluster, then the storage classes they provide. The azurefile* classes
# come from the Azure Files CSI driver, which samples/web-app-file-storage provisions its volumes from.
print_storage() {
	log "Storage profile of the [$aks_cluster_name] AKS cluster:"
	run az aks show \
		--name "$aks_cluster_name" \
		--resource-group "$resource_group_name" \
		--query storageProfile \
		--output yaml \
		--only-show-errors
	log "Storage classes of the [$aks_cluster_name] AKS cluster:"
	if ! run kubectl get storageclass; then
		if [[ $ENABLE_ENTRA_RBAC == true ]]; then
			die "kubectl cannot reach the [$aks_cluster_name] cluster. On Azure, a cluster with Entra ID needs kubelogin" \
				"(install it with: az aks install-cli) and your account in one of the admin groups" \
				"[$AAD_ADMIN_GROUP_OBJECT_IDS] or in an Azure Kubernetes Service RBAC role on the cluster."
		fi
		die "kubectl cannot reach the [$aks_cluster_name] cluster: see the kubectl error above."
	fi
}

main() {
	# fd 3 is where dry-run commands are printed: the real stdout, even inside $(...)
	exec 3>&1
	trap cleanup_jobs EXIT
	parse_args "$@"
	ask_questions
	derive_settings
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
	if [[ $CREATE_BASTION == true ]]; then
		add_bastion_extension
	fi

	# Resources that do not depend on each other
	start_job acr ensure_acr
	if [[ $CLUSTER_IDENTITY == user ]]; then
		start_job identity ensure_cluster_identity
	fi
	if [[ $ENABLE_MONITORING == true ]]; then
		start_job log-analytics ensure_log_analytics
	fi
	if [[ $CREATE_KEY_VAULT == true ]]; then
		start_job key-vault ensure_key_vault
	fi
	if [[ $CREATE_VNET == true ]]; then
		start_job vnet ensure_virtual_network
	fi
	wait_job vnet
	if [[ $CREATE_BASTION == true ]]; then
		start_job bastion ensure_bastion
	fi
	wait_job acr
	wait_job identity
	wait_job log-analytics
	read_resource_ids

	ensure_cluster
	if [[ $ENABLE_FILE_CSI_DRIVER == true ]]; then
		ensure_storage_drivers
	fi
	ensure_role_assignments
	if [[ $CREATE_USER_NODE_POOL == true ]]; then
		ensure_user_node_pool
	fi
	get_credentials
	if [[ $INSTALL_GATEWAY_CONTROLLERS == true ]]; then
		install_gateway_controllers
	fi
	wait_job bastion
	print_storage

	if [[ $DRY_RUN != true ]]; then
		echo "Provisioned:"
		print_resources
	fi
}

main "$@"
