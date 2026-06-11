using '../../infra/entry.bicep'

// Contoso — production. Mixed Linux + Windows, two subnets, data disks,
// availability zones, a single-VM computer-name override, OS version override.
param customer = 'contoso'
param environmentName = 'prod'

param tags = {
  costCenter: 'cc-1001'
  owner: 'platform-team'
}

param addressPrefixes = [
  '10.10.0.0/16'
]

param subnets = [
  {
    name: 'app'
    addressPrefix: '10.10.1.0/24'
    usage: 'VM'
  }
  {
    name: 'data'
    addressPrefix: '10.10.2.0/24'
    usage: 'VM/PrivateEndpoint'
  }
]

param vmBatches = [
  {
    name: 'web'
    vmCount: 2
    osType: 'Linux'
    subnetIndex: 0
    vmSize: 'Standard_D2s_v5'
    zone: '1'
    osVersion: '22.04.202404170'
  }
  {
    name: 'sql'
    vmCount: 1
    osType: 'Windows'
    subnetIndex: 1
    vmSize: 'Standard_D4s_v5'
    zone: '2'
    computerNameOverride: 'SQLPROD01'
    dataDisks: [
      {
        diskSizeGB: 256
        sku: 'Premium_LRS'
        lun: 0
      }
      {
        diskSizeGB: 512
        sku: 'Premium_ZRS'
        lun: 1
      }
    ]
  }
]

param vmAdminUsername = 'azureadmin'

// Password is read from an environment variable — never committed.
param vmAdminPassword = readEnvironmentVariable('VM_ADMIN_PASSWORD', '')

param osVersion = 'latest'
