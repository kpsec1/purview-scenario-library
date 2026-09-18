---
part: "deploy"
parent: "records-management/multi-stage-disposition-review"
---
The scripts and configuration below deploy this scenario. Review them, then run in order — each is designed to be idempotent and has a matching rollback.


#### `config/multi-stage-disposition-review.sample.json`

```json
{
  "_comment": "Config for deploy/New-MultiStageDispositionReview.ps1. Author-only reference data - NOT applied to any tenant unless passed to the deploy script without -DryRun. Builds an event-based, MULTI-STAGE disposition-review lifecycle for employee separation records: an event TYPE, a record label whose disposal requires sequential sign-off from up to 5 reviewer stages (-MultiStageReviewProperty), a PUBLISH policy, and an optional gated trigger EVENT. Placeholder values are illustrative - set them to your real records schedule, reviewer distribution lists, and locations, validated by Records/Legal/HR, before deploying. Read README.md Sections 2 and 11 first - a triggered event and an applied record label are IRREVERSIBLE, and a misconfigured autoApprovalPeriodDays can auto-approve a stage no human reviewed.",

  "eventType": {
    "name": "Employee Separation",
    "comment": "Triggers the retention clock for an employee's records when their employment ends. Created via New-ComplianceRetentionEventType."
  },

  "label": {
    "name": "Employee Records - Post-Separation Disposition",
    "comment": "Record label for employee personnel/HR-file records. Retention starts on an Employee Separation event; disposal requires HR -> Legal -> Records Management sign-off (multi-stage disposition review) - one approver is not enough given wrongful-termination/discrimination-claim exposure.",
    "retentionAction": "KeepAndDelete",
    "retentionDurationDays": 1095,
    "retentionType": "EventAgeInDays",
    "isRecordLabel": true,
    "autoApprovalPeriodDays": 30,
    "complianceTagForNextStage": null,
    "multiStageReview": {
      "enabled": true,
      "stages": [
        {
          "stageName": "Stage 1 - HR Business Partner review",
          "reviewers": [
            "hr-separations-review@contoso.com"
          ]
        },
        {
          "stageName": "Stage 2 - Employment Counsel review",
          "reviewers": [
            "employment-counsel@contoso.com"
          ]
        },
        {
          "stageName": "Stage 3 - Records Management final disposition",
          "reviewers": [
            "records-managers@contoso.com"
          ]
        }
      ]
    }
  },

  "policy": {
    "name": "Publish - Employee Separation Records",
    "comment": "Publishes the employee-records label so it can be applied (manually or as a default library label) in the target HR locations.",
    "enabled": true,
    "sharePointLocation": [
      "https://contoso.sharepoint.com/sites/HR-EmployeeFiles"
    ],
    "exchangeLocation": [],
    "oneDriveLocation": []
  },

  "event": {
    "create": false,
    "name": "Employee 30294 separated",
    "comment": "Illustrative trigger event. create=false by default so deploy does NOT start a live retention clock. Set create=true (or run with -TriggerEvent) only for a real, dated separation, scoped to that employee's own records.",
    "eventDateTime": "2026-09-08T00:00:00Z",
    "sharePointAssetIdQuery": "ComplianceAssetID:EE-30294",
    "exchangeAssetIdQuery": ""
  }
}
```

#### `New-MultiStageDispositionReview.ps1`

