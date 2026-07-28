output "id" {
  description = "Specifies the resource id of the Log Analytics workspace."
  value       = azurerm_log_analytics_workspace.workspace.id
}

output "name" {
  description = "Specifies the name of the Log Analytics workspace."
  value       = azurerm_log_analytics_workspace.workspace.name
}

output "customer_id" {
  description = "Specifies the workspace (customer) id of the Log Analytics workspace."
  value       = azurerm_log_analytics_workspace.workspace.workspace_id
}
