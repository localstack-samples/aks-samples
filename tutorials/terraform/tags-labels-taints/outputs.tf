# Root outputs mirror the Bicep main.bicep outputs 1:1 (user_node_pool_name is
# userNodePoolName there) so the deploy.sh validation battery works identically
# across both stacks.

output "cluster_name" {
  description = "Specifies the name of the AKS cluster."
  value       = module.aks_cluster.name
}

output "user_node_pool_name" {
  description = "Specifies the name of the user agent pool."
  value       = module.aks_node_pool.name
}

output "acr_name" {
  description = "Specifies the name of the container registry."
  value       = module.container_registry.name
}

output "key_vault_name" {
  description = "Specifies the name of the Key Vault."
  value       = module.key_vault.name
}

output "log_analytics_workspace_name" {
  description = "Specifies the name of the Log Analytics workspace."
  value       = module.log_analytics.name
}

output "managed_identity_name" {
  description = "Specifies the name of the AKS user-assigned managed identity."
  value       = module.aks_managed_identity.name
}

output "node_resource_group" {
  description = "Specifies the node resource group of the AKS cluster."
  value       = module.aks_cluster.node_resource_group
}

output "oidc_issuer_url" {
  description = "Specifies the OIDC issuer URL of the AKS cluster."
  value       = module.aks_cluster.oidc_issuer_url
}

output "key_vault_secrets_provider_object_id" {
  description = "Specifies the object id of the Azure Key Vault Secrets Provider addon identity."
  value       = module.aks_cluster.key_vault_secrets_provider_identity_object_id
}