```powershell
#Requires -Version 7.0
<#
.SYNOPSIS
    Builds an event-based records-disposition lifecycle whose disposal requires sequential sign-off
    from up to 5 reviewer STAGES (a multi-stage disposition review panel) instead of a single reviewer
    set - using Security & Compliance PowerShell.

.DESCRIPTION
    Extends the single-reviewer pattern in scenarios/records-management/regulatory-records-disposition/
    with -MultiStageReviewProperty on New-ComplianceTag, for records whose disposal needs a genuine
    sign-off CHAIN (e.g. HR -> Legal -> Records Management for employee separation records) because one
    approver isn't enough given the record's litigation/regulatory exposure. Builds:
      1. New-ComplianceRetentionEventType -> the event type (e.g. "Employee Separation")
      2. New-ComplianceTag                -> the record label: -RetentionType EventAgeInDays bound to the
                                             event type, -RetentionAction KeepAndDelete,
                                             -MultiStageReviewProperty (up to 5 stages / 10 reviewers per
                                             stage, JSON), optional -AutoApprovalPeriod, optional
                                             -ComplianceTagForNextStage, -IsRecordLabel
      3. New-RetentionCompliancePolicy    -> the publish policy (locations)
      4. New-RetentionComplianceRule      -> the rule that PUBLISHES the label (-PublishComplianceTag)
      5. (optional, gated) New-ComplianceRetentionEvent -> a dated event that STARTS the retention clock

    How a multi-stage review behaves (per Microsoft Learn "Disposition of content"): stages are
    sequential - a reviewer in Stage 1 who selects "Approve disposal" advances the item to Stage 2; only
    the FINAL stage's approval marks the item for permanent deletion. Any stage's reviewer can instead
    "Relabel" (apply a different retention label) or "Extend" (choose a new duration). If
    -AutoApprovalPeriod is set (7-365 days) and no reviewer acts within that window at a given stage, the
    item auto-advances to the next stage (or is auto-disposed if it was the final stage) - this is a real
    silent-approval risk for a sign-off chain and is called out in README.md Section 8/11.

    !!! MultiStageReviewProperty JSON note !!! Microsoft's own published syntax for this parameter shows
    reviewer values unquoted inside the JSON array (e.g. Reviewers":[jie@contoso.onmicrosoft.com]), which
    is not valid JSON as literally written. This script always emits properly quoted, valid JSON (built
    with ConvertTo-Json, not string concatenation) - see .NOTES.

    !!! -ComplianceTagForNextStage is undocumented by Microsoft !!! its own published parameter reference
    leaves the description as an unfilled placeholder. This script passes it through ONLY if
    label.complianceTagForNextStage is set in the config (default: null / omitted) - see .NOTES and
    README.md Section 11 before relying on it.

    Idempotent: each object is located by name via Get-* before create; if present it is reported
    (records objects are high-consequence and not silently mutated - this includes NOT retrofitting a
    multi-stage panel onto an already-existing label via Set-ComplianceTag, even though Set-ComplianceTag
    documents the same parameter, because changing reviewers on a label already in use is a deliberate,
    reviewed action, not a deploy side effect). Re-running is safe. -WhatIf is non-functional in Security
    & Compliance PowerShell, so this script implements its own -DryRun that prints the intended cmdlets
    and runs none.

    !!! CREATING AN EVENT STARTS AN IRREVERSIBLE CLOCK !!! Same guardrail as the parent scenario: the
    trigger event is NEVER created unless BOTH the config's event.create is true AND -TriggerEvent is
    passed.

    Connect first: Connect-IPPSSession (certificate app-only preferred - docs/automation-surface.md
    Section 3). This script does not open the session.

.PARAMETER ConfigPath
    Path to the JSON config. Defaults to 'config/multi-stage-disposition-review.sample.json'.

.PARAMETER TriggerEvent
    Also create the trigger event from the config's 'event' block - but ONLY if event.create is true.
    Starts a real, irreversible retention clock. Requires Records/Legal sign-off.

.PARAMETER DryRun
    Print every mutating cmdlet that would run (including the exact -MultiStageReviewProperty JSON) and
    invoke none.

.EXAMPLE
    Connect-IPPSSession -AppId $AppId -Certificate $Cert -Organization 'contoso.onmicrosoft.com'
    ./New-MultiStageDispositionReview.ps1 -DryRun

.EXAMPLE
    Connect-IPPSSession -AppId $AppId -Certificate $Cert -Organization 'contoso.onmicrosoft.com'
    ./New-MultiStageDispositionReview.ps1        # builds type + label + publish policy; starts no clock

.EXAMPLE
    ./New-MultiStageDispositionReview.ps1 -TriggerEvent   # ALSO fires the event if event.create=true

.NOTES
    Grounded in Microsoft Learn (verify before production use):
    - New-ComplianceTag / Set-ComplianceTag (-MultiStageReviewProperty JSON syntax
      '{"MultiStageReviewSettings":[{"StageName":"Stage1","Reviewers":[...]},...]}'; -AutoApprovalPeriod
      7-365 days, default 14; -ComplianceTagForNextStage is a documented parameter whose description is
      an unfilled placeholder in Microsoft's own reference - behavior not confirmed):
      https://learn.microsoft.com/powershell/module/exchangepowershell/new-compliancetag
      https://learn.microsoft.com/powershell/module/exchangepowershell/set-compliancetag
    - Disposition of content (multi-stage review: up to 5 stages, up to 10 reviewers/stage - individual
      users or mail-enabled security groups, not M365 Groups; sequential stages; reviewer actions Approve
      disposal / Relabel / Extend / Add reviewers; auto-approval auto-advances a stage - or auto-disposes
      at the final stage - if no reviewer acts within the configured window):
      https://learn.microsoft.com/purview/disposition
    - Microsoft Graph records-management retentionLabel resource's analogous (but not confirmed
      identical) `labelToBeApplied` property - "the replacement label to be applied automatically after
      the retention period of the current label ends" - the closest documented description of what
      -ComplianceTagForNextStage likely does, cited here only as context, not as confirmed PowerShell
      behavior:
      https://learn.microsoft.com/graph/api/resources/security-retentionlabel
    - New-ComplianceRetentionEventType / New-ComplianceRetentionEvent; event-based retention:
      https://learn.microsoft.com/powershell/module/exchangepowershell/new-complianceretentioneventtype
      https://learn.microsoft.com/powershell/module/exchangepowershell/new-complianceretentionevent
      https://learn.microsoft.com/purview/event-driven-retention
    - New-RetentionCompliancePolicy / New-RetentionComplianceRule (-PublishComplianceTag):
      https://learn.microsoft.com/powershell/module/exchangepowershell/new-retentioncompliancerule
#>
[CmdletBinding()]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$ConfigPath = (Join-Path $PSScriptRoot 'config/multi-stage-disposition-review.sample.json'),

    [Parameter()]
    [switch]$TriggerEvent,

    [Parameter()]
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

function Assert-SccConnected {
    if (-not (Get-Command Get-ComplianceTag -ErrorAction SilentlyContinue)) {
        throw "Records management cmdlets not found. Connect first: Connect-IPPSSession (Security & Compliance PowerShell). See docs/automation-surface.md Section 3."
    }
}
function Invoke-Scc {
    param([Parameter(Mandatory)][string]$Describe, [Parameter(Mandatory)][scriptblock]$Action)
    if ($DryRun) { Write-Host "  DRYRUN would run: $Describe" -ForegroundColor DarkYellow; return $null }
    Write-Host "  $Describe" -ForegroundColor Green
    return & $Action
}

# Builds a VALID JSON string for -MultiStageReviewProperty. Microsoft's own published example shows
# reviewer values unquoted (not valid JSON); this always emits well-formed, quoted JSON via
# ConvertTo-Json so the cmdlet receives an unambiguous payload regardless of that documentation issue.
function New-MultiStageReviewJson {
    param([Parameter(Mandatory)][object[]]$Stages)
    if (@($Stages).Count -eq 0) { throw "multiStageReview.stages must have at least 1 stage." }
    if (@($Stages).Count -gt 5) { throw "multiStageReview.stages has $(@($Stages).Count) stages - Microsoft documents a maximum of 5 disposition-review stages." }
    $settings = foreach ($s in $Stages) {
        if (-not $s.stageName) { throw "Every multiStageReview stage requires a stageName." }
        $reviewers = @($s.reviewers)
        if ($reviewers.Count -eq 0) { throw "Stage '$($s.stageName)' has no reviewers - every stage requires at least 1." }
        if ($reviewers.Count -gt 10) { throw "Stage '$($s.stageName)' has $($reviewers.Count) reviewers - Microsoft documents a maximum of 10 reviewers per stage." }
        [PSCustomObject]@{ StageName = $s.stageName; Reviewers = $reviewers }
    }
    $payload = [PSCustomObject]@{ MultiStageReviewSettings = @($settings) }
    return ($payload | ConvertTo-Json -Depth 6 -Compress)
}

if (-not (Test-Path -LiteralPath $ConfigPath)) { throw "Config file not found: $ConfigPath" }
$cfg = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
foreach ($k in 'eventType', 'label', 'policy') { if (-not $cfg.$k) { throw "Config missing '$k' section." } }
if (-not $cfg.eventType.name) { throw "eventType.name is required." }
if (-not $cfg.label.name) { throw "label.name is required." }
if (-not $cfg.policy.name) { throw "policy.name is required." }
if (-not $cfg.label.multiStageReview -or -not $cfg.label.multiStageReview.enabled) {
    throw "label.multiStageReview.enabled must be true - this scenario builds a multi-stage panel. For a single-reviewer disposition, use scenarios/records-management/regulatory-records-disposition/ instead."
}
if ($cfg.label.autoApprovalPeriodDays) {
    $aap = [int]$cfg.label.autoApprovalPeriodDays
    if ($aap -lt 7 -or $aap -gt 365) { throw "label.autoApprovalPeriodDays is $aap - Microsoft documents a valid range of 7-365 days." }
    Write-Host "NOTE: autoApprovalPeriodDays=$aap - if a stage's reviewers take no action within $aap day(s), the item auto-advances (or, at the final stage, is auto-disposed) with NO human sign-off at that stage. See README.md Section 8/11." -ForegroundColor Yellow
}

Assert-SccConnected
Write-Host "Deploying multi-stage disposition review: event type '$($cfg.eventType.name)' + record label '$($cfg.label.name)' ($(@($cfg.label.multiStageReview.stages).Count) stage(s)) + publish policy '$($cfg.policy.name)'." -ForegroundColor Cyan

# --- 1. Event type (New-ComplianceRetentionEventType) ---
$existingType = Get-ComplianceRetentionEventType -Identity $cfg.eventType.name -ErrorAction SilentlyContinue
if ($existingType) {
    Write-Host "  [eventType] exists '$($cfg.eventType.name)'" -ForegroundColor DarkGreen
}
else {
    $etParams = @{ Name = $cfg.eventType.name }
    if ($cfg.eventType.comment) { $etParams.Comment = $cfg.eventType.comment }
    Invoke-Scc -Describe "New-ComplianceRetentionEventType -Name '$($cfg.eventType.name)'" `
        -Action { New-ComplianceRetentionEventType @etParams -Confirm:$false } | Out-Null
    Write-Host "  [eventType] created '$($cfg.eventType.name)'" -ForegroundColor Green
}

