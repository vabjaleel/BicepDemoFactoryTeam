# Bicep VM Factory

A multi-customer "factory" that deploys a virtual network and **N virtual machines** per
customer environment using [Azure Verified Modules](https://aka.ms/avm) and GitHub Actions.

Each customer/environment is deployed into **its own resource group** (`rg-<customer>-<environment>`).

```text
infra/main.bicep              # Orchestrator (resourceGroup scope)
infra/modules/network.bicep   # VNet + subnet (AVM virtual-network 0.9.0)
infra/modules/compute.bicep   # One VM + NIC (AVM virtual-machine 0.22.1)
params/<customer>/<env>.bicepparam
.github/workflows/deploy.yml
README.md
```

## Quick start

1. Configure the required GitHub secrets (see below) and OIDC.
2. In GitHub, open **Actions → Deploy customer environment → Run workflow**.
3. Provide the inputs:
   - **customer** — must match a folder under `params/` (e.g. `contoso`)
   - **environment** — must match a `.bicepparam` file (e.g. `dev`)
   - **location** — Azure region (default `eastus`)
4. The workflow resolves the parameter file, creates `rg-<customer>-<environment>`,
   and deploys the VNet + VMs.

### Local validation

```powershell
# Build the template
az bicep build --file infra/main.bicep

# Build a parameter file (password comes from an env var)
$env:VM_ADMIN_PASSWORD = '<a-strong-password>'
az bicep build-params --file params/contoso/dev.bicepparam
```

## How to add a customer

Adding a customer (or environment) requires **no Bicep changes** — just add a parameter file:

1. Create `params/<customer>/<environment>.bicepparam`.
2. Set `customer`, `environment`, `addressPrefix`, `subnetPrefix`, `vmCount`, `vmSize`,
   `osType`, and `adminUsername`. Use a **non-overlapping** address space.
3. Keep `adminPassword = readEnvironmentVariable('VM_ADMIN_PASSWORD')` — never hardcode secrets.
4. Do **not** set `location` in the param file; it comes from the workflow input.
5. Commit, then run the workflow with the matching `customer` / `environment` inputs.

> Tip: copy `params/contoso/dev.bicepparam` (Linux) or `params/fabrikam/prod.bicepparam`
> (Windows) as a starting point.

## Required GitHub secrets

| Secret | Purpose |
| --- | --- |
| `AZURE_CLIENT_ID` | App registration (client) ID used for OIDC login |
| `AZURE_TENANT_ID` | Entra ID tenant ID |
| `AZURE_SUBSCRIPTION_ID` | Target subscription ID |
| `VM_ADMIN_PASSWORD` | Local administrator password injected at deploy time |

No client secret is stored — authentication uses **OIDC federation**.

## One-line OIDC setup

Create an Entra ID app registration with a **federated credential** (entity = Branch,
branch `main`, subject `repo:<owner>/<repo>:ref:refs/heads/main`) and assign it the
**Contributor** role on the target subscription (or resource group).
