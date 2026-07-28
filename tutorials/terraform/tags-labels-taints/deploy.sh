#!/usr/bin/env bash
#
# Deploys the modular AKS Terraform stack in this directory and validates the result
# end-to-end. Works against both real Azure and the LocalStack Azure emulator:
# real-Azure-only steps (aks-preview extension, preview-feature registration, Entra
# signed-in-user lookup, kubelogin, Key Vault purge preflight) are skipped
# automatically when the CLI cloud points at a local endpoint, and the Terraform
# providers are pointed at the emulator via -var overrides (azurerm metadata_host,
# azapi resource_manager_endpoint).

set -euo pipefail

# --- Variables ----------------------------------------------------------------

PREFIX='local'
SUFFIX='test'
RESOURCE_GROUP_NAME="${PREFIX}-rg"
LOCATION='westeurope'
INSTALL_EXTENSIONS_AND_FEATURES=1
PURGE_SOFT_DELETED_KEY_VAULT=1
GATEWAY_API_ENABLED=1
# Mirrors the keyVaultName values: terraform.tfvars pins the real-Azure name;
# the emulator has no global vault-name uniqueness so it keeps the short one.
REAL_KEY_VAULT_NAME='local-kv-ciao-local'
EMULATOR_KEY_VAULT_NAME='local-kv-test'
EMULATOR_METADATA_HOST='localhost.localstack.cloud:4566'
EMULATOR_GUID='00000000-0000-0000-0000-000000000000'
AKS_FEATURES=("ManagedGatewayAPIPreview")
SSH_KEY_FILE="$HOME/.ssh/id_rsa.pub"
CURRENT_DIR="$(cd "$(dirname "$0")" && pwd)"
FAILED_CHECKS=0

cd "$CURRENT_DIR"

# --- Environment detection ----------------------------------------------------

RESOURCE_MANAGER_ENDPOINT=$(az cloud show --query endpoints.resourceManager --output tsv --only-show-errors)
IS_EMULATOR=0
if [[ "$RESOURCE_MANAGER_ENDPOINT" == *localhost* || "$RESOURCE_MANAGER_ENDPOINT" == *localstack* ]]; then
  IS_EMULATOR=1
  echo "Detected LocalStack Azure emulator at [$RESOURCE_MANAGER_ENDPOINT]"
else
  echo "Detected real Azure ([$RESOURCE_MANAGER_ENDPOINT])"
fi

# --- Validation helpers ---------------------------------------------------------

check_equals() {
  local description=$1
  local actual=$2
  local expected=$3
  if [[ "$actual" == "$expected" ]]; then
    echo "PASS: $description [$actual]"
  else
    echo "FAIL: $description - expected [$expected], got [$actual]"
    FAILED_CHECKS=$((FAILED_CHECKS + 1))
  fi
}

check_not_empty() {
  local description=$1
  local actual=$2
  if [[ -n "$actual" ]]; then
    echo "PASS: $description [$actual]"
  else
    echo "FAIL: $description - value is empty"
    FAILED_CHECKS=$((FAILED_CHECKS + 1))
  fi
}

# --- CNI configuration menu -----------------------------------------------------

echo "===================================="
echo "Select the CNI configuration (1-4):"
echo "===================================="
options=(
  "Azure Network Plugin + Azure Network Policy"
  "Azure Network Plugin + Cilium Network Policy"
  "Azure Network Plugin + Calico Network Policy"
  "Quit"
)
# COLUMNS=0 forces select to render the menu as a single column.
COLUMNS=0
export COLUMNS
select option in "${options[@]}"; do
  case $option in
  "Azure Network Plugin + Azure Network Policy")
    network_plugin='azure'
    network_policy='azure'
    network_plugin_mode='overlay'
    network_dataplane='azure'
    break
    ;;
  "Azure Network Plugin + Cilium Network Policy")
    network_plugin='azure'
    network_policy='cilium'
    network_plugin_mode='overlay'
    network_dataplane='cilium'
    break
    ;;
  "Azure Network Plugin + Calico Network Policy")
    network_plugin='azure'
    network_policy='calico'
    network_plugin_mode='overlay'
    network_dataplane='azure'
    break
    ;;
  "Quit")
    exit 0
    ;;
  *) echo "invalid option $REPLY" ;;
  esac
