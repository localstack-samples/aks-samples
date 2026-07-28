output "id" {
  description = "Specifies the resource id of the container registry."
  value       = azurerm_container_registry.registry.id
}

output "name" {
  description = "Specifies the name of the container registry."
  value       = azurerm_container_registry.registry.name
}
