using '../../infra/entry.bicep'

// Fabrikam — dev. Smallest valid configuration: one subnet, one Linux VM.
param customer = 'fabrikam'
param environmentName = 'dev'

param addressPrefixes = [
  '10.30.0.0/16'
]

param subnets = [
  {
    name: 'app'
    addressPrefix: '10.30.1.0/24'
    usage: 'VM'
  }
]

param vmBatches = [
  {
    name: 'app'
    vmCount: 1
    osType: 'Linux'
    subnetIndex: 0
    vmSize: 'Standard_B2s'
  }
]

param vmAdminUsername = 'azureuser'

param vmAdminPassword = readEnvironmentVariable('VM_ADMIN_PASSWORD', '')
