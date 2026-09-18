---
part: "validate"
parent: "information-barriers/segregate-trading-and-research"
---
Run these checks after deployment to confirm the control is working as designed.


#### `Test-TradingResearchBarrier.ps1`

```powershell
#Requires -Version 7.0
<#
.SYNOPSIS
    Verifies the Trading/Research information-barrier segments and block policies exist and
    (optionally) are active, and reports the policy-application status.

.DESCRIPTION
    Read-only - never modifies any object. Uses the Information Barriers Get-* cmdlets in Security &
    Compliance PowerShell to check, against the config file:
      1. Each configured segment exists.
      2. Each expected one-way block policy exists, blocks the right segment, and (with
         -RequireActive) is Active.
      3. Reports the latest policy-application status (Get-InformationBarrierPoliciesApplicationStatus).
    Exits non-zero on any hard failure (safe for a CI-style pre-flight). Safe to re-run.

    Connect first with Connect-IPPSSession.

.PARAMETER ConfigPath
    Path to the config to validate against. Defaults to '../deploy/config/trading-research-barrier.sample.json'.

.PARAMETER RequireActive
    Treat a non-Active policy as a hard FAIL (use after -Activate; omit while policies are still staged Inactive).

.EXAMPLE
    Connect-IPPSSession -AppId $AppId -Certificate $Cert -Organization 'contoso.onmicrosoft.com'
    ./Test-TradingResearchBarrier.ps1
#>
[CmdletBinding()]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$ConfigPath = (Join-Path $PSScriptRoot '../deploy/config/trading-research-barrier.sample.json'),

    [Parameter()]
    [switch]$RequireActive
)

$ErrorActionPreference = 'Stop'
$script:failures = 0
function Test-Check {
    param([string]$Description, [bool]$Condition, [switch]$Warn)
    if ($Condition) { Write-Host "  [PASS] $Description" -ForegroundColor Green }
    elseif ($Warn) { Write-Host "  [WARN] $Description" -ForegroundColor Yellow }
    else { Write-Host "  [FAIL] $Description" -ForegroundColor Red; $script:failures++ }
}

if (-not (Get-Command Get-OrganizationSegment -ErrorAction SilentlyContinue)) {
    throw "Information Barriers cmdlets not found. Connect first: Connect-IPPSSession. See docs/automation-surface.md Section 3."
}
if (-not (Test-Path -LiteralPath $ConfigPath)) { throw "Config file not found: $ConfigPath" }
$cfg = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json

Write-Host "Validating Trading/Research information-barrier wall..." -ForegroundColor Cyan

$segments = Get-OrganizationSegment -ErrorAction SilentlyContinue
foreach ($seg in @($cfg.segments)) {
    $s = $segments | Where-Object { $_.Name -eq $seg.name } | Select-Object -First 1
    Test-Check -Description "Segment '$($seg.name)' exists" -Condition ($null -ne $s)
    if ($s -and $seg.userGroupFilter) {
        $liveFilter = ("$($s.UserGroupFilter)" -replace '\s', '')
        $cfgFilter = ("$($seg.userGroupFilter)" -replace '\s', '')
        Test-Check -Description "  '$($seg.name)' filter matches config" -Condition ($liveFilter -eq $cfgFilter) -Warn
    }
}

$policies = Get-InformationBarrierPolicy -ErrorAction SilentlyContinue
foreach ($pair in @($cfg.blockPairs)) {
    $polName = "$($pair.assignedSegment)-block-$($pair.blocks)"
    $pol = $policies | Where-Object { $_.Name -eq $polName } | Select-Object -First 1
    Test-Check -Description "Block policy '$polName' exists" -Condition ($null -ne $pol)
    if ($pol) {
        Test-Check -Description "  '$polName' is assigned to segment '$($pair.assignedSegment)'" `
            -Condition ("$($pol.AssignedSegment)" -eq "$($pair.assignedSegment)") -Warn
        Test-Check -Description "  '$polName' state is Active (current: $($pol.State))" `
            -Condition ("$($pol.State)" -eq 'Active') -Warn:(-not $RequireActive)
    }
}

# Application status
try {
    $status = Get-InformationBarrierPoliciesApplicationStatus -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($status) { Write-Host "  Latest policy application: $($status.Status) (started $($status.CreatedDateTime))" -ForegroundColor Cyan }
    else { Write-Host "  [WARN] No policy-application run found yet - run New-...ps1 -Activate (or Start-InformationBarrierPoliciesApplication) to apply." -ForegroundColor Yellow }
}
catch {
    Write-Host "  [WARN] Could not read policy-application status: $($_.Exception.Message)" -ForegroundColor Yellow
}

Write-Host "`n  Note: after activation+application, allow ~30 min to start (~5,000 users/hour) and up to 24h for SharePoint/OneDrive propagation. Confirm real blocking in Teams between a Trading and a Research user." -ForegroundColor Cyan
Write-Host "$(if ($script:failures -eq 0) { 'All hard checks passed.' } else { "$script:failures hard check(s) failed." })" `
    -ForegroundColor $(if ($script:failures -eq 0) { 'Green' } else { 'Red' })
if ($script:failures -gt 0) { exit 1 }
```