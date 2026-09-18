---
part: "deploy"
parent: "records-management/graph-event-automation"
---
The scripts and configuration below deploy this scenario. Review them, then run in order — each is designed to be idempotent and has a matching rollback.


#### `config/graph-event-automation.sample.json`

```json
{
  "_comment": "Config for deploy/New-GraphRetentionEvent.ps1. Author-only reference data - NOT applied to any tenant unless passed to the deploy script and confirmed (or run without -WhatIf). Automates event-based retention via the Microsoft Graph records-management APIs: ensures a retention EVENT TYPE exists, and (only when gated) fires a retention EVENT that STARTS an irreversible retention clock for matching event-based-labeled content. This is the automation complement to the PowerShell scenario ../../regulatory-records-disposition/. Read README.md Sections 2 and 11 first.",

  "eventType": {
    "displayName": "Contract Expiration",
    "description": "Triggers the retention clock for contract records when a contract expires. Referenced by an event-based retention label (retentionTrigger = dateOfEvent)."
  },

  "event": {
    "fire": false,
    "displayName": "Contract 4815 expired",
    "description": "Illustrative trigger event. fire=false by default so the deploy does NOT start a live retention clock. Set fire=true (and pass -FireEvent) only for a real, dated event from your business system.",
    "eventTriggerDateTime": "2026-09-04T00:00:00Z",
    "eventQuery": [
      {
        "queryType": "files",
        "query": "ComplianceAssetID:4815"
      }
    ]
  }
}
```

#### `New-GraphRetentionEvent.ps1`

