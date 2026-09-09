#Requires -Modules @{ ModuleName = 'Microsoft.Graph.Applications'; ModuleVersion = '2.25.0' }
<#
.SYNOPSIS
    Removes a superseded or expired client secret from the HR-connector Entra app registration
    that deploy/Register-HrConnectorApp.ps1 creates, closing the manual-cleanup gap that script's
    own .NOTES and README.md §11 flag: "-RotateSecret adds a secret, it doesn't replace one."

.DESCRIPTION
    Resolves a follow-up tracked in PROGRESS.md. Microsoft Entra applications support multiple
    concurrent client secrets by design, so Register-HrConnectorApp.ps1 -RotateSecret always adds
    a new one alongside any existing (even already-expired) ones rather than replacing it - a
    correct, documented Microsoft Graph behavior, not a bug in that script. Left alone, a
    superseded secret is a standing, unnecessary credential-leak surface until someone remembers
    to delete it by hand in the Microsoft Entra admin center. This script makes that cleanup a
    scripted, idempotent, -WhatIf-capable step instead.

    Two removal modes (mutually exclusive - see .PARAMETER RemoveExpired / .PARAMETER KeyId):

      -RemoveExpired (default, safe-by-construction): removes every password credential whose
      EndDateTime has already passed. An already-expired secret cannot authenticate
      Send-HrTerminationRecord.ps1 regardless of whether this script deletes it, so this mode
      never reduces the app's *working* secret count - it only deletes dead weight.

      -KeyId <guid>: removes one specific password credential by its KeyId (from
      Get-MgApplication's PasswordCredentials, or the value Register-HrConnectorApp.ps1's
      -RotateSecret run reported for the *previous* secret before rotation). Unlike
      -RemoveExpired, this can target a credential that has NOT yet expired - e.g. an operator
      who wants to force-retire a secret immediately after confirming the new one works, without
      waiting for the old one's natural expiry. Because this can remove a still-valid secret,
      the script refuses to proceed if doing so would leave the application with zero unexpired
      secrets, unless -Force is also passed - that combination would silently break
      Send-HrTerminationRecord.ps1's next scheduled run with no working credential left.

    Calls Microsoft Graph's application: removePassword action via Remove-MgApplicationPassword
    (Microsoft.Graph.Applications, v1.0 - confirmed current, non-beta, on this run against
    Microsoft Learn). -ApplicationId takes the application's OBJECT ID (aliased ObjectId in this
    cmdlet, same as Add-MgApplicationPassword in Register-HrConnectorApp.ps1) - not its AppId
    (client ID). This script always resolves and passes $app.Id, never $app.AppId.

    Idempotent: re-running with -RemoveExpired after there is nothing left to expire, or with a
    -KeyId that no longer exists on the application, reports "nothing to do" and exits cleanly
    rather than erroring.

.PARAMETER DisplayName
    Display name of the app registration to clean up. Must match the -DisplayName used with
    deploy/Register-HrConnectorApp.ps1 (defaults to the same value).

.PARAMETER RemoveExpired
    Remove every password credential that has already expired (EndDateTime in the past). Safe by
    construction - see .DESCRIPTION. This is the default, lower-risk mode.

.PARAMETER KeyId
    Remove one specific password credential by its KeyId, regardless of whether it has expired
    yet. Mutually exclusive with -RemoveExpired. Requires -Force if the targeted credential has
    not yet expired and removing it would leave zero unexpired secrets on the application.

.PARAMETER Force
    Required in addition to -KeyId when the targeted credential is still unexpired AND removing
    it would leave the application with no working secret. Never required for -RemoveExpired,
    which by definition only removes already-dead credentials.

.PARAMETER WhatIf
    Standard PowerShell ShouldProcess dry-run. Reports which credential(s) would be removed
    without calling Microsoft Graph to change anything.

