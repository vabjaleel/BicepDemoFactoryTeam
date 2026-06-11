// ----------------------------------------------------------------------------
// Network module — VNet + single subnet (Azure Verified Module, pinned)
// ----------------------------------------------------------------------------

@description('Virtual network name.')
param name string

@description('Azure region.')
param location string

@description('VNet address space, e.g. 10.10.0.0/16.')
param addressPrefix string

@description('Subnet name.')
param subnetName string

@description('Subnet address prefix, e.g. 10.10.1.0/24.')
param subnetPrefix string

@description('Resource tags.')
param tags object = {}

module virtualNetwork 'br/public:avm/res/network/virtual-network:0.9.0' = {
  name: 'avm-vnet'
  params: {
    name: name
    location: location
    addressPrefixes: [
      addressPrefix
    ]
    tags: tags
    subnets: [
      {
        name: subnetName
        addressPrefix: subnetPrefix
      }
    ]
  }
}

@description('Resource ID of the virtual network.')
output vnetId string = virtualNetwork.outputs.resourceId

@description('Resource ID of the subnet.')
output subnetResourceId string = virtualNetwork.outputs.subnetResourceIds[0]
