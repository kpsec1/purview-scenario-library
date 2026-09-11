#Requires -Version 7.0
<#
.SYNOPSIS
    Rolls back the allow-list exception segments/policies: deactivates the allow policies (and, with
    -Apply, re-applies so the exception's access is actually revoked), and optionally deletes the
    policies and segments.

.DESCRIPTION
    Uses the Information Barriers cmdlets in Security & Compliance PowerShell. Staged:
      Default        Set the allow policies this config manages to Inactive. (Deactivation only takes
                     effect for users after an application run - pass -Apply to run it now.)
      -Apply         Run Start-InformationBarrierPoliciesApplication after deactivating, so the
                     exception segment's access reverts tenant-wide (asynchronous; SharePoint/OneDrive
                     up to 24h). NOTE: an Allow-type policy is what grants its segment ANY cross-
                     segment access at all - deactivating it does not restore open communication, it
                     removes the exception. Members of an exception segment revert to whatever the
                     rest of the tenant's IB policies say about them (typically nothing, i.e. open,
                     unless another policy names their segment).
      -Delete        Additionally remove the policies (Remove-InformationBarrierPolicy) and the
                     segments (Remove-OrganizationSegment) this config defines.

    This does not touch the 'Trading'/'Research' wall itself (segregate-trading-and-research owns
    that) - only the exception segments/policies this scenario added. -WhatIf is non-functional in
    Security & Compliance PowerShell, so this script implements -DryRun. Connect first with
    Connect-IPPSSession.

.PARAMETER ConfigPath
    Path to the same JSON config used to deploy. Defaults to 'config/control-room-allow-exceptions.sample.json'.

.PARAMETER Apply
    Run Start-InformationBarrierPoliciesApplication after deactivating so the exception is revoked now.

.PARAMETER Delete
    Delete the allow policies and the exception segments (after deactivation).

.PARAMETER DryRun
    Print the intended cmdlets and run none.

.EXAMPLE
    Connect-IPPSSession -AppId $AppId -Certificate $Cert -Organization 'contoso.onmicrosoft.com'
    ./Remove-ControlRoomAllowException.ps1 -DryRun

.EXAMPLE
    ./Remove-ControlRoomAllowException.ps1 -Apply            # deactivate + revoke the exception
    ./Remove-ControlRoomAllowException.ps1 -Apply -Delete    # revoke, then delete policies + segments

.NOTES
    Grounded in Microsoft Learn: Set-/Remove-InformationBarrierPolicy, Remove-OrganizationSegment,
    Start-InformationBarrierPoliciesApplication.
    https://learn.microsoft.com/purview/information-barriers-edit-segments-policies
#>
[CmdletBinding()]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$ConfigPath = (Join-Path $PSScriptRoot 'config/control-room-allow-exceptions.sample.json'),

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

$policyNames = @($cfg.allowPolicies | ForEach-Object { "$($_.assignedSegment)-allow-$(@($_.allows) -join '-')" })

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

# --- Apply so deactivation actually revokes the exception ---
if ($Apply) {
    Invoke-Scc -Describe "Start-InformationBarrierPoliciesApplication" -Action { Start-InformationBarrierPoliciesApplication -Confirm:$false }
    Write-Host "  [apply] application started - the exception is being revoked (async; SharePoint up to 24h)." -ForegroundColor Cyan
}
else {
    Write-Host "  NOTE: deactivation does not take effect for users until an application run. Re-run with -Apply to revoke the exception now." -ForegroundColor Yellow
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
Write-Host "The 'Trading'/'Research' wall itself is untouched by this rollback. Track application with Get-InformationBarrierPoliciesApplicationStatus." -ForegroundColor Yellow
