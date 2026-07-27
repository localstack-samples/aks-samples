// AKS managed cluster: user-assigned identity, system agent pool on SystemSubnet,
// Managed Gateway API, Workload Identity + OIDC issuer, Azure Key Vault Secrets
// Provider addon, CSI storage drivers, managed AAD + Azure RBAC, VPA, omsagent and
// diagnostic settings wired to Log Analytics. The user agent pool lives in
// modules/aksAgentPool.bicep. Deliberate gaps vs the reference module: no private
// cluster / API-server VNet integration, no web-app routing / DNS zones, no
// Istio / Dapr / Flux, no Defender / ImageCleaner / Prometheus — not in PROMPT.md.

// Parameters
@description('Specifies the name of the AKS cluster.')
param clusterName string

@description('Specifies the DNS prefix of the AKS cluster.')
param dnsPrefix string = toLower(clusterName)

@description('Specifies the location of the AKS cluster.')
param location string = resourceGroup().location

@description('Specifies the resource tags for the AKS cluster.')
param tags object = {}

@description('Specifies the tier of the managed cluster SKU.')
@allowed([
  'Free'
  'Standard'
  'Premium'
])
param skuTier string = 'Free'

@description('Specifies the Kubernetes version. Empty lets the platform pick its default.')
param kubernetesVersion string = ''

@description('Specifies the name of the existing user-assigned managed identity of the AKS cluster.')
param managedIdentityName string

@description('Specifies the name of the existing virtual network.')
param virtualNetworkName string

@description('Specifies the name of the existing subnet hosting the system agent pool nodes.')
param systemSubnetName string = 'SystemSubnet'

@description('Specifies the network plugin used for building the Kubernetes network.')
@allowed([
  'azure'
  'kubenet'
])
param networkPlugin string = 'azure'

@description('Specifies the network plugin mode used for building the Kubernetes network.')
@allowed([
  ''
  'overlay'
])
param networkPluginMode string = 'overlay'

@description('Specifies the network policy used for building the Kubernetes network.')
@allowed([
  'azure'
  'calico'
  'cilium'
  'none'
])
param networkPolicy string = 'azure'

@description('Specifies the network dataplane used in the Kubernetes cluster.')
@allowed([
  'azure'
  'cilium'
])
param networkDataplane string = 'azure'

@description('Specifies the CIDR notation IP range from which to assign pod IPs (overlay or kubenet).')
param podCidr string = '192.168.0.0/16'

@description('Specifies the CIDR notation IP range from which to assign service cluster IPs.')
param serviceCidr string = '172.16.0.0/16'

@description('Specifies the IP address assigned to the Kubernetes DNS service; must be within serviceCidr.')
param dnsServiceIP string = '172.16.0.10'

@description('Specifies the sku of the load balancer used by the AKS cluster.')
@allowed([
  'basic'
  'standard'
])
param loadBalancerSku string = 'standard'

@description('Specifies the outbound (egress) routing method.')
@allowed([
  'loadBalancer'
  'managedNATGateway'
  'userAssignedNATGateway'
  'userDefinedRouting'
])
param outboundType string = 'loadBalancer'

@description('Specifies the name of the system agent pool.')
param systemAgentPoolName string = 'system'

@description('Specifies the vm size of the nodes in the system agent pool.')
param systemAgentPoolVmSize string = 'Standard_DS2_v2'

@description('Specifies the number of nodes in the system agent pool.')
param systemAgentPoolAgentCount int = 1

@description('Specifies whether to enable auto-scaling for the system agent pool.')
param systemAgentPoolEnableAutoScaling bool = false

@description('Specifies the minimum number of nodes for auto-scaling of the system agent pool.')
param systemAgentPoolMinCount int = 1

@description('Specifies the maximum number of nodes for auto-scaling of the system agent pool.')
param systemAgentPoolMaxCount int = 3

@description('Specifies the maximum number of pods per node in the system agent pool.')
param systemAgentPoolMaxPods int = 100

@description('Specifies the OS Disk Size in GB for the system agent pool. 0 applies the platform default for the vm size.')
param systemAgentPoolOsDiskSizeGB int = 0

@description('Specifies the OS disk type of the system agent pool.')
@allowed([
  'Ephemeral'
  'Managed'
])
param systemAgentPoolOsDiskType string = 'Managed'

