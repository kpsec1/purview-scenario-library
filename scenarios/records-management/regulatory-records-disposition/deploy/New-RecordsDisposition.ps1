#Requires -Version 7.0
<#
.SYNOPSIS
    Builds an event-based records-disposition lifecycle: an event TYPE, a record retention label whose
    retention clock starts on that event and ends in a DISPOSITION REVIEW, a policy that PUBLISHES the
    label, and (optionally, gated) a trigger EVENT - using Security & Compliance PowerShell.

.DESCRIPTION
    Uses the Records Management cmdlets in Security & Compliance PowerShell (automation surface 2 per
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
