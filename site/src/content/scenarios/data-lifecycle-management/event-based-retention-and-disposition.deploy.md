---
part: "deploy"
parent: "data-lifecycle-management/event-based-retention-and-disposition"
---
The scripts and configuration below deploy this scenario. Review them, then run in order — each is designed to be idempotent and has a matching rollback.


#### `config/employee-departure-retention.sample.json`

```json
{
  "_comment": "Config for deploy/New-EventBasedRetentionAndDisposition.ps1. Author-only reference data - NOT applied to any tenant unless passed to the deploy script without -DryRun. Creates a retention EVENT TYPE, an event-based retention LABEL (KeepAndDelete + two-stage disposition review), and a PUBLISH label policy so Records/HR can manually apply the label to a departed employee's records. Read README.md Sections 2 and 11 before deploying.",
  "eventType": {
    "name": "Employee Departure",
    "comment": "Retention event type for employee-departure-triggered record retention. Fired per employee via deploy/New-RetentionTriggerEvent.ps1 when the event actually occurs (HR/business-system driven) - not by this deploy script."
  },
  "label": {
    "name": "Employee Records - Post-Departure Retention",
    "comment": "Personnel/hiring/performance/termination records for a departed employee. Retention period starts on the employee-departure EVENT, not on content creation.",
    "retentionAction": "KeepAndDelete",
    "retentionDurationDays": 3650,
    "retentionType": "EventAgeInDays",
    "isRecordLabel": true,
    "multiStageReview": [
      { "stageName": "HR Records Review", "reviewers": ["hr-records-review@contoso.onmicrosoft.com"] },
      { "stageName": "Legal Review", "reviewers": ["legal-disposition-review@contoso.onmicrosoft.com"] }
    ],
    "autoApprovalPeriodDays": null,
    "_labelNote": "retentionAction MUST be KeepAndDelete or Delete to use reviewerEmail/multiStageReview (New-ComplianceTag reference). retentionType MUST be EventAgeInDays to pair with eventType.name - the retention clock does not start until New-RetentionTriggerEvent.ps1 fires a matching event for a given employee (README.md Section 5/Section 11). retentionDurationDays: 3650 (~10 years) mirrors Microsoft's own 'employee leaving the organization' event-based-retention example (README.md Section 12 ref 1) - set this to your organization's actual post-departure record-retention obligation, not this illustrative value. isRecordLabel=true marks labeled content as a record (locked - can't be edited/deleted until disposed); this is NOT a regulatory record (see the sibling retention-labels-financial-records scenario for that stronger, PowerShell-only control) - a Records Management-privileged user can still unlock/relabel a record if genuinely necessary. multiStageReview becomes -MultiStageReviewProperty (a JSON string built by the script) - two stages shown (HR, then Legal); mail-enabled security groups are also valid reviewer values per Microsoft's disposition documentation. autoApprovalPeriodDays: if set, must be 7-365 (portal-documented range/default 14 - README.md Section 11 VERIFY on the exact cmdlet-parameter mapping); null disables auto-approval so every stage requires an explicit human decision."
  },
  "policy": {
    "name": "Publish Employee Records Retention - HR",
    "comment": "Publishes the event-based label so Records/HR can manually apply it (and its required Asset ID) to a departed employee's records. Auto-apply is not used here - see README.md Section 11 for why.",
    "enabled": true,
    "sharePointLocation": ["https://contoso.sharepoint.com/sites/hr-employee-records"],
    "exchangeLocation": [],
    "_policyNote": "At least one location is required. This is a PUBLISH policy (New-RetentionComplianceRule -PublishComplianceTag), not auto-apply - event-based labels are normally applied per-employee by a records manager along with that employee's Asset ID (README.md Section 5/11)."
  },
  "schemaVersion": "1.0",
  "lastUpdated": "2026-09-10"
}
```

#### `New-EventBasedRetentionAndDisposition.ps1`

