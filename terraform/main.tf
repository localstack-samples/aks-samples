# The AKS cluster of scripts/01-system-assigned-managed-identity.sh and, with identity_type set to UserAssigned, of
# scripts/01-user-assigned-managed-identity.sh: the same resources, names and defaults, including the diagnostic
# settings that send the logs and metrics of every resource to the Log Analytics workspace.

data "azurerm_client_config" "current" {}

locals {
  # Names, as in the scripts
  resource_group_name       = "${var.prefix}-rg"
  aks_cluster_name          = "${var.prefix}-aks-${var.suffix}"
  aks_managed_identity_name = "${var.prefix}-aks-identity-${var.suffix}"
  key_vault_name            = "${var.prefix}-kv-${var.suffix}"
  acr_name                  = "${var.prefix}acr${var.suffix}"
  log_analytics_name        = "${var.prefix}-log-analytics-${var.suffix}"
  virtual_network_name      = "${var.prefix}-vnet-${var.suffix}"
  bastion_public_ip_name    = "${var.prefix}-bastion-ip-${var.suffix}"
  bastion_host_name         = "${var.prefix}-bastion-${var.suffix}"

  # Network policy and dataplane of each option of the scripts' menu
  network_options = {
    "1" = { policy = "azure", data_plane = "azure" }
    "2" = { policy = "cilium", data_plane = "cilium" }
    "3" = { policy = "calico", data_plane = "azure" }
  }
  network = local.network_options[tostring(var.network_option)]

  # The node pools' tags and labels the scripts set
  node_labels = {
    os_disk_type = var.os_disk_type
    os_type      = "Linux"
  }
  provisioning_tags = {
    provisioning = "terraform"
  }
}

resource "azurerm_resource_group" "resource_group" {
  name     = local.resource_group_name
  location = var.location
}

module "log_analytics" {
  source = "./modules/log_analytics"

  name                = local.log_analytics_name
  location            = var.location
  resource_group_name = azurerm_resource_group.resource_group.name
  sku                 = var.log_analytics_sku
}

module "key_vault" {
  source = "./modules/key_vault"

  name                       = local.key_vault_name
  location                   = var.location
  resource_group_name        = azurerm_resource_group.resource_group.name
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  log_analytics_workspace_id = module.log_analytics.id
  diagnostic_settings_name   = var.diagnostic_settings_name
}

module "container_registry" {
  source = "./modules/container_registry"

  name                       = local.acr_name
  location                   = var.location
  resource_group_name        = azurerm_resource_group.resource_group.name
  sku                        = var.acr_sku
  log_analytics_workspace_id = module.log_analytics.id
  diagnostic_settings_name   = var.diagnostic_settings_name
}

module "virtual_network" {
  source = "./modules/virtual_network"

  name                       = local.virtual_network_name
  location                   = var.location
  resource_group_name        = azurerm_resource_group.resource_group.name
  log_analytics_workspace_id = module.log_analytics.id
  diagnostic_settings_name   = var.diagnostic_settings_name
}

module "bastion_host" {
  source = "./modules/bastion_host"

  name                       = local.bastion_host_name
  public_ip_name             = local.bastion_public_ip_name
  location                   = var.location
  resource_group_name        = azurerm_resource_group.resource_group.name
  subnet_id                  = module.virtual_network.bastion_subnet_id
  log_analytics_workspace_id = module.log_analytics.id
  diagnostic_settings_name   = var.diagnostic_settings_name
}

# The user-assigned identity of the cluster, as scripts/01-user-assigned-managed-identity.sh creates it
resource "azurerm_user_assigned_identity" "aks" {
  count = var.identity_type == "UserAssigned" ? 1 : 0

  name                = local.aks_managed_identity_name
  location            = var.location
  resource_group_name = azurerm_resource_group.resource_group.name
}

module "aks_cluster" {
  source = "./modules/aks_cluster"

