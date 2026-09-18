---
part: "validate"
parent: "insider-risk/departing-employee-data-theft"
---
Run these checks after deployment to confirm the control is working as designed.


#### `Test-DepartingEmployeeIrmSetup.ps1`

```powershell
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
```

#### `Test-HrConnectorAppRegistration.ps1`

```powershell
#Requires -Modules @{ ModuleName = 'Microsoft.Graph.Applications'; ModuleVersion = '2.25.0' }
<#
.SYNOPSIS
    Validates the HR-connector Entra app registration deploy/Register-HrConnectorApp.ps1
    creates: it exists, has an unexpired secret, and - the hygiene requirement README.md §3
    calls out as load-bearing - still holds NO Microsoft Graph API permissions.

.DESCRIPTION
    Read-only. Never modifies the application, its service principal, or its credentials.

    AUTOMATED checks (contribute to exit code):
      - An application with -DisplayName exists.
      - Its matching service principal exists (Get-MgApplication does not imply one - see
        deploy/Register-HrConnectorApp.ps1's own .DESCRIPTION for why the deploy script
        creates it explicitly).
      - At least one client secret (password credential) exists and is not already expired.
      - No Microsoft Graph API permission has been granted to this app (empty
        RequiredResourceAccess) - this is the specific control the Red Team finding in
        reviews.md and README.md §3's callout depend on staying true. A FAIL here means the
        single-purpose scoping this scenario relies on has been silently widened - by another
        script, a manual portal edit, or an admin adding a permission for an unrelated reason -
        and the blast-radius argument in README.md §3 no longer holds until it's fixed.

    WARN (not a hard failure, printed as a checklist item):
      - A secret expiring within 30 days - a nudge to rotate before README.md §3/§11's
        recommended ~90-day cadence lapses into an actual outage of
        Send-HrTerminationRecord.ps1's scheduled run.
      - One or more already-expired secrets still present on the application - a nudge to run
        deploy/Remove-HrConnectorAppSecret.ps1 -RemoveExpired, since Register-HrConnectorApp.ps1
        -RotateSecret only ever adds a secret, it never deletes the one it superseded.

.PARAMETER DisplayName
    Display name of the app registration to check. Must match the -DisplayName used with
    deploy/Register-HrConnectorApp.ps1 (defaults to the same value).

.PARAMETER SecretExpiryWarningDays
    Warn if the soonest-expiring, still-valid secret expires within this many days. Defaults
    to 30.

.EXAMPLE
    Connect-MgGraph -Scopes 'Application.Read.All'
    ./Test-HrConnectorAppRegistration.ps1

.NOTES
    Grounded in Microsoft Learn - see deploy/Register-HrConnectorApp.ps1 .NOTES for the
    Microsoft.Graph.Applications cmdlet references this script's checks rely on.
#>
[CmdletBinding()]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$DisplayName = 'Purview HR Connector - Insider Risk Management (single-purpose)',

    [Parameter()]
    [ValidateRange(1, 365)]
    [int]$SecretExpiryWarningDays = 30
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

Write-Host "=== AUTOMATED CHECKS: '$DisplayName' ===" -ForegroundColor Cyan

$graphContext = Get-MgContext
Test-Check -Description 'Microsoft Graph session is active' -Condition ($null -ne $graphContext)
if (-not $graphContext) {
    Write-Host "`nRun Connect-MgGraph -Scopes 'Application.Read.All' first." -ForegroundColor Red
    exit 1
}

$app = Get-MgApplication -Filter "displayName eq '$DisplayName'" `
    -Property Id, DisplayName, AppId, PasswordCredentials, RequiredResourceAccess
Test-Check -Description "Application '$DisplayName' exists" -Condition ($null -ne $app)

if ($app) {
    if ($app -is [array]) {
        Test-Check -Description "Exactly one application named '$DisplayName' exists (found $($app.Count) - resolve the duplicate manually)" -Condition $false
        $app = $app[0]
    }

    $sp = Get-MgServicePrincipal -Filter "appId eq '$($app.AppId)'"
    Test-Check -Description 'Matching service principal exists' -Condition ($null -ne $sp)

    $credentials = @($app.PasswordCredentials)
    $now = Get-Date
    $validCredentials = @($credentials | Where-Object { $_.EndDateTime -gt $now })
    Test-Check -Description "At least one unexpired client secret exists (found $($validCredentials.Count) of $($credentials.Count) total)" `
        -Condition ($validCredentials.Count -gt 0)

    if ($validCredentials.Count -gt 0) {
        $soonestExpiry = ($validCredentials | Sort-Object EndDateTime | Select-Object -First 1).EndDateTime
        $daysRemaining = [Math]::Round(($soonestExpiry - $now).TotalDays)
        Test-Check -Description "Soonest-expiring valid secret has more than $SecretExpiryWarningDays day(s) remaining (has $daysRemaining) - rotate with Register-HrConnectorApp.ps1 -RotateSecret if not" `
            -Condition ($daysRemaining -gt $SecretExpiryWarningDays) -Warn
    }

    $expiredCredentials = @($credentials | Where-Object { $_.EndDateTime -le $now })
    Test-Check -Description "No already-expired secrets left on the application (found $($expiredCredentials.Count)) - clean up superseded secrets with Remove-HrConnectorAppSecret.ps1 -RemoveExpired" `
        -Condition ($expiredCredentials.Count -eq 0) -Warn

    $grantedPermissions = @($app.RequiredResourceAccess)
    Test-Check -Description 'No Microsoft Graph API permission is granted to this app (RequiredResourceAccess is empty - README.md §3 hygiene requirement)' `
        -Condition ($grantedPermissions.Count -eq 0)
    if ($grantedPermissions.Count -gt 0) {
        Write-Host "    Found $($grantedPermissions.Count) resource access entr(y/ies) - review in the Microsoft Entra admin center (App registrations > this app > API permissions) and remove any that aren't the HR-connector ingestion webhook's own OAuth resource." -ForegroundColor Red
    }
}

Write-Host "`n$(if ($script:failures -eq 0) { 'All automated checks passed.' } else { "$script:failures automated check(s) failed." })" `
    -ForegroundColor $(if ($script:failures -eq 0) { 'Green' } else { 'Red' })

if ($script:failures -gt 0) { exit 1 }
```