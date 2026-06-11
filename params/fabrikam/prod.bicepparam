using '../../infra/main.bicep'

param customer = 'fabrikam'
param environment = 'prod'

// Networking
param addressPrefix = '10.20.0.0/16'
param subnetPrefix = '10.20.1.0/24'

// Virtual machines
param vmCount = 3
param vmSize = 'Standard_D4s_v5'
param osType = 'Windows'

// Admin credentials (password read from an environment variable, never hardcoded)
param adminUsername = 'azureadmin'
param adminPassword = readEnvironmentVariable('VM_ADMIN_PASSWORD')
