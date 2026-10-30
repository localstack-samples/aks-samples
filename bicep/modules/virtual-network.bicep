// Virtual network with the subnets of the two node pools and of the Bastion host, and the diagnostic settings that
// send its logs and metrics to the Log Analytics workspace

@description('Specifies the name of the virtual network.')
param name string

@description('Specifies the location of the virtual network.')
param location string = resourceGroup().location

@description('Specifies the address prefix of the virtual network.')
param addressPrefix string = '10.0.0.0/8'

@description('Specifies the name of the subnet of the system node pool.')
param systemSubnetName string = 'SystemSubnet'

@description('Specifies the address prefix of the subnet of the system node pool.')
param systemSubnetPrefix string = '10.240.0.0/16'

@description('Specifies the name of the subnet of the user node pool.')
param userSubnetName string = 'UserSubnet'

@description('Specifies the address prefix of the subnet of the user node pool.')
param userSubnetPrefix string = '10.241.0.0/16'

@description('Specifies the address prefix of the AzureBastionSubnet subnet.')
param bastionSubnetPrefix string = '10.242.2.0/24'

@description('Specifies the resource id of the Log Analytics workspace.')
param workspaceId string

@description('Specifies the name of the diagnostic settings.')
param diagnosticSettingsName string = 'default'

// An Azure Files NFS share can only be reached from a virtual network, so the Azure Files CSI driver needs the
// Microsoft.Storage service endpoint on the node subnets to mount an NFS volume
var storageServiceEndpoints = [
  {
    service: 'Microsoft.Storage'
  }
]

resource virtualNetwork 'Microsoft.Network/virtualNetworks@2024-05-01' = {
  name: name
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        addressPrefix
      ]
    }
    subnets: [
      {
        name: systemSubnetName
        properties: {
          addressPrefix: systemSubnetPrefix
          serviceEndpoints: storageServiceEndpoints
        }
      }
      {
        name: userSubnetName
        properties: {
          addressPrefix: userSubnetPrefix
          serviceEndpoints: storageServiceEndpoints
        }
      }
      {
        // Azure Bastion looks this subnet up by name
        name: 'AzureBastionSubnet'
        properties: {
          addressPrefix: bastionSubnetPrefix
        }
      }
    ]
  }
}

resource diagnosticSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: diagnosticSettingsName
  scope: virtualNetwork
  properties: {
    workspaceId: workspaceId
    logs: [
      {
        category: 'VMProtectionAlerts'
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

output id string = virtualNetwork.id
output name string = virtualNetwork.name
output systemSubnetId string = resourceId('Microsoft.Network/virtualNetworks/subnets', name, systemSubnetName)
output userSubnetId string = resourceId('Microsoft.Network/virtualNetworks/subnets', name, userSubnetName)
output bastionSubnetId string = resourceId('Microsoft.Network/virtualNetworks/subnets', name, 'AzureBastionSubnet')
