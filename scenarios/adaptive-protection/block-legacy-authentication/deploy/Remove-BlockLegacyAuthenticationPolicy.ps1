#Requires -Version 7.0
<#
.SYNOPSIS
    Rolls back the custom Conditional Access policy created by
    New-BlockLegacyAuthenticationPolicy.ps1, in stages: disable (default, reversible in seconds),
    step back to Report-only, or permanently delete (-Purge).

.DESCRIPTION
    Mirrors the staged rollback pattern this library's other Conditional-Access-based scenarios use
    (scenarios/adaptive-protection/conditional-access-insider-risk-block/deploy/
    Remove-InsiderRiskConditionalAccessPolicy.ps1) - a live block control affects real users the
    moment it changes state, so this script defaults to the least-destructive action (disable)
    rather than deleting outright.

    THIS SCRIPT ONLY TOUCHES THE CUSTOM POLICY THIS SCENARIO CREATED (matched by -DisplayName). It
    never modifies, disables, or deletes a Microsoft-managed "Block legacy authentication" policy -
    Microsoft's own documentation states organizations can't rename or delete Microsoft-managed
    policies at all, and this scenario does not attempt to (design.md Section 7). If your tenant
    relies on the Microsoft-managed policy instead of this scenario's custom one, manage it directly
    in the Microsoft Entra admin center - see rollback.md.

.PARAMETER DisplayName
    Must match the -DisplayName used at deploy time. Defaults to
    'Block Legacy Authentication (Custom)'.

.PARAMETER ReportOnly
    Step back to Report-only (state = enabledForReportingButNotEnforced) instead of fully
    disabling. Keeps evaluation/sign-in-log visibility while removing the block.

.PARAMETER Purge
    Permanently delete the policy object (Remove-MgIdentityConditionalAccessPolicy). Not
    reversible - re-establishing the control means re-running
    New-BlockLegacyAuthenticationPolicy.ps1 from scratch.

.PARAMETER GraphBaseUri
    Present for symmetry with the deploy script; not used directly (all calls go through the
    Microsoft.Graph.Identity.SignIns cmdlets, which target whatever profile Connect-MgGraph
    established).

.PARAMETER WhatIf
    Standard PowerShell ShouldProcess dry-run.

.EXAMPLE
    Connect-MgGraph -ClientId $AppId -TenantId $TenantId -CertificateThumbprint $Thumbprint
    ./Remove-BlockLegacyAuthenticationPolicy.ps1 -WhatIf

.EXAMPLE
    # Stage 1 - disable (reversible)
    ./Remove-BlockLegacyAuthenticationPolicy.ps1

.EXAMPLE
    # Stage 2 - step back to Report-only instead of a full disable
    ./Remove-BlockLegacyAuthenticationPolicy.ps1 -ReportOnly

.EXAMPLE
    # Stage 3 - permanent removal
    ./Remove-BlockLegacyAuthenticationPolicy.ps1 -Purge

.NOTES
    Sources (Microsoft Learn, verify before production use):
    - Update conditionalAccessPolicy (state property PATCH):
      https://learn.microsoft.com/graph/api/conditionalaccesspolicy-update
    - Delete conditionalAccessPolicy:
      https://learn.microsoft.com/graph/api/conditionalaccesspolicy-delete
    - Remove-MgIdentityConditionalAccessPolicy (Microsoft.Graph.Identity.SignIns):
      https://learn.microsoft.com/powershell/module/microsoft.graph.identity.signins/remove-mgidentityconditionalaccesspolicy
    - Microsoft-managed Conditional Access policies (organizations can't rename or delete a
      Microsoft-managed policy):
      https://learn.microsoft.com/entra/identity/conditional-access/managed-policies
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$DisplayName = 'Block Legacy Authentication (Custom)',

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
        Write-Host "  [purged] '$DisplayName' (id $($existing.Id)) permanently deleted. Re-run deploy/New-BlockLegacyAuthenticationPolicy.ps1 to re-establish this control." -ForegroundColor Green
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

Write-Host "`nDone. This does not affect any Microsoft-managed 'Block legacy authentication' policy the tenant may also have - see rollback.md." -ForegroundColor Cyan
