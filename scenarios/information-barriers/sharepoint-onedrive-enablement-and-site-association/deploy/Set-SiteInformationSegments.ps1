#Requires -Version 7.0
<#
.SYNOPSIS
    Associates (or, with -RemoveConfigured, removes) Information Barrier segments on specific
    SharePoint sites, from a JSON config.

.DESCRIPTION
    A SharePoint site only gets Explicit-mode IB coverage when a SharePoint Administrator
    associates one or more segments with it (Set-SPOSite -AddInformationSegment). This is the
    manual, per-site half of the SharePoint/OneDrive IB story - Teams-connected sites are handled
    automatically (Implicit mode, segments follow the connected Microsoft 365 group's membership),
    and a segmented user's own OneDrive protects itself automatically (Explicit mode within 24
    hours of enablement) - neither needs this script. Use this for standalone SharePoint sites
    (document libraries, portals) that aren't Teams-connected and need the same wall.

    For each site in the config:
      1. Resolves each configured segment NAME to its GUID via Get-OrganizationSegment (Security &
         Compliance PowerShell - surface 2; this script needs BOTH surface 2 and surface 5
         sessions connected).
      2. Reads the site's current segments (Get-SPOSite -Identity <url> | Select
         InformationSegment).
      3. Default mode: associates any configured segment not already present
         (Set-SPOSite -AddInformationSegment) - additive, create-or-report, never removes a
         segment the config didn't mention.
      4. -RemoveConfigured: removes exactly the segments THIS config lists from each site
         (Set-SPOSite -RemoveInformationSegment) - the rollback path. Does not touch segments the
         config never mentioned.

    Associating an incompatible segment pair (segments an active IB block policy keeps apart) on
    the same site is rejected by Set-SPOSite with an error - this script surfaces that error
    per-site and continues with the remaining sites rather than aborting the whole run.

    Idempotent and safe to re-run. -WhatIf is non-functional on Set-SPOSite in the SharePoint
    Online Management Shell, so this script implements -DryRun.

    Connect first: Connect-SPOService (surface 5) AND Connect-IPPSSession (surface 2), both
    certificate app-only preferred - docs/automation-surface.md Section 3. This script does not
    open either session. Surface 5 requires a Windows runner/console.

.PARAMETER ConfigPath
    Path to the JSON config. Defaults to 'config/sharepoint-site-segments.sample.json'.

.PARAMETER RemoveConfigured
    Remove (instead of add) exactly the segments this config lists from each site.

.PARAMETER DryRun
    Print every intended Set-SPOSite call and run none.

.EXAMPLE
    Connect-IPPSSession -AppId $AppId -Certificate $Cert -Organization 'contoso.onmicrosoft.com'
    Connect-SPOService -Url https://contoso-admin.sharepoint.com -ClientId $AppId -Certificate $Cert
    ./Set-SiteInformationSegments.ps1 -ConfigPath ./config/sharepoint-site-segments.json -DryRun

.EXAMPLE
    ./Set-SiteInformationSegments.ps1 -ConfigPath ./config/sharepoint-site-segments.json                    # associate
    ./Set-SiteInformationSegments.ps1 -ConfigPath ./config/sharepoint-site-segments.json -RemoveConfigured   # roll back

.NOTES
    Grounded in Microsoft Learn (verify before production use):
    - Use Information Barriers with SharePoint - Example scenario / View and manage segments as an
      administrator (Get-OrganizationSegment | ft Name, EXOSegmentID; Set-SPOSite
      -AddInformationSegment/-RemoveInformationSegment <GUID>; Get-SPOSite | Select
      InformationSegment; up to 100 compatible segments per site; adding a segment sets the site's
      IB mode to Explicit, removing the last one reverts it to Open):
      https://learn.microsoft.com/purview/information-barriers-sharepoint#view-and-manage-segments-as-an-administrator
    - Set-SPOSite reference (-InformationBarriersMode):
      https://learn.microsoft.com/powershell/module/microsoft.online.sharepoint.powershell/set-sposite

    VERIFY (pilot tenant): Microsoft's own worked example resolves a segment's identifier via
    `Get-OrganizationSegment | ft Name, EXOSegmentID` (Security & Compliance PowerShell) for use
    with Set-SPOSite -AddInformationSegment, while segregate-trading-and-research's own scripts
    address the same Get-OrganizationSegment objects by a `.Guid` property (for
    Set-InformationBarrierPolicy -Identity / Remove-OrganizationSegment -Identity, i.e. within
    Security & Compliance PowerShell itself). This script resolves the segment identifier by
    trying `EXOSegmentId` first (matching the SharePoint-association worked example verbatim) and
    falling back to `Guid` if absent, rather than assuming one property name - confirm against a
    pilot tenant which property Get-OrganizationSegment actually exposes (they may be the same
    underlying value under two aliases, or the SharePoint doc's example table header may be
    describing display formatting rather than a real property name). README.md Section 11 and
    design.md Section 5.
