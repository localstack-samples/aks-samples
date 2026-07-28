# Virtual network hosting the AKS node subnets. Address plan mirrors
# ~/azure/aks/scripts/01-user-assigned-managed-identity.sh. Deliberate gap: no
# AzureBastionSubnet — nothing in this sample deploys Azure Bastion.

resource "azurerm_virtual_network" "virtual_network" {
  name                = var.name
  location            = var.location
  resource_group_name = var.resource_group_name
  address_space       = var.address_space
  tags                = var.tags

  lifecycle {
    ignore_changes = [tags]
  }
}

resource "azurerm_subnet" "system_subnet" {
  name                 = var.system_subnet_name
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.virtual_network.name
  address_prefixes     = [var.system_subnet_address_prefix]
}

# depends_on between sibling subnets is deliberate: parallel subnet writes on the
# same VNet fail with AnotherOperationInProgress on real Azure.
resource "azurerm_subnet" "user_subnet" {
  name                 = var.user_subnet_name
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.virtual_network.name
  address_prefixes     = [var.user_subnet_address_prefix]

  depends_on = [azurerm_subnet.system_subnet]
}