```powershell
#Requires -Version 7.0
<#
.SYNOPSIS
    Automates event-based retention via the Microsoft Graph records-management APIs: ensures a
    retention EVENT TYPE exists (create-or-report), and - only when explicitly gated - fires a
    retention EVENT that starts the retention clock for matching event-based-labeled content.

.DESCRIPTION
    Uses the Microsoft Graph records-management API (v1.0 security namespace) via the Microsoft Graph
    PowerShell SDK (Invoke-MgGraphRequest) - automation surface 3 per docs/automation-surface.md - so
    that a business system (HR, contract, ERP) can fire retention events automatically when the
    business event happens, instead of a records manager creating events by hand in the portal. This
    is the Graph automation complement to the Security & Compliance PowerShell scenario
    ../../regulatory-records-disposition/ (which defines the event type + event-based label + publish
    policy). Microsoft's guidance: the older REST event API is deprecated - use Microsoft Graph.

      1. Event type: GET  /security/triggerTypes/retentionEventTypes  (find by displayName)
                     POST /security/triggerTypes/retentionEventTypes  (create if missing)
      2. Event:      POST /security/triggers/retentionEvents          (fire; retentionEventType@odata.bind
                     -> the type id; eventQuery = files/messages + AssetID/keywords; eventTriggerDateTime)

    Idempotent for the event type: located by displayName via a paged GET before create, so re-running
    reconciles rather than duplicating. Real -WhatIf works here (unlike Security & Compliance
    PowerShell) because every mutating call is wrapped in $PSCmdlet.ShouldProcess.

    !!! FIRING AN EVENT STARTS AN IRREVERSIBLE CLOCK !!! A retention event, once created, cannot be
    cancelled and deleting it does NOT stop the retention it started (README.md Section 11). So the
    event is fired ONLY when BOTH the config's event.fire is true AND -FireEvent is passed - and even
    then it goes through ShouldProcess. Ensuring the event type is safe and starts no clock.

    Connect first: Connect-MgGraph -Scopes 'RecordsManagement.ReadWrite.All' (delegated - signed-in
    user needs a records-management role), or app-only with a certificate. This script does not open
    the session.

    Author-only reference code. Firing a retention event is a consequential, irreversible action -
    review with -WhatIf, and with Records/Legal, before running for real.

.PARAMETER ConfigPath
    Path to the JSON config. Defaults to the sibling 'config/graph-event-automation.sample.json'.

.PARAMETER FireEvent
    Also fire the trigger event from the config's 'event' block - but ONLY if event.fire is true.
    Starts a real, irreversible retention clock. Omit to only ensure the event type exists.

.PARAMETER GraphBaseUri
    Graph base URI. Defaults to 'https://graph.microsoft.com/v1.0'.

.EXAMPLE
    Connect-MgGraph -Scopes 'RecordsManagement.ReadWrite.All'
    ./New-GraphRetentionEvent.ps1 -WhatIf

    Dry-run: shows the event type (and, with -FireEvent, the event) that would be created.

.EXAMPLE
    Connect-MgGraph -Scopes 'RecordsManagement.ReadWrite.All'
    ./New-GraphRetentionEvent.ps1                 # ensure event type only; starts no clock

.EXAMPLE
    ./New-GraphRetentionEvent.ps1 -FireEvent       # ALSO fire the event (irreversible) if event.fire=true

.NOTES
    Grounded in Microsoft Learn (verify before production use):
    - Records management API overview / trigger events for an existing label (retentionTrigger =
      dateOfEvent): https://learn.microsoft.com/graph/api/resources/security-recordsmanagement-overview?view=graph-rest-1.0
    - Create retentionEventType (POST /security/triggerTypes/retentionEventTypes):
      https://learn.microsoft.com/graph/api/security-retentioneventtype-post?view=graph-rest-1.0
    - Create retentionEvent (POST /security/triggers/retentionEvents; eventQuery, eventTriggerDateTime,
      retentionEventType@odata.bind): https://learn.microsoft.com/graph/api/security-retentionevent-post?view=graph-rest-1.0
    - eventQuery (queryType files|messages; query = Asset ID for SPO/ODB, keywords for EXO):
      https://learn.microsoft.com/graph/api/resources/security-eventquery?view=graph-rest-1.0
    - Equivalent typed SDK cmdlets: New-MgSecurityTriggerTypeRetentionEventType,
      New-MgSecurityTriggerRetentionEvent (Microsoft.Graph.Security). Permission:
      RecordsManagement.ReadWrite.All (delegated or application).
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$ConfigPath = (Join-Path $PSScriptRoot 'config/graph-event-automation.sample.json'),

    [Parameter()]
    [switch]$FireEvent,

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
        throw "Not connected to Microsoft Graph. Run Connect-MgGraph -Scopes 'RecordsManagement.ReadWrite.All' first. See docs/automation-surface.md Section 3."
    }
}

function Get-AllGraphValues {
    # GET a collection, following @odata.nextLink, returning all .value items.
    param([Parameter(Mandatory)][string]$Uri)
    $items = @()
    $next = $Uri
    while ($next) {
        $resp = Invoke-MgGraphRequest -Method GET -Uri $next
        if ($resp.value) { $items += $resp.value }
        $next = $resp.'@odata.nextLink'
    }
    return $items
}

if (-not (Test-Path -LiteralPath $ConfigPath)) { throw "Config file not found: $ConfigPath" }
$cfg = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
if (-not $cfg.eventType.displayName) { throw "eventType.displayName is required." }

Assert-MgConnected
Write-Host "Records-management event automation (Graph): event type '$($cfg.eventType.displayName)'." -ForegroundColor Cyan

# --- 1. Event type: create-or-report ---
$typeUri = "$GraphBaseUri/security/triggerTypes/retentionEventTypes"
$existingType = Get-AllGraphValues -Uri $typeUri | Where-Object { $_.displayName -eq $cfg.eventType.displayName } | Select-Object -First 1

if ($existingType) {
    Write-Host "  [eventType] exists '$($cfg.eventType.displayName)' (id $($existingType.id)) - not modified." -ForegroundColor DarkGreen
    $typeId = $existingType.id
}
else {
    $typeBody = @{
        '@odata.type' = '#microsoft.graph.security.retentionEventType'
        displayName   = $cfg.eventType.displayName
    }
    if ($cfg.eventType.description) { $typeBody.description = $cfg.eventType.description }

    if ($PSCmdlet.ShouldProcess("retention event type '$($cfg.eventType.displayName)'", "POST $typeUri")) {
        $created = Invoke-MgGraphRequest -Method POST -Uri $typeUri -Body ($typeBody | ConvertTo-Json -Depth 5)
        $typeId = $created.id
        Write-Host "  [eventType] created '$($cfg.eventType.displayName)' (id $typeId)" -ForegroundColor Green
    }
    else {
        Write-Host "  [eventType] WhatIf - would create '$($cfg.eventType.displayName)'" -ForegroundColor DarkYellow
        $typeId = '<new-event-type-id>'
    }
}

# --- 2. Event: fire (gated, irreversible) ---
if (-not $FireEvent) {
    Write-Host "  [event] skipped (no -FireEvent) - event type ensured, no retention clock started." -ForegroundColor DarkGray
    Write-Host "`nDone." -ForegroundColor Cyan
    return
}
if (-not [bool]$cfg.event.fire) {
    Write-Host "  [event] -FireEvent passed but config event.fire is not true - refusing to fire an event. Set event.fire=true for a real, dated event." -ForegroundColor Yellow
    Write-Host "`nDone." -ForegroundColor Cyan
    return
}
if (-not $cfg.event.displayName) { throw "event.displayName is required to fire an event." }

