#Requires -Modules @{ ModuleName = 'ExchangeOnlineManagement'; ModuleVersion = '3.2.0' }
<#
.SYNOPSIS
    Rolls back the PII-Exchange-ElevatedRisk-Block-AllExternal rule added by
    New-ExchangePiiElevatedRiskBlock.ps1, restoring the parent policy's other rules to their
    pre-Part-2 priority order.

.DESCRIPTION
    Two rollback modes:
      -Disable (default, recommended first step): sets the rule's action to audit-only
       (BlockAccess = $false) instead of removing it - reversible in seconds by re-running
       New-ExchangePiiElevatedRiskBlock.ps1 -Force, which restores BlockAccess = $true.
      -Purge: permanently removes the rule via Remove-DlpComplianceRule, then decompacts the
       parent policy's remaining rules back down by one priority slot each, preserving their
       relative order - the reverse of New-ExchangePiiElevatedRiskBlock.ps1's compaction (see that
       script's .NOTES and design.md §6). NOT reversible except by re-running
       New-ExchangePiiElevatedRiskBlock.ps1 from scratch.

    This script never touches the parent policy's other rules' conditions or actions - only their
    -Priority value (Purge mode only, to restore contiguous 0-based numbering).

    Idempotent: if the rule does not exist, the script reports that and exits cleanly.

.PARAMETER PolicyName
    Name of the parent DLP policy. Must match the -PolicyName used at deploy time.

.PARAMETER Purge
    Permanently delete the PII-Exchange-ElevatedRisk-Block-AllExternal rule and decompact the
    parent policy's remaining rules back to contiguous 0-based priorities, instead of disabling
    (audit-only) the rule's block action.

.PARAMETER WhatIf
    Standard PowerShell ShouldProcess dry-run.

.EXAMPLE
    Connect-IPPSSession -AppId $AppId -Certificate $Cert -Organization $TenantDomain
    ./Remove-ExchangePiiElevatedRiskBlock.ps1 -WhatIf

.EXAMPLE
    ./Remove-ExchangePiiElevatedRiskBlock.ps1
    # Switches the rule to audit-only (soft rollback) - keeps visibility, stops blocking.

.EXAMPLE
    ./Remove-ExchangePiiElevatedRiskBlock.ps1 -Purge
    # Permanently removes the rule and decompacts the parent policy's remaining rules back to
    # contiguous 0-based priorities in their original relative order.

.NOTES
    Sources: https://learn.microsoft.com/powershell/module/exchangepowershell/set-dlpcompliancerule
             https://learn.microsoft.com/powershell/module/exchangepowershell/remove-dlpcompliancerule
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$PolicyName = 'PII DLP - Exchange External Send Control',

    [Parameter()]
    [switch]$Purge
)

$ErrorActionPreference = 'Stop'

if (-not (Get-Command Get-DlpCompliancePolicy -ErrorAction SilentlyContinue)) {
    throw 'No Security & Compliance PowerShell session found. Run Connect-IPPSSession first (see docs/automation-surface.md).'
}

$newRuleName = 'PII-Exchange-ElevatedRisk-Block-AllExternal'
$rule = Get-DlpComplianceRule -Identity $newRuleName -ErrorAction SilentlyContinue

if (-not $rule) {
    Write-Host "Rule '$newRuleName' does not exist. Nothing to roll back." -ForegroundColor Yellow
    return
}

if ($Purge) {
    if ($PSCmdlet.ShouldProcess($newRuleName, 'Remove-DlpComplianceRule (permanent)')) {
        Remove-DlpComplianceRule -Identity $newRuleName -Confirm:$false -WhatIf:$WhatIfPreference
    }
    Write-Host "Permanently removed rule '$newRuleName'." -ForegroundColor Green

    # --- Decompact remaining rules: preserve their current relative order, reassign contiguous
    #     priorities starting at 0. Reverse of the compaction New-ExchangePiiElevatedRiskBlock.ps1
    #     performs. Applied lowest-target-priority-first (ascending) since removing the rule above
    #     already freed priority 0 - no collision risk restoring downward. -->
    $remainingRules = @(Get-DlpComplianceRule -Policy $PolicyName -ErrorAction SilentlyContinue)
    $orderedAscendingByCurrentPriority = $remainingRules | Sort-Object -Property Priority
    $targetPriority = 0
    $decompactionPlan = foreach ($r in $orderedAscendingByCurrentPriority) {
        [PSCustomObject]@{ Name = $r.Name; CurrentPriority = $r.Priority; TargetPriority = $targetPriority }
        $targetPriority++
    }

    foreach ($entry in ($decompactionPlan | Sort-Object -Property TargetPriority)) {
        if ($entry.CurrentPriority -ne $entry.TargetPriority) {
            if ($PSCmdlet.ShouldProcess($entry.Name, "Set-DlpComplianceRule -Priority $($entry.TargetPriority)")) {
                Set-DlpComplianceRule -Identity $entry.Name -Priority $entry.TargetPriority -WhatIf:$WhatIfPreference
            }
            Write-Host "Restored rule '$($entry.Name)' to priority $($entry.TargetPriority)." -ForegroundColor Green
        }
    }
}
else {
    if ($PSCmdlet.ShouldProcess($newRuleName, 'Set-DlpComplianceRule -BlockAccess $false (audit-only)')) {
        Set-DlpComplianceRule -Identity $newRuleName -BlockAccess $false -WhatIf:$WhatIfPreference
    }
    Write-Host "Rule '$newRuleName' switched to audit-only. Re-run New-ExchangePiiElevatedRiskBlock.ps1 -Force to restore blocking." -ForegroundColor Green
}
