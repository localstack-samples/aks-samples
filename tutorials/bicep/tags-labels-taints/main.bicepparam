using './main.bicep'

param prefix = 'local'
param suffix = 'test'
param tags = {
  env: 'test'
  iac: 'bicep'
}
param systemNodePoolNodeLabels = {
  team: 'platform'
}
param systemNodePoolNodeCount = 1
param systemNodePoolMinCount = 1
param systemNodePoolMaxCount = 3
param userNodePoolName = 'upool1'
param userNodePoolNodeLabels = {
  workload: 'batch'
}
param userNodePoolNodeTaints = [
  'dedicated=batch:NoSchedule'
]
param userNodePoolTags = {
  costcenter: '1234'
}
param userNodePoolNodeCount = 1
param userNodePoolMinCount = 1
param userNodePoolMaxCount = 3
// Explicit, globally unique vault name: the derived defaults collided twice with
// names already reserved elsewhere (Key Vault names are global across Azure).
param keyVaultName = 'local-kv-ciao-local'
param gatewayApiEnabled = true
param oidcIssuerProfileEnabled = true
param workloadIdentityEnabled = true
param azureKeyvaultSecretsProviderEnabled = true
param verticalPodAutoscalerEnabled = true
param blobCSIDriverEnabled = true
param diskCSIDriverEnabled = true
param fileCSIDriverEnabled = true
param enableRBAC = true
param aadProfileManaged = true
param aadProfileEnableAzureRBAC = true
param aadProfileAdminGroupObjectIDs = []