Write-Host "WARNING: firing a retention EVENT starts an IRREVERSIBLE clock - it cannot be cancelled and deleting it later does NOT stop retention. Ensure Records/Legal sign-off. See README.md Section 11." -ForegroundColor Red

# eventQuery: files (SPO/ODB, Asset ID) or messages (EXO, keywords)
$queries = @()
foreach ($q in @($cfg.event.eventQuery)) {
    if (-not $q) { continue }
    $queries += @{ '@odata.type' = '#microsoft.graph.security.eventQuery'; queryType = $q.queryType; query = $q.query }
}
if ($queries.Count -eq 0) {
    Write-Host "  CAUTION: no eventQuery set - the event will trigger retention for ALL content with this event type's label. This is rarely intended." -ForegroundColor Red
}

$eventUri = "$GraphBaseUri/security/triggers/retentionEvents"
$eventBody = @{
    '@odata.type'                    = '#microsoft.graph.security.retentionEvent'
    displayName                      = $cfg.event.displayName
    'retentionEventType@odata.bind'  = "$GraphBaseUri/security/triggerTypes/retentionEventTypes/$typeId"
}
if ($cfg.event.description) { $eventBody.description = $cfg.event.description }
if ($cfg.event.eventTriggerDateTime) { $eventBody.eventTriggerDateTime = $cfg.event.eventTriggerDateTime }
if ($queries.Count -gt 0) { $eventBody.eventQuery = $queries }

if ($PSCmdlet.ShouldProcess("retention event '$($cfg.event.displayName)' (STARTS RETENTION CLOCK)", "POST $eventUri")) {
    $ev = Invoke-MgGraphRequest -Method POST -Uri $eventUri -Body ($eventBody | ConvertTo-Json -Depth 6)
    Write-Host "  [event] fired '$($cfg.event.displayName)' (id $($ev.id)) - retention clock started (sync up to 7 days)." -ForegroundColor Green
    if ($ev.eventStatus) { Write-Host "    Event status: $($ev.eventStatus.status)" -ForegroundColor Cyan }
    if ($ev.eventPropagationResults) {
        foreach ($r in @($ev.eventPropagationResults)) {
            Write-Host "    Propagation: $($r.serviceName)/$($r.location) -> $($r.status)" -ForegroundColor DarkCyan
        }
    }
}
else {
    Write-Host "  [event] WhatIf - would fire '$($cfg.event.displayName)' (irreversible)" -ForegroundColor DarkYellow
}

Write-Host "`nDone." -ForegroundColor Cyan
Write-Host "A fired event syncs to labeled content in up to 7 days. Validate with validate/Test-GraphRetentionEvent.ps1 and review disposition in the portal (Records Management > Disposition)." -ForegroundColor Yellow
```

#### `Remove-GraphRetentionEvent.ps1`

```powershell
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
```