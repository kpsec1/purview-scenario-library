---
part: "validate"
parent: "adaptive-protection/exchange-legacy-auth-block"
---
Run these checks after deployment to confirm the control is working as designed.


#### `Test-ExchangeLegacyAuthBlock.ps1`

```powershell
#Requires -Modules @{ ModuleName = 'ExchangeOnlineManagement'; ModuleVersion = '3.2.0' }
<#
.SYNOPSIS
    Validates the Exchange-side legacy authentication block: the baseline AuthenticationPolicy's
    shape, whether it is the tenant default, the tenant-wide SMTP AUTH transport gate, exception
    mailbox coverage, and (optionally) any user with a conflicting explicit policy assignment that
    the tenant default does not cover.

.DESCRIPTION
    Read-only. Makes no changes. Five checks:
      1. Baseline policy exists with every AllowBasicAuth* blocked.
      2. Tenant DefaultAuthenticationPolicy, if expected to be set.
      3. Tenant-wide SmtpClientAuthenticationDisabled, if expected to be set.
      4. Each -ExpectedExceptionMailboxes entry: assigned the exception policy AND has the
         CASMailbox override set (both gates - design.md Section 5).
      5. -CheckUserOverrides (opt-in, can be slow on a large tenant): every user with an explicit
         AuthenticationPolicy assignment other than this scenario's own two policies - these are
         NOT covered by the tenant default (README.md Section 11) and need individual review.

.PARAMETER PolicyName
    Must match deploy time. Defaults to 'Block Legacy Authentication (Exchange)'.

.PARAMETER ExceptionPolicyName
    Must match deploy time. Defaults to 'Allow-Smtp-Auth-Exception'.

.PARAMETER ExpectOrgDefault
    If set, FAILs when the tenant DefaultAuthenticationPolicy is not -PolicyName. If not set, only
    reports the current value as INFO (some tenants may deliberately assign per-user instead of a
    tenant default).

.PARAMETER ExpectSmtpAuthDisabledTenantWide
    If set, FAILs when Get-TransportConfig's SmtpClientAuthenticationDisabled is not $true.

.PARAMETER ExpectedExceptionMailboxes
    Mailbox identities that should be covered by both SMTP AUTH exception gates. Each one missing
    either gate is a FAIL (a mailbox that needs the exception but only has one of the two gates
    opened may or may not actually work - design.md Section 5 - so this script treats "only one
    gate open" the same as "not covered" rather than guessing it's sufficient).

.PARAMETER CheckUserOverrides
    Also runs Get-User -ResultSize Unlimited (can be slow on a large tenant) to find any user whose
    AuthenticationPolicy is set to something other than $null, -PolicyName, or -ExceptionPolicyName
    - these users are NOT covered by the tenant default and need individual review. Off by default.

.EXAMPLE
    Connect-ExchangeOnline -AppId $AppId -CertificateThumbprint $Thumbprint -Organization $TenantDomain
    ./Test-ExchangeLegacyAuthBlock.ps1 -ExpectOrgDefault -ExpectSmtpAuthDisabledTenantWide -CheckUserOverrides

.NOTES
    Sources: same as deploy/New-ExchangeLegacyAuthBlock.ps1's .NOTES block.
#>
[CmdletBinding()]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$PolicyName = 'Block Legacy Authentication (Exchange)',

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$ExceptionPolicyName = 'Allow-Smtp-Auth-Exception',

    [Parameter()]
    [switch]$ExpectOrgDefault,

    [Parameter()]
    [switch]$ExpectSmtpAuthDisabledTenantWide,

    [Parameter()]
    [string[]]$ExpectedExceptionMailboxes = @(),

    [Parameter()]
    [switch]$CheckUserOverrides
)

$ErrorActionPreference = 'Stop'
$script:FailCount = 0
$script:WarnCount = 0

function Write-Check {
    param([ValidateSet('PASS', 'FAIL', 'WARN', 'INFO')][string]$Status, [string]$Message)
    $color = switch ($Status) { 'PASS' { 'Green' } 'FAIL' { 'Red' } 'WARN' { 'Yellow' } 'INFO' { 'Cyan' } }
    Write-Host "  [$Status] $Message" -ForegroundColor $color
    if ($Status -eq 'FAIL') { $script:FailCount++ }
    if ($Status -eq 'WARN') { $script:WarnCount++ }
}

if (-not (Get-Command Get-AuthenticationPolicy -ErrorAction SilentlyContinue)) {
    throw 'No Exchange Online PowerShell session found. Run Connect-ExchangeOnline first.'
}

Write-Host 'Validating Exchange-side legacy authentication block...' -ForegroundColor Cyan
Write-Host '--- Check 1: baseline policy ---' -ForegroundColor Cyan

$baseline = Get-AuthenticationPolicy -Identity $PolicyName -ErrorAction SilentlyContinue
if (-not $baseline) {
    Write-Check FAIL "Baseline policy '$PolicyName' does not exist."
}
else {
    $allowProps = $baseline.PSObject.Properties | Where-Object { $_.Name -like 'AllowBasicAuth*' }
    $stillAllowed = @($allowProps | Where-Object { $_.Value -eq $true })
    if ($stillAllowed.Count -eq 0) {
        Write-Check PASS "Baseline policy '$PolicyName' exists with every AllowBasicAuth* blocked."
    }
    else {
        Write-Check FAIL "Baseline policy '$PolicyName' still allows Basic auth for: $($stillAllowed.Name -join ', ')."
    }
}

Write-Host "`n--- Check 2: tenant default assignment ---" -ForegroundColor Cyan
$orgConfig = Get-OrganizationConfig
if ($orgConfig.DefaultAuthenticationPolicy -eq $PolicyName) {
    Write-Check PASS "Tenant DefaultAuthenticationPolicy = '$PolicyName'."
}
elseif ($ExpectOrgDefault) {
    Write-Check FAIL "Tenant DefaultAuthenticationPolicy is '$($orgConfig.DefaultAuthenticationPolicy)', expected '$PolicyName'."
}
else {
    Write-Check INFO "Tenant DefaultAuthenticationPolicy is '$($orgConfig.DefaultAuthenticationPolicy)' (not asserted - pass -ExpectOrgDefault to require '$PolicyName')."
}

Write-Host "`n--- Check 3: tenant-wide SMTP AUTH transport gate ---" -ForegroundColor Cyan
$transportConfig = Get-TransportConfig
if ($transportConfig.SmtpClientAuthenticationDisabled -eq $true) {
    Write-Check PASS 'SmtpClientAuthenticationDisabled = $true tenant-wide.'
}
elseif ($ExpectSmtpAuthDisabledTenantWide) {
    Write-Check FAIL "SmtpClientAuthenticationDisabled = $($transportConfig.SmtpClientAuthenticationDisabled), expected `$true."
}
else {
    Write-Check INFO "SmtpClientAuthenticationDisabled = $($transportConfig.SmtpClientAuthenticationDisabled) (not asserted - pass -ExpectSmtpAuthDisabledTenantWide to require `$true)."
}

if ($ExpectedExceptionMailboxes.Count -gt 0) {
    Write-Host "`n--- Check 4: SMTP AUTH exception mailbox coverage ---" -ForegroundColor Cyan
    foreach ($mailbox in $ExpectedExceptionMailboxes) {
        $user = Get-User -Identity $mailbox -ErrorAction SilentlyContinue
        $cas = Get-CASMailbox -Identity $mailbox -ErrorAction SilentlyContinue
        $policyOk = $user -and $user.AuthenticationPolicy -eq $ExceptionPolicyName
        $casOk = $cas -and $cas.SmtpClientAuthenticationDisabled -eq $false

        if ($policyOk -and $casOk) {
            Write-Check PASS "'$mailbox' - both SMTP AUTH gates open (policy + CASMailbox override)."
        }
        elseif ($policyOk -or $casOk) {
            Write-Check FAIL "'$mailbox' - only one of the two SMTP AUTH gates is open (policy: $policyOk, CASMailbox override: $casOk). design.md Section 5: Microsoft does not document which gate wins if they disagree - this scenario requires both."
        }
        else {
            Write-Check FAIL "'$mailbox' - neither SMTP AUTH gate is open. This mailbox will lose SMTP AUTH once the tenant-wide gate is enabled."
        }
    }
}

if ($CheckUserOverrides) {
    Write-Host "`n--- Check 5: per-user policy overrides (can be slow) ---" -ForegroundColor Cyan
    $knownPolicies = @($PolicyName, $ExceptionPolicyName)
    $overrides = @(Get-User -ResultSize Unlimited -ErrorAction Stop | Where-Object {
            $_.AuthenticationPolicy -and $_.AuthenticationPolicy -notin $knownPolicies
        })
    if ($overrides.Count -eq 0) {
        Write-Check PASS 'No user found with an AuthenticationPolicy assignment outside this scenario''s own two policies.'
    }
    else {
        Write-Check WARN "$($overrides.Count) user(s) have an explicit AuthenticationPolicy other than this scenario's own - NOT covered by the tenant default (README.md Section 11). Review: $((@($overrides | Select-Object -First 10 -ExpandProperty UserPrincipalName)) -join ', ')$(if ($overrides.Count -gt 10) { '...' })."
    }
}
else {
    Write-Check INFO 'Per-user override check skipped (pass -CheckUserOverrides to run it - can be slow on a large tenant).'
}

Write-Host "`n--- Manual checklist (no cmdlet exists for these) ---" -ForegroundColor Cyan
Write-Host '  [ ] README.md Section 5 Step 2''s SMTP AUTH / legacy-protocol usage inventory was reviewed before enforcing.' -ForegroundColor White
Write-Host '  [ ] Every -ExceptionMailboxes entry was end-to-end tested (a real SMTP AUTH send/receive), not just config-checked.' -ForegroundColor White
Write-Host '  [ ] Aware of Microsoft''s own SMTP AUTH default-disable date (end of December 2026) and that this scenario is meant to get ahead of it, not replace ongoing monitoring.' -ForegroundColor White
Write-Host '  [ ] Exception mailbox list reviewed on the same quarterly cadence as the Conditional Access sibling scenario - README.md Section 8.' -ForegroundColor White

Write-Host "`nSummary: $script:FailCount FAIL, $script:WarnCount WARN." -ForegroundColor Cyan
if ($script:FailCount -gt 0) {
    Write-Host 'Result: FAIL' -ForegroundColor Red
    exit 1
}
else {
    Write-Host 'Result: PASS (automated checks only - complete the manual checklist above before relying on this in production).' -ForegroundColor Green
    exit 0
}
```