# --- 2. Multi-stage record label (New-ComplianceTag -MultiStageReviewProperty) ---
# NOTE: the event type must exist before the label references it. After a label is saved with an event
# type (and its reviewer stages), it is create-or-report, never mutate - see .DESCRIPTION.
$existingLabel = Get-ComplianceTag -Identity $cfg.label.name -ErrorAction SilentlyContinue
if ($existingLabel) {
    Write-Host "  [label] exists '$($cfg.label.name)' (not modified - to change the reviewer chain on a label already in use, edit deliberately with Set-ComplianceTag after Records/Legal/HR sign-off, outside this deploy)." -ForegroundColor DarkGreen
}
else {
    $msrJson = New-MultiStageReviewJson -Stages $cfg.label.multiStageReview.stages
    $dur = if ("$($cfg.label.retentionDurationDays)" -eq 'Unlimited') { 'Unlimited' } else { [int]$cfg.label.retentionDurationDays }
    $tagParams = @{
        Name                    = $cfg.label.name
        RetentionAction         = $cfg.label.retentionAction   # KeepAndDelete for retain-then-dispose
        RetentionType           = $cfg.label.retentionType      # EventAgeInDays for event-based
        RetentionDuration       = $dur
        EventType               = $cfg.eventType.name
        MultiStageReviewProperty = $msrJson
    }
    if ($cfg.label.comment) { $tagParams.Comment = $cfg.label.comment }
    if ($cfg.label.isRecordLabel) { $tagParams.IsRecordLabel = $true }
    if ($cfg.label.autoApprovalPeriodDays) { $tagParams.AutoApprovalPeriod = [int]$cfg.label.autoApprovalPeriodDays }
    if (-not [string]::IsNullOrWhiteSpace("$($cfg.label.complianceTagForNextStage)")) {
        Write-Host "  NOTE: complianceTagForNextStage is set but Microsoft's own parameter reference does not document its behavior (unfilled description). Passed through as configured - VERIFY before relying on it. See README.md Section 11." -ForegroundColor Yellow
        $tagParams.ComplianceTagForNextStage = $cfg.label.complianceTagForNextStage
    }

    $stageNames = ($cfg.label.multiStageReview.stages | ForEach-Object { $_.stageName }) -join ' -> '
    $desc = "New-ComplianceTag -Name '$($cfg.label.name)' -RetentionAction $($cfg.label.retentionAction) -RetentionType EventAgeInDays -RetentionDuration $dur -EventType '$($cfg.eventType.name)'$(if ($cfg.label.isRecordLabel) { ' -IsRecordLabel $true' }) -MultiStageReviewProperty <$(@($cfg.label.multiStageReview.stages).Count) stage(s): $stageNames>$(if ($cfg.label.autoApprovalPeriodDays) { " -AutoApprovalPeriod $($cfg.label.autoApprovalPeriodDays)" })"
    if ($DryRun) { Write-Host "    MultiStageReviewProperty JSON: $msrJson" -ForegroundColor DarkYellow }
    Invoke-Scc -Describe $desc -Action { New-ComplianceTag @tagParams -Confirm:$false } | Out-Null
    Write-Host "  [label] created '$($cfg.label.name)' ($(@($cfg.label.multiStageReview.stages).Count)-stage disposition review: $stageNames)" -ForegroundColor Green
}

