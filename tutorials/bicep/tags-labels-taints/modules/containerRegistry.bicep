// Azure Container Registry pulled by the AKS kubelet identity (AcrPull assigned in
// modules/kubeletManagedIdentity.bicep). Deliberate gaps vs the reference module:
// no policies block and anonymous pull / data endpoints / zone redundancy default
// off — those features require the Premium sku and this sample defaults to Basic.

// Parameters
@description('Specifies the name of the container registry.')
@minLength(5)
@maxLength(50)
param containerRegistryName string

@description('Specifies the tier of the container registry.')
@allowed([
  'Basic'
  'Standard'
  'Premium'
])
param sku string = 'Basic'

@description('Specifies whether the admin user is enabled.')
param adminUserEnabled bool = true

@description('Specifies whether registry-wide pull is enabled from unauthenticated clients (Premium only).')
param anonymousPullEnabled bool = false

@description('Specifies whether a single data endpoint is enabled per region for serving data (Premium only).')
param dataEndpointEnabled bool = false

@description('Specifies whether to allow trusted Azure services to access a network restricted registry.')
@allowed([
  'AzureServices'
  'None'
])
param networkRuleBypassOptions string = 'AzureServices'

@description('Specifies whether to allow public network access for the container registry.')
@allowed([
  'Disabled'
  'Enabled'
])
param publicNetworkAccess string = 'Enabled'

@description('Specifies whether zone redundancy is enabled for the container registry (Premium only).')
@allowed([
  'Disabled'
  'Enabled'
])
param zoneRedundancy string = 'Disabled'

@description('Specifies the resource id of the Log Analytics workspace.')
param workspaceId string

@description('Specifies the location of the container registry.')
param location string = resourceGroup().location

@description('Specifies the resource tags.')
param tags object = {}

// Variables
var diagnosticSettingsName = 'diagnosticSettings'
var logCategories = [
  'ContainerRegistryRepositoryEvents'
  'ContainerRegistryLoginEvents'
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
resource containerRegistry 'Microsoft.ContainerRegistry/registries@2024-11-01-preview' = {
  name: containerRegistryName
  location: location
  tags: tags
  sku: {
    name: sku
  }
  properties: {
    adminUserEnabled: adminUserEnabled
    anonymousPullEnabled: anonymousPullEnabled
    dataEndpointEnabled: dataEndpointEnabled
    networkRuleBypassOptions: networkRuleBypassOptions
    publicNetworkAccess: publicNetworkAccess
    zoneRedundancy: zoneRedundancy
  }
}

resource diagnosticSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: diagnosticSettingsName
  scope: containerRegistry
  properties: {
    workspaceId: workspaceId
    logs: logs
    metrics: metrics
  }
}

// Outputs
output containerRegistryId string = containerRegistry.id
output containerRegistryName string = containerRegistry.name
