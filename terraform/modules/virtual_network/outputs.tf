output "id" {
  value = azurerm_virtual_network.virtual_network.id
}

output "name" {
  value = azurerm_virtual_network.virtual_network.name
}

output "system_subnet_id" {
  value = azurerm_subnet.system_subnet.id
}

output "user_subnet_id" {
  value = azurerm_subnet.user_subnet.id
}

output "bastion_subnet_id" {
  value = azurerm_subnet.bastion_subnet.id
}
