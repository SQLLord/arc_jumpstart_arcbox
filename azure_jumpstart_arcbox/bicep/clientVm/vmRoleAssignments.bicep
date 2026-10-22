@description('Principal Id of the ArcBox client VM managed identity')
param principalId string

// The principal Id is part of each assignment name, so a recreated client VM (new identity) gets new
// assignments instead of failing with RoleAssignmentUpdateNotPermitted on the previous VM's assignments.
// Redeploying with the same VM keeps the same names and is a no-op.
var roles = {
  KeyVaultAdministrator: '00482a5a-887f-4fb3-b363-3b7fe8e74483'
  Owner: '8e3af657-a8ff-443c-a75c-2fe8c4bcb635'
  StorageBlobDataContributor: 'ba92f5b4-2d11-453d-a403-e96b0029c9fe'
}

resource vmRoleAssignments 'Microsoft.Authorization/roleAssignments@2022-04-01' = [for role in items(roles): {
  name: guid(resourceGroup().id, principalId, role.value)
  properties: {
    principalId: principalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', role.value)
    principalType: 'ServicePrincipal'
  }
}]
