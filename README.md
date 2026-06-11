# Customer VM factory (Bicep + GitHub Actions)

Deploys a virtual network and **N** virtual machines per customer environment using
[Azure Verified Modules](https://aka.ms/avm). Each customer/environment deploys to its
own resource group.

## Layout

```
infra/
  main.bicep            # thin orchestrator (resourceGroup scope)
  modules/
    network.bicep       # VNet + subnet (AVM, pinned)
    compute.bicep       # one VM + NIC (AVM, pinned)
params/
  <customer>/<env>.bicepparam
.github/workflows/deploy.yml
```

`main.bicep` only wires parameters into the two modules and loops the VMs with
zero-padded names (`vm-<customer>-<env>-01`, `-02`, ...). All resource logic lives
in the modules.

## Quick start

1. Configure the [required secrets](#required-secrets) and OIDC (see note below).
2. Run the **Deploy customer environment** workflow (Actions tab) with `customer`,
   `environment`, and `location` inputs.

Deploy locally instead:

```bash
az group create -n rg-contoso-dev -l eastus
$env:VM_ADMIN_PASSWORD = '<strong-password>'   # PowerShell; use export on bash
az deployment group create \
  -g rg-contoso-dev \
  -f infra/main.bicep \
  -p params/contoso/dev.bicepparam
```

## Adding a customer

Add a new parameter file — no Bicep changes required:

```
params/<customer>/<environment>.bicepparam
```

Set `customer`, `environment`, networking (`addressPrefix`, `subnetPrefix`), VM
settings (`vmCount`, `vmSize`, `osType`), and `adminUsername`. The password is read
from the `VM_ADMIN_PASSWORD` environment variable via `readEnvironmentVariable(...)`
— never hardcode secrets. Seeded examples: `contoso/dev` (Linux) and
`fabrikam/prod` (Windows).

## Required secrets

| Secret | Purpose |
| --- | --- |
| `AZURE_CLIENT_ID` | App registration (federated credential) client ID |
| `AZURE_TENANT_ID` | Entra tenant ID |
| `AZURE_SUBSCRIPTION_ID` | Target subscription ID |
| `VM_ADMIN_PASSWORD` | VM local admin password (passed as the secure parameter) |

## OIDC setup (one line)

Create an app registration with a federated credential for this repo and assign it
`Contributor` on the subscription:

```bash
az ad app create --display-name vm-factory && az role assignment create --assignee <appId> --role Contributor --scope /subscriptions/<subId>   # then add a federated credential for repo:<org>/<repo>:ref:refs/heads/main
```

Login uses OIDC (`azure/login@v2` with `id-token: write`) — no client secret stored.

## Acceptance

- `az bicep build -f infra/main.bicep` builds cleanly.
- `az bicep build-params -f params/<customer>/<env>.bicepparam` builds cleanly.
- `deploy.yml` is valid YAML with spaces only (no tabs).
- No hardcoded secrets; password flows from `VM_ADMIN_PASSWORD` → secure parameter.
- Each customer/environment deploys to its own `rg-<customer>-<environment>`.
