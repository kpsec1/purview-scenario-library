---
part: "validate"
parent: "records-management/multi-stage-disposition-review"
---
Run these checks after deployment to confirm the control is working as designed.


#### `Test-MultiStageDispositionReview.ps1`

```powershell
#Requires -Version 7.0
<#
.SYNOPSIS
    Verifies the multi-stage disposition-review lifecycle: the event type, the event-based record label
    (KeepAndDelete + a multi-stage reviewer chain, bound to the event type), the publish policy, and the
    publish rule exist and are configured as expected.

.DESCRIPTION
    Read-only - never modifies any object. Uses Security & Compliance PowerShell Get-* cmdlets to check,
    against the config file:
      1. The event type exists.
      2. The record label exists, is a record, uses RetentionAction=KeepAndDelete and
         RetentionType=EventAgeInDays, is bound to the event type.
      3. The label's multi-stage reviewer chain - stage count, stage names, reviewer counts - matches the
         config, read back from Get-ComplianceTag's MultiStageReviewerMetadata property. This property
         name/shape is corroborated by third-party worked examples of Get-ComplianceTag output, not by
         Microsoft's own published parameter reference (which does not document output properties for
         this feature) - see README.md Section 11. The check degrades to [WARN], never [FAIL], if the
         property is absent or differently shaped, so an unconfirmed read-back never blocks a pipeline.
      4. The publish policy exists and is enabled with at least one location.
      5. The policy's rule PUBLISHES the expected label (PublishComplianceTag).
      6. (Informational) reports any triggered events for the event type, and whether AutoApprovalPeriod
         is set (a silent-approval risk for a reviewer chain - see README.md Section 8).
    Exits non-zero on any hard failure (safe for a CI-style pre-flight). Safe to re-run.

    Connect first with Connect-IPPSSession. A View-Only role that can read retention configuration is
    sufficient.

.PARAMETER ConfigPath
    Path to the config to validate against. Defaults to
    '../deploy/config/multi-stage-disposition-review.sample.json'.

.EXAMPLE
    Connect-IPPSSession -AppId $AppId -Certificate $Cert -Organization 'contoso.onmicrosoft.com'
    ./Test-MultiStageDispositionReview.ps1
#>
[CmdletBinding()]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$ConfigPath = (Join-Path $PSScriptRoot '../deploy/config/multi-stage-disposition-review.sample.json')
)

$ErrorActionPreference = 'Stop'
$script:failures = 0
function Test-Check {
    param([string]$Description, [bool]$Condition, [switch]$Warn)
    if ($Condition) { Write-Host "  [PASS] $Description" -ForegroundColor Green }
    elseif ($Warn) { Write-Host "  [WARN] $Description" -ForegroundColor Yellow }
    else { Write-Host "  [FAIL] $Description" -ForegroundColor Red; $script:failures++ }
}

if (-not (Get-Command Get-ComplianceTag -ErrorAction SilentlyContinue)) {
    throw "Records management cmdlets not found. Connect first: Connect-IPPSSession. See docs/automation-surface.md Section 3."
}
if (-not (Test-Path -LiteralPath $ConfigPath)) { throw "Config file not found: $ConfigPath" }
$cfg = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
$expectedStages = @($cfg.label.multiStageReview.stages)

Write-Host "Validating multi-stage disposition review ('$($cfg.eventType.name)' / '$($cfg.label.name)' / '$($cfg.policy.name)')..." -ForegroundColor Cyan

# Event type
$etype = Get-ComplianceRetentionEventType -Identity $cfg.eventType.name -ErrorAction SilentlyContinue
Test-Check -Description "Event type '$($cfg.eventType.name)' exists" -Condition ($null -ne $etype)

# Label
$label = Get-ComplianceTag -Identity $cfg.label.name -ErrorAction SilentlyContinue
Test-Check -Description "Record label '$($cfg.label.name)' exists" -Condition ($null -ne $label)
if ($label) {
    Test-Check -Description "  RetentionAction is '$($cfg.label.retentionAction)' (current: $($label.RetentionAction))" `
        -Condition ("$($label.RetentionAction)" -eq "$($cfg.label.retentionAction)")
    Test-Check -Description "  RetentionType is EventAgeInDays (current: $($label.RetentionType))" `
        -Condition ("$($label.RetentionType)" -eq 'EventAgeInDays')
    if ("$($cfg.label.retentionDurationDays)" -ne 'Unlimited') {
        Test-Check -Description "  RetentionDuration is $($cfg.label.retentionDurationDays) days (current: $($label.RetentionDuration))" `
            -Condition ("$($label.RetentionDuration)" -eq "$($cfg.label.retentionDurationDays)") -Warn
    }
    Test-Check -Description "  Label bound to event type '$($cfg.eventType.name)' (current: $($label.EventType))" `
        -Condition ("$($label.EventType)" -eq "$($cfg.eventType.name)") -Warn
    if ($cfg.label.isRecordLabel) {
        Test-Check -Description "  Label is a record label" -Condition ([bool]$label.IsRecordLabel) -Warn
    }

    # Multi-stage reviewer chain read-back. Property name/shape (MultiStageReviewerMetadata with
    # StageId/StageName/Reviewers) is corroborated by third-party Get-ComplianceTag output examples, not
    # by Microsoft's own published reference - read defensively and never hard-fail on shape alone.
    $msrProp = $label.PSObject.Properties['MultiStageReviewerMetadata']
    if (-not $msrProp -or $null -eq $msrProp.Value) {
        Test-Check -Description "  Multi-stage reviewer metadata present on the label (property 'MultiStageReviewerMetadata' - VERIFY, see README.md Section 11)" -Condition $false -Warn
    }
    else {
        try {
            $stages = @($msrProp.Value | ConvertFrom-Json -ErrorAction Stop)
        }
        catch {
            $stages = @($msrProp.Value)
        }
        Test-Check -Description "  Multi-stage reviewer chain present ($(@($stages).Count) stage(s) read back)" -Condition (@($stages).Count -gt 0) -Warn
        Test-Check -Description "  Stage count matches config ($(@($expectedStages).Count) expected, $(@($stages).Count) found)" `
            -Condition (@($stages).Count -eq @($expectedStages).Count) -Warn
        for ($i = 0; $i -lt [Math]::Min(@($stages).Count, @($expectedStages).Count); $i++) {
            $actualName = $stages[$i].StageName
            if (-not $actualName) { $actualName = $stages[$i].stageName }
            Test-Check -Description "  Stage $($i + 1) name matches config ('$($expectedStages[$i].stageName)' expected, found '$actualName')" `
                -Condition ("$actualName" -eq "$($expectedStages[$i].stageName)") -Warn
        }
    }

    # AutoApprovalPeriod - informational, but flagged because it can silently advance/dispose a stage.
    $aapProp = $label.PSObject.Properties['AutoApprovalPeriod']
    if ($aapProp -and $aapProp.Value) {
        Write-Host "    AutoApprovalPeriod: $($aapProp.Value) day(s) - a stage with no reviewer action auto-advances (or auto-disposes, at the final stage) after this window. Confirm this is intended for every stage in the chain, not just non-critical ones." -ForegroundColor Yellow
    }
    else {
        Write-Host "    AutoApprovalPeriod: not set - a stalled stage waits indefinitely for a human reviewer (no silent-approval risk, but a backlog risk)." -ForegroundColor DarkGray
    }
}

# Publish policy
$policy = Get-RetentionCompliancePolicy -Identity $cfg.policy.name -ErrorAction SilentlyContinue
Test-Check -Description "Publish policy '$($cfg.policy.name)' exists" -Condition ($null -ne $policy)
if ($policy) {
    Test-Check -Description "  Policy is enabled" -Condition ([bool]$policy.Enabled) -Warn
    $hasLoc = (@($policy.SharePointLocation).Count -gt 0) -or (@($policy.ExchangeLocation).Count -gt 0) -or (@($policy.OneDriveLocation).Count -gt 0)
    Test-Check -Description "  Policy has at least one location" -Condition $hasLoc
    if ($policy.DistributionStatus) { Write-Host "    Distribution status: $($policy.DistributionStatus)" -ForegroundColor Cyan }
}

# Publish rule
$rule = Get-RetentionComplianceRule -Policy $cfg.policy.name -ErrorAction SilentlyContinue | Select-Object -First 1
Test-Check -Description "Publish rule exists on the policy" -Condition ($null -ne $rule)
if ($rule) {
    Test-Check -Description "  Rule publishes label '$($cfg.label.name)' (current: $($rule.PublishComplianceTag))" `
        -Condition ("$($rule.PublishComplianceTag)" -eq "$($cfg.label.name)")
}

# Triggered events (informational - a triggered event is an irreversible retention start)
$events = Get-ComplianceRetentionEvent -ErrorAction SilentlyContinue | Where-Object { "$($_.EventType)" -eq "$($cfg.eventType.name)" }
if (@($events).Count -gt 0) {
    Write-Host "    Triggered events for this event type: $(@($events).Count) (each started an irreversible retention clock)." -ForegroundColor Cyan
    foreach ($e in $events) { Write-Host "      - $($e.Name) @ $($e.EventDateTime)" -ForegroundColor DarkCyan }
}
else {
    Write-Host "    No events triggered yet for this event type - retention clock not started (expected for a fresh deploy)." -ForegroundColor DarkGray
}

Write-Host "`n  Note: publishing can take up to 7 days to reach apps; a triggered event syncs to labeled content up to 7 days. Review pending disposals and each stage's status in the portal (Records Management > Disposition)." -ForegroundColor Cyan
Write-Host "$(if ($script:failures -eq 0) { 'All hard checks passed.' } else { "$script:failures hard check(s) failed." })" `
    -ForegroundColor $(if ($script:failures -eq 0) { 'Green' } else { 'Red' })
if ($script:failures -gt 0) { exit 1 }
```