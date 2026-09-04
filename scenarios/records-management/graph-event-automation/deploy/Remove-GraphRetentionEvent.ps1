#Requires -Version 7.0
<#
.SYNOPSIS
    Cleans up Graph records-management retention events and, optionally, the event type - via the
    Microsoft Graph records-management APIs.

.DESCRIPTION
    Deletes retention EVENTS matching the config's event.displayName
    (DELETE /security/triggers/retentionEvents/{id}) and, with -DeleteEventType, the event type
    (DELETE /security/triggerTypes/retentionEventTypes/{id}). Uses Invoke-MgGraphRequest (surface 3);
    real -WhatIf via $PSCmdlet.ShouldProcess.

    !!! DELETING AN EVENT DOES NOT STOP RETENTION !!! A retention event, once fired, has already
    started the retention clock for matching content; deleting the event object is bookkeeping only and
    does NOT reverse or cancel that retention (README.md Section 11 / rollback.md). Use this to tidy up
    event records or remove an unused event type - not as a way to undo a triggered retention period.

    Removing an event type generally requires that no label still references it. Failures are reported,
    not forced.

    Connect first: Connect-MgGraph -Scopes 'RecordsManagement.ReadWrite.All'.

.PARAMETER ConfigPath
    Path to the JSON config. Defaults to the sibling 'config/graph-event-automation.sample.json'.

.PARAMETER DeleteEventType
    Also delete the event type after removing matching events. Without it, only events are removed.

.PARAMETER GraphBaseUri
    Graph base URI. Defaults to 'https://graph.microsoft.com/v1.0'.

.EXAMPLE
    Connect-MgGraph -Scopes 'RecordsManagement.ReadWrite.All'
    ./Remove-GraphRetentionEvent.ps1 -WhatIf

.EXAMPLE
    ./Remove-GraphRetentionEvent.ps1                    # delete matching events only
    ./Remove-GraphRetentionEvent.ps1 -DeleteEventType   # also delete the event type (if unreferenced)

.NOTES
    Grounded in Microsoft Learn (verify before production use):
    - Delete retentionEvent: https://learn.microsoft.com/graph/api/security-retentionevent-delete?view=graph-rest-1.0
    - retentionEventType resource (delete via the triggerTypes/retentionEventTypes collection):
      https://learn.microsoft.com/graph/api/resources/security-retentioneventtype?view=graph-rest-1.0
    - Events can't be cancelled once created: https://learn.microsoft.com/purview/event-driven-retention
    - Equivalent typed SDK cmdlets: Remove-MgSecurityTriggerRetentionEvent,
      Remove-MgSecurityTriggerTypeRetentionEventType (Microsoft.Graph.Security).
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$ConfigPath = (Join-Path $PSScriptRoot 'config/graph-event-automation.sample.json'),

    [Parameter()]
    [switch]$DeleteEventType,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$GraphBaseUri = 'https://graph.microsoft.com/v1.0'
)

$ErrorActionPreference = 'Stop'

function Assert-MgConnected {
    if (-not (Get-Command Invoke-MgGraphRequest -ErrorAction SilentlyContinue)) {
        throw "Microsoft Graph PowerShell SDK not found. Install Microsoft.Graph and run Connect-MgGraph -Scopes 'RecordsManagement.ReadWrite.All'."
    }
    if (-not (Get-MgContext -ErrorAction SilentlyContinue)) {
        throw "Not connected to Microsoft Graph. Run Connect-MgGraph -Scopes 'RecordsManagement.ReadWrite.All' first."
    }
}
function Get-AllGraphValues {
    param([Parameter(Mandatory)][string]$Uri)
    $items = @(); $next = $Uri
    while ($next) {
        $resp = Invoke-MgGraphRequest -Method GET -Uri $next
        if ($resp.value) { $items += $resp.value }
        $next = $resp.'@odata.nextLink'
    }
    return $items
}

if (-not (Test-Path -LiteralPath $ConfigPath)) { throw "Config file not found: $ConfigPath" }
$cfg = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
if (-not $cfg.event.displayName) { throw "event.displayName is required to identify events to remove." }

Assert-MgConnected
Write-Host "Cleaning up Graph retention events named '$($cfg.event.displayName)'$(if ($DeleteEventType) { " and event type '$($cfg.eventType.displayName)'" })." -ForegroundColor Cyan
Write-Host "NOTE: deleting an event does NOT stop retention it already started - this is bookkeeping only. See rollback.md." -ForegroundColor Yellow

# --- Events ---
$events = Get-AllGraphValues -Uri "$GraphBaseUri/security/triggers/retentionEvents" | Where-Object { $_.displayName -eq $cfg.event.displayName }
if (@($events).Count -eq 0) {
    Write-Host "  [event] none found named '$($cfg.event.displayName)'." -ForegroundColor DarkGray
}
else {
    foreach ($e in $events) {
        if ($PSCmdlet.ShouldProcess("retention event '$($e.displayName)' (id $($e.id))", "DELETE")) {
            Invoke-MgGraphRequest -Method DELETE -Uri "$GraphBaseUri/security/triggers/retentionEvents/$($e.id)" | Out-Null
            Write-Host "  [event] deleted '$($e.displayName)' (id $($e.id)) - retention already started is unaffected." -ForegroundColor Green
        }
        else {
            Write-Host "  [event] WhatIf - would delete '$($e.displayName)' (id $($e.id))" -ForegroundColor DarkYellow
        }
    }
}

if (-not $DeleteEventType) {
    Write-Host "`nDone (events only). Re-run with -DeleteEventType to remove the event type." -ForegroundColor Cyan
    return
}

# --- Event type ---
if (-not $cfg.eventType.displayName) { throw "eventType.displayName is required to remove the event type." }
$etype = Get-AllGraphValues -Uri "$GraphBaseUri/security/triggerTypes/retentionEventTypes" | Where-Object { $_.displayName -eq $cfg.eventType.displayName } | Select-Object -First 1
if (-not $etype) {
    Write-Host "  [eventType] not found '$($cfg.eventType.displayName)' - skipping." -ForegroundColor DarkGray
}
else {
    try {
        if ($PSCmdlet.ShouldProcess("retention event type '$($etype.displayName)' (id $($etype.id))", "DELETE")) {
            Invoke-MgGraphRequest -Method DELETE -Uri "$GraphBaseUri/security/triggerTypes/retentionEventTypes/$($etype.id)" | Out-Null
            Write-Host "  [eventType] deleted '$($etype.displayName)' (id $($etype.id))" -ForegroundColor Green
        }
        else {
            Write-Host "  [eventType] WhatIf - would delete '$($etype.displayName)' (id $($etype.id))" -ForegroundColor DarkYellow
        }
    }
    catch {
        Write-Host "  [eventType] NOT deleted '$($etype.displayName)': $($_.Exception.Message)" -ForegroundColor Yellow
        Write-Host "         An event type still referenced by a label may not be removable - this is expected." -ForegroundColor Yellow
    }
}

Write-Host "`nDone." -ForegroundColor Cyan
