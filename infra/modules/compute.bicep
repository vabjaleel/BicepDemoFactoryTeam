metadata description = 'Deploys a single virtual machine with a NIC on the given subnet using Azure Verified Modules.'

@description('Name of the virtual machine.')
param name string

@description('Location for the virtual machine.')
param location string

@description('Size of the virtual machine, e.g. Standard_D2s_v5.')
param vmSize string

@description('Operating system type.')
@allowed([
  'Linux'
  'Windows'
])
param osType string

@description('Computer name (OS-level hostname). Must be <= 15 chars for Windows.')
param computerName string

@description('OS image reference (publisher, offer, sku, version).')
param imageReference object

@description('Local administrator username.')
param adminUsername string

@secure()
@description('Local administrator password.')
param adminPassword string

@description('Resource ID of the subnet the NIC is attached to.')
param subnetResourceId string

@description('Availability zone for the VM. Use -1 for no zone.')
@allowed([
  -1
  1
  2
  3
])
param availabilityZone int = -1

@description('Tags applied to the virtual machine.')
param tags object = {}

// Pinned Azure Verified Module for the virtual machine. It also creates the NIC.
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
