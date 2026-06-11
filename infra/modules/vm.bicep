// ----------------------------------------------------------------------------
// Single virtual machine via AVM, plus standalone managed data disks.
// Validates data-disk LUN uniqueness fail-fast before any disk/VM is created.
// ----------------------------------------------------------------------------

import { osTypeT, zoneT, dataDiskConfigT } from 'types.bicep'

@description('VM resource name.')
param vmName string

@description('In-guest computer name (already validated/resolved by the caller).')
param computerName string

@description('Azure region.')
param location string

@description('VM size SKU.')
param vmSize string

@description('Operating system family.')
param osType osTypeT

@description('OS image version.')
param osVersion string

@description('Local administrator username.')
param adminUsername string

@secure()
@description('Local administrator password.')
param adminPassword string

@description('Resource ID of the subnet to attach the NIC to.')
param subnetResourceId string

@description('Availability zone selector.')
param zone zoneT = 'none'

@description('Data disks to create and attach.')
param dataDisks dataDiskConfigT[] = []

@description('Resource tags.')
param tags object = {}

// ----------------------------------------------------------------------------
// LUN uniqueness validation. The for-expression is extracted to a var before
// filter(...) to avoid BCP138.
// ----------------------------------------------------------------------------
var lunValues = [for d in dataDisks: d.lun]

var duplicateLunErrors = map(
  filter(
    range(0, length(dataDisks)),
    i => length(filter(lunValues, l => l == dataDisks[i].lun)) > 1 && indexOf(lunValues, dataDisks[i].lun) == i
  ),
  i => 'Duplicate data-disk LUN ${dataDisks[i].lun} on VM "${vmName}".'
)

module validateLuns 'validator.bicep' = {
  name: 'validate-luns-${uniqueString(vmName)}'
  params: {
    scope: 'vm-luns:${vmName}'
    errors: duplicateLunErrors
    errorCount: any(length(duplicateLunErrors))
  }
}

// ----------------------------------------------------------------------------
// Image + zone mapping.
// ----------------------------------------------------------------------------
var imageReference = osType == 'Windows'
  ? {
      publisher: 'MicrosoftWindowsServer'
      offer: 'WindowsServer'
      sku: '2022-datacenter-azure-edition'
      version: osVersion
    }
  : {
      publisher: 'Canonical'
      offer: '0001-com-ubuntu-server-jammy'
      sku: '22_04-lts-gen2'
      version: osVersion
    }

var zoneInt = zone == 'none' ? -1 : int(zone)

// ----------------------------------------------------------------------------
// Standalone managed data disks (created before the VM attaches them).
// ----------------------------------------------------------------------------
module dataDiskResources 'br/public:avm/res/compute/disk:0.6.0' = [for (d, i) in dataDisks: {
  name: 'avm-disk-${uniqueString(vmName)}-${i}'
  params: {
    name: '${vmName}-datadisk-${padLeft(string(i + 1), 2, '0')}'
    location: location
    availabilityZone: zoneInt
    sku: d.sku
    diskSizeGB: d.diskSizeGB
    tags: tags
    enableTelemetry: false
  }
  dependsOn: [
    validateLuns
  ]
}]

// ----------------------------------------------------------------------------
// Virtual machine.
// ----------------------------------------------------------------------------
module virtualMachine 'br/public:avm/res/compute/virtual-machine:0.22.1' = {
  name: 'avm-vm-${uniqueString(vmName)}'
  params: {
    name: vmName
    computerName: computerName
    location: location
    vmSize: vmSize
    osType: osType
    availabilityZone: zoneInt
    imageReference: imageReference
    adminUsername: adminUsername
    adminPassword: adminPassword
    disablePasswordAuthentication: false
    encryptionAtHost: false
    licenseType: osType == 'Windows' ? 'Windows_Server' : null
    tags: tags
    enableTelemetry: false
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
      name: '${vmName}-osdisk'
      caching: 'ReadWrite'
      diskSizeGB: 128
      managedDisk: {
        storageAccountType: 'StandardSSD_LRS'
      }
    }
    dataDisks: [for (d, i) in dataDisks: {
      lun: d.lun
      managedDisk: {
        resourceId: dataDiskResources[i].outputs.resourceId
      }
    }]
  }
}

@description('Name of the virtual machine.')
output name string = virtualMachine.outputs.name

@description('Resource ID of the virtual machine.')
output resourceId string = virtualMachine.outputs.resourceId
