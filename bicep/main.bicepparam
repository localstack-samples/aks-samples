using 'main.bicep'

// The defaults of the cluster scripts. deploy.sh overrides each of them from its environment variables.
param prefix = 'local'
param suffix = 'test'
param identityType = 'SystemAssigned'
param networkOption = 1
param systemNodeCount = 1
param userNodeCount = 1
param nodeVmSize = 'Standard_D4ds_v5'
param osSku = 'AzureLinux'
param osDiskSizeGB = 50
param osDiskType = 'Ephemeral'
param maxPods = 100
param windowsAdminUsername = 'azadmin'

// Read when the parameters are built: deploy.sh exports it, with the scripts' default
param windowsAdminPassword = readEnvironmentVariable('WINDOWS_ADMIN_PASSWORD')