done
echo "Selected CNI configuration: plugin=[$network_plugin] policy=[$network_policy] mode=[$network_plugin_mode] dataplane=[$network_dataplane]"

# --- aks-preview extension + preview features (real Azure only) ------------------

if [[ "$INSTALL_EXTENSIONS_AND_FEATURES" == 1 && "$IS_EMULATOR" == 0 ]]; then
  echo "Adding or upgrading the [aks-preview] extension..."
  az extension add --upgrade --name aks-preview --only-show-errors 1>/dev/null

  for aks_feature in "${AKS_FEATURES[@]}"; do
    registration_state=$(az feature show \
      --name "$aks_feature" \
      --namespace Microsoft.ContainerService \
      --query properties.state \
      --output tsv \
      --only-show-errors 2>/dev/null || true)
    if [[ "$registration_state" == "Registered" ]]; then
      echo "[$aks_feature] feature is already registered"
      continue
    fi
    echo "Registering the [$aks_feature] feature..."
    az feature register \
      --name "$aks_feature" \
      --namespace Microsoft.ContainerService \
      --only-show-errors 1>/dev/null
    echo -n "Waiting for the [$aks_feature] feature registration..."
    while true; do
      registration_state=$(az feature show \
        --name "$aks_feature" \
        --namespace Microsoft.ContainerService \
        --query properties.state \
        --output tsv \
        --only-show-errors 2>/dev/null || true)
      if [[ "$registration_state" == "Registered" ]]; then
        echo "."
        break
      fi
      echo -n "."
      sleep 5
    done
    echo "Refreshing the registration of the Microsoft.ContainerService resource provider..."
    az provider register --namespace Microsoft.ContainerService --only-show-errors 1>/dev/null
  done
else
  # Deliberate skip: az feature registration and the aks-preview extension have no
  # meaning against the emulator; the emulator serves preview API versions directly.
  echo "Skipping aks-preview extension and feature registration"
fi

# --- Latest Kubernetes version ------------------------------------------------------

KUBERNETES_VERSION=$(az aks get-versions \
  --location "$LOCATION" \
  --query "values[?isPreview==null].version | sort(@) | [-1]" \
  --output tsv \
  --only-show-errors 2>/dev/null || true)
if [[ -n "$KUBERNETES_VERSION" ]]; then
  echo "Latest GA Kubernetes version in [$LOCATION]: [$KUBERNETES_VERSION]"
else
  # Deliberate fallback: without a version Terraform omits kubernetes_version and
  # the platform default applies.
  echo "Could not determine the latest Kubernetes version; using the platform default"
fi

# --- Optional inputs -----------------------------------------------------------------

# The SSH key is only passed on real Azure: the emulator ignores linuxProfile and
# does not echo it back on GET, and since linux_profile addition is ForceNew in
# azurerm, passing it locally puts every plan into a cluster-replacement loop
# (emulator parity gap, reported).
SSH_PUBLIC_KEY=''
if [[ "$IS_EMULATOR" == 0 ]]; then
  if [[ -f "$SSH_KEY_FILE" ]]; then
    SSH_PUBLIC_KEY=$(cat "$SSH_KEY_FILE")
    echo "Using the SSH public key from [$SSH_KEY_FILE]"
  else
    echo "No SSH public key found at [$SSH_KEY_FILE]; the cluster is created without a linux_profile"
  fi
fi

USER_ID=''
if [[ "$IS_EMULATOR" == 0 ]]; then
  USER_ID=$(az ad signed-in-user show --query id --output tsv --only-show-errors 2>/dev/null || true)
  if [[ -n "$USER_ID" ]]; then
    echo "Signed-in user object id: [$USER_ID]"
  else
    echo "Could not resolve the signed-in user object id; skipping user role assignments"
  fi
fi

# --- Key Vault name preflight (real Azure only) -----------------------------------------

