// Log Analytics workspace that Container Insights and the diagnostic settings of every resource send their data to

@description('Specifies the name of the Log Analytics workspace.')
param name string

@description('Specifies the location of the Log Analytics workspace.')
param location string = resourceGroup().location

@description('Specifies the pricing tier of the Log Analytics workspace.')
param sku string = 'PerGB2018'

resource workspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: name
  location: location
  // The scripts create the workspace with --identity-type SystemAssigned
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    sku: {
      name: sku
    }
  }
}

output id string = workspace.id
output name string = workspace.name
