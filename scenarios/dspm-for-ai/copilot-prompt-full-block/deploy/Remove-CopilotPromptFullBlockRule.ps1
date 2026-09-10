#Requires -Modules @{ ModuleName = 'ExchangeOnlineManagement'; ModuleVersion = '3.2.0' }
<#
.SYNOPSIS
    Disables (default) or permanently removes (-Purge) the "Copilot-Block-SensitivePrompts-
    FullResponse" DLP rule only - never touches the parent policy or its other rules.

.DESCRIPTION
    Default behavior is reversible: sets the rule's Disabled property to $true, leaving it defined
    and re-enable-able (Set-DlpComplianceRule -Disabled $false). Pass -Purge to permanently delete
    the rule via Remove-DlpComplianceRule - not reversible; re-establishing it means re-running
    deploy/Add-CopilotPromptFullBlockRule.ps1.

    Scoped to this one rule by design - the parent policy (scenarios/dspm-for-ai/
    copilot-sensitive-data-exposure) and its own Rule 0/Rule 1 are never modified by this script.

    Author-only reference code. Never runs against a live tenant without an explicit
    Connect-IPPSSession call made by the operator first.

.PARAMETER Purge
    Permanently deletes the rule instead of disabling it. Not reversible - see rollback.md.

.PARAMETER WhatIf
    Standard PowerShell ShouldProcess dry-run.

.EXAMPLE
    Connect-IPPSSession -AppId $AppId -Certificate $Cert -Organization $TenantDomain
    ./Remove-CopilotPromptFullBlockRule.ps1 -WhatIf

.EXAMPLE
    ./Remove-CopilotPromptFullBlockRule.ps1
    # Disables the rule (reversible)

.EXAMPLE
    ./Remove-CopilotPromptFullBlockRule.ps1 -Purge
    # Permanently deletes the rule

.NOTES
    Sources (Microsoft Learn):
    - Set-DlpComplianceRule reference (-Disabled parameter):
      https://learn.microsoft.com/powershell/module/exchangepowershell/set-dlpcompliancerule
    - Remove-DlpComplianceRule reference:
      https://learn.microsoft.com/powershell/module/exchangepowershell/remove-dlpcompliancerule
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter()]
    [switch]$Purge
)

$ErrorActionPreference = 'Stop'
$ruleName = 'Copilot-Block-SensitivePrompts-FullResponse'

if (-not (Get-Command Get-DlpComplianceRule -ErrorAction SilentlyContinue)) {
    throw 'No Security & Compliance PowerShell session found. Run Connect-IPPSSession first (see docs/automation-surface.md).'
}

$rule = Get-DlpComplianceRule -Identity $ruleName -ErrorAction SilentlyContinue
if (-not $rule) {
    Write-Host "Rule '$ruleName' not found. Nothing to do." -ForegroundColor Yellow
    return
}

if ($Purge) {
    if ($PSCmdlet.ShouldProcess($ruleName, 'Remove-DlpComplianceRule (permanent - this rule only)')) {
        Remove-DlpComplianceRule -Identity $ruleName -Confirm:$false -WhatIf:$WhatIfPreference
    }
    Write-Host "Permanently removed rule '$ruleName'. The parent policy and its other rules are unaffected." -ForegroundColor Red
}
else {
    if ($PSCmdlet.ShouldProcess($ruleName, 'Set-DlpComplianceRule -Disabled $true')) {
        Set-DlpComplianceRule -Identity $ruleName -Disabled $true -WhatIf:$WhatIfPreference
    }
    Write-Host "Disabled rule '$ruleName' (reversible - re-enable with Set-DlpComplianceRule -Identity '$ruleName' -Disabled `$false). The parent policy and its other rules are unaffected." -ForegroundColor Yellow
}
