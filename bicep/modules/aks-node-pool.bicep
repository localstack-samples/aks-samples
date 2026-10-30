// User node pool of the AKS cluster, as the cluster scripts add it with az aks nodepool add

@description('Specifies the name of the AKS cluster.')
param clusterName string

@description('Specifies the name of the node pool.')
param name string = 'user'

@description('Specifies the resource id of the subnet of the node pool.')
param subnetId string

@description('Specifies the VM size of the nodes.')
param vmSize string = 'Standard_D4ds_v5'

@description('Specifies the number of nodes.')
param nodeCount int = 1

@description('Specifies the minimum number of nodes for the cluster autoscaler.')
param minCount int = 1

@description('Specifies the maximum number of nodes for the cluster autoscaler.')
param maxCount int = 3

@description('Specifies the maximum number of pods per node.')
param maxPods int = 100

@description('Specifies the OS disk size in GB.')
param osDiskSizeGB int = 50

@description('Specifies the OS disk type.')
@allowed([
  'Ephemeral'
  'Managed'
])
param osDiskType string = 'Ephemeral'

@description('Specifies the OS SKU.')
param osSku string = 'AzureLinux'

@description('Specifies the availability zones the nodes are spread across.')
param availabilityZones array = [
  '1'
  '2'
  '3'
]

@description('Specifies the tags of the node pool.')
param tags object = {}

@description('Specifies the node labels of the node pool.')
param nodeLabels object = {}

resource aksCluster 'Microsoft.ContainerService/managedClusters@2026-04-02-preview' existing = {
  name: clusterName
}

resource nodePool 'Microsoft.ContainerService/managedClusters/agentPools@2026-04-02-preview' = {
  parent: aksCluster
  name: name
  properties: {
    mode: 'User'
    count: nodeCount
    vmSize: vmSize
    osType: 'Linux'
    osSKU: osSku
    osDiskSizeGB: osDiskSizeGB
    osDiskType: osDiskType
    vnetSubnetID: subnetId
    maxPods: maxPods
    enableAutoScaling: true
    minCount: minCount
    maxCount: maxCount
    availabilityZones: availabilityZones
    tags: tags
    nodeLabels: nodeLabels
    type: 'VirtualMachineScaleSets'
  }
}

output name string = nodePool.name