@description('Specifies the OS SKU used by the system agent pool.')
@allowed([
  'Ubuntu'
  'AzureLinux'
])
param systemAgentPoolOsSKU string = 'AzureLinux'

@description('Specifies the availability zones of the system agent pool. Empty deploys without zones.')
param systemAgentPoolAvailabilityZones array = []

@description('Specifies the node labels of the system agent pool.')
param systemAgentPoolNodeLabels object = {}

@description('Specifies the node taints of the system agent pool (key[=value]:effect strings).')
param systemAgentPoolNodeTaints array = []

@description('Specifies the administrator username of Linux virtual machines.')
param adminUsername string = 'azureuser'

@description('Specifies the SSH RSA public key for the Linux nodes. Empty omits the linuxProfile (emulator-friendly).')
param sshPublicKey string = ''

@description('Specifies whether to install the Managed Gateway API (ingressProfile.gatewayAPI).')
param gatewayApiEnabled bool = true

@description('Specifies whether the OIDC issuer is enabled.')
param oidcIssuerProfileEnabled bool = true

@description('Specifies whether Microsoft Entra Workload ID is enabled.')
param workloadIdentityEnabled bool = true

@description('Specifies whether the Azure Key Vault Provider for Secrets Store CSI Driver addon is enabled.')
param azureKeyvaultSecretsProviderEnabled bool = true

@description('Specifies whether the Secrets Store CSI Driver rotates secrets.')
param enableSecretRotation bool = false

@description('Specifies whether the Kubernetes Event-Driven Autoscaler (KEDA) is enabled.')
param kedaEnabled bool = false

@description('Specifies whether the Vertical Pod Autoscaler is enabled.')
param verticalPodAutoscalerEnabled bool = false

@description('Specifies whether to enable the Azure Blob CSI Driver.')
param blobCSIDriverEnabled bool = true

@description('Specifies whether to enable the Azure Disk CSI Driver.')
param diskCSIDriverEnabled bool = true

@description('Specifies whether to enable the Azure File CSI Driver.')
param fileCSIDriverEnabled bool = true

@description('Specifies whether to enable the Snapshot Controller.')
param snapshotControllerEnabled bool = true

@description('Specifies whether Kubernetes Role-Based Access Control is enabled.')
param enableRBAC bool = true

@description('Specifies whether to enable managed AAD integration. When false the aadProfile is omitted.')
param aadProfileManaged bool = true

@description('Specifies whether to enable Azure RBAC for Kubernetes authorization.')
param aadProfileEnableAzureRBAC bool = true

@description('Specifies the AAD group object IDs that will have the admin role of the cluster.')
param aadProfileAdminGroupObjectIDs array = []

@description('Specifies the tenant id of the Azure Active Directory used by the AKS cluster for authentication.')
param aadProfileTenantId string = subscription().tenantId

@description('Specifies the upgrade channel for auto upgrade.')
@allowed([
  'rapid'
  'stable'
  'patch'
  'node-image'
  'none'
])
param upgradeChannel string = 'stable'

@description('Specifies the node OS upgrade channel.')
@allowed([
  'NodeImage'
  'None'
  'SecurityPatch'
  'Unmanaged'
])
param nodeOSUpgradeChannel string = 'Unmanaged'

@description('Specifies the scan interval of the auto-scaler of the AKS cluster.')
param autoScalerProfileScanInterval string = '10s'

@description('Specifies the scale down delay after add of the auto-scaler of the AKS cluster.')
param autoScalerProfileScaleDownDelayAfterAdd string = '10m'

@description('Specifies the scale down delay after delete of the auto-scaler of the AKS cluster.')
param autoScalerProfileScaleDownDelayAfterDelete string = '20s'

@description('Specifies the scale down delay after failure of the auto-scaler of the AKS cluster.')
param autoScalerProfileScaleDownDelayAfterFailure string = '3m'

@description('Specifies the scale down unneeded time of the auto-scaler of the AKS cluster.')
param autoScalerProfileScaleDownUnneededTime string = '10m'

@description('Specifies the scale down unready time of the auto-scaler of the AKS cluster.')
param autoScalerProfileScaleDownUnreadyTime string = '20m'

