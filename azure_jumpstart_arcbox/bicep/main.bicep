@description('RSA public key used for securing SSH access to ArcBox resources. This parameter is only needed when deploying the DataOps or DevOps flavors.')
@secure()
param sshRSAPublicKey string = ''

@description('Your Microsoft Entra tenant Id')
param tenantId string = tenant().tenantId

@description('Username for Windows account')
param windowsAdminUsername string

@description('Password for Windows account. Password must have 3 of the following: 1 lower case character, 1 upper case character, 1 number, and 1 special character. The value must be between 12 and 123 characters long')
@minLength(12)
@maxLength(123)
@secure()
param windowsAdminPassword string  = newGuid()

@description('Enable automatic logon into ArcBox Virtual Machine')
param vmAutologon bool = true

@description('Override default RDP port using this parameter. Default is 3389. No changes will be made to the client VM.')
param rdpPort string = '3389'

@description('Name for your log analytics workspace')
param logAnalyticsWorkspaceName string = 'ArcBox-la'

@description('The flavor of ArcBox you want to deploy. Valid values are: \'Full\', \'ITPro\', \'DevOps\', \'DataOps\'')
@allowed([
  'ITPro'
  'DevOps'
  'DataOps'
])
param flavor string = 'ITPro'

@description('SQL Server edition to deploy. Valid values are: \'Developer\', \'Standard\', \'Enterprise\'')
@allowed([
  'Developer'
  'Standard'
  'Enterprise'
])
param sqlServerEdition string = 'Developer'

@description('Target GitHub account')
param githubAccount string = 'SQLLord'

@description('Target GitHub branch')
param githubBranch string = 'master'

@description('Choice to deploy Bastion to connect to the client VM')
param deployBastion bool = false

@description('Bastion host Sku name. The Developer SKU is currently supported in a limited number of regions: https://learn.microsoft.com/azure/bastion/quickstart-developer-sku')
@allowed([
  'Basic'
  'Standard'
  'Developer'
])
param bastionSku string = 'Basic'

@description('User github account where they have forked https://github.com/Azure/jumpstart-apps')
param githubUser string = 'Azure'

@description('Active directory domain services domain name')
param addsDomainName string = 'jumpstart.local'

@description('Random GUID for cluster names')
param guid string = substring(newGuid(),0,4)

@description('Azure location to deploy all resources')
param location string = resourceGroup().location

@description('The custom location RPO ID. This parameter is only needed when deploying the DataOps flavor.')
param customLocationRPOID string = newGuid()

@description('Use this parameter to enable or disable debug mode for the automation scripts on the client VM, effectively configuring PowerShell ErrorActionPreference to Break. Intended for use when troubleshooting automation scripts. Default is false.')
param debugEnabled bool = false

@description('Tags to assign for all ArcBox resources')
param resourceTags object = {
  Solution: 'jumpstart_arcbox_${toLower(flavor)}'
}

@description('Name of the NAT Gateway')
param natGatewayName string = '${namingPrefix}-NatGateway'

@maxLength(7)
@description('The naming prefix for the nested virtual machines and all Azure resources deployed. The maximum length for the naming prefix is 7 characters,example: `ArcBox-Win2k19`')
param namingPrefix string = 'ArcBox'

@description('Optional. Globally unique name for the Key Vault (3-24 alphanumerics/hyphens). Leave empty to auto-generate a unique name from the naming prefix, resource group and deployment time.')
@maxLength(24)
param keyVaultName string = ''

