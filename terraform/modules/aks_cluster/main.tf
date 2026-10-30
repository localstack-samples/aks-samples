# AKS cluster of the cluster scripts: the system node pool on SystemSubnet, Microsoft Entra ID with Azure RBAC,
# Workload ID, the monitoring (Container Insights) and Key Vault secrets provider add-ons, ACNS, KEDA, the Azure Files
# CSI driver and the snapshot controller, and the diagnostic settings that send the control plane logs and the
# metrics to the Log Analytics workspace. The managed Gateway API is installed from the root module with azapi,
# because azurerm does not expose it, and the user node pool is in the aks_node_pool module.

locals {
  # The control plane logs the diagnostic settings collect. kube-audit is left out on purpose: it adds every get and
  # list request to what kube-audit-admin collects, which can be costly on Azure.
  log_categories = [
    "kube-apiserver",
    "kube-audit-admin",
    "kube-controller-manager",
    "kube-scheduler",
    "cluster-autoscaler",
    "cloud-controller-manager",
    "guard",
    "csi-azurefile-controller",
    "csi-snapshot-controller",
  ]

  # The stream that the Container Insights data collection rule sends to the workspace
  container_insights_streams = ["Microsoft-ContainerInsights-Group-Default"]
}

resource "azurerm_kubernetes_cluster" "aks_cluster" {
  name                = var.name
  location            = var.location
  resource_group_name = var.resource_group_name
  # The DNS prefix az aks create generates: the first 10 characters of the cluster name, the first 16 of the resource
  # group name and the first 6 of the subscription id
  dns_prefix         = "${substr(var.name, 0, 10)}-${substr(var.resource_group_name, 0, 16)}-${substr(var.subscription_id, 0, 6)}"
  kubernetes_version = var.kubernetes_version
  sku_tier           = "Free"
  tags               = var.tags

  role_based_access_control_enabled = true
  oidc_issuer_enabled               = true
  workload_identity_enabled         = true

  # Required by azurerm 5: Manual is the AKS default, the node pools below rather than node auto-provisioning
  node_provisioning_profile {
    mode = "Manual"
  }

  identity {
    type         = var.identity_type
    identity_ids = var.identity_type == "UserAssigned" ? [var.user_assigned_identity_id] : null
  }

  default_node_pool {
    name                        = var.system_node_pool_name
    vm_size                     = var.vm_size
    vnet_subnet_id              = var.system_subnet_id
    node_count                  = var.node_count
    auto_scaling_enabled        = true
    min_count                   = var.min_count
    max_count                   = var.max_count
    max_pods                    = var.max_pods
    os_disk_size_gb             = var.os_disk_size_gb
    os_disk_type                = var.os_disk_type
    os_sku                      = var.os_sku
    node_labels                 = var.node_labels
    tags                        = var.node_pool_tags
    temporary_name_for_rotation = "systemtemp"

    upgrade_settings {
      max_surge = "10%"
    }
  }

  # Emitted only when an SSH public key is passed
  dynamic "linux_profile" {
    for_each = var.ssh_public_key == "" ? [] : [1]
    content {
      admin_username = var.linux_admin_username
      ssh_key {
        key_data = var.ssh_public_key
      }
    }
  }

  windows_profile {
    admin_username = var.windows_admin_username
    admin_password = var.windows_admin_password
  }

  network_profile {
    network_plugin      = "azure"
    network_plugin_mode = "overlay"
    network_policy      = var.network_policy
    network_data_plane  = var.network_data_plane
    pod_cidr            = var.pod_cidr
    service_cidr        = var.service_cidr
    dns_service_ip      = var.dns_service_ip
    outbound_type       = "loadBalancer"
    load_balancer_sku   = "standard"

    # Advanced Container Networking Services, as --enable-acns turns them on. azurerm allows the security features
    # (FQDN filtering) only with the Cilium dataplane, so with the Azure dataplane only observability is on.
    advanced_networking {
      observability_enabled = true
      security_enabled      = var.network_data_plane == "cilium"
    }
  }

  oms_agent {
    log_analytics_workspace_id      = var.log_analytics_workspace_id
    msi_auth_for_monitoring_enabled = true
  }

  key_vault_secrets_provider {
    secret_rotation_enabled = false
  }

  azure_active_directory_role_based_access_control {
    tenant_id              = var.tenant_id
    admin_group_object_ids = var.aad_admin_group_object_ids
    azure_rbac_enabled     = true
  }

  workload_autoscaler_profile {
    keda_enabled = true
  }

  storage_profile {
    disk_driver_enabled         = true
    file_driver_enabled         = true
    snapshot_controller_enabled = true
  }

  lifecycle {
    ignore_changes = [
      # The cluster autoscaler changes the node count
      default_node_pool[0].node_count,
      # The emulator does not return the Windows profile, and a change to it replaces the cluster
      windows_profile,
    ]
  }
}

# Container Insights collects through a data collection rule associated with the cluster, which az aks create
# --enable-addons monitoring creates with these names
resource "azurerm_monitor_data_collection_rule" "container_insights" {
  name                = "MSCI-${var.location}-${var.name}"
  location            = var.location
  resource_group_name = var.resource_group_name
  kind                = "Linux"

  destinations {
    log_analytics {
      name                  = "la-workspace"
      workspace_resource_id = var.log_analytics_workspace_id
    }
  }

  data_flow {
    streams      = local.container_insights_streams
    destinations = ["la-workspace"]
  }

  data_sources {
    extension {
      name           = "ContainerInsightsExtension"
      extension_name = "ContainerInsights"
      streams        = local.container_insights_streams
      extension_json = jsonencode({
        dataCollectionSettings = {
          interval               = "1m"
          namespaceFilteringMode = "Off"
          enableContainerLogV2   = true
        }
      })
    }
  }
}

resource "azurerm_monitor_data_collection_rule_association" "container_insights" {
  name                    = "ContainerInsightsExtension"
  target_resource_id      = azurerm_kubernetes_cluster.aks_cluster.id
  data_collection_rule_id = azurerm_monitor_data_collection_rule.container_insights.id
  description             = "Association of data collection rule. Deleting this association will break the data collection for this AKS Cluster."
}

# The control plane logs go to the resource-specific tables of the workspace (AKSAuditAdmin, AKSControlPlane)
resource "azurerm_monitor_diagnostic_setting" "diagnostic_setting" {
  name                           = var.diagnostic_settings_name
  target_resource_id             = azurerm_kubernetes_cluster.aks_cluster.id
  log_analytics_workspace_id     = var.log_analytics_workspace_id
  log_analytics_destination_type = "Dedicated"

  dynamic "enabled_log" {
    for_each = local.log_categories
    content {
      category = enabled_log.value
    }
  }

  enabled_metric {
    category = "AllMetrics"
  }
}
