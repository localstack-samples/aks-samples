# AKS managed cluster: user-assigned identity, system agent pool on SystemSubnet,
# Managed Gateway API (via azapi — azurerm does not expose ingressProfile.gatewayAPI
# yet, see hashicorp/terraform-provider-azurerm#31710), Workload Identity + OIDC
# issuer, Azure Key Vault Secrets Provider addon, CSI storage drivers, managed AAD +
# Azure RBAC, VPA, oms_agent and diagnostic settings wired to Log Analytics. The user
# agent pool lives in modules/aks_node_pool. Deliberate gaps vs the Bicep reference
# repo: no private cluster / API-server VNet integration, no web-app routing / DNS
# zones, no Istio / Dapr / Flux, no Defender / ImageCleaner / Prometheus.

terraform {
  required_providers {
    azurerm = {
      source = "hashicorp/azurerm"
    }
  }
}

locals {
  log_categories = [
    "kube-apiserver",
    "kube-audit",
    "kube-audit-admin",
    "kube-controller-manager",
    "kube-scheduler",
    "cluster-autoscaler",
    "cloud-controller-manager",
    "guard",
    "csi-azuredisk-controller",
    "csi-azurefile-controller",
    "csi-snapshot-controller",
  ]
}

resource "azurerm_kubernetes_cluster" "aks_cluster" {
  name                = var.name
  location            = var.location
  resource_group_name = var.resource_group_name
  dns_prefix          = var.dns_prefix == "" ? lower(var.name) : var.dns_prefix
  kubernetes_version  = var.kubernetes_version
  sku_tier            = var.sku_tier
  tags                = var.tags

  role_based_access_control_enabled = var.rbac_enabled
  oidc_issuer_enabled               = var.oidc_issuer_enabled
  workload_identity_enabled         = var.workload_identity_enabled
  automatic_upgrade_channel         = var.automatic_upgrade_channel
  node_os_upgrade_channel           = var.node_os_upgrade_channel

  identity {
    type         = "UserAssigned"
    identity_ids = [var.managed_identity_id]
  }

  default_node_pool {
    name                        = var.system_node_pool_name
    vm_size                     = var.system_node_pool_vm_size
    vnet_subnet_id              = var.system_subnet_id
    node_count                  = var.system_node_pool_node_count
    auto_scaling_enabled        = var.system_node_pool_auto_scaling_enabled
    min_count                   = var.system_node_pool_auto_scaling_enabled ? var.system_node_pool_min_count : null
    max_count                   = var.system_node_pool_auto_scaling_enabled ? var.system_node_pool_max_count : null
    max_pods                    = var.system_node_pool_max_pods
    os_disk_type                = var.system_node_pool_os_disk_type
    os_sku                      = var.system_node_pool_os_sku
    zones                       = length(var.system_node_pool_availability_zones) > 0 ? var.system_node_pool_availability_zones : null
    node_labels                 = var.system_node_pool_node_labels
    temporary_name_for_rotation = "systemtemp"
    tags                        = var.tags

    # Matches the value AKS assigns automatically; leaving it unset makes every
    # real-Azure plan carry a perpetual in-place diff.
    upgrade_settings {
      max_surge = "10%"
    }
  }

  # linux_profile is emitted only when an SSH public key is provided
  # (emulator-friendly, mirrors the Bicep module).
  dynamic "linux_profile" {
    for_each = var.ssh_public_key == "" ? [] : [1]
    content {
      admin_username = var.admin_username

      ssh_key {
        key_data = var.ssh_public_key
      }
    }
  }

  network_profile {
    network_plugin      = var.network_plugin
    network_plugin_mode = var.network_plugin_mode == "" ? null : var.network_plugin_mode
    network_policy      = var.network_policy
    network_data_plane  = var.network_data_plane
    pod_cidr            = var.network_plugin == "kubenet" || var.network_plugin_mode == "overlay" ? var.pod_cidr : null
    service_cidr        = var.service_cidr
    dns_service_ip      = var.dns_service_ip
    outbound_type       = var.outbound_type
    load_balancer_sku   = var.load_balancer_sku
  }

  dynamic "key_vault_secrets_provider" {
    for_each = var.azure_keyvault_secrets_provider_enabled ? [1] : []
    content {
      secret_rotation_enabled = var.secret_rotation_enabled
    }
  }

  storage_profile {
    blob_driver_enabled         = var.blob_csi_driver_enabled
    disk_driver_enabled         = var.disk_csi_driver_enabled
    file_driver_enabled         = var.file_csi_driver_enabled
    snapshot_controller_enabled = var.snapshot_controller_enabled
  }

  workload_autoscaler_profile {
    keda_enabled                    = var.keda_enabled
    vertical_pod_autoscaler_enabled = var.vertical_pod_autoscaler_enabled
  }

  # AAD RBAC block is omitted entirely when managed AAD is off (mirrors the Bicep
  # module, where ARM rejects managed:false with null legacy app ids).
  dynamic "azure_active_directory_role_based_access_control" {
    for_each = var.aad_enabled ? [1] : []
    content {
      tenant_id              = var.aad_tenant_id
      admin_group_object_ids = var.aad_admin_group_object_ids
      azure_rbac_enabled     = var.aad_azure_rbac_enabled
    }
  }

  oms_agent {
    log_analytics_workspace_id      = var.log_analytics_workspace_id
    msi_auth_for_monitoring_enabled = true
  }

  auto_scaler_profile {
    scan_interval                    = var.auto_scaler_profile_scan_interval
    scale_down_delay_after_add       = var.auto_scaler_profile_scale_down_delay_after_add
    scale_down_delay_after_delete    = var.auto_scaler_profile_scale_down_delay_after_delete
    scale_down_delay_after_failure   = var.auto_scaler_profile_scale_down_delay_after_failure
    scale_down_unneeded              = var.auto_scaler_profile_scale_down_unneeded
    scale_down_unready               = var.auto_scaler_profile_scale_down_unready
    scale_down_utilization_threshold = var.auto_scaler_profile_scale_down_utilization_threshold
    max_graceful_termination_sec     = var.auto_scaler_profile_max_graceful_termination_sec
    expander                         = var.auto_scaler_profile_expander
  }
}

# The Managed Gateway API azapi patch lives in the root main.tf: it must be ordered
# after the user node pool (AKS serializes cluster operations and real Azure preempts
# concurrent updates with AKSOperationPreempted), which this module cannot express.

# Grants the deploying user cluster-admin over the Kubernetes API when Azure RBAC is
# enabled — required for the kubectl validation in deploy.sh on real Azure.
resource "azurerm_role_assignment" "aks_rbac_cluster_admin" {
  count = var.user_object_id == "" ? 0 : 1

  scope                = azurerm_kubernetes_cluster.aks_cluster.id
  role_definition_name = "Azure Kubernetes Service RBAC Cluster Admin"
  principal_id         = var.user_object_id
  principal_type       = "User"
}

resource "azurerm_monitor_diagnostic_setting" "diagnostic_setting" {
  name                       = "diagnosticSettings"
  target_resource_id         = azurerm_kubernetes_cluster.aks_cluster.id
  log_analytics_workspace_id = var.log_analytics_workspace_id

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
