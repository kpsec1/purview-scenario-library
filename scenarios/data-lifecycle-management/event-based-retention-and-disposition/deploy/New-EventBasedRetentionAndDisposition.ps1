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
