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
