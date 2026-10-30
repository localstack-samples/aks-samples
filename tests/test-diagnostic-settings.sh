#!/bin/bash
# Check that every resource the cluster scripts, bicep/ and terraform/ create has a diagnostic setting called
# "default". A resource the deployment left out (scripts/01-configurable-cluster.sh can skip the virtual network,
# the Bastion host and the key vault) is reported as skipped. The resources are looked up by the names the scripts
# give them, not by type, because the samples add resources of their own to the same resource group.
#
# Usage: tests/test-diagnostic-settings.sh
# Override PREFIX, SUFFIX or RESOURCE_GROUP_NAME when the cluster was deployed with other names.
set -euo pipefail

PREFIX=${PREFIX:-local}
SUFFIX=${SUFFIX:-test}
RESOURCE_GROUP_NAME=${RESOURCE_GROUP_NAME:-$PREFIX-rg}
DIAGNOSTIC_SETTINGS_NAME=${DIAGNOSTIC_SETTINGS_NAME:-default}

aks_cluster_name="$PREFIX-aks-$SUFFIX"

# Name and resource type of every resource that gets the diagnostic settings
expected=(
  "$aks_cluster_name|Microsoft.ContainerService/managedClusters"
  "$PREFIX-vnet-$SUFFIX|Microsoft.Network/virtualNetworks"
  "$PREFIX-bastion-ip-$SUFFIX|Microsoft.Network/publicIPAddresses"
  "$PREFIX-bastion-$SUFFIX|Microsoft.Network/bastionHosts"
  "${PREFIX,,}acr${SUFFIX,,}|Microsoft.ContainerRegistry/registries"
  "$PREFIX-kv-$SUFFIX|Microsoft.KeyVault/vaults"
)

# Name, type and ID of every resource in the resource group, in one call. The carriage returns that the
# Windows Azure CLI writes are removed, so the lines compare equal on every platform.
if ! resources=$(az resource list \
  --resource-group "$RESOURCE_GROUP_NAME" \
  --query "[].[name, type, id]" \
  --output tsv \
  --only-show-errors | tr -d '\r'); then
  echo "FAIL: cannot list the resources of the [$RESOURCE_GROUP_NAME] resource group"
  exit 1
fi

# Print the ID of the resource with the given name and type, or nothing when the group has none
resource_id() {
  awk -F '\t' -v name="${1,,}" -v type="${2,,}" \
    'tolower($1) == name && tolower($2) == type { print $3; exit }' <<<"$resources"
}

if [[ -z $(resource_id "$aks_cluster_name" Microsoft.ContainerService/managedClusters) ]]; then
  echo "FAIL: no [$aks_cluster_name] AKS cluster in the [$RESOURCE_GROUP_NAME] resource group"
  exit 1
fi

checked=0
failures=0
for entry in "${expected[@]}"; do
  IFS='|' read -r name type <<<"$entry"
  id=$(resource_id "$name" "$type")
  if [[ -z $id ]]; then
    echo "SKIP: no [$name] $type in the [$RESOURCE_GROUP_NAME] resource group"
    continue
  fi
  checked=$((checked + 1))
  if az monitor diagnostic-settings show \
    --name "$DIAGNOSTIC_SETTINGS_NAME" \
    --resource "$id" \
    --only-show-errors &>/dev/null; then
    echo "PASS: [$name] has the [$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings"
  else
    echo "FAIL: [$name] has no [$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings"
    failures=$((failures + 1))
  fi
done

echo "Checked the [$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings of $checked resources in the [$RESOURCE_GROUP_NAME] resource group: $failures missing"
[[ $failures -eq 0 ]]
