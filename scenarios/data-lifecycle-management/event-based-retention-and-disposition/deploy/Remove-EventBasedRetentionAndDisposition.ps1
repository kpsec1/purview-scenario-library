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
