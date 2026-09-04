#Requires -Modules @{ ModuleName = 'ExchangeOnlineManagement'; ModuleVersion = '3.2.0' }
<#
.SYNOPSIS
    Rolls back the PCI-ElevatedRisk-Block-AllExternal rule added by
    New-PciElevatedRiskTeamsBlock.ps1, restoring Part 1's policy to its original three-rule state.

.DESCRIPTION
    Two rollback modes:
      -Disable (default, recommended first step): sets the rule's action to audit-only
       (BlockAccess = $false) instead of removing it - reversible in seconds by re-running
       New-PciElevatedRiskTeamsBlock.ps1 -Force, which restores BlockAccess = $true.
      -Purge: permanently removes the rule via Remove-DlpComplianceRule, then re-prioritizes
       Part 1's three original rules back to 0/1/2. NOT reversible except by re-running
       New-PciElevatedRiskTeamsBlock.ps1 from scratch.

    This script never touches Part 1's own three rules' conditions or actions - only their
    -Priority value (Purge mode only, to restore the original 0/1/2 ordering).

    Idempotent: if the rule does not exist, the script reports that and exits cleanly.

.PARAMETER PolicyName
    Name of the parent DLP policy. Must match the -PolicyName used at deploy time.

.PARAMETER Purge
    Permanently delete the PCI-ElevatedRisk-Block-AllExternal rule and restore Part 1's original
    rule priorities, instead of disabling (audit-only) the rule's block action.

.PARAMETER WhatIf
    Standard PowerShell ShouldProcess dry-run.

.EXAMPLE
    Connect-IPPSSession -AppId $AppId -Certificate $Cert -Organization $TenantDomain
    ./Remove-PciElevatedRiskTeamsBlock.ps1 -WhatIf

.EXAMPLE
    ./Remove-PciElevatedRiskTeamsBlock.ps1
    # Switches the rule to audit-only (soft rollback) - keeps visibility, stops blocking.

.EXAMPLE
    ./Remove-PciElevatedRiskTeamsBlock.ps1 -Purge
    # Permanently removes the rule and restores Part 1's original 0/1/2 priority order.

.NOTES
    Sources: https://learn.microsoft.com/powershell/module/exchangepowershell/set-dlpcompliancerule
             https://learn.microsoft.com/powershell/module/exchangepowershell/remove-dlpcompliancerule
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$PolicyName = 'PCI DSS - Teams Card Data Exfiltration Block',

    [Parameter()]
    [switch]$Purge
)

$ErrorActionPreference = 'Stop'

if (-not (Get-Command Get-DlpCompliancePolicy -ErrorAction SilentlyContinue)) {
    throw 'No Security & Compliance PowerShell session found. Run Connect-IPPSSession first (see docs/automation-surface.md).'
}

$newRuleName = 'PCI-ElevatedRisk-Block-AllExternal'
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

    $originalPriorities = @(
        @{ Name = 'PCI-CardOps-Override-External'; TargetPriority = 0 }
        @{ Name = 'PCI-Block-External-AllUsers'; TargetPriority = 1 }
        @{ Name = 'PCI-Audit-Internal-AllUsers'; TargetPriority = 2 }
    )
    # Ascending order this time (lowest target first) since removing the new rule already freed
    # priority 0 - no collision risk restoring downward.
    foreach ($entry in ($originalPriorities | Sort-Object -Property TargetPriority)) {
        $existing = Get-DlpComplianceRule -Identity $entry.Name -ErrorAction SilentlyContinue
        if ($existing -and $existing.Priority -ne $entry.TargetPriority) {
            if ($PSCmdlet.ShouldProcess($entry.Name, "Set-DlpComplianceRule -Priority $($entry.TargetPriority)")) {
                Set-DlpComplianceRule -Identity $entry.Name -Priority $entry.TargetPriority -WhatIf:$WhatIfPreference
            }
            Write-Host "Restored rule '$($entry.Name)' to its original priority $($entry.TargetPriority)." -ForegroundColor Green
        }
    }
}
else {
    if ($PSCmdlet.ShouldProcess($newRuleName, 'Set-DlpComplianceRule -BlockAccess $false (audit-only)')) {
        Set-DlpComplianceRule -Identity $newRuleName -BlockAccess $false -WhatIf:$WhatIfPreference
    }
    Write-Host "Rule '$newRuleName' switched to audit-only. Re-run New-PciElevatedRiskTeamsBlock.ps1 -Force to restore blocking." -ForegroundColor Green
}
