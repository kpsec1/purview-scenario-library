#Requires -Version 7.0
<#
.SYNOPSIS
    Rolls back the Conditional Access policies created by New-InsiderRiskStepUpPolicies.ps1, in
    stages: disable (default, reversible in seconds), step back to Report-only, or permanently
    delete (-Purge). Operates on one or both policies via -Policy.

.DESCRIPTION
    Mirrors the staged rollback pattern conditional-access-insider-risk-block/deploy/
    Remove-InsiderRiskConditionalAccessPolicy.ps1 already uses. Neither policy this scenario
    deploys can lock a user out of Microsoft 365 entirely (unlike the Elevated sibling's block),
    but the same least-destructive-default discipline applies. See rollback.md for the full staged
    procedure and what rollback does NOT undo.

.PARAMETER Policy
    Which policy to roll back: 'Moderate', 'Minor', or 'Both' (default).

.PARAMETER ModerateDisplayName
    Must match the -ModerateDisplayName used at deploy time. Defaults to
    'Adaptive Protection - Require Terms of Use for Moderate Insider Risk (Custom)'.

.PARAMETER MinorDisplayName
    Must match the -MinorDisplayName used at deploy time. Defaults to
    'Adaptive Protection - Insights for Minor Insider Risk (Custom)'.

.PARAMETER ReportOnly
    Step back to Report-only (state = enabledForReportingButNotEnforced) instead of fully
    disabling. For the Minor policy this is a no-op-equivalent (it is already restricted to
    ReportOnly/Disabled and defaults to ReportOnly).

.PARAMETER Purge
    Permanently delete the selected policy object(s) (Remove-MgIdentityConditionalAccessPolicy).
    Not reversible - re-establishing the control means re-running
    New-InsiderRiskStepUpPolicies.ps1 from scratch.

.PARAMETER GraphBaseUri
    Present for symmetry with the deploy script; not used directly.

.PARAMETER WhatIf
    Standard PowerShell ShouldProcess dry-run.

.EXAMPLE
    Connect-MgGraph -ClientId $AppId -TenantId $TenantId -CertificateThumbprint $Thumbprint
    ./Remove-InsiderRiskStepUpPolicies.ps1 -WhatIf

.EXAMPLE
    # Stage 1 - disable both policies (reversible)
    ./Remove-InsiderRiskStepUpPolicies.ps1

.EXAMPLE
    # Roll back only the Moderate (Terms of Use) policy, stepping back to Report-only
    ./Remove-InsiderRiskStepUpPolicies.ps1 -Policy Moderate -ReportOnly

.EXAMPLE
    # Stage 3 - permanent removal of both
    ./Remove-InsiderRiskStepUpPolicies.ps1 -Purge

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
    [ValidateSet('Moderate', 'Minor', 'Both')]
    [string]$Policy = 'Both',

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$ModerateDisplayName = 'Adaptive Protection - Require Terms of Use for Moderate Insider Risk (Custom)',

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$MinorDisplayName = 'Adaptive Protection - Insights for Minor Insider Risk (Custom)',

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

function Remove-OnePolicy {
    param([Parameter(Mandatory)][string]$DisplayName)

    $existing = @(Get-MgIdentityConditionalAccessPolicy -All -ErrorAction Stop) | Where-Object { $_.DisplayName -eq $DisplayName } | Select-Object -First 1

    if (-not $existing) {
        Write-Host "'$DisplayName' not found - nothing to roll back." -ForegroundColor Yellow
        return
    }

    if ($Purge) {
        if ($PSCmdlet.ShouldProcess($DisplayName, "PERMANENTLY DELETE Conditional Access policy $($existing.Id)")) {
            Remove-MgIdentityConditionalAccessPolicy -ConditionalAccessPolicyId $existing.Id
            Write-Host "  [purged] '$DisplayName' (id $($existing.Id)) permanently deleted." -ForegroundColor Green
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
}

if ($Policy -in @('Moderate', 'Both')) { Remove-OnePolicy -DisplayName $ModerateDisplayName }
if ($Policy -in @('Minor', 'Both')) { Remove-OnePolicy -DisplayName $MinorDisplayName }

Write-Host "`nDone. This does not delete the Terms of Use agreement object, turn off Adaptive Protection, reset any user's current insider risk level, or affect the Elevated sibling's block policy - see rollback.md." -ForegroundColor Cyan
