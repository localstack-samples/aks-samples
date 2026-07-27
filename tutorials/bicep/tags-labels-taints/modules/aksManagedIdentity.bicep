// User-assigned managed identity used as the AKS cluster control-plane identity,
// with Network Contributor on the VNet so the cluster can manage node subnets.

// Parameters
@description('Specifies the name of the user-assigned managed identity of the AKS cluster.')
param managedIdentityName string

@description('Specifies the name of the existing virtual network used by the AKS cluster.')
param virtualNetworkName string

@description('Specifies the location of the user-assigned managed identity.')
param location string = resourceGroup().location

@description('Specifies the resource tags.')
param tags object = {}

// Resources
resource networkContributorRoleDefinition 'Microsoft.Authorization/roleDefinitions@2022-04-01' existing = {
  name: '4d97b98b-1d4f-4787-a291-c67834d212e7'
  scope: subscription()
}

resource managedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2024-11-30' = {
  name: managedIdentityName
  location: location
  tags: tags
}

resource virtualNetwork 'Microsoft.Network/virtualNetworks@2024-05-01' existing = {
  name: virtualNetworkName
}

resource virtualNetworkContributorRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(managedIdentity.id, virtualNetwork.id, networkContributorRoleDefinition.id)
  scope: virtualNetwork
  properties: {
    roleDefinitionId: networkContributorRoleDefinition.id
    principalId: managedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

// Outputs
output managedIdentityId string = managedIdentity.id
output managedIdentityName string = managedIdentity.name
output managedIdentityPrincipalId string = managedIdentity.properties.principalId
