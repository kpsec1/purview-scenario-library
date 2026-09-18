---
part: "validate"
parent: "adaptive-protection/conditional-access-insider-risk-block"
---
Run these checks after deployment to confirm the control is working as designed.


#### `Test-InsiderRiskConditionalAccessPolicy.ps1`

```powershell
#Requires -Version 7.0
<#
.SYNOPSIS
    Validates the Conditional Access policy deployed by
    deploy/New-InsiderRiskConditionalAccessPolicy.ps1, and prints a manual checklist for the
    portal-only prerequisites no Graph query can confirm.

.DESCRIPTION
    Two-part validation, matching this library's established pattern (e.g.
    scenarios/adaptive-protection/dynamic-risk-dlp-enforcement/validate/
    Test-AdaptiveProtectionDlpPolicy.ps1):
      1. Automated checks against the live conditionalAccessPolicy object - exits non-zero on a
         hard failure (policy missing, wrong condition/control shape).
      2. A manual checklist for everything with no API to query: whether Adaptive Protection is
         actually turned on, whether Entra ID P2 is licensed, whether a feeder Insider Risk
         Management policy is in Adaptive Protection's scope. A policy that passes every
         automated check can still match zero users if these portal-only prerequisites aren't met
         - the same "looks configured, does nothing" trap the DLP sibling scenario's own
         validation script exists to catch.

    Read-only. Makes no changes.

.PARAMETER DisplayName
    Must match the -DisplayName used at deploy time. Defaults to
    'Adaptive Protection - Block Elevated Insider Risk (Custom)'.

.PARAMETER ExpectedRiskLevels
    Risk levels expected to be present on the policy's insiderRiskLevels condition. Defaults to
    @('elevated').

.PARAMETER ExpectedState
    Expected Graph state value. Defaults to 'enabledForReportingButNotEnforced' (this script's
    default expectation matches the deploy script's own default -Mode ReportOnly - pass
    'enabled' once promoted to enforcement).

.PARAMETER ExpectedExcludeGuestOrExternalUserTypes
    Guest/external user categories expected on conditions.users.excludeGuestsOrExternalUsers.
    guestOrExternalUserTypes. Defaults to @('b2bDirectConnectUser', 'serviceProvider',
    'otherExternalUser'), matching deploy/New-InsiderRiskConditionalAccessPolicy.ps1's own
    default. Pass @() if you deployed with -ExcludeGuestOrExternalUserTypes @() (exclusion
    omitted).

.EXAMPLE
    Connect-MgGraph -ClientId $AppId -TenantId $TenantId -CertificateThumbprint $Thumbprint
    ./Test-InsiderRiskConditionalAccessPolicy.ps1

.EXAMPLE
    ./Test-InsiderRiskConditionalAccessPolicy.ps1 -ExpectedState enabled

.NOTES
    Sources: same as deploy/New-InsiderRiskConditionalAccessPolicy.ps1's .NOTES block, including
    that script's disclosed VERIFY on the exact guestOrExternalUserTypes multi-value wire format.
#>
[CmdletBinding()]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$DisplayName = 'Adaptive Protection - Block Elevated Insider Risk (Custom)',

    [Parameter()]
    [string[]]$ExpectedRiskLevels = @('elevated'),

    [Parameter()]
    [ValidateSet('enabled', 'disabled', 'enabledForReportingButNotEnforced')]
    [string]$ExpectedState = 'enabledForReportingButNotEnforced',

    [Parameter()]
    [ValidateSet('internalGuest', 'b2bCollaborationGuest', 'b2bCollaborationMember', 'b2bDirectConnectUser', 'otherExternalUser', 'serviceProvider')]
    [string[]]$ExpectedExcludeGuestOrExternalUserTypes = @('b2bDirectConnectUser', 'serviceProvider', 'otherExternalUser')
)

$ErrorActionPreference = 'Stop'
$script:FailCount = 0
$script:WarnCount = 0

function Write-Check {
    param([ValidateSet('PASS', 'FAIL', 'WARN')][string]$Status, [string]$Message)
    $color = switch ($Status) { 'PASS' { 'Green' } 'FAIL' { 'Red' } 'WARN' { 'Yellow' } }
    Write-Host "  [$Status] $Message" -ForegroundColor $color
    if ($Status -eq 'FAIL') { $script:FailCount++ }
    if ($Status -eq 'WARN') { $script:WarnCount++ }
}

function ConvertTo-GuestOrExternalUserTypeArray {
    # Same normalization as deploy/New-InsiderRiskConditionalAccessPolicy.ps1's helper of the same
    # name - see that script's .NOTES for why both shapes are handled.
    param($Value)
    if ($null -eq $Value) { return @() }
    if ($Value -is [string]) {
        if ([string]::IsNullOrWhiteSpace($Value)) { return @() }
        return @($Value -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' })
    }
    return @($Value | ForEach-Object { $_.ToString() })
}

if (-not (Get-Command Get-MgIdentityConditionalAccessPolicy -ErrorAction SilentlyContinue)) {
    throw 'Microsoft Graph PowerShell SDK not found. Install Microsoft.Graph.Authentication and Microsoft.Graph.Identity.SignIns, then Connect-MgGraph.'
}
if (-not (Get-MgContext -ErrorAction SilentlyContinue)) {
    throw 'Not connected to Microsoft Graph. Run Connect-MgGraph first.'
}

Write-Host "Validating Conditional Access policy '$DisplayName'..." -ForegroundColor Cyan
Write-Host '--- Automated checks ---' -ForegroundColor Cyan

$policy = @(Get-MgIdentityConditionalAccessPolicy -All -ErrorAction Stop) | Where-Object { $_.DisplayName -eq $DisplayName } | Select-Object -First 1

if (-not $policy) {
    Write-Check FAIL "Policy '$DisplayName' not found. Run deploy/New-InsiderRiskConditionalAccessPolicy.ps1 first."
}
else {
    Write-Check PASS "Policy found (id $($policy.Id))."

    if ($policy.State -eq $ExpectedState) {
        Write-Check PASS "State is '$($policy.State)' as expected."
    }
    else {
        Write-Check FAIL "State is '$($policy.State)', expected '$ExpectedState'."
    }

    $actualRiskLevels = @($policy.Conditions.InsiderRiskLevels | ForEach-Object { $_.ToString().ToLowerInvariant() } | Sort-Object)
    $wantRiskLevels = @($ExpectedRiskLevels | ForEach-Object { $_.ToLowerInvariant() } | Sort-Object)
    if (@(Compare-Object $actualRiskLevels $wantRiskLevels).Count -eq 0) {
        Write-Check PASS "insiderRiskLevels condition = $($actualRiskLevels -join ', ')."
    }
    else {
        Write-Check FAIL "insiderRiskLevels condition = $($actualRiskLevels -join ', '); expected $($wantRiskLevels -join ', ')."
    }

    $includeApps = @($policy.Conditions.Applications.IncludeApplications)
    if ($includeApps -contains 'All') {
        Write-Check PASS 'Target resources includes All applications.'
    }
    else {
        Write-Check FAIL "Target resources does not include 'All' (got: $($includeApps -join ', '))."
    }

    $includeUsers = @($policy.Conditions.Users.IncludeUsers)
    if ($includeUsers -contains 'All') {
        Write-Check PASS 'Users condition includes All users.'
    }
    else {
        Write-Check FAIL "Users condition does not include 'All' (got: $($includeUsers -join ', '))."
    }

    $excludeUsers = @($policy.Conditions.Users.ExcludeUsers)
    $excludeGroups = @($policy.Conditions.Users.ExcludeGroups)
    if ($excludeUsers.Count -eq 0 -and $excludeGroups.Count -eq 0) {
        if ($policy.State -eq 'enabled') {
            Write-Check FAIL 'No excludeUsers/excludeGroups configured while the policy is ENABLED (enforcing). A break-glass/emergency-access account has no exclusion - see README.md Section 3 before leaving this as-is.'
        }
        else {
            Write-Check WARN 'No excludeUsers/excludeGroups configured. Not blocking yet in this state, but add a break-glass exclusion before promoting to enabled.'
        }
    }
    else {
        Write-Check PASS "Exclusions present ($($excludeUsers.Count) user(s), $($excludeGroups.Count) group(s))."
    }

    $actualExcludeGuestTypes = @(ConvertTo-GuestOrExternalUserTypeArray $policy.Conditions.Users.ExcludeGuestsOrExternalUsers.GuestOrExternalUserTypes | ForEach-Object { $_.ToLowerInvariant() } | Sort-Object)
    $wantExcludeGuestTypes = @($ExpectedExcludeGuestOrExternalUserTypes | ForEach-Object { $_.ToLowerInvariant() } | Sort-Object)
    if (@(Compare-Object $actualExcludeGuestTypes $wantExcludeGuestTypes).Count -eq 0) {
        if ($wantExcludeGuestTypes.Count -gt 0) {
            Write-Check PASS "excludeGuestsOrExternalUsers.guestOrExternalUserTypes = $($actualExcludeGuestTypes -join ', ')."
        }
        else {
            Write-Check WARN 'No guest/external user categories excluded (matches -ExpectedExcludeGuestOrExternalUserTypes @() - confirm this is intentional for your tenant, since Microsoft''s own documented reference configuration excludes B2B direct connect / service provider / other external users).'
        }
    }
    else {
        Write-Check FAIL "excludeGuestsOrExternalUsers.guestOrExternalUserTypes = $($actualExcludeGuestTypes -join ', '); expected $($wantExcludeGuestTypes -join ', ')."
    }

    $builtInControls = @($policy.GrantControls.BuiltInControls)
    if ($builtInControls -contains 'block') {
        Write-Check PASS "Grant control includes 'block'."
    }
    else {
        Write-Check FAIL "Grant control does not include 'block' (got: $($builtInControls -join ', '))."
    }

    if ($policy.GrantControls.Operator -eq 'OR') {
        Write-Check PASS "Grant controls operator is 'OR'."
    }
    else {
        Write-Check FAIL "Grant controls operator is '$($policy.GrantControls.Operator)', expected 'OR'."
    }
}

Write-Host "`n--- Manual checklist (no Graph/PowerShell query exists for these) ---" -ForegroundColor Cyan
Write-Host '  [ ] Adaptive Protection is turned ON: Purview portal > Insider Risk Management > Adaptive protection > Adaptive Protection settings.' -ForegroundColor White
Write-Host '  [ ] At least one feeder Insider Risk Management policy is in Adaptive Protection scope and has completed a baseline/tuning cycle.' -ForegroundColor White
Write-Host '  [ ] Insider risk levels (Elevated/Moderate/Minor) are defined: Purview portal > Insider Risk Management > Adaptive protection > Insider risk levels.' -ForegroundColor White
Write-Host '  [ ] Tenant holds Microsoft Entra ID P2 (or an equivalent bundle) for every user in this policy''s scope - docs/licensing-matrix.md Section 8.' -ForegroundColor White
Write-Host '  [ ] The excluded break-glass account(s)/group have been sign-in tested and confirmed NOT blocked before promoting to -Mode Enabled.' -ForegroundColor White
Write-Host '  [ ] Entra admin center > Conditional Access > Insights and reporting shows this policy''s Report-only evaluation results (allow 24-48h for sign-in log population) before promoting to enforcement.' -ForegroundColor White
Write-Host '  [ ] Up to 36 hours after Adaptive Protection is first enabled before insider risk levels (and this policy''s evaluation of them) are actually applied - do not conclude a pilot failed before this window elapses.' -ForegroundColor White

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