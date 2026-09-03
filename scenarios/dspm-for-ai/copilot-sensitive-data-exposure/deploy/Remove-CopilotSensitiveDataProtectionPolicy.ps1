#Requires -Modules @{ ModuleName = 'ExchangeOnlineManagement'; ModuleVersion = '3.2.0' }
<#
.SYNOPSIS
    Disables (default) or permanently removes (-Purge) the "Copilot DLP - Sensitive Data Exposure
    Protection" DLP policy.

.DESCRIPTION
    Default behavior is reversible: sets the policy Mode to Disable, leaving the policy and its
    two rules intact and re-enable-able (Set-DlpCompliancePolicy -Mode Enable). Pass -Purge to
    permanently delete the policy and its rules via Remove-DlpCompliancePolicy - not reversible.

    Author-only reference code. Never runs against a live tenant without an explicit
    Connect-IPPSSession call made by the operator first.

.PARAMETER PolicyName
    Name of the DLP policy to disable or remove. Must match the -PolicyName used at deploy time.

.PARAMETER Purge
    Permanently deletes the policy and its rules instead of disabling. Not reversible - see
    rollback.md.

.PARAMETER WhatIf
    Standard PowerShell ShouldProcess dry-run.

.EXAMPLE
    Connect-IPPSSession -AppId $AppId -Certificate $Cert -Organization $TenantDomain
    ./Remove-CopilotSensitiveDataProtectionPolicy.ps1 -WhatIf

.EXAMPLE
    ./Remove-CopilotSensitiveDataProtectionPolicy.ps1
    # Disables (reversible)

.EXAMPLE
    ./Remove-CopilotSensitiveDataProtectionPolicy.ps1 -Purge
    # Permanently deletes the policy and its rules

.NOTES
    Sources (Microsoft Learn):
    - Set-DlpCompliancePolicy -Mode Disable: https://learn.microsoft.com/powershell/module/exchangepowershell/set-dlpcompliancepolicy
    - Remove-DlpCompliancePolicy reference: https://learn.microsoft.com/powershell/module/exchangepowershell/remove-dlpcompliancepolicy
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$PolicyName = 'Copilot DLP - Sensitive Data Exposure Protection',

    [Parameter()]
    [switch]$Purge
)

$ErrorActionPreference = 'Stop'

if (-not (Get-Command Get-DlpCompliancePolicy -ErrorAction SilentlyContinue)) {
    throw 'No Security & Compliance PowerShell session found. Run Connect-IPPSSession first (see docs/automation-surface.md).'
}

$policy = Get-DlpCompliancePolicy -Identity $PolicyName -ErrorAction SilentlyContinue
if (-not $policy) {
    Write-Host "Policy '$PolicyName' not found. Nothing to do." -ForegroundColor Yellow
    return
}

if ($Purge) {
    if ($PSCmdlet.ShouldProcess($PolicyName, 'Remove-DlpCompliancePolicy (permanent - removes the policy and its rules)')) {
        Remove-DlpCompliancePolicy -Identity $PolicyName -Confirm:$false -WhatIf:$WhatIfPreference
    }
    Write-Host "Permanently removed policy '$PolicyName' and its rules." -ForegroundColor Red
}
else {
    if ($PSCmdlet.ShouldProcess($PolicyName, 'Set-DlpCompliancePolicy -Mode Disable')) {
        Set-DlpCompliancePolicy -Identity $PolicyName -Mode Disable -WhatIf:$WhatIfPreference
    }
    Write-Host "Disabled policy '$PolicyName' (reversible - re-enable with Set-DlpCompliancePolicy -Identity '$PolicyName' -Mode Enable)." -ForegroundColor Yellow
}
