---
part: "validate"
parent: "data-lifecycle-management/adaptive-scope-retention"
---
Run these checks after deployment to confirm the control is working as designed.


#### `Test-AdaptiveScopeRetention.ps1`

```powershell
#Requires -Version 7.0
<#
.SYNOPSIS
    Verifies the adaptive scope and the adaptive-scope retention policy/rule exist and are
    configured as expected.

.DESCRIPTION
    Read-only - never modifies any object. Uses Security & Compliance PowerShell Get-* cmdlets to
    check, against the config file:
      1. The adaptive scope exists with the expected LocationType.
      2. The retention policy exists, is enabled, and its AdaptiveScopeLocation includes the scope.
      3. The rule exists and applies the expected RetentionDuration/RetentionComplianceAction.
      4. (Informational, non-failing) A small sample of current scope membership via
         Get-AdaptiveScopeMembers, so an operator can sanity-check "who does this actually cover"
         without waiting for the portal's own scope-details view.
    Exits non-zero on any hard failure (safe for a CI-style pre-flight). Safe to re-run.

    Connect first with Connect-IPPSSession. A View-Only role that can read retention/adaptive-scope
    configuration is sufficient.

.PARAMETER ConfigPath
    Path to the config to validate against. Defaults to
    '../deploy/config/adaptive-scope-retention.sample.json'.

.PARAMETER SkipMembershipSample
    Skip the informational Get-AdaptiveScopeMembers call (useful for a fast, minimal-permission
    pre-flight, or if the scope is very large).

.EXAMPLE
    Connect-IPPSSession -AppId $AppId -Certificate $Cert -Organization 'contoso.onmicrosoft.com'
    ./Test-AdaptiveScopeRetention.ps1

.NOTES
    Grounded in Microsoft Learn:
    - Get-AdaptiveScope / Get-AdaptiveScopeMembers (-Identity, -State, -PageResultSize; metadata +
      up to 10,000 members per page, 5-day population delay):
      https://learn.microsoft.com/powershell/module/exchangepowershell/get-adaptivescope
      https://learn.microsoft.com/powershell/module/exchangepowershell/get-adaptivescopemembers
    - Get-RetentionCompliancePolicy / Get-RetentionComplianceRule:
      https://learn.microsoft.com/powershell/module/exchangepowershell/get-retentioncompliancepolicy
      https://learn.microsoft.com/powershell/module/exchangepowershell/get-retentioncompliancerule
#>
[CmdletBinding()]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$ConfigPath = (Join-Path $PSScriptRoot '../deploy/config/adaptive-scope-retention.sample.json'),

    [Parameter()]
    [switch]$SkipMembershipSample
)

$ErrorActionPreference = 'Stop'
$script:failures = 0
function Test-Check {
    param([string]$Description, [bool]$Condition, [switch]$Warn)
    if ($Condition) { Write-Host "  [PASS] $Description" -ForegroundColor Green }
    elseif ($Warn) { Write-Host "  [WARN] $Description" -ForegroundColor Yellow }
    else { Write-Host "  [FAIL] $Description" -ForegroundColor Red; $script:failures++ }
}

if (-not (Get-Command Get-RetentionCompliancePolicy -ErrorAction SilentlyContinue)) {
    throw "Retention cmdlets not found. Connect first: Connect-IPPSSession. See docs/automation-surface.md Section 3."
}
if (-not (Test-Path -LiteralPath $ConfigPath)) { throw "Config file not found: $ConfigPath" }
$cfg = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json

Write-Host "Validating adaptive-scope retention ('$($cfg.adaptiveScope.name)' / '$($cfg.policy.name)')..." -ForegroundColor Cyan

# Adaptive scope
$scope = Get-AdaptiveScope -Identity $cfg.adaptiveScope.name -ErrorAction SilentlyContinue
Test-Check -Description "Adaptive scope '$($cfg.adaptiveScope.name)' exists" -Condition ($null -ne $scope)
if ($scope) {
    Test-Check -Description "  LocationType is '$($cfg.adaptiveScope.locationType)' (current: $($scope.LocationType))" `
        -Condition ("$($scope.LocationType)" -eq "$($cfg.adaptiveScope.locationType)")
}

# Policy
$policy = Get-RetentionCompliancePolicy -Identity $cfg.policy.name -ErrorAction SilentlyContinue
Test-Check -Description "Retention policy '$($cfg.policy.name)' exists" -Condition ($null -ne $policy)
if ($policy) {
    Test-Check -Description "  Policy is enabled" -Condition ([bool]$policy.Enabled) -Warn
    $scopeLocations = @($policy.AdaptiveScopeLocation)
    Test-Check -Description "  Policy references adaptive scope '$($cfg.adaptiveScope.name)'" `
        -Condition ($scopeLocations -contains $cfg.adaptiveScope.name) -Warn
    if ($policy.DistributionStatus) { Write-Host "    Distribution status: $($policy.DistributionStatus)" -ForegroundColor Cyan }
}

# Rule
$rule = Get-RetentionComplianceRule -Policy $cfg.policy.name -ErrorAction SilentlyContinue | Select-Object -First 1
Test-Check -Description "Retention rule exists on the policy" -Condition ($null -ne $rule)
if ($rule) {
    if ("$($cfg.rule.retentionDurationDays)" -ne 'Unlimited') {
        Test-Check -Description "  RetentionDuration is $($cfg.rule.retentionDurationDays) days (current: $($rule.RetentionDuration))" `
            -Condition ("$($rule.RetentionDuration)" -eq "$($cfg.rule.retentionDurationDays)") -Warn
    }
    Test-Check -Description "  RetentionComplianceAction is '$($cfg.rule.retentionComplianceAction)' (current: $($rule.RetentionComplianceAction))" `
        -Condition ("$($rule.RetentionComplianceAction)" -eq "$($cfg.rule.retentionComplianceAction)")
}

# Informational membership sample (never fails the run)
if (-not $SkipMembershipSample -and $scope) {
    try {
        # VERIFY: Microsoft's reference documents that the first returned element carries result
        # metadata (total member count, page size, whether more pages exist, a Watermark) but does
        # not name its properties. Printed generically ($meta | Format-List) rather than guessing a
        # property name (e.g. TotalMemberCount) that isn't in the documented reference - see
        # README.md Section 11.
        $sample = Get-AdaptiveScopeMembers -Identity $cfg.adaptiveScope.name -State Added -PageResultSize 5 -ErrorAction Stop
        $meta = $sample | Select-Object -First 1
        Write-Host "`n  Membership sample (informational, not a hard check) - result metadata:" -ForegroundColor Cyan
        $meta | Format-List | Out-String | Write-Host
        Write-Host "  If membership looks empty shortly after creation, that's expected - allow up to 5 days for the query to populate." -ForegroundColor Cyan
    }
    catch {
        Write-Host "`n  Could not sample scope membership (informational only): $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

Write-Host "`n  Note: policy distribution and adaptive scope membership can each take up to several days. Confirm actual coverage via the portal's Adaptive scopes > Scope details view before relying on this operationally." -ForegroundColor Cyan
Write-Host "$(if ($script:failures -eq 0) { 'All hard checks passed.' } else { "$script:failures hard check(s) failed." })" `
    -ForegroundColor $(if ($script:failures -eq 0) { 'Green' } else { 'Red' })
if ($script:failures -gt 0) { exit 1 }
```