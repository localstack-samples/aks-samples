// User-assigned managed identity of the AKS cluster, as scripts/01-user-assigned-managed-identity.sh creates it

@description('Specifies the name of the user-assigned managed identity.')
param name string

@description('Specifies the location of the user-assigned managed identity.')
param location string = resourceGroup().location

resource managedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2024-11-30' = {
  name: name
  location: location
}

output id string = managedIdentity.id
output name string = managedIdentity.name
output principalId string = managedIdentity.properties.principalId