# Key Vault names are globally unique and soft delete keeps a deleted vault's name
# reserved. Because this script destroys the resources between runs, a re-run would
# fail with VaultAlreadyExists unless the soft-deleted vault is purged first. Only
# the vault name this deployment owns is purged, and a check-name call fails fast
# when the name is held outside this deployment (the emulator models neither soft
# delete nor global uniqueness, so both steps are skipped there).
if [[ "$IS_EMULATOR" == 0 ]]; then
  if [[ "$PURGE_SOFT_DELETED_KEY_VAULT" == 1 ]]; then
    deleted_vault_location=$(az keyvault list-deleted \
      --query "[?name=='$REAL_KEY_VAULT_NAME'] | [0].properties.location" \
      --output tsv \
      --only-show-errors 2>/dev/null || true)
    if [[ -n "$deleted_vault_location" ]]; then
      echo "Purging the soft-deleted [$REAL_KEY_VAULT_NAME] key vault in [$deleted_vault_location]..."
      az keyvault purge --name "$REAL_KEY_VAULT_NAME" --location "$deleted_vault_location" --only-show-errors
    fi
  fi
  name_available=$(az keyvault check-name \
    --name "$REAL_KEY_VAULT_NAME" \
    --query nameAvailable \
    --output tsv \
    --only-show-errors 2>/dev/null || true)
  if [[ "$name_available" == "false" ]]; then
    if az keyvault show --name "$REAL_KEY_VAULT_NAME" --resource-group "$RESOURCE_GROUP_NAME" --only-show-errors &>/dev/null; then
      echo "Key vault [$REAL_KEY_VAULT_NAME] already exists in [$RESOURCE_GROUP_NAME]; Terraform will update it"
    else
      echo "ERROR: key vault name [$REAL_KEY_VAULT_NAME] is taken outside this deployment; set a different key_vault_name in terraform.tfvars"
      exit 1
    fi
  fi
fi

# --- Terraform variables ------------------------------------------------------------------

tf_vars=(
  -var "location=$LOCATION"
  -var "prefix=$PREFIX"
  -var "suffix=$SUFFIX"
  -var "network_plugin=$network_plugin"
  -var "network_plugin_mode=$network_plugin_mode"
  -var "network_policy=$network_policy"
  -var "network_data_plane=$network_dataplane"
)
if [[ "$IS_EMULATOR" == 1 ]]; then
  # gateway_api_enabled=false disables the azapi resource on the emulator: the
  # emulator does not persist ingressProfile.gatewayAPI from azapi's full-resource
  # PUT and the azapi update then hangs on its LRO (parity gap). The gateway API is
  # enabled through the az CLI after apply instead — the same path the emulator's
  # own test_aks_gateway_api.bats exercises.
  tf_vars+=(
    -var "metadata_host=$EMULATOR_METADATA_HOST"
    -var "resource_manager_endpoint=$RESOURCE_MANAGER_ENDPOINT"
    -var "subscription_id=$EMULATOR_GUID"
    -var "tenant_id=$EMULATOR_GUID"
    -var "client_id=$EMULATOR_GUID"
    -var "client_secret=fake-secret"
    -var "key_vault_name=$EMULATOR_KEY_VAULT_NAME"
    -var "gateway_api_enabled=false"
  )
else
  SUBSCRIPTION_ID=$(az account show --query id --output tsv --only-show-errors)
  tf_vars+=(-var "subscription_id=$SUBSCRIPTION_ID")
fi
if [[ -n "$KUBERNETES_VERSION" ]]; then
  tf_vars+=(-var "kubernetes_version=$KUBERNETES_VERSION")
fi
if [[ -n "$SSH_PUBLIC_KEY" ]]; then
  tf_vars+=(-var "ssh_public_key=$SSH_PUBLIC_KEY")
fi
if [[ -n "$USER_ID" ]]; then
  tf_vars+=(-var "user_object_id=$USER_ID")
fi

# --- Terraform init / validate / plan / apply ----------------------------------------------

