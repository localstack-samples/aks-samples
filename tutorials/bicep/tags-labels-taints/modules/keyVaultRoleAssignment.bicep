// Grants the Azure Key Vault Secrets Provider addon identity the Key Vault
// Administrator role on the vault — the declarative equivalent of
// ~/localstack/aks-samples/samples/key-vault-csi-driver/user-assigned-managed-identity/03-create-role-assignment.sh.

// Parameters
@description('Specifies the name of the existing Key Vault.')
param keyVaultName string

@description('Specifies the object id of the principal to grant the Key Vault Administrator role.')
param principalId string

// Resources
resource keyVaultAdministratorRoleDefinition 'Microsoft.Authorization/roleDefinitions@2022-04-01' existing = {
  name: '00482a5a-887f-4fb3-b363-3b7fe8e74483'
  scope: subscription()
}

resource keyVault 'Microsoft.KeyVault/vaults@2024-04-01-preview' existing = {
  name: keyVaultName
}

resource keyVaultAdministratorRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(keyVault.id, keyVaultAdministratorRoleDefinition.id, principalId)
  scope: keyVault
  properties: {
    roleDefinitionId: keyVaultAdministratorRoleDefinition.id
    principalId: principalId
    principalType: 'ServicePrincipal'
  }
}