# --- 3. Publish policy (New-RetentionCompliancePolicy) ---
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
    if ($cfg.policy.oneDriveLocation -and @($cfg.policy.oneDriveLocation).Count -gt 0) { $polParams.OneDriveLocation = @($cfg.policy.oneDriveLocation) }
    if (-not ($polParams.SharePointLocation -or $polParams.ExchangeLocation -or $polParams.OneDriveLocation)) {
        throw "policy needs at least one location (sharePointLocation / exchangeLocation / oneDriveLocation)."
    }
    Invoke-Scc -Describe "New-RetentionCompliancePolicy -Name '$($cfg.policy.name)' (publish policy, locations set)" `
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

# --- 5. Trigger event (New-ComplianceRetentionEvent) - GATED, IRREVERSIBLE ---
if ($TriggerEvent) {
    if (-not $cfg.event -or -not [bool]$cfg.event.create) {
        Write-Host "  [event] -TriggerEvent passed but config event.create is not true - refusing to fire an event. Set event.create=true for a real, dated event." -ForegroundColor Yellow
    }
    elseif (-not $cfg.event.name) {
        throw "event.name is required to create a trigger event."
    }
    else {
        Write-Host "WARNING: creating a retention EVENT starts an IRREVERSIBLE clock - it cannot be cancelled and deleting it later does NOT stop retention. Ensure Records/Legal/HR sign-off. See README.md Section 11." -ForegroundColor Red
        $evParams = @{ Name = $cfg.event.name; EventType = $cfg.eventType.name }
        if ($cfg.event.comment) { $evParams.Comment = $cfg.event.comment }
        if ($cfg.event.eventDateTime) { $evParams.EventDateTime = [datetime]$cfg.event.eventDateTime }
        if (-not [string]::IsNullOrWhiteSpace($cfg.event.sharePointAssetIdQuery)) { $evParams.SharePointAssetIdQuery = $cfg.event.sharePointAssetIdQuery }
        if (-not [string]::IsNullOrWhiteSpace($cfg.event.exchangeAssetIdQuery)) { $evParams.ExchangeAssetIdQuery = $cfg.event.exchangeAssetIdQuery }
        if (-not ($evParams.SharePointAssetIdQuery -or $evParams.ExchangeAssetIdQuery)) {
            Write-Host "  CAUTION: no asset-ID query set - the event will trigger retention for ALL content with this event type's label (every separated employee's records, not just this one). This is almost never intended." -ForegroundColor Red
        }
        Invoke-Scc -Describe "New-ComplianceRetentionEvent -Name '$($cfg.event.name)' -EventType '$($cfg.eventType.name)' -EventDateTime $($cfg.event.eventDateTime) (STARTS RETENTION CLOCK)" `
            -Action { New-ComplianceRetentionEvent @evParams -Confirm:$false } | Out-Null
        Write-Host "  [event] created '$($cfg.event.name)' - retention clock started (sync up to 7 days)." -ForegroundColor Green
    }
}
else {
    Write-Host "  [event] skipped (no -TriggerEvent) - type/label/publish-policy built, no retention clock started." -ForegroundColor DarkGray
}

