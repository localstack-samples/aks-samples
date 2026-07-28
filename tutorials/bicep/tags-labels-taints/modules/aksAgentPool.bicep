// User agent pool of the AKS cluster, on UserSubnet, carrying the sample's node
// labels, node taints, and agent-pool tags (the tags/labels/taints focus of this
// sample lives here and on the cluster in main.bicep).

// Parameters
@description('Specifies the name of the agent pool.')
param agentPoolName string

@description('Specifies the name of the existing AKS cluster.')
param clusterName string

@description('Specifies the name of the existing virtual network.')
param virtualNetworkName string

@description('Specifies the name of the existing subnet hosting the agent pool nodes.')
param subnetName string = 'UserSubnet'

@description('Specifies the mode of the agent pool.')
@allowed([
  'System'
  'User'
])
param mode string = 'User'

@description('Specifies the vm size of the nodes in the agent pool.')
param vmSize string = 'Standard_DS2_v2'

@description('Specifies the number of nodes in the agent pool.')
param agentCount int = 1

@description('Specifies whether to enable auto-scaling for the agent pool.')
param enableAutoScaling bool = false

@description('Specifies the minimum number of nodes for auto-scaling of the agent pool.')
param minCount int = 1

@description('Specifies the maximum number of nodes for auto-scaling of the agent pool.')
param maxCount int = 3

@description('Specifies the maximum number of pods per node in the agent pool.')
param maxPods int = 100

@description('Specifies the OS Disk Size in GB for the agent pool. 0 applies the platform default for the vm size.')
param osDiskSizeGB int = 0

@description('Specifies the OS disk type of the agent pool.')
@allowed([
  'Ephemeral'
  'Managed'
])
param osDiskType string = 'Managed'

@description('Specifies the OS type of the agent pool.')
@allowed([
  'Linux'
  'Windows'
])
param osType string = 'Linux'

@description('Specifies the OS SKU used by the agent pool.')
@allowed([
  'Ubuntu'
  'AzureLinux'
])
param osSKU string = 'AzureLinux'

@description('Specifies the availability zones of the agent pool. Empty deploys without zones.')
param availabilityZones array = []

@description('Specifies the node labels of the agent pool.')
param nodeLabels object = {}

@description('Specifies the node taints of the agent pool (key[=value]:effect strings).')
param nodeTaints array = []

@description('Specifies the resource tags persisted on the agent pool virtual machine scale set.')
param agentPoolTags object = {}

// Resources
resource virtualNetwork 'Microsoft.Network/virtualNetworks@2024-05-01' existing = {
  name: virtualNetworkName
}

resource subnet 'Microsoft.Network/virtualNetworks/subnets@2024-05-01' existing = {
  parent: virtualNetwork
  name: subnetName
}

resource aksCluster 'Microsoft.ContainerService/managedClusters@2026-04-02-preview' existing = {
  name: clusterName
}

resource agentPool 'Microsoft.ContainerService/managedClusters/agentPools@2026-04-02-preview' = {
  parent: aksCluster
  name: agentPoolName
  properties: {
    mode: mode
    count: agentCount
    vmSize: vmSize
    vnetSubnetID: subnet.id
    maxPods: maxPods
    osDiskSizeGB: osDiskSizeGB
    osDiskType: osDiskType
    osType: osType
    osSKU: osSKU
    enableAutoScaling: enableAutoScaling
    minCount: enableAutoScaling ? minCount : null
    maxCount: enableAutoScaling ? maxCount : null
    availabilityZones: empty(availabilityZones) ? null : availabilityZones
    nodeLabels: nodeLabels
    nodeTaints: nodeTaints
    tags: agentPoolTags
    type: 'VirtualMachineScaleSets'
  }
}

// Outputs
output agentPoolId string = agentPool.id
output agentPoolName string = agentPool.name
