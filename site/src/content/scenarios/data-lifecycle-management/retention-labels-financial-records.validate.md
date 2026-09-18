---
part: "validate"
parent: "data-lifecycle-management/retention-labels-financial-records"
---
Run these checks after deployment to confirm the control is working as designed.


#### `Test-FinancialRecordsRetention.ps1`

```powershell
#Requires -Version 7.0
<#
.SYNOPSIS
    Verifies the financial-records retention label, auto-apply policy, and rule exist and are
    configured as expected (label retention/record settings, policy enabled + locations, rule binds
    the label).

.DESCRIPTION
    Read-only - never modifies any object. Uses Security & Compliance PowerShell Get-* cmdlets to
    check, against the config file:
      1. The retention label exists with the expected RetentionAction/Duration and record flags.
      2. If the label is NOT a regulatory record: the auto-apply policy exists and is enabled, with
         at least one location, and the policy's rule applies the expected label.
      3. If the label IS a regulatory record: policy/rule checks are skipped by design (this
         scenario's deploy script never creates them for a regulatory record - see README.md
         Section 2/11) - validate distribution instead via the sibling
         publish-labels-for-manual-application scenario's own validate script.
    Exits non-zero on any hard failure (safe for a CI-style pre-flight). Safe to re-run.

    Connect first with Connect-IPPSSession. A View-Only role that can read retention configuration is
    sufficient.

.PARAMETER ConfigPath
    Path to the config to validate against. Defaults to
    '../deploy/config/financial-records-retention.sample.json'.

.EXAMPLE
    Connect-IPPSSession -AppId $AppId -Certificate $Cert -Organization 'contoso.onmicrosoft.com'
    ./Test-FinancialRecordsRetention.ps1
#>
[CmdletBinding()]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$ConfigPath = (Join-Path $PSScriptRoot '../deploy/config/financial-records-retention.sample.json')
)

$ErrorActionPreference = 'Stop'
$script:failures = 0
function Test-Check {
    param([string]$Description, [bool]$Condition, [switch]$Warn)
    if ($Condition) { Write-Host "  [PASS] $Description" -ForegroundColor Green }
    elseif ($Warn) { Write-Host "  [WARN] $Description" -ForegroundColor Yellow }
    else { Write-Host "  [FAIL] $Description" -ForegroundColor Red; $script:failures++ }
}

if (-not (Get-Command Get-ComplianceTag -ErrorAction SilentlyContinue)) {
    throw "Retention cmdlets not found. Connect first: Connect-IPPSSession. See docs/automation-surface.md Section 3."
}
if (-not (Test-Path -LiteralPath $ConfigPath)) { throw "Config file not found: $ConfigPath" }
$cfg = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json

Write-Host "Validating financial-records retention ('$($cfg.label.name)' / '$($cfg.policy.name)')..." -ForegroundColor Cyan

# Label
$label = Get-ComplianceTag -Identity $cfg.label.name -ErrorAction SilentlyContinue
Test-Check -Description "Retention label '$($cfg.label.name)' exists" -Condition ($null -ne $label)
if ($label) {
    Test-Check -Description "  RetentionAction is '$($cfg.label.retentionAction)' (current: $($label.RetentionAction))" `
        -Condition ("$($label.RetentionAction)" -eq "$($cfg.label.retentionAction)")
    if ("$($cfg.label.retentionDurationDays)" -ne 'Unlimited') {
        Test-Check -Description "  RetentionDuration is $($cfg.label.retentionDurationDays) days (current: $($label.RetentionDuration))" `
            -Condition ("$($label.RetentionDuration)" -eq "$($cfg.label.retentionDurationDays)") -Warn
    }
    if ($cfg.label.regulatory) {
        Test-Check -Description "  Label is a regulatory record (IsRegulatory/Regulatory true)" `
            -Condition ([bool]$label.IsRegulatory -or [bool]$label.Regulatory) -Warn
    }
    if ($cfg.label.isRecordLabel -or $cfg.label.regulatory) {
        Test-Check -Description "  Label is a record label" -Condition ([bool]$label.IsRecordLabel) -Warn
    }
}

if ($cfg.label.regulatory) {
    Write-Host "`n  Label is configured as a REGULATORY RECORD - this scenario's deploy script does NOT create an" -ForegroundColor Cyan
    Write-Host "  auto-apply policy/rule for it by design (Microsoft doesn't support that combination)." -ForegroundColor Cyan
    Write-Host "  Skipping policy/rule checks. Validate distribution instead via" -ForegroundColor Cyan
    Write-Host "  scenarios/data-lifecycle-management/publish-labels-for-manual-application/validate/Test-PublishRetentionLabelPolicy.ps1" -ForegroundColor Cyan
}
else {
    # Policy
    $policy = Get-RetentionCompliancePolicy -Identity $cfg.policy.name -ErrorAction SilentlyContinue
    Test-Check -Description "Auto-apply policy '$($cfg.policy.name)' exists" -Condition ($null -ne $policy)
    if ($policy) {
        Test-Check -Description "  Policy is enabled" -Condition ([bool]$policy.Enabled) -Warn
        $hasLoc = (@($policy.SharePointLocation).Count -gt 0) -or (@($policy.ExchangeLocation).Count -gt 0) -or (@($policy.OneDriveLocation).Count -gt 0)
        Test-Check -Description "  Policy has at least one location" -Condition $hasLoc
        if ($policy.DistributionStatus) { Write-Host "    Distribution status: $($policy.DistributionStatus)" -ForegroundColor Cyan }
    }

    # Rule
    $rule = Get-RetentionComplianceRule -Policy $cfg.policy.name -ErrorAction SilentlyContinue | Select-Object -First 1
    Test-Check -Description "Auto-apply rule exists on the policy" -Condition ($null -ne $rule)
    if ($rule) {
        Test-Check -Description "  Rule applies label '$($cfg.label.name)' (current: $($rule.ApplyComplianceTag))" `
            -Condition ("$($rule.ApplyComplianceTag)" -eq "$($cfg.label.name)")
    }
}

Write-Host "`n  Note: auto-apply can take up to 7 days to label content; confirm actual labeling in the portal (Records Management / Data Lifecycle Management) and via content search." -ForegroundColor Cyan
Write-Host "$(if ($script:failures -eq 0) { 'All hard checks passed.' } else { "$script:failures hard check(s) failed." })" `
    -ForegroundColor $(if ($script:failures -eq 0) { 'Green' } else { 'Red' })
if ($script:failures -gt 0) { exit 1 }
```