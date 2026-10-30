output "resource_group_name" {
  value = azurerm_resource_group.resource_group.name
}

output "aks_cluster_name" {
  value = module.aks_cluster.name
}

output "acr_name" {
  value = module.container_registry.name
}

output "key_vault_name" {
  value = module.key_vault.name
}

output "log_analytics_name" {
  value = module.log_analytics.name
}
