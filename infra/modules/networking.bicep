// ----------------------------------------------------------------------------
// Networking: CIDR/subnet validation (fail-fast) + AVM virtual network.
// ----------------------------------------------------------------------------

import { subnetConfigT, subnetOutputT } from 'types.bicep'

@description('Virtual network name.')
param vnetName string

@description('Azure region.')
param location string

@description('VNet IPv4 address prefixes.')
@minLength(1)
param addressPrefixes string[]

@description('Subnet definitions.')
param subnets subnetConfigT[]

@description('Resource tags.')
param tags object = {}

// ----------------------------------------------------------------------------
// Pure CIDR helpers (total: never error on malformed input).
// ----------------------------------------------------------------------------

@description('True when every character of a non-empty string is a digit.')
func allDigits(s string) bool =>
  !empty(s) && length(filter(map(range(0, length(s)), i => substring(s, i, 1)), c => indexOf('0123456789', c) < 0)) == 0

@description('True when an octet string is numeric and within 0..255.')
func octetValid(o string) bool => allDigits(o) && length(o) <= 3 && int(o) <= 255

@description('True when the string is a syntactically valid IPv4 CIDR.')
func isValidCidr(cidr string) bool => length(split(cidr, '/')) == 2 && allDigits(last(split(cidr, '/'))) && int(last(split(cidr, '/'))) <= 32 && length(split(first(split(cidr, '/')), '.')) == 4 && octetValid(split(first(split(cidr, '/')), '.')[0]) && octetValid(split(first(split(cidr, '/')), '.')[1]) && octetValid(split(first(split(cidr, '/')), '.')[2]) && octetValid(split(first(split(cidr, '/')), '.')[3])

@description('Returns the input CIDR when valid, otherwise a non-overlapping sentinel /32.')
func safeCidr(cidr string) string => isValidCidr(cidr) ? cidr : '255.255.255.255/32'

@description('Converts a dotted-quad IPv4 string to a 32-bit integer.')
func ipToInt(ip string) int =>
  int(split(ip, '.')[0]) * 16777216 + int(split(ip, '.')[1]) * 65536 + int(split(ip, '.')[2]) * 256 + int(split(ip, '.')[3])

@description('Network start integer of a (valid) CIDR.')
func cidrStartInt(cidr string) int => ipToInt(first(split(cidr, '/')))

@description('Prefix length of a (valid) CIDR.')
func cidrPrefixLen(cidr string) int => int(last(split(cidr, '/')))

// ----------------------------------------------------------------------------
// Precomputed range arithmetic.
// ----------------------------------------------------------------------------

// 2^0 .. 2^32 (64-bit ints; 2^32 exceeds int32 but Bicep ints are 64-bit).
var pow2 = [
  1
  2
  4
  8
  16
  32
  64
  128
  256
  512
  1024
  2048
  4096
  8192
  16384
  32768
  65536
  131072
  262144
  524288
  1048576
  2097152
  4194304
  8388608
  16777216
  33554432
  67108864
  134217728
  268435456
  536870912
  1073741824
  2147483648
  4294967296
]

var subnetCount = length(subnets)
var vnetCount = length(addressPrefixes)

var subnetSafe = [for s in subnets: safeCidr(s.addressPrefix)]
var vnetSafe = [for p in addressPrefixes: safeCidr(p)]

var subnetStart = [for c in subnetSafe: cidrStartInt(c)]
var subnetPrefix = [for c in subnetSafe: cidrPrefixLen(c)]
var subnetEnd = [for i in range(0, subnetCount): subnetStart[i] + pow2[32 - subnetPrefix[i]] - 1]

var vnetStart = [for c in vnetSafe: cidrStartInt(c)]
var vnetPrefix = [for c in vnetSafe: cidrPrefixLen(c)]
var vnetEnd = [for i in range(0, vnetCount): vnetStart[i] + pow2[32 - vnetPrefix[i]] - 1]

// ----------------------------------------------------------------------------
// Validation rules.
// ----------------------------------------------------------------------------

var vnetCidrErrors = map(
  filter(range(0, vnetCount), i => !isValidCidr(addressPrefixes[i])),
  i => 'VNet addressPrefix[${i}] "${addressPrefixes[i]}" is not a valid IPv4 CIDR.'
)

var subnetCidrErrors = map(
  filter(range(0, subnetCount), i => !isValidCidr(subnets[i].addressPrefix)),
  i => 'Subnet "${subnets[i].name}" addressPrefix "${subnets[i].addressPrefix}" is not a valid IPv4 CIDR.'
)

var subnetTooSmallErrors = map(
  filter(range(0, subnetCount), i => isValidCidr(subnets[i].addressPrefix) && subnetPrefix[i] > 29),
  i => 'Subnet "${subnets[i].name}" prefix /${subnetPrefix[i]} is smaller than the minimum /29.'
)

var subnetOutsideErrors = map(
  filter(
    range(0, subnetCount),
    i => isValidCidr(subnets[i].addressPrefix) && length(filter(range(0, vnetCount), j => subnetStart[i] >= vnetStart[j] && subnetEnd[i] <= vnetEnd[j])) == 0
  ),
  i => 'Subnet "${subnets[i].name}" (${subnets[i].addressPrefix}) is not contained within any VNet address prefix.'
)

var subnetOverlapErrors = flatten(map(
  range(0, subnetCount),
  i => map(
    filter(
      range(0, subnetCount),
      j => j > i && isValidCidr(subnets[i].addressPrefix) && isValidCidr(subnets[j].addressPrefix) && subnetStart[i] <= subnetEnd[j] && subnetStart[j] <= subnetEnd[i]
    ),
    j => 'Subnet "${subnets[i].name}" overlaps subnet "${subnets[j].name}".'
  )
))

var subnetUsageErrors = map(
  filter(range(0, subnetCount), i => !contains(['VM', 'VM/PrivateEndpoint'], subnets[i].usage)),
  i => 'Subnet "${subnets[i].name}" has invalid usage "${subnets[i].usage}".'
)

var errors = concat(
  vnetCidrErrors,
  subnetCidrErrors,
  subnetTooSmallErrors,
  subnetOutsideErrors,
  subnetOverlapErrors,
  subnetUsageErrors
)

module validate 'validator.bicep' = {
  name: 'validate-net-${uniqueString(vnetName)}'
  params: {
    scope: 'networking:${vnetName}'
    errors: errors
    errorCount: any(length(errors))
  }
}

// ----------------------------------------------------------------------------
// Virtual network (deployed only after validation passes).
// ----------------------------------------------------------------------------

var subnetsForAvm = [for (s, i) in subnets: {
  name: '${s.name}-${padLeft(string(i + 1), 2, '0')}'
  addressPrefix: s.addressPrefix
}]

module vnet 'br/public:avm/res/network/virtual-network:0.9.0' = {
  name: 'avm-vnet-${uniqueString(vnetName)}'
  params: {
    name: vnetName
    location: location
    addressPrefixes: addressPrefixes
    subnets: subnetsForAvm
    tags: tags
    enableTelemetry: false
  }
  dependsOn: [
    validate
  ]
}

@description('Resource ID of the virtual network.')
output vnetResourceId string = vnet.outputs.resourceId

@description('Name of the virtual network.')
output vnetName string = vnet.outputs.name

@description('Resolved subnets.')
output subnets subnetOutputT[] = [for (s, i) in subnets: {
  name: '${s.name}-${padLeft(string(i + 1), 2, '0')}'
  resourceId: vnet.outputs.subnetResourceIds[i]
  addressPrefix: s.addressPrefix
  usage: s.usage
}]