@description('Specifies the utilization threshold of the auto-scaler of the AKS cluster.')
param autoScalerProfileUtilizationThreshold string = '0.5'

@description('Specifies the max graceful termination time interval in seconds for the auto-scaler of the AKS cluster.')
param autoScalerProfileMaxGracefulTerminationSec string = '600'

@description('Specifies the type of node pool expander used in scale up.')
@allowed([
  'least-waste'
  'most-pods'
  'priority'
  'random'
])
param autoScalerProfileExpander string = 'random'

@description('Specifies the resource id of the Log Analytics workspace.')
param workspaceId string

@description('Specifies the object id of a Microsoft Entra ID user to grant the AKS RBAC Cluster Admin role on the cluster. Empty skips the assignment.')
param userId string = ''

// Variables
var diagnosticSettingsName = 'diagnosticSettings'
var logCategories = [
  'kube-apiserver'
  'kube-audit'
  'kube-audit-admin'
  'kube-controller-manager'
  'kube-scheduler'
  'cluster-autoscaler'
  'cloud-controller-manager'
  'guard'
  'csi-azuredisk-controller'
  'csi-azurefile-controller'
  'csi-snapshot-controller'
]
var metricCategories = [
  'AllMetrics'
]
var logs = [
  for category in logCategories: {
    category: category
    enabled: true
    retentionPolicy: {
      enabled: true
      days: 0
    }
  }
]
var metrics = [
  for category in metricCategories: {
    category: category
    enabled: true
    retentionPolicy: {
      enabled: true
      days: 0
    }
  }
]

// Resources
resource managedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2024-11-30' existing = {
  name: managedIdentityName
}

resource virtualNetwork 'Microsoft.Network/virtualNetworks@2024-05-01' existing = {
  name: virtualNetworkName
}

resource systemSubnet 'Microsoft.Network/virtualNetworks/subnets@2024-05-01' existing = {
  parent: virtualNetwork
  name: systemSubnetName
}