  name                       = local.aks_cluster_name
  location                   = var.location
  resource_group_name        = azurerm_resource_group.resource_group.name
  subscription_id            = data.azurerm_client_config.current.subscription_id
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  tags                       = local.provisioning_tags
  kubernetes_version         = var.kubernetes_version
  identity_type              = var.identity_type
  user_assigned_identity_id  = var.identity_type == "UserAssigned" ? azurerm_user_assigned_identity.aks[0].id : ""
  system_subnet_id           = module.virtual_network.system_subnet_id
  vm_size                    = var.node_vm_size
  node_count                 = var.system_node_count
  min_count                  = min(1, var.system_node_count)
  max_count                  = max(3, var.system_node_count)
  max_pods                   = var.max_pods
  os_disk_size_gb            = var.os_disk_size_gb
  os_disk_type               = var.os_disk_type
  os_sku                     = var.os_sku
  node_labels                = local.node_labels
  node_pool_tags             = local.node_labels
  ssh_public_key             = var.ssh_public_key
  windows_admin_username     = var.windows_admin_username
  windows_admin_password     = var.windows_admin_password
  network_policy             = local.network.policy
  network_data_plane         = local.network.data_plane
  aad_admin_group_object_ids = var.aad_admin_group_object_ids
  log_analytics_workspace_id = module.log_analytics.id
  diagnostic_settings_name   = var.diagnostic_settings_name
}

module "aks_node_pool" {
  source = "./modules/aks_node_pool"

  kubernetes_cluster_id = module.aks_cluster.id
  subnet_id             = module.virtual_network.user_subnet_id
  vm_size               = var.node_vm_size
  node_count            = var.user_node_count
  min_count             = min(1, var.user_node_count)
  max_count             = max(3, var.user_node_count)
  max_pods              = var.max_pods
  os_disk_size_gb       = var.os_disk_size_gb
  os_disk_type          = var.os_disk_type
  os_sku                = var.os_sku
  node_labels           = local.node_labels
  tags                  = local.provisioning_tags
}

# The managed Gateway API CRDs (azurerm does not expose ingressProfile.gatewayAPI). Ordered after the user node pool:
# AKS serializes the operations on a cluster. deploy.sh turns it off on the emulator, which does not persist it from
# this PUT, and enables the Gateway API there with az aks update instead.
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

# Network Contributor on the virtual network for the cluster identity
resource "azurerm_role_assignment" "network_contributor" {
  scope                            = module.virtual_network.id
  role_definition_name             = "Network Contributor"
  principal_id                     = var.identity_type == "UserAssigned" ? azurerm_user_assigned_identity.aks[0].principal_id : module.aks_cluster.principal_id
  skip_service_principal_aad_check = true
}

# Network Contributor on the subnet of the system node pool for the cluster identity, which az aks create
# --vnet-subnet-id grants as well
resource "azurerm_role_assignment" "system_subnet_network_contributor" {
  scope                            = module.virtual_network.system_subnet_id
  role_definition_name             = "Network Contributor"
  principal_id                     = var.identity_type == "UserAssigned" ? azurerm_user_assigned_identity.aks[0].principal_id : module.aks_cluster.principal_id
  skip_service_principal_aad_check = true
}

# AKS itself grants the cluster identity, system-assigned or user-assigned, the Contributor role on the node resource
# group: scripts/01-user-assigned-managed-identity.sh finds that assignment, and a second one would conflict with it

# Key Vault Administrator on the key vault for the identity of the Key Vault secrets provider add-on
resource "azurerm_role_assignment" "key_vault_administrator" {
  scope                            = module.key_vault.id
  role_definition_name             = "Key Vault Administrator"
  principal_id                     = module.aks_cluster.key_vault_secrets_provider_identity_object_id
  skip_service_principal_aad_check = true
}

# AcrPull on the container registry for the kubelet identity, which is what az aks create --attach-acr grants
resource "azurerm_role_assignment" "acr_pull" {
  scope                            = module.container_registry.id
  role_definition_name             = "AcrPull"
  principal_id                     = module.aks_cluster.kubelet_identity_object_id
  skip_service_principal_aad_check = true
}
