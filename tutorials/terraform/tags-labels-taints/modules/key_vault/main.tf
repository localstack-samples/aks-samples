# Key Vault accessed by the AKS azureKeyvaultSecretsProvider addon identity (Key
# Vault Administrator assigned in the root main.tf). Deliberate test-sample defaults:
# public network access enabled, network ACLs allow, purge protection off — so test
# resource groups can be deleted and recreated freely. Production guidance differs.

resource "azurerm_key_vault" "key_vault" {
  name                            = var.name
  location                        = var.location
  resource_group_name             = var.resource_group_name
  tenant_id                       = var.tenant_id
  sku_name                        = var.sku_name
  rbac_authorization_enabled      = var.rbac_authorization_enabled
  purge_protection_enabled        = var.purge_protection_enabled
  soft_delete_retention_days      = var.soft_delete_retention_days
  enabled_for_deployment          = true
  enabled_for_disk_encryption     = true
  enabled_for_template_deployment = true
  public_network_access_enabled   = var.public_network_access_enabled
  tags                            = var.tags

  network_acls {
    bypass         = "AzureServices"
    default_action = var.network_acls_default_action
  }

  lifecycle {
    ignore_changes = [tags]
  }
}

# Grants the deploying user full data-plane access (certificates, keys, secrets).
resource "azurerm_role_assignment" "key_vault_administrator_user" {
  count = var.user_object_id == "" ? 0 : 1

  scope                = azurerm_key_vault.key_vault.id
  role_definition_name = "Key Vault Administrator"
  principal_id         = var.user_object_id
  principal_type       = "User"
}

resource "azurerm_monitor_diagnostic_setting" "diagnostic_setting" {
  name                       = "diagnosticSettings"
  target_resource_id         = azurerm_key_vault.key_vault.id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_log {
    category = "AuditEvent"
  }

  enabled_log {
    category = "AzurePolicyEvaluationDetails"
  }

  enabled_metric {
    category = "AllMetrics"
  }
}