@description('Size of the ArcBox client VM (v5 or newer D/E-series x64 sizes with 8+ vCPUs and 32+ GB). Leave empty for the flavor default (Standard_D4s_v7 for DevOps, Standard_D8s_v7 otherwise).')
@allowed([
  ''
  'Standard_D8_v5'
  'Standard_D16_v5'
  'Standard_D32_v5'
  'Standard_D48_v5'
  'Standard_D64_v5'
  'Standard_D8ads_v5'
  'Standard_D16ads_v5'
  'Standard_D32ads_v5'
  'Standard_D48ads_v5'
  'Standard_D64ads_v5'
  'Standard_D8as_v5'
  'Standard_D16as_v5'
  'Standard_D32as_v5'
  'Standard_D48as_v5'
  'Standard_D64as_v5'
  'Standard_D8d_v5'
  'Standard_D16d_v5'
  'Standard_D32d_v5'
  'Standard_D48d_v5'
  'Standard_D64d_v5'
  'Standard_D8ds_v5'
  'Standard_D16ds_v5'
  'Standard_D32ds_v5'
  'Standard_D48ds_v5'
  'Standard_D64ds_v5'
  'Standard_D16lds_v5'
  'Standard_D32lds_v5'
  'Standard_D48lds_v5'
  'Standard_D64lds_v5'
  'Standard_D16ls_v5'
  'Standard_D32ls_v5'
  'Standard_D48ls_v5'
  'Standard_D64ls_v5'
  'Standard_D8s_v5'
  'Standard_D16s_v5'
  'Standard_D32s_v5'
  'Standard_D48s_v5'
  'Standard_D64s_v5'
  'Standard_E8_v5'
  'Standard_E16_v5'
  'Standard_E20_v5'
  'Standard_E32_v5'
  'Standard_E48_v5'
  'Standard_E64_v5'
  'Standard_E8ads_v5'
  'Standard_E16ads_v5'
  'Standard_E20ads_v5'
  'Standard_E32ads_v5'
  'Standard_E48ads_v5'
  'Standard_E64ads_v5'
  'Standard_E8as_v5'
  'Standard_E16as_v5'
  'Standard_E20as_v5'
  'Standard_E32as_v5'
  'Standard_E48as_v5'
  'Standard_E64as_v5'
  'Standard_E8bds_v5'
  'Standard_E16bds_v5'
  'Standard_E32bds_v5'
  'Standard_E48bds_v5'
  'Standard_E64bds_v5'
  'Standard_E8bs_v5'
  'Standard_E16bs_v5'
  'Standard_E32bs_v5'
  'Standard_E48bs_v5'
  'Standard_E64bs_v5'
  'Standard_E8d_v5'
  'Standard_E16d_v5'
  'Standard_E20d_v5'
  'Standard_E32d_v5'
  'Standard_E48d_v5'
  'Standard_E64d_v5'
  'Standard_E8ds_v5'
  'Standard_E16ds_v5'
  'Standard_E20ds_v5'
  'Standard_E32ds_v5'
  'Standard_E48ds_v5'
  'Standard_E64ds_v5'
  'Standard_E8s_v5'
  'Standard_E16s_v5'
  'Standard_E20s_v5'
  'Standard_E32s_v5'
  'Standard_E48s_v5'
  'Standard_E64s_v5'
  'Standard_D8ads_v6'
  'Standard_D16ads_v6'
  'Standard_D32ads_v6'
  'Standard_D48ads_v6'
  'Standard_D64ads_v6'
  'Standard_D16alds_v6'
  'Standard_D32alds_v6'
  'Standard_D48alds_v6'
  'Standard_D64alds_v6'
  'Standard_D16als_v6'
  'Standard_D32als_v6'
  'Standard_D48als_v6'
  'Standard_D64als_v6'
  'Standard_D8as_v6'
  'Standard_D16as_v6'
  'Standard_D32as_v6'
  'Standard_D48as_v6'
  'Standard_D64as_v6'
  'Standard_D8ds_v6'
  'Standard_D16ds_v6'
  'Standard_D32ds_v6'
  'Standard_D48ds_v6'
  'Standard_D64ds_v6'
  'Standard_D16lds_v6'
  'Standard_D32lds_v6'
  'Standard_D48lds_v6'
  'Standard_D64lds_v6'
  'Standard_D16ls_v6'
  'Standard_D32ls_v6'
  'Standard_D48ls_v6'
  'Standard_D64ls_v6'
  'Standard_D8s_v6'
  'Standard_D16s_v6'
  'Standard_D32s_v6'
  'Standard_D48s_v6'
  'Standard_D64s_v6'
  'Standard_E8ads_v6'
  'Standard_E16ads_v6'
  'Standard_E20ads_v6'
  'Standard_E32ads_v6'
  'Standard_E48ads_v6'
  'Standard_E64ads_v6'
  'Standard_E8as_v6'
  'Standard_E16as_v6'
  'Standard_E20as_v6'
  'Standard_E32as_v6'
  'Standard_E48as_v6'
  'Standard_E64as_v6'
  'Standard_E8ds_v6'
  'Standard_E16ds_v6'
  'Standard_E20ds_v6'
  'Standard_E32ds_v6'
  'Standard_E48ds_v6'
  'Standard_E64ds_v6'
  'Standard_E8s_v6'
  'Standard_E16s_v6'
  'Standard_E20s_v6'
  'Standard_E32s_v6'
  'Standard_E48s_v6'
  'Standard_E64s_v6'
  'Standard_D8ads_v7'
  'Standard_D16ads_v7'
  'Standard_D32ads_v7'
  'Standard_D48ads_v7'
  'Standard_D64ads_v7'
  'Standard_D16alds_v7'
  'Standard_D32alds_v7'
  'Standard_D48alds_v7'
  'Standard_D64alds_v7'
  'Standard_D16als_v7'
  'Standard_D32als_v7'
  'Standard_D48als_v7'
  'Standard_D64als_v7'
  'Standard_D8as_v7'
  'Standard_D16as_v7'
  'Standard_D32as_v7'
  'Standard_D48as_v7'
  'Standard_D64as_v7'
  'Standard_D8ds_v7'
  'Standard_D16ds_v7'
  'Standard_D32ds_v7'
  'Standard_D48ds_v7'
  'Standard_D64ds_v7'
  'Standard_D16lds_v7'
  'Standard_D32lds_v7'
  'Standard_D48lds_v7'
  'Standard_D64lds_v7'
  'Standard_D16ls_v7'
  'Standard_D32ls_v7'
  'Standard_D48ls_v7'
  'Standard_D64ls_v7'
  'Standard_D8s_v7'
  'Standard_D16s_v7'
  'Standard_D32s_v7'
  'Standard_D48s_v7'
  'Standard_D64s_v7'
  'Standard_E8ads_v7'
  'Standard_E16ads_v7'
  'Standard_E32ads_v7'
  'Standard_E48ads_v7'
  'Standard_E64ads_v7'
  'Standard_E8as_v7'
  'Standard_E16as_v7'
  'Standard_E32as_v7'
  'Standard_E48as_v7'
  'Standard_E64as_v7'
  'Standard_E8ds_v7'
  'Standard_E16ds_v7'
  'Standard_E20ds_v7'
  'Standard_E32ds_v7'
  'Standard_E48ds_v7'
  'Standard_E64ds_v7'
  'Standard_E8s_v7'
  'Standard_E16s_v7'
  'Standard_E20s_v7'
  'Standard_E32s_v7'
  'Standard_E48s_v7'
  'Standard_E64s_v7'
])
param clientVmSize string = ''

