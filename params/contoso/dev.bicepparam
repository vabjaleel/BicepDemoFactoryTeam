using '../../infra/main.bicep'

// Contoso — development environment (Linux)
param customer = 'contoso'
param environment = 'dev'
param addressPrefix = '10.10.0.0/16'
param subnetPrefix = '10.10.1.0/24'
param vmCount = 2
param vmSize = 'Standard_D2s_v5'
param osType = 'Linux'
param adminUsername = 'azureuser'

// Password is read from an environment variable — never hardcoded.
// CI sets VM_ADMIN_PASSWORD from a GitHub secret.
param adminPassword = readEnvironmentVariable('VM_ADMIN_PASSWORD')
