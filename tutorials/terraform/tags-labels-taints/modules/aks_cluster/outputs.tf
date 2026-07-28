output "id" {
  description = "Specifies the resource id of the AKS cluster."
  value       = azurerm_kubernetes_cluster.aks_cluster.id
}

output "name" {
  description = "Specifies the name of the AKS cluster."
  value       = azurerm_kubernetes_cluster.aks_cluster.name
}

output "node_resource_group" {
  description = "Specifies the node resource group of the AKS cluster."
  value       = azurerm_kubernetes_cluster.aks_cluster.node_resource_group
}

output "oidc_issuer_url" {
  description = "Specifies the OIDC issuer URL of the AKS cluster."
  value       = try(azurerm_kubernetes_cluster.aks_cluster.oidc_issuer_url, "")
}

output "kubelet_identity_object_id" {
  description = "Specifies the object id of the kubelet identity (the agent pool user-assigned managed identity)."
  value       = azurerm_kubernetes_cluster.aks_cluster.kubelet_identity[0].object_id
}

# Deliberately NOT try()-guarded when the addon is enabled: a transient refresh
# mis-read once returned "" here, silently destroying a valid role assignment and
# recreating it with an empty principal (InvalidPrincipalId). Failing loud is safer.
output "key_vault_secrets_provider_identity_object_id" {
  description = "Specifies the object id of the Azure Key Vault Secrets Provider addon identity."
  value       = var.azure_keyvault_secrets_provider_enabled ? azurerm_kubernetes_cluster.aks_cluster.key_vault_secrets_provider[0].secret_identity[0].object_id : ""
}
