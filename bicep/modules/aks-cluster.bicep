// AKS cluster of the cluster scripts: the system node pool on SystemSubnet, Microsoft Entra ID with Azure RBAC,
// Workload ID, the monitoring (Container Insights) and Key Vault secrets provider add-ons, ACNS, the managed Gateway
// API, KEDA, the Azure Files CSI driver and the snapshot controller, and the diagnostic settings that send the
// control plane logs and the metrics to the Log Analytics workspace. The user node pool is in aks-node-pool.bicep.

@description('Specifies the name of the AKS cluster.')
param name string

@description('Specifies the location of the AKS cluster.')
param location string = resourceGroup().location

@description('Specifies the tags of the AKS cluster.')
param tags object = {}

@description('Specifies the Kubernetes version. Empty lets AKS pick its default.')
param kubernetesVersion string = ''

@description('Specifies the type of the cluster identity.')
@allowed([
  'SystemAssigned'
  'UserAssigned'
])
param identityType string = 'SystemAssigned'

@description('Specifies the resource id of the user-assigned identity of the cluster, when identityType is UserAssigned.')
param userAssignedIdentityId string = ''

@description('Specifies the name of the system node pool.')
param systemNodePoolName string = 'system'

@description('Specifies the resource id of the subnet of the system node pool.')
param systemSubnetId string

@description('Specifies the VM size of the system node pool.')
param systemNodePoolVmSize string = 'Standard_D4ds_v5'

@description('Specifies the number of nodes of the system node pool.')
param systemNodePoolNodeCount int = 1

@description('Specifies the minimum number of nodes of the system node pool for the cluster autoscaler.')
param systemNodePoolMinCount int = 1

@description('Specifies the maximum number of nodes of the system node pool for the cluster autoscaler.')
param systemNodePoolMaxCount int = 3

@description('Specifies the maximum number of pods per node of the system node pool.')
param systemNodePoolMaxPods int = 100

@description('Specifies the OS disk size in GB of the system node pool.')
param systemNodePoolOsDiskSizeGB int = 50

@description('Specifies the OS disk type of the system node pool.')
@allowed([
  'Ephemeral'
  'Managed'
])
param systemNodePoolOsDiskType string = 'Ephemeral'

@description('Specifies the OS SKU of the system node pool.')
param systemNodePoolOsSku string = 'AzureLinux'

@description('Specifies the tags of the system node pool.')
param systemNodePoolTags object = {}

@description('Specifies the node labels of the system node pool.')
param systemNodePoolNodeLabels object = {}

@description('Specifies the administrator user name of the Linux nodes.')
param linuxAdminUsername string = 'azureuser'

@description('Specifies the SSH public key of the Linux nodes. Empty omits the Linux profile.')
param sshPublicKey string = ''

@description('Specifies the administrator user name of Windows nodes.')
param windowsAdminUsername string = 'azadmin'

@description('Specifies the administrator password of Windows nodes.')
@secure()
param windowsAdminPassword string

@description('Specifies the network policy.')
@allowed([
  'azure'
  'calico'
  'cilium'
])
param networkPolicy string = 'azure'

@description('Specifies the network dataplane.')
@allowed([
  'azure'
  'cilium'
])
param networkDataplane string = 'azure'

@description('Specifies the CIDR of the pods.')
param podCidr string = '192.168.0.0/16'

@description('Specifies the CIDR of the services.')
param serviceCidr string = '172.16.0.0/16'

@description('Specifies the IP address of the Kubernetes DNS service, within serviceCidr.')
param dnsServiceIP string = '172.16.0.10'

@description('Specifies the object ids of the Microsoft Entra ID groups that administer the cluster.')
param aadAdminGroupObjectIds array = []

@description('Specifies the resource id of the Log Analytics workspace.')
param workspaceId string

@description('Specifies the name of the diagnostic settings.')
param diagnosticSettingsName string = 'default'

// The control plane logs the diagnostic settings collect. kube-audit is left out on purpose: it adds every get and
// list request to what kube-audit-admin collects, which can be costly on Azure.
var logCategories = [
  'kube-apiserver'
  'kube-audit-admin'
  'kube-controller-manager'
  'kube-scheduler'
  'cluster-autoscaler'
  'cloud-controller-manager'
  'guard'
  'csi-azurefile-controller'
  'csi-snapshot-controller'
]

// The stream that the Container Insights data collection rule sends to the workspace
var containerInsightsStreams = [
  'Microsoft-ContainerInsights-Group-Default'
]