@description('Deploy a NAT Gateway for outbound internet access (required where policy blocks default outbound access). Always deployed with Bastion or the DevOps/DataOps flavors.')
param deployNatGateway bool = false

@description('Optional. Storage account holding the nested VM VHD images (private; accessed with the client VM managed identity). Leave empty to use the public Jumpstart storage account.')
param vhdStorageAccountName string = 'arcboxfilesdonotdelete'

@description('Resource group of the VHD storage account (same subscription as the deployment)')
param vhdStorageAccountResourceGroup string = 'Arcbox'

@description('Blob container holding the nested VM VHD images')
param vhdContainerName string = 'arcboxvhds'

@description('Do not set. Seeds the auto-generated Key Vault name so each deployment gets a unique, never-before-used name.')
param deploymentTimestamp string = utcNow()

param autoShutdownEnabled bool = true
param autoShutdownTime string = '1800' // The time for auto-shutdown in HHmm format (24-hour clock)
param autoShutdownTimezone string = 'UTC' // Timezone for the auto-shutdown
param autoShutdownEmailRecipient string = ''

@description('Option to enable spot pricing for the ArcBox Client VM')
param enableAzureSpotPricing bool = false

@description('The availability zone for the Virtual Machine, public IP, and data disk for the ArcBox client VM')
@allowed([
  '1'
  '2'
  '3'
])
param zones string = '1'

@secure()
param registryPassword string = newGuid()

var resolvedKeyVaultName = empty(keyVaultName) ? toLower('${namingPrefix}${uniqueString(subscription().id, resourceGroup().id, deploymentTimestamp)}') : toLower(keyVaultName)

var templateBaseUrl = 'https://raw.githubusercontent.com/${githubAccount}/arc_jumpstart_arcbox/${githubBranch}/azure_jumpstart_arcbox/'
var aksArcDataClusterName = '${namingPrefix}-AKS-Data-${guid}'
var aksDrArcDataClusterName = '${namingPrefix}-AKS-DR-Data-${guid}'
var k3sArcDataClusterName = '${namingPrefix}-K3s-Data-${guid}'
var k3sArcClusterName = '${namingPrefix}-K3s-${guid}'
var k3sClusterNodesCount = 3 // Number of nodes to deploy in the K3s cluster
var customerUsageAttributionDeploymentName = (flavor == 'DevOps' ? '390d1642-349e-43c5-845e-8c7cc0972f22' : flavor == 'DataOps' ? 'a8caf3c1-0980-4e23-8c52-27e5d424dbbd' : 'c4a26bed-72cb-415d-91a3-e2577c7c92f5')

