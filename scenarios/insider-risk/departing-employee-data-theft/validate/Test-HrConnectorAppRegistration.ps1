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
