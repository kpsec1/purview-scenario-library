#Requires -Version 7.0
<#
.SYNOPSIS
    Rolls back the Trading/Research information-barrier wall: deactivates the block policies (and, with
    -Apply, re-applies so communication is restored), and optionally deletes the policies and segments.

.DESCRIPTION
    Uses the Information Barriers cmdlets in Security & Compliance PowerShell. Staged:
      Default        Set the block policies to Inactive. (Deactivation only takes effect for users
                     after an application run - pass -Apply to run it now and lift the wall.)
      -Apply         Run Start-InformationBarrierPoliciesApplication after deactivating, so the block
                     is actually lifted tenant-wide (asynchronous; SharePoint/OneDrive up to 24h).
      -Delete        Additionally remove the policies (Remove-InformationBarrierPolicy) and the
                     segments (disassociate users via Set-OrganizationSegment, then
                     Remove-OrganizationSegment).

    Lifting an ethical wall re-enables communication that may be subject to regulatory obligations -
    do this only with Compliance/Legal confirmation. -WhatIf is non-functional in Security &
    Compliance PowerShell, so this script implements -DryRun. Connect first with Connect-IPPSSession.

.PARAMETER ConfigPath
    Path to the same JSON config used to deploy. Defaults to 'config/trading-research-barrier.sample.json'.

.PARAMETER Apply
    Run Start-InformationBarrierPoliciesApplication after deactivating so the wall is lifted now.

.PARAMETER Delete
    Delete the block policies and the segments (after deactivation).

.PARAMETER DryRun
    Print the intended cmdlets and run none.

.EXAMPLE
    Connect-IPPSSession -AppId $AppId -Certificate $Cert -Organization 'contoso.onmicrosoft.com'
    ./Remove-TradingResearchBarrier.ps1 -DryRun

.EXAMPLE
    ./Remove-TradingResearchBarrier.ps1 -Apply            # deactivate + lift the wall
    ./Remove-TradingResearchBarrier.ps1 -Apply -Delete    # lift, then delete policies + segments

.NOTES
    Grounded in Microsoft Learn: Set-/Remove-InformationBarrierPolicy, Set-/Remove-OrganizationSegment,
    Start-InformationBarrierPoliciesApplication.
    https://learn.microsoft.com/purview/information-barriers-edit-segments-policies
#>
[CmdletBinding()]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$ConfigPath = (Join-Path $PSScriptRoot 'config/trading-research-barrier.sample.json'),

    [Parameter()]
    [switch]$Apply,

    [Parameter()]
    [switch]$Delete,

    [Parameter()]
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
if (-not (Get-Command Get-InformationBarrierPolicy -ErrorAction SilentlyContinue)) {
    throw "Information Barriers cmdlets not found. Connect first: Connect-IPPSSession. See docs/automation-surface.md Section 3."
}
if (-not (Test-Path -LiteralPath $ConfigPath)) { throw "Config file not found: $ConfigPath" }
$cfg = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json

function Invoke-Scc {
    param([string]$Describe, [scriptblock]$Action)
    if ($DryRun) { Write-Host "  DRYRUN would run: $Describe" -ForegroundColor DarkYellow; return }
    Write-Host "  $Describe" -ForegroundColor Green
    & $Action
}

$policyNames = @($cfg.blockPairs | ForEach-Object { "$($_.assignedSegment)-block-$($_.blocks)" })

# --- Deactivate (and optionally delete) policies ---
foreach ($polName in $policyNames) {
    $pol = Get-InformationBarrierPolicy -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq $polName } | Select-Object -First 1
    if (-not $pol) { Write-Host "  [policy] '$polName' not found." -ForegroundColor DarkGray; continue }
    if ("$($pol.State)" -eq 'Active') {
        Invoke-Scc -Describe "Set-InformationBarrierPolicy -Identity $($pol.Guid) -State Inactive" `
            -Action { Set-InformationBarrierPolicy -Identity $pol.Guid -State Inactive -Confirm:$false }
        Write-Host "  [deactivate] '$polName' set Inactive" -ForegroundColor Yellow
    }
    if ($Delete) {
        Invoke-Scc -Describe "Remove-InformationBarrierPolicy -Identity $($pol.Guid)" `
            -Action { Remove-InformationBarrierPolicy -Identity $pol.Guid -Confirm:$false }
        Write-Host "  [delete] policy '$polName' removed" -ForegroundColor Red
    }
}

# --- Apply so deactivation actually lifts the wall ---
if ($Apply) {
    Invoke-Scc -Describe "Start-InformationBarrierPoliciesApplication" -Action { Start-InformationBarrierPoliciesApplication -Confirm:$false }
    Write-Host "  [apply] application started - the wall is being lifted (async; SharePoint up to 24h)." -ForegroundColor Cyan
}
else {
    Write-Host "  NOTE: deactivation does not take effect for users until an application run. Re-run with -Apply to lift the wall now." -ForegroundColor Yellow
}

# --- Delete segments (after policies are gone) ---
if ($Delete) {
    foreach ($seg in @($cfg.segments)) {
        $s = Get-OrganizationSegment -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq $seg.name } | Select-Object -First 1
        if (-not $s) { continue }
        Invoke-Scc -Describe "Remove-OrganizationSegment -Identity $($s.Guid)" `
            -Action { Remove-OrganizationSegment -Identity $s.Guid -Confirm:$false }
        Write-Host "  [delete] segment '$($seg.name)' removed" -ForegroundColor Red
    }
}

Write-Host "`nDone." -ForegroundColor Cyan
Write-Host "Lifting an ethical wall re-enables communication that may carry regulatory obligations - confirm with Compliance/Legal. Track with Get-InformationBarrierPoliciesApplicationStatus." -ForegroundColor Yellow
