---
part: "validate"
parent: "information-barriers/sharepoint-onedrive-enablement-and-site-association"
---
Run these checks after deployment to confirm the control is working as designed.


#### `Test-SharePointOneDriveInformationBarrierSetup.ps1`

```powershell
#Requires -Version 7.0
<#
.SYNOPSIS
    Verifies SharePoint/OneDrive Information Barriers enablement and the configured sites'
    segment associations. Read-only.

.DESCRIPTION
    Uses SharePoint Online Management Shell (surface 5) and Security & Compliance PowerShell
    (surface 2) Get-* cmdlets only - never modifies any object. Checks, against the config file:
      1. Tenant-wide InformationBarriersSuspension is $false (IB for SharePoint/OneDrive enabled).
      2. Each configured site exists, is in Explicit mode, and has every configured segment
         associated.
      3. Reports each configured segment's resolved GUID and whether it was found via
         EXOSegmentId or the Guid property fallback (see deploy script .NOTES VERIFY).
    Exits non-zero on any hard failure (safe for a CI-style pre-flight). Safe to re-run.

    Connect first: Connect-SPOService AND Connect-IPPSSession.

.PARAMETER ConfigPath
    Path to the config to validate against. Defaults to
    '../deploy/config/sharepoint-site-segments.sample.json'.

.PARAMETER AllowSuspended
    Treat InformationBarriersSuspension = $true as a WARN instead of a hard FAIL (use while
    deliberately validating during a temporary suspension - rollback.md Stage 1b).

.EXAMPLE
    Connect-SPOService -Url https://contoso-admin.sharepoint.com -ClientId $AppId -Certificate $Cert
    Connect-IPPSSession -AppId $AppId -Certificate $Cert -Organization 'contoso.onmicrosoft.com'
    ./Test-SharePointOneDriveInformationBarrierSetup.ps1
#>
[CmdletBinding()]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$ConfigPath = (Join-Path $PSScriptRoot '../deploy/config/sharepoint-site-segments.sample.json'),

    [Parameter()]
    [switch]$AllowSuspended
)

$ErrorActionPreference = 'Stop'
$script:failures = 0
function Test-Check {
    param([string]$Description, [bool]$Condition, [switch]$Warn)
    if ($Condition) { Write-Host "  [PASS] $Description" -ForegroundColor Green }
    elseif ($Warn) { Write-Host "  [WARN] $Description" -ForegroundColor Yellow }
    else { Write-Host "  [FAIL] $Description" -ForegroundColor Red; $script:failures++ }
}

if (-not (Get-Command Get-SPOSite -ErrorAction SilentlyContinue)) {
    throw "SharePoint Online Management Shell cmdlets not found. Connect first: Connect-SPOService. See docs/automation-surface.md Section 3/6."
}
if (-not (Get-Command Get-OrganizationSegment -ErrorAction SilentlyContinue)) {
    throw "Information Barriers cmdlets not found. Connect first: Connect-IPPSSession. See docs/automation-surface.md Section 3."
}
if (-not (Test-Path -LiteralPath $ConfigPath)) { throw "Config file not found: $ConfigPath" }
$cfg = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json

Write-Host "Validating SharePoint/OneDrive Information Barriers enablement and site segments..." -ForegroundColor Cyan

# --- 1. Tenant-wide enablement ---
try {
    $tenant = Get-SPOTenant -ErrorAction Stop
    if ($null -ne $tenant.PSObject.Properties['InformationBarriersSuspension']) {
        $suspended = [bool]$tenant.InformationBarriersSuspension
        Test-Check -Description "Tenant-wide IB for SharePoint/OneDrive is enabled (InformationBarriersSuspension = `$false)" `
            -Condition (-not $suspended) -Warn:$AllowSuspended
    }
    else {
        Write-Host "  [WARN] Get-SPOTenant did not expose InformationBarriersSuspension in this session - can't confirm tenant-wide enablement here. See deploy script .NOTES VERIFY." -ForegroundColor Yellow
    }
}
catch {
    Write-Host "  [WARN] Could not read tenant state via Get-SPOTenant: $($_.Exception.Message)" -ForegroundColor Yellow
}

# --- 2. Per-site segment associations ---
$allSegments = Get-OrganizationSegment -ErrorAction SilentlyContinue
foreach ($site in @($cfg.sites)) {
    if (-not $site.url) { continue }
    Write-Host "Site: $($site.url)" -ForegroundColor Cyan
    try {
        $spoSite = Get-SPOSite -Identity $site.url -ErrorAction Stop
    }
    catch {
        Test-Check -Description "Site '$($site.url)' is reachable via Get-SPOSite" -Condition $false
        continue
    }
    $current = @($spoSite.InformationSegment)
    Test-Check -Description "  IB mode is Explicit (current: $($spoSite.InformationBarriersMode))" `
        -Condition ("$($spoSite.InformationBarriersMode)" -eq 'Explicit') -Warn

    foreach ($segName in @($site.segments)) {
        $seg = $allSegments | Where-Object { $_.Name -eq $segName } | Select-Object -First 1
        if (-not $seg) {
            Test-Check -Description "  Segment '$segName' exists (Get-OrganizationSegment)" -Condition $false
            continue
        }
        $segGuid = if ($seg.PSObject.Properties['EXOSegmentId']) { "$($seg.EXOSegmentId)" } elseif ($seg.PSObject.Properties['Guid']) { "$($seg.Guid)" } else { $null }
        $resolvedVia = if ($seg.PSObject.Properties['EXOSegmentId']) { 'EXOSegmentId' } elseif ($seg.PSObject.Properties['Guid']) { 'Guid (fallback)' } else { 'none' }
        Write-Host "    resolved '$segName' -> $segGuid (via $resolvedVia)" -ForegroundColor DarkCyan
        Test-Check -Description "  Segment '$segName' is associated with the site" -Condition ($null -ne $segGuid -and $current -contains $segGuid)
    }
}

Write-Host "`n  Note: enabling the tenant switch takes ~1 hour to take effect; site associations you just made are immediate in Get-SPOSite but propagation to actual access/sharing enforcement can lag. Teams-connected (Implicit mode) sites and segmented users' OneDrive aren't covered by this config - they self-associate within 24h of enablement and aren't independently checked here." -ForegroundColor Cyan
Write-Host "$(if ($script:failures -eq 0) { 'All hard checks passed.' } else { "$script:failures hard check(s) failed." })" `
    -ForegroundColor $(if ($script:failures -eq 0) { 'Green' } else { 'Red' })
if ($script:failures -gt 0) { exit 1 }
```