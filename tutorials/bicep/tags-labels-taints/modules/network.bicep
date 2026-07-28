// Virtual network hosting the AKS node subnets. Address plan mirrors
// ~/azure/aks/scripts/01-user-assigned-managed-identity.sh. Deliberate gap: no
// AzureBastionSubnet — nothing in this sample deploys Azure Bastion.

// Parameters
@description('Specifies the name of the virtual network.')
param virtualNetworkName string

@description('Specifies the address prefixes of the virtual network.')
param virtualNetworkAddressPrefixes array = [
  '10.0.0.0/8'
]

@description('Specifies the name of the subnet hosting the system agent pool nodes.')
param systemSubnetName string = 'SystemSubnet'

@description('Specifies the address prefix of the subnet hosting the system agent pool nodes.')
param systemSubnetAddressPrefix string = '10.240.0.0/16'

@description('Specifies the name of the subnet hosting the user agent pool nodes.')
param userSubnetName string = 'UserSubnet'

@description('Specifies the address prefix of the subnet hosting the user agent pool nodes.')
param userSubnetAddressPrefix string = '10.241.0.0/16'

@description('Specifies the location of the virtual network.')
param location string = resourceGroup().location

@description('Specifies the resource tags.')
param tags object = {}

// Resources
resource virtualNetwork 'Microsoft.Network/virtualNetworks@2024-05-01' = {
  name: virtualNetworkName
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: virtualNetworkAddressPrefixes
    }
  }
}

resource systemSubnet 'Microsoft.Network/virtualNetworks/subnets@2024-05-01' = {
  parent: virtualNetwork
  name: systemSubnetName
  properties: {
    addressPrefix: systemSubnetAddressPrefix
  }
}

// dependsOn between sibling subnets is deliberate: parallel subnet writes on the
// same VNet fail with AnotherOperationInProgress on real Azure.
resource userSubnet 'Microsoft.Network/virtualNetworks/subnets@2024-05-01' = {
  parent: virtualNetwork
  name: userSubnetName
  properties: {
    addressPrefix: userSubnetAddressPrefix
  }
  dependsOn: [
    systemSubnet
  ]
}

// Outputs
output virtualNetworkId string = virtualNetwork.id
output virtualNetworkName string = virtualNetwork.name
output systemSubnetId string = systemSubnet.id
output userSubnetId string = userSubnet.id
