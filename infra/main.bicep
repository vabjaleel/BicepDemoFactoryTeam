// ----------------------------------------------------------------------------
// Orchestrator: networking + VM batch loop. Validates subnetIndex bounds
// fail-fast, then delegates to the networking and vm-batch modules.
// ----------------------------------------------------------------------------

targetScope = 'resourceGroup'

import { subnetConfigT, vmBatchConfigT, subnetOutputT } from 'modules/types.bicep'

@description('Customer short name.')
param customer string

@description('Environment short name.')
param environmentName string

@description('Azure region.')
param location string

@description('Resource tags (already merged with mandatory tags by entry.bicep).')
param tags object = {}

@description('VNet IPv4 address prefixes.')
@minLength(1)
param addressPrefixes string[]

@description('Subnet definitions.')
param subnets subnetConfigT[]

@description('VM batches (empty for network-only environments).')
param vmBatches vmBatchConfigT[] = []

@description('Local administrator username.')
param vmAdminUsername string

@secure()
@description('Local administrator password.')
param vmAdminPassword string

@description('Default OS image version.')
param osVersion string = 'latest'

var vnetName = 'vnet-${customer}-${environmentName}'
var subnetCount = length(subnets)

// ----------------------------------------------------------------------------
// Networking.
// ----------------------------------------------------------------------------
module networking 'modules/networking.bicep' = {
  name: 'net-${customer}-${environmentName}'
  params: {
    vnetName: vnetName
    location: location
    addressPrefixes: addressPrefixes
    subnets: subnets
    tags: tags
  }
}

// ----------------------------------------------------------------------------
// subnetIndex bounds validation (fail-fast).
// ----------------------------------------------------------------------------
var subnetIndexErrors = map(
  filter(range(0, length(vmBatches)), i => vmBatches[i].subnetIndex < 0 || vmBatches[i].subnetIndex >= subnetCount),
  i => 'vmBatch "${vmBatches[i].name}" subnetIndex ${vmBatches[i].subnetIndex} is out of range (0..${subnetCount - 1}).'
)

module validateBatches 'modules/validator.bicep' = {
  name: 'validate-batches-${customer}-${environmentName}'
  params: {
    scope: 'main:subnetIndex'
    errors: subnetIndexErrors
    errorCount: any(length(subnetIndexErrors))
  }
}

// ----------------------------------------------------------------------------
// VM batches. The subnet index is clamped defensively so expression evaluation
// never indexes out of bounds; the validator still hard-fails genuine errors.
// ----------------------------------------------------------------------------
module vmBatchMods 'modules/vm-batch.bicep' = [for (b, i) in vmBatches: {
  name: 'batch-${customer}-${environmentName}-${i}'
  params: {
    batchName: b.name
    vmCount: b.vmCount
    osType: b.osType
    vmSize: b.vmSize
    computerNameOverride: b.?computerNameOverride
    zone: b.?zone ?? 'none'
    dataDisks: b.?dataDisks ?? []
    osVersion: b.?osVersion ?? osVersion
    location: location
    subnetResourceId: subnetCount > 0 ? networking.outputs.subnets[min(max(b.subnetIndex, 0), subnetCount - 1)].resourceId : ''
    adminUsername: vmAdminUsername
    adminPassword: vmAdminPassword
    tags: tags
  }
  dependsOn: [
    validateBatches
  ]
}]

@description('Resource ID of the virtual network.')
output vnetResourceId string = networking.outputs.vnetResourceId

@description('Name of the virtual network.')
output vnetName string = networking.outputs.vnetName

@description('Resolved subnets.')
output subnets subnetOutputT[] = networking.outputs.subnets

@description('VM names grouped per batch.')
output vmNamesByBatch array = [for i in range(0, length(vmBatches)): vmBatchMods[i].outputs.vmNames]
