// Orchestrates the modular AKS stack: Log Analytics, VNet, AKS user-assigned
// identity, ACR, Key Vault, AKS cluster (system pool), user agent pool, and the
// AcrPull / Key Vault Administrator role assignments.

// Parameters
@description('Specifies the name prefix for all the Azure resources.')
@minLength(3)
@maxLength(10)
param prefix string = substring(uniqueString(resourceGroup().id), 0, 4)

@description('Specifies the name suffix for all the Azure resources.')
@minLength(3)
@maxLength(10)
param suffix string = substring(uniqueString(resourceGroup().id), 0, 4)

@description('Specifies the location for all the Azure resources.')
param location string = resourceGroup().location

@description('Specifies the resource tags for all the Azure resources.')
param tags object = {}

@description('Specifies the name of the AKS cluster. Empty derives it from prefix and suffix.')
param aksClusterName string = ''

@description('Specifies the name of the AKS user-assigned managed identity. Empty derives it from prefix and suffix.')
param aksManagedIdentityName string = ''

@description('Specifies the name of the virtual network. Empty derives it from prefix and suffix.')
param virtualNetworkName string = ''

@description('Specifies the name of the Log Analytics workspace. Empty derives it from prefix and suffix.')
param logAnalyticsWorkspaceName string = ''

@description('Specifies the name of the container registry. Empty derives it from prefix and suffix.')
param containerRegistryName string = ''

@description('Specifies the name of the Key Vault. Empty derives it from prefix and suffix.')
param keyVaultName string = ''

@description('Specifies the Kubernetes version. Empty lets the platform pick its default.')
param kubernetesVersion string = ''

@description('Specifies the DNS prefix of the AKS cluster. Empty derives it from the cluster name.')
param dnsPrefix string = ''

@description('Specifies the tier of the managed cluster SKU.')
@allowed([
  'Free'
  'Standard'
  'Premium'
])
param skuTier string = 'Free'

@description('Specifies the VM size for all agent pool nodes.')
param vmSize string = 'Standard_DS2_v2'

@description('Specifies the name of the system agent pool.')
param systemNodePoolName string = 'system'

@description('Specifies the number of nodes in the system agent pool.')
param systemNodePoolNodeCount int = 1

@description('Specifies whether to enable auto-scaling for the system agent pool.')
param systemNodePoolAutoScalingEnabled bool = false

@description('Specifies the minimum number of nodes for auto-scaling of the system agent pool.')
param systemNodePoolMinCount int = 1

@description('Specifies the maximum number of nodes for auto-scaling of the system agent pool.')
param systemNodePoolMaxCount int = 3

@description('Specifies the maximum number of pods per node in the system agent pool.')
param systemNodePoolMaxPods int = 100

@description('Specifies the OS Disk Size in GB for the system agent pool. 0 applies the platform default for the vm size.')
param systemNodePoolOsDiskSizeGB int = 0

@description('Specifies the OS disk type of the system agent pool.')
@allowed([
  'Ephemeral'
  'Managed'
])
param systemNodePoolOsDiskType string = 'Managed'

@description('Specifies the OS SKU used by the system agent pool.')
@allowed([
  'Ubuntu'
  'AzureLinux'
])
param systemNodePoolOsSKU string = 'AzureLinux'

@description('Specifies the availability zones of the system agent pool. Empty deploys without zones.')
param systemNodePoolAvailabilityZones array = []

@description('Specifies the node labels of the system agent pool.')
param systemNodePoolNodeLabels object = {}

@description('Specifies the node taints of the system agent pool (key[=value]:effect strings).')
param systemNodePoolNodeTaints array = []

@description('Specifies the name of the user agent pool.')
param userNodePoolName string = 'upool1'

@description('Specifies the mode of the user agent pool.')
@allowed([
  'System'
  'User'
])
param userNodePoolMode string = 'User'

@description('Specifies the number of nodes in the user agent pool.')
param userNodePoolNodeCount int = 1

@description('Specifies whether to enable auto-scaling for the user agent pool.')
param userNodePoolAutoScalingEnabled bool = false