Write-Host "`nDone." -ForegroundColor Cyan
Write-Host "Publishing can take up to 7 days to appear in apps; a created event syncs to labeled content up to 7 days. Validate with validate/Test-MultiStageDispositionReview.ps1 and review pending disposals in the portal (Records Management > Disposition)." -ForegroundColor Yellow
```

#### `Remove-MultiStageDispositionReview.ps1`

```powershell
#Requires -Version 7.0
<#
.SYNOPSIS
    Rolls back the multi-stage disposition review scenario: disables (or deletes) the publish policy so
    the record label is no longer offered, and optionally removes the label and event type - using
    Security & Compliance PowerShell.

.DESCRIPTION
    Safe-by-default rollback, identical shape to
    scenarios/records-management/regulatory-records-disposition/deploy/Remove-RecordsDisposition.ps1.
    With no switches it DISABLES the publish policy (the label stays defined, including its full
    multi-stage reviewer chain, but is no longer published to locations). -Delete removes the policy +
    rule and then ATTEMPTS to remove the label and the event type.

    What rollback CANNOT do (records-management reality - see rollback.md):
      - It cannot delete a record label that has already been applied to content, nor shorten its
        retention or edit its reviewer stages. Remove-ComplianceTag succeeds only for labels not applied
        and not in a policy.
      - It cannot cancel a retention EVENT already created, nor stop retention on content whose clock a
        prior event started.
      - It cannot cancel or reassign an in-flight disposition review that has already reached a reviewer
        - manage pending items in the portal (Records Management > Disposition), not here.

    Idempotent and non-destructive to records: objects that don't exist are reported and skipped; the
    label/event-type deletions are attempted only under -Delete and failures (e.g. label in use) are
    reported, not forced. -WhatIf is non-functional in Security & Compliance PowerShell, so this script
    implements its own -DryRun.

    Connect first: Connect-IPPSSession (docs/automation-surface.md Section 3).

