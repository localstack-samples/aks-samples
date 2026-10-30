// Container registry that every sample pushes its image to, and the diagnostic settings that send its logs and
// metrics to the Log Analytics workspace

@description('Specifies the name of the container registry.')
param name string

@description('Specifies the location of the container registry.')
param location string = resourceGroup().location

@description('Specifies the SKU of the container registry.')
@allowed([
  'Basic'
  'Standard'
  'Premium'
])
param sku string = 'Basic'

@description('Specifies the resource id of the Log Analytics workspace.')
param workspaceId string

@description('Specifies the name of the diagnostic settings.')
param diagnosticSettingsName string = 'default'

resource containerRegistry 'Microsoft.ContainerRegistry/registries@2024-11-01-preview' = {
  name: name
  location: location
  sku: {
    name: sku
  }
  properties: {
    // The scripts create the registry with --admin-enabled true
    adminUserEnabled: true
  }
}

resource diagnosticSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: diagnosticSettingsName
  scope: containerRegistry
  properties: {
    workspaceId: workspaceId
    logs: [
      {
        category: 'ContainerRegistryRepositoryEvents'
        enabled: true
      }
      {
        category: 'ContainerRegistryLoginEvents'
        enabled: true
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
      }
    ]
  }
}

output id string = containerRegistry.id
output name string = containerRegistry.name