```powershell
#Requires -Version 7.0
<#
.SYNOPSIS
    Creates a retention EVENT TYPE, an event-based retention LABEL (KeepAndDelete, two-stage
    disposition review), and a PUBLISH label policy/rule so Records/HR can manually apply the
    label to a departed employee's records - using Security & Compliance PowerShell.

.DESCRIPTION
    Uses the Data Lifecycle Management / Records Management cmdlets in Security & Compliance
    PowerShell (automation surface 2 per docs/automation-surface.md):
      1. New-ComplianceRetentionEventType -> the event type the label listens for
      2. New-ComplianceTag -EventType ...  -> the retention label (KeepAndDelete; retention clock
         starts only once a matching event is fired - see New-RetentionTriggerEvent.ps1)
      3. New-RetentionCompliancePolicy     -> the label policy (locations)
      4. New-RetentionComplianceRule -PublishComplianceTag -> publishes the label for manual
         application (event-based labels are normally applied per item, with an Asset ID, by a
         records manager - not auto-applied by content match)

    Idempotent: each object is located by name via Get-* before create; if present it is reported
    (labels/policies are not silently mutated - retention objects are high-consequence). Re-running
    is safe. -WhatIf is non-functional in Security & Compliance PowerShell, so this script
    implements its own -DryRun that prints the intended cmdlets and runs none.

    This script does NOT fire retention events for individual employees - see
    deploy/New-RetentionTriggerEvent.ps1 for that operational, per-employee step, run whenever an
    employee actually leaves.

    Connect first: Connect-IPPSSession (certificate app-only preferred - docs/automation-surface.md
    Section 3). This script does not open the session.

.PARAMETER ConfigPath
    Path to the JSON config. Defaults to 'config/employee-departure-retention.sample.json'.

.PARAMETER DryRun
    Print every mutating cmdlet that would run and invoke none (the working substitute for -WhatIf,
    which does not function in Security & Compliance PowerShell).

.EXAMPLE
    Connect-IPPSSession -AppId $AppId -Certificate $Cert -Organization 'contoso.onmicrosoft.com'
    ./New-EventBasedRetentionAndDisposition.ps1 -DryRun

.EXAMPLE
    Connect-IPPSSession -AppId $AppId -Certificate $Cert -Organization 'contoso.onmicrosoft.com'
    ./New-EventBasedRetentionAndDisposition.ps1

.NOTES
    Grounded in Microsoft Learn (verify before production use):
    - New-ComplianceTag (-EventType/-RetentionAction/-RetentionDuration/-RetentionType/
      -IsRecordLabel/-MultiStageReviewProperty/-AutoApprovalPeriod/-ReviewerEmail):
      https://learn.microsoft.com/powershell/module/exchangepowershell/new-compliancetag
    - New-ComplianceRetentionEventType:
      https://learn.microsoft.com/powershell/module/exchangepowershell/new-complianceretentioneventtype
    - New-RetentionCompliancePolicy / New-RetentionComplianceRule (-PublishComplianceTag):
      https://learn.microsoft.com/powershell/module/exchangepowershell/new-retentioncompliancepolicy
      https://learn.microsoft.com/powershell/module/exchangepowershell/new-retentioncompliancerule
    - Start retention when an event occurs (event-based retention concepts, asset IDs):
      https://learn.microsoft.com/purview/event-driven-retention
    - Disposition of content (disposition review timelines, auto-approval 7-365 days/default 14):
      https://learn.microsoft.com/purview/disposition

    VERIFY (pilot tenant): -AutoApprovalPeriod's own parameter description on the New-ComplianceTag
    reference page is an unfilled Microsoft documentation stub ("{{ Fill AutoApprovalPeriod
    Description }}"). The 7-365 day range and 14-day default used here come from the conceptual
    disposition-review article, not a confirmed mapping to this specific cmdlet parameter. Left
    null (disabled) by default in the sample config for exactly this reason.
#>
[CmdletBinding()]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$ConfigPath = (Join-Path $PSScriptRoot 'config/employee-departure-retention.sample.json'),

    [Parameter()]
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

function Assert-SccConnected {
    if (-not (Get-Command Get-ComplianceTag -ErrorAction SilentlyContinue)) {
        throw "Retention cmdlets not found. Connect first: Connect-IPPSSession (Security & Compliance PowerShell). See docs/automation-surface.md Section 3."
    }
}
function Invoke-Scc {
    param([Parameter(Mandatory)][string]$Describe, [Parameter(Mandatory)][scriptblock]$Action)
    if ($DryRun) { Write-Host "  DRYRUN would run: $Describe" -ForegroundColor DarkYellow; return $null }
    Write-Host "  $Describe" -ForegroundColor Green
    return & $Action
}
function ConvertTo-MultiStageReviewJson {
    param([Parameter(Mandatory)][array]$Stages)
    $settings = @($Stages | ForEach-Object {
        [PSCustomObject]@{ StageName = $_.stageName; Reviewers = @($_.reviewers) }
    })
    return (ConvertTo-Json -InputObject ([PSCustomObject]@{ MultiStageReviewSettings = $settings }) -Depth 6 -Compress)
}

if (-not (Test-Path -LiteralPath $ConfigPath)) { throw "Config file not found: $ConfigPath" }
$cfg = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
foreach ($k in 'eventType', 'label', 'policy') { if (-not $cfg.$k) { throw "Config missing '$k' section." } }
if (-not $cfg.eventType.name) { throw "eventType.name is required." }
if (-not $cfg.label.name) { throw "label.name is required." }
if ("$($cfg.label.retentionType)" -ne 'EventAgeInDays') { throw "label.retentionType must be 'EventAgeInDays' for an event-based label." }
if ("$($cfg.label.retentionAction)" -notin @('KeepAndDelete', 'Delete')) { throw "label.retentionAction must be 'KeepAndDelete' or 'Delete' to use disposition review (ReviewerEmail/MultiStageReviewProperty)." }
if (-not $cfg.policy.name) { throw "policy.name is required." }

Assert-SccConnected
Write-Host "Deploying event-based retention: event type '$($cfg.eventType.name)' + label '$($cfg.label.name)' + publish policy '$($cfg.policy.name)'." -ForegroundColor Cyan
if ($cfg.label.isRecordLabel) {
    Write-Host "NOTE: this label marks content as a RECORD (IsRecordLabel). Once applied and its event has fired, content is locked until disposition. See README.md Sections 2/9/11." -ForegroundColor Yellow
}

# --- 1. Retention event type (New-ComplianceRetentionEventType) ---
$existingEventType = Get-ComplianceRetentionEventType -Identity $cfg.eventType.name -ErrorAction SilentlyContinue
if ($existingEventType) {
    Write-Host "  [eventType] exists '$($cfg.eventType.name)'" -ForegroundColor DarkGreen
}
else {
    $etParams = @{ Name = $cfg.eventType.name }
    if ($cfg.eventType.comment) { $etParams.Comment = $cfg.eventType.comment }
    Invoke-Scc -Describe "New-ComplianceRetentionEventType -Name '$($cfg.eventType.name)'" `
        -Action { New-ComplianceRetentionEventType @etParams -Confirm:$false } | Out-Null
    Write-Host "  [eventType] created '$($cfg.eventType.name)'" -ForegroundColor Green
}