@description('Specifies the minimum number of nodes for auto-scaling of the user agent pool.')
param userNodePoolMinCount int = 1

@description('Specifies the maximum number of nodes for auto-scaling of the user agent pool.')
param userNodePoolMaxCount int = 3

@description('Specifies the maximum number of pods per node in the user agent pool.')
param userNodePoolMaxPods int = 100

@description('Specifies the OS Disk Size in GB for the user agent pool. 0 applies the platform default for the vm size.')
param userNodePoolOsDiskSizeGB int = 0

@description('Specifies the OS disk type of the user agent pool.')
@allowed([
  'Ephemeral'
  'Managed'
])
param userNodePoolOsDiskType string = 'Managed'

@description('Specifies the OS type of the user agent pool.')
@allowed([
  'Linux'
  'Windows'
])
param userNodePoolOsType string = 'Linux'

@description('Specifies the OS SKU used by the user agent pool.')
@allowed([
  'Ubuntu'
  'AzureLinux'
])
param userNodePoolOsSKU string = 'AzureLinux'

@description('Specifies the availability zones of the user agent pool. Empty deploys without zones.')
param userNodePoolAvailabilityZones array = []

@description('Specifies the node labels of the user agent pool.')
param userNodePoolNodeLabels object = {}

@description('Specifies the node taints of the user agent pool (key[=value]:effect strings).')
param userNodePoolNodeTaints array = []

@description('Specifies the resource tags of the user agent pool.')
param userNodePoolTags object = {}

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

@description('Specifies the outbound (egress) routing method.')
@allowed([
  'loadBalancer'
  'managedNATGateway'
  'userAssignedNATGateway'
  'userDefinedRouting'
])
param outboundType string = 'loadBalancer'

@description('Specifies the sku of the load balancer used by the AKS cluster.')
@allowed([
  'basic'
  'standard'
])
param loadBalancerSku string = 'standard'

@description('Specifies whether to install the Managed Gateway API on the AKS cluster.')
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

@description('Specifies whether to enable managed AAD integration.')
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

@description('Specifies the administrator username of Linux virtual machines.')
param adminUsername string = 'azureuser'

@description('Specifies the SSH RSA public key for the Linux nodes. Empty omits the linuxProfile.')
param sshPublicKey string = ''

@description('Specifies the object id of the deploying user, used for the AKS RBAC Cluster Admin and Key Vault Administrator role assignments. Empty skips them.')
param userId string = ''

@description('Specifies the service tier of the Log Analytics workspace: Free, Standalone, PerNode, PerGB2018.')
@allowed([
  'Free'
  'Standalone'
  'PerNode'
  'PerGB2018'
])
param logAnalyticsWorkspaceSku string = 'PerGB2018'

@description('Specifies the Log Analytics workspace data retention in days.')
param logAnalyticsWorkspaceRetentionInDays int = 60

@description('Specifies the tier of the container registry.')
@allowed([
  'Basic'
  'Standard'
  'Premium'
])
param containerRegistrySku string = 'Basic'

@description('Specifies whether the container registry admin user is enabled.')
param containerRegistryAdminUserEnabled bool = true

@description('Specifies whether registry-wide pull is enabled from unauthenticated clients (Premium only).')
param containerRegistryAnonymousPullEnabled bool = false

@description('Specifies whether a single data endpoint is enabled per region for serving data (Premium only).')
param containerRegistryDataEndpointEnabled bool = false

@description('Specifies whether to allow trusted Azure services to access a network restricted registry.')
@allowed([
  'AzureServices'
  'None'
])
param containerRegistryNetworkRuleBypassOptions string = 'AzureServices'

@description('Specifies whether to allow public network access for the container registry.')
@allowed([
  'Disabled'
  'Enabled'
])
param containerRegistryPublicNetworkAccess string = 'Enabled'

@description('Specifies whether zone redundancy is enabled for the container registry (Premium only).')
@allowed([
  'Disabled'
  'Enabled'
])
param containerRegistryZoneRedundancy string = 'Disabled'