resource aksCluster 'Microsoft.ContainerService/managedClusters@2026-04-02-preview' = {
  name: clusterName
  location: location
  tags: tags
  sku: {
    name: 'Base'
    tier: skuTier
  }
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${managedIdentity.id}': {}
    }
  }
  properties: {
    kubernetesVersion: empty(kubernetesVersion) ? null : kubernetesVersion
    dnsPrefix: dnsPrefix
    enableRBAC: enableRBAC
    agentPoolProfiles: [
      {
        name: toLower(systemAgentPoolName)
        mode: 'System'
        count: systemAgentPoolAgentCount
        vmSize: systemAgentPoolVmSize
        vnetSubnetID: systemSubnet.id
        maxPods: systemAgentPoolMaxPods
        osDiskSizeGB: systemAgentPoolOsDiskSizeGB
        osDiskType: systemAgentPoolOsDiskType
        osType: 'Linux'
        osSKU: systemAgentPoolOsSKU
        enableAutoScaling: systemAgentPoolEnableAutoScaling
        minCount: systemAgentPoolEnableAutoScaling ? systemAgentPoolMinCount : null
        maxCount: systemAgentPoolEnableAutoScaling ? systemAgentPoolMaxCount : null
        availabilityZones: empty(systemAgentPoolAvailabilityZones) ? null : systemAgentPoolAvailabilityZones
        nodeLabels: systemAgentPoolNodeLabels
        nodeTaints: systemAgentPoolNodeTaints
        type: 'VirtualMachineScaleSets'
      }
    ]
    linuxProfile: empty(sshPublicKey)
      ? null
      : {
          adminUsername: adminUsername
          ssh: {
            publicKeys: [
              {
                keyData: sshPublicKey
              }
            ]
          }
        }
    addonProfiles: {
      omsagent: {
        enabled: true
        config: {
          logAnalyticsWorkspaceResourceID: workspaceId
        }
      }
      azureKeyvaultSecretsProvider: {
        enabled: azureKeyvaultSecretsProviderEnabled
        config: {
          enableSecretRotation: string(enableSecretRotation)
        }
      }
    }
    oidcIssuerProfile: {
      enabled: oidcIssuerProfileEnabled
    }
    ingressProfile: {
      gatewayAPI: {
        installation: gatewayApiEnabled ? 'Standard' : 'Disabled'
      }
    }
    networkProfile: {
      networkPlugin: networkPlugin
      networkPluginMode: empty(networkPluginMode) ? null : networkPluginMode
      networkPolicy: networkPolicy
      networkDataplane: networkDataplane
      podCidr: networkPlugin == 'kubenet' || networkPluginMode == 'overlay' ? podCidr : null
      serviceCidr: serviceCidr
      dnsServiceIP: dnsServiceIP
      outboundType: outboundType
      loadBalancerSku: loadBalancerSku
    }
    workloadAutoScalerProfile: {
      keda: {
        enabled: kedaEnabled
      }
      verticalPodAutoscaler: {
        enabled: verticalPodAutoscalerEnabled
      }
    }
    // aadProfile shape mandated by PROMPT.md; omitted entirely when managed AAD is
    // off because ARM rejects managed:false with null legacy app ids.
    aadProfile: aadProfileManaged
      ? {
          clientAppID: null
          serverAppID: null
          serverAppSecret: null
          managed: aadProfileManaged
          enableAzureRBAC: aadProfileEnableAzureRBAC
          adminGroupObjectIDs: aadProfileAdminGroupObjectIDs
          tenantID: aadProfileTenantId
        }
      : null
    autoUpgradeProfile: {
      upgradeChannel: upgradeChannel
      nodeOSUpgradeChannel: nodeOSUpgradeChannel
    }
    autoScalerProfile: {
      'scan-interval': autoScalerProfileScanInterval
      'scale-down-delay-after-add': autoScalerProfileScaleDownDelayAfterAdd
      'scale-down-delay-after-delete': autoScalerProfileScaleDownDelayAfterDelete
      'scale-down-delay-after-failure': autoScalerProfileScaleDownDelayAfterFailure
      'scale-down-unneeded-time': autoScalerProfileScaleDownUnneededTime
      'scale-down-unready-time': autoScalerProfileScaleDownUnreadyTime
      'scale-down-utilization-threshold': autoScalerProfileUtilizationThreshold
      'max-graceful-termination-sec': autoScalerProfileMaxGracefulTerminationSec
      expander: autoScalerProfileExpander
    }
    securityProfile: {
      workloadIdentity: {
        enabled: workloadIdentityEnabled
      }
    }
    storageProfile: {
      blobCSIDriver: {
        enabled: blobCSIDriverEnabled
      }
      diskCSIDriver: {
        enabled: diskCSIDriverEnabled
      }
      fileCSIDriver: {
        enabled: fileCSIDriverEnabled
      }
      snapshotController: {
        enabled: snapshotControllerEnabled
      }
    }
  }
}

// Role Definitions
resource aksRbacClusterAdminRoleDefinition 'Microsoft.Authorization/roleDefinitions@2022-04-01' existing = {
  name: 'b1ff04bb-8a4e-4dc4-8eb5-8693973ce19b'
  scope: subscription()
}

// Grants the deploying user cluster-admin over the Kubernetes API when Azure RBAC
// is enabled — required for the kubectl validation in deploy.sh on real Azure.
resource aksRbacClusterAdminRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(userId)) {
  name: guid(aksCluster.id, aksRbacClusterAdminRoleDefinition.id, userId)
  scope: aksCluster
  properties: {
    roleDefinitionId: aksRbacClusterAdminRoleDefinition.id
    principalType: 'User'
    principalId: userId
  }
}

// Diagnostic Settings
resource diagnosticSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: diagnosticSettingsName
  scope: aksCluster
  properties: {
    workspaceId: workspaceId
    logs: logs
    metrics: metrics
  }
}

// Outputs
output clusterId string = aksCluster.id
output clusterName string = aksCluster.name
output nodeResourceGroup string = aksCluster.properties.nodeResourceGroup
output oidcIssuerUrl string = oidcIssuerProfileEnabled ? aksCluster.properties.oidcIssuerProfile.issuerURL : ''
output azureKeyvaultSecretsProviderIdentityObjectId string = azureKeyvaultSecretsProviderEnabled
  ? aksCluster.properties.addonProfiles.azureKeyvaultSecretsProvider.identity.objectId
  : ''
