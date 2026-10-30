# Virtual network with the subnets of the two node pools and of the Bastion host, and the diagnostic settings that
# send its logs and metrics to the Log Analytics workspace
resource "azurerm_virtual_network" "virtual_network" {
  name                = var.name
  location            = var.location
  resource_group_name = var.resource_group_name
  address_space       = [var.address_prefix]
}

# An Azure Files NFS share can only be reached from a virtual network, so the Azure Files CSI driver needs the
# Microsoft.Storage service endpoint on the node subnets to mount an NFS volume
resource "azurerm_subnet" "system_subnet" {
  name                 = var.system_subnet_name
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.virtual_network.name
  address_prefixes     = [var.system_subnet_prefix]

  service_endpoint {
    service = "Microsoft.Storage"
  }
}

# The subnets are created one at a time: Azure rejects concurrent changes to the same virtual network
resource "azurerm_subnet" "user_subnet" {
  name                 = var.user_subnet_name
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.virtual_network.name
  address_prefixes     = [var.user_subnet_prefix]

  service_endpoint {
    service = "Microsoft.Storage"
  }

  depends_on = [azurerm_subnet.system_subnet]
}

# Azure Bastion looks this subnet up by name
resource "azurerm_subnet" "bastion_subnet" {
  name                 = "AzureBastionSubnet"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.virtual_network.name
  address_prefixes     = [var.bastion_subnet_prefix]

  depends_on = [azurerm_subnet.user_subnet]
}

resource "azurerm_monitor_diagnostic_setting" "diagnostic_setting" {
  name                       = var.diagnostic_settings_name
  target_resource_id         = azurerm_virtual_network.virtual_network.id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_log {
    category = "VMProtectionAlerts"
  }

  enabled_metric {
    category = "AllMetrics"
  }
}
