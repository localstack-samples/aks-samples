# Orchestrates the modular AKS stack: Log Analytics, VNet, AKS user-assigned
# identity, ACR, Key Vault, AKS cluster (system pool), user agent pool, and the
# AcrPull / Key Vault Administrator role assignments. Terraform port of
# ~/azure/aks/bicep/tags_labels_taints/main.bicep.

data "azurerm_client_config" "current" {}

locals {
  prefix = lower(var.prefix)
  suffix = lower(var.suffix)

  resource_group_name          = "${var.prefix}-rg"
  aks_cluster_name             = var.aks_cluster_name == "" ? "${local.prefix}-aks-${local.suffix}" : var.aks_cluster_name
  aks_managed_identity_name    = var.aks_managed_identity_name == "" ? "${local.prefix}-aks-identity-${local.suffix}" : var.aks_managed_identity_name
  virtual_network_name         = var.virtual_network_name == "" ? "${local.prefix}-vnet-${local.suffix}" : var.virtual_network_name
  log_analytics_workspace_name = var.log_analytics_workspace_name == "" ? "${local.prefix}-log-analytics-${local.suffix}" : var.log_analytics_workspace_name
  container_registry_name      = var.container_registry_name == "" ? "${local.prefix}acr${local.suffix}" : var.container_registry_name
  key_vault_name               = var.key_vault_name == "" ? "${local.prefix}-kv-${local.suffix}" : var.key_vault_name

  aad_tenant_id = var.aad_tenant_id == null ? data.azurerm_client_config.current.tenant_id : var.aad_tenant_id
}

resource "azurerm_resource_group" "resource_group" {
  name     = local.resource_group_name
  location = var.location
  tags     = var.tags

  lifecycle {
    ignore_changes = [tags]
  }
}

module "log_analytics" {
  source = "./modules/log_analytics"

  name                = local.log_analytics_workspace_name
  resource_group_name = azurerm_resource_group.resource_group.name
  location            = var.location
  sku                 = var.log_analytics_workspace_sku
  retention_in_days   = var.log_analytics_workspace_retention_in_days
  tags                = var.tags
}

module "virtual_network" {
  source = "./modules/virtual_network"

  name                         = local.virtual_network_name
  resource_group_name          = azurerm_resource_group.resource_group.name
  location                     = var.location
  address_space                = var.virtual_network_address_space
  system_subnet_name           = var.system_subnet_name
  system_subnet_address_prefix = var.system_subnet_address_prefix
  user_subnet_name             = var.user_subnet_name
  user_subnet_address_prefix   = var.user_subnet_address_prefix
  tags                         = var.tags
}

module "aks_managed_identity" {
  source = "./modules/aks_managed_identity"

  name                = local.aks_managed_identity_name
  resource_group_name = azurerm_resource_group.resource_group.name
  location            = var.location
  virtual_network_id  = module.virtual_network.virtual_network_id
  tags                = var.tags
}

module "container_registry" {
  source = "./modules/container_registry"

  name                       = local.container_registry_name
  resource_group_name        = azurerm_resource_group.resource_group.name
  location                   = var.location
  sku                        = var.container_registry_sku
  admin_enabled              = var.container_registry_admin_enabled
  log_analytics_workspace_id = module.log_analytics.id
  tags                       = var.tags
}

module "key_vault" {
  source = "./modules/key_vault"

  name                          = local.key_vault_name
  resource_group_name           = azurerm_resource_group.resource_group.name
  location                      = var.location
  tenant_id                     = data.azurerm_client_config.current.tenant_id
  sku_name                      = var.key_vault_sku_name
  rbac_authorization_enabled    = var.key_vault_rbac_authorization_enabled
  purge_protection_enabled      = var.key_vault_purge_protection_enabled
  soft_delete_retention_days    = var.key_vault_soft_delete_retention_days
  public_network_access_enabled = var.key_vault_public_network_access_enabled
  network_acls_default_action   = var.key_vault_network_acls_default_action
  user_object_id                = var.user_object_id
  log_analytics_workspace_id    = module.log_analytics.id
  tags                          = var.tags
}

module "aks_cluster" {
  source = "./modules/aks_cluster"

  name                = local.aks_cluster_name
  resource_group_name = azurerm_resource_group.resource_group.name
  location            = var.location
  dns_prefix          = var.dns_prefix
  kubernetes_version  = var.kubernetes_version
  sku_tier            = var.sku_tier
  managed_identity_id = module.aks_managed_identity.id
  system_subnet_id    = module.virtual_network.system_subnet_id

  system_node_pool_name                 = var.system_node_pool_name
  system_node_pool_vm_size              = var.vm_size
  system_node_pool_node_count           = var.system_node_pool_node_count
  system_node_pool_auto_scaling_enabled = var.system_node_pool_auto_scaling_enabled
  system_node_pool_min_count            = var.system_node_pool_min_count
  system_node_pool_max_count            = var.system_node_pool_max_count
  system_node_pool_max_pods             = var.system_node_pool_max_pods
  system_node_pool_os_disk_type         = var.system_node_pool_os_disk_type
  system_node_pool_os_sku               = var.system_node_pool_os_sku
  system_node_pool_availability_zones   = var.system_node_pool_availability_zones
  system_node_pool_node_labels          = var.system_node_pool_node_labels

  admin_username = var.admin_username
  ssh_public_key = var.ssh_public_key

