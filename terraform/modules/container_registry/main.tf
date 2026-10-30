# Container registry that every sample pushes its image to, and the diagnostic settings that send its logs and
# metrics to the Log Analytics workspace
resource "azurerm_container_registry" "registry" {
  name                = var.name
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = var.sku

  # The scripts create the registry with --admin-enabled true
  admin_enabled = true
}

resource "azurerm_monitor_diagnostic_setting" "diagnostic_setting" {
  name                       = var.diagnostic_settings_name
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
