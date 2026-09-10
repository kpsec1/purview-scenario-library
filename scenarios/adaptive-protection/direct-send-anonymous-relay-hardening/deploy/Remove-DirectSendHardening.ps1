#Requires -Modules @{ ModuleName = 'ExchangeOnlineManagement'; ModuleVersion = '3.2.0' }
<#
.SYNOPSIS
    Staged rollback for Direct Send / anonymous relay hardening: disable tenant-wide rejection,
    remove the audit-mode detection rule, and/or remove a certificate-based relay connector.

.DESCRIPTION
    Mirrors deploy/New-DirectSendHardening.ps1's independent stages. Each switch below undoes
    exactly one stage; combine as needed. See rollback.md for the recommended sequence and what
    rollback does NOT undo.

.PARAMETER UnsetRejectDirectSend
    Sets Set-OrganizationConfig -RejectDirectSend $false tenant-wide - immediate, reversible.

.PARAMETER RuleName
    Name of the audit-mode detection TransportRule to remove. Only used with -RemoveAuditRule.
    Defaults to 'Direct Send Detection (Audit)'.

.PARAMETER RemoveAuditRule
    Removes the audit-mode TransportRule via Remove-TransportRule. Stops evidence-gathering; does
    not affect enforcement (RejectDirectSend is independent).

.PARAMETER RelayConnectorName
    Name of a certificate-based relay connector to remove. Only used with -RemoveRelayConnector.

.PARAMETER RemoveRelayConnector
    Removes the named certificate-based InboundConnector via Remove-InboundConnector. Any
    device/app still relying on it for mail flow will stop being able to relay once this runs -
    confirm no legitimate sender still depends on it first.

.PARAMETER Force
    Required in addition to -RemoveAuditRule/-RemoveRelayConnector to actually remove an object -
    a deliberate double-opt-in for a non-reversible action, the same pattern this library's other
    -Purge-style rollback scripts use.

.PARAMETER WhatIf
    Standard PowerShell ShouldProcess dry-run.

.EXAMPLE
    Connect-ExchangeOnline -AppId $AppId -CertificateThumbprint $Thumbprint -Organization $TenantDomain
    ./Remove-DirectSendHardening.ps1 -UnsetRejectDirectSend

.EXAMPLE
    ./Remove-DirectSendHardening.ps1 -RemoveAuditRule -RemoveRelayConnector `
        -RelayConnectorName 'Contoso Scan-to-Email (Certificate)' -Force

.NOTES
    Sources: same as deploy/New-DirectSendHardening.ps1's .NOTES block.
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter()]
    [switch]$UnsetRejectDirectSend,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$RuleName = 'Direct Send Detection (Audit)',

    [Parameter()]
    [switch]$RemoveAuditRule,

    [Parameter()]
    [string]$RelayConnectorName,

    [Parameter()]
    [switch]$RemoveRelayConnector,

    [Parameter()]
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

if (-not (Get-Command Get-TransportRule -ErrorAction SilentlyContinue)) {
    throw 'No Exchange Online PowerShell session found. Run Connect-ExchangeOnline first.'
}

if ($UnsetRejectDirectSend) {
    Write-Host 'Re-enabling unauthenticated Direct Send tenant-wide (RejectDirectSend = $false)...' -ForegroundColor Cyan
    $orgConfig = Get-OrganizationConfig
    if ($orgConfig.RejectDirectSend -eq $false) {
        Write-Host '  [coverage] RejectDirectSend is already $false - not modified.' -ForegroundColor Yellow
    }
    elseif ($PSCmdlet.ShouldProcess('Organization', 'Set-OrganizationConfig -RejectDirectSend $false')) {
        Set-OrganizationConfig -RejectDirectSend $false
        Write-Host '  [set] RejectDirectSend = $false tenant-wide.' -ForegroundColor Green
    }
}

if ($RemoveAuditRule) {
    Write-Host "`nRemoving audit rule '$RuleName'..." -ForegroundColor Cyan
    $rule = Get-TransportRule -Identity $RuleName -ErrorAction SilentlyContinue
    if (-not $rule) {
        Write-Host "  [coverage] Rule '$RuleName' does not exist - nothing to remove." -ForegroundColor Yellow
    }
    elseif (-not $Force) {
        Write-Warning "  Rule '$RuleName' exists but -Force was not passed - not removed. Pass -Force to confirm."
    }
    elseif ($PSCmdlet.ShouldProcess($RuleName, 'Remove-TransportRule')) {
        Remove-TransportRule -Identity $RuleName -Confirm:$false
        Write-Host "  [removed] '$RuleName'." -ForegroundColor Green
    }
}

if ($RemoveRelayConnector) {
    if (-not $RelayConnectorName) {
        throw '-RemoveRelayConnector requires -RelayConnectorName.'
    }
    Write-Host "`nRemoving relay connector '$RelayConnectorName'..." -ForegroundColor Cyan
    $connector = Get-InboundConnector -Identity $RelayConnectorName -ErrorAction SilentlyContinue
    if (-not $connector) {
        Write-Host "  [coverage] Connector '$RelayConnectorName' does not exist - nothing to remove." -ForegroundColor Yellow
    }
    elseif (-not $Force) {
        Write-Warning "  Connector '$RelayConnectorName' exists but -Force was not passed - not removed. Pass -Force to confirm. Any device/app still sending through it will lose mail flow once removed."
    }
    elseif ($PSCmdlet.ShouldProcess($RelayConnectorName, 'Remove-InboundConnector')) {
        Remove-InboundConnector -Identity $RelayConnectorName -Confirm:$false
        Write-Host "  [removed] '$RelayConnectorName'." -ForegroundColor Green
    }
}

if (-not ($UnsetRejectDirectSend -or $RemoveAuditRule -or $RemoveRelayConnector)) {
    Write-Warning 'No rollback switch passed - nothing to do. Pass -UnsetRejectDirectSend, -RemoveAuditRule, and/or -RemoveRelayConnector (with -Force for removals).'
}

Write-Host "`nDone. Run validate/Test-DirectSendHardening.ps1 to confirm the resulting state." -ForegroundColor Cyan
