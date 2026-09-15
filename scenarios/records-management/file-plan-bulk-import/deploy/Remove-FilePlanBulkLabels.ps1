#Requires -Version 7.0
<#
.SYNOPSIS
    Attempts to remove every retention label a file-plan schedule CSV created via
    New-FilePlanBulkLabels.ps1 - using Security & Compliance PowerShell.

.DESCRIPTION
    For each row, attempts Remove-ComplianceTag by name. Remove-ComplianceTag only succeeds for a
    label that has never been applied to content, isn't configured for event-based retention, isn't
    a regulatory record, and isn't in a published/auto-apply policy [[label-delete]](../README.md#12-references)
    - so a label already in real use is reported as NOT removed, not forced. This mirrors the
    sibling `regulatory-records-disposition` scenario's rollback philosophy: records objects are
    high-consequence and this script never forces their removal.

    Does NOT remove the file-plan-property descriptor objects (Department/Category/SubCategory/
    Citation/ReferenceId/Authority) New-FilePlanBulkLabels.ps1 created - those are shared,
    tenant-wide picklist values that other labels (including ones outside this schedule) may
    already reference; deleting them is out of scope for this rollback (README.md Section 11).

    Idempotent: a label that doesn't exist is reported and skipped. -WhatIf is non-functional in
    Security & Compliance PowerShell, so this script implements its own -DryRun.

    Connect first: Connect-IPPSSession (docs/automation-surface.md Section 3).

.PARAMETER InputPath
    Path to the file-plan schedule CSV whose LabelName column drives removal. Defaults to
    'config/file-plan-schedule.sample.csv'.

.PARAMETER DryRun
    Print every mutating cmdlet this run would execute and invoke none.

.EXAMPLE
    Connect-IPPSSession -AppId $AppId -Certificate $Cert -Organization 'contoso.onmicrosoft.com'
    ./Remove-FilePlanBulkLabels.ps1 -DryRun

.EXAMPLE
    ./Remove-FilePlanBulkLabels.ps1

.NOTES
    Grounded in Microsoft Learn (verify before production use):
    - Delete retention labels (succeeds only if not applied/published; fails - reported, not forced
      - otherwise): https://learn.microsoft.com/purview/file-plan-manager#delete-retention-labels
    - Remove-ComplianceTag: https://learn.microsoft.com/powershell/module/exchangepowershell/remove-compliancetag
#>
[CmdletBinding()]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$InputPath = (Join-Path $PSScriptRoot 'config/file-plan-schedule.sample.csv'),

    [Parameter()]
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

function Assert-SccConnected {
    if (-not (Get-Command Get-ComplianceTag -ErrorAction SilentlyContinue)) {
        throw "Records management cmdlets not found. Connect first: Connect-IPPSSession. See docs/automation-surface.md Section 3."
    }
}
function Invoke-Scc {
    param([Parameter(Mandatory)][string]$Describe, [Parameter(Mandatory)][scriptblock]$Action)
    if ($DryRun) { Write-Host "  DRYRUN would run: $Describe" -ForegroundColor DarkYellow; return $null }
    Write-Host "  $Describe" -ForegroundColor Green
    return & $Action
}

if (-not (Test-Path -LiteralPath $InputPath)) { throw "Input CSV not found: $InputPath" }
Assert-SccConnected
$rows = Import-Csv -LiteralPath $InputPath
Write-Host "Rolling back file plan labels from '$InputPath' ($(@($rows).Count) row(s))$(if ($DryRun) { ' [DRYRUN]' })." -ForegroundColor Cyan
Write-Host "NOTE: descriptor objects (Department/Category/etc.) are NOT removed - see rollback.md." -ForegroundColor Yellow

$removed = 0; $kept = 0; $missing = 0
foreach ($row in $rows) {
    $label = Get-ComplianceTag -Identity $row.LabelName -ErrorAction SilentlyContinue
    if (-not $label) {
        Write-Host "  [label] not found '$($row.LabelName)' - skipping." -ForegroundColor DarkGray
        $missing++
        continue
    }
    try {
        Invoke-Scc -Describe "Remove-ComplianceTag -Identity '$($row.LabelName)' (only if not applied/published/regulatory/event-based)" `
            -Action { Remove-ComplianceTag -Identity $row.LabelName -Confirm:$false } | Out-Null
        if (-not $DryRun) { Write-Host "  [label] removed '$($row.LabelName)'" -ForegroundColor Green }
        $removed++
    }
    catch {
        Write-Host "  [label] NOT removed '$($row.LabelName)': $($_.Exception.Message)" -ForegroundColor Yellow
        Write-Host "         Expected if the label has been applied to content, published, marked a regulatory record, or is event-based. Leave it in place." -ForegroundColor Yellow
        $kept++
    }
}

Write-Host "`nDone$(if ($DryRun) { ' [DRYRUN]' }). Removed: $removed  Kept (in use / not removable): $kept  Already absent: $missing." -ForegroundColor Cyan
