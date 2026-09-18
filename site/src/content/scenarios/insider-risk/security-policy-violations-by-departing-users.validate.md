---
part: "validate"
parent: "insider-risk/security-policy-violations-by-departing-users"
---
Run these checks after deployment to confirm the control is working as designed.


#### `Test-SecurityViolationIrmSetup.ps1`

```powershell
#Requires -Modules @{ ModuleName = 'Microsoft.Graph.Security'; ModuleVersion = '2.25.0' }
<#
.SYNOPSIS
    Validates the scriptable parts of the Security Policy Violations by Departing Users scenario
    and prints a manual-verification checklist for the parts that have no API surface.

.DESCRIPTION
    Read-only. Two categories of check, clearly separated in the output:

    1. AUTOMATED (hard pass/fail, contributes to exit code) - a Microsoft Graph session is active
       with the SecurityAlert.Read.All permission (probed with a minimal Get-MgSecurityAlertV2
       -Top 1 call, not a full pull) - the same dependency
       Export-SecurityViolationInsiderRiskAlerts.ps1 has.

    2. MANUAL (printed as a checklist, never fails the script) - the portal-only configuration
       (policy, Defender for Endpoint advanced feature, Intelligent detections triage statuses,
       role groups) that has no Graph/PowerShell read API to verify programmatically as of this
       writing. This is not a gap in this script - see design.md §4.

    Exits non-zero only if an AUTOMATED check hard-fails. Safe to re-run any number of times;
    makes no mutating calls.

.PARAMETER PolicyName
    Display name used for the manual-checklist output only (no API call is made against it -
    there is nothing to query). Defaults to the name used throughout this scenario's docs.

.EXAMPLE
    Connect-MgGraph -ClientId $AppId -TenantId $TenantId -CertificateThumbprint $Thumbprint
    ./Test-SecurityViolationIrmSetup.ps1

.NOTES
    Grounded in Microsoft Learn - see deploy/Export-SecurityViolationInsiderRiskAlerts.ps1 .NOTES
    for the Graph API references this script's automated check relies on.
#>
[CmdletBinding()]
param(
    [Parameter()]
    [string]$PolicyName = 'Security Policy Violations by Departing Users'
)

$ErrorActionPreference = 'Stop'
$script:failures = 0

function Test-Check {
    param([string]$Description, [bool]$Condition, [switch]$Warn)
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

Write-Host "=== AUTOMATED CHECKS ===" -ForegroundColor Cyan

$graphContext = Get-MgContext
Test-Check -Description 'Microsoft Graph session is active' -Condition ($null -ne $graphContext)

if ($graphContext) {
    $hasAlertScope = $graphContext.Scopes -contains 'SecurityAlert.Read.All' -or
                      $graphContext.AuthType -eq 'AppOnly'
    Test-Check -Description 'Session appears app-only or holds SecurityAlert.Read.All (best-effort check; Scopes may not be populated for app-only certificate auth)' `
        -Condition $hasAlertScope -Warn

    try {
        $null = Get-MgSecurityAlertV2 -Top 1 -ErrorAction Stop
        Test-Check -Description 'GET /security/alerts_v2 call succeeds (permission is actually granted, not just requested)' -Condition $true
    }
    catch {
        Test-Check -Description "GET /security/alerts_v2 call succeeds - FAILED: $($_.Exception.Message)" -Condition $false
    }
}

Write-Host "`n=== MANUAL VERIFICATION CHECKLIST (no API surface exists to automate these - design.md §4) ===" -ForegroundColor Cyan
$manualChecklist = @(
    "Purview portal > Insider Risk Management > Policies: policy '$PolicyName' exists, uses the 'Security policy violations by departing users' template, and is in an active (not draft/disabled) state."
    "Microsoft Defender portal > Settings > Endpoints > Advanced features: 'Share endpoint alerts with Microsoft Compliance Center' is ON (README.md §5 Step 2)."
    "Purview portal > Settings > Insider Risk Management > Intelligent detections: at least one Defender for Endpoint alert triage status is selected (README.md §5 Step 3)."
    "Policy's triggering events include the HR connector resignation signal and/or 'User account deleted from Microsoft Entra ID' - AT LEAST ONE must be enabled. Unlike the sibling scenario, this template treats both as optional, so a policy can be created with neither enabled and no error at creation time (README.md §8)."
    "Policy's Indicators page has the 'Microsoft Defender for Endpoint indicators (preview)' category selected."
    "Purview portal > Insider Risk Management > Policies: no 'Your organization doesn't have a Microsoft Defender for Endpoint subscription' or 'Microsoft Defender for Endpoint alerts aren't being shared with the Microsoft Purview portal' policy-health warning is showing (README.md §8)."
    "If departing-employee-data-theft's HR connector is being reused: its import log shows a recent successful run (that scenario's own validate script already checks this - not duplicated here)."
    "Purview portal > Settings > Roles and groups: at least one user is a member of 'Insider Risk Management' or 'Insider Risk Management Admins'."
    "Deployed configuration matches deploy/policy/security-policy-violations-departing-users-policy-manifest.json (diff manually - the manifest is a reference, not a live query)."
)
$manualChecklist | ForEach-Object { Write-Host "  [ ] $_" -ForegroundColor Yellow }

Write-Host "`n$(if ($script:failures -eq 0) { 'All automated checks passed.' } else { "$script:failures automated check(s) failed." }) Manual checklist above still requires a human to confirm in the portal." `
    -ForegroundColor $(if ($script:failures -eq 0) { 'Green' } else { 'Red' })

if ($script:failures -gt 0) { exit 1 }
```