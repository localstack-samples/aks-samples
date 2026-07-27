output "virtual_network_id" {
  description = "Specifies the resource id of the virtual network."
  value       = azurerm_virtual_network.virtual_network.id
}

output "virtual_network_name" {
  description = "Specifies the name of the virtual network."
  value       = azurerm_virtual_network.virtual_network.name
}

output "system_subnet_id" {
  description = "Specifies the resource id of the subnet hosting the system agent pool nodes."
  value       = azurerm_subnet.system_subnet.id
}

output "user_subnet_id" {
  description = "Specifies the resource id of the subnet hosting the user agent pool nodes."
  value       = azurerm_subnet.user_subnet.id
}
