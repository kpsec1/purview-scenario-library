#Requires -Modules @{ ModuleName = 'ExchangeOnlineManagement'; ModuleVersion = '3.2.0' }
<#
.SYNOPSIS
    Removes the "PII-Exchange-Audit-Encrypt-Exception" rule added by
    New-ExchangePiiEncryptModeAuditCompanion.ps1.

.DESCRIPTION
    Deletes only this companion's own rule via Remove-DlpComplianceRule. Never touches the parent
    scenario's policy or its own three rules (PII-Exchange-Override-External,
    PII-Exchange-Protect-External, PII-Exchange-Audit-Internal).

    Idempotent: if the rule does not exist, reports that and exits cleanly rather than erroring.

.PARAMETER WhatIf
    Standard PowerShell ShouldProcess dry-run - reports the removal that would happen without
    calling Remove-DlpComplianceRule.

.EXAMPLE
    Connect-IPPSSession -AppId $AppId -Certificate $Cert -Organization $TenantDomain
    ./Remove-ExchangePiiEncryptModeAuditCompanion.ps1 -WhatIf

.EXAMPLE
    ./Remove-ExchangePiiEncryptModeAuditCompanion.ps1
    # Permanently removes the rule. There is no "disable" state for a single rule (unlike a
    # policy's Mode) - see rollback.md.

.NOTES
    Sources: https://learn.microsoft.com/powershell/module/exchangepowershell/remove-dlpcompliancerule
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param()

$ErrorActionPreference = 'Stop'

$ruleName = 'PII-Exchange-Audit-Encrypt-Exception'

if (-not (Get-Command Get-DlpComplianceRule -ErrorAction SilentlyContinue)) {
    throw 'No Security & Compliance PowerShell session found. Run Connect-IPPSSession first (see docs/automation-surface.md).'
}

$rule = Get-DlpComplianceRule -Identity $ruleName -ErrorAction SilentlyContinue

if (-not $rule) {
    Write-Host "Rule '$ruleName' does not exist. Nothing to roll back." -ForegroundColor Yellow
    return
}

if ($PSCmdlet.ShouldProcess($ruleName, 'Remove-DlpComplianceRule (permanent - this rule has no disabled state)')) {
    Remove-DlpComplianceRule -Identity $ruleName -Confirm:$false -WhatIf:$WhatIfPreference
}
Write-Host "Removed rule '$ruleName'. The parent policy and its other rules are unaffected." -ForegroundColor Green
