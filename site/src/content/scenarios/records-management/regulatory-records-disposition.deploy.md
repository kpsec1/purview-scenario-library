---
part: "deploy"
parent: "records-management/regulatory-records-disposition"
---
The scripts and configuration below deploy this scenario. Review them, then run in order — each is designed to be idempotent and has a matching rollback.


#### `config/records-disposition.sample.json`

```json
{
  "_comment": "Config for deploy/New-RecordsDisposition.ps1. Author-only reference data - NOT applied to any tenant unless passed to the deploy script without -DryRun. Builds an event-based records-disposition lifecycle: an event TYPE, a record retention label whose clock starts on that event (KeepAndDelete + disposition review), a PUBLISH policy that makes the label selectable, and an optional trigger EVENT. Placeholder values below are illustrative - set them to your real records schedule and reviewers, validated by Records/Legal, before deploying. Read README.md Sections 2 and 11 first - a triggered event and an applied record label are IRREVERSIBLE.",

  "eventType": {
    "name": "Contract Expiration",
    "comment": "Triggers the retention clock for contract records when a contract expires. Created via New-ComplianceRetentionEventType."
  },

  "label": {
    "name": "Contract Records - 7yr after expiry",
    "comment": "Record label for contract records. Retention starts on a Contract Expiration event; disposed via disposition review after 7 years.",
    "retentionAction": "KeepAndDelete",
    "retentionDurationDays": 2555,
    "retentionType": "EventAgeInDays",
    "isRecordLabel": true,
    "reviewerEmail": [
      "records-managers@contoso.com"
    ],
    "autoApprovalPeriodDays": null
  },

  "policy": {
    "name": "Publish - Contract Records",
    "comment": "Publishes the contract-records label so it can be applied (manually or via default library label) in the target locations.",
    "enabled": true,
    "sharePointLocation": [
      "https://contoso.sharepoint.com/sites/Contracts"
    ],
    "exchangeLocation": [],
    "oneDriveLocation": []
  },

  "event": {
    "create": false,
    "name": "Contract 4815 expired",
    "comment": "Illustrative trigger event. create=false by default so deploy does NOT start a live retention clock. Set create=true (or run with -TriggerEvent) only for a real, dated event.",
    "eventDateTime": "2026-09-04T00:00:00Z",
    "sharePointAssetIdQuery": "ComplianceAssetID:4815",
    "exchangeAssetIdQuery": ""
  }
}
```

#### `New-RecordsDisposition.ps1`

