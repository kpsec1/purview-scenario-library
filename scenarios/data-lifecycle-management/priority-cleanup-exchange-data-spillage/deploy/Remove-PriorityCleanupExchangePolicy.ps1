#Requires -Version 7.0
<#
.SYNOPSIS
    Rolls back the Exchange priority cleanup deployment: disables (and optionally deletes) the
    policy/rule. The priority cleanup LABEL itself is intentionally not force-removed.

.DESCRIPTION
    Uses Security & Compliance PowerShell. Staged:
      Default    Disable the policy (Set-RetentionCompliancePolicy -Enabled $false) so it stops
                 identifying NEW items for deletion. Items already approved and deleted are gone -
                 disabling the policy cannot recover them. Items in the pending-approval queue that
                 have not yet completed all required approvals are NOT deleted by disabling the
                 policy, but Microsoft's own documentation states: "Although you can delete a
                 priority cleanup policy, if the approval process for it is complete, items might
                 still be permanently deleted" - disabling/deleting the POLICY does not reliably
                 stop an in-flight APPROVAL from completing. If items are already pending approval,
                 the only reliable stop is to have every remaining approver decline (Relabel) them
                 in the portal before disabling this policy.
      -Delete    Additionally delete the policy (Remove-RetentionCompliancePolicy) and its rule.

    The retention LABEL is NOT deleted by this script by default. Removing the label from content
    that was already deleted is meaningless (the content is gone); removing a label still applied
    to surviving content changes its retention state and should be a deliberate, reviewed action.

    -WhatIf is non-functional in Security & Compliance PowerShell, so this script implements -DryRun.
    Connect first with Connect-IPPSSession.

.PARAMETER ConfigPath
    Path to the same JSON config used to deploy. Defaults to
    'config/priority-cleanup-exchange.sample.json'. Only policy.name (and, with -TryRemoveLabel,
    label.name) are read here.

.PARAMETER Delete
    Delete the policy and its rule (not just disable).

.PARAMETER TryRemoveLabel
    Attempt to remove the retention label too (Remove-ComplianceTag). Reports rather than forces if
    the service refuses (e.g. the label is still applied to surviving content).

.PARAMETER DryRun
    Print the intended cmdlets and run none.

.EXAMPLE
    Connect-IPPSSession -AppId $AppId -Certificate $Cert -Organization 'contoso.onmicrosoft.com'
    ./Remove-PriorityCleanupExchangePolicy.ps1 -DryRun

.NOTES
    Grounded in Microsoft Learn: Set-/Remove-RetentionCompliancePolicy, Remove-ComplianceTag;
    priority cleanup approval-completion behavior.
    https://learn.microsoft.com/purview/priority-cleanup-exchange#limitations-of-priority-cleanup
#>
[CmdletBinding()]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$ConfigPath = (Join-Path $PSScriptRoot 'config/priority-cleanup-exchange.sample.json'),

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

Write-Host "IMPORTANT: if any items are currently pending approval in the portal (Data Lifecycle Management > Priority cleanup > Pending cleanups), disabling/deleting this policy does NOT reliably stop an in-flight approval from completing. Have remaining approvers decline (Relabel) pending items first if they must not be deleted. See this script's .DESCRIPTION." -ForegroundColor Red

$policy = Get-RetentionCompliancePolicy -PriorityCleanup -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq $cfg.policy.name }
if ($policy) {
    Invoke-Scc -Describe "Set-RetentionCompliancePolicy -Identity '$($cfg.policy.name)' -Enabled `$false" `
        -Action { Set-RetentionCompliancePolicy -Identity $cfg.policy.name -Enabled $false -Confirm:$false }
    Write-Host "  [disable] policy '$($cfg.policy.name)' disabled (stops identifying NEW items)." -ForegroundColor Yellow
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
            Write-Host "  [delete] label '$($cfg.label.name)' removed." -ForegroundColor Red
        }
        catch {
            Write-Warning "  Could not remove label '$($cfg.label.name)': $($_.Exception.Message). See rollback.md."
        }
    }
}

Write-Host "`nDone." -ForegroundColor Cyan
Write-Host "Content already permanently deleted by completed approvals cannot be recovered by this script, by any admin action, or by Microsoft - see rollback.md." -ForegroundColor Yellow
