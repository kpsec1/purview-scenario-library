#Requires -Version 7.0
<#
.SYNOPSIS
    Enables (or, with -Suspend, temporarily suspends) Microsoft Purview Information Barriers for
    SharePoint and OneDrive at the tenant level.

.DESCRIPTION
    Uses the SharePoint Online Management Shell (automation surface 5 per
    docs/automation-surface.md) to flip the single tenant-wide switch that turns on IB enforcement
    for SharePoint sites and OneDrive:
      Set-SPOTenant -InformationBarriersSuspension $false   (enable)
      Set-SPOTenant -InformationBarriersSuspension $true    (-Suspend: temporarily turn off)

    SharePoint and OneDrive Information Barriers are enabled or suspended together as a SINGLE
    action - Microsoft does not support enabling one without the other. Enabling this switch is
    what makes segregate-trading-and-research's Teams "ethical wall" also cover SharePoint file
    access/sharing and OneDrive - without it, IB only blocks Teams chat/calls/membership; the
    file-collaboration surface stays open (README.md Section 2, design.md Section 3).

    PREREQUISITE: the org's Information Barriers segments and block policies (this scenario
    assumes segregate-trading-and-research's Trading/Research segments) must already be created,
    set Active, applied, and given up to 24 hours to propagate BEFORE you enable this switch -
    Microsoft states this ordering explicitly. Running this script first, against a tenant with no
    active IB policies yet, enables the switch but has nothing to enforce.

    Idempotent: reads the current InformationBarriersSuspension value first (VERIFY below) and
    only calls Set-SPOTenant when a change is actually needed. -WhatIf is non-functional on
    Set-SPOTenant in the SharePoint Online Management Shell, so this script implements -DryRun.

    Connect first: Connect-SPOService -Url https://<tenant>-admin.sharepoint.com (certificate
    app-only preferred - docs/automation-surface.md Section 3). This script does not open the
    session. Surface 5 requires a Windows runner/console - docs/automation-surface.md Section 6.

.PARAMETER Suspend
    Temporarily suspend Information Barriers enforcement on SharePoint and OneDrive tenant-wide
    (sets InformationBarriersSuspension to $true) instead of enabling it. Omit to enable.

.PARAMETER DryRun
    Print the intended Set-SPOTenant call and run none.

.EXAMPLE
    Connect-SPOService -Url https://contoso-admin.sharepoint.com -ClientId $AppId -Certificate $Cert
    ./Set-SharePointOneDriveIBEnablement.ps1 -DryRun

.EXAMPLE
    ./Set-SharePointOneDriveIBEnablement.ps1            # enable (after IB policies are active+applied+propagated)
    ./Set-SharePointOneDriveIBEnablement.ps1 -Suspend    # temporarily suspend (rollback.md Stage 1b)

.NOTES
    Grounded in Microsoft Learn (verify before production use):
    - Use Information Barriers with SharePoint - Enable SharePoint and OneDrive Information
      Barriers in your organization (Set-SPOTenant -InformationBarriersSuspension, ~1 hour to take
      effect, single action for both services, 24h-propagated-policies prerequisite):
      https://learn.microsoft.com/purview/information-barriers-sharepoint#enable-sharepoint-and-onedrive-information-barriers-in-your-organization
    - Set-SPOTenant reference (-InformationBarriersSuspension, -IBImplicitGroupBased,
      -AppBypassInformationBarriers, -DefaultOneDriveInformationBarrierMode parameters):
      https://learn.microsoft.com/powershell/module/microsoft.online.sharepoint.powershell/set-spotenant

    VERIFY (pilot tenant, before relying on the idempotency check): Get-SPOTenant's own reference
    page states only that it returns "organization-level site collection properties such as
    StorageQuota, StorageQuotaAllocated, ResourceQuota, ResourceQuotaAllocated and
    SiteCreationMode" and documents no parameters - it does not explicitly confirm
    InformationBarriersSuspension is present on the returned object, the way Set-SPOTenant
    documents it as a settable parameter. This script reads it defensively (falls through to
    "unknown, will attempt Set-SPOTenant" if the property is absent) rather than assuming it's
    there. See README.md Section 11.
#>
[CmdletBinding()]
param(
    [Parameter()]
    [switch]$Suspend,

    [Parameter()]
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

if (-not (Get-Command Get-SPOTenant -ErrorAction SilentlyContinue)) {
    throw "SharePoint Online Management Shell cmdlets not found. Connect first: Connect-SPOService -Url https://<tenant>-admin.sharepoint.com. See docs/automation-surface.md Section 3/6 (Windows PowerShell 5.1-native module; PS7 needs -UseWindowsPowerShell)."
}

$desiredSuspension = [bool]$Suspend
$action = if ($Suspend) { 'suspend' } else { 'enable' }
Write-Host "Requested: $action Information Barriers for SharePoint and OneDrive (tenant-wide)." -ForegroundColor Cyan

if (-not $Suspend) {
    Write-Host "Reminder: this enables enforcement for BOTH SharePoint and OneDrive together and takes ~1 hour to take effect. Confirm the org's IB segments/policies are already Active and applied (24h propagated) before proceeding - README.md Section 3/5." -ForegroundColor Yellow
}
else {
    Write-Host "WARNING: suspending drops IB enforcement for ALL SharePoint sites and ALL OneDrive accounts tenant-wide - including Teams-connected (Implicit mode) sites that back the segregate-trading-and-research Teams wall's file surface. Prefer removing specific site associations (Set-SiteInformationSegments.ps1 -RemoveConfigured) over a full suspend unless you are decommissioning this scenario entirely. See rollback.md." -ForegroundColor Red
}

$currentSuspension = $null
try {
    $tenant = Get-SPOTenant -ErrorAction Stop
    if ($null -ne $tenant.PSObject.Properties['InformationBarriersSuspension']) {
        $currentSuspension = [bool]$tenant.InformationBarriersSuspension
    }
}
catch {
    Write-Host "  [WARN] Could not read current tenant state via Get-SPOTenant: $($_.Exception.Message)" -ForegroundColor Yellow
}

if ($null -ne $currentSuspension) {
    Write-Host "  Current InformationBarriersSuspension: $currentSuspension" -ForegroundColor DarkCyan
    if ($currentSuspension -eq $desiredSuspension) {
        Write-Host "  [no-op] Already in the desired state ($action). Nothing to change." -ForegroundColor DarkGreen
        Write-Host "`nDone." -ForegroundColor Cyan
        return
    }
}
else {
    Write-Host "  Current state unknown (property not present on Get-SPOTenant output in this session - see .NOTES VERIFY). Proceeding to set it explicitly." -ForegroundColor Yellow
}

$describe = "Set-SPOTenant -InformationBarriersSuspension `$$desiredSuspension"
if ($DryRun) {
    Write-Host "  DRYRUN would run: $describe" -ForegroundColor DarkYellow
}
else {
    Write-Host "  $describe" -ForegroundColor Green
    Set-SPOTenant -InformationBarriersSuspension $desiredSuspension
    Write-Host "  [$action] Information Barriers for SharePoint/OneDrive set. Allow ~1 hour to take effect tenant-wide." -ForegroundColor Green
}

Write-Host "`nDone." -ForegroundColor Cyan
if (-not $DryRun -and -not $Suspend) {
    Write-Host "Next: associate segments with any standalone (non-Teams-connected) sites that need Explicit-mode IB coverage - deploy/Set-SiteInformationSegments.ps1. Teams-connected sites and segmented users' OneDrive protect themselves automatically within 24h. Validate with validate/Test-SharePointOneDriveInformationBarrierSetup.ps1." -ForegroundColor Yellow
}
