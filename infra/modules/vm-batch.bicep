// ----------------------------------------------------------------------------
// VM batch: resolves & validates in-guest computer names (fail-fast), then
// loops the requested VM count, delegating each VM to vm.bicep.
// ----------------------------------------------------------------------------

import { osTypeT, zoneT, dataDiskConfigT } from 'types.bicep'

@description('Batch name (VM resource-name prefix).')
param batchName string

@minValue(1)
@maxValue(50)
@description('Number of VMs in the batch.')
param vmCount int

@description('Operating system family.')
param osType osTypeT

@description('VM size SKU.')
param vmSize string

@description('Optional in-guest computer name. Only valid for single-VM batches.')
param computerNameOverride string?

@description('Availability zone selector.')
param zone zoneT = 'none'

@description('Data disks attached to every VM in the batch.')
param dataDisks dataDiskConfigT[] = []

@description('OS image version.')
param osVersion string

@description('Azure region.')
param location string

@description('Resource ID of the subnet to attach NICs to.')
param subnetResourceId string

@description('Local administrator username.')
param adminUsername string

@secure()
@description('Local administrator password.')
param adminPassword string

@description('Resource tags.')
param tags object = {}

// ----------------------------------------------------------------------------
// Pure computer-name helpers.
// ----------------------------------------------------------------------------

@description('True when every character is an ASCII letter, digit, or hyphen.')
func isAlnumHyphen(s string) bool =>
  !empty(s) && length(filter(map(range(0, length(s)), i => substring(s, i, 1)), c => indexOf('abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-', c) < 0)) == 0

@description('True when every character of a non-empty string is a digit.')
func isAllDigits(s string) bool =>
  !empty(s) && length(filter(map(range(0, length(s)), i => substring(s, i, 1)), c => indexOf('0123456789', c) < 0)) == 0

@description('Validates an in-guest computer name for the given OS family.')
func validComputerName(name string, os string) bool => os == 'Windows' ? (!empty(name) && length(name) <= 15 && isAlnumHyphen(name) && !isAllDigits(name)) : (!empty(name) && length(name) <= 64 && isAlnumHyphen(name))

// ----------------------------------------------------------------------------
// Computer-name resolution.
// ----------------------------------------------------------------------------
var maxLen = osType == 'Windows' ? 15 : 64
var sanitized = toLower(replace(batchName, '-', ''))
var computerBase = take(sanitized, maxLen - 2)
var defaultNames = [for i in range(0, vmCount): '${computerBase}${padLeft(string(i + 1), 2, '0')}']

var hasOverride = computerNameOverride != null
var overrideValue = computerNameOverride ?? ''

var overrideReuseError = (hasOverride && vmCount > 1)
  ? ['computerNameOverride "${overrideValue}" cannot be reused across ${vmCount} VMs in batch "${batchName}".']
  : []

var overrideInvalidError = (hasOverride && !validComputerName(overrideValue, osType))
  ? ['computerNameOverride "${overrideValue}" is not a valid ${osType} computer name.']
  : []

var errors = concat(overrideReuseError, overrideInvalidError)

// Per-VM resolved computer name: override (single-VM) -> default -> safe fallback.
var resolvedNames = [for i in range(0, vmCount): (hasOverride && vmCount == 1)
  ? (validComputerName(overrideValue, osType) ? overrideValue : take(toLower('vm${uniqueString(batchName)}'), maxLen))
  : (validComputerName(defaultNames[i], osType) ? defaultNames[i] : take(toLower('vm${uniqueString(batchName, string(i))}'), maxLen))]

module validateNames 'validator.bicep' = {
  name: 'validate-names-${uniqueString(batchName)}'
  params: {
    scope: 'vm-batch:${batchName}'
    errors: errors
    errorCount: any(length(errors))
  }
}

// ----------------------------------------------------------------------------
// VM loop.
// ----------------------------------------------------------------------------
module vms 'vm.bicep' = [for i in range(0, vmCount): {
  name: 'vm-${uniqueString(batchName)}-${i}'
  params: {
    vmName: '${batchName}-${padLeft(string(i + 1), 2, '0')}'
    computerName: resolvedNames[i]
    location: location
    vmSize: vmSize
    osType: osType
    osVersion: osVersion
    adminUsername: adminUsername
    adminPassword: adminPassword
    subnetResourceId: subnetResourceId
    zone: zone
    dataDisks: dataDisks
    tags: tags
  }
  dependsOn: [
    validateNames
  ]
}]

@description('Names of the VMs deployed in this batch.')
output vmNames array = [for i in range(0, vmCount): vms[i].outputs.name]
