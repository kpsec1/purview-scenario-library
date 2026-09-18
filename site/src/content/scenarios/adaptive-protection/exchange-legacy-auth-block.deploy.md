---
part: "deploy"
parent: "adaptive-protection/exchange-legacy-auth-block"
---
The scripts and configuration below deploy this scenario. Review them, then run in order — each is designed to be idempotent and has a matching rollback.


#### `New-ExchangeLegacyAuthBlock.ps1`

```powershell
#Requires -Modules @{ ModuleName = 'ExchangeOnlineManagement'; ModuleVersion = '3.2.0' }
<#
.SYNOPSIS
    Creates (or reconciles) an Exchange Online Authentication Policy that blocks legacy/Basic
    authentication, then - only if the corresponding opt-in switch is passed - assigns it as the
    tenant-wide default and/or disables Authenticated SMTP (SMTP AUTH) tenant-wide, with a named,
    narrow per-mailbox exception path.

.DESCRIPTION
    Deferred from scenarios/adaptive-protection/block-legacy-authentication (design.md Section 7,
    reviews.md Red Team) because it is a separate, workload-specific control surface (Exchange
    Online PowerShell, not Entra/Graph) that acts before first-factor authentication completes -
    closes that follow-up as its own standalone scenario.

    GROUNDING FINDING (design.md Section 3): Microsoft has already PERMANENTLY disabled Basic
    authentication tenant-wide, with no re-enable option, for Exchange ActiveSync, POP, IMAP,
    Remote PowerShell, Exchange Web Services, Offline Address Book, Autodiscover, and Outlook for
    Windows/Mac. Authenticated SMTP (SMTP AUTH) is the one protocol Microsoft has deliberately left
    admin-controlled during an extended deprecation runway (default-disable for existing tenants
    scheduled for end of December 2026, final removal date to be announced 2027 H2 - see .NOTES).
    This script's practical value-add is therefore centered on SMTP, not on protocols Microsoft has
    already closed for free.

    Three independent, opt-in stages (design.md Section 4 - Authentication Policies have no
    Report-only mode, so staging is done by parameter, not by platform state):
      1. ALWAYS RUNS: create/reconcile the baseline AuthenticationPolicy (-PolicyName). No
         -AllowBasicAuth* switches are ever passed, matching Microsoft's own documented default
         (every protocol blocked). Creating this object alone has ZERO effect on any user until
         assigned - see stage 2.
      2. -SetAsOrgDefault (opt-in, live impact): Set-OrganizationConfig -DefaultAuthenticationPolicy
         to this script's policy. Applies to every user WITHOUT an explicit per-user
         AuthenticationPolicy already assigned - a pre-existing explicit assignment is NOT
         overridden (README.md Section 11 - a disclosed, not silently ignored, gap).
      3. -DisableSmtpAuthTenantWide (opt-in, live impact, independent of stage 2):
         Set-TransportConfig -SmtpClientAuthenticationDisabled $true tenant-wide. For each
         -ExceptionMailboxes entry: assigns a separate 'Allow-Smtp-Auth-Exception' policy (only
         -AllowBasicAuthSmtp enabled) via Set-User, AND sets Set-CASMailbox
         -SmtpClientAuthenticationDisabled $false for that mailbox - both of the two independent
         SMTP AUTH gates opened together, since Microsoft does not document their precedence if
         only one is opened (design.md Section 5).

    Idempotent throughout: every Get- read-back is compared against this run's desired state before
    any Set-/New- call; an already-matching object is reported and left untouched. -Force
    reconciles a drifted object to this run's parameters.

    Author-only reference code. This script never establishes its own connection to a tenant - run
    Connect-ExchangeOnline yourself first (see docs/automation-surface.md Section 3), then call
    this script.

.PARAMETER PolicyName
    Name of the baseline AuthenticationPolicy. Defaults to
    'Block Legacy Authentication (Exchange)' - deliberately distinct from the Conditional Access
    sibling scenario's 'Block Legacy Authentication (Custom)' policy name, since the two live in
    entirely different systems (Exchange Online vs. Microsoft Entra) but share a naming pattern for
    discoverability.

.PARAMETER SetAsOrgDefault
    Live-impact stage. Sets -PolicyName as the tenant's DefaultAuthenticationPolicy. Off by default
    - creating the policy object (always run) has no effect until this switch (or an explicit
    per-user Set-User -AuthenticationPolicy assignment, not scripted by this tool) is used.

.PARAMETER DisableSmtpAuthTenantWide
    Live-impact stage, independent of -SetAsOrgDefault. Sets
    Set-TransportConfig -SmtpClientAuthenticationDisabled $true tenant-wide. Off by default - this
    is this scenario's single highest-risk operational change (README.md Section 8); run
    README.md Section 5 Step 2's inventory first.

.PARAMETER ExceptionMailboxes
    Mailbox identities (UPN/email/alias) that must keep Authenticated SMTP. For each: assigns the
    'Allow-Smtp-Auth-Exception' policy (created/reconciled automatically, -AllowBasicAuthSmtp only)
    via Set-User, and sets Set-CASMailbox -SmtpClientAuthenticationDisabled $false. Only meaningful
    together with -DisableSmtpAuthTenantWide; ignored (with a warning) otherwise. Both gates are
    opened together per design.md Section 5 - the exact precedence between them if only one were
    opened is not documented by Microsoft.

.PARAMETER ExceptionPolicyName
    Name of the shared SMTP-AUTH-only exception policy. Defaults to 'Allow-Smtp-Auth-Exception'.

.PARAMETER Force
    Reconcile an existing baseline or exception policy's AllowBasicAuth* shape to this script's
    definition if it has drifted, instead of leaving a drifted policy untouched.

.PARAMETER WhatIf
    Standard PowerShell ShouldProcess dry-run. Reports every create/update/assignment this run
    would make without calling any mutating cmdlet.

.EXAMPLE
    Connect-ExchangeOnline -AppId $AppId -CertificateThumbprint $Thumbprint -Organization $TenantDomain
    ./New-ExchangeLegacyAuthBlock.ps1 -WhatIf

    Dry run of Stage 1 only (policy creation - no live impact regardless of -WhatIf).

.EXAMPLE
    ./New-ExchangeLegacyAuthBlock.ps1

.EXAMPLE
    # Stage 2: assign tenant-wide, after confirming no conflicting per-user override exists
    # (validate/Test-ExchangeLegacyAuthBlock.ps1 -CheckUserOverrides).
    ./New-ExchangeLegacyAuthBlock.ps1 -SetAsOrgDefault

.EXAMPLE
    # Stage 3: disable SMTP AUTH tenant-wide with two named exceptions.
    ./New-ExchangeLegacyAuthBlock.ps1 -DisableSmtpAuthTenantWide `
        -ExceptionMailboxes 'scan-to-email@contoso.com','relay-app@contoso.com'

