// Grants the AKS kubelet identity (the agent pool user-assigned managed identity)
// AcrPull on the container registry, so nodes can pull images without credentials.

// Parameters
@description('Specifies the name of the existing AKS cluster.')
param clusterName string

@description('Specifies the name of the existing container registry.')
param containerRegistryName string

// Resources
resource acrPullRoleDefinition 'Microsoft.Authorization/roleDefinitions@2022-04-01' existing = {
  name: '7f951dda-4ed3-4680-a7ca-43fe172d538d'
  scope: subscription()
}

resource aksCluster 'Microsoft.ContainerService/managedClusters@2026-04-02-preview' existing = {
  name: clusterName
}

resource containerRegistry 'Microsoft.ContainerRegistry/registries@2024-11-01-preview' existing = {
  name: containerRegistryName
}

resource acrPullRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(aksCluster.id, containerRegistry.id, acrPullRoleDefinition.id)
  scope: containerRegistry
  properties: {
    roleDefinitionId: acrPullRoleDefinition.id
    principalId: any(aksCluster.properties.identityProfile.kubeletidentity).objectId
    principalType: 'ServicePrincipal'
  }
}
