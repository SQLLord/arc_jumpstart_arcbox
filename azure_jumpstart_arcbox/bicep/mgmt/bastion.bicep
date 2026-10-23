@description('Bastion host Sku name')
@allowed([
  'Basic'
  'Standard'
  'Premium'
  'Developer'
])
param bastionSku string = 'Basic'

@description('Resource Id of the ArcBox virtual network')
param vnetId string

@description('Azure Region to deploy the Bastion host')
param location string = resourceGroup().location

@maxLength(7)
@description('The naming prefix for the nested virtual machines and all Azure resources deployed. The maximum length for the naming prefix is 7 characters,example: `ArcBox-Win2k19`')
param namingPrefix string = 'ArcBox'

var bastionName = '${namingPrefix}-Bastion'
var bastionPublicIpAddressName = '${bastionName}-PIP'
var bastionSubnetRef = '${vnetId}/subnets/AzureBastionSubnet'

// Native client support (Windows Remote Desktop app via az network bastion rdp) is only available on Standard and Premium
var enableNativeClient = contains(['Standard', 'Premium'], bastionSku)

resource publicIpAddress 'Microsoft.Network/publicIPAddresses@2024-05-01' = if (bastionSku != 'Developer') {
  name: bastionPublicIpAddressName
  location: location
  properties: {
    publicIPAllocationMethod: 'Static'
    publicIPAddressVersion: 'IPv4'
    idleTimeoutInMinutes: 4
  }
  sku: {
    name: 'Standard'
  }
}

resource bastionHost 'Microsoft.Network/bastionHosts@2024-05-01' = {
  name: bastionName
  location: location
  sku: {
    name: bastionSku
  }
  properties: {
    enableTunneling: enableNativeClient
    virtualNetwork: bastionSku == 'Developer'
      ? {
          id: vnetId
        }
      : null
    ipConfigurations: bastionSku != 'Developer'
      ? [
          {
            name: 'IpConf'
            properties: {
              publicIPAddress: {
                id: publicIpAddress.id
              }
              subnet: {
                id: bastionSubnetRef
              }
            }
          }
        ]
      : null
  }
}
