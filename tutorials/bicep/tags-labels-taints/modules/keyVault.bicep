// Key Vault accessed by the AKS azureKeyvaultSecretsProvider addon identity
// (Key Vault Administrator assigned in modules/keyVaultRoleAssignment.bicep).
// Deliberate test-sample defaults: public network access enabled, network ACLs
// allow, purge protection off — so test resource groups can be deleted and
// recreated freely. Production guidance differs.

// Parameters
@description('Specifies the name of the Key Vault.')
param keyVaultName string

@description('Specifies the location of the Key Vault.')
param location string = resourceGroup().location

@description('Specifies the sku name of the Key Vault.')
@allowed([
  'premium'
  'standard'
])
param skuName string = 'standard'

@description('Specifies the Azure Active Directory tenant ID used for authenticating requests to the Key Vault.')
param tenantId string = subscription().tenantId

@description('Specifies whether to allow public network access for the Key Vault.')
@allowed([
  'Disabled'
  'Enabled'
])
param publicNetworkAccess string = 'Enabled'

@description('Specifies the default action when no network ACL rules match.')
@allowed([
  'Allow'
  'Deny'
])
param networkAclsDefaultAction string = 'Allow'

@description('Specifies whether the Key Vault is enabled for deployments.')
param enabledForDeployment bool = true

@description('Specifies whether the Key Vault is enabled for disk encryption.')
param enabledForDiskEncryption bool = true

@description('Specifies whether the Key Vault is enabled for template deployment.')
param enabledForTemplateDeployment bool = true

@description('Specifies whether purge protection is enabled. The property only accepts true, so false emits null (property omitted).')
param enablePurgeProtection bool = false

@description('Specifies whether RBAC authorization is enabled for the Key Vault data plane.')
param enableRbacAuthorization bool = true

@description('Specifies whether soft delete is enabled.')
param enableSoftDelete bool = true

@description('Specifies the soft delete retention in days.')
param softDeleteRetentionInDays int = 7

@description('Specifies the resource id of the Log Analytics workspace.')
param workspaceId string

@description('Specifies the object id of a Microsoft Entra ID user to grant Key Vault Administrator on the vault. Empty skips the assignment.')
param userObjectId string = ''

@description('Specifies the resource tags.')
param tags object = {}

// Variables
var diagnosticSettingsName = 'diagnosticSettings'
var logCategories = [
  'AuditEvent'
  'AzurePolicyEvaluationDetails'
]
var metricCategories = [
  'AllMetrics'
]
var logs = [
  for category in logCategories: {
    category: category
    enabled: true
    retentionPolicy: {
      enabled: true
      days: 0
    }
  }
]
var metrics = [
  for category in metricCategories: {
    category: category
    enabled: true
    retentionPolicy: {
      enabled: true
      days: 0
    }
  }
]

// Resources
resource keyVault 'Microsoft.KeyVault/vaults@2024-04-01-preview' = {
  name: keyVaultName
  location: location
  tags: tags
  properties: {
    createMode: 'default'
    sku: {
      family: 'A'
      name: skuName
    }
    tenantId: tenantId
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: networkAclsDefaultAction
    }
    enabledForDeployment: enabledForDeployment
    enabledForDiskEncryption: enabledForDiskEncryption
    enabledForTemplateDeployment: enabledForTemplateDeployment
    enablePurgeProtection: enablePurgeProtection ? enablePurgeProtection : null
    enableRbacAuthorization: enableRbacAuthorization
    enableSoftDelete: enableSoftDelete
    softDeleteRetentionInDays: softDeleteRetentionInDays
    publicNetworkAccess: publicNetworkAccess
  }
}

resource keyVaultAdministratorRoleDefinition 'Microsoft.Authorization/roleDefinitions@2022-04-01' existing = {
  name: '00482a5a-887f-4fb3-b363-3b7fe8e74483'
  scope: subscription()
}

// Grants the deploying user full data-plane access (certificates, keys, secrets).
resource keyVaultAdministratorUserRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(userObjectId)) {
  name: guid(keyVault.id, keyVaultAdministratorRoleDefinition.id, userObjectId)
  scope: keyVault
  properties: {
    roleDefinitionId: keyVaultAdministratorRoleDefinition.id
    principalType: 'User'
    principalId: userObjectId
  }
}

resource diagnosticSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: diagnosticSettingsName
  scope: keyVault
  properties: {
    workspaceId: workspaceId
    logs: logs
    metrics: metrics
  }
}

// Outputs
output keyVaultId string = keyVault.id
output keyVaultName string = keyVault.name
