# Bastion host and its public IP address, and the diagnostic settings that send their logs and metrics to the
# Log Analytics workspace

# Azure Bastion requires a Standard SKU public IP address with a static allocation method
resource "azurerm_public_ip" "public_ip" {
  name                = var.public_ip_name
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = "Standard"
  allocation_method   = "Static"
}

resource "azurerm_bastion_host" "bastion_host" {
  name                = var.name
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = var.sku

  ip_configuration {
    name                 = "ipconfig"
    subnet_id            = var.subnet_id
    public_ip_address_id = azurerm_public_ip.public_ip.id
  }
}

# The DDoS categories only receive data while Azure DDoS Protection mitigates an attack on the address
resource "azurerm_monitor_diagnostic_setting" "public_ip_diagnostic_setting" {
  name                       = var.diagnostic_settings_name
  target_resource_id         = azurerm_public_ip.public_ip.id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_log {
    category = "DDoSProtectionNotifications"
  }

  enabled_log {
    category = "DDoSMitigationFlowLogs"
  }

  enabled_log {
    category = "DDoSMitigationReports"
  }

  enabled_metric {
    category = "AllMetrics"
  }
}

resource "azurerm_monitor_diagnostic_setting" "bastion_host_diagnostic_setting" {
  name                       = var.diagnostic_settings_name
  target_resource_id         = azurerm_bastion_host.bastion_host.id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_log {
    category = "BastionAuditLogs"
  }

  enabled_metric {
    category = "AllMetrics"
  }
}
