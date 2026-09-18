---
part: "validate"
parent: "data-lifecycle-management/publish-labels-for-manual-application"
---
Run these checks after deployment to confirm the control is working as designed.


#### `Test-PublishRetentionLabelPolicy.ps1`

```powershell
#Requires -Version 7.0
<#
.SYNOPSIS
    Verifies the retention label exists, the publish policy exists/enabled/has locations, and its
    rule publishes the expected label.

.DESCRIPTION
    Read-only - never modifies any object. Uses Security & Compliance PowerShell Get-* cmdlets to
    check, against the config file:
      1. The retention label exists (this scenario never creates it).
      2. The publish policy exists and is enabled, with at least one location.
      3. The policy's rule publishes the expected label (-PublishComplianceTag).
    Exits non-zero on any hard failure (safe for a CI-style pre-flight). Safe to re-run.

    Connect first with Connect-IPPSSession. A View-Only role that can read retention configuration
    is sufficient.

.PARAMETER ConfigPath
    Path to the config to validate against. Defaults to
    '../deploy/config/publish-financial-records-label.sample.json'.

.EXAMPLE
    Connect-IPPSSession -AppId $AppId -Certificate $Cert -Organization 'contoso.onmicrosoft.com'
    ./Test-PublishRetentionLabelPolicy.ps1
#>
[CmdletBinding()]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$ConfigPath = (Join-Path $PSScriptRoot '../deploy/config/publish-financial-records-label.sample.json')
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

Write-Host "Validating publish label policy ('$($cfg.label.name)' / '$($cfg.policy.name)')..." -ForegroundColor Cyan

# Label (this scenario never creates it - existence is the only check that makes sense here)
$label = Get-ComplianceTag -Identity $cfg.label.name -ErrorAction SilentlyContinue
Test-Check -Description "Retention label '$($cfg.label.name)' exists" -Condition ($null -ne $label)
if ($label) {
    if ($label.Regulatory -or $label.IsRegulatory) {
        Write-Host "    Label is a REGULATORY RECORD - publishing is its only supported distribution path." -ForegroundColor Cyan
    }
}

# Policy
$policy = Get-RetentionCompliancePolicy -Identity $cfg.policy.name -ErrorAction SilentlyContinue
Test-Check -Description "Publish policy '$($cfg.policy.name)' exists" -Condition ($null -ne $policy)
if ($policy) {
    Test-Check -Description "  Policy is enabled" -Condition ([bool]$policy.Enabled) -Warn
    $hasLoc = (@($policy.SharePointLocation).Count -gt 0) -or (@($policy.ExchangeLocation).Count -gt 0) -or `
        (@($policy.OneDriveLocation).Count -gt 0) -or (@($policy.ModernGroupLocation).Count -gt 0)
    Test-Check -Description "  Policy has at least one location" -Condition $hasLoc
    if ($policy.DistributionStatus) { Write-Host "    Distribution status: $($policy.DistributionStatus)" -ForegroundColor Cyan }
}

# Rule
$rule = Get-RetentionComplianceRule -Policy $cfg.policy.name -ErrorAction SilentlyContinue | Select-Object -First 1
Test-Check -Description "Publish rule exists on the policy" -Condition ($null -ne $rule)
if ($rule) {
    Test-Check -Description "  Rule publishes label '$($cfg.label.name)' (current: $($rule.PublishComplianceTag))" `
        -Condition ("$($rule.PublishComplianceTag)" -eq "$($cfg.label.name)")
}

Write-Host "`n  Note: publishing typically takes under a day for SharePoint/OneDrive and up to 7 days for Exchange (mailbox needs >= 10 MB). Confirm the label actually appears in the Outlook/SharePoint/OneDrive label picker before relying on manual application." -ForegroundColor Cyan
Write-Host "$(if ($script:failures -eq 0) { 'All hard checks passed.' } else { "$script:failures hard check(s) failed." })" `
    -ForegroundColor $(if ($script:failures -eq 0) { 'Green' } else { 'Red' })
if ($script:failures -gt 0) { exit 1 }
```