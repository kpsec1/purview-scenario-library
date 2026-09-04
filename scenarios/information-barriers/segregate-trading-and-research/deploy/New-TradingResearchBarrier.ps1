#Requires -Version 7.0
<#
.SYNOPSIS
    Builds an information-barrier "ethical wall" between the Trading desk and Research: defines the
    organization segments and the two one-way block policies, and (only with -Activate) activates and
    applies them.

.DESCRIPTION
    Uses the Information Barriers cmdlets in Security & Compliance PowerShell (automation surface 1
    per docs/automation-surface.md):
      1. New-OrganizationSegment      -> a segment per side, from an Entra attribute filter
      2. New-InformationBarrierPolicy -> a one-way BLOCK policy per direction (created -State Inactive)
      3. (with -Activate) Set-InformationBarrierPolicy -State Active  +  Start-InformationBarrierPoliciesApplication

    Safe by default: segments and policies are CREATED but left INACTIVE and NOT applied. Nothing
    changes for users until you pass -Activate, which sets the policies active and starts the
    tenant-wide application - a consequential action that blocks live Teams chat/calls and SharePoint/
    OneDrive collaboration between the two sides. Application is asynchronous (~30 min to start,
    ~5,000 users/hour) and SharePoint/OneDrive enforcement can take up to 24 hours to propagate.

    Idempotent (create-or-report): each segment/policy is located by name via Get-* before create; an
    existing object is reported, not silently mutated (IB objects gate real communication). -WhatIf is
    non-functional in Security & Compliance PowerShell, so this script implements its own -DryRun.

    Connect first: Connect-IPPSSession (certificate app-only preferred - docs/automation-surface.md
    Section 3). This script does not open the session.

.PARAMETER ConfigPath
    Path to the JSON config. Defaults to 'config/trading-research-barrier.sample.json'.

.PARAMETER Activate
    After creating segments/policies, set the policies Active and run
    Start-InformationBarrierPoliciesApplication to enforce them tenant-wide. Omit to stage everything
    inactive for review first (strongly recommended for a first run).

.PARAMETER DryRun
    Print every mutating cmdlet that would run and invoke none (the working substitute for -WhatIf).

.EXAMPLE
    Connect-IPPSSession -AppId $AppId -Certificate $Cert -Organization 'contoso.onmicrosoft.com'
    ./New-TradingResearchBarrier.ps1 -DryRun

.EXAMPLE
    Connect-IPPSSession -AppId $AppId -Certificate $Cert -Organization 'contoso.onmicrosoft.com'
    ./New-TradingResearchBarrier.ps1            # create segments + policies, INACTIVE (no user impact)

.EXAMPLE
    ./New-TradingResearchBarrier.ps1 -Activate  # activate + apply (blocks live communication)

.NOTES
    Grounded in Microsoft Learn (verify before production use):
    - New-OrganizationSegment / New-InformationBarrierPolicy / Set-InformationBarrierPolicy /
      Start-InformationBarrierPoliciesApplication (SCC PowerShell):
      https://learn.microsoft.com/powershell/module/exchangepowershell/new-informationbarrierpolicy
    - Get started with Information Barriers (segments, block policies, apply):
      https://learn.microsoft.com/purview/information-barriers-policies
    - Attributes for IB segments: https://learn.microsoft.com/purview/information-barriers-attributes
#>
[CmdletBinding()]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$ConfigPath = (Join-Path $PSScriptRoot 'config/trading-research-barrier.sample.json'),

    [Parameter()]
    [switch]$Activate,

    [Parameter()]
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

function Assert-SccConnected {
    if (-not (Get-Command Get-OrganizationSegment -ErrorAction SilentlyContinue)) {
        throw "Information Barriers cmdlets not found. Connect first: Connect-IPPSSession. See docs/automation-surface.md Section 3."
    }
}
function Invoke-Scc {
    param([Parameter(Mandatory)][string]$Describe, [Parameter(Mandatory)][scriptblock]$Action)
    if ($DryRun) { Write-Host "  DRYRUN would run: $Describe" -ForegroundColor DarkYellow; return $null }
    Write-Host "  $Describe" -ForegroundColor Green
    return & $Action
}

