---
part: "validate"
parent: "records-management/graph-event-automation"
---
Run these checks after deployment to confirm the control is working as designed.


#### `Test-GraphRetentionEvent.ps1`

```powershell
#Requires -Version 7.0
<#
.SYNOPSIS
    Verifies (read-only) the Graph records-management event automation: the retention event type
    exists, and reports any retention events fired for it with their propagation status.

.DESCRIPTION
    Read-only - issues only GET requests, never modifies any object. Uses the Microsoft Graph
    records-management API (v1.0 security namespace) via Invoke-MgGraphRequest to check, against the
    config file:
      1. The retention event type exists (GET /security/triggerTypes/retentionEventTypes).
      2. Reports retention events matching the config's event.displayName, with eventStatus and
         eventPropagationResults (each fired event is an irreversible retention start).
    Exits non-zero if the event type is missing (safe for a CI-style pre-flight). Safe to re-run.

    Connect first: Connect-MgGraph -Scopes 'RecordsManagement.Read.All' (read-only is sufficient).

.PARAMETER ConfigPath
    Path to the config to validate against. Defaults to the sibling
    'config/graph-event-automation.sample.json'.

.PARAMETER GraphBaseUri
    Graph base URI. Defaults to 'https://graph.microsoft.com/v1.0'.

.EXAMPLE
    Connect-MgGraph -Scopes 'RecordsManagement.Read.All'
    ./Test-GraphRetentionEvent.ps1
#>
[CmdletBinding()]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$ConfigPath = (Join-Path $PSScriptRoot '../deploy/config/graph-event-automation.sample.json'),

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$GraphBaseUri = 'https://graph.microsoft.com/v1.0'
)

$ErrorActionPreference = 'Stop'
$script:failures = 0
function Test-Check {
    param([string]$Description, [bool]$Condition, [switch]$Warn)
    if ($Condition) { Write-Host "  [PASS] $Description" -ForegroundColor Green }
    elseif ($Warn) { Write-Host "  [WARN] $Description" -ForegroundColor Yellow }
    else { Write-Host "  [FAIL] $Description" -ForegroundColor Red; $script:failures++ }
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

if (-not (Get-Command Invoke-MgGraphRequest -ErrorAction SilentlyContinue)) {
    throw "Microsoft Graph PowerShell SDK not found. Install Microsoft.Graph and run Connect-MgGraph -Scopes 'RecordsManagement.Read.All'."
}
if (-not (Get-MgContext -ErrorAction SilentlyContinue)) {
    throw "Not connected to Microsoft Graph. Run Connect-MgGraph -Scopes 'RecordsManagement.Read.All' first."
}
if (-not (Test-Path -LiteralPath $ConfigPath)) { throw "Config file not found: $ConfigPath" }
$cfg = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json

Write-Host "Validating Graph records-management event automation ('$($cfg.eventType.displayName)')..." -ForegroundColor Cyan

# Event type
$etype = Get-AllGraphValues -Uri "$GraphBaseUri/security/triggerTypes/retentionEventTypes" | Where-Object { $_.displayName -eq $cfg.eventType.displayName } | Select-Object -First 1
Test-Check -Description "Event type '$($cfg.eventType.displayName)' exists" -Condition ($null -ne $etype)
if ($etype) { Write-Host "    id: $($etype.id)" -ForegroundColor DarkCyan }

# Events (informational - each is an irreversible retention start)
$events = Get-AllGraphValues -Uri "$GraphBaseUri/security/triggers/retentionEvents" | Where-Object { $_.displayName -eq $cfg.event.displayName }
if (@($events).Count -gt 0) {
    Write-Host "    Events named '$($cfg.event.displayName)': $(@($events).Count) (each started an irreversible retention clock)." -ForegroundColor Cyan
    foreach ($e in $events) {
        $status = if ($e.eventStatus) { $e.eventStatus.status } else { 'unknown' }
        Write-Host "      - $($e.displayName) (id $($e.id)) trigger=$($e.eventTriggerDateTime) status=$status" -ForegroundColor DarkCyan
        foreach ($r in @($e.eventPropagationResults)) {
            Write-Host "          propagation: $($r.serviceName)/$($r.location) -> $($r.status)" -ForegroundColor DarkGray
        }
    }
}
else {
    Write-Host "    No events fired yet named '$($cfg.event.displayName)' - retention clock not started (expected before firing)." -ForegroundColor DarkGray
}

Write-Host "`n  Note: a fired event syncs to labeled content in up to 7 days. Confirm disposition in the portal (Records Management > Disposition)." -ForegroundColor Cyan
Write-Host "$(if ($script:failures -eq 0) { 'All hard checks passed.' } else { "$script:failures hard check(s) failed." })" `
    -ForegroundColor $(if ($script:failures -eq 0) { 'Green' } else { 'Red' })
if ($script:failures -gt 0) { exit 1 }
```