#!/usr/bin/env bash
# --- HELP ---
# deploy.sh — production deployment driver for the Bicep VM platform factory.
#
# Usage:
#   ./scripts/deploy.sh --param-file <path> [--subscription <id|n/a>] [--location <region>]
#
# Arguments:
#   --param-file <path>     Required. Path to a .bicepparam customer environment file.
#   --subscription <id|n/a> Optional. Subscription id, or "n/a" to use the current
#                           az context (default: n/a).
#   --location <region>     Optional. Overrides the resource group location.
#   --help                  Print this help and exit.
#
# Environment variables:
#   VM_ADMIN_PASSWORD     VM local admin password (required when vmBatches is non-empty).
#   RUN_WHATIF            Run a what-if before deploying (default: true).
#   WHATIF_FAILURE_MODE   "fail" or "warn" when what-if fails (default: fail).
#   VERBOSE               Verbose logging and live operation tree (default: false).
#   POLL_INTERVAL         Seconds between deployment status polls (default: 15).
#   MAX_WAIT              Max seconds to wait for the deployment (default: 3600).
#   ARTIFACT_DIR          Directory for JSON artifacts (default: ./artifacts).
#
# Behavior:
#   Resolves customer/environmentName from the compiled parameter file, targets
#   resource group rg-<customer>-<environmentName>, optionally runs what-if,
#   deploys, then polls nested operations and reports failures with a portal link.
# --- /HELP ---

set -Eeuo pipefail

# ----------------------------------------------------------------------------
# Globals & cleanup.
# ----------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." >/dev/null 2>&1 && pwd)"
TEMPLATE_FILE="${REPO_ROOT}/infra/entry.bicep"
TMP_DIR=""

cleanup() {
  local code=$?
  if [[ -n "${TMP_DIR}" && -d "${TMP_DIR}" ]]; then
    rm -rf "${TMP_DIR}"
  fi
  exit "${code}"
}
on_error() {
  err "Failed at line $1 (exit ${2})."
}
trap 'on_error ${LINENO} $?' ERR
trap cleanup EXIT INT TERM

# ----------------------------------------------------------------------------
# Logging helpers.
# ----------------------------------------------------------------------------
ts() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }
info() { printf '%s [INFO]  %s\n' "$(ts)" "$*"; }
warn() { printf '%s [WARN]  %s\n' "$(ts)" "$*" >&2; }
err()  { printf '%s [ERROR] %s\n' "$(ts)" "$*" >&2; }
dbg()  { if [[ "${VERBOSE}" == "true" ]]; then printf '%s [DEBUG] %s\n' "$(ts)" "$*"; fi; }

usage() {
  sed -n '/^# --- HELP ---$/,/^# --- \/HELP ---$/p' "$0" | sed -e 's/^# \{0,1\}//' -e '1d;$d'
}

# ----------------------------------------------------------------------------
# Defaults & argument parsing.
# ----------------------------------------------------------------------------
PARAM_FILE=""
SUBSCRIPTION="n/a"
LOCATION_OVERRIDE=""

RUN_WHATIF="${RUN_WHATIF:-true}"
WHATIF_FAILURE_MODE="${WHATIF_FAILURE_MODE:-fail}"
VERBOSE="${VERBOSE:-false}"
POLL_INTERVAL="${POLL_INTERVAL:-15}"
MAX_WAIT="${MAX_WAIT:-3600}"
ARTIFACT_DIR="${ARTIFACT_DIR:-./artifacts}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --param-file)
      PARAM_FILE="${2:-}"
      shift 2
      ;;
    --subscription)
      SUBSCRIPTION="${2:-n/a}"
      shift 2
      ;;
    --location)
      LOCATION_OVERRIDE="${2:-}"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      err "Unknown argument: $1"
      usage
      exit 2
      ;;
  esac
done

# ----------------------------------------------------------------------------
# Preflight.
# ----------------------------------------------------------------------------
if [[ -z "${PARAM_FILE}" ]]; then
  err "--param-file is required."
  usage
  exit 2
fi
if [[ ! -f "${PARAM_FILE}" ]]; then
  err "Parameter file not found: ${PARAM_FILE}"
  exit 2
fi

command -v az >/dev/null 2>&1 || { err "Azure CLI (az) is required."; exit 3; }
command -v jq >/dev/null 2>&1 || { err "jq is required."; exit 3; }

if [[ "${SUBSCRIPTION}" != "n/a" ]]; then
  info "Setting subscription context: ${SUBSCRIPTION}"
  az account set --subscription "${SUBSCRIPTION}"
fi

TMP_DIR="$(mktemp -d)"
COMPILED="${TMP_DIR}/params.json"

info "Compiling parameter file: ${PARAM_FILE}"
az bicep build-params --file "${PARAM_FILE}" --outfile "${COMPILED}"

