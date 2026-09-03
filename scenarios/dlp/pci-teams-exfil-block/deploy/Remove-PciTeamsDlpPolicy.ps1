#Requires -Modules @{ ModuleName = 'ExchangeOnlineManagement'; ModuleVersion = '3.2.0' }
<#
.SYNOPSIS
    Removes (or disables) the "PCI DSS - Teams Card Data Exfiltration Block" DLP policy.

.DESCRIPTION
    Two rollback modes:
      -Disable (default, recommended first step): sets the policy Mode to Disable. Reversible in
       seconds via Set-DlpCompliancePolicy -Mode Enable. No history is lost.
      -Purge: permanently deletes the policy and its three rules via Remove-DlpCompliancePolicy.
       Removing the policy also removes its rules (Microsoft Learn: remove-dlpcompliancepolicy).
       This is NOT reversible - re-deploying requires re-running New-PciTeamsDlpPolicy.ps1.

    Idempotent: if the policy does not exist, the script reports that and exits cleanly rather
    than erroring.

.PARAMETER PolicyName
    Name of the DLP policy to roll back. Must match the -PolicyName used at deploy time.

.PARAMETER Purge
    Permanently delete the policy instead of disabling it. See rollback.md for the recommended
    disable-first, purge-later sequence.

.PARAMETER WhatIf
    Standard PowerShell ShouldProcess dry-run - reports the disable/removal that would happen
    without calling Set-DlpCompliancePolicy / Remove-DlpCompliancePolicy.

.EXAMPLE
    Connect-IPPSSession -AppId $AppId -Certificate $Cert -Organization $TenantDomain
    ./Remove-PciTeamsDlpPolicy.ps1 -WhatIf

.EXAMPLE
    ./Remove-PciTeamsDlpPolicy.ps1
    # Disables the policy (soft rollback).

.EXAMPLE
    ./Remove-PciTeamsDlpPolicy.ps1 -Purge
    # Permanently deletes the policy and its rules.

.NOTES
    Sources: https://learn.microsoft.com/powershell/module/exchangepowershell/set-dlpcompliancepolicy
             https://learn.microsoft.com/powershell/module/exchangepowershell/remove-dlpcompliancepolicy
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

$policy = Get-DlpCompliancePolicy -Identity $PolicyName -ErrorAction SilentlyContinue

if (-not $policy) {
    Write-Host "Policy '$PolicyName' does not exist. Nothing to roll back." -ForegroundColor Yellow
    return
}

if ($Purge) {
    if ($PSCmdlet.ShouldProcess($PolicyName, 'Remove-DlpCompliancePolicy (permanent, also removes its rules)')) {
        Remove-DlpCompliancePolicy -Identity $PolicyName -Confirm:$false -WhatIf:$WhatIfPreference
    }
    Write-Host "Permanently removed policy '$PolicyName' and its rules." -ForegroundColor Green
}
else {
    if ($PSCmdlet.ShouldProcess($PolicyName, 'Set-DlpCompliancePolicy -Mode Disable')) {
        Set-DlpCompliancePolicy -Identity $PolicyName -Mode Disable -WhatIf:$WhatIfPreference
    }
    Write-Host "Disabled policy '$PolicyName'. Re-enable with: Set-DlpCompliancePolicy -Identity '$PolicyName' -Mode Enable" -ForegroundColor Green
}
