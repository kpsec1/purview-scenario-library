#Requires -Modules @{ ModuleName = 'ExchangeOnlineManagement'; ModuleVersion = '3.2.0' }
<#
.SYNOPSIS
    Staged rollback for scenarios/adaptive-protection/exchange-legacy-auth-block/ - unassigns the
    tenant default and/or re-enables Authenticated SMTP tenant-wide, then (only with -Purge)
    removes the policy objects entirely.

.DESCRIPTION
    Mirrors the staged, reversible-before-destructive pattern used by every other
    Conditional-Access/policy-based scenario's own rollback script in this library (see
    scenarios/adaptive-protection/block-legacy-authentication/deploy/
    Remove-BlockLegacyAuthenticationPolicy.ps1). Three independent stages, run any subset:

      -UnsetOrgDefault           : Set-OrganizationConfig -DefaultAuthenticationPolicy $null
                                   (reversible in seconds - re-run
                                   New-ExchangeLegacyAuthBlock.ps1 -SetAsOrgDefault to restore)
      -ReenableSmtpAuthTenantWide: Set-TransportConfig -SmtpClientAuthenticationDisabled $false
                                   tenant-wide (reversible - re-run
                                   New-ExchangeLegacyAuthBlock.ps1 -DisableSmtpAuthTenantWide)
      -Purge                     : Remove-AuthenticationPolicy for both the baseline and exception
                                   policy objects (NOT reversible - re-establishing the control
                                   means re-running New-ExchangeLegacyAuthBlock.ps1 from scratch).
                                   Refuses (without -Force) if either policy is still the tenant
                                   default or still assigned to any user, since
                                   Remove-AuthenticationPolicy's own behavior for a still-assigned
                                   policy is not confirmed by this build (README.md Section 11) -
                                   this script does not rely on Exchange to reject it safely.

    Author-only reference code. Run Connect-ExchangeOnline yourself first.

.PARAMETER PolicyName
    Must match the -PolicyName used at deploy time. Defaults to
    'Block Legacy Authentication (Exchange)'.

.PARAMETER ExceptionPolicyName
    Must match the -ExceptionPolicyName used at deploy time. Defaults to
    'Allow-Smtp-Auth-Exception'.

.PARAMETER UnsetOrgDefault
    Stage 1. Clears the tenant DefaultAuthenticationPolicy if it is currently -PolicyName. Leaves
    the policy object itself intact.

.PARAMETER ReenableSmtpAuthTenantWide
    Stage 2, independent of Stage 1. Sets Set-TransportConfig -SmtpClientAuthenticationDisabled
    $false tenant-wide. Does not touch any per-mailbox CASMailbox override.

.PARAMETER Purge
    Stage 3 (not reversible). Removes both policy objects entirely via Remove-AuthenticationPolicy.
    Refuses if either policy is still the tenant default or still assigned to a user, unless
    -Force is also passed.

.PARAMETER Force
    Required in addition to -Purge to remove a policy that is still assigned (tenant default or
    per-user) - forces the assignment to be cleared first rather than silently orphaning it.

.PARAMETER WhatIf
    Standard PowerShell ShouldProcess dry-run.

.EXAMPLE
    Connect-ExchangeOnline -AppId $AppId -CertificateThumbprint $Thumbprint -Organization $TenantDomain
    ./Remove-ExchangeLegacyAuthBlock.ps1 -UnsetOrgDefault -WhatIf

.EXAMPLE
    ./Remove-ExchangeLegacyAuthBlock.ps1 -ReenableSmtpAuthTenantWide

.EXAMPLE
    # Permanent removal, only after confirming with validate/Test-ExchangeLegacyAuthBlock.ps1 that
    # this control is being deliberately retired.
    ./Remove-ExchangeLegacyAuthBlock.ps1 -UnsetOrgDefault -ReenableSmtpAuthTenantWide -Purge -Force

.NOTES
    Sources: same as deploy/New-ExchangeLegacyAuthBlock.ps1's .NOTES block.
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$PolicyName = 'Block Legacy Authentication (Exchange)',

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$ExceptionPolicyName = 'Allow-Smtp-Auth-Exception',

    [Parameter()]
    [switch]$UnsetOrgDefault,

    [Parameter()]
    [switch]$ReenableSmtpAuthTenantWide,

    [Parameter()]
    [switch]$Purge,

    [Parameter()]
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

if (-not (Get-Command Get-AuthenticationPolicy -ErrorAction SilentlyContinue)) {
    throw 'No Exchange Online PowerShell session found. Run Connect-ExchangeOnline first.'
}