```powershell
#Requires -Version 7.0
<#
.SYNOPSIS
    Builds an event-based records-disposition lifecycle: an event TYPE, a record retention label whose
    retention clock starts on that event and ends in a DISPOSITION REVIEW, a policy that PUBLISHES the
    label, and (optionally, gated) a trigger EVENT - using Security & Compliance PowerShell.

.DESCRIPTION
    Uses the Records Management cmdlets in Security & Compliance PowerShell (automation surface 1 per
    docs/automation-surface.md):
      1. New-ComplianceRetentionEventType -> the event type (e.g. "Contract Expiration")
      2. New-ComplianceTag                -> the record label: -RetentionType EventAgeInDays bound to the
                                             event type, -RetentionAction KeepAndDelete, disposition
                                             review via -ReviewerEmail, -IsRecordLabel
      3. New-RetentionCompliancePolicy    -> the publish policy (locations)
      4. New-RetentionComplianceRule      -> the rule that PUBLISHES the label (-PublishComplianceTag)
      5. (optional, gated) New-ComplianceRetentionEvent -> a dated event that STARTS the retention clock

    Why this is a distinct records-management scenario (vs. the DLM regulatory-retention one): here the
    retention period is driven by a business EVENT (contract expiry, employee departure, product end-of-
    life), not the age of the content, and disposal is a reviewed decision (disposition review), not an
    automatic delete. That is the core records-management lifecycle: declare -> retain-until-event ->
    review -> dispose, with proof at each step.

    Idempotent: each object is located by name via Get-* before create; if present it is reported
    (records objects are high-consequence and not silently mutated). Re-running is safe. -WhatIf is
    non-functional in Security & Compliance PowerShell, so this script implements its own -DryRun that
    prints the intended cmdlets and runs none.

    !!! CREATING AN EVENT STARTS AN IRREVERSIBLE CLOCK !!! A retention event, once created, cannot be
    cancelled and its effect on already-labeled content cannot be undone (deleting the event does NOT
    stop retention). So the trigger event is NEVER created unless BOTH the config's event.create is true
    AND -TriggerEvent is passed. Building the type/label/policy is safe and starts no clock.

    Connect first: Connect-IPPSSession (certificate app-only preferred - docs/automation-surface.md
    Section 3). This script does not open the session.

.PARAMETER ConfigPath
    Path to the JSON config. Defaults to 'config/records-disposition.sample.json'.

.PARAMETER TriggerEvent
    Also create the trigger event from the config's 'event' block - but ONLY if event.create is true.
    Starts a real, irreversible retention clock. Requires Records/Legal sign-off. Omit to build only the
    type/label/publish-policy (starts no clock).

.PARAMETER DryRun
    Print every mutating cmdlet that would run and invoke none (the working substitute for -WhatIf,
    which does not function in Security & Compliance PowerShell).

.EXAMPLE
    Connect-IPPSSession -AppId $AppId -Certificate $Cert -Organization 'contoso.onmicrosoft.com'
    ./New-RecordsDisposition.ps1 -DryRun

.EXAMPLE
    Connect-IPPSSession -AppId $AppId -Certificate $Cert -Organization 'contoso.onmicrosoft.com'
    ./New-RecordsDisposition.ps1            # builds type + label + publish policy; starts no clock

.EXAMPLE
    ./New-RecordsDisposition.ps1 -TriggerEvent   # ALSO fires the event (irreversible) if event.create=true

.NOTES
    Grounded in Microsoft Learn (verify before production use):
    - New-ComplianceTag (retention label; -RetentionType EventAgeInDays, -EventType, -RetentionAction
      KeepAndDelete, -ReviewerEmail, -IsRecordLabel, -AutoApprovalPeriod):
      https://learn.microsoft.com/powershell/module/exchangepowershell/new-compliancetag
    - New-ComplianceRetentionEventType / New-ComplianceRetentionEvent:
      https://learn.microsoft.com/powershell/module/exchangepowershell/new-complianceretentioneventtype
      https://learn.microsoft.com/powershell/module/exchangepowershell/new-complianceretentionevent
    - New-RetentionCompliancePolicy / New-RetentionComplianceRule (-PublishComplianceTag):
      https://learn.microsoft.com/powershell/module/exchangepowershell/new-retentioncompliancerule
    - Event-based retention; disposition of content / disposition reviews:
      https://learn.microsoft.com/purview/event-driven-retention
      https://learn.microsoft.com/purview/disposition
#>
[CmdletBinding()]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$ConfigPath = (Join-Path $PSScriptRoot 'config/records-disposition.sample.json'),

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

if (-not (Test-Path -LiteralPath $ConfigPath)) { throw "Config file not found: $ConfigPath" }
$cfg = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
foreach ($k in 'eventType', 'label', 'policy') { if (-not $cfg.$k) { throw "Config missing '$k' section." } }
if (-not $cfg.eventType.name) { throw "eventType.name is required." }
if (-not $cfg.label.name) { throw "label.name is required." }
if (-not $cfg.policy.name) { throw "policy.name is required." }
if (-not $cfg.label.reviewerEmail -or @($cfg.label.reviewerEmail).Count -eq 0) {
    Write-Host "NOTE: label.reviewerEmail is empty - the label will auto-delete at end of retention with NO disposition review. For a reviewed disposition (records-management best practice), set reviewerEmail." -ForegroundColor Yellow
}

Assert-SccConnected
Write-Host "Deploying records disposition: event type '$($cfg.eventType.name)' + record label '$($cfg.label.name)' + publish policy '$($cfg.policy.name)'." -ForegroundColor Cyan

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

# --- 2. Event-based record label (New-ComplianceTag) ---
# NOTE: the event type must exist before the label references it (-EventType). After a label is saved
# with an event type, the event type can't be changed - so this is create-or-report, never mutate.
$existingLabel = Get-ComplianceTag -Identity $cfg.label.name -ErrorAction SilentlyContinue
if ($existingLabel) {
    Write-Host "  [label] exists '$($cfg.label.name)' (not modified - record labels are high-consequence; edit deliberately)." -ForegroundColor DarkGreen
}
else {
    $dur = if ("$($cfg.label.retentionDurationDays)" -eq 'Unlimited') { 'Unlimited' } else { [int]$cfg.label.retentionDurationDays }
    $tagParams = @{
        Name              = $cfg.label.name
        RetentionAction   = $cfg.label.retentionAction   # KeepAndDelete for retain-then-dispose
        RetentionType     = $cfg.label.retentionType      # EventAgeInDays for event-based
        RetentionDuration = $dur
        EventType         = $cfg.eventType.name
    }
    if ($cfg.label.comment) { $tagParams.Comment = $cfg.label.comment }
    if ($cfg.label.isRecordLabel) { $tagParams.IsRecordLabel = $true }
    if ($cfg.label.reviewerEmail -and @($cfg.label.reviewerEmail).Count -gt 0) { $tagParams.ReviewerEmail = @($cfg.label.reviewerEmail) }
    if ($cfg.label.autoApprovalPeriodDays) { $tagParams.AutoApprovalPeriod = [int]$cfg.label.autoApprovalPeriodDays }

    $reviewNote = if ($tagParams.ReviewerEmail) { " -ReviewerEmail <$(@($tagParams.ReviewerEmail).Count) reviewer(s)>" } else { ' (no disposition review - auto-delete)' }
    $desc = "New-ComplianceTag -Name '$($cfg.label.name)' -RetentionAction $($cfg.label.retentionAction) -RetentionType EventAgeInDays -RetentionDuration $dur -EventType '$($cfg.eventType.name)'$(if ($cfg.label.isRecordLabel) { ' -IsRecordLabel $true' })$reviewNote"
    Invoke-Scc -Describe $desc -Action { New-ComplianceTag @tagParams -Confirm:$false } | Out-Null
    Write-Host "  [label] created '$($cfg.label.name)' (event-based record; disposal via disposition review)" -ForegroundColor Green
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
        Write-Host "WARNING: creating a retention EVENT starts an IRREVERSIBLE clock - it cannot be cancelled and deleting it later does NOT stop retention. Ensure Records/Legal sign-off. See README.md Section 11." -ForegroundColor Red
        $evParams = @{ Name = $cfg.event.name; EventType = $cfg.eventType.name }
        if ($cfg.event.comment) { $evParams.Comment = $cfg.event.comment }
        if ($cfg.event.eventDateTime) { $evParams.EventDateTime = [datetime]$cfg.event.eventDateTime }
        if (-not [string]::IsNullOrWhiteSpace($cfg.event.sharePointAssetIdQuery)) { $evParams.SharePointAssetIdQuery = $cfg.event.sharePointAssetIdQuery }
        if (-not [string]::IsNullOrWhiteSpace($cfg.event.exchangeAssetIdQuery)) { $evParams.ExchangeAssetIdQuery = $cfg.event.exchangeAssetIdQuery }
        if (-not ($evParams.SharePointAssetIdQuery -or $evParams.ExchangeAssetIdQuery)) {
            Write-Host "  CAUTION: no asset-ID query set - the event will trigger retention for ALL content with this event type's label. This is rarely intended." -ForegroundColor Red
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
Write-Host "Publishing can take up to 7 days to appear in apps; a created event syncs to labeled content up to 7 days. Validate with validate/Test-RecordsDisposition.ps1 and review disposition items in the portal (Records Management > Disposition)." -ForegroundColor Yellow
```

