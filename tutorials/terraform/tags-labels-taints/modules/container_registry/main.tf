# Azure Container Registry pulled by the AKS kubelet identity (AcrPull assigned in
# the root main.tf). Basic sku: anonymous pull, data endpoints, zone redundancy, and
# registry policies are Premium-only and deliberately not configured.

resource "azurerm_container_registry" "registry" {
  name                = var.name
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = var.sku
  admin_enabled       = var.admin_enabled
  tags                = var.tags

  lifecycle {
    ignore_changes = [tags]
  }
}

resource "azurerm_monitor_diagnostic_setting" "diagnostic_setting" {
  name                       = "diagnosticSettings"
  target_resource_id         = azurerm_container_registry.registry.id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_log {
    category = "ContainerRegistryRepositoryEvents"
  }

  enabled_log {
    category = "ContainerRegistryLoginEvents"
  }

  enabled_metric {
    category = "AllMetrics"
  }
}
