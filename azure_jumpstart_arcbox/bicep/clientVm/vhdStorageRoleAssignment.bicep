@description('Name of the storage account holding the ArcBox nested VM VHD images')
param storageAccountName string

@description('Principal Id of the ArcBox client VM managed identity')
param principalId string

// Storage Blob Data Reader
var roleDefinitionId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '2a2b9908-6ea1-4ae2-8e65-a410df84e7d1')

resource vhdStorageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' existing = {
  name: storageAccountName
}

resource vmRoleAssignment_VhdStorageReader 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(vhdStorageAccount.id, principalId, roleDefinitionId)
  scope: vhdStorageAccount
  properties: {
    principalId: principalId
    roleDefinitionId: roleDefinitionId
    principalType: 'ServicePrincipal'
  }
}