CUSTOMER="$(jq -r '.parameters.customer.value // empty' "${COMPILED}")"
ENVIRONMENT_NAME="$(jq -r '.parameters.environmentName.value // empty' "${COMPILED}")"
PARAM_LOCATION="$(jq -r '.parameters.location.value // empty' "${COMPILED}")"
SUBNET_COUNT="$(jq -r '(.parameters.subnets.value // []) | length' "${COMPILED}")"
BATCH_COUNT="$(jq -r '(.parameters.vmBatches.value // []) | length' "${COMPILED}")"

if [[ -z "${CUSTOMER}" || -z "${ENVIRONMENT_NAME}" ]]; then
  err "Parameter file must set 'customer' and 'environmentName'."
  exit 2
fi

# Location resolution: CLI override > param file value > default.
if [[ -n "${LOCATION_OVERRIDE}" ]]; then
  LOCATION="${LOCATION_OVERRIDE}"
elif [[ -n "${PARAM_LOCATION}" ]]; then
  LOCATION="${PARAM_LOCATION}"
else
  LOCATION="eastus"
fi

# Require a password whenever VMs will be deployed.
if [[ "${BATCH_COUNT}" -gt 0 && -z "${VM_ADMIN_PASSWORD:-}" ]]; then
  err "VM_ADMIN_PASSWORD must be set because the environment defines ${BATCH_COUNT} VM batch(es)."
  exit 2
fi

# Re-validate subnetIndex bounds against the compiled subnet count.
INVALID_INDEX="$(jq -r --argjson sc "${SUBNET_COUNT}" \
  '[ (.parameters.vmBatches.value // [])[] | select(.subnetIndex < 0 or .subnetIndex >= $sc) | .name ] | join(", ")' \
  "${COMPILED}")"
if [[ -n "${INVALID_INDEX}" ]]; then
  err "vmBatch subnetIndex out of range (0..$((SUBNET_COUNT - 1))) for batch(es): ${INVALID_INDEX}"
  exit 2
fi

TIMESTAMP="$(date -u +%Y%m%d%H%M%S)"
RESOURCE_GROUP="rg-${CUSTOMER}-${ENVIRONMENT_NAME}"
DEPLOYMENT_NAME="entry-${CUSTOMER}-${ENVIRONMENT_NAME}-${TIMESTAMP}"

mkdir -p "${ARTIFACT_DIR}"

info "Customer:        ${CUSTOMER}"
info "Environment:     ${ENVIRONMENT_NAME}"
info "Resource group:  ${RESOURCE_GROUP}"
info "Location:        ${LOCATION}"
info "Subnets:         ${SUBNET_COUNT}"
info "VM batches:      ${BATCH_COUNT}"
info "Deployment name: ${DEPLOYMENT_NAME}"

# ----------------------------------------------------------------------------
# Ensure resource group.
# ----------------------------------------------------------------------------
info "Ensuring resource group ${RESOURCE_GROUP} exists."
az group create \
  --name "${RESOURCE_GROUP}" \
  --location "${LOCATION}" \
  --tags "customer=${CUSTOMER}" "environmentName=${ENVIRONMENT_NAME}" "managedBy=deploy.sh" \
  --output none

# ----------------------------------------------------------------------------
# Deployment argument assembly (password never echoed).
# ----------------------------------------------------------------------------
COMMON_PARAMS=(--template-file "${TEMPLATE_FILE}" --parameters "${PARAM_FILE}")
if [[ -n "${VM_ADMIN_PASSWORD:-}" ]]; then
  COMMON_PARAMS+=(--parameters "vmAdminPassword=${VM_ADMIN_PASSWORD}")
fi

# ----------------------------------------------------------------------------
# Optional what-if.
# ----------------------------------------------------------------------------
if [[ "${RUN_WHATIF}" == "true" ]]; then
  info "Running what-if analysis."
  WHATIF_FILE="${ARTIFACT_DIR}/whatif-${CUSTOMER}-${ENVIRONMENT_NAME}-${TIMESTAMP}.json"
  if az deployment group what-if \
      --resource-group "${RESOURCE_GROUP}" \
      --name "${DEPLOYMENT_NAME}" \
      "${COMMON_PARAMS[@]}" \
      --no-pretty-print \
      --result-format FullResourcePayload >"${WHATIF_FILE}" 2>"${TMP_DIR}/whatif.err"; then
    info "What-if change summary:"
    jq -r '(.changes // []) | group_by(.changeType) | map("  \(.[0].changeType): \(length)") | .[]' \
      "${WHATIF_FILE}" || true
    info "What-if artifact: ${WHATIF_FILE}"
  else
    cat "${TMP_DIR}/whatif.err" >&2 || true
    if [[ "${WHATIF_FAILURE_MODE}" == "warn" ]]; then
      warn "What-if failed; continuing because WHATIF_FAILURE_MODE=warn."
    else
      err "What-if failed; aborting because WHATIF_FAILURE_MODE=fail."
      exit 4
    fi
  fi
fi

# ----------------------------------------------------------------------------
# Deploy (async) and poll.
# ----------------------------------------------------------------------------
PORTAL_LINK="https://portal.azure.com/#blade/HubsExtension/DeploymentDetailsBlade/id/$(printf '%s' "/subscriptions/SUBSCRIPTION/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.Resources/deployments/${DEPLOYMENT_NAME}" | jq -sRr @uri)"

info "Starting deployment (async)."
az deployment group create \
  --resource-group "${RESOURCE_GROUP}" \
  --name "${DEPLOYMENT_NAME}" \
  "${COMMON_PARAMS[@]}" \
  --no-wait

print_operation_tree() {
  local rg="$1" name="$2" indent="$3"
  local ops
  ops="$(az deployment operation group list --resource-group "${rg}" --name "${name}" --output json 2>/dev/null || echo '[]')"
  printf '%s' "${ops}" | jq -r --arg ind "${indent}" \
    '.[] | "\($ind)- \(.properties.targetResource.resourceType // "?") \(.properties.targetResource.resourceName // "") [\(.properties.provisioningState // "?")]"' || true
  # Recurse into nested deployments.
  local nested
  nested="$(printf '%s' "${ops}" | jq -r '.[] | select(.properties.targetResource.resourceType == "Microsoft.Resources/deployments") | .properties.targetResource.resourceName' 2>/dev/null || true)"
  local child
  for child in ${nested}; do
    if [[ -n "${child}" && "${child}" != "${name}" ]]; then
      print_operation_tree "${rg}" "${child}" "${indent}  "
    fi
  done
}

info "Polling deployment status (interval ${POLL_INTERVAL}s, max ${MAX_WAIT}s)."
ELAPSED=0
STATE="Running"
while true; do
  STATE="$(az deployment group show --resource-group "${RESOURCE_GROUP}" --name "${DEPLOYMENT_NAME}" --query 'properties.provisioningState' --output tsv 2>/dev/null || echo 'Running')"
  dbg "Provisioning state: ${STATE}"
  if [[ "${VERBOSE}" == "true" ]]; then
    info "Operation tree:"
    print_operation_tree "${RESOURCE_GROUP}" "${DEPLOYMENT_NAME}" "  "
  fi
  case "${STATE}" in
    Succeeded|Failed|Canceled)
      break
      ;;
  esac
  if [[ "${ELAPSED}" -ge "${MAX_WAIT}" ]]; then
    err "Timed out after ${MAX_WAIT}s waiting for deployment ${DEPLOYMENT_NAME}."
    err "Portal: ${PORTAL_LINK}"
    exit 5
  fi
  sleep "${POLL_INTERVAL}"
  ELAPSED=$((ELAPSED + POLL_INTERVAL))
done

# ----------------------------------------------------------------------------
# Report failed operations (if any).
# ----------------------------------------------------------------------------
FAILED="$(az deployment operation group list --resource-group "${RESOURCE_GROUP}" --name "${DEPLOYMENT_NAME}" --output json 2>/dev/null || echo '[]')"
FAILED_COUNT="$(printf '%s' "${FAILED}" | jq -r '[ .[] | select(.properties.provisioningState == "Failed") ] | length')"

if [[ "${STATE}" != "Succeeded" || "${FAILED_COUNT}" -gt 0 ]]; then
  err "Deployment ${DEPLOYMENT_NAME} did not succeed (state=${STATE}, failedOps=${FAILED_COUNT})."
  printf '%s' "${FAILED}" | jq -r '
    .[] | select(.properties.provisioningState == "Failed") |
    "  type:        \(.properties.targetResource.resourceType // "?")\n" +
    "  code:        \(.properties.statusMessage.error.code // "?")\n" +
    "  message:     \(.properties.statusMessage.error.message // "?")\n" +
    "  correlation: \(.properties.statusCode // "?")\n" +
    "  timestamp:   \(.properties.timestamp // "?")\n"' >&2 || true
  err "Portal: ${PORTAL_LINK}"
  exit 6
fi

# ----------------------------------------------------------------------------
# Success.
# ----------------------------------------------------------------------------
DEPLOY_JSON="${ARTIFACT_DIR}/deployment-${CUSTOMER}-${ENVIRONMENT_NAME}-${TIMESTAMP}.json"
az deployment group show --resource-group "${RESOURCE_GROUP}" --name "${DEPLOYMENT_NAME}" --output json >"${DEPLOY_JSON}"

OP_TOTAL="$(printf '%s' "${FAILED}" | jq -r 'length')"
info "Deployment succeeded. Operations: ${OP_TOTAL}, failed: ${FAILED_COUNT}."
info "Deployment artifact: ${DEPLOY_JSON}"
info "Key outputs:"
jq -r '.properties.outputs // {} | to_entries[] | "  \(.key): \(.value.value)"' "${DEPLOY_JSON}" || true

info "Done."
