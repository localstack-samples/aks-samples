// The AKS cluster of scripts/01-system-assigned-managed-identity.sh and, with identityType set to UserAssigned, of
// scripts/01-user-assigned-managed-identity.sh: the same resources, names and defaults, including the diagnostic
// settings that send the logs and metrics of every resource to the Log Analytics workspace.

@description('Specifies the prefix of every resource name, as in the scripts.')
@minLength(1)
param prefix string = 'local'

@description('Specifies the suffix of every resource name, as in the scripts.')
@minLength(1)
param suffix string = 'test'

@description('Specifies the location of every resource.')
param location string = resourceGroup().location

@description('Specifies the cluster identity: SystemAssigned as in scripts/01-system-assigned-managed-identity.sh, UserAssigned as in scripts/01-user-assigned-managed-identity.sh.')
@allowed([
  'SystemAssigned'
  'UserAssigned'
])
param identityType string = 'SystemAssigned'

@description('Specifies the network plugin and policy, as the scripts\' menu: 1 Azure CNI Overlay with the Azure network policy, 2 with the Cilium dataplane and network policy, 3 with the Calico network policy.')
@allowed([
  1
  2
  3
])
param networkOption int = 1

@description('Specifies the Kubernetes version. Empty lets AKS pick its default; deploy.sh passes the latest GA version in the region, as the scripts do.')
param kubernetesVersion string = ''

@description('Specifies the number of nodes of the system node pool. The autoscaler range, 1 to 3, is widened to include it.')
@minValue(1)
param systemNodeCount int = 1

@description('Specifies the number of nodes of the user node pool. The autoscaler range, 1 to 3, is widened to include it.')
@minValue(1)
param userNodeCount int = 1

@description('Specifies the VM size of the nodes of both node pools.')
param nodeVmSize string = 'Standard_D4ds_v5'

@description('Specifies the OS SKU of the nodes.')
param osSku string = 'AzureLinux'

@description('Specifies the OS disk size in GB of the nodes.')
param osDiskSizeGB int = 50

@description('Specifies the OS disk type of the nodes.')
@allowed([
  'Ephemeral'
  'Managed'
])
param osDiskType string = 'Ephemeral'

@description('Specifies the maximum number of pods per node.')
param maxPods int = 100

@description('Specifies the SSH public key of the Linux nodes. deploy.sh reads ~/.ssh/id_rsa.pub, as the scripts do.')
param sshPublicKey string = ''

@description('Specifies the administrator user name of Windows nodes.')
param windowsAdminUsername string = 'azadmin'

@description('Specifies the administrator password of Windows nodes.')
@secure()
param windowsAdminPassword string

@description('Specifies the object ids of the Microsoft Entra ID groups that administer the cluster. The placeholder works on the emulator; on Azure, pass real group object ids.')
param aadAdminGroupObjectIds array = [
  '<your-admin-group-object-id>'
]

@description('Specifies the SKU of the container registry.')
param acrSku string = 'Basic'

@description('Specifies the pricing tier of the Log Analytics workspace.')
param logAnalyticsSku string = 'PerGB2018'

@description('Specifies the name of the diagnostic settings of every resource.')
param diagnosticSettingsName string = 'default'

// Names, as in the scripts
var aksClusterName = '${prefix}-aks-${suffix}'
var aksManagedIdentityName = '${prefix}-aks-identity-${suffix}'
var keyVaultName = '${prefix}-kv-${suffix}'
var acrName = '${prefix}acr${suffix}'
var logAnalyticsName = '${prefix}-log-analytics-${suffix}'
var virtualNetworkName = '${prefix}-vnet-${suffix}'
var bastionPublicIpName = '${prefix}-bastion-ip-${suffix}'
var bastionHostName = '${prefix}-bastion-${suffix}'
var systemSubnetName = 'SystemSubnet'

// Network policy and dataplane of each option of the scripts' menu
var networkOptions = {
  '1': {
    policy: 'azure'
    dataplane: 'azure'
  }
  '2': {
    policy: 'cilium'
    dataplane: 'cilium'
  }
  '3': {
    policy: 'calico'
    dataplane: 'azure'
  }
}

// The node pools' tags and labels the scripts set
var nodeLabels = {
  os_disk_type: osDiskType
  os_type: 'Linux'
}
var provisioningTags = {
  provisioning: 'bicep'
}

// Built-in roles
var networkContributorRoleId = '4d97b98b-1d4f-4787-a291-c67834d212e7'
var keyVaultAdministratorRoleId = '00482a5a-887f-4fb3-b363-3b7fe8e74483'
var acrPullRoleId = '7f951dda-4ed3-4680-a7ca-43fe172d538d'

module logAnalytics 'modules/log-analytics.bicep' = {
  name: 'logAnalytics'
  params: {
    name: logAnalyticsName
    location: location
    sku: logAnalyticsSku
  }
}

module keyVault 'modules/key-vault.bicep' = {
  name: 'keyVault'
  params: {
    name: keyVaultName
    location: location
    workspaceId: logAnalytics.outputs.id
    diagnosticSettingsName: diagnosticSettingsName
  }
}

module containerRegistry 'modules/container-registry.bicep' = {
  name: 'containerRegistry'
  params: {
    name: acrName
    location: location
    sku: acrSku
    workspaceId: logAnalytics.outputs.id
    diagnosticSettingsName: diagnosticSettingsName
  }
}

module virtualNetwork 'modules/virtual-network.bicep' = {
  name: 'virtualNetwork'
  params: {
    name: virtualNetworkName
    location: location
    systemSubnetName: systemSubnetName
    workspaceId: logAnalytics.outputs.id
    diagnosticSettingsName: diagnosticSettingsName
  }
}