if ($UnsetOrgDefault) {
    Write-Host "Stage 1: clearing DefaultAuthenticationPolicy if it is '$PolicyName'..." -ForegroundColor Cyan
    $orgConfig = Get-OrganizationConfig
    if ($orgConfig.DefaultAuthenticationPolicy -ne $PolicyName) {
        Write-Host "  [no-op] Tenant DefaultAuthenticationPolicy is '$($orgConfig.DefaultAuthenticationPolicy)', not '$PolicyName' - nothing to clear." -ForegroundColor Yellow
    }
    elseif ($PSCmdlet.ShouldProcess('Organization', 'Set-OrganizationConfig -DefaultAuthenticationPolicy $null')) {
        Set-OrganizationConfig -DefaultAuthenticationPolicy $null
        Write-Host '  [cleared] Tenant no longer has a DefaultAuthenticationPolicy.' -ForegroundColor Green
    }
}

if ($ReenableSmtpAuthTenantWide) {
    Write-Host "`nStage 2: re-enabling Authenticated SMTP tenant-wide..." -ForegroundColor Cyan
    if ($PSCmdlet.ShouldProcess('Organization', 'Set-TransportConfig -SmtpClientAuthenticationDisabled $false')) {
        Set-TransportConfig -SmtpClientAuthenticationDisabled $false
        Write-Host '  [set] SmtpClientAuthenticationDisabled = $false tenant-wide. Per-mailbox CASMailbox overrides are unchanged by this stage.' -ForegroundColor Green
    }
}

if ($Purge) {
    Write-Host "`nStage 3 (-Purge, not reversible): removing policy objects..." -ForegroundColor Cyan
    foreach ($name in @($PolicyName, $ExceptionPolicyName)) {
        $policy = Get-AuthenticationPolicy -Identity $name -ErrorAction SilentlyContinue
        if (-not $policy) {
            Write-Host "  [no-op] Policy '$name' does not exist." -ForegroundColor Yellow
            continue
        }

        $orgConfig = Get-OrganizationConfig
        $isOrgDefault = $orgConfig.DefaultAuthenticationPolicy -eq $name
        # Client-side filter, not -Filter "AuthenticationPolicy -eq '...'": whether
        # AuthenticationPolicy is a supported OPATH filter property for Get-User is not confirmed
        # by this build (README.md Section 11) - a plain property comparison after an unfiltered
        # fetch is slower on a large tenant but cannot silently under-match the way an unsupported
        # filter property could (e.g. failing open with zero results instead of an error).
        $assignedUsers = @(Get-User -ResultSize Unlimited -ErrorAction SilentlyContinue | Where-Object { $_.AuthenticationPolicy -eq $name })

        if (($isOrgDefault -or $assignedUsers.Count -gt 0) -and -not $Force) {
            Write-Warning "  Policy '$name' is still $(if ($isOrgDefault) { 'the tenant default' })$(if ($isOrgDefault -and $assignedUsers.Count -gt 0) { ' and ' })$(if ($assignedUsers.Count -gt 0) { "assigned to $($assignedUsers.Count) user(s)" }) - Remove-AuthenticationPolicy's behavior against a still-assigned policy is not confirmed by this build (README.md Section 11), so this script refuses rather than risk an undocumented failure mode. Re-run with -UnsetOrgDefault (if applicable) and -Force, or manually clear per-user assignments first."
            continue
        }

        if ($isOrgDefault -and $Force -and -not $UnsetOrgDefault) {
            if ($PSCmdlet.ShouldProcess('Organization', "Clear DefaultAuthenticationPolicy before removing '$name' (-Force)")) {
                Set-OrganizationConfig -DefaultAuthenticationPolicy $null
            }
        }
        if ($assignedUsers.Count -gt 0 -and $Force) {
            foreach ($u in $assignedUsers) {
                if ($PSCmdlet.ShouldProcess($u.Identity, "Clear AuthenticationPolicy assignment before removing '$name' (-Force)")) {
                    Set-User -Identity $u.Identity -AuthenticationPolicy $null
                }
            }
        }

        if ($PSCmdlet.ShouldProcess($name, 'Remove-AuthenticationPolicy')) {
            Remove-AuthenticationPolicy -Identity $name -Confirm:$false
            Write-Host "  [removed] Policy '$name' deleted. Not reversible - re-run deploy/New-ExchangeLegacyAuthBlock.ps1 to re-establish." -ForegroundColor Green
        }
    }
}

if (-not $UnsetOrgDefault -and -not $ReenableSmtpAuthTenantWide -and -not $Purge) {
    Write-Warning 'No stage switch passed (-UnsetOrgDefault / -ReenableSmtpAuthTenantWide / -Purge) - nothing to do. See rollback.md for the recommended sequence.'
}

Write-Host "`nDone. Run validate/Test-ExchangeLegacyAuthBlock.ps1 to confirm the resulting state." -ForegroundColor Cyan
