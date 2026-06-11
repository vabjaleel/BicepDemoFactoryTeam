// ----------------------------------------------------------------------------
// Compute module — single VM + NIC (Azure Verified Module, pinned)
// ----------------------------------------------------------------------------

@description('Virtual machine name.')
param name string

@description('OS computer name (<= 15 chars for Windows, must be unique).')
param computerName string

@description('Azure region.')
param location string

@description('VM size SKU.')
param vmSize string

@description('Operating system type.')
@allowed([
  'Linux'
  'Windows'
])
param osType string

@description('Marketplace image reference.')
param imageReference object

@description('Local administrator username.')
param adminUsername string

@description('Local administrator password.')
@secure()
param adminPassword string

@description('Resource ID of the subnet to attach the NIC to.')
param subnetResourceId string

@description('Availability zone. -1 = no zone.')
@allowed([
  -1
  1
  2
  3
])
param availabilityZone int = -1

@description('Resource tags.')
param tags object = {}

module virtualMachine 'br/public:avm/res/compute/virtual-machine:0.22.1' = {
  name: 'avm-${name}'
  params: {
    name: name
    computerName: computerName
    location: location
    availabilityZone: availabilityZone
    vmSize: vmSize
    osType: osType
    imageReference: imageReference
    adminUsername: adminUsername
    adminPassword: adminPassword
    disablePasswordAuthentication: false
    tags: tags
    nicConfigurations: [
      {
        nicSuffix: '-nic-01'
        ipConfigurations: [
          {
            name: 'ipconfig01'
            subnetResourceId: subnetResourceId
          }
        ]
      }
    ]
    osDisk: {
      caching: 'ReadWrite'
      diskSizeGB: 128
      managedDisk: {
        storageAccountType: 'Premium_LRS'
      }
    }
  }
}

@description('Name of the virtual machine.')
output name string = virtualMachine.outputs.name

@description('Resource ID of the virtual machine.')
output resourceId string = virtualMachine.outputs.resourceId
