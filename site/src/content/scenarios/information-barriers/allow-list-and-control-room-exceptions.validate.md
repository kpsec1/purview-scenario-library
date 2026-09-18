---
part: "validate"
parent: "information-barriers/allow-list-and-control-room-exceptions"
---
Run these checks after deployment to confirm the control is working as designed.


#### `Test-ControlRoomAllowException.ps1`

```powershell
#Requires -Version 7.0
<#
.SYNOPSIS
    Verifies the allow-list exception segments and policies exist, that each policy's
    SegmentsAllowed matches the config, and (optionally) that policies are Active; reports the
    latest policy-application status.

.DESCRIPTION
    Read-only - never modifies any object. Uses the Information Barriers Get-* cmdlets in Security &
    Compliance PowerShell to check, against the config file:
      1. Each configured prerequisite segment ('Trading'/'Research') exists.
      2. Each configured exception segment exists.
      3. Each expected allow policy exists, is assigned to the right segment, has a SegmentsAllowed
         set that exactly matches the config (order-independent), and (with -RequireActive) is Active.
      4. Reports the latest policy-application status (Get-InformationBarrierPoliciesApplicationStatus).
    Exits non-zero on any hard failure (safe for a CI-style pre-flight). Safe to re-run.

    Connect first with Connect-IPPSSession.

.PARAMETER ConfigPath
    Path to the config to validate against. Defaults to '../deploy/config/control-room-allow-exceptions.sample.json'.

.PARAMETER RequireActive
    Treat a non-Active policy as a hard FAIL (use after -Activate; omit while policies are still staged Inactive).

.EXAMPLE
    Connect-IPPSSession -AppId $AppId -Certificate $Cert -Organization 'contoso.onmicrosoft.com'
    ./Test-ControlRoomAllowException.ps1
#>
[CmdletBinding()]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$ConfigPath = (Join-Path $PSScriptRoot '../deploy/config/control-room-allow-exceptions.sample.json'),

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
function Test-SegmentSetEqual {
    param([string[]]$Live, [string[]]$Desired)
    $liveSet = @($Live | ForEach-Object { "$_".Trim() } | Where-Object { $_ } | Sort-Object -Unique)
    $desiredSet = @($Desired | ForEach-Object { "$_".Trim() } | Where-Object { $_ } | Sort-Object -Unique)
    return -not (Compare-Object $liveSet $desiredSet -CaseSensitive:$false)
}

if (-not (Get-Command Get-OrganizationSegment -ErrorAction SilentlyContinue)) {
    throw "Information Barriers cmdlets not found. Connect first: Connect-IPPSSession. See docs/automation-surface.md Section 3."
}
if (-not (Test-Path -LiteralPath $ConfigPath)) { throw "Config file not found: $ConfigPath" }
$cfg = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json

Write-Host "Validating allow-list information-barrier exceptions..." -ForegroundColor Cyan

try {
    $policyConfig = Get-PolicyConfig -ErrorAction Stop
    $ibMode = if ($policyConfig.PSObject.Properties['InformationBarrierMode']) { "$($policyConfig.InformationBarrierMode)" } else { $null }
    Test-Check -Description "Tenant IB mode is NOT 'Legacy' (current: $(if ($ibMode) { $ibMode } else { 'unknown' })) - Legacy mode hides non-IB users/groups from an Allow-policy segment's members" `
        -Condition ($ibMode -and $ibMode -ne 'Legacy') -Warn
}
catch {
    Write-Host "  [WARN] Could not read tenant IB mode via Get-PolicyConfig: $($_.Exception.Message)" -ForegroundColor Yellow
}

$segments = Get-OrganizationSegment -ErrorAction SilentlyContinue

foreach ($reqName in @($cfg.prerequisiteSegments)) {
    $s = $segments | Where-Object { $_.Name -eq $reqName } | Select-Object -First 1
    Test-Check -Description "Prerequisite segment '$reqName' exists (from segregate-trading-and-research)" -Condition ($null -ne $s)
}

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
foreach ($pair in @($cfg.allowPolicies)) {
    $allows = @($pair.allows)
    $polName = "$($pair.assignedSegment)-allow-$($allows -join '-')"
    $pol = $policies | Where-Object { $_.Name -eq $polName } | Select-Object -First 1
    Test-Check -Description "Allow policy '$polName' exists" -Condition ($null -ne $pol)
    if ($pol) {
        Test-Check -Description "  '$polName' is assigned to segment '$($pair.assignedSegment)'" `
            -Condition ("$($pol.AssignedSegment)" -eq "$($pair.assignedSegment)") -Warn
        $liveAllowed = @($pol.SegmentsAllowed)
        Test-Check -Description "  '$polName' SegmentsAllowed matches config (live: [$($liveAllowed -join ', ')], desired: [$($allows -join ', ')])" `
            -Condition (Test-SegmentSetEqual -Live $liveAllowed -Desired $allows)
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

Write-Host "`n  Note: after activation+application, allow ~30 min to start (~5,000 users/hour) and up to 24h for SharePoint/OneDrive propagation. Confirm real access in Teams: a ComplianceControlRoom user should reach both a Trading and a Research user; a Legal user should reach Research but NOT Trading." -ForegroundColor Cyan
Write-Host "$(if ($script:failures -eq 0) { 'All hard checks passed.' } else { "$script:failures hard check(s) failed." })" `
    -ForegroundColor $(if ($script:failures -eq 0) { 'Green' } else { 'Red' })
if ($script:failures -gt 0) { exit 1 }
```