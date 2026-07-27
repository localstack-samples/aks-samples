output "id" {
  description = "Specifies the resource id of the agent pool."
  value       = azurerm_kubernetes_cluster_node_pool.node_pool.id
}

output "name" {
  description = "Specifies the name of the agent pool."
  value       = azurerm_kubernetes_cluster_node_pool.node_pool.name
}
