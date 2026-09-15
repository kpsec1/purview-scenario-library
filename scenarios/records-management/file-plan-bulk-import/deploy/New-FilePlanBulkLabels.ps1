#Requires -Version 7.0
<#
.SYNOPSIS
    Creates an entire file plan (many retention labels, across departments/categories/citations)
    from the same CSV schedule New-FilePlanImportCsv.ps1 validates - via Security & Compliance
    PowerShell (New-ComplianceTag + New-FilePlanProperty*), with no portal Import step at all.

.DESCRIPTION
    File plan's own bulk "Import" button is portal-only (no API/cmdlet performs it -
    README.md Section 5 / Section 11). This script is the fully-scriptable equivalent: for every
    row it idempotently creates-or-reports the six file-plan-property descriptor objects
    (Department/Category/SubCategory/Citation/ReferenceId/Authority) the row references, then
    creates-or-reports the retention label itself with -FilePlanProperty wired to them, using the
    exact PSCustomObject -> ConvertTo-Json shape Microsoft documents for that parameter
    [[3]](../README.md#12-references).

    Reuses FilePlanRow.Validate.ps1 (the same rule set New-FilePlanImportCsv.ps1 uses) so a row
    that would fail the portal's own CSV-import validation is refused here too, before anything is
    created.

    Idempotent, create-or-report throughout - like the sibling `regulatory-records-disposition`
    scenario, records objects here are never silently mutated. Re-running after a partial failure
    is safe: every already-created label/descriptor is detected and skipped.

    !!! Multi-stage disposition review is NOT built by this script or by the CSV import it
    complements !!! Every row's ReviewerEmail becomes a SINGLE-stage review
    (-ReviewerEmail on New-ComplianceTag). A dedicated multi-stage scenario
    (`-MultiStageReviewProperty`) is a tracked follow-up - see PROGRESS.md.

    Connect first: Connect-IPPSSession (certificate app-only preferred -
    docs/automation-surface.md Section 3). -WhatIf is non-functional in Security & Compliance
    PowerShell, so this script implements its own -DryRun.

.PARAMETER InputPath
    Path to the file-plan schedule CSV (same format/columns as New-FilePlanImportCsv.ps1).
    Defaults to 'config/file-plan-schedule.sample.csv'.

.PARAMETER DryRun
    Print every mutating cmdlet this run would execute, for every row, and invoke none.

.EXAMPLE
    Connect-IPPSSession -AppId $AppId -Certificate $Cert -Organization 'contoso.onmicrosoft.com'
    ./New-FilePlanBulkLabels.ps1 -DryRun

.EXAMPLE
    ./New-FilePlanBulkLabels.ps1
    # Creates every valid row's descriptors + label. Re-run any time - already-created objects are
    # reported, not recreated or modified.

.NOTES
    Grounded in Microsoft Learn (verify before production use):
    - New-ComplianceTag (-FilePlanProperty PSCustomObject -> ConvertTo-Json shape;
      -RetentionAction/-RetentionDuration/-RetentionType/-ReviewerEmail/-IsRecordLabel/-Regulatory/
      -IsRecordUnlockedAsDefault/-ComplianceTagForNextStage):
      https://learn.microsoft.com/powershell/module/exchangepowershell/new-compliancetag
    - New-FilePlanPropertyDepartment / -Category / -SubCategory (-ParentId) / -Citation /
      -ReferenceId / -Authority:
      https://learn.microsoft.com/powershell/module/exchangepowershell/new-fileplanpropertydepartment
      https://learn.microsoft.com/powershell/module/exchangepowershell/new-fileplanpropertycategory
      https://learn.microsoft.com/powershell/module/exchangepowershell/new-fileplanpropertysubcategory
      https://learn.microsoft.com/powershell/module/exchangepowershell/new-fileplanpropertycitation
      https://learn.microsoft.com/powershell/module/exchangepowershell/new-fileplanpropertyreferenceid
    - Import retention labels into your file plan (CSV import is portal-only; the property table
      this script's validation mirrors):
      https://learn.microsoft.com/purview/file-plan-manager#import-retention-labels-into-your-file-plan
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
. (Join-Path $PSScriptRoot 'FilePlanRow.Validate.ps1')

function Assert-SccConnected {
    if (-not (Get-Command Get-ComplianceTag -ErrorAction SilentlyContinue)) {
        throw "Records management cmdlets not found. Connect first: Connect-IPPSSession. See docs/automation-surface.md Section 3."
    }
}
function Invoke-Scc {
    param([Parameter(Mandatory)][string]$Describe, [Parameter(Mandatory)][scriptblock]$Action)
    if ($DryRun) { Write-Host "    DRYRUN would run: $Describe" -ForegroundColor DarkYellow; return $null }
    Write-Host "    $Describe" -ForegroundColor Green
    return & $Action
}
# Create-or-report one file-plan-property descriptor object (Department/Category/Citation/ReferenceId/Authority - no -ParentId).
function Confirm-FilePlanProperty {
    param([Parameter(Mandatory)][string]$Kind, [Parameter(Mandatory)][string]$Name)
    $getCmd = "Get-FilePlanProperty$Kind"; $newCmd = "New-FilePlanProperty$Kind"
    $existing = & $getCmd -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq $Name }
    if ($existing) { Write-Host "    [$Kind] exists '$Name'" -ForegroundColor DarkGreen; return }
    Invoke-Scc -Describe "$newCmd -Name '$Name'" -Action { & $newCmd -Name $Name -Confirm:$false } | Out-Null
    if (-not $DryRun) { Write-Host "    [$Kind] created '$Name'" -ForegroundColor Green }
}
# SubCategory takes -ParentId (the parent Category name) - documented separately from the other five.
function Confirm-FilePlanSubCategory {
    param([Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)][string]$ParentCategory)
    $existing = Get-FilePlanPropertySubCategory -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq $Name }
    if ($existing) { Write-Host "    [SubCategory] exists '$Name'" -ForegroundColor DarkGreen; return }
    Invoke-Scc -Describe "New-FilePlanPropertySubCategory -Name '$Name' -ParentId '$ParentCategory'" `
        -Action { New-FilePlanPropertySubCategory -Name $Name -ParentId $ParentCategory -Confirm:$false } | Out-Null
    if (-not $DryRun) { Write-Host "    [SubCategory] created '$Name'" -ForegroundColor Green }
}

if (-not (Test-Path -LiteralPath $InputPath)) { throw "Input CSV not found: $InputPath" }
Assert-SccConnected
$rows = Import-Csv -LiteralPath $InputPath
Write-Host "Bulk-creating file plan from '$InputPath' ($(@($rows).Count) row(s))$(if ($DryRun) { ' [DRYRUN]' })." -ForegroundColor Cyan

$existingTags = @(Get-ComplianceTag -ErrorAction SilentlyContinue)
$existingEventTypes = @(Get-ComplianceRetentionEventType -ErrorAction SilentlyContinue)
$created = 0; $skipped = 0; $failed = 0
$rowNum = 1
foreach ($row in $rows) {
    $rowNum++
    Write-Host "`nRow ${rowNum}: '$($row.LabelName)'" -ForegroundColor Cyan

    $labelExists = [bool]($existingTags | Where-Object { $_.Name -eq $row.LabelName })
    $eventExists = if ($row.EventType) { [bool]($existingEventTypes | Where-Object { $_.Name -eq $row.EventType }) } else { $null }
    $result = Test-FilePlanRow -Row $row -RowNumber $rowNum -LabelNameExistsInTenant $(if ($labelExists) { $true } else { $null }) -EventTypeExistsInTenant $eventExists
    if (-not $result.IsValid -and -not $labelExists) {
        foreach ($e in $result.Errors) { Write-Host "  [FAIL] $e" -ForegroundColor Red }
        $failed++
        continue
    }
    foreach ($w in $result.Warnings) { Write-Host "  [WARN] $w" -ForegroundColor Yellow }

    if ($labelExists) {
        Write-Host "  [label] exists '$($row.LabelName)' (not modified - records objects are never silently mutated)." -ForegroundColor DarkGreen
        $skipped++
        continue
    }

    # --- Descriptor objects (create-or-report each, before the label references them) ---
    $descriptors = @{}
    if ($row.DepartmentName) { Confirm-FilePlanProperty -Kind 'Department' -Name $row.DepartmentName; $descriptors.FilePlanPropertyDepartment = $row.DepartmentName }
    if ($row.Category) { Confirm-FilePlanProperty -Kind 'Category' -Name $row.Category; $descriptors.FilePlanPropertyCategory = $row.Category }
    if ($row.SubCategory) { Confirm-FilePlanSubCategory -Name $row.SubCategory -ParentCategory $row.Category; $descriptors.FilePlanPropertySubcategory = $row.SubCategory }
    if ($row.ReferenceId) { Confirm-FilePlanProperty -Kind 'ReferenceId' -Name $row.ReferenceId; $descriptors.FilePlanPropertyReferenceId = $row.ReferenceId }
    if ($row.CitationName) { Confirm-FilePlanProperty -Kind 'Citation' -Name $row.CitationName; $descriptors.FilePlanPropertyCitation = $row.CitationName }
    if ($row.AuthorityType) { Confirm-FilePlanProperty -Kind 'Authority' -Name $row.AuthorityType; $descriptors.FilePlanPropertyAuthority = $row.AuthorityType }
    # CitationUrl/CitationJurisdiction are properties of the Citation object itself in the portal UI, not
    # separate -FilePlanProperty settings keys, and New-FilePlanPropertyCitation takes no -Url/-Jurisdiction
    # parameter in its documented syntax. VERIFY (pilot tenant or a future Learn pass): how to set them via
    # PowerShell - not built here; the citation NAME is created/attached, its URL/jurisdiction are not.
    if ($row.CitationUrl -or $row.CitationJurisdiction) {
        Write-Host "  [WARN] CitationUrl/CitationJurisdiction are set in the source row but this script has no documented PowerShell parameter to set them on the citation object - only the citation NAME is created/linked. Set them via the portal (File plan descriptors) if required. See README.md Section 11." -ForegroundColor Yellow
    }

    # --- The label itself ---
    $tagParams = @{
        Name            = $row.LabelName
        RetentionAction = $row.RetentionAction
        RetentionType   = $row.RetentionType
    }
    $tagParams.RetentionDuration = if ($row.RetentionDuration -eq 'Unlimited') { 'Unlimited' } else { [int]$row.RetentionDuration }
    if ($row.Comment) { $tagParams.Comment = $row.Comment }
    if ($row.Notes) { $tagParams.Notes = $row.Notes }
    if ($row.IsRecordLabel -eq 'TRUE') { $tagParams.IsRecordLabel = $true }
    if ($row.Regulatory -eq 'TRUE') { $tagParams.Regulatory = $true }
    if ($row.IsRecordUnlockedAsDefault -eq 'TRUE') { $tagParams.IsRecordUnlockedAsDefault = $true }
    if ($row.EventType) { $tagParams.EventType = $row.EventType }
    if ($row.ComplianceTagForNextStage) { $tagParams.ComplianceTagForNextStage = $row.ComplianceTagForNextStage }
    if ($row.ReviewerEmail) { $tagParams.ReviewerEmail = @($row.ReviewerEmail -split ';' | Where-Object { $_ } | ForEach-Object { $_.Trim() }) }
    if ($descriptors.Count -gt 0) {
        $fpObject = [PSCustomObject]@{ Settings = @($descriptors.GetEnumerator() | ForEach-Object { @{ Key = $_.Key; Value = $_.Value } }) }
        $tagParams.FilePlanProperty = ConvertTo-Json $fpObject -Compress -Depth 5
    }

    $desc = "New-ComplianceTag -Name '$($row.LabelName)' -RetentionAction $($row.RetentionAction) -RetentionType $($row.RetentionType) -RetentionDuration $($tagParams.RetentionDuration)$(if ($tagParams.FilePlanProperty) { ' -FilePlanProperty <descriptors>' })"
    Invoke-Scc -Describe $desc -Action { New-ComplianceTag @tagParams -Confirm:$false } | Out-Null
    if (-not $DryRun) { Write-Host "  [label] created '$($row.LabelName)'" -ForegroundColor Green }
    $created++
}

Write-Host "`nDone$(if ($DryRun) { ' [DRYRUN - nothing was created]' }). Created: $created  Skipped (already existed): $skipped  Failed validation: $failed." -ForegroundColor Cyan
Write-Host "Validate with validate/Test-FilePlanBulkImport.ps1. Publish or auto-apply the new labels separately (Label policies tab / a DLM auto-apply scenario) - this script only creates them." -ForegroundColor Yellow
if ($failed -gt 0) { exit 1 }
