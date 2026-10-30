// Bastion host and its public IP address, and the diagnostic settings that send their logs and metrics to the
// Log Analytics workspace

@description('Specifies the name of the Bastion host.')
param name string

@description('Specifies the name of the public IP address of the Bastion host.')
param publicIpAddressName string

@description('Specifies the location of the Bastion host and its public IP address.')
param location string = resourceGroup().location

@description('Specifies the SKU of the Bastion host.')
@allowed([
  'Basic'
  'Standard'
])
param sku string = 'Basic'

@description('Specifies the resource id of the AzureBastionSubnet subnet.')
param subnetId string

@description('Specifies the resource id of the Log Analytics workspace.')
param workspaceId string

@description('Specifies the name of the diagnostic settings.')
param diagnosticSettingsName string = 'default'

// Azure Bastion requires a Standard SKU public IP address with a static allocation method
resource publicIpAddress 'Microsoft.Network/publicIPAddresses@2024-05-01' = {
  name: publicIpAddressName
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

resource bastionHost 'Microsoft.Network/bastionHosts@2024-05-01' = {
  name: name
  location: location
  sku: {
    name: sku
  }
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig'
        properties: {
          subnet: {
            id: subnetId
          }
          publicIPAddress: {
            id: publicIpAddress.id
          }
        }
      }
    ]
  }
}

// The DDoS categories only receive data while Azure DDoS Protection mitigates an attack on the address
resource publicIpAddressDiagnosticSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: diagnosticSettingsName
  scope: publicIpAddress
  properties: {
    workspaceId: workspaceId
    logs: [
      {
        category: 'DDoSProtectionNotifications'
        enabled: true
      }
      {
        category: 'DDoSMitigationFlowLogs'
        enabled: true
      }
      {
        category: 'DDoSMitigationReports'
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

resource bastionHostDiagnosticSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: diagnosticSettingsName
  scope: bastionHost
  properties: {
    workspaceId: workspaceId
    logs: [
      {
        category: 'BastionAuditLogs'
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

output id string = bastionHost.id
output publicIpAddressId string = publicIpAddress.id