# Subscription automation (Azure Policy) creates diagnostic settings named
# 'diagnosticSettings' on the cluster / ACR / Key Vault shortly after they exist.
# Bicep upserts over them transparently; Terraform refuses to overwrite unmanaged
# resources, so existing ones are adopted into state instead (real Azure only).
import_existing_diagnostic_settings() {
  local address resource_id
  while IFS='|' read -r address resource_id; do
    if [[ -z "$resource_id" ]]; then
      continue
    fi
    if terraform state show "$address" &>/dev/null; then
      continue
    fi
    if az monitor diagnostic-settings show --resource "$resource_id" --name diagnosticSettings --only-show-errors &>/dev/null; then
      echo "Adopting the existing diagnosticSettings on [$resource_id] into the Terraform state..."
      terraform import -input=false "${tf_vars[@]}" "$address" "${resource_id}|diagnosticSettings" 1>/dev/null
    fi
  done <<EOF
module.aks_cluster.azurerm_monitor_diagnostic_setting.diagnostic_setting|$(az aks show --name "${PREFIX}-aks-${SUFFIX}" --resource-group "$RESOURCE_GROUP_NAME" --query id --output tsv --only-show-errors 2>/dev/null || true)
module.container_registry.azurerm_monitor_diagnostic_setting.diagnostic_setting|$(az acr show --name "${PREFIX}acr${SUFFIX}" --resource-group "$RESOURCE_GROUP_NAME" --query id --output tsv --only-show-errors 2>/dev/null || true)
module.key_vault.azurerm_monitor_diagnostic_setting.diagnostic_setting|$(az keyvault show --name "$REAL_KEY_VAULT_NAME" --resource-group "$RESOURCE_GROUP_NAME" --query id --output tsv --only-show-errors 2>/dev/null || true)
EOF
}

echo "Initializing Terraform..."
terraform init -upgrade -input=false 1>/dev/null
echo "Validating the Terraform configuration..."
terraform validate 1>/dev/null
echo "Terraform configuration is valid"

if [[ "$IS_EMULATOR" == 0 ]]; then
  # Sync state with reality before importing: an interrupted earlier apply can
  # leave stale nested attributes in state (e.g. an empty secrets-provider
  # identity) that block output evaluation during terraform import.
  if terraform state list 2>/dev/null | grep -q .; then
    echo "Refreshing the Terraform state..."
    terraform apply -refresh-only -input=false -auto-approve "${tf_vars[@]}" 1>/dev/null
  fi
  import_existing_diagnostic_settings
fi

echo "Planning the Terraform deployment (full plan in tfplan.log)..."
terraform plan -input=false -no-color -out=tfplan "${tf_vars[@]}" >tfplan.log 2>&1
grep -E "^Plan:|No changes|must be replaced" tfplan.log || true
echo "Applying the Terraform deployment (10-15 minutes on real Azure)..."
apply_exit=0
terraform apply -input=false -auto-approve tfplan || apply_exit=$?
if [[ "$apply_exit" != 0 && "$IS_EMULATOR" == 0 ]]; then
  # A fresh deployment can lose the diagnostic-settings creation race against the
  # subscription automation: adopt whatever it created and retry once.
  echo "Apply failed; adopting automation-created diagnostic settings and retrying once..."
  import_existing_diagnostic_settings
  terraform plan -input=false -no-color -out=tfplan "${tf_vars[@]}" >tfplan.log 2>&1
  grep -E "^Plan:|No changes|must be replaced" tfplan.log || true
  terraform apply -input=false -auto-approve tfplan
elif [[ "$apply_exit" != 0 ]]; then
  exit "$apply_exit"
fi

# Idempotency + azapi/azurerm co-management guard: a plan right after apply must be
# empty (exit 0). Exit 2 means drift. Known limitation: on the emulator this check
# FAILS today because several properties are not echoed back on GET
# (autoUpgradeProfile, autoScalerProfile, diagnostic metric categories, LA retention,
# subnet defaults, ACR role_assignment_mode) — emulator parity gaps, reported; real
# Azure is expected to pass.
echo "Verifying the post-apply plan is empty (full plan in tfplan-postapply.log)..."
post_apply_plan_exit=0
terraform plan -input=false -no-color -detailed-exitcode "${tf_vars[@]}" >tfplan-postapply.log 2>&1 || post_apply_plan_exit=$?
check_equals "post-apply terraform plan is a no-op" "$post_apply_plan_exit" "0"
if [[ "$post_apply_plan_exit" != 0 ]]; then
  echo "Post-apply drift inventory:"
  grep -E "will be|must be|^Plan:" tfplan-postapply.log || true
