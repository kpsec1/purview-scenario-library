#Requires -Version 7.0
<#
.SYNOPSIS
    Fires a compliance retention event for one departed employee, starting the retention clock for
    every item already labeled with the matching event-based retention label and that employee's
    Asset ID.

.DESCRIPTION
    Operational script, run once per employee departure (not part of the one-time policy deploy -
    see New-EventBasedRetentionAndDisposition.ps1 for that). Wraps New-ComplianceRetentionEvent
    (Security & Compliance PowerShell, automation surface 2):

      New-ComplianceRetentionEvent -Name <unique> -EventType <event type> `
        -SharePointAssetIdQuery "ComplianceAssetID:<EmployeeId>" -EventDateTime <departure date>

    Only content that (a) already carries the matching event-based retention label AND (b) has its
    ComplianceAssetID document property set to the same employee ID has its retention period
    started by this event. If you omit an asset ID/keyword query entirely, Microsoft's own guidance
    warns this event starts the clock for ALL content under that event type tenant-wide - this
    script REQUIRES an asset scope for exactly that reason (see the -Force override).

    Idempotency: retention events are individually-named, append-only audit-style objects, not
    reconcilable policy state - and Microsoft's documentation states events cannot be canceled once
    triggered. This script therefore checks for an existing event with the same -Name first and
    reports it rather than firing a duplicate. Re-running with the same -Name is safe; re-running
    with a new -Name for an employee who already has an event fires a SECOND, likely-redundant
    event - the script does not attempt to detect that by asset ID (no documented query cmdlet for
    it - see README.md Section 11).

    -WhatIf is non-functional in Security & Compliance PowerShell, so this script implements
    -DryRun. Connect first with Connect-IPPSSession.

.PARAMETER EventName
    A unique name for this retention event (max 64 characters - New-ComplianceRetentionEvent
    limit). Include the employee ID for traceability, e.g. 'Employee Departure - 123456'.

.PARAMETER EventTypeName
    The retention event type this event belongs to. Defaults to 'Employee Departure' (the sample
    config's event type name).

.PARAMETER EmployeeId
    The employee's Asset ID (the value already set in the ComplianceAssetID SharePoint/OneDrive
    document property on that employee's labeled records). Scopes the event to only that
    employee's content.

.PARAMETER EventDate
    The date the event occurred (the employee's actual departure date). Defaults to today. Can be
    a past date - the retention clock is computed from this date, not from when the event object
    is created.

.PARAMETER Force
    Allow firing an event with no -EmployeeId (and therefore no asset scope), which starts the
    retention clock for ALL content under this event type tenant-wide. Confirmed intentional-only
    behavior per Microsoft's documentation - not the default.

.PARAMETER DryRun
    Print the intended cmdlet and run none.

.EXAMPLE
    Connect-IPPSSession -AppId $AppId -Certificate $Cert -Organization 'contoso.onmicrosoft.com'
    ./New-RetentionTriggerEvent.ps1 -EventName 'Employee Departure - 123456' -EmployeeId '123456' -EventDate '2026-09-01' -DryRun

.NOTES
    Grounded in Microsoft Learn (verify before production use):
    - New-ComplianceRetentionEvent (-EventType/-AssetId/-SharePointAssetIdQuery/
      -ExchangeAssetIdQuery/-EventDateTime/-EventTags):
      https://learn.microsoft.com/powershell/module/exchangepowershell/new-complianceretentionevent
    - Start retention when an event occurs (asset ID / event-type relationship; events can't be
      canceled once triggered; unscoped events retain ALL content of that event type):
      https://learn.microsoft.com/purview/event-driven-retention
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateLength(1, 64)]
    [string]$EventName,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$EventTypeName = 'Employee Departure',

    [Parameter()]
    [string]$EmployeeId,

    [Parameter()]
    [datetime]$EventDate = (Get-Date),

    [Parameter()]
    [switch]$Force,

    [Parameter()]
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
if (-not (Get-Command Get-ComplianceRetentionEvent -ErrorAction SilentlyContinue)) {
    throw "Retention cmdlets not found. Connect first: Connect-IPPSSession. See docs/automation-surface.md Section 3."
}
if (-not (Get-ComplianceRetentionEventType -Identity $EventTypeName -ErrorAction SilentlyContinue)) {
    throw "Retention event type '$EventTypeName' not found. Deploy it first with New-EventBasedRetentionAndDisposition.ps1."
}
if (-not $EmployeeId -and -not $Force) {
    throw "No -EmployeeId given. Firing an event with no asset scope starts retention for ALL content under event type '$EventTypeName' tenant-wide. Pass -EmployeeId, or -Force to confirm that's intended."
}

$existingEvent = Get-ComplianceRetentionEvent -Identity $EventName -ErrorAction SilentlyContinue
if ($existingEvent) {
    Write-Host "[event] '$EventName' already exists (created $($existingEvent.WhenCreated)) - not re-fired. Retention events cannot be canceled or re-triggered once created." -ForegroundColor DarkGreen
    exit 0
}

$eventParams = @{
    Name          = $EventName
    EventType     = $EventTypeName
    EventDateTime = $EventDate
}
if ($EmployeeId) { $eventParams.SharePointAssetIdQuery = "ComplianceAssetID:$EmployeeId" }

$desc = "New-ComplianceRetentionEvent -Name '$EventName' -EventType '$EventTypeName'$(if ($EmployeeId) { " -SharePointAssetIdQuery 'ComplianceAssetID:$EmployeeId'" } else { ' (UNSCOPED - all content of this event type)' }) -EventDateTime '$($EventDate.ToString('yyyy-MM-dd'))'"
if ($DryRun) {
    Write-Host "DRYRUN would run: $desc" -ForegroundColor DarkYellow
    exit 0
}

Write-Host $desc -ForegroundColor Green
New-ComplianceRetentionEvent @eventParams -Confirm:$false | Out-Null
Write-Host "[event] created '$EventName'. Synchronization to labeled content can take up to 7 days. This cannot be canceled - see README.md Section 11." -ForegroundColor Yellow