module ubuntuRancherK3sDataSvcDeployment 'kubernetes/ubuntuRancher.bicep' = if (flavor == 'DevOps' || flavor == 'DataOps') {
  name: 'ubuntuRancherK3sDataSvcDeployment'
  params: {
    sshRSAPublicKey: sshRSAPublicKey
    stagingStorageAccountName: toLower(stagingStorageAccountDeployment.outputs.storageAccountName)
    logAnalyticsWorkspace: logAnalyticsWorkspaceName
    templateBaseUrl: templateBaseUrl
    subnetId: mgmtArtifactsAndPolicyDeployment.outputs.subnetId
    azureLocation: location
    vmName : k3sArcDataClusterName
    storageContainerName: toLower(k3sArcDataClusterName)
    flavor: flavor
    namingPrefix: namingPrefix
  }
}

module ubuntuRancherK3sDataSvcNodesDeployment 'kubernetes/ubuntuRancherNodes.bicep' = [for i in range(0, k3sClusterNodesCount): if (flavor == 'DataOps' || flavor == 'DevOps') {
  name: 'ubuntuRancherK3sDataSvcNodesDeployment-${i}'
  params: {
    sshRSAPublicKey: sshRSAPublicKey
    stagingStorageAccountName: toLower(stagingStorageAccountDeployment.outputs.storageAccountName)
    logAnalyticsWorkspace: logAnalyticsWorkspaceName
    templateBaseUrl: templateBaseUrl
    subnetId: mgmtArtifactsAndPolicyDeployment.outputs.subnetId
    azureLocation: location
    flavor: flavor
    vmName : '${k3sArcDataClusterName}-Node-0${i}'
    storageContainerName: toLower(k3sArcDataClusterName)
    namingPrefix: namingPrefix
  }
  dependsOn: [
    ubuntuRancherK3sDataSvcDeployment
  ]
}]

module ubuntuRancherK3sDeployment 'kubernetes/ubuntuRancher.bicep' = if (flavor == 'DevOps') {
  name: 'ubuntuRancherK3sDeployment'
  params: {
    sshRSAPublicKey: sshRSAPublicKey
    stagingStorageAccountName: toLower(stagingStorageAccountDeployment.outputs.storageAccountName)
    logAnalyticsWorkspace: logAnalyticsWorkspaceName
    templateBaseUrl: templateBaseUrl
    subnetId: mgmtArtifactsAndPolicyDeployment.outputs.subnetId
    azureLocation: location
    vmName : k3sArcClusterName
    storageContainerName: toLower(k3sArcClusterName)
    flavor: flavor
    namingPrefix: namingPrefix
  }
}

module ubuntuRancherK3sNodesDeployment 'kubernetes/ubuntuRancherNodes.bicep' = [for i in range(0, k3sClusterNodesCount): if (flavor == 'DevOps') {
  name: 'ubuntuRancherK3sNodesDeployment-${i}'
  params: {
    sshRSAPublicKey: sshRSAPublicKey
    stagingStorageAccountName: toLower(stagingStorageAccountDeployment.outputs.storageAccountName)
    logAnalyticsWorkspace: logAnalyticsWorkspaceName
    templateBaseUrl: templateBaseUrl
    subnetId: mgmtArtifactsAndPolicyDeployment.outputs.subnetId
    azureLocation: location
    flavor: flavor
    vmName : '${k3sArcClusterName}-Node-0${i}'
    storageContainerName: toLower(k3sArcClusterName)
    namingPrefix: namingPrefix
  }
  dependsOn: [
    ubuntuRancherK3sDeployment
  ]
}]

