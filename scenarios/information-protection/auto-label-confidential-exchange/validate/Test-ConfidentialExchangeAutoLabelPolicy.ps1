#Requires -Version 7.0
<#
.SYNOPSIS
    Verifies the "Confidentiality - Auto-Label PII in Exchange Email" auto-labeling policy and its
    Exchange rule are deployed as expected.

.DESCRIPTION
    Read-only - never modifies any object. Uses Security & Compliance PowerShell Get-* cmdlets to
    check, against the config file:
      1. The target label exists and resolves via Get-Label.
      2. The policy exists, applies that label, and is scoped to an Exchange location.
      3. The rule exists, targets the Exchange workload, and references SIT conditions.
      4. The policy Mode is enforcing (warns, does not fail, if still in a Test* simulation mode).
    Exits non-zero on any hard failure (safe for a CI-style pre-flight). Safe to re-run.

    IMPORTANT - config validation is not match validation: a fully green run proves the policy and
    rule are SHAPED correctly, NOT that any email is actually being labeled. Exchange auto-labeling
    acts on mail IN TRANSIT; a policy in simulation, or one that no matching mail has flowed through,
    looks identical to a working one from this script's point of view. Confirm real matches on the
    Items to review tab in the Purview portal (README.md Sections 7 and 11).

    Connect first with Connect-IPPSSession. A View-Only role that can read label/auto-labeling
    configuration is sufficient.

.PARAMETER ConfigPath
    Path to the config to validate against. Defaults to
    '../deploy/config/auto-label-confidential-exchange.sample.json'.

.EXAMPLE
    Connect-IPPSSession -AppId $AppId -Certificate $Cert -Organization 'contoso.onmicrosoft.com'
    ./Test-ConfidentialExchangeAutoLabelPolicy.ps1
#>
[CmdletBinding()]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$ConfigPath = (Join-Path $PSScriptRoot '../deploy/config/auto-label-confidential-exchange.sample.json')
)

$ErrorActionPreference = 'Stop'
$script:failures = 0
function Test-Check {
    param([string]$Description, [bool]$Condition, [switch]$Warn)
    if ($Condition) { Write-Host "  [PASS] $Description" -ForegroundColor Green }
    elseif ($Warn) { Write-Host "  [WARN] $Description" -ForegroundColor Yellow }
    else { Write-Host "  [FAIL] $Description" -ForegroundColor Red; $script:failures++ }
}

if (-not (Get-Command Get-AutoSensitivityLabelPolicy -ErrorAction SilentlyContinue)) {
    throw "Auto-labeling cmdlets not found. Connect first: Connect-IPPSSession. See docs/automation-surface.md Section 3."
}
if (-not (Test-Path -LiteralPath $ConfigPath)) { throw "Config file not found: $ConfigPath" }
$cfg = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
$policyName = $cfg.policy.name
$labelName = $cfg.policy.applySensitivityLabel

Write-Host "Validating Exchange email auto-labeling policy '$policyName'..." -ForegroundColor Cyan

$label = Get-Label -Identity $labelName -ErrorAction SilentlyContinue
Test-Check -Description "Label '$labelName' exists and resolves via Get-Label" -Condition ($null -ne $label)

$policy = Get-AutoSensitivityLabelPolicy -Identity $policyName -ErrorAction SilentlyContinue
Test-Check -Description "Policy '$policyName' exists" -Condition ($null -ne $policy)
if (-not $policy) {
    Write-Host "`nCannot continue - policy not found. $script:failures check(s) failed." -ForegroundColor Red
    exit 1
}

Test-Check -Description 'Policy applies the expected label' `
    -Condition ($policy.ApplySensitivityLabel -eq $labelName -or ($label -and $policy.ApplySensitivityLabel -eq $label.ImmutableId))

Test-Check -Description 'Policy is scoped to an Exchange location' `
    -Condition ($policy.ExchangeLocation -and @($policy.ExchangeLocation).Count -gt 0)

Test-Check -Description 'Policy Mode is enforcing (Enable), not still in simulation' `
    -Condition ($policy.Mode -eq 'Enable') -Warn

$rule = Get-AutoSensitivityLabelRule -Identity $cfg.rule.name -ErrorAction SilentlyContinue
Test-Check -Description "Rule '$($cfg.rule.name)' exists" -Condition ($null -ne $rule)
if ($rule) {
    Test-Check -Description 'Rule targets the Exchange workload' -Condition ($rule.Workload -contains 'Exchange')
    Test-Check -Description 'Rule references at least one sensitive information type condition' `
        -Condition ($null -ne $rule.ContentContainsSensitiveInformation -and @($rule.ContentContainsSensitiveInformation).Count -gt 0)
}

Write-Host "`nManual checks not automated by this script (see README.md Section 11):" -ForegroundColor Cyan
Write-Host "  - Confirm '$labelName' is not a parent label and its scope includes 'Emails' (Purview portal label list)."
Write-Host "  - Confirm unified audit logging is on (required for simulation results)."
Write-Host "  - Confirm real matches on the policy's 'Items to review' tab - config validation is not match validation."

Write-Host "`n$(if ($script:failures -eq 0) { 'All hard checks passed.' } else { "$script:failures hard check(s) failed." })" `
    -ForegroundColor $(if ($script:failures -eq 0) { 'Green' } else { 'Red' })
if ($script:failures -gt 0) { exit 1 }
