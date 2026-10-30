output "id" {
  value = azurerm_bastion_host.bastion_host.id
}

output "public_ip_id" {
  value = azurerm_public_ip.public_ip.id
}