#### `Remove-RecordsDisposition.ps1`

```powershell
#Requires -Version 7.0
<#
.SYNOPSIS
    Rolls back the event-based records-disposition scenario: disables (or deletes) the publish policy so
    the record label is no longer offered, and optionally removes the label and event type - using
    Security & Compliance PowerShell.

.DESCRIPTION
    Safe-by-default rollback. With no switches it DISABLES the publish policy (the label stays defined
    but is no longer published to locations - stops the label being newly applied). -Delete removes the
    policy + rule and then ATTEMPTS to remove the label and the event type.

    What rollback CANNOT do (records-management reality - see rollback.md):
      - It cannot delete a record label that has already been applied to content, nor shorten its
        retention. Remove-ComplianceTag succeeds only for labels not applied and not in a policy.
      - It cannot cancel a retention EVENT already created, nor stop retention on content whose clock a
        prior event started. Deleting an event does not reverse its effect. There is no cmdlet here that
        touches live retention - by design.

    Idempotent and non-destructive to records: objects that don't exist are reported and skipped; the
    label/event-type deletions are attempted only under -Delete and failures (e.g. label in use) are
    reported, not forced. -WhatIf is non-functional in Security & Compliance PowerShell, so this script
    implements its own -DryRun.

    Connect first: Connect-IPPSSession (docs/automation-surface.md Section 3).

.PARAMETER ConfigPath
    Path to the JSON config. Defaults to 'config/records-disposition.sample.json'.

.PARAMETER Delete
    Remove the publish policy + rule, then attempt Remove-ComplianceTag (label) and
    Remove-ComplianceRetentionEventType (event type). Without it, the policy is only disabled.

.PARAMETER DryRun
    Print every mutating cmdlet that would run and invoke none.

.EXAMPLE
    Connect-IPPSSession -AppId $AppId -Certificate $Cert -Organization 'contoso.onmicrosoft.com'
    ./Remove-RecordsDisposition.ps1 -DryRun

.EXAMPLE
    ./Remove-RecordsDisposition.ps1                # disable publish policy only
    ./Remove-RecordsDisposition.ps1 -Delete        # remove policy/rule; try to remove label + event type

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
    [string]$ConfigPath = (Join-Path $PSScriptRoot 'config/records-disposition.sample.json'),

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
Write-Host "Rolling back records disposition for publish policy '$($cfg.policy.name)'$(if ($Delete) { ' (with -Delete)' })." -ForegroundColor Cyan
Write-Host "NOTE: this never touches live retention - it cannot delete applied records, shorten retention, or cancel a triggered event. See rollback.md." -ForegroundColor Yellow

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
        Write-Host "         A record label that has been applied cannot be deleted - this is expected. Leave it in place." -ForegroundColor Yellow
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
Write-Host "Reminder: any event already triggered continues its retention clock; content already retained/disposed is unaffected by this rollback. See rollback.md." -ForegroundColor Yellow
```