fi

DEPLOYMENT_OUTPUTS=$(terraform output -json)
echo "Terraform outputs:"
jq . <<<"$DEPLOYMENT_OUTPUTS"

CLUSTER_NAME=$(jq -r '.cluster_name.value' <<<"$DEPLOYMENT_OUTPUTS")
USER_NODE_POOL_NAME=$(jq -r '.user_node_pool_name.value' <<<"$DEPLOYMENT_OUTPUTS")
ACR_NAME=$(jq -r '.acr_name.value' <<<"$DEPLOYMENT_OUTPUTS")
KEY_VAULT_NAME=$(jq -r '.key_vault_name.value' <<<"$DEPLOYMENT_OUTPUTS")
NODE_RESOURCE_GROUP=$(jq -r '.node_resource_group.value' <<<"$DEPLOYMENT_OUTPUTS")
OIDC_ISSUER_URL=$(jq -r '.oidc_issuer_url.value' <<<"$DEPLOYMENT_OUTPUTS")
KV_SECRETS_PROVIDER_OBJECT_ID=$(jq -r '.key_vault_secrets_provider_object_id.value' <<<"$DEPLOYMENT_OUTPUTS")

check_not_empty "terraform output cluster_name" "$CLUSTER_NAME"
check_not_empty "terraform output user_node_pool_name" "$USER_NODE_POOL_NAME"
check_not_empty "terraform output acr_name" "$ACR_NAME"
check_not_empty "terraform output key_vault_name" "$KEY_VAULT_NAME"
check_not_empty "terraform output node_resource_group" "$NODE_RESOURCE_GROUP"

# --- Managed Gateway API on the emulator (az CLI path) --------------------------------------

# See the emulator note in the Terraform variables section above. Idempotent: the
# update is a no-op when the installation is already Standard.
if [[ "$IS_EMULATOR" == 1 && "$GATEWAY_API_ENABLED" == 1 ]]; then
  echo "Enabling the Managed Gateway API via the az CLI (emulator parity gap: azapi full PUT is not persisted)..."
  az aks update \
    --name "$CLUSTER_NAME" \
    --resource-group "$RESOURCE_GROUP_NAME" \
    --enable-gateway-api \
    --only-show-errors 1>/dev/null
fi

# --- ARM-side validation ----------------------------------------------------------------

# The emulator's create returns before the cluster start LRO completes (real Azure
# awaits it, so this loop exits immediately there).
echo "Waiting for the [$CLUSTER_NAME] cluster to reach powerState Running..."
cluster_running=0
for _ in $(seq 1 60); do
  power_state=$(az aks show \
    --name "$CLUSTER_NAME" \
    --resource-group "$RESOURCE_GROUP_NAME" \
    --query 'powerState.code' \
    --output tsv \
    --only-show-errors 2>/dev/null || true)
  if [[ "$power_state" == "Running" ]]; then
    cluster_running=1
    break
  fi
  sleep 5
done
if [[ "$cluster_running" != 1 ]]; then
  echo "FAIL: cluster [$CLUSTER_NAME] never reached powerState Running"
  exit 1
fi
echo "PASS: cluster [$CLUSTER_NAME] is Running"

echo "Verifying cluster tags and profiles..."
check_equals "cluster tag env" \
  "$(az aks show --name "$CLUSTER_NAME" --resource-group "$RESOURCE_GROUP_NAME" --query 'tags.env' --output tsv --only-show-errors)" \
  "test"
check_equals "system pool node label team" \
  "$(
    # shellcheck disable=SC2016 # JMESPath uses backticks for literals; no shell expansion wanted
    az aks show --name "$CLUSTER_NAME" --resource-group "$RESOURCE_GROUP_NAME" --query 'agentPoolProfiles[?name==`system`] | [0].nodeLabels.team' --output tsv --only-show-errors
  )" \
  "platform"
check_equals "gateway API installation" \
  "$(az aks show --name "$CLUSTER_NAME" --resource-group "$RESOURCE_GROUP_NAME" --query 'ingressProfile.gatewayAPI.installation || ingressProfile.gatewayApi.installation' --output tsv --only-show-errors)" \
  "Standard"
