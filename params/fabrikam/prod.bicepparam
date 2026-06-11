using '../../infra/main.bicep'

// Fabrikam — production environment (Windows)
param customer = 'fabrikam'
param environment = 'prod'
param addressPrefix = '10.20.0.0/16'
param subnetPrefix = '10.20.1.0/24'
param vmCount = 3
param vmSize = 'Standard_D4s_v5'
param osType = 'Windows'
param adminUsername = 'azureadmin'

// Password is read from an environment variable — never hardcoded.
// CI sets VM_ADMIN_PASSWORD from a GitHub secret.
param adminPassword = readEnvironmentVariable('VM_ADMIN_PASSWORD')
