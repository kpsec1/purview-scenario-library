---
part: "validate"
parent: "adaptive-protection/dynamic-risk-dlp-enforcement"
---
Run these checks after deployment to confirm the control is working as designed.


#### `Test-AdaptiveProtectionDlpPolicy.ps1`

```powershell
#Requires -Modules @{ ModuleName = 'ExchangeOnlineManagement'; ModuleVersion = '3.2.0' }
<#
.SYNOPSIS
    Verifies the "Adaptive Protection - Teams and Exchange DLP (Custom)" DLP policy is deployed
    correctly, and prints a manual checklist for the portal-only prerequisites this script cannot
    check via API.

.DESCRIPTION
    Read-only validation script - never modifies policy state. Automated checks:
      1. The policy exists and is scoped to Exchange and Teams locations.
      2. Both rules exist with the expected priority order.
      3. Rule 0 (Elevated) uses the correct -SharedByIRMUserRisk GUID and blocks access.
      4. Rule 1 (Moderate/Minor) uses the correct GUIDs and does not block access.
      5. The policy Mode matches what was requested (warns, does not fail, if still in a Test* mode).
    Exits with a non-zero code if any hard check fails, so this script is safe to wire into a
    CI-style pre-flight or a post-deploy smoke test. Safe to re-run any number of times.

    Then prints a manual checklist for everything this script has no API to query: whether
    Adaptive Protection is actually turned on, whether insider risk levels are defined, and
    whether a feeder Insider Risk Management policy is in scope. A policy that passes every
    automated check below can still silently match zero users if any of those three portal-only
    prerequisites aren't met - see README.md Section 7 for how to confirm them end-to-end.

.PARAMETER PolicyName
    Name of the DLP policy to validate. Must match the -PolicyName used at deploy time.

.EXAMPLE
    Connect-IPPSSession -AppId $AppId -Certificate $Cert -Organization $TenantDomain
    ./Test-AdaptiveProtectionDlpPolicy.ps1
#>
[CmdletBinding()]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$PolicyName = 'Adaptive Protection - Teams and Exchange DLP (Custom)'
)

$ErrorActionPreference = 'Stop'
$script:failures = 0

# Fixed, Microsoft-documented GUIDs for the three Adaptive Protection insider risk levels.
$riskLevelElevated = 'FCB9FA93-6269-4ACF-A756-832E79B36A2A'
$riskLevelModerate = '797C4446-5C73-484F-8E58-0CCA08D6DF6C'
$riskLevelMinor = '75A4318B-94A2-4323-BA42-2CA6DB29AAFE'

function Test-Check {
    param(
        [string]$Description,
        [bool]$Condition,
        [switch]$Warn
    )
    if ($Condition) {
        Write-Host "  [PASS] $Description" -ForegroundColor Green
    }
    elseif ($Warn) {
        Write-Host "  [WARN] $Description" -ForegroundColor Yellow
    }
    else {
        Write-Host "  [FAIL] $Description" -ForegroundColor Red
        $script:failures++
    }
}

if (-not (Get-Command Get-DlpCompliancePolicy -ErrorAction SilentlyContinue)) {
    throw 'No Security & Compliance PowerShell session found. Run Connect-IPPSSession first (see docs/automation-surface.md).'
}

Write-Host "Validating policy '$PolicyName'..." -ForegroundColor Cyan

$policy = Get-DlpCompliancePolicy -Identity $PolicyName -ErrorAction SilentlyContinue
Test-Check -Description "Policy '$PolicyName' exists" -Condition ($null -ne $policy)
if (-not $policy) {
    Write-Host "`nCannot continue - policy not found. $script:failures check(s) failed." -ForegroundColor Red
    exit 1
}

Test-Check -Description 'Policy is scoped to Exchange Online' `
    -Condition ($policy.ExchangeLocation -and $policy.ExchangeLocation.Count -gt 0)
Test-Check -Description 'Policy is scoped to Microsoft Teams' `
    -Condition ($policy.TeamsLocation -and $policy.TeamsLocation.Count -gt 0)