@description('Specifies the sku name of the Key Vault.')
@allowed([
  'premium'
  'standard'
])
param keyVaultSkuName string = 'standard'

@description('Specifies the Azure Active Directory tenant ID used for authenticating requests to the Key Vault.')
param keyVaultTenantId string = subscription().tenantId

@description('Specifies whether to allow public network access for the Key Vault.')
@allowed([
  'Disabled'
  'Enabled'
])
param keyVaultPublicNetworkAccess string = 'Enabled'

@description('Specifies the default action when no Key Vault network ACL rules match.')
@allowed([
  'Allow'
  'Deny'
])
param keyVaultNetworkAclsDefaultAction string = 'Allow'

@description('Specifies whether the Key Vault is enabled for deployments.')
param keyVaultEnabledForDeployment bool = true

@description('Specifies whether the Key Vault is enabled for disk encryption.')
param keyVaultEnabledForDiskEncryption bool = true

@description('Specifies whether the Key Vault is enabled for template deployment.')
param keyVaultEnabledForTemplateDeployment bool = true

@description('Specifies whether purge protection is enabled for the Key Vault. The property only accepts true, so false emits null (property omitted).')
param keyVaultEnablePurgeProtection bool = false

@description('Specifies whether RBAC authorization is enabled for the Key Vault data plane.')
param keyVaultEnableRbacAuthorization bool = true

@description('Specifies whether soft delete is enabled for the Key Vault.')
param keyVaultEnableSoftDelete bool = true

@description('Specifies the Key Vault soft delete retention in days.')
param keyVaultSoftDeleteRetentionInDays int = 7

// Variables
var aksClusterNameValue = empty(aksClusterName) ? toLower('${prefix}-aks-${suffix}') : aksClusterName
var aksManagedIdentityNameValue = empty(aksManagedIdentityName)
  ? toLower('${prefix}-aks-identity-${suffix}')
  : aksManagedIdentityName
var virtualNetworkNameValue = empty(virtualNetworkName) ? toLower('${prefix}-vnet-${suffix}') : virtualNetworkName
var logAnalyticsWorkspaceNameValue = empty(logAnalyticsWorkspaceName)
  ? toLower('${prefix}-log-analytics-${suffix}')
  : logAnalyticsWorkspaceName
var containerRegistryNameValue = empty(containerRegistryName) ? toLower('${prefix}acr${suffix}') : containerRegistryName
// '-key-vault-' rather than '-kv-': vault names are globally unique and the
// shorter name was already reserved by a soft-deleted vault in this tenant.
var keyVaultNameValue = empty(keyVaultName) ? toLower('${prefix}-key-vault-${suffix}') : keyVaultName

// Modules
module logAnalyticsWorkspace 'modules/logAnalytics.bicep' = {
  name: 'logAnalyticsDeployment'
  params: {
    workspaceName: logAnalyticsWorkspaceNameValue
    sku: logAnalyticsWorkspaceSku
    retentionInDays: logAnalyticsWorkspaceRetentionInDays
    location: location
    tags: tags
  }
}

module network 'modules/network.bicep' = {
  name: 'networkDeployment'
  params: {
    virtualNetworkName: virtualNetworkNameValue
    virtualNetworkAddressPrefixes: virtualNetworkAddressPrefixes
    systemSubnetName: systemSubnetName
    systemSubnetAddressPrefix: systemSubnetAddressPrefix
    userSubnetName: userSubnetName
    userSubnetAddressPrefix: userSubnetAddressPrefix
    location: location
    tags: tags
  }
}

module aksManagedIdentity 'modules/aksManagedIdentity.bicep' = {
  name: 'aksManagedIdentityDeployment'
  params: {
    managedIdentityName: aksManagedIdentityNameValue
    virtualNetworkName: network.outputs.virtualNetworkName
    location: location
    tags: tags
  }
}