resource aksCluster 'Microsoft.ContainerService/managedClusters@2026-04-02-preview' = {
  name: name
  location: location
  tags: tags
  sku: {
    name: 'Base'
    tier: 'Free'
  }
  identity: identityType == 'UserAssigned'
    ? {
        type: 'UserAssigned'
        userAssignedIdentities: {
          '${userAssignedIdentityId}': {}
        }
      }
    : {
        type: 'SystemAssigned'
      }
  properties: {
    kubernetesVersion: empty(kubernetesVersion) ? null : kubernetesVersion
    // The DNS prefix az aks create generates: the first 10 characters of the cluster name, the first 16 of the
    // resource group name and the first 6 of the subscription id
    dnsPrefix: '${take(name, 10)}-${take(resourceGroup().name, 16)}-${take(subscription().subscriptionId, 6)}'
    enableRBAC: true
    agentPoolProfiles: [
      {
        name: systemNodePoolName
        mode: 'System'
        count: systemNodePoolNodeCount
        vmSize: systemNodePoolVmSize
        osType: 'Linux'
        osSKU: systemNodePoolOsSku
        osDiskSizeGB: systemNodePoolOsDiskSizeGB
        osDiskType: systemNodePoolOsDiskType
        vnetSubnetID: systemSubnetId
        maxPods: systemNodePoolMaxPods
        enableAutoScaling: true
        minCount: systemNodePoolMinCount
        maxCount: systemNodePoolMaxCount
        tags: systemNodePoolTags
        nodeLabels: systemNodePoolNodeLabels
        type: 'VirtualMachineScaleSets'
      }
    ]
    linuxProfile: empty(sshPublicKey)
      ? null
      : {
          adminUsername: linuxAdminUsername
          ssh: {
            publicKeys: [
              {
                keyData: sshPublicKey
              }
            ]
          }
        }
    windowsProfile: {
      adminUsername: windowsAdminUsername
      adminPassword: windowsAdminPassword
    }
    addonProfiles: {
      omsagent: {
        enabled: true
        config: {
          logAnalyticsWorkspaceResourceID: workspaceId
          useAADAuth: 'true'
        }
      }
      azureKeyvaultSecretsProvider: {
        enabled: true
        config: {
          enableSecretRotation: 'false'
          rotationPollInterval: '2m'
        }
      }
    }
    oidcIssuerProfile: {
      enabled: true
    }
    securityProfile: {
      workloadIdentity: {
        enabled: true
      }
    }
    aadProfile: {
      managed: true
      enableAzureRBAC: true
      adminGroupObjectIDs: aadAdminGroupObjectIds
      tenantID: subscription().tenantId
    }
    ingressProfile: {
      gatewayAPI: {
        installation: 'Standard'
      }
    }
    workloadAutoScalerProfile: {
      keda: {
        enabled: true
      }
    }
    networkProfile: {
      networkPlugin: 'azure'
      networkPluginMode: 'overlay'
      networkPolicy: networkPolicy
      networkDataplane: networkDataplane
      podCidr: podCidr
      serviceCidr: serviceCidr
      dnsServiceIP: dnsServiceIP
      outboundType: 'loadBalancer'
      loadBalancerSku: 'standard'
      // Advanced Container Networking Services, exactly as az aks create --enable-acns requests them: AKS turns on
      // observability, and the security features (FQDN filtering) only with the Cilium dataplane, which they need
      advancedNetworking: {
        enabled: true
      }
    }
    storageProfile: {
      diskCSIDriver: {
        enabled: true
      }
      fileCSIDriver: {
        enabled: true
      }
      snapshotController: {
        enabled: true
      }
    }
  }
}

// Container Insights collects through a data collection rule associated with the cluster, which az aks create
// --enable-addons monitoring creates with these names
resource dataCollectionRule 'Microsoft.Insights/dataCollectionRules@2023-03-11' = {
  name: 'MSCI-${location}-${name}'
  location: location
  kind: 'Linux'
  properties: {
    dataSources: {
      extensions: [
        {
          name: 'ContainerInsightsExtension'
          extensionName: 'ContainerInsights'
          streams: containerInsightsStreams
          extensionSettings: {
            dataCollectionSettings: {
              interval: '1m'
              namespaceFilteringMode: 'Off'
              enableContainerLogV2: true
            }
          }
        }
      ]
    }
    destinations: {
      logAnalytics: [
        {
          name: 'la-workspace'
          workspaceResourceId: workspaceId
        }
      ]
    }
    dataFlows: [
      {
        streams: containerInsightsStreams
        destinations: [
          'la-workspace'
        ]
      }
    ]
  }
}

resource dataCollectionRuleAssociation 'Microsoft.Insights/dataCollectionRuleAssociations@2023-03-11' = {
  name: 'ContainerInsightsExtension'
  scope: aksCluster
  properties: {
    dataCollectionRuleId: dataCollectionRule.id
    description: 'Association of data collection rule. Deleting this association will break the data collection for this AKS Cluster.'
  }
}

// The control plane logs go to the resource-specific tables of the workspace (AKSAuditAdmin, AKSControlPlane)
resource diagnosticSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: diagnosticSettingsName
  scope: aksCluster
  properties: {
    workspaceId: workspaceId
    logAnalyticsDestinationType: 'Dedicated'
    logs: [
      for category in logCategories: {
        category: category
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

output id string = aksCluster.id
output name string = aksCluster.name
output principalId string = identityType == 'SystemAssigned' ? aksCluster.identity.principalId : ''
output kubeletIdentityObjectId string = aksCluster.properties.identityProfile.kubeletidentity.objectId
output keyVaultSecretsProviderIdentityObjectId string = aksCluster.properties.addonProfiles.azureKeyvaultSecretsProvider.identity.objectId
