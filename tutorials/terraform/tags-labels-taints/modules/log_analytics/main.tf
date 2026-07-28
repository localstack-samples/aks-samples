# Log Analytics workspace used by the AKS cluster (oms_agent + diagnostic settings)
# and by the ACR / Key Vault diagnostic settings.

resource "azurerm_log_analytics_workspace" "workspace" {
  name                = var.name
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = var.sku
  retention_in_days   = var.retention_in_days
  tags                = var.tags

  lifecycle {
    ignore_changes = [tags]
  }
}
