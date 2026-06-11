metadata description = 'Deploys a Virtual Network with a single subnet using Azure Verified Modules.'

@description('Name of the virtual network.')
param name string

@description('Location for the virtual network.')
param location string

@description('Address space for the virtual network, e.g. 10.10.0.0/16.')
param addressPrefix string

@description('Name of the workload subnet.')
param subnetName string

@description('Address prefix for the workload subnet, e.g. 10.10.1.0/24.')
param subnetPrefix string

@description('Tags applied to the virtual network.')
param tags object = {}

// Pinned Azure Verified Module for the virtual network.
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

@description('Resource ID of the workload subnet.')
output subnetResourceId string = virtualNetwork.outputs.subnetResourceIds[0]
