---
part: "validate"
parent: "data-lifecycle-management/adaptive-scope-auto-apply-label"
---
Run these checks after deployment to confirm the control is working as designed.


#### `Test-AdaptiveScopeAutoApplyLabel.ps1`

```powershell
#Requires -Version 7.0
<#
.SYNOPSIS
    Verifies the adaptive scope, the retention label, and (unless the label is a regulatory record)
    the auto-apply policy/rule exist and are configured as expected.

.DESCRIPTION
    Read-only - never modifies any object. Uses Security & Compliance PowerShell Get-* cmdlets to
    check, against the config file:
      1. The adaptive scope exists with the expected LocationType.
      2. The retention label exists with the expected RetentionAction/RetentionDuration/record flags.
      3. If the label is NOT a regulatory record: the policy exists, is enabled, and references the
         adaptive scope; the rule exists and applies the expected label.
      4. If the label IS a regulatory record: confirms no policy was created (matching the deploy
         script's documented skip) rather than treating its absence as a failure.
      5. (Informational, non-failing) A small adaptive-scope membership sample via
         Get-AdaptiveScopeMembers, so an operator can sanity-check "who does this actually cover."
    Exits non-zero on any hard failure (safe for a CI-style pre-flight). Safe to re-run.

    Connect first with Connect-IPPSSession. A View-Only role that can read retention/records/
    adaptive-scope configuration is sufficient.

.PARAMETER ConfigPath
    Path to the config to validate against. Defaults to
    '../deploy/config/adaptive-scope-auto-apply-label.sample.json'.

.PARAMETER SkipMembershipSample
    Skip the informational Get-AdaptiveScopeMembers call (useful for a fast, minimal-permission
    pre-flight, or if the scope is very large).

.EXAMPLE
    Connect-IPPSSession -AppId $AppId -Certificate $Cert -Organization 'contoso.onmicrosoft.com'
    ./Test-AdaptiveScopeAutoApplyLabel.ps1

.NOTES
    Grounded in Microsoft Learn:
    - Get-AdaptiveScope / Get-AdaptiveScopeMembers:
      https://learn.microsoft.com/powershell/module/exchangepowershell/get-adaptivescope
      https://learn.microsoft.com/powershell/module/exchangepowershell/get-adaptivescopemembers
    - Get-ComplianceTag / Get-RetentionCompliancePolicy / Get-RetentionComplianceRule:
      https://learn.microsoft.com/powershell/module/exchangepowershell/get-compliancetag
      https://learn.microsoft.com/powershell/module/exchangepowershell/get-retentioncompliancepolicy
      https://learn.microsoft.com/powershell/module/exchangepowershell/get-retentioncompliancerule
#>
[CmdletBinding()]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$ConfigPath = (Join-Path $PSScriptRoot '../deploy/config/adaptive-scope-auto-apply-label.sample.json'),

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

Write-Host "Validating adaptive-scope auto-apply label ('$($cfg.adaptiveScope.name)' / '$($cfg.label.name)')..." -ForegroundColor Cyan

# Adaptive scope
$scope = Get-AdaptiveScope -Identity $cfg.adaptiveScope.name -ErrorAction SilentlyContinue
Test-Check -Description "Adaptive scope '$($cfg.adaptiveScope.name)' exists" -Condition ($null -ne $scope)
if ($scope) {
    Test-Check -Description "  LocationType is '$($cfg.adaptiveScope.locationType)' (current: $($scope.LocationType))" `
        -Condition ("$($scope.LocationType)" -eq "$($cfg.adaptiveScope.locationType)")
}

# Retention label
$label = Get-ComplianceTag -Identity $cfg.label.name -ErrorAction SilentlyContinue
Test-Check -Description "Retention label '$($cfg.label.name)' exists" -Condition ($null -ne $label)
if ($label) {
    Test-Check -Description "  RetentionAction is '$($cfg.label.retentionAction)' (current: $($label.RetentionAction))" `
        -Condition ("$($label.RetentionAction)" -eq "$($cfg.label.retentionAction)")
    if ("$($cfg.label.retentionDurationDays)" -ne 'Unlimited') {
        Test-Check -Description "  RetentionDuration is $($cfg.label.retentionDurationDays) days (current: $($label.RetentionDuration))" `
            -Condition ("$($label.RetentionDuration)" -eq "$($cfg.label.retentionDurationDays)") -Warn
    }
    if ($cfg.label.regulatory) {
        Test-Check -Description "  Label is a regulatory record (current IsRecordLabel/Regulatory-derived state, informational)" -Condition $true -Warn
    }
    else {
        Test-Check -Description "  Label is a (non-regulatory) record label" -Condition ([bool]$label.IsRecordLabel) -Warn
    }
}

if ($cfg.label.regulatory) {
    Write-Host "`n  Label is configured as a REGULATORY RECORD - per design, no adaptive-scope policy/rule is expected to exist (Microsoft does not support auto-apply for regulatory records)." -ForegroundColor Cyan
    $policy = Get-RetentionCompliancePolicy -Identity $cfg.policy.name -ErrorAction SilentlyContinue
    Test-Check -Description "  Policy '$($cfg.policy.name)' correctly NOT created for a regulatory record" -Condition ($null -eq $policy) -Warn
    if ($policy) {
        Write-Host "  Unexpected: a policy exists for a regulatory-record config. Review manually - this combination is not Microsoft-supported for auto-apply." -ForegroundColor Red
    }
}
else {
    # Policy
    $policy = Get-RetentionCompliancePolicy -Identity $cfg.policy.name -ErrorAction SilentlyContinue
    Test-Check -Description "Auto-apply policy '$($cfg.policy.name)' exists" -Condition ($null -ne $policy)
    if ($policy) {
        Test-Check -Description "  Policy is enabled" -Condition ([bool]$policy.Enabled) -Warn
        $scopeLocations = @($policy.AdaptiveScopeLocation)
        Test-Check -Description "  Policy references adaptive scope '$($cfg.adaptiveScope.name)'" `
            -Condition ($scopeLocations -contains $cfg.adaptiveScope.name) -Warn
        if ($policy.DistributionStatus) { Write-Host "    Distribution status: $($policy.DistributionStatus)" -ForegroundColor Cyan }
    }

    # Rule
    $rule = Get-RetentionComplianceRule -Policy $cfg.policy.name -ErrorAction SilentlyContinue | Select-Object -First 1
    Test-Check -Description "Auto-apply rule exists on the policy" -Condition ($null -ne $rule)
    if ($rule) {
        Test-Check -Description "  Rule applies compliance tag '$($cfg.label.name)' (current: $($rule.ApplyComplianceTag))" `
            -Condition ("$($rule.ApplyComplianceTag)" -eq "$($cfg.label.name)")
    }
}

# Informational membership sample (never fails the run)
if (-not $SkipMembershipSample -and $scope) {
    try {
        # VERIFY: as in the adaptive-scope-retention sibling, the first returned element's result-
        # metadata property names aren't documented - printed generically rather than guessed.
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

Write-Host "`n  Note: two delays stack here - adaptive scope population (up to 5 days) and auto-apply distribution (up to 7 days). A newly-deployed config can validate 'exists' while genuinely covering zero content so far - confirm actual labeling in the portal (Records Management > File plan, or search for the label on content) before relying on this operationally." -ForegroundColor Cyan
Write-Host "$(if ($script:failures -eq 0) { 'All hard checks passed.' } else { "$script:failures hard check(s) failed." })" `
    -ForegroundColor $(if ($script:failures -eq 0) { 'Green' } else { 'Red' })
if ($script:failures -gt 0) { exit 1 }
```