module containerRegistry 'modules/containerRegistry.bicep' = {
  name: 'containerRegistryDeployment'
  params: {
    containerRegistryName: containerRegistryNameValue
    sku: containerRegistrySku
    adminUserEnabled: containerRegistryAdminUserEnabled
    anonymousPullEnabled: containerRegistryAnonymousPullEnabled
    dataEndpointEnabled: containerRegistryDataEndpointEnabled
    networkRuleBypassOptions: containerRegistryNetworkRuleBypassOptions
    publicNetworkAccess: containerRegistryPublicNetworkAccess
    zoneRedundancy: containerRegistryZoneRedundancy
    workspaceId: logAnalyticsWorkspace.outputs.workspaceId
    location: location
    tags: tags
  }
}

module keyVault 'modules/keyVault.bicep' = {
  name: 'keyVaultDeployment'
  params: {
    keyVaultName: keyVaultNameValue
    skuName: keyVaultSkuName
    tenantId: keyVaultTenantId
    publicNetworkAccess: keyVaultPublicNetworkAccess
    networkAclsDefaultAction: keyVaultNetworkAclsDefaultAction
    enabledForDeployment: keyVaultEnabledForDeployment
    enabledForDiskEncryption: keyVaultEnabledForDiskEncryption
    enabledForTemplateDeployment: keyVaultEnabledForTemplateDeployment
    enablePurgeProtection: keyVaultEnablePurgeProtection
    enableRbacAuthorization: keyVaultEnableRbacAuthorization
    enableSoftDelete: keyVaultEnableSoftDelete
    softDeleteRetentionInDays: keyVaultSoftDeleteRetentionInDays
    workspaceId: logAnalyticsWorkspace.outputs.workspaceId
    userObjectId: userId
    location: location
    tags: tags
  }
}

module aksCluster 'modules/aksCluster.bicep' = {
  name: 'aksClusterDeployment'
  params: {
    clusterName: aksClusterNameValue
    dnsPrefix: empty(dnsPrefix) ? toLower(aksClusterNameValue) : dnsPrefix
    skuTier: skuTier
    managedIdentityName: aksManagedIdentity.outputs.managedIdentityName
    virtualNetworkName: network.outputs.virtualNetworkName
    systemSubnetName: systemSubnetName
    workspaceId: logAnalyticsWorkspace.outputs.workspaceId
    kubernetesVersion: kubernetesVersion
    systemAgentPoolName: systemNodePoolName
    systemAgentPoolVmSize: vmSize
    systemAgentPoolAgentCount: systemNodePoolNodeCount
    systemAgentPoolEnableAutoScaling: systemNodePoolAutoScalingEnabled
    systemAgentPoolMinCount: systemNodePoolMinCount
    systemAgentPoolMaxCount: systemNodePoolMaxCount
    systemAgentPoolMaxPods: systemNodePoolMaxPods
    systemAgentPoolOsDiskSizeGB: systemNodePoolOsDiskSizeGB
    systemAgentPoolOsDiskType: systemNodePoolOsDiskType
    systemAgentPoolOsSKU: systemNodePoolOsSKU
    systemAgentPoolAvailabilityZones: systemNodePoolAvailabilityZones
    systemAgentPoolNodeLabels: systemNodePoolNodeLabels
    systemAgentPoolNodeTaints: systemNodePoolNodeTaints
    networkPlugin: networkPlugin
    networkPluginMode: networkPluginMode
    networkPolicy: networkPolicy
    networkDataplane: networkDataplane
    podCidr: podCidr
    serviceCidr: serviceCidr
    dnsServiceIP: dnsServiceIP
    outboundType: outboundType
    loadBalancerSku: loadBalancerSku
    gatewayApiEnabled: gatewayApiEnabled
    oidcIssuerProfileEnabled: oidcIssuerProfileEnabled
    workloadIdentityEnabled: workloadIdentityEnabled
    azureKeyvaultSecretsProviderEnabled: azureKeyvaultSecretsProviderEnabled
    enableSecretRotation: enableSecretRotation
    kedaEnabled: kedaEnabled
    verticalPodAutoscalerEnabled: verticalPodAutoscalerEnabled
    blobCSIDriverEnabled: blobCSIDriverEnabled
    diskCSIDriverEnabled: diskCSIDriverEnabled
    fileCSIDriverEnabled: fileCSIDriverEnabled
    snapshotControllerEnabled: snapshotControllerEnabled
    enableRBAC: enableRBAC
    aadProfileManaged: aadProfileManaged
    aadProfileEnableAzureRBAC: aadProfileEnableAzureRBAC
    aadProfileAdminGroupObjectIDs: aadProfileAdminGroupObjectIDs
    aadProfileTenantId: aadProfileTenantId
    upgradeChannel: upgradeChannel
    nodeOSUpgradeChannel: nodeOSUpgradeChannel
    autoScalerProfileScanInterval: autoScalerProfileScanInterval
    autoScalerProfileScaleDownDelayAfterAdd: autoScalerProfileScaleDownDelayAfterAdd
    autoScalerProfileScaleDownDelayAfterDelete: autoScalerProfileScaleDownDelayAfterDelete
    autoScalerProfileScaleDownDelayAfterFailure: autoScalerProfileScaleDownDelayAfterFailure
    autoScalerProfileScaleDownUnneededTime: autoScalerProfileScaleDownUnneededTime
    autoScalerProfileScaleDownUnreadyTime: autoScalerProfileScaleDownUnreadyTime
    autoScalerProfileUtilizationThreshold: autoScalerProfileUtilizationThreshold
    autoScalerProfileMaxGracefulTerminationSec: autoScalerProfileMaxGracefulTerminationSec
    autoScalerProfileExpander: autoScalerProfileExpander
    adminUsername: adminUsername
    sshPublicKey: sshPublicKey
    userId: userId
    location: location
    tags: tags
  }
}