check_equals "workload identity enabled" \
  "$(az aks show --name "$CLUSTER_NAME" --resource-group "$RESOURCE_GROUP_NAME" --query 'securityProfile.workloadIdentity.enabled' --output tsv --only-show-errors)" \
  "true"
check_equals "key vault secrets provider addon enabled" \
  "$(az aks show --name "$CLUSTER_NAME" --resource-group "$RESOURCE_GROUP_NAME" --query 'addonProfiles.azureKeyvaultSecretsProvider.enabled' --output tsv --only-show-errors)" \
  "true"
check_equals "vertical pod autoscaler enabled" \
  "$(az aks show --name "$CLUSTER_NAME" --resource-group "$RESOURCE_GROUP_NAME" --query 'workloadAutoScalerProfile.verticalPodAutoscaler.enabled' --output tsv --only-show-errors)" \
  "true"
check_not_empty "OIDC issuer URL" "$OIDC_ISSUER_URL"

echo "Verifying the [$USER_NODE_POOL_NAME] user agent pool..."
check_equals "user pool node label workload" \
  "$(az aks nodepool show --cluster-name "$CLUSTER_NAME" --resource-group "$RESOURCE_GROUP_NAME" --name "$USER_NODE_POOL_NAME" --query 'nodeLabels.workload' --output tsv --only-show-errors)" \
  "batch"
check_equals "user pool node taint" \
  "$(az aks nodepool show --cluster-name "$CLUSTER_NAME" --resource-group "$RESOURCE_GROUP_NAME" --name "$USER_NODE_POOL_NAME" --query 'nodeTaints[0]' --output tsv --only-show-errors)" \
  "dedicated=batch:NoSchedule"
check_equals "user pool tag costcenter" \
  "$(az aks nodepool show --cluster-name "$CLUSTER_NAME" --resource-group "$RESOURCE_GROUP_NAME" --name "$USER_NODE_POOL_NAME" --query 'tags.costcenter' --output tsv --only-show-errors)" \
  "1234"

echo "Verifying the AcrPull role assignment for the kubelet identity..."
KUBELET_OBJECT_ID=$(az aks show \
  --name "$CLUSTER_NAME" \
  --resource-group "$RESOURCE_GROUP_NAME" \
  --query 'identityProfile.kubeletidentity.objectId' \
  --output tsv \
  --only-show-errors)
check_not_empty "kubelet identity object id" "$KUBELET_OBJECT_ID"
ACR_ID=$(az acr show \
  --name "$ACR_NAME" \
  --resource-group "$RESOURCE_GROUP_NAME" \
  --query id \
  --output tsv \
  --only-show-errors)
check_equals "AcrPull role assignment on the container registry" \
  "$(az role assignment list --assignee "$KUBELET_OBJECT_ID" --scope "$ACR_ID" --query "[?roleDefinitionName=='AcrPull'] | length(@)" --output tsv --only-show-errors)" \
  "1"

echo "Verifying the Key Vault Administrator role assignment for the secrets provider identity..."
check_not_empty "key vault secrets provider object id" "$KV_SECRETS_PROVIDER_OBJECT_ID"
KEY_VAULT_ID=$(az keyvault show \
  --name "$KEY_VAULT_NAME" \
  --resource-group "$RESOURCE_GROUP_NAME" \
  --query id \
  --output tsv \
  --only-show-errors)
check_equals "Key Vault Administrator role assignment on the key vault" \
  "$(az role assignment list --assignee "$KV_SECRETS_PROVIDER_OBJECT_ID" --scope "$KEY_VAULT_ID" --query "[?roleDefinitionName=='Key Vault Administrator'] | length(@)" --output tsv --only-show-errors)" \
  "1"

# --- Kubernetes-side validation -----------------------------------------------------------

echo "Getting the access credentials for the [$CLUSTER_NAME] cluster..."
az aks get-credentials \
  --name "$CLUSTER_NAME" \
  --resource-group "$RESOURCE_GROUP_NAME" \
  --overwrite-existing \
  --only-show-errors