if (-not (Test-Path -LiteralPath $ConfigPath)) { throw "Config file not found: $ConfigPath" }
$cfg = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
if (-not $cfg.segments -or @($cfg.segments).Count -lt 1) { throw "Config needs at least one segment." }
if (-not $cfg.blockPairs -or @($cfg.blockPairs).Count -lt 1) { throw "Config needs at least one blockPair." }

Assert-SccConnected
Write-Host "Building information-barrier ethical wall from '$ConfigPath'." -ForegroundColor Cyan
if (-not $Activate) {
    Write-Host "Segments/policies will be created INACTIVE and NOT applied (no user impact). Re-run with -Activate to enforce." -ForegroundColor Yellow
}
else {
    Write-Host "WARNING: -Activate will BLOCK live Teams/SharePoint/OneDrive communication between the segments once application completes (~30 min to start, up to 24h for SharePoint). Review with -DryRun and Compliance/Legal first." -ForegroundColor Red
}

# --- 1. Segments ---
foreach ($seg in @($cfg.segments)) {
    if (-not $seg.name -or -not $seg.userGroupFilter) { throw "Each segment needs name and userGroupFilter." }
    $existing = Get-OrganizationSegment -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq $seg.name } | Select-Object -First 1
    if ($existing) {
        Write-Host "  [segment] exists '$($seg.name)'" -ForegroundColor DarkGreen
    }
    else {
        Invoke-Scc -Describe "New-OrganizationSegment -Name '$($seg.name)' -UserGroupFilter `"$($seg.userGroupFilter)`"" `
            -Action { New-OrganizationSegment -Name $seg.name -UserGroupFilter $seg.userGroupFilter -Confirm:$false } | Out-Null
        Write-Host "  [segment] created '$($seg.name)'" -ForegroundColor Green
    }
}

# --- 2. One-way block policies ---
$policyNames = [System.Collections.Generic.List[string]]::new()
foreach ($pair in @($cfg.blockPairs)) {
    if (-not $pair.assignedSegment -or -not $pair.blocks) { throw "Each blockPair needs assignedSegment and blocks." }
    $polName = "$($pair.assignedSegment)-block-$($pair.blocks)"
    $policyNames.Add($polName)
    $existing = Get-InformationBarrierPolicy -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq $polName } | Select-Object -First 1
    if ($existing) {
        Write-Host "  [policy] exists '$polName' (state: $($existing.State))" -ForegroundColor DarkGreen
    }
    else {
        Invoke-Scc -Describe "New-InformationBarrierPolicy -Name '$polName' -AssignedSegment '$($pair.assignedSegment)' -SegmentsBlocked '$($pair.blocks)' -State Inactive" `
            -Action { New-InformationBarrierPolicy -Name $polName -AssignedSegment $pair.assignedSegment -SegmentsBlocked $pair.blocks -State Inactive -Confirm:$false } | Out-Null
        Write-Host "  [policy] created '$polName' (Inactive)" -ForegroundColor Green
    }
}

# --- 3. (optional) Activate + apply ---
if ($Activate) {
    foreach ($polName in $policyNames) {
        $pol = Get-InformationBarrierPolicy -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq $polName } | Select-Object -First 1
        if ($pol -and "$($pol.State)" -ne 'Active') {
            Invoke-Scc -Describe "Set-InformationBarrierPolicy -Identity $($pol.Guid) -State Active" `
                -Action { Set-InformationBarrierPolicy -Identity $pol.Guid -State Active -Confirm:$false } | Out-Null
            Write-Host "  [activate] '$polName' set Active" -ForegroundColor Yellow
        }
    }
    Invoke-Scc -Describe "Start-InformationBarrierPoliciesApplication" -Action { Start-InformationBarrierPoliciesApplication -Confirm:$false } | Out-Null
    Write-Host "  [apply] tenant-wide application started (~30 min to begin, ~5,000 users/hour)." -ForegroundColor Cyan
}

Write-Host "`nDone." -ForegroundColor Cyan
if (-not $Activate) {
    Write-Host "Nothing is enforced yet. Review the segments/policies, then re-run with -Activate. Validate with validate/Test-TradingResearchBarrier.ps1." -ForegroundColor Yellow
}
else {
    Write-Host "Track application with Get-InformationBarrierPoliciesApplicationStatus. Allow up to 24h for SharePoint/OneDrive propagation." -ForegroundColor Yellow
}