.NOTES
    Sources (Microsoft Learn, verify before production use - learn.microsoft.com and
    techcommunity.microsoft.com were not directly fetchable from this build's network environment;
    cmdlet syntax was grounded via the equivalent pages mirrored in the public
    MicrosoftDocs/office-docs-powershell GitHub repository, and the SMTP AUTH deprecation timeline
    via WebSearch corroborated across multiple independent secondary sources - README.md Section
    11):
    - New-AuthenticationPolicy / Set-AuthenticationPolicy / Get-AuthenticationPolicy /
      Remove-AuthenticationPolicy (AllowBasicAuth* switches, default-blocked behavior):
      https://learn.microsoft.com/powershell/module/exchangepowershell/new-authenticationpolicy?view=exchange-ps
      https://learn.microsoft.com/powershell/module/exchangepowershell/set-authenticationpolicy?view=exchange-ps
      https://learn.microsoft.com/powershell/module/exchangepowershell/get-authenticationpolicy?view=exchange-ps
    - Set-User -AuthenticationPolicy (per-user assignment, overrides org default):
      https://learn.microsoft.com/powershell/module/exchangepowershell/set-user?view=exchange-ps
    - Set-OrganizationConfig -DefaultAuthenticationPolicy (tenant-wide default, does not override
      an explicit per-user assignment):
      https://learn.microsoft.com/powershell/module/exchangepowershell/set-organizationconfig?view=exchange-ps
    - Set-TransportConfig -SmtpClientAuthenticationDisabled (tenant-wide SMTP AUTH gate) /
      Set-CASMailbox -SmtpClientAuthenticationDisabled (per-mailbox override, $null = follow org):
      https://learn.microsoft.com/powershell/module/exchangepowershell/set-transportconfig?view=exchange-ps
      https://learn.microsoft.com/powershell/module/exchangepowershell/set-casmailbox?view=exchange-ps
    - Enable or disable SMTP AUTH in Exchange Online (org-then-mailbox-override pattern):
      https://learn.microsoft.com/exchange/clients-and-mobile-in-exchange-online/authenticated-client-smtp-submission
    - Disable Basic authentication in Exchange Online (already-permanently-disabled protocol list):
      https://learn.microsoft.com/exchange/clients-and-mobile-in-exchange-online/disable-basic-authentication-in-exchange-online
    - Updated Exchange Online SMTP AUTH Basic Authentication Deprecation Timeline (December 2026
      default-disable, 2027 H2 final-removal announcement):
      https://techcommunity.microsoft.com/blog/exchange/updated-exchange-online-smtp-auth-basic-authentication-deprecation-timeline/4489835
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$PolicyName = 'Block Legacy Authentication (Exchange)',

    [Parameter()]
    [switch]$SetAsOrgDefault,

    [Parameter()]
    [switch]$DisableSmtpAuthTenantWide,

    [Parameter()]
    [string[]]$ExceptionMailboxes = @(),

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$ExceptionPolicyName = 'Allow-Smtp-Auth-Exception',

    [Parameter()]
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

