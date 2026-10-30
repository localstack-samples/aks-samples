output "id" {
  value = azurerm_kubernetes_cluster.aks_cluster.id
}

output "name" {
  value = azurerm_kubernetes_cluster.aks_cluster.name
}

output "principal_id" {
  value = var.identity_type == "SystemAssigned" ? azurerm_kubernetes_cluster.aks_cluster.identity[0].principal_id : ""
}

output "kubelet_identity_object_id" {
  value = azurerm_kubernetes_cluster.aks_cluster.kubelet_identity[0].object_id
}

output "key_vault_secrets_provider_identity_object_id" {
  value = azurerm_kubernetes_cluster.aks_cluster.key_vault_secrets_provider[0].secret_identity[0].object_id
}