#>
[CmdletBinding()]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$ConfigPath = (Join-Path $PSScriptRoot 'config/sharepoint-site-segments.sample.json'),

    [Parameter()]
    [switch]$RemoveConfigured,

    [Parameter()]
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

if (-not (Get-Command Get-SPOSite -ErrorAction SilentlyContinue)) {
    throw "SharePoint Online Management Shell cmdlets not found. Connect first: Connect-SPOService. See docs/automation-surface.md Section 3/6."
}
if (-not (Get-Command Get-OrganizationSegment -ErrorAction SilentlyContinue)) {
    throw "Information Barriers cmdlets not found. Connect first: Connect-IPPSSession (Security & Compliance PowerShell). See docs/automation-surface.md Section 3."
}
if (-not (Test-Path -LiteralPath $ConfigPath)) { throw "Config file not found: $ConfigPath" }
$cfg = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
if (-not $cfg.sites -or @($cfg.sites).Count -lt 1) { throw "Config needs at least one site." }

function Get-SegmentGuid {
    param([Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)]$AllSegments)
    $seg = $AllSegments | Where-Object { $_.Name -eq $Name } | Select-Object -First 1
    if (-not $seg) { return $null }
    if ($seg.PSObject.Properties['EXOSegmentId']) { return "$($seg.EXOSegmentId)" }
    if ($seg.PSObject.Properties['Guid']) { return "$($seg.Guid)" }
    return $null
}

$action = if ($RemoveConfigured) { 'remove' } else { 'associate' }
Write-Host "Reconciling SharePoint site information-segment associations ($action) from '$ConfigPath'." -ForegroundColor Cyan

$allSegments = Get-OrganizationSegment -ErrorAction SilentlyContinue
$failures = 0

foreach ($site in @($cfg.sites)) {
    if (-not $site.url -or -not $site.segments -or @($site.segments).Count -lt 1) {
        Write-Host "  [skip] Site entry missing url or segments." -ForegroundColor DarkYellow
        continue
    }
    Write-Host "Site: $($site.url)" -ForegroundColor Cyan

    $current = $null
    try {
        $spoSite = Get-SPOSite -Identity $site.url -ErrorAction Stop
        $current = @($spoSite.InformationSegment)
    }
    catch {
        Write-Host "  [FAIL] Could not read site '$($site.url)': $($_.Exception.Message)" -ForegroundColor Red
        $failures++
        continue
    }

    foreach ($segName in @($site.segments)) {
        $segGuid = Get-SegmentGuid -Name $segName -AllSegments $allSegments
        if (-not $segGuid) {
            Write-Host "  [FAIL] Segment '$segName' not found (create it first - segregate-trading-and-research/deploy/New-TradingResearchBarrier.ps1)." -ForegroundColor Red
            $failures++
            continue
        }

        $alreadyPresent = $current -contains $segGuid
        if (-not $RemoveConfigured) {
            if ($alreadyPresent) {
                Write-Host "  [segment] '$segName' already associated." -ForegroundColor DarkGreen
                continue
            }
            $describe = "Set-SPOSite -Identity '$($site.url)' -AddInformationSegment $segGuid   # '$segName'"
            if ($DryRun) { Write-Host "  DRYRUN would run: $describe" -ForegroundColor DarkYellow; continue }
            try {
                Write-Host "  $describe" -ForegroundColor Green
                Set-SPOSite -Identity $site.url -AddInformationSegment $segGuid -ErrorAction Stop
                Write-Host "  [added] '$segName' -> site now Explicit mode (or stays Explicit)." -ForegroundColor Green
            }
            catch {
                Write-Host "  [FAIL] Could not add '$segName' (likely an incompatible-segment rejection - confirm no active block policy conflicts): $($_.Exception.Message)" -ForegroundColor Red
                $failures++
            }
        }
        else {
            if (-not $alreadyPresent) {
                Write-Host "  [segment] '$segName' not currently associated - nothing to remove." -ForegroundColor DarkGray
                continue
            }
            $describe = "Set-SPOSite -Identity '$($site.url)' -RemoveInformationSegment $segGuid   # '$segName'"
            if ($DryRun) { Write-Host "  DRYRUN would run: $describe" -ForegroundColor DarkYellow; continue }
            try {
                Write-Host "  $describe" -ForegroundColor Yellow
                Set-SPOSite -Identity $site.url -RemoveInformationSegment $segGuid -ErrorAction Stop
                Write-Host "  [removed] '$segName' (site reverts to Open if this was its last segment)." -ForegroundColor Yellow
            }
            catch {
                Write-Host "  [FAIL] Could not remove '$segName': $($_.Exception.Message)" -ForegroundColor Red
                $failures++
            }
        }
    }
}

Write-Host "`nDone." -ForegroundColor Cyan
Write-Host "Validate with validate/Test-SharePointOneDriveInformationBarrierSetup.ps1." -ForegroundColor Yellow
if ($failures -gt 0) {
    Write-Host "$failures failure(s) - review the [FAIL] lines above." -ForegroundColor Red
    exit 1
}
