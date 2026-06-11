using '../../infra/main.bicep'

param customer = 'contoso'
param environment = 'dev'

// Networking
param addressPrefix = '10.10.0.0/16'
param subnetPrefix = '10.10.1.0/24'

// Virtual machines
param vmCount = 2
param vmSize = 'Standard_D2s_v5'
param osType = 'Linux'

// Admin credentials (password read from an environment variable, never hardcoded)
param adminUsername = 'azureuser'
param adminPassword = readEnvironmentVariable('VM_ADMIN_PASSWORD')
