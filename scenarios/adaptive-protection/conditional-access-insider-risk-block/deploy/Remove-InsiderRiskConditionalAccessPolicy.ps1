#Requires -Version 7.0
<#
.SYNOPSIS
    Rolls back the Conditional Access policy created by New-InsiderRiskConditionalAccessPolicy.ps1,
    in stages: disable (default, reversible in seconds), step back to Report-only, or permanently
    delete (-Purge).

.DESCRIPTION
    Mirrors the staged rollback pattern scenarios/adaptive-protection/dynamic-risk-dlp-enforcement/
    deploy/Remove-AdaptiveProtectionDlpPolicy.ps1 already uses for its DLP policy - a live block
    control affects real users the moment it changes state, so this script defaults to the
    least-destructive action (disable) rather than deleting outright. See rollback.md for the
    full staged procedure and what rollback does NOT undo (Adaptive Protection itself, insider
    risk level definitions, a user's current risk level - none of those are touched by this
    script, exactly as documented for the DLP sibling's own rollback).

.PARAMETER DisplayName
    Must match the -DisplayName used at deploy time. Defaults to
    'Adaptive Protection - Block Elevated Insider Risk (Custom)'.

.PARAMETER ReportOnly
    Step back to Report-only (state = enabledForReportingButNotEnforced) instead of fully
    disabling. Keeps evaluation/sign-in-log visibility while removing the block.

.PARAMETER Purge
    Permanently delete the policy object (Remove-MgIdentityConditionalAccessPolicy). Not
    reversible - re-establishing the control means re-running New-InsiderRiskConditionalAccessPolicy.ps1
    from scratch.

.PARAMETER GraphBaseUri
    Present for symmetry with the deploy script; not used directly (all calls go through the
    Microsoft.Graph.Identity.SignIns cmdlets, which target whatever profile Connect-MgGraph
    established).

.PARAMETER WhatIf
    Standard PowerShell ShouldProcess dry-run.

.EXAMPLE
    Connect-MgGraph -ClientId $AppId -TenantId $TenantId -CertificateThumbprint $Thumbprint
    ./Remove-InsiderRiskConditionalAccessPolicy.ps1 -WhatIf

.EXAMPLE
    # Stage 1 - disable (reversible)
    ./Remove-InsiderRiskConditionalAccessPolicy.ps1

.EXAMPLE
    # Stage 2 - step back to Report-only instead of a full disable
    ./Remove-InsiderRiskConditionalAccessPolicy.ps1 -ReportOnly

.EXAMPLE
    # Stage 3 - permanent removal
    ./Remove-InsiderRiskConditionalAccessPolicy.ps1 -Purge

.NOTES
    Sources (Microsoft Learn, verify before production use):
    - Update conditionalAccessPolicy (state property PATCH):
      https://learn.microsoft.com/graph/api/conditionalaccesspolicy-update
    - Delete conditionalAccessPolicy:
      https://learn.microsoft.com/graph/api/conditionalaccesspolicy-delete
    - Remove-MgIdentityConditionalAccessPolicy (Microsoft.Graph.Identity.SignIns):
      https://learn.microsoft.com/powershell/module/microsoft.graph.identity.signins/remove-mgidentityconditionalaccesspolicy
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$DisplayName = 'Adaptive Protection - Block Elevated Insider Risk (Custom)',

    [Parameter()]
    [switch]$ReportOnly,

    [Parameter()]
    [switch]$Purge,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$GraphBaseUri = 'https://graph.microsoft.com/v1.0'
)

$ErrorActionPreference = 'Stop'

if ($ReportOnly -and $Purge) {
    throw '-ReportOnly and -Purge are mutually exclusive - pick one rollback stage per run.'
}

if (-not (Get-Command Get-MgIdentityConditionalAccessPolicy -ErrorAction SilentlyContinue)) {
    throw 'Microsoft Graph PowerShell SDK not found. Install Microsoft.Graph.Authentication and Microsoft.Graph.Identity.SignIns, then Connect-MgGraph.'
}
if (-not (Get-MgContext -ErrorAction SilentlyContinue)) {
    throw 'Not connected to Microsoft Graph. Run Connect-MgGraph (app-only certificate, Policy.ReadWrite.ConditionalAccess + Policy.Read.All) first.'
}

$existing = @(Get-MgIdentityConditionalAccessPolicy -All -ErrorAction Stop) | Where-Object { $_.DisplayName -eq $DisplayName } | Select-Object -First 1

if (-not $existing) {
    Write-Host "'$DisplayName' not found - nothing to roll back." -ForegroundColor Yellow
    return
}

if ($Purge) {
    if ($PSCmdlet.ShouldProcess($DisplayName, "PERMANENTLY DELETE Conditional Access policy $($existing.Id)")) {
        Remove-MgIdentityConditionalAccessPolicy -ConditionalAccessPolicyId $existing.Id
        Write-Host "  [purged] '$DisplayName' (id $($existing.Id)) permanently deleted. Re-run deploy/New-InsiderRiskConditionalAccessPolicy.ps1 to re-establish this control." -ForegroundColor Green
    }
    return
}

$targetState = if ($ReportOnly) { 'enabledForReportingButNotEnforced' } else { 'disabled' }
$body = @{ state = $targetState }

if ($existing.State -eq $targetState) {
    Write-Host "  [no-op] '$DisplayName' is already in state '$targetState'." -ForegroundColor Yellow
    return
}

if ($PSCmdlet.ShouldProcess($DisplayName, "PATCH state -> $targetState")) {
    Update-MgIdentityConditionalAccessPolicy -ConditionalAccessPolicyId $existing.Id -BodyParameter $body | Out-Null
    Write-Host "  [rolled back] '$DisplayName' (id $($existing.Id)) state changed: $($existing.State) -> $targetState." -ForegroundColor Green
}

Write-Host "`nDone. This does not turn off Adaptive Protection, reset any user's current insider risk level, or delete the feeder Insider Risk Management policy - see rollback.md." -ForegroundColor Cyan
