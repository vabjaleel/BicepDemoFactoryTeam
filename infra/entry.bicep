// ----------------------------------------------------------------------------
// Public deployment contract (resource-group scoped).
// One parameter file = one customer environment. Merges mandatory tags and
// forwards everything to the orchestrator.
// ----------------------------------------------------------------------------

targetScope = 'resourceGroup'

import { subnetConfigT, vmBatchConfigT, subnetOutputT } from 'modules/types.bicep'

@minLength(1)
@maxLength(20)
@description('Customer short name. Drives naming and traceability.')
param customer string

@minLength(1)
@maxLength(20)
@description('Environment short name (e.g. prod, test, dev).')
param environmentName string

@description('Azure region.')
param location string = resourceGroup().location

@description('Optional caller-supplied tags.')
param tags object = {}

@minLength(1)
@description('VNet IPv4 address prefixes.')
param addressPrefixes string[]

@description('Subnet definitions.')
param subnets subnetConfigT[]

@description('VM batches (empty for network-only environments).')
param vmBatches vmBatchConfigT[] = []

@description('Local administrator username.')
param vmAdminUsername string

@secure()
@description('Local administrator password. Never logged or output.')
param vmAdminPassword string

@description('Default OS image version.')
param osVersion string = 'latest'

var mergedTags = union(tags, {
  customer: customer
  environmentName: environmentName
  managedBy: 'bicep'
})

module main 'main.bicep' = {
  name: 'main-${customer}-${environmentName}'
  params: {
    customer: customer
    environmentName: environmentName
    location: location
    tags: mergedTags
    addressPrefixes: addressPrefixes
    subnets: subnets
    vmBatches: vmBatches
    vmAdminUsername: vmAdminUsername
    vmAdminPassword: vmAdminPassword
    osVersion: osVersion
  }
}

@description('Resource ID of the virtual network.')
output vnetResourceId string = main.outputs.vnetResourceId

@description('Name of the virtual network.')
output vnetName string = main.outputs.vnetName

@description('Resolved subnets.')
output subnets subnetOutputT[] = main.outputs.subnets

@description('VM names grouped per batch.')
output vmNamesByBatch array = main.outputs.vmNamesByBatch