function Assert-ExoSession {
    # Get-AuthenticationPolicy is only exported after a successful Connect-ExchangeOnline; its
    # absence means the caller never connected.
    if (-not (Get-Command Get-AuthenticationPolicy -ErrorAction SilentlyContinue)) {
        throw 'No Exchange Online PowerShell session found. Run Connect-ExchangeOnline first (see docs/automation-surface.md). The connecting identity (or the automation app''s service principal) also needs the Organization Management Exchange Online role group - see README.md Section 3 and Section 11.'
    }
}

function Confirm-BaselinePolicy {
    param(
        [Parameter(Mandatory)][string]$Name,
        [switch]$Force
    )
    $existing = Get-AuthenticationPolicy -Identity $Name -ErrorAction SilentlyContinue
    if ($existing) {
        $allowProps = $existing.PSObject.Properties | Where-Object { $_.Name -like 'AllowBasicAuth*' }
        $anyAllowed = @($allowProps | Where-Object { $_.Value -eq $true })
        if ($anyAllowed.Count -eq 0) {
            Write-Host "  [coverage] Policy '$Name' already exists with every AllowBasicAuth* blocked - not modified." -ForegroundColor Yellow
            return $existing
        }
        Write-Host "  [drift] Policy '$Name' exists but allows Basic auth for: $($anyAllowed.Name -join ', ')." -ForegroundColor Yellow
        if (-not $Force) {
            Write-Host '    Not modified - pass -Force to reconcile back to fully-blocked.' -ForegroundColor Yellow
            return $existing
        }
        if ($PSCmdlet.ShouldProcess($Name, 'Set-AuthenticationPolicy (reconcile all AllowBasicAuth* to blocked)')) {
            $blockArgs = @{}
            foreach ($p in $anyAllowed) { $blockArgs[$p.Name] = $false }
            Set-AuthenticationPolicy -Identity $Name @blockArgs | Out-Null
            Write-Host "  [reconciled] '$Name' - all AllowBasicAuth* now blocked." -ForegroundColor Green
        }
        return Get-AuthenticationPolicy -Identity $Name
    }
    if ($PSCmdlet.ShouldProcess($Name, 'New-AuthenticationPolicy (no AllowBasicAuth* switches - every protocol blocked by default)')) {
        New-AuthenticationPolicy -Name $Name | Out-Null
        Write-Host "  [created] Baseline policy '$Name' created - every protocol blocked by default. No user is affected until assigned (Section 5 Step 4/5)." -ForegroundColor Green
        return Get-AuthenticationPolicy -Identity $Name
    }
    return $null
}

