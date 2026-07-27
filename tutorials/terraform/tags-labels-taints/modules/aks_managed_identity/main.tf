# User-assigned managed identity used as the AKS cluster control-plane identity,
# with Network Contributor on the VNet so the cluster can manage node subnets.

resource "azurerm_user_assigned_identity" "aks_identity" {
  name                = var.name
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags

  lifecycle {
    ignore_changes = [tags]
  }
}

resource "azurerm_role_assignment" "network_contributor" {
  scope                            = var.virtual_network_id
  role_definition_name             = "Network Contributor"
  principal_id                     = azurerm_user_assigned_identity.aks_identity.principal_id
  skip_service_principal_aad_check = true
}