SKIP_KUBECTL=0
AAD_MANAGED=$(az aks show \
  --name "$CLUSTER_NAME" \
  --resource-group "$RESOURCE_GROUP_NAME" \
  --query 'aadProfile.managed' \
  --output tsv \
  --only-show-errors 2>/dev/null || true)
if [[ "$AAD_MANAGED" == "true" && "$IS_EMULATOR" == 0 ]]; then
  if command -v kubelogin &>/dev/null; then
    echo "Converting the kubeconfig for Azure RBAC access with kubelogin..."
    kubelogin convert-kubeconfig -l azurecli
  else
    echo "WARNING: kubelogin is not on PATH and the cluster uses managed AAD; skipping the kubectl validation section"
    SKIP_KUBECTL=1
  fi
fi

if [[ "$SKIP_KUBECTL" == 0 ]]; then
  echo "Verifying the user pool node labels through the Kubernetes API..."
  node_label_found=0
  for _ in $(seq 1 24); do
    node_label=$(kubectl --context "$CLUSTER_NAME" get nodes -l "agentpool=$USER_NODE_POOL_NAME" \
      -o jsonpath='{.items[0].metadata.labels.workload}' 2>/dev/null || true)
    if [[ "$node_label" == "batch" ]]; then
      node_label_found=1
      break
    fi
    sleep 5
  done
  check_equals "user pool node carries the workload=batch label" "$node_label_found" "1"

  # Retry like the label check: taints can land on the node moments after the
  # labels during node join (observed on the emulator).
  node_taint_effect=''
  for _ in $(seq 1 24); do
    node_taint_effect=$(kubectl --context "$CLUSTER_NAME" get nodes -l "agentpool=$USER_NODE_POOL_NAME" \
      -o jsonpath='{.items[0].spec.taints[?(@.key=="dedicated")].effect}' 2>/dev/null || true)
    if [[ "$node_taint_effect" == "NoSchedule" ]]; then
      break
    fi
    sleep 5
  done
  check_equals "user pool node carries the dedicated taint" "$node_taint_effect" "NoSchedule"

  echo "Verifying the Secrets Store CSI Driver daemonsets..."
  csi_daemonsets_found=0
  for _ in $(seq 1 24); do
    if kubectl --context "$CLUSTER_NAME" get daemonset aks-secrets-store-csi-driver -n kube-system &>/dev/null &&
      kubectl --context "$CLUSTER_NAME" get daemonset aks-secrets-store-provider-azure -n kube-system &>/dev/null; then
      csi_daemonsets_found=1
      break
    fi
    sleep 5
  done
  check_equals "secrets store CSI driver daemonsets exist in kube-system" "$csi_daemonsets_found" "1"

  echo "Verifying the Managed Gateway API CRDs (their installation can lag cluster readiness)..."
  gateway_crd_found=0
  for _ in $(seq 1 24); do
    if kubectl --context "$CLUSTER_NAME" get crd gateways.gateway.networking.k8s.io &>/dev/null; then
      gateway_crd_found=1
      break
    fi
    sleep 5
  done
  check_equals "gateway API CRD gateways.gateway.networking.k8s.io exists" "$gateway_crd_found" "1"

  echo "Verifying the workload identity webhook..."
  workload_identity_found=0
  if kubectl --context "$CLUSTER_NAME" get mutatingwebhookconfiguration azure-wi-webhook-mutating-webhook-configuration &>/dev/null; then
    workload_identity_found=1
  else
    webhook_pods=$(kubectl --context "$CLUSTER_NAME" get pods -n kube-system \
      -l azure-workload-identity.io/system=true -o name 2>/dev/null || true)
    if [[ -n "$webhook_pods" ]]; then
      workload_identity_found=1
    fi
  fi
  check_equals "workload identity webhook is installed" "$workload_identity_found" "1"
fi

# --- Summary -------------------------------------------------------------------------------

echo "Listing the resources in the [$RESOURCE_GROUP_NAME] resource group..."
az resource list --resource-group "$RESOURCE_GROUP_NAME" --output table --only-show-errors

if [[ "$FAILED_CHECKS" -gt 0 ]]; then
  echo "Validation completed with [$FAILED_CHECKS] failed check(s)"
  exit 1
fi
echo "All validation checks passed"
