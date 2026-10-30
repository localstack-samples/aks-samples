# Log Analytics workspace that Container Insights and the diagnostic settings of every resource send their data to
resource "azurerm_log_analytics_workspace" "workspace" {
  name                = var.name
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = var.sku

  # The scripts create the workspace with --identity-type SystemAssigned
  identity {
    type = "SystemAssigned"
  }
}
