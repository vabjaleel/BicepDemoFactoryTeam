targetScope = 'resourceGroup'

// ----------------------------------------------------------------------------
// Multi-customer VM factory — orchestrator
// Deploys a VNet + subnet, then N VMs (each with its own NIC) into the subnet.
// One resource group per customer/environment (created by the workflow).
// ----------------------------------------------------------------------------

@description('Customer (tenant) short name. Used in resource names and tags.')
param customer string

@description('Environment short name, e.g. dev, test, prod.')
param environment string

@description('Azure region. Defaults to the resource group location.')
param location string = resourceGroup().location

@description('VNet address space, e.g. 10.10.0.0/16.')
param addressPrefix string

@description('Subnet address prefix, e.g. 10.10.1.0/24.')
param subnetPrefix string

@description('Number of VMs to deploy.')
@minValue(1)
@maxValue(99)
param vmCount int

@description('VM size SKU.')
param vmSize string = 'Standard_D2s_v5'

@description('Operating system type.')
@allowed([
  'Linux'
  'Windows'
])
param osType string = 'Linux'

@description('Marketplace image reference. Defaults based on osType.')
param imageReference object = osType == 'Windows'
  ? {
      publisher: 'MicrosoftWindowsServer'
      offer: 'WindowsServer'
      sku: '2022-datacenter-azure-edition'
      version: 'latest'
    }
  : {
      publisher: 'Canonical'
      offer: '0001-com-ubuntu-server-jammy'
      sku: '22_04-lts-gen2'
      version: 'latest'
    }

@description('Local administrator username.')
param adminUsername string

@description('Local administrator password. Supplied via secret/env var — never hardcoded.')
@secure()
param adminPassword string

@description('Availability zone for the VMs. -1 = no zone (regions without zones).')
@allowed([
  -1
  1
  2
  3
])
param availabilityZone int = -1

// ----------------------------------------------------------------------------
// Naming & tags
// ----------------------------------------------------------------------------
var namePrefix = '${customer}-${environment}'

// Windows computer names must be <= 15 chars and unique per VM.
// Take up to 13 chars of the (sanitised) prefix, then append a 2-digit index.
var computerNamePrefix = take(toLower(replace(namePrefix, '-', '')), 13)

var tags = {
  customer: customer
  environment: environment
}

// ----------------------------------------------------------------------------
// Networking
// ----------------------------------------------------------------------------
module network 'modules/network.bicep' = {
  name: 'network'
  params: {
    name: 'vnet-${namePrefix}'
    location: location
    addressPrefix: addressPrefix
    subnetName: 'snet-${namePrefix}'
    subnetPrefix: subnetPrefix
    tags: tags
  }
}

// ----------------------------------------------------------------------------
// Virtual machines (one module instance per VM, NIC created by the module)
// ----------------------------------------------------------------------------
module vms 'modules/compute.bicep' = [
  for i in range(0, vmCount): {
    name: 'vm-${i}'
    params: {
      name: 'vm-${namePrefix}-${padLeft(string(i + 1), 2, '0')}'
      computerName: '${computerNamePrefix}${padLeft(string(i + 1), 2, '0')}'
      location: location
      vmSize: vmSize
      osType: osType
      imageReference: imageReference
      adminUsername: adminUsername
      adminPassword: adminPassword
      availabilityZone: availabilityZone
      subnetResourceId: network.outputs.subnetResourceId
      tags: tags
    }
  }
]

// ----------------------------------------------------------------------------
// Outputs (no secrets)
// ----------------------------------------------------------------------------
@description('Resource ID of the deployed virtual network.')
output vnetId string = network.outputs.vnetId

@description('Names of the deployed virtual machines.')
output vmNames array = [for i in range(0, vmCount): vms[i].outputs.name]
