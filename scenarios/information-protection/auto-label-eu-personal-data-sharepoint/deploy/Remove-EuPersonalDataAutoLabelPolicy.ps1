#Requires -Modules @{ ModuleName = 'ExchangeOnlineManagement'; ModuleVersion = '3.2.0' }
<#
.SYNOPSIS
    Removes (or disables) the "Confidentiality - Auto-Label EU Personal Data in SharePoint and
    OneDrive" auto-labeling policy.

.DESCRIPTION
    Two rollback modes:
      -Disable (default, recommended first step): sets the policy Mode to Disable. Reversible in
       seconds via Set-AutoSensitivityLabelPolicy -Mode Enable. No history is lost, and labels
       already applied to files are not removed.
      -Purge: permanently deletes the policy and its two rules via
       Remove-AutoSensitivityLabelPolicy. Removing the policy also removes its rules. This is NOT
       reversible - re-deploying requires re-running New-EuPersonalDataAutoLabelPolicy.ps1. Labels
       already applied to files remain on those files; this does not remove labels retroactively.

    Idempotent: if the policy does not exist, the script reports that and exits cleanly rather
    than erroring.

.PARAMETER PolicyName
    Name of the auto-labeling policy to roll back. Must match the -PolicyName used at deploy time.

.PARAMETER Purge
    Permanently delete the policy instead of disabling it. See rollback.md for the recommended
    disable-first, purge-later sequence.

.PARAMETER WhatIf
    Standard PowerShell ShouldProcess dry-run - reports the disable/removal that would happen
    without calling Set-AutoSensitivityLabelPolicy / Remove-AutoSensitivityLabelPolicy.

.EXAMPLE
    Connect-IPPSSession -AppId $AppId -Certificate $Cert -Organization $TenantDomain
    ./Remove-EuPersonalDataAutoLabelPolicy.ps1 -WhatIf

.EXAMPLE
    ./Remove-EuPersonalDataAutoLabelPolicy.ps1
    # Disables the policy (soft rollback).

.EXAMPLE
    ./Remove-EuPersonalDataAutoLabelPolicy.ps1 -Purge
    # Permanently deletes the policy and its rules.

.NOTES
    Sources: https://learn.microsoft.com/powershell/module/exchangepowershell/set-autosensitivitylabelpolicy
             https://learn.microsoft.com/powershell/module/exchangepowershell/remove-autosensitivitylabelpolicy
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$PolicyName = 'Confidentiality - Auto-Label EU Personal Data in SharePoint and OneDrive',

    [Parameter()]
    [switch]$Purge
)

$ErrorActionPreference = 'Stop'

if (-not (Get-Command Get-AutoSensitivityLabelPolicy -ErrorAction SilentlyContinue)) {
    throw 'No Security & Compliance PowerShell session found. Run Connect-IPPSSession first (see docs/automation-surface.md).'
}

$policy = Get-AutoSensitivityLabelPolicy -Identity $PolicyName -ErrorAction SilentlyContinue

if (-not $policy) {
    Write-Host "Policy '$PolicyName' does not exist. Nothing to roll back." -ForegroundColor Yellow
    return
}

if ($Purge) {
    if ($PSCmdlet.ShouldProcess($PolicyName, 'Remove-AutoSensitivityLabelPolicy (permanent, also removes its rules)')) {
        Remove-AutoSensitivityLabelPolicy -Identity $PolicyName -Confirm:$false -WhatIf:$WhatIfPreference
    }
    Write-Host "Permanently removed policy '$PolicyName' and its rules. Labels already applied to files are not removed." -ForegroundColor Green
}
else {
    if ($PSCmdlet.ShouldProcess($PolicyName, 'Set-AutoSensitivityLabelPolicy -Mode Disable')) {
        Set-AutoSensitivityLabelPolicy -Identity $PolicyName -Mode Disable -WhatIf:$WhatIfPreference
    }
    Write-Host "Disabled policy '$PolicyName'. Re-enable with: Set-AutoSensitivityLabelPolicy -Identity '$PolicyName' -Mode Enable" -ForegroundColor Green
}
