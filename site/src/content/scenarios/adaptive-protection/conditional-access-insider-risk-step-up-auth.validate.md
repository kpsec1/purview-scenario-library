---
part: "validate"
parent: "adaptive-protection/conditional-access-insider-risk-step-up-auth"
---
Run these checks after deployment to confirm the control is working as designed.


#### `Test-InsiderRiskStepUpPolicies.ps1`

```powershell
#Requires -Version 7.0
<#
.SYNOPSIS
    Validates the two Conditional Access policies deployed by
    deploy/New-InsiderRiskStepUpPolicies.ps1, and prints a manual checklist for the portal-only /
    delegated-auth-only prerequisites no app-only Graph query can confirm.

.DESCRIPTION
    Two-part validation per policy, matching this library's established pattern (see
    conditional-access-insider-risk-block/validate/Test-InsiderRiskConditionalAccessPolicy.ps1):
      1. Automated checks against each live conditionalAccessPolicy object - exits non-zero on a
         hard failure (policy missing, wrong condition/control shape, or - specifically for the
         Minor policy - a state that has somehow become 'enabled', which should be structurally
         impossible via the deploy/remove scripts but is checked anyway as a hard safety net).
      2. A manual checklist for everything with no API to query: whether Adaptive Protection is
         actually turned on, whether the Terms of Use agreement itself exists and is correctly
         referenced, whether break-glass exclusions have been tested.

    Read-only. Makes no changes.

.PARAMETER ModerateDisplayName
    Must match the -ModerateDisplayName used at deploy time.

.PARAMETER MinorDisplayName
    Must match the -MinorDisplayName used at deploy time.

.PARAMETER ExpectedAgreementId
    If supplied, checks the Moderate policy's grantControls.termsOfUse contains exactly this
    agreement id. Optional - omit to skip this specific check (e.g. when validating before the
    agreement id is known to the caller).

.PARAMETER ExpectedModerateState
    Expected Graph state value for the Moderate policy. Defaults to
    'enabledForReportingButNotEnforced'.

.PARAMETER ExpectedMinorState
    Expected Graph state value for the Minor policy. Defaults to
    'enabledForReportingButNotEnforced'. 'enabled' is deliberately not a valid value for this
    parameter - see .DESCRIPTION.

.PARAMETER SkipModeratePolicy
    Skip all checks for the Moderate policy (e.g. it was never deployed via -SkipModeratePolicy).

.PARAMETER SkipMinorPolicy
    Skip all checks for the Minor policy.

.EXAMPLE
    Connect-MgGraph -ClientId $AppId -TenantId $TenantId -CertificateThumbprint $Thumbprint
    ./Test-InsiderRiskStepUpPolicies.ps1 -ExpectedAgreementId '11111111-1111-1111-1111-111111111111'

.NOTES
    Sources: same as deploy/New-InsiderRiskStepUpPolicies.ps1's .NOTES block.
#>
[CmdletBinding()]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$ModerateDisplayName = 'Adaptive Protection - Require Terms of Use for Moderate Insider Risk (Custom)',

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$MinorDisplayName = 'Adaptive Protection - Insights for Minor Insider Risk (Custom)',

    [Parameter()]
    [string]$ExpectedAgreementId,

    [Parameter()]
    [ValidateSet('enabled', 'disabled', 'enabledForReportingButNotEnforced')]
    [string]$ExpectedModerateState = 'enabledForReportingButNotEnforced',

    [Parameter()]
    [ValidateSet('disabled', 'enabledForReportingButNotEnforced')]
    [string]$ExpectedMinorState = 'enabledForReportingButNotEnforced',

    [Parameter()]
    [switch]$SkipModeratePolicy,

    [Parameter()]
    [switch]$SkipMinorPolicy
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

if (-not (Get-Command Get-MgIdentityConditionalAccessPolicy -ErrorAction SilentlyContinue)) {
    throw 'Microsoft Graph PowerShell SDK not found. Install Microsoft.Graph.Authentication and Microsoft.Graph.Identity.SignIns, then Connect-MgGraph.'
}
if (-not (Get-MgContext -ErrorAction SilentlyContinue)) {
    throw 'Not connected to Microsoft Graph. Run Connect-MgGraph first.'
}

$allPolicies = @(Get-MgIdentityConditionalAccessPolicy -All -ErrorAction Stop)

if (-not $SkipModeratePolicy) {
    Write-Host "Validating Moderate policy '$ModerateDisplayName'..." -ForegroundColor Cyan
    Write-Host '--- Automated checks ---' -ForegroundColor Cyan

    $policy = $allPolicies | Where-Object { $_.DisplayName -eq $ModerateDisplayName } | Select-Object -First 1

    if (-not $policy) {
        Write-Check FAIL "Policy '$ModerateDisplayName' not found. Run deploy/New-InsiderRiskStepUpPolicies.ps1 first."
    }
    else {
        Write-Check PASS "Policy found (id $($policy.Id))."

        if ($policy.State -eq $ExpectedModerateState) { Write-Check PASS "State is '$($policy.State)' as expected." }
        else { Write-Check FAIL "State is '$($policy.State)', expected '$ExpectedModerateState'." }

        $riskLevels = @($policy.Conditions.InsiderRiskLevels | ForEach-Object { $_.ToString().ToLowerInvariant() } | Sort-Object)
        if ($riskLevels -contains 'moderate') { Write-Check PASS "insiderRiskLevels condition includes 'moderate' (got: $($riskLevels -join ', '))." }
        else { Write-Check FAIL "insiderRiskLevels condition does not include 'moderate' (got: $($riskLevels -join ', '))." }

        $includeApps = @($policy.Conditions.Applications.IncludeApplications)
        if ($includeApps -contains 'MicrosoftAdminPortals') { Write-Check PASS "Target resources includes 'MicrosoftAdminPortals'." }
        else { Write-Check FAIL "Target resources does not include 'MicrosoftAdminPortals' (got: $($includeApps -join ', '))." }

        $tou = @($policy.GrantControls.TermsOfUse)
        if ($tou.Count -eq 0) {
            Write-Check FAIL 'Grant control has no termsOfUse agreement id set.'
        }
        elseif ($ExpectedAgreementId -and ($tou -notcontains $ExpectedAgreementId)) {
            Write-Check FAIL "termsOfUse does not contain expected agreement id '$ExpectedAgreementId' (got: $($tou -join ', '))."
        }
        else {
            Write-Check PASS "Grant control references termsOfUse agreement(s): $($tou -join ', ')."
        }

        if ($policy.GrantControls.Operator -eq 'OR') { Write-Check PASS "Grant controls operator is 'OR'." }
        else { Write-Check FAIL "Grant controls operator is '$($policy.GrantControls.Operator)', expected 'OR'." }

        $excludeUsers = @($policy.Conditions.Users.ExcludeUsers)
        $excludeGroups = @($policy.Conditions.Users.ExcludeGroups)
        if ($excludeUsers.Count -eq 0 -and $excludeGroups.Count -eq 0) {
            Write-Check WARN 'No excludeUsers/excludeGroups configured. Add a break-glass exclusion before broad enforcement.'
        }
        else {
            Write-Check PASS "Exclusions present ($($excludeUsers.Count) user(s), $($excludeGroups.Count) group(s))."
        }
    }
    Write-Host ''
}

if (-not $SkipMinorPolicy) {
    Write-Host "Validating Minor policy '$MinorDisplayName'..." -ForegroundColor Cyan
    Write-Host '--- Automated checks ---' -ForegroundColor Cyan

    $policy = $allPolicies | Where-Object { $_.DisplayName -eq $MinorDisplayName } | Select-Object -First 1

    if (-not $policy) {
        Write-Check FAIL "Policy '$MinorDisplayName' not found. Run deploy/New-InsiderRiskStepUpPolicies.ps1 first."
    }
    else {
        Write-Check PASS "Policy found (id $($policy.Id))."

        if ($policy.State -eq 'enabled') {
            Write-Check FAIL "State is 'enabled'. This policy is designed to be visibility-only per Microsoft's Adaptive Protection configuration guide and should NEVER be enforced - it was not put into this state by this scenario's own deploy/remove scripts. Investigate how it was changed (portal edit outside this scenario's automation) and step it back to Report-only or Disabled."
        }
        elseif ($policy.State -eq $ExpectedMinorState) {
            Write-Check PASS "State is '$($policy.State)' as expected."
        }
        else {
            Write-Check FAIL "State is '$($policy.State)', expected '$ExpectedMinorState'."
        }

        $riskLevels = @($policy.Conditions.InsiderRiskLevels | ForEach-Object { $_.ToString().ToLowerInvariant() } | Sort-Object)
        if ($riskLevels -contains 'minor') { Write-Check PASS "insiderRiskLevels condition includes 'minor' (got: $($riskLevels -join ', '))." }
        else { Write-Check FAIL "insiderRiskLevels condition does not include 'minor' (got: $($riskLevels -join ', '))." }

        $includeApps = @($policy.Conditions.Applications.IncludeApplications)
        if ($includeApps -contains 'All') { Write-Check PASS 'Target resources includes All resources.' }
        else { Write-Check FAIL "Target resources does not include 'All' (got: $($includeApps -join ', '))." }

        $builtInControls = @($policy.GrantControls.BuiltInControls)
        if ($builtInControls -contains 'block') {
            Write-Check FAIL "Grant control is 'block' - this is the WORST possible fail-safe shape for a policy intended to stay permanently Report-only (see design.md Section 6): if this policy's state is ever changed to 'enabled' outside this scenario's scripts, 'block' would lock out every Minor-risk user tenant-wide. Reconcile with -Force to restore the deploy script's own 'mfa' container shape."
        }
        elseif ($builtInControls -contains 'mfa') {
            Write-Check PASS "Grant control is 'mfa' (the disclosed, fail-safe payload container - see README.md Section 6)."
        }
        else {
            Write-Check WARN "Grant control is '$($builtInControls -join ', ')' - not the deploy script's own default ('mfa'). Confirm this was an intentional override."
        }
    }
    Write-Host ''
}

Write-Host '--- Manual checklist (no Graph/PowerShell query exists for these) ---' -ForegroundColor Cyan
Write-Host '  [ ] Adaptive Protection is turned ON: Purview portal > Insider Risk Management > Adaptive protection > Adaptive Protection settings.' -ForegroundColor White
Write-Host '  [ ] At least one feeder Insider Risk Management policy is in Adaptive Protection scope and has completed a baseline/tuning cycle.' -ForegroundColor White
Write-Host '  [ ] The Terms of Use agreement referenced by the Moderate policy actually exists and its PDF content is current: Entra admin center > Conditional Access > Terms of use, or Get-MgIdentityGovernanceTermsOfUseAgreement.' -ForegroundColor White
Write-Host '  [ ] A test sign-in to a Microsoft Admin Portal (e.g. entra.microsoft.com) by a Moderate-risk test account shows the Terms of Use prompt (Enabled mode) or a report-only match (Report-only mode).' -ForegroundColor White
Write-Host '  [ ] Entra admin center > Conditional Access > Insights and reporting shows this policy pair''s Report-only evaluation results (allow 24-48h for sign-in log population) before promoting the Moderate policy to enforcement.' -ForegroundColor White
Write-Host '  [ ] The excluded break-glass account(s)/group have been sign-in tested and confirmed not disrupted before promoting the Moderate policy to -Mode Enabled.' -ForegroundColor White
Write-Host '  [ ] Up to 36 hours after Adaptive Protection is first enabled before insider risk levels (and both policies'' evaluation of them) are actually applied.' -ForegroundColor White

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