.PARAMETER ConfigPath
    Path to the JSON config. Defaults to 'config/multi-stage-disposition-review.sample.json'.

.PARAMETER Delete
    Remove the publish policy + rule, then attempt Remove-ComplianceTag (label) and
    Remove-ComplianceRetentionEventType (event type). Without it, the policy is only disabled.

.PARAMETER DryRun
    Print every mutating cmdlet that would run and invoke none.

.EXAMPLE
    Connect-IPPSSession -AppId $AppId -Certificate $Cert -Organization 'contoso.onmicrosoft.com'
    ./Remove-MultiStageDispositionReview.ps1 -DryRun

.EXAMPLE
    ./Remove-MultiStageDispositionReview.ps1                # disable publish policy only
    ./Remove-MultiStageDispositionReview.ps1 -Delete        # remove policy/rule; try to remove label + event type

.NOTES
    Grounded in Microsoft Learn (verify before production use):
    - Remove-RetentionCompliancePolicy / Set-RetentionCompliancePolicy:
      https://learn.microsoft.com/powershell/module/exchangepowershell/set-retentioncompliancepolicy
    - Remove-ComplianceTag (deletes a label only if not applied and not in a policy):
      https://learn.microsoft.com/powershell/module/exchangepowershell/remove-compliancetag
    - Remove-ComplianceRetentionEventType:
      https://learn.microsoft.com/powershell/module/exchangepowershell/remove-complianceretentioneventtype
    - Events can't be cancelled once created: https://learn.microsoft.com/purview/event-driven-retention
#>
[CmdletBinding()]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$ConfigPath = (Join-Path $PSScriptRoot 'config/multi-stage-disposition-review.sample.json'),

    [Parameter()]
    [switch]$Delete,

    [Parameter()]
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

function Assert-SccConnected {
    if (-not (Get-Command Get-RetentionCompliancePolicy -ErrorAction SilentlyContinue)) {
        throw "Records management cmdlets not found. Connect first: Connect-IPPSSession. See docs/automation-surface.md Section 3."
    }
}
function Invoke-Scc {
    param([Parameter(Mandatory)][string]$Describe, [Parameter(Mandatory)][scriptblock]$Action)
    if ($DryRun) { Write-Host "  DRYRUN would run: $Describe" -ForegroundColor DarkYellow; return $null }
    Write-Host "  $Describe" -ForegroundColor Green
    return & $Action
}

