output "id" {
  description = "Specifies the resource id of the user-assigned managed identity."
  value       = azurerm_user_assigned_identity.aks_identity.id
}

output "name" {
  description = "Specifies the name of the user-assigned managed identity."
  value       = azurerm_user_assigned_identity.aks_identity.name
}

output "principal_id" {
  description = "Specifies the principal id of the user-assigned managed identity."
  value       = azurerm_user_assigned_identity.aks_identity.principal_id
}

output "client_id" {
  description = "Specifies the client id of the user-assigned managed identity."
  value       = azurerm_user_assigned_identity.aks_identity.client_id
}
