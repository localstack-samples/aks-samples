output "id" {
  description = "Specifies the resource id of the Key Vault."
  value       = azurerm_key_vault.key_vault.id
}

output "name" {
  description = "Specifies the name of the Key Vault."
  value       = azurerm_key_vault.key_vault.name
}