function Confirm-ExceptionPolicy {
    param(
        [Parameter(Mandatory)][string]$Name,
        [switch]$Force
    )
    $existing = Get-AuthenticationPolicy -Identity $Name -ErrorAction SilentlyContinue
    if ($existing) {
        if ($existing.AllowBasicAuthSmtp -eq $true) {
            Write-Host "  [coverage] Exception policy '$Name' already allows SMTP only - not modified." -ForegroundColor Yellow
            return $existing
        }
        Write-Host "  [drift] Exception policy '$Name' exists but AllowBasicAuthSmtp is not enabled." -ForegroundColor Yellow
        if (-not $Force) {
            Write-Host '    Not modified - pass -Force to reconcile.' -ForegroundColor Yellow
            return $existing
        }
        if ($PSCmdlet.ShouldProcess($Name, 'Set-AuthenticationPolicy -AllowBasicAuthSmtp')) {
            Set-AuthenticationPolicy -Identity $Name -AllowBasicAuthSmtp | Out-Null
            Write-Host "  [reconciled] '$Name' now allows SMTP only." -ForegroundColor Green
        }
        return Get-AuthenticationPolicy -Identity $Name
    }
    if ($PSCmdlet.ShouldProcess($Name, 'New-AuthenticationPolicy -AllowBasicAuthSmtp (every other protocol stays blocked by default)')) {
        New-AuthenticationPolicy -Name $Name -AllowBasicAuthSmtp | Out-Null
        Write-Host "  [created] Exception policy '$Name' created - SMTP allowed, every other protocol still blocked by default." -ForegroundColor Green
        return Get-AuthenticationPolicy -Identity $Name
    }
    return $null
}

Assert-ExoSession

Write-Host "Exchange legacy authentication block: reconciling baseline policy '$PolicyName'." -ForegroundColor Cyan
$baseline = Confirm-BaselinePolicy -Name $PolicyName -Force:$Force

if ($SetAsOrgDefault) {
    Write-Host "`nStage 2 (-SetAsOrgDefault): assigning '$PolicyName' as the tenant DefaultAuthenticationPolicy." -ForegroundColor Cyan
    $orgConfig = Get-OrganizationConfig
    if ($orgConfig.DefaultAuthenticationPolicy -eq $PolicyName) {
        Write-Host "  [coverage] Tenant DefaultAuthenticationPolicy is already '$PolicyName' - not modified." -ForegroundColor Yellow
    }
    else {
        if ($orgConfig.DefaultAuthenticationPolicy) {
            Write-Host "  [note] Replacing existing DefaultAuthenticationPolicy '$($orgConfig.DefaultAuthenticationPolicy)' with '$PolicyName'." -ForegroundColor DarkYellow
        }
        if ($PSCmdlet.ShouldProcess('Organization', "Set-OrganizationConfig -DefaultAuthenticationPolicy '$PolicyName'")) {
            Set-OrganizationConfig -DefaultAuthenticationPolicy $PolicyName
            Write-Host "  [set] Tenant DefaultAuthenticationPolicy = '$PolicyName'." -ForegroundColor Green
        }
    }
    Write-Host '  Reminder: this does NOT override any user with an existing explicit per-user AuthenticationPolicy assignment - run validate/Test-ExchangeLegacyAuthBlock.ps1 -CheckUserOverrides to find them (README.md Section 11).' -ForegroundColor Yellow
}
else {
    Write-Host "`nStage 2 skipped (-SetAsOrgDefault not passed) - baseline policy exists but is not the tenant default." -ForegroundColor DarkYellow
}

if ($DisableSmtpAuthTenantWide) {
    Write-Host "`nStage 3 (-DisableSmtpAuthTenantWide): disabling Authenticated SMTP tenant-wide." -ForegroundColor Cyan
    $transportConfig = Get-TransportConfig
    if ($transportConfig.SmtpClientAuthenticationDisabled -eq $true) {
        Write-Host '  [coverage] SmtpClientAuthenticationDisabled is already $true tenant-wide - not modified.' -ForegroundColor Yellow
    }
    else {
        if ($PSCmdlet.ShouldProcess('Organization', 'Set-TransportConfig -SmtpClientAuthenticationDisabled $true')) {
            Set-TransportConfig -SmtpClientAuthenticationDisabled $true
            Write-Host '  [set] SmtpClientAuthenticationDisabled = $true tenant-wide.' -ForegroundColor Green
        }
    }

    if ($ExceptionMailboxes.Count -gt 0) {
        Write-Host "  Reconciling $($ExceptionMailboxes.Count) SMTP AUTH exception mailbox(es) via '$ExceptionPolicyName' (both independent gates opened together - design.md Section 5)..." -ForegroundColor Cyan
        Confirm-ExceptionPolicy -Name $ExceptionPolicyName -Force:$Force | Out-Null

        foreach ($mailbox in $ExceptionMailboxes) {
            $user = Get-User -Identity $mailbox -ErrorAction SilentlyContinue
            if (-not $user) {
                Write-Warning "  Mailbox '$mailbox' not found via Get-User - skipped."
                continue
            }
            if ($user.AuthenticationPolicy -eq $ExceptionPolicyName) {
                Write-Host "  [coverage] '$mailbox' already assigned '$ExceptionPolicyName'." -ForegroundColor Yellow
            }
            elseif ($PSCmdlet.ShouldProcess($mailbox, "Set-User -AuthenticationPolicy '$ExceptionPolicyName'")) {
                Set-User -Identity $mailbox -AuthenticationPolicy $ExceptionPolicyName
                Write-Host "  [assigned] '$mailbox' -> '$ExceptionPolicyName'." -ForegroundColor Green
            }

            $cas = Get-CASMailbox -Identity $mailbox -ErrorAction SilentlyContinue
            if ($cas -and $cas.SmtpClientAuthenticationDisabled -eq $false) {
                Write-Host "  [coverage] '$mailbox' CASMailbox override already allows SMTP AUTH." -ForegroundColor Yellow
            }
            elseif ($PSCmdlet.ShouldProcess($mailbox, 'Set-CASMailbox -SmtpClientAuthenticationDisabled $false')) {
                Set-CASMailbox -Identity $mailbox -SmtpClientAuthenticationDisabled $false
                Write-Host "  [assigned] '$mailbox' CASMailbox override -> SMTP AUTH allowed." -ForegroundColor Green
            }
        }
    }
    else {
        Write-Warning 'No -ExceptionMailboxes supplied while disabling SMTP AUTH tenant-wide. Any device/app still depending on it (scan-to-email, relay apps) will start failing - confirm README.md Section 5 Step 2''s inventory found none before proceeding, or re-run with -ExceptionMailboxes.'
    }
}
else {
    if ($ExceptionMailboxes.Count -gt 0) {
        Write-Warning '-ExceptionMailboxes supplied without -DisableSmtpAuthTenantWide - ignored (there is nothing to except from yet).'
    }
    Write-Host "`nStage 3 skipped (-DisableSmtpAuthTenantWide not passed) - Authenticated SMTP is unchanged by this run." -ForegroundColor DarkYellow
}

Write-Host "`nDone. Run validate/Test-ExchangeLegacyAuthBlock.ps1 to verify." -ForegroundColor Cyan
```

#### `Remove-ExchangeLegacyAuthBlock.ps1`

```powershell
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
```