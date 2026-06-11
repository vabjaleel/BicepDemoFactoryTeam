// ----------------------------------------------------------------------------
// Generic fail-fast validation guard.
//
// This module declares NO resources. It exists purely to abort a deployment at
// ARM validation time (before any resource is created) when the caller reports
// validation errors.
//
// Contract:
//   - The caller computes an array of human-readable error strings.
//   - The caller passes `errorCount: any(length(errors))`.
//   - The `any()` wrapper is MANDATORY: it defeats Bicep's static type
//     narrowing of `length([])` to the literal type `0`, which would otherwise
//     raise BCP036 against `@maxValue(0)`. At deploy time ARM still enforces
//     `@maxValue(0)`, so any non-zero error count aborts the deployment.
//   - Real resources `dependsOn` this module so they never start when invalid.
// ----------------------------------------------------------------------------

@description('Logical scope label used in error reporting (e.g. "networking:vnet-x").')
param scope string

@description('Validation error messages collected by the caller. Empty means valid.')
param errors string[] = []

@minValue(0)
@maxValue(0)
@description('Must resolve to 0. Pass any(length(errors)) so a non-zero count aborts deployment.')
param errorCount int

@description('True when validation passed (ARM enforces errorCount == 0).')
output validated bool = errorCount == 0

@description('Echoes the validation scope.')
output scope string = scope

@description('Echoes the collected errors (empty when valid).')
output errors string[] = errors
