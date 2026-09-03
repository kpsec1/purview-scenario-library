#Requires -Modules @{ ModuleName = 'Microsoft.Graph.Security'; ModuleVersion = '2.25.0' }
<#
.SYNOPSIS
    Validates the scriptable parts of the Departing Employee Data Theft scenario and prints a
    manual-verification checklist for the parts that have no API surface.

.DESCRIPTION
    Read-only. Two categories of check, clearly separated in the output:

    1. AUTOMATED (hard pass/fail, contributes to exit code) - things this scenario's own
       scripts depend on:
       - A Microsoft Graph session is active with the SecurityAlert.Read.All permission
         (probed with a minimal Get-MgSecurityAlertV2 -Top 1 call, not a full pull).
       - The HR resignation CSV at -CsvPath (if provided) has the required schema
         (UserPrincipalName, ResignationDate, LastWorkingDate).

    2. MANUAL (printed as a checklist, never fails the script) - the portal-only
       configuration (policy, priority user group, HR connector, role groups) that has no
       Graph/PowerShell read API to verify programmatically as of this writing. This is not
       a gap in this script - see design.md §6.

    Exits non-zero only if an AUTOMATED check hard-fails. Safe to re-run any number of times;
    makes no mutating calls.

.PARAMETER CsvPath
    Optional path to the resignation CSV that deploy/Send-HrTerminationRecord.ps1 would upload,
    to validate its schema before a real run.

.PARAMETER PolicyName
    Display name used for the manual-checklist output only (no API call is made against it -
    there is nothing to query). Defaults to the name used throughout this scenario's docs.

.EXAMPLE
    Connect-MgGraph -ClientId $AppId -TenantId $TenantId -CertificateThumbprint $Thumbprint
    ./Test-DepartingEmployeeIrmSetup.ps1 -CsvPath ./employee_resignations.csv

.NOTES
    Grounded in Microsoft Learn - see deploy/Export-InsiderRiskAlerts.ps1 .NOTES for the Graph
    API references this script's automated check relies on.
#>
[CmdletBinding()]
param(
    [Parameter()]
    [string]$CsvPath,

    [Parameter()]
    [string]$PolicyName = 'Departing Employee Data Theft'
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
    # Best-effort heuristic, not a hard grounded fact: AuthType/Scopes population on the
    # MgContext object can vary by Microsoft.Graph.Authentication module version - VERIFY
    # against the installed module version if this warns unexpectedly. The real proof is the
    # Get-MgSecurityAlertV2 call below, which fails loudly if the permission isn't actually granted.
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

if ($CsvPath) {
    if (Test-Path -LiteralPath $CsvPath -PathType Leaf) {
        $rows = Import-Csv -LiteralPath $CsvPath
        $requiredColumns = @('UserPrincipalName', 'ResignationDate', 'LastWorkingDate')
        $actualColumns = if ($rows.Count -gt 0) { $rows[0].PSObject.Properties.Name } else { @() }
        $missingColumns = $requiredColumns | Where-Object { $_ -notin $actualColumns }
        Test-Check -Description "CsvPath '$CsvPath' has all required columns ($($requiredColumns -join ', '))" `
            -Condition ($missingColumns.Count -eq 0)
        Test-Check -Description "CsvPath '$CsvPath' has at least one data row" -Condition ($rows.Count -gt 0)
    }
    else {
        Test-Check -Description "CsvPath '$CsvPath' exists" -Condition $false
    }
}
else {
    Write-Host '  [SKIP] CSV schema check - no -CsvPath supplied.' -ForegroundColor DarkGray
}

Write-Host "`n=== MANUAL VERIFICATION CHECKLIST (no API surface exists to automate these - design.md §6) ===" -ForegroundColor Cyan
$manualChecklist = @(
    "Purview portal > Insider Risk Management > Policies: policy '$PolicyName' exists, uses the 'Data theft by departing users' template, and is in an active (not draft/disabled) state."
    "Policy's triggering events include both the HR connector resignation signal AND 'User account deleted from Microsoft Entra ID' as a fallback (design.md §6)."
    "Purview portal > Settings > Data connectors: the HR connector shows a recent successful import in its log (matches the schedule deploy/Send-HrTerminationRecord.ps1 runs on)."
    "Purview portal > Settings > Roles and groups: at least one user is a member of 'Insider Risk Management' or 'Insider Risk Management Admins' (avoid a zero-administrator state)."
    "If a priority user group was configured per README.md §8: confirm its membership is current and reviewers are assigned."
    "Deployed indicators/thresholds match deploy/policy/departing-employee-policy-manifest.json (diff manually - the manifest is a reference, not a live query)."
)
$manualChecklist | ForEach-Object { Write-Host "  [ ] $_" -ForegroundColor Yellow }

Write-Host "`n$(if ($script:failures -eq 0) { 'All automated checks passed.' } else { "$script:failures automated check(s) failed." }) Manual checklist above still requires a human to confirm in the portal." `
    -ForegroundColor $(if ($script:failures -eq 0) { 'Green' } else { 'Red' })

if ($script:failures -gt 0) { exit 1 }
