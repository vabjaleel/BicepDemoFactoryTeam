targetScope = 'resourceGroup'

metadata description = 'Deploys a VNet and N VMs for a single customer environment. Orchestrates the network and compute modules.'

@description('Customer identifier, e.g. contoso.')
param customer string

@description('Environment name, e.g. dev or prod.')
param environment string

@description('Azure region for all resources. Defaults to the resource group location.')
param location string = resourceGroup().location

@description('Virtual network address space, e.g. 10.10.0.0/16.')
param addressPrefix string

@description('Workload subnet address prefix, e.g. 10.10.1.0/24.')
param subnetPrefix string

@description('Number of virtual machines to deploy.')
@minValue(1)
@maxValue(99)
param vmCount int

@description('Size of each virtual machine.')
param vmSize string = 'Standard_D2s_v5'

@description('Operating system type for the virtual machines.')
@allowed([
  'Linux'
  'Windows'
])
param osType string = 'Linux'

@description('OS image reference. Defaults are chosen based on osType.')
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

@secure()
@description('Local administrator password. Provide via a secret / environment variable, never hardcode.')
param adminPassword string

@description('Availability zone for the VMs. Use -1 for no zone.')
@allowed([
  -1
  1
  2
  3
])
param availabilityZone int = -1

var namePrefix = '${customer}-${environment}'

// Windows computer names must be <= 15 chars. Build a short, lowercase prefix and
// append the per-VM index so every computer name stays valid and unique.
var computerNamePrefix = take(toLower(replace(namePrefix, '-', '')), 13)

var tags = {
  customer: customer
  environment: environment
}

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

@description('Resource ID of the virtual network.')
output vnetId string = network.outputs.vnetId

@description('Names of the deployed virtual machines.')
output vmNames array = [for i in range(0, vmCount): vms[i].outputs.name]
