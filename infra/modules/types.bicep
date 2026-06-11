// ----------------------------------------------------------------------------
// Shared, exported user-defined types for the VM platform factory.
// Imported by entry/main and every module to keep one source of truth.
// ----------------------------------------------------------------------------

@export()
@description('Operating system family for a VM batch.')
type osTypeT = 'Linux' | 'Windows'

@export()
@description('Availability zone selector. "none" maps to the AVM integer -1.')
type zoneT = 'none' | '1' | '2' | '3'

@export()
@description('Allowed subnet usage classification.')
type subnetUsageT = 'VM' | 'VM/PrivateEndpoint'

@export()
@description('Managed-disk SKUs accepted by the AVM virtual-machine dataDisks enum.')
type diskSkuT = 'Premium_LRS' | 'Premium_ZRS' | 'Standard_LRS' | 'StandardSSD_LRS'

@export()
@description('Subnet definition for a customer environment.')
type subnetConfigT = {
  @minLength(1)
  @maxLength(60)
  @description('Logical subnet name (a 2-digit ordinal is appended automatically).')
  name: string

  @description('Subnet IPv4 CIDR. Must sit fully inside a VNet address prefix.')
  addressPrefix: string

  @description('Subnet usage classification.')
  usage: subnetUsageT
}

@export()
@description('Standalone managed data disk attached to every VM in a batch.')
type dataDiskConfigT = {
  @minValue(4)
  @maxValue(32767)
  @description('Data disk size in GB.')
  diskSizeGB: int

  @description('Managed disk SKU.')
  sku: diskSkuT

  @minValue(0)
  @maxValue(63)
  @description('Logical unit number. Must be unique within a VM.')
  lun: int
}

@export()
@description('A homogeneous batch of VMs deployed into one subnet.')
type vmBatchConfigT = {
  @minLength(1)
  @maxLength(40)
  @description('Batch name (used as the VM resource-name prefix).')
  name: string

  @minValue(1)
  @maxValue(50)
  @description('Number of VMs in the batch.')
  vmCount: int

  @description('Operating system family.')
  osType: osTypeT

  @minValue(0)
  @description('Zero-based index into the environment subnets array.')
  subnetIndex: int

  @description('VM size SKU, e.g. Standard_D2s_v5.')
  vmSize: string

  @description('Optional in-guest computer name. Only valid for single-VM batches.')
  computerNameOverride: string?

  @description('Optional availability zone.')
  zone: zoneT?

  @description('Optional data disks attached to every VM in the batch.')
  dataDisks: dataDiskConfigT[]?

  @description('Optional per-batch OS image version override.')
  osVersion: string?
}

@export()
@description('Resolved subnet output shape.')
type subnetOutputT = {
  name: string
  resourceId: string
  addressPrefix: string
  usage: subnetUsageT
}