Test-Check -Description 'Policy Mode is enforcing (Enable), not still in simulation' `
    -Condition ($policy.Mode -eq 'Enable') -Warn

$rules = Get-DlpComplianceRule -Policy $PolicyName -ErrorAction SilentlyContinue
$ruleBlock = $rules | Where-Object { $_.Name -eq 'AdaptiveProtection-Block-Elevated' }
$ruleAudit = $rules | Where-Object { $_.Name -eq 'AdaptiveProtection-Audit-ModerateMinor' }

Test-Check -Description 'Rule AdaptiveProtection-Block-Elevated exists' -Condition ($null -ne $ruleBlock)
Test-Check -Description 'Rule AdaptiveProtection-Audit-ModerateMinor exists' -Condition ($null -ne $ruleAudit)

if ($ruleBlock) {
    Test-Check -Description 'Elevated-block rule is scoped only to the Elevated risk-level GUID' `
        -Condition ($ruleBlock.SharedByIRMUserRisk -contains $riskLevelElevated -and $ruleBlock.SharedByIRMUserRisk.Count -eq 1)
    Test-Check -Description 'Elevated-block rule blocks access (BlockAccess = true)' `
        -Condition ($ruleBlock.BlockAccess -eq $true)
    Test-Check -Description 'Elevated-block rule has priority 0 (evaluated first)' `
        -Condition ($ruleBlock.Priority -eq 0)
}

if ($ruleAudit) {
    Test-Check -Description 'Moderate/Minor-audit rule is scoped to exactly the Moderate and Minor GUIDs' `
        -Condition ($ruleAudit.SharedByIRMUserRisk -contains $riskLevelModerate -and $ruleAudit.SharedByIRMUserRisk -contains $riskLevelMinor -and $ruleAudit.SharedByIRMUserRisk.Count -eq 2)
    Test-Check -Description 'Moderate/Minor-audit rule does not block access' `
        -Condition ($ruleAudit.BlockAccess -ne $true)
    Test-Check -Description 'Moderate/Minor-audit rule still generates an alert for visibility' `
        -Condition ($null -ne $ruleAudit.GenerateAlert -and $ruleAudit.GenerateAlert.Count -gt 0)
}

Write-Host "`n$(if ($script:failures -eq 0) { 'All hard checks passed.' } else { "$script:failures hard check(s) failed." })" `
    -ForegroundColor $(if ($script:failures -eq 0) { 'Green' } else { 'Red' })

Write-Host "`n--- Manual checklist (no API surface exists to check these) ---" -ForegroundColor Cyan
Write-Host '  [ ] Adaptive Protection is turned ON (Purview portal > Insider Risk Management > Adaptive protection > Adaptive Protection settings).'
Write-Host '  [ ] Elevated/Moderate/Minor insider risk levels are defined and match deploy/policy/adaptive-protection-config-manifest.json.'
Write-Host '  [ ] At least one Insider Risk Management policy is included in Adaptive Protection scope (e.g. scenarios/insider-risk/departing-employee-data-theft, or the Data leaks template).'
Write-Host '  [ ] Purview portal > Insider Risk Management > Adaptive protection > Data Loss Prevention tab lists this policy - confirms the portal itself recognizes the SharedByIRMUserRisk condition as an Adaptive Protection binding, not just a syntactically valid rule.'
Write-Host '  [ ] At least 36 hours have passed since Adaptive Protection was enabled before concluding a pilot user was not correctly matched (see design.md Section 5).'
Write-Host '  [ ] End-to-end functional test (non-production account only): assign a test user a confirmed insider risk level (or wait for a real detection from the feeder IRM policy), then have that account attempt to share content externally via Exchange or Teams. Confirm the expected rule (block for Elevated, audit for Moderate/Minor) fires and an alert appears in the DLP Alerts dashboard.'

if ($script:failures -gt 0) { exit 1 }
```