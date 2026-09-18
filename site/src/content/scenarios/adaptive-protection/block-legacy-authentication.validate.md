---
part: "validate"
parent: "adaptive-protection/block-legacy-authentication"
---
Run these checks after deployment to confirm the control is working as designed.


#### `Test-BlockLegacyAuthenticationPolicy.ps1`

```powershell
#Requires -Version 7.0
<#
.SYNOPSIS
    Validates that legacy authentication is actually covered by SOME Conditional Access control -
    either a Microsoft-managed "Block legacy authentication" policy, or the custom policy deployed
    by deploy/New-BlockLegacyAuthenticationPolicy.ps1 - and prints a manual checklist for the
    portal-only checks no Graph query can confirm.

.DESCRIPTION
    Three-part validation:
      1. Check for a Microsoft-managed policy (best-effort displayName match - see deploy script's
         .NOTES) and report its state.
      2. Check for this scenario's own custom policy (by -DisplayName) and validate its shape if
         present - exits non-zero on a hard failure (wrong condition/control shape).
      3. If NEITHER is found, this is a hard FAIL: the tenant has no Conditional Access control over
         legacy authentication at all (Security Defaults, a free-tier alternative, is a separate,
         unrelated mechanism this script does not check - see README.md Section 3).
      4. A manual checklist for everything with no API to query: legacy-auth-usage impact review,
         break-glass testing, and the Microsoft-managed policy's 30-day auto-enable clock.

    Read-only. Makes no changes.

.PARAMETER DisplayName
    Must match the -DisplayName used at deploy time for the custom policy path. Defaults to
    'Block Legacy Authentication (Custom)'.

.PARAMETER ExpectedState
    Expected Graph state value for the custom policy, if present. Defaults to
    'enabledForReportingButNotEnforced' (matches the deploy script's own default -Mode ReportOnly -
    pass 'enabled' once promoted to enforcement). Not applied to a Microsoft-managed policy, whose
    state this script only reports, never judges pass/fail on (Microsoft controls its rollout
    timeline, not this scenario).

.EXAMPLE
    Connect-MgGraph -ClientId $AppId -TenantId $TenantId -CertificateThumbprint $Thumbprint
    ./Test-BlockLegacyAuthenticationPolicy.ps1

.EXAMPLE
    ./Test-BlockLegacyAuthenticationPolicy.ps1 -ExpectedState enabled

.NOTES
    Sources: same as deploy/New-BlockLegacyAuthenticationPolicy.ps1's .NOTES block.
#>
[CmdletBinding()]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$DisplayName = 'Block Legacy Authentication (Custom)',

    [Parameter()]
    [ValidateSet('enabled', 'disabled', 'enabledForReportingButNotEnforced')]
    [string]$ExpectedState = 'enabledForReportingButNotEnforced'
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

if (-not (Get-Command Get-MgIdentityConditionalAccessPolicy -ErrorAction SilentlyContinue)) {
    throw 'Microsoft Graph PowerShell SDK not found. Install Microsoft.Graph.Authentication and Microsoft.Graph.Identity.SignIns, then Connect-MgGraph.'
}
if (-not (Get-MgContext -ErrorAction SilentlyContinue)) {
    throw 'Not connected to Microsoft Graph. Run Connect-MgGraph first.'
}

Write-Host 'Validating legacy authentication coverage...' -ForegroundColor Cyan
Write-Host '--- Automated checks ---' -ForegroundColor Cyan

$allPolicies = @(Get-MgIdentityConditionalAccessPolicy -All -ErrorAction Stop)

$managed = @($allPolicies | Where-Object {
        $_.DisplayName -and $_.DisplayName -imatch '^Microsoft-managed:' -and $_.DisplayName -imatch 'legacy'
    }) | Select-Object -First 1

$managedActive = $false
if ($managed) {
    Write-Check INFO "Microsoft-managed policy '$($managed.DisplayName)' found (id $($managed.Id), state: $($managed.State))."
    if ($managed.State -eq 'enabled') {
        Write-Check PASS 'Microsoft-managed policy is enabled (enforcing).'
        $managedActive = $true
    }
    elseif ($managed.State -eq 'enabledForReportingButNotEnforced') {
        Write-Check WARN 'Microsoft-managed policy is in Report-only - not yet blocking anyone. Microsoft auto-enables it no less than 30 days after it first appeared unless disabled or promoted sooner - see README.md Section 8.'
        $managedActive = $true
    }
    else {
        Write-Check FAIL "Microsoft-managed policy state is '$($managed.State)' (disabled/opted out) - legacy authentication is NOT blocked or reported on by it. This counts as no coverage from this policy, not a soft warning."
    }
}
else {
    Write-Check INFO 'No Microsoft-managed "Block legacy authentication" policy detected (best-effort displayName match - see deploy script .NOTES).'
}

$policy = @($allPolicies) | Where-Object { $_.DisplayName -eq $DisplayName } | Select-Object -First 1

if (-not $policy) {
    Write-Check INFO "Custom policy '$DisplayName' not found."
}
else {
    Write-Check PASS "Custom policy '$DisplayName' found (id $($policy.Id))."

    if ($policy.State -eq $ExpectedState) {
        Write-Check PASS "State is '$($policy.State)' as expected."
    }
    else {
        Write-Check FAIL "State is '$($policy.State)', expected '$ExpectedState'."
    }

    $actualClientAppTypes = @($policy.Conditions.ClientAppTypes | ForEach-Object { $_.ToString().ToLowerInvariant() } | Sort-Object)
    $wantClientAppTypes = @('exchangeactivesync', 'other')
    if (@(Compare-Object $actualClientAppTypes $wantClientAppTypes).Count -eq 0) {
        Write-Check PASS "clientAppTypes condition = $($actualClientAppTypes -join ', ')."
    }
    else {
        Write-Check FAIL "clientAppTypes condition = $($actualClientAppTypes -join ', '); expected exchangeActiveSync, other. A broader or narrower set changes what this policy actually restricts - see README.md Section 6."
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

$policyActive = $policy -and $policy.State -ne 'disabled'

if (-not $managedActive -and -not $policyActive) {
    if (-not $managed -and -not $policy) {
        Write-Check FAIL 'Neither a Microsoft-managed policy nor this scenario''s custom policy was found. Legacy authentication is NOT restricted by Conditional Access in this tenant (Security Defaults, a separate free-tier mechanism, is not checked by this script - confirm separately if that is the intended control - README.md Section 3).'
    }
    else {
        Write-Check FAIL 'A policy object exists but every one found (Microsoft-managed and/or custom) is in state ''disabled''. This is equivalent to no coverage at all - legacy authentication is NOT restricted, blocked, or even reported on in this tenant right now.'
    }
}

Write-Host "`n--- Manual checklist (no Graph/PowerShell query exists for these) ---" -ForegroundColor Cyan
Write-Host '  [ ] Reviewed the Sign-ins using legacy authentication workbook (or filtered sign-in logs by Client App) to confirm actual impact before promoting either policy to enforcing/enabled.' -ForegroundColor White
Write-Host '  [ ] If relying on the Microsoft-managed policy: break-glass/emergency-access accounts are added to its exclusions in the Microsoft Entra admin center (this script cannot modify a Microsoft-managed policy).' -ForegroundColor White
Write-Host '  [ ] If relying on the Microsoft-managed policy: aware of its auto-enable timeline (no less than 30 days after first appearing in Report-only) and has decided whether to accelerate or opt out.' -ForegroundColor White
Write-Host '  [ ] Confirmed which control (Microsoft-managed, this scenario''s custom policy, both, or Security Defaults) is the tenant''s actual source of truth for this control, to avoid contradictory guidance during an incident.' -ForegroundColor White
Write-Host '  [ ] Tenant holds Microsoft Entra ID P1 (or an equivalent bundle) for every user in the custom policy''s scope, if using the custom policy path - docs/licensing-matrix.md Section 9.' -ForegroundColor White

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