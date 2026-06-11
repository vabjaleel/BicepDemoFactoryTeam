using '../../infra/entry.bicep'

// Contoso — test. Same customer, second environment. Two subnets and a
// multi-VM Linux batch placed in an availability zone.
param customer = 'contoso'
param environmentName = 'test'

param addressPrefixes = [
  '10.20.0.0/16'
]

param subnets = [
  {
    name: 'app'
    addressPrefix: '10.20.1.0/24'
    usage: 'VM'
  }
  {
    name: 'pe'
    addressPrefix: '10.20.2.0/24'
    usage: 'VM/PrivateEndpoint'
  }
]

param vmBatches = [
  {
    name: 'worker'
    vmCount: 3
    osType: 'Linux'
    subnetIndex: 0
    vmSize: 'Standard_D2s_v5'
    zone: '1'
  }
    {
    name: 'web'
    vmCount: 30
    osType: 'Windows'
    subnetIndex: 0
    vmSize: 'Standard_D2s_v5'
    zone: '1'
  }
]

param vmAdminUsername = 'azureuser'

param vmAdminPassword = readEnvironmentVariable('VM_ADMIN_PASSWORD', '')
