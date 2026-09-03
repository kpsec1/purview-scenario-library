#Requires -Version 7.0
<#
.SYNOPSIS
    Verifies the scriptable subset of the code-of-conduct Communication Compliance policy exists and
    is configured as expected, and prints a manual checklist for the portal-only pieces (trainable
    classifiers, locations) this scenario cannot read via cmdlet.

.DESCRIPTION
    Read-only - never modifies any object. Uses Get-SupervisoryReviewPolicyV2 and
    Get-SupervisoryReviewRule (Security & Compliance PowerShell) to check:
      1. The policy exists.
      2. It is enabled.
      3. It has at least one reviewer assigned.
      4. Its keyword rule exists and carries a Condition and a sampling rate.
    Exits non-zero on any hard failure (safe for a CI-style pre-flight). Safe to re-run.

    Because Microsoft doesn't expose the trainable classifiers (Targeted harassment/Threat/
    Discrimination) or location selection through the documented cmdlet surface, those are printed as
    a MANUAL verification checklist rather than asserted - see README.md Sections 5, 7, and 11.

    Connect first with Connect-IPPSSession. A Communication Compliance Admins (or read-capable
    compliance) role is sufficient for the Get-* calls.

.PARAMETER ConfigPath
    Path to the JSON config to validate against. Defaults to
    '../deploy/config/code-of-conduct.sample.json'.

.EXAMPLE
    Connect-IPPSSession -AppId $AppId -Certificate $Cert -Organization 'contoso.onmicrosoft.com'
    ./Test-CodeOfConductPolicy.ps1
#>
[CmdletBinding()]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$ConfigPath = (Join-Path $PSScriptRoot '../deploy/config/code-of-conduct.sample.json')
)

$ErrorActionPreference = 'Stop'
$script:failures = 0

function Test-Check {
    param([string]$Description, [bool]$Condition, [switch]$Warn)
    if ($Condition) { Write-Host "  [PASS] $Description" -ForegroundColor Green }
    elseif ($Warn) { Write-Host "  [WARN] $Description" -ForegroundColor Yellow }
    else { Write-Host "  [FAIL] $Description" -ForegroundColor Red; $script:failures++ }
}

if (-not (Get-Command Get-SupervisoryReviewPolicyV2 -ErrorAction SilentlyContinue)) {
    throw "SupervisoryReview cmdlets not found. Connect first: Connect-IPPSSession. See docs/automation-surface.md Section 3."
}
if (-not (Test-Path -LiteralPath $ConfigPath)) { throw "Config file not found: $ConfigPath" }
$cfg = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
if (-not $cfg.policyName) { throw "Config is missing 'policyName'." }
$policyName = $cfg.policyName
$ruleName = "$policyName - Keyword Rule"

Write-Host "Validating Communication Compliance policy '$policyName'..." -ForegroundColor Cyan

$policy = Get-SupervisoryReviewPolicyV2 -Identity $policyName -ErrorAction SilentlyContinue
Test-Check -Description "Policy '$policyName' exists" -Condition ($null -ne $policy)
if (-not $policy) {
    Write-Host "`nCannot continue - policy not found. $script:failures check(s) failed." -ForegroundColor Red
    exit 1
}

# Enabled state - property name can be Enabled or IsEnabled depending on the object shape; check both.
$isEnabled = $false
if ($null -ne $policy.Enabled) { $isEnabled = [bool]$policy.Enabled }
elseif ($null -ne $policy.IsEnabled) { $isEnabled = [bool]$policy.IsEnabled }
Test-Check -Description "Policy is enabled" -Condition $isEnabled -Warn

$reviewers = @($policy.Reviewers)
Test-Check -Description "Policy has at least one reviewer assigned" -Condition ($reviewers.Count -gt 0)

$rule = Get-SupervisoryReviewRule -Policy $policyName -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -eq $ruleName } | Select-Object -First 1
Test-Check -Description "Keyword rule '$ruleName' exists" -Condition ($null -ne $rule)
if ($rule) {
    Test-Check -Description "Rule has a Condition set" -Condition (-not [string]::IsNullOrWhiteSpace([string]$rule.Condition))
    Test-Check -Description "Rule has a sampling rate set" -Condition ($null -ne $rule.SamplingRate)
    if ($null -ne $rule.SamplingRate) {
        Write-Host "    Sampling rate: $($rule.SamplingRate)%" -ForegroundColor Cyan
    }
}

Write-Host "`n  Manual checklist (portal-only - not readable via cmdlet, see README.md Sections 5/11):" -ForegroundColor Cyan
Write-Host "   [ ] Trainable classifiers added to the policy: Targeted harassment, Threat, Discrimination" -ForegroundColor Cyan
Write-Host "   [ ] Locations selected: Exchange Online, Microsoft Teams, Viva Engage" -ForegroundColor Cyan
Write-Host "   [ ] 'Filter email blasts' enabled (reduce bulk-sender false positives)" -ForegroundColor Cyan
Write-Host "   [ ] Reviewers are members of Communication Compliance Analysts/Investigators and have Exchange Online mailboxes" -ForegroundColor Cyan
Write-Host "   [ ] User-name pseudonymization left ON (unless HR/Legal explicitly decided otherwise)" -ForegroundColor Cyan

Write-Host "`n$(if ($script:failures -eq 0) { 'All hard checks passed.' } else { "$script:failures hard check(s) failed." })" `
    -ForegroundColor $(if ($script:failures -eq 0) { 'Green' } else { 'Red' })
if ($script:failures -gt 0) { exit 1 }