# --- 2. Event-based retention label (New-ComplianceTag) ---
$existingLabel = Get-ComplianceTag -Identity $cfg.label.name -ErrorAction SilentlyContinue
if ($existingLabel) {
    Write-Host "  [label] exists '$($cfg.label.name)' (not modified - retention labels are high-consequence; edit deliberately)." -ForegroundColor DarkGreen
}
else {
    $tagParams = @{
        Name              = $cfg.label.name
        RetentionAction   = $cfg.label.retentionAction
        RetentionType     = $cfg.label.retentionType
        RetentionDuration = [int]$cfg.label.retentionDurationDays
        EventType         = $cfg.eventType.name
    }
    if ($cfg.label.comment) { $tagParams.Comment = $cfg.label.comment }
    if ($null -ne $cfg.label.isRecordLabel) { $tagParams.IsRecordLabel = [bool]$cfg.label.isRecordLabel }
    if ($cfg.label.multiStageReview -and @($cfg.label.multiStageReview).Count -gt 0) {
        $tagParams.MultiStageReviewProperty = ConvertTo-MultiStageReviewJson -Stages $cfg.label.multiStageReview
    }
    elseif ($cfg.label.reviewerEmail -and @($cfg.label.reviewerEmail).Count -gt 0) {
        $tagParams.ReviewerEmail = @($cfg.label.reviewerEmail)
    }
    else {
        throw "label needs either multiStageReview (>=1 stage) or reviewerEmail for a KeepAndDelete/Delete disposition review."
    }
    if ($cfg.label.autoApprovalPeriodDays) {
        $days = [int]$cfg.label.autoApprovalPeriodDays
        if ($days -lt 7 -or $days -gt 365) { throw "label.autoApprovalPeriodDays must be 7-365 (or null to disable) per the disposition-review documentation." }
        $tagParams.AutoApprovalPeriod = $days
    }

    $desc = "New-ComplianceTag -Name '$($cfg.label.name)' -EventType '$($cfg.eventType.name)' -RetentionAction $($cfg.label.retentionAction) -RetentionDuration $($cfg.label.retentionDurationDays) -RetentionType EventAgeInDays$(if ($tagParams.IsRecordLabel) { ' -IsRecordLabel $true' })$(if ($tagParams.MultiStageReviewProperty) { ' -MultiStageReviewProperty <json>' } elseif ($tagParams.ReviewerEmail) { ' -ReviewerEmail <addresses>' })"
    Invoke-Scc -Describe $desc -Action { New-ComplianceTag @tagParams -Confirm:$false } | Out-Null
    Write-Host "  [label] created '$($cfg.label.name)'" -ForegroundColor Green
}

# --- 3. Publish label policy (New-RetentionCompliancePolicy) ---
$existingPolicy = Get-RetentionCompliancePolicy -Identity $cfg.policy.name -ErrorAction SilentlyContinue
if ($existingPolicy) {
    Write-Host "  [policy] exists '$($cfg.policy.name)'" -ForegroundColor DarkGreen
}
else {
    $polParams = @{ Name = $cfg.policy.name }
    if ($null -ne $cfg.policy.enabled) { $polParams.Enabled = [bool]$cfg.policy.enabled }
    if ($cfg.policy.comment) { $polParams.Comment = $cfg.policy.comment }
    if ($cfg.policy.sharePointLocation -and @($cfg.policy.sharePointLocation).Count -gt 0) { $polParams.SharePointLocation = @($cfg.policy.sharePointLocation) }
    if ($cfg.policy.exchangeLocation -and @($cfg.policy.exchangeLocation).Count -gt 0) { $polParams.ExchangeLocation = @($cfg.policy.exchangeLocation) }
    if (-not ($polParams.SharePointLocation -or $polParams.ExchangeLocation)) {
        throw "policy needs at least one location (sharePointLocation / exchangeLocation)."
    }
    Invoke-Scc -Describe "New-RetentionCompliancePolicy -Name '$($cfg.policy.name)' (publish label policy, locations set)" `
        -Action { New-RetentionCompliancePolicy @polParams -Confirm:$false } | Out-Null
    Write-Host "  [policy] created '$($cfg.policy.name)'" -ForegroundColor Green
}

# --- 4. Publish rule (New-RetentionComplianceRule -PublishComplianceTag) ---
$existingRule = Get-RetentionComplianceRule -Policy $cfg.policy.name -ErrorAction SilentlyContinue | Select-Object -First 1
if ($existingRule) {
    Write-Host "  [rule] exists on policy '$($cfg.policy.name)' (one rule per policy - not modified)." -ForegroundColor DarkGreen
}
else {
    $ruleParams = @{
        Name                 = "$($cfg.policy.name) - Rule"
        Policy               = $cfg.policy.name
        PublishComplianceTag = $cfg.label.name
    }
    Invoke-Scc -Describe "New-RetentionComplianceRule -Policy '$($cfg.policy.name)' -PublishComplianceTag '$($cfg.label.name)'" `
        -Action { New-RetentionComplianceRule @ruleParams -Confirm:$false } | Out-Null
    Write-Host "  [rule] created (publishes '$($cfg.label.name)')" -ForegroundColor Green
}

Write-Host "`nDone." -ForegroundColor Cyan
Write-Host "Publish policy distribution can take up to 7 days before records managers see the label to apply. The retention clock for any item does NOT start until an event is fired for it - see deploy/New-RetentionTriggerEvent.ps1. Validate with validate/Test-EventBasedRetentionAndDisposition.ps1." -ForegroundColor Yellow
```

#### `New-RetentionTriggerEvent.ps1`

```powershell
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
```

#### `Remove-EventBasedRetentionAndDisposition.ps1`

```powershell
#Requires -Version 7.0
<#
.SYNOPSIS
    Rolls back the event-based retention deployment: disables (and optionally deletes) the publish
    policy/rule. The retention label and event type are intentionally not force-removed once events
    may have been fired against them.

.DESCRIPTION
    Uses Security & Compliance PowerShell. Staged:
      Default    Disable the publish policy (Set-RetentionCompliancePolicy -Enabled $false) so
                 records managers no longer see the label to apply to NEW content. Content already
                 labeled - and any whose retention event has already fired - keeps its label and
                 retention; disposition review still runs at the end of that retention period.
      -Delete    Additionally delete the policy (Remove-RetentionCompliancePolicy) and its rule.
                 Users can no longer manually apply the label at all after this.

    The retention LABEL is NOT deleted by this script by default. Content already marked as a
    record under this label (isRecordLabel) cannot have the label removed while it's locked; even
    for non-record content, a label with events already fired against it should not be deleted out
    from under retention that's actively counting down. Use -TryRemoveLabel to attempt it anyway -
    the service refuses if the label is genuinely in use, which this script reports rather than
    forcing. The EVENT TYPE is never removed by this script (Remove-ComplianceRetentionEventType
    exists per Microsoft Learn's own automation list, but this scenario treats event types, like
    fired events, as an append-only audit record of what happened - see README.md Section 9).

    -WhatIf is non-functional in Security & Compliance PowerShell, so this script implements
    -DryRun. Connect first with Connect-IPPSSession.

.PARAMETER ConfigPath
    Path to the same JSON config used to deploy. Defaults to
    'config/employee-departure-retention.sample.json'. Only policy.name (and, with
    -TryRemoveLabel, label.name) are read here.

.PARAMETER Delete
    Delete the publish policy and rule (not just disable).

.PARAMETER TryRemoveLabel
    Attempt to remove the retention label too (Remove-ComplianceTag). Succeeds only if the label
    was never applied (or, for a record label, isn't locked on any item); otherwise the service
    refuses, which this script reports rather than forcing.

.PARAMETER DryRun
    Print the intended cmdlets and run none.

.EXAMPLE
    Connect-IPPSSession -AppId $AppId -Certificate $Cert -Organization 'contoso.onmicrosoft.com'
    ./Remove-EventBasedRetentionAndDisposition.ps1 -DryRun

.NOTES
    Grounded in Microsoft Learn: Set-/Remove-RetentionCompliancePolicy, Remove-ComplianceTag;
    event-based retention and disposition review behavior.
    https://learn.microsoft.com/purview/event-driven-retention
    https://learn.microsoft.com/purview/disposition
#>
[CmdletBinding()]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$ConfigPath = (Join-Path $PSScriptRoot 'config/employee-departure-retention.sample.json'),

    [Parameter()]
    [switch]$Delete,

    [Parameter()]
    [switch]$TryRemoveLabel,

    [Parameter()]
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
if (-not (Get-Command Get-RetentionCompliancePolicy -ErrorAction SilentlyContinue)) {
    throw "Retention cmdlets not found. Connect first: Connect-IPPSSession. See docs/automation-surface.md Section 3."
}
if (-not (Test-Path -LiteralPath $ConfigPath)) { throw "Config file not found: $ConfigPath" }
$cfg = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
if (-not $cfg.policy.name) { throw "policy.name is required." }

function Invoke-Scc {
    param([string]$Describe, [scriptblock]$Action)
    if ($DryRun) { Write-Host "  DRYRUN would run: $Describe" -ForegroundColor DarkYellow; return }
    Write-Host "  $Describe" -ForegroundColor Green
    & $Action
}

$policy = Get-RetentionCompliancePolicy -Identity $cfg.policy.name -ErrorAction SilentlyContinue
if ($policy) {
    Invoke-Scc -Describe "Set-RetentionCompliancePolicy -Identity '$($cfg.policy.name)' -Enabled `$false" `
        -Action { Set-RetentionCompliancePolicy -Identity $cfg.policy.name -Enabled $false -Confirm:$false }
    Write-Host "  [disable] policy '$($cfg.policy.name)' disabled (records managers can no longer apply the label to NEW content)." -ForegroundColor Yellow
    if ($Delete) {
        Invoke-Scc -Describe "Remove-RetentionCompliancePolicy -Identity '$($cfg.policy.name)'" `
            -Action { Remove-RetentionCompliancePolicy -Identity $cfg.policy.name -Confirm:$false }
        Write-Host "  [delete] policy '$($cfg.policy.name)' removed (rule removed with it)." -ForegroundColor Red
    }
}
else { Write-Host "  [policy] '$($cfg.policy.name)' not found." -ForegroundColor DarkGray }

if ($TryRemoveLabel -and $cfg.label.name) {
    if ($DryRun) {
        Write-Host "  DRYRUN would run: Remove-ComplianceTag -Identity '$($cfg.label.name)'" -ForegroundColor DarkYellow
    }
    else {
        try {
            Remove-ComplianceTag -Identity $cfg.label.name -Confirm:$false
            Write-Host "  [delete] label '$($cfg.label.name)' removed (was not in use)." -ForegroundColor Red
        }
        catch {
            Write-Warning "  Could not remove label '$($cfg.label.name)': $($_.Exception.Message). Expected if the label is applied and locked as a record, or has content with an active retention clock. See rollback.md."
        }
    }
}

Write-Host "`nDone." -ForegroundColor Cyan
Write-Host "Content already labeled - and any whose retention event already fired - keeps its retention/disposition schedule. The event type and any fired events are never removed by this script (append-only audit record). See rollback.md." -ForegroundColor Yellow
```