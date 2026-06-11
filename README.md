# Bicep VM platform factory

Production-ready Bicep + GitHub Actions solution that deploys virtual-machine platform
environments to Azure using pinned [Azure Verified Modules](https://aka.ms/avm). **One
parameter file describes one customer environment**, and each environment deploys to its
own resource group `rg-<customer>-<environmentName>`.

## Repository layout

```text
infra/
  entry.bicep              # Public deployment contract (resource-group scoped)
  main.bicep               # Orchestrator (networking + VM batch loop)
  modules/
    types.bicep            # Shared @export() user-defined types
    validator.bicep        # Generic maxValue(0) fail-fast guard (no resources)
    networking.bicep       # CIDR/subnet validation + AVM VNet
    vm-batch.bicep         # Computer-name validation + VM loop
    vm.bicep               # Single VM via AVM + standalone managed data disks
params/
  <customer>/<environment>.bicepparam   # one file per customer environment
scripts/
  deploy.sh                # Bash production deployment driver
.github/workflows/
  deploy.yml               # Manual-trigger CI/CD (GitHub Actions, OIDC)
docs/
  ARCHITECTURE.md
  BEGINNER-GUIDE.md
bicepconfig.json           # Strict analyzer rules
.gitattributes             # LF for *.sh, *.bicep, *.bicepparam
.gitignore
README.md
```

Seed environments: `params/contoso/prod.bicepparam` (mixed Linux + Windows, data disks,
zones), `params/contoso/test.bicepparam` (multi-VM Linux batch), and
`params/fabrikam/dev.bicepparam` (smallest valid config).

## Prerequisites

- Azure CLI + Bicep (`az bicep install`)
- `jq` and Bash (Git Bash / WSL on Windows)
- An Azure subscription and permission to create resource groups

## Quick start

```bash
az login
export VM_ADMIN_PASSWORD='<strong-password>'
az bicep build --file infra/entry.bicep
az bicep build-params --file params/contoso/prod.bicepparam
./scripts/deploy.sh --param-file params/contoso/prod.bicepparam
```

## Validate

```bash
# Template
az bicep build --file infra/entry.bicep

# Every parameter file (password supplied via env var)
export VM_ADMIN_PASSWORD='<temporary-strong-password>'
for f in params/**/*.bicepparam; do az bicep build-params --file "$f"; done
```

Both must exit 0 with no analyzer warnings.

## Deployment flags (`scripts/deploy.sh`)

| Flag / env | Default | Purpose |
| --- | --- | --- |
| `--param-file <path>` | (required) | Customer environment parameter file. |
| `--subscription <id\|n/a>` | `n/a` | Subscription id, or current az context. |
| `--location <region>` | (param/`eastus`) | Override resource group location. |
| `VM_ADMIN_PASSWORD` | — | Required when the environment has VM batches. |
| `RUN_WHATIF` | `true` | Run what-if before deploying. |
| `WHATIF_FAILURE_MODE` | `fail` | `fail` or `warn` on what-if failure. |
| `VERBOSE` | `false` | Verbose logging + live operation tree. |
| `POLL_INTERVAL` | `15` | Seconds between status polls. |
| `MAX_WAIT` | `3600` | Max seconds to wait. |
| `ARTIFACT_DIR` | `./artifacts` | Output directory for JSON artifacts. |

## Add a new customer or environment

1. Create `params/<customer>/<environment>.bicepparam` (copy a seed file).
2. Set `customer`, `environmentName`, `addressPrefixes`, `subnets`, `vmBatches`
   (non-overlapping address space).
3. Keep `vmAdminPassword = readEnvironmentVariable('VM_ADMIN_PASSWORD', '')`.
4. Validate, commit, then run the workflow with the matching inputs.

No Bicep changes are required to onboard a customer or environment.

## GitHub Actions

The `Deploy environment` workflow (`workflow_dispatch`) runs two jobs:

1. **quality-gate** — builds `entry.bicep`/`main.bicep` and lints every
   `params/**/*.bicepparam` into an uploaded `validation/` artifact.
2. **deploy** — OIDC login, resolves the parameter file (failing with a list of valid
   combinations if missing), prints a preflight summary, and runs `scripts/deploy.sh`.

### Required secrets

| Secret | Purpose |
| --- | --- |
| `AZURE_CLIENT_ID` | App registration (client) ID for OIDC login. |
| `AZURE_TENANT_ID` | Entra ID tenant ID. |
| `AZURE_SUBSCRIPTION_ID` | Target subscription ID. |
| `VM_ADMIN_PASSWORD` | VM local administrator password (injected at deploy time). |

No client secret is stored — authentication uses OIDC federation. See
[docs/BEGINNER-GUIDE.md](docs/BEGINNER-GUIDE.md) for the one-time OIDC setup and
[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for the design and validation rules.
