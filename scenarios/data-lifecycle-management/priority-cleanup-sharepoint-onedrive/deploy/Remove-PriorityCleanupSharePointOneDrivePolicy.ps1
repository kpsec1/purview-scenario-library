#Requires -Version 7.0
<#
.SYNOPSIS
    Rolls back the SharePoint/OneDrive priority cleanup deployment: disables (and optionally
    deletes) the policy/rule. The priority cleanup LABEL itself is intentionally not force-removed.

.DESCRIPTION
    Uses Security & Compliance PowerShell. Staged:
      Default    Disable the policy (Set-RetentionCompliancePolicy -Enabled $false) so it stops
                 identifying NEW items. Items already moved to the second-stage Recycle Bin are
                 unaffected by disabling this policy - from there they follow ordinary
                 SharePoint/OneDrive Recycle Bin retention timers, the same as any other deleted
                 item (this scenario does not use the separate permanent-deletion sub-feature).
                 Items in the pending-approval queue that have not yet completed a required
                 eDiscovery-admin approval are NOT moved by disabling the policy, but Microsoft's
                 own documentation states: "Although you can delete a priority cleanup policy, if
                 the approval process for it is complete, items might still be deleted" - disabling/
                 deleting the POLICY does not reliably stop an in-flight APPROVAL from completing.
                 If items are pending and must not be moved, have every remaining approver decline
                 (Relabel) them in the portal first.
      -Delete    Additionally delete the policy (Remove-RetentionCompliancePolicy) and its rule.

    The retention LABEL is NOT deleted by this script by default - removing a label still applied
    to surviving content changes its retention state and should be a deliberate, reviewed action.

    -WhatIf is non-functional in Security & Compliance PowerShell, so this script implements -DryRun.
    Connect first with Connect-IPPSSession.

.PARAMETER ConfigPath
    Path to the same JSON config used to deploy. Defaults to
    'config/priority-cleanup-sharepoint-onedrive.sample.json'. Only policy.name (and, with
    -TryRemoveLabel, label.name) are read here.

.PARAMETER Delete
    Delete the policy and its rule (not just disable).

.PARAMETER TryRemoveLabel
    Attempt to remove the retention label too (Remove-ComplianceTag). Reports rather than forces if
    the service refuses (e.g. the label is still applied to surviving content).

.PARAMETER DryRun
    Print the intended cmdlets and run none.

.EXAMPLE
    Connect-IPPSSession -AppId $AppId -Certificate $Cert -Organization 'contoso.onmicrosoft.com'
    ./Remove-PriorityCleanupSharePointOneDrivePolicy.ps1 -DryRun

.NOTES
    Grounded in Microsoft Learn: Set-/Remove-RetentionCompliancePolicy, Remove-ComplianceTag;
    priority cleanup approval-completion behavior.
    https://learn.microsoft.com/purview/priority-cleanup-onedrive-sharepoint#limitations-of-priority-cleanup
#>
[CmdletBinding()]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$ConfigPath = (Join-Path $PSScriptRoot 'config/priority-cleanup-sharepoint-onedrive.sample.json'),

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

Write-Host "IMPORTANT: if any items are currently pending eDiscovery-admin approval in the portal (Data Lifecycle Management > Priority cleanup > Pending cleanups), disabling/deleting this policy does NOT reliably stop an in-flight approval from completing. Have the remaining approver decline (Relabel) pending items first if they must not move to the Recycle Bin. See this script's .DESCRIPTION." -ForegroundColor Red

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
Write-Host "Items already moved to the second-stage Recycle Bin by a completed disposal are not restored by this script - recover them from the Recycle Bin (within its retention window) if needed, per rollback.md." -ForegroundColor Yellow