.EXAMPLE
    Connect-MgGraph -Scopes 'Application.ReadWrite.All'
    ./Remove-HrConnectorAppSecret.ps1 -RemoveExpired -WhatIf

    Dry run: lists which already-expired secrets would be deleted, calls nothing.

.EXAMPLE
    Connect-MgGraph -Scopes 'Application.ReadWrite.All'
    ./Remove-HrConnectorAppSecret.ps1 -RemoveExpired

    Routine cleanup: deletes every already-expired secret on the app. Safe to run on a schedule
    or immediately after confirming a -RotateSecret run's new secret works in production.

.EXAMPLE
    Connect-MgGraph -Scopes 'Application.ReadWrite.All'
    ./Remove-HrConnectorAppSecret.ps1 -KeyId '5b1a1e3e-8f21-4a6c-9d3b-1a2b3c4d5e6f' -Force

    Force-retires one specific still-valid secret immediately (e.g. suspected exposure) even
    though it has not expired yet, accepting that this may leave the app with fewer working
    secrets - only needed if that secret is also the last unexpired one.

.NOTES
    Grounded in Microsoft Learn (verify before production use):
    - Remove-MgApplicationPassword (Microsoft.Graph.Applications, v1.0 - confirmed current, not
      the beta-only Remove-MgBetaApplicationPassword; -ApplicationId is aliased ObjectId and
      takes the application's object ID; -KeyId's own documented parameter type is
      System.String, not System.Guid, despite the underlying Graph resource property's Edm type
      being Guid - this script's own -KeyId parameter is typed [string] with a GUID-format
      ValidatePattern to match the cmdlet's actual signature exactly, rather than declaring
      [guid] and risking an unnecessary type-conversion mismatch against what
      Get-MgApplication's PasswordCredentials.KeyId returns at runtime):
      https://learn.microsoft.com/powershell/module/microsoft.graph.applications/remove-mgapplicationpassword
    - application: removePassword (the underlying Graph REST action - `POST /applications/{id}/
      removePassword` with a `{"keyId": "<guid>"}` body; the REST reference documents addressing
      by the object ID path segment only, so this script always resolves and passes $app.Id, the
      same object ID Register-HrConnectorApp.ps1's Add-MgApplicationPassword call already uses):
      https://learn.microsoft.com/graph/api/application-removepassword
    - passwordCredential resource type (keyId's Edm type is Guid at the REST layer; endDateTime
      is the expiry this script's -RemoveExpired mode filters on):
      https://learn.microsoft.com/graph/api/resources/passwordcredential
    - Get-MgApplication / Add-MgApplicationPassword: see deploy/Register-HrConnectorApp.ps1
      .NOTES for these references (unchanged by this script).

    This script never prints or logs a secret's plaintext value - it only ever handles KeyId
    (a non-secret Guid identifier) and EndDateTime, never SecretText.
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High', DefaultParameterSetName = 'Expired')]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$DisplayName = 'Purview HR Connector - Insider Risk Management (single-purpose)',

    [Parameter(ParameterSetName = 'Expired')]
    [switch]$RemoveExpired,

    [Parameter(Mandatory, ParameterSetName = 'Specific')]
    [ValidatePattern('^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$')]
    [string]$KeyId,

    [Parameter(ParameterSetName = 'Specific')]
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

if ($PSCmdlet.ParameterSetName -eq 'Expired' -and -not $RemoveExpired) {
    throw 'Specify -RemoveExpired to delete all already-expired secrets, or -KeyId <guid> to remove one specific secret.'
}

$graphContext = Get-MgContext
if (-not $graphContext) {
    throw "Not connected to Microsoft Graph. Run Connect-MgGraph -Scopes 'Application.ReadWrite.All' first."
}
if ($graphContext.Scopes -notcontains 'Application.ReadWrite.All') {
    Write-Warning "Current Graph session does not list 'Application.ReadWrite.All' in its granted scopes - the call below will fail if it wasn't actually consented. Reconnect with Connect-MgGraph -Scopes 'Application.ReadWrite.All' if so."
}

$app = Get-MgApplication -Filter "displayName eq '$DisplayName'" `
    -Property Id, DisplayName, AppId, PasswordCredentials
if (-not $app) {
    throw "No application named '$DisplayName' found - nothing to clean up. Has deploy/Register-HrConnectorApp.ps1 been run yet?"
}
if ($app -is [array]) {
    throw "Multiple applications named '$DisplayName' exist (ObjectIds: $($app.Id -join ', ')) - resolve the duplicate manually before re-running this script."
}

$now = Get-Date
$credentials = @($app.PasswordCredentials)
$validCredentials = @($credentials | Where-Object { $_.EndDateTime -gt $now })

if ($PSCmdlet.ParameterSetName -eq 'Expired') {
    $targets = @($credentials | Where-Object { $_.EndDateTime -le $now })
    if ($targets.Count -eq 0) {
        Write-Host "No expired secrets found on '$DisplayName' ($($credentials.Count) total, all unexpired). Nothing to do." -ForegroundColor Green
        return
    }
}
else {
    $target = $credentials | Where-Object { $_.KeyId -eq $KeyId }
    if (-not $target) {
        Write-Host "No secret with KeyId '$KeyId' found on '$DisplayName'. Nothing to do (already removed, or wrong KeyId)." -ForegroundColor Green
        return
    }
    $isTargetValid = $target.EndDateTime -gt $now
    $wouldOrphanApp = $isTargetValid -and $validCredentials.Count -le 1
    if ($wouldOrphanApp -and -not $Force) {
        throw "KeyId '$KeyId' is the application's only unexpired secret - removing it would leave Send-HrTerminationRecord.ps1 with no working credential. Re-run with -Force if this is intentional (e.g. suspected secret exposure), after confirming a replacement secret is already deployed."
    }
    $targets = @($target)
}

foreach ($cred in $targets) {
    $label = if ($cred.DisplayName) { $cred.DisplayName } else { '(no label)' }
    $status = if ($cred.EndDateTime -le $now) { "expired $($cred.EndDateTime.ToString('u'))" } else { "VALID until $($cred.EndDateTime.ToString('u'))" }

    if ($WhatIfPreference) {
        Write-Host "[WhatIf] Would remove secret KeyId=$($cred.KeyId) ('$label', $status) from '$DisplayName'." -ForegroundColor Yellow
        continue
    }

    if (-not $PSCmdlet.ShouldProcess("$DisplayName (KeyId=$($cred.KeyId), $status)", 'Remove client secret')) {
        continue
    }

    Write-Host "Removing secret KeyId=$($cred.KeyId) ('$label', $status)..." -NoNewline
    # -ApplicationId takes the object ID (aliased ObjectId), matching Register-HrConnectorApp.ps1's
    # Add-MgApplicationPassword usage - never $app.AppId.
    Remove-MgApplicationPassword -ApplicationId $app.Id -KeyId $cred.KeyId | Out-Null
    Write-Host ' done.' -ForegroundColor Green
}

if ($WhatIfPreference) {
    Write-Host 'WhatIf: no Microsoft Graph write call made.' -ForegroundColor Yellow
    return
}

$remaining = @((Get-MgApplication -ApplicationId $app.Id -Property PasswordCredentials).PasswordCredentials)
$remainingValid = @($remaining | Where-Object { $_.EndDateTime -gt $now })
Write-Host "`n$($targets.Count) secret(s) removed. $($remainingValid.Count) unexpired secret(s) remain on '$DisplayName'." -ForegroundColor Cyan
if ($remainingValid.Count -eq 0) {
    Write-Warning "No unexpired secrets remain on '$DisplayName' - Send-HrTerminationRecord.ps1's next scheduled run will fail authentication until Register-HrConnectorApp.ps1 -RotateSecret issues a new one."
}