module clientVmDeployment 'clientVm/clientVm.bicep' = {
  name: 'clientVmDeployment'
  params: {
    keyVaultName: resolvedKeyVaultName
    vhdStorageAccountName: vhdStorageAccountName
    clientVmSize: clientVmSize
    vhdStorageAccountResourceGroup: vhdStorageAccountResourceGroup
    vhdContainerName: vhdContainerName
    windowsAdminUsername: windowsAdminUsername
    windowsAdminPassword: windowsAdminPassword
    tenantId: tenantId
    workspaceName: logAnalyticsWorkspaceName
    stagingStorageAccountName: toLower(stagingStorageAccountDeployment.outputs.storageAccountName)
    templateBaseUrl: templateBaseUrl
    flavor: flavor
    subnetId: mgmtArtifactsAndPolicyDeployment.outputs.subnetId
    deployBastion: deployBastion
    githubBranch: githubBranch
    githubUser: githubUser
    location: location
    k3sArcDataClusterName : k3sArcDataClusterName
    k3sArcClusterName : k3sArcClusterName
    aksArcClusterName : aksArcDataClusterName
    aksdrArcClusterName : aksDrArcDataClusterName
    vmAutologon: vmAutologon
    rdpPort: rdpPort
    addsDomainName: addsDomainName
    customLocationRPOID: customLocationRPOID
    namingPrefix: namingPrefix
    debugEnabled: debugEnabled
    autoShutdownEnabled: autoShutdownEnabled
    autoShutdownTime: autoShutdownTime
    autoShutdownTimezone: autoShutdownTimezone
    autoShutdownEmailRecipient: empty(autoShutdownEmailRecipient) ? null : autoShutdownEmailRecipient
    sqlServerEdition: sqlServerEdition
    zones: zones
    enableAzureSpotPricing: enableAzureSpotPricing
  }
  dependsOn: [
    updateVNetDNSServers
    ubuntuRancherK3sDataSvcDeployment
    ubuntuRancherK3sDeployment
  ]
}

module stagingStorageAccountDeployment 'mgmt/mgmtStagingStorage.bicep' = {
  name: 'stagingStorageAccountDeployment'
  params: {
    location: location
    namingPrefix: namingPrefix
  }
}

module mgmtArtifactsAndPolicyDeployment 'mgmt/mgmtArtifacts.bicep' = {
  name: 'mgmtArtifactsAndPolicyDeployment'
  params: {
    workspaceName: logAnalyticsWorkspaceName
    flavor: flavor
    deployBastion: deployBastion
    bastionSku: bastionSku
    location: location
    resourceTags: resourceTags
    namingPrefix: namingPrefix
    windowsAdminPassword: windowsAdminPassword
    registryPassword: registryPassword
    natGatewayName: natGatewayName
    deployNatGateway: deployNatGateway
    keyVaultName: resolvedKeyVaultName
  }
}

module addsVmDeployment 'mgmt/addsVm.bicep' = if (flavor == 'DataOps'){
  name: 'addsVmDeployment'
  params: {
    keyVaultName: resolvedKeyVaultName
    windowsAdminUsername : windowsAdminUsername
    windowsAdminPassword : windowsAdminPassword
    addsDomainName: addsDomainName
    deployBastion: deployBastion
    templateBaseUrl: templateBaseUrl
    azureLocation: location
    namingPrefix: namingPrefix
  }
  dependsOn:[
    mgmtArtifactsAndPolicyDeployment
  ]
}

module updateVNetDNSServers 'mgmt/mgmtArtifacts.bicep' = if (flavor == 'DataOps'){
  name: 'updateVNetDNSServers'
  params: {
    workspaceName: logAnalyticsWorkspaceName
    flavor: flavor
    deployBastion: deployBastion
    location: location
    dnsServers: [
    '10.16.2.100'
    '168.63.129.16'
    ]
    namingPrefix: namingPrefix
    keyVaultName: resolvedKeyVaultName
    natGatewayName: natGatewayName
    deployNatGateway: deployNatGateway
  }
  dependsOn: [
    addsVmDeployment
    mgmtArtifactsAndPolicyDeployment
  ]
}

module aksDeployment 'kubernetes/aks.bicep' = if (flavor == 'DataOps') {
  name: 'aksDeployment'
  params: {
    sshRSAPublicKey: sshRSAPublicKey
    location: location
    aksClusterName : aksArcDataClusterName
    drClusterName : aksDrArcDataClusterName
    namingPrefix: namingPrefix
  }
  dependsOn: [
    updateVNetDNSServers
    stagingStorageAccountDeployment
    mgmtArtifactsAndPolicyDeployment
  ]
}

// Bastion is deployed last: it is slow to provision and slow to delete, so a failed or cancelled test run is cheaper to clean up
module bastionDeployment 'mgmt/bastion.bicep' = if (deployBastion) {
  name: 'bastionDeployment'
  params: {
    bastionSku: bastionSku
    vnetId: mgmtArtifactsAndPolicyDeployment.outputs.vnetId
    location: location
    namingPrefix: namingPrefix
  }
  dependsOn: [
    clientVmDeployment
    aksDeployment
  ]
}

module customerUsageAttribution 'mgmt/customerUsageAttribution.bicep' = {
  name: 'pid-${customerUsageAttributionDeploymentName}'
  params: {
  }
}

output clientVmLogonUserName string = flavor == 'DataOps' ? '${windowsAdminUsername}@${addsDomainName}' : ''