module userAgentPool 'modules/aksAgentPool.bicep' = {
  name: 'userAgentPoolDeployment'
  params: {
    agentPoolName: userNodePoolName
    clusterName: aksCluster.outputs.clusterName
    virtualNetworkName: network.outputs.virtualNetworkName
    subnetName: userSubnetName
    mode: userNodePoolMode
    vmSize: vmSize
    agentCount: userNodePoolNodeCount
    enableAutoScaling: userNodePoolAutoScalingEnabled
    minCount: userNodePoolMinCount
    maxCount: userNodePoolMaxCount
    maxPods: userNodePoolMaxPods
    osDiskSizeGB: userNodePoolOsDiskSizeGB
    osDiskType: userNodePoolOsDiskType
    osType: userNodePoolOsType
    osSKU: userNodePoolOsSKU
    availabilityZones: userNodePoolAvailabilityZones
    nodeLabels: userNodePoolNodeLabels
    nodeTaints: userNodePoolNodeTaints
    agentPoolTags: userNodePoolTags
  }
}

module kubeletManagedIdentity 'modules/kubeletManagedIdentity.bicep' = {
  name: 'kubeletManagedIdentityDeployment'
  params: {
    clusterName: aksCluster.outputs.clusterName
    containerRegistryName: containerRegistry.outputs.containerRegistryName
  }
}

module keyVaultRoleAssignment 'modules/keyVaultRoleAssignment.bicep' = if (azureKeyvaultSecretsProviderEnabled) {
  name: 'keyVaultRoleAssignmentDeployment'
  params: {
    keyVaultName: keyVault.outputs.keyVaultName
    principalId: aksCluster.outputs.azureKeyvaultSecretsProviderIdentityObjectId
  }
}

// Outputs
output clusterName string = aksCluster.outputs.clusterName
output userNodePoolName string = userAgentPool.outputs.agentPoolName
output acrName string = containerRegistry.outputs.containerRegistryName
output keyVaultName string = keyVault.outputs.keyVaultName
output logAnalyticsWorkspaceName string = logAnalyticsWorkspace.outputs.workspaceName
output managedIdentityName string = aksManagedIdentity.outputs.managedIdentityName
output nodeResourceGroup string = aksCluster.outputs.nodeResourceGroup
output oidcIssuerUrl string = aksCluster.outputs.oidcIssuerUrl
output keyVaultSecretsProviderObjectId string = aksCluster.outputs.azureKeyvaultSecretsProviderIdentityObjectId