module bastionHost 'modules/bastion-host.bicep' = {
  name: 'bastionHost'
  params: {
    name: bastionHostName
    publicIpAddressName: bastionPublicIpName
    location: location
    subnetId: virtualNetwork.outputs.bastionSubnetId
    workspaceId: logAnalytics.outputs.id
    diagnosticSettingsName: diagnosticSettingsName
  }
}

module managedIdentity 'modules/managed-identity.bicep' = if (identityType == 'UserAssigned') {
  name: 'managedIdentity'
  params: {
    name: aksManagedIdentityName
    location: location
  }
}

module aksCluster 'modules/aks-cluster.bicep' = {
  name: 'aksCluster'
  params: {
    name: aksClusterName
    location: location
    tags: provisioningTags
    kubernetesVersion: kubernetesVersion
    identityType: identityType
    userAssignedIdentityId: identityType == 'UserAssigned' ? managedIdentity!.outputs.id : ''
    systemSubnetId: virtualNetwork.outputs.systemSubnetId
    systemNodePoolVmSize: nodeVmSize
    systemNodePoolNodeCount: systemNodeCount
    systemNodePoolMinCount: min(1, systemNodeCount)
    systemNodePoolMaxCount: max(3, systemNodeCount)
    systemNodePoolMaxPods: maxPods
    systemNodePoolOsDiskSizeGB: osDiskSizeGB
    systemNodePoolOsDiskType: osDiskType
    systemNodePoolOsSku: osSku
    systemNodePoolTags: nodeLabels
    systemNodePoolNodeLabels: nodeLabels
    sshPublicKey: sshPublicKey
    windowsAdminUsername: windowsAdminUsername
    windowsAdminPassword: windowsAdminPassword
    networkPolicy: networkOptions[string(networkOption)].policy
    networkDataplane: networkOptions[string(networkOption)].dataplane
    aadAdminGroupObjectIds: aadAdminGroupObjectIds
    workspaceId: logAnalytics.outputs.id
    diagnosticSettingsName: diagnosticSettingsName
  }
}

module userNodePool 'modules/aks-node-pool.bicep' = {
  name: 'userNodePool'
  params: {
    clusterName: aksCluster.outputs.name
    subnetId: virtualNetwork.outputs.userSubnetId
    vmSize: nodeVmSize
    nodeCount: userNodeCount
    minCount: min(1, userNodeCount)
    maxCount: max(3, userNodeCount)
    maxPods: maxPods
    osDiskSizeGB: osDiskSizeGB
    osDiskType: osDiskType
    osSku: osSku
    tags: provisioningTags
    nodeLabels: nodeLabels
  }
}

resource existingVirtualNetwork 'Microsoft.Network/virtualNetworks@2024-05-01' existing = {
  name: virtualNetworkName
}

resource existingSystemSubnet 'Microsoft.Network/virtualNetworks/subnets@2024-05-01' existing = {
  parent: existingVirtualNetwork
  name: systemSubnetName
}

resource existingKeyVault 'Microsoft.KeyVault/vaults@2024-04-01-preview' existing = {
  name: keyVaultName
}

resource existingContainerRegistry 'Microsoft.ContainerRegistry/registries@2024-11-01-preview' existing = {
  name: acrName
}

// Network Contributor on the virtual network for the cluster identity
resource networkContributorRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(existingVirtualNetwork.id, aksClusterName, networkContributorRoleId)
  scope: existingVirtualNetwork
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', networkContributorRoleId)
    principalId: identityType == 'UserAssigned' ? managedIdentity!.outputs.principalId : aksCluster.outputs.principalId
    principalType: 'ServicePrincipal'
  }
}

// Network Contributor on the subnet of the system node pool for the cluster identity, which az aks create
// --vnet-subnet-id grants as well
resource systemSubnetNetworkContributorRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(existingSystemSubnet.id, aksClusterName, networkContributorRoleId)
  scope: existingSystemSubnet
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', networkContributorRoleId)
    principalId: identityType == 'UserAssigned' ? managedIdentity!.outputs.principalId : aksCluster.outputs.principalId
    principalType: 'ServicePrincipal'
  }
}

// AKS itself grants the cluster identity, system-assigned or user-assigned, the Contributor role on the node resource
// group: scripts/01-user-assigned-managed-identity.sh finds that assignment, and a second one would conflict with it

// Key Vault Administrator on the key vault for the identity of the Key Vault secrets provider add-on
resource keyVaultAdministratorRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(existingKeyVault.id, aksClusterName, keyVaultAdministratorRoleId)
  scope: existingKeyVault
  dependsOn: [
    keyVault
  ]
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', keyVaultAdministratorRoleId)
    principalId: aksCluster.outputs.keyVaultSecretsProviderIdentityObjectId
    principalType: 'ServicePrincipal'
  }
}

// AcrPull on the container registry for the kubelet identity, which is what az aks create --attach-acr grants
resource acrPullRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(existingContainerRegistry.id, aksClusterName, acrPullRoleId)
  scope: existingContainerRegistry
  dependsOn: [
    containerRegistry
  ]
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', acrPullRoleId)
    principalId: aksCluster.outputs.kubeletIdentityObjectId
    principalType: 'ServicePrincipal'
  }
}

output aksClusterName string = aksCluster.outputs.name
output acrName string = containerRegistry.outputs.name
output keyVaultName string = keyVault.outputs.name
output logAnalyticsName string = logAnalytics.outputs.name