  network_plugin      = var.network_plugin
  network_plugin_mode = var.network_plugin_mode
  network_policy      = var.network_policy
  network_data_plane  = var.network_data_plane
  pod_cidr            = var.pod_cidr
  service_cidr        = var.service_cidr
  dns_service_ip      = var.dns_service_ip
  outbound_type       = var.outbound_type
  load_balancer_sku   = var.load_balancer_sku

  oidc_issuer_enabled                     = var.oidc_issuer_enabled
  workload_identity_enabled               = var.workload_identity_enabled
  azure_keyvault_secrets_provider_enabled = var.azure_keyvault_secrets_provider_enabled
  secret_rotation_enabled                 = var.secret_rotation_enabled
  keda_enabled                            = var.keda_enabled
  vertical_pod_autoscaler_enabled         = var.vertical_pod_autoscaler_enabled
  blob_csi_driver_enabled                 = var.blob_csi_driver_enabled
  disk_csi_driver_enabled                 = var.disk_csi_driver_enabled
  file_csi_driver_enabled                 = var.file_csi_driver_enabled
  snapshot_controller_enabled             = var.snapshot_controller_enabled

  rbac_enabled               = var.rbac_enabled
  aad_enabled                = var.aad_enabled
  aad_azure_rbac_enabled     = var.aad_azure_rbac_enabled
  aad_admin_group_object_ids = var.aad_admin_group_object_ids
  aad_tenant_id              = local.aad_tenant_id
  user_object_id             = var.user_object_id

  automatic_upgrade_channel = var.automatic_upgrade_channel
  node_os_upgrade_channel   = var.node_os_upgrade_channel

  auto_scaler_profile_scan_interval                    = var.auto_scaler_profile_scan_interval
  auto_scaler_profile_scale_down_delay_after_add       = var.auto_scaler_profile_scale_down_delay_after_add
  auto_scaler_profile_scale_down_delay_after_delete    = var.auto_scaler_profile_scale_down_delay_after_delete
  auto_scaler_profile_scale_down_delay_after_failure   = var.auto_scaler_profile_scale_down_delay_after_failure
  auto_scaler_profile_scale_down_unneeded              = var.auto_scaler_profile_scale_down_unneeded
  auto_scaler_profile_scale_down_unready               = var.auto_scaler_profile_scale_down_unready
  auto_scaler_profile_scale_down_utilization_threshold = var.auto_scaler_profile_scale_down_utilization_threshold
  auto_scaler_profile_max_graceful_termination_sec     = var.auto_scaler_profile_max_graceful_termination_sec
  auto_scaler_profile_expander                         = var.auto_scaler_profile_expander

  log_analytics_workspace_id = module.log_analytics.id
  tags                       = var.tags
}

module "aks_node_pool" {
  source = "./modules/aks_node_pool"

  name                  = var.user_node_pool_name
  kubernetes_cluster_id = module.aks_cluster.id
  subnet_id             = module.virtual_network.user_subnet_id
  mode                  = var.user_node_pool_mode
  vm_size               = var.vm_size
  node_count            = var.user_node_pool_node_count
  auto_scaling_enabled  = var.user_node_pool_auto_scaling_enabled
  min_count             = var.user_node_pool_min_count
  max_count             = var.user_node_pool_max_count
  max_pods              = var.user_node_pool_max_pods
  os_type               = var.user_node_pool_os_type
  os_sku                = var.user_node_pool_os_sku
  os_disk_type          = var.user_node_pool_os_disk_type
  availability_zones    = var.user_node_pool_availability_zones
  node_labels           = var.user_node_pool_node_labels
  node_taints           = var.user_node_pool_node_taints
  node_pool_tags        = var.user_node_pool_tags
}

# Managed Gateway API installation (azurerm does not expose ingressProfile.gatewayAPI,
# hashicorp/terraform-provider-azurerm#31710). Ordered after the user node pool: AKS
# serializes cluster operations and real Azure preempts concurrent updates with
# AKSOperationPreempted. azurerm does not model the property, so no ignore_changes is
# needed on the cluster; azapi_update_resource performs no operation on destroy (the
# setting dies with the cluster).
resource "azapi_update_resource" "gateway_api" {
  count = var.gateway_api_enabled ? 1 : 0

  type        = "Microsoft.ContainerService/managedClusters@2026-03-02-preview"
  resource_id = module.aks_cluster.id

  body = {
    properties = {
      ingressProfile = {
        gatewayAPI = {
          installation = "Standard"
        }
      }
    }
  }

  depends_on = [module.aks_node_pool]
}

# Grants the AKS kubelet identity (the agent pool user-assigned managed identity)
# AcrPull on the container registry, so nodes can pull images without credentials.
resource "azurerm_role_assignment" "acr_pull" {
  scope                            = module.container_registry.id
  role_definition_name             = "AcrPull"
  principal_id                     = module.aks_cluster.kubelet_identity_object_id
  skip_service_principal_aad_check = true
}

# Grants the Azure Key Vault Secrets Provider addon identity the Key Vault
# Administrator role on the vault (equivalent of the Bicep keyVaultRoleAssignment
# module and of 03-create-role-assignment.sh).
resource "azurerm_role_assignment" "key_vault_administrator_secrets_provider" {
  count = var.azure_keyvault_secrets_provider_enabled ? 1 : 0

  scope                            = module.key_vault.id
  role_definition_name             = "Key Vault Administrator"
  principal_id                     = module.aks_cluster.key_vault_secrets_provider_identity_object_id
  skip_service_principal_aad_check = true
}
