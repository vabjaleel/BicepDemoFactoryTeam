# Beginner guide

A step-by-step walkthrough for deploying a customer environment.

## 1. Install the tools

- **Azure CLI** — https://learn.microsoft.com/cli/azure/install-azure-cli
- **Bicep** — `az bicep install`
- **jq** — https://jqlang.github.io/jq/ (used by `scripts/deploy.sh`)
- **Bash** — Linux/macOS natively, or Git Bash / WSL on Windows.

## 2. Sign in

```bash
az login
az account set --subscription "<your-subscription-id>"
```

## 3. Understand the model

- One file `params/<customer>/<environment>.bicepparam` = one customer environment.
- A customer can have many environments (each its own file, each its own resource group).
- Example seeds:
  - `params/contoso/prod.bicepparam` — mixed Linux + Windows, data disks, zones.
  - `params/contoso/test.bicepparam` — same customer, second environment.
  - `params/fabrikam/dev.bicepparam` — smallest valid config.

## 4. Create a new customer environment

1. Copy a seed file to `params/<customer>/<environment>.bicepparam`.
2. Set `customer`, `environmentName`, `addressPrefixes`, `subnets`, and `vmBatches`.
   Use a non-overlapping address space.
3. Keep `vmAdminPassword = readEnvironmentVariable('VM_ADMIN_PASSWORD', '')` — never
   hardcode a secret.

## 5. Validate locally

```bash
az bicep build --file infra/entry.bicep
export VM_ADMIN_PASSWORD='<temporary-strong-password>'
az bicep build-params --file params/<customer>/<environment>.bicepparam
```

Both commands must exit 0 with no analyzer warnings.

## 6. Deploy

```bash
export VM_ADMIN_PASSWORD='<strong-password>'
./scripts/deploy.sh --param-file params/<customer>/<environment>.bicepparam
```

Useful toggles: `RUN_WHATIF=false`, `WHATIF_FAILURE_MODE=warn`, `VERBOSE=true`.

## 7. Troubleshooting

| Symptom | Likely cause |
| --- | --- |
| `maxValue` validation error at deploy | A validator caught a bad CIDR, overlapping/duplicate subnet, too-small subnet, invalid usage, out-of-range `subnetIndex`, invalid computer-name override, or duplicate data-disk LUN. Read the validator scope/errors. |
| `VM_ADMIN_PASSWORD must be set` | Export the env var before running for an environment that has VM batches. |
| `Parameter file not found` | The customer/environment combo has no `.bicepparam` file. |
| What-if fails | Inspect the artifact under `artifacts/`; set `WHATIF_FAILURE_MODE=warn` to proceed. |

## 8. OIDC setup (GitHub Actions — no stored secret)

The GitHub Actions equivalent of a service-principal client secret is a **federated
identity credential (OIDC)** on an Entra app registration. No secret is stored.

```bash
# 1. Create an app registration + service principal.
az ad sp create-for-rbac --name "bicep-vm-platform-deployer" --query appId -o tsv
# -> APP_ID

# 2. Assign Azure RBAC (authorization is separate from authentication).
az role assignment create \
  --assignee "<APP_ID>" \
  --role "Contributor" \
  --scope "/subscriptions/<SUBSCRIPTION_ID>"

# 3. Add a federated credential bound to the deployment environment.
az ad app federated-credential create \
  --id "<APP_ID>" \
  --parameters '{
    "name": "github-bicep-vm-platform",
    "issuer": "https://token.actions.githubusercontent.com",
    "subject": "repo:<owner>/<repo>:environment:bicep-vm-platform",
    "audiences": ["api://AzureADTokenExchange"]
  }'
```

Then add repo secrets `AZURE_CLIENT_ID` (= APP_ID), `AZURE_TENANT_ID`,
`AZURE_SUBSCRIPTION_ID`, and `VM_ADMIN_PASSWORD`.
