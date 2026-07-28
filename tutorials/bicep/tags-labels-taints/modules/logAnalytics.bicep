// Log Analytics workspace used by the AKS cluster (omsagent addon + diagnostic
// settings) and by the ACR / Key Vault diagnostic settings.

// Parameters
@description('Specifies the name of the Log Analytics workspace.')
param workspaceName string

@description('Specifies the location of the Log Analytics workspace.')
param location string = resourceGroup().location

@description('Specifies the service tier of the workspace: Free, Standalone, PerNode, PerGB2018.')
@allowed([
  'Free'
  'Standalone'
  'PerNode'
  'PerGB2018'
])
param sku string = 'PerGB2018'

@description('Specifies the workspace data retention in days.')
param retentionInDays int = 60

@description('Specifies the resource tags.')
param tags object = {}

// Resources
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: workspaceName
  location: location
  tags: tags
  properties: {
    sku: {
      name: sku
    }
    retentionInDays: retentionInDays
  }
}

// Outputs
output workspaceId string = logAnalyticsWorkspace.id
output workspaceName string = logAnalyticsWorkspace.name
output workspaceCustomerId string = logAnalyticsWorkspace.properties.customerId