if (-not (Test-Path -LiteralPath $ConfigPath)) { throw "Config file not found: $ConfigPath" }
$cfg = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
if (-not $cfg.policy.name) { throw "policy.name is required." }
if (-not $cfg.label.name) { throw "label.name is required." }

Assert-SccConnected
Write-Host "Rolling back multi-stage disposition review for publish policy '$($cfg.policy.name)'$(if ($Delete) { ' (with -Delete)' })." -ForegroundColor Cyan
Write-Host "NOTE: this never touches live retention or in-flight reviews - it cannot delete applied records, shorten retention, cancel a triggered event, or reach into a pending disposition item. See rollback.md." -ForegroundColor Yellow

# --- Publish policy: disable, or delete under -Delete ---
$policy = Get-RetentionCompliancePolicy -Identity $cfg.policy.name -ErrorAction SilentlyContinue
if (-not $policy) {
    Write-Host "  [policy] not found '$($cfg.policy.name)' - nothing to disable/remove." -ForegroundColor DarkGray
}
elseif ($Delete) {
    Invoke-Scc -Describe "Remove-RetentionCompliancePolicy -Identity '$($cfg.policy.name)' (removes policy + its rule)" `
        -Action { Remove-RetentionCompliancePolicy -Identity $cfg.policy.name -Confirm:$false } | Out-Null
    Write-Host "  [policy] removed '$($cfg.policy.name)'" -ForegroundColor Green
}
else {
    Invoke-Scc -Describe "Set-RetentionCompliancePolicy -Identity '$($cfg.policy.name)' -Enabled `$false (stop publishing the label)" `
        -Action { Set-RetentionCompliancePolicy -Identity $cfg.policy.name -Enabled $false -Confirm:$false } | Out-Null
    Write-Host "  [policy] disabled '$($cfg.policy.name)' (label no longer published; re-enable with the deploy)." -ForegroundColor Green
}

if (-not $Delete) {
    Write-Host "`nDone (disable-only). Re-run with -Delete to remove the policy/rule and attempt label + event-type removal." -ForegroundColor Cyan
    return
}

# --- Label: attempt delete (succeeds only if not applied and not in a policy) ---
$label = Get-ComplianceTag -Identity $cfg.label.name -ErrorAction SilentlyContinue
if (-not $label) {
    Write-Host "  [label] not found '$($cfg.label.name)' - skipping." -ForegroundColor DarkGray
}
else {
    try {
        Invoke-Scc -Describe "Remove-ComplianceTag -Identity '$($cfg.label.name)' (only if not applied / not in a policy)" `
            -Action { Remove-ComplianceTag -Identity $cfg.label.name -Confirm:$false } | Out-Null
        Write-Host "  [label] removed '$($cfg.label.name)'" -ForegroundColor Green
    }
    catch {
        Write-Host "  [label] NOT removed '$($cfg.label.name)': $($_.Exception.Message)" -ForegroundColor Yellow
        Write-Host "         A record label that has been applied cannot be deleted - this is expected. Leave it in place; its reviewer stages stay intact for records already relying on them." -ForegroundColor Yellow
    }
}

# --- Event type: attempt delete (succeeds only if no label references it) ---
$etype = Get-ComplianceRetentionEventType -Identity $cfg.eventType.name -ErrorAction SilentlyContinue
if (-not $etype) {
    Write-Host "  [eventType] not found '$($cfg.eventType.name)' - skipping." -ForegroundColor DarkGray
}
else {
    try {
        Invoke-Scc -Describe "Remove-ComplianceRetentionEventType -Identity '$($cfg.eventType.name)' (only if unreferenced)" `
            -Action { Remove-ComplianceRetentionEventType -Identity $cfg.eventType.name -Confirm:$false } | Out-Null
        Write-Host "  [eventType] removed '$($cfg.eventType.name)'" -ForegroundColor Green
    }
    catch {
        Write-Host "  [eventType] NOT removed '$($cfg.eventType.name)': $($_.Exception.Message)" -ForegroundColor Yellow
        Write-Host "         An event type still referenced by a label (or with triggered events) may not be removable - this is expected." -ForegroundColor Yellow
    }
}

Write-Host "`nDone." -ForegroundColor Cyan
Write-Host "Reminder: any event already triggered continues its retention clock; any in-flight disposition review continues at its current stage; content already retained/disposed is unaffected by this rollback. See rollback.md." -ForegroundColor Yellow
```