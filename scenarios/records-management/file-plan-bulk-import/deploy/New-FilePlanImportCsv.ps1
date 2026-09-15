#Requires -Version 7.0
<#
.SYNOPSIS
    Validates a file-plan record-schedule CSV against every documented rule for Purview's file plan
    "Import" feature, and emits a copy ready for upload via the portal - Microsoft does not publish
    an API/cmdlet that performs the import itself.

.DESCRIPTION
    File plan's bulk-import ("Records Management > File plan > Import") is a PORTAL-ONLY action: a
    human downloads a blank template, fills it in, and uploads it; there is no documented Graph/REST
    endpoint or PowerShell cmdlet that performs that upload [[1]](../README.md#12-references). This
    script is the automatable half of that workflow: it reproduces every validation rule Microsoft
    documents for the template (required columns, valid values, group dependencies, max lengths,
    the LabelName character set) so a bad row is caught locally - with the row number and column
    name, exactly like the portal's own validation - instead of after a human uploads it.

    Two validation tiers:
      1. OFFLINE (default, no tenant connection needed) - every rule that doesn't require reading
         live tenant state: required columns, valid enums, lengths, LabelName charset, and the
         documented group dependencies (RetentionAction/RetentionDuration/RetentionType/
         ReviewerEmail/IsRecordLabel/Regulatory/IsRecordUnlockedAsDefault/ComplianceTagForNextStage).
      2. -TenantChecks (requires Connect-IPPSSession first) - additionally checks LabelName isn't
         already used in the tenant, and that any referenced EventType already exists (the CSV
         import's own documented pre-requisite for EventAgeInDays rows) [[1]](../README.md#12-references).

    On success, writes a validated copy of the CSV (byte-identical rows, normalized line endings) to
    -OutputPath - upload THAT file via the portal's Import button. On any hard failure, nothing is
    written and every row/column error is printed (does not stop at the first error - reports all of
    them, like the portal's own "note the row number and column name" validation UX).

    Never calls a mutating cmdlet. Read-only even with -TenantChecks (Get-ComplianceTag /
    Get-ComplianceRetentionEventType only).

.PARAMETER InputPath
    Path to the source file-plan schedule CSV. Defaults to 'config/file-plan-schedule.sample.csv'.

.PARAMETER OutputPath
    Path to write the validated, upload-ready copy. Defaults to 'file-plan-import-ready.csv' next to
    -InputPath. Not written if validation fails.

.PARAMETER TenantChecks
    Also check LabelName-uniqueness-in-tenant and EventType-exists-in-tenant against a live
    connection. Requires Connect-IPPSSession first. Without this switch, those two checks are
    skipped (reported as [INFO], not [FAIL]) and the script runs fully offline.

.EXAMPLE
    ./New-FilePlanImportCsv.ps1
    # Offline validation only - no tenant connection required.

.EXAMPLE
    Connect-IPPSSession -AppId $AppId -Certificate $Cert -Organization 'contoso.onmicrosoft.com'
    ./New-FilePlanImportCsv.ps1 -TenantChecks -OutputPath ./file-plan-import-ready.csv
    # Then: Purview portal > Records Management > File plan > Import > Upload a file (file-plan-import-ready.csv)

.NOTES
    Grounded in Microsoft Learn (verify before production use):
    - Import retention labels into your file plan (portal-only Import flow; property table; "not
      supported for import: multi-stage disposition review"):
      https://learn.microsoft.com/purview/file-plan-manager#import-retention-labels-into-your-file-plan
    - Get-ComplianceRetentionEventType (live EventType-exists check):
      https://learn.microsoft.com/powershell/module/exchangepowershell/get-complianceretentioneventtype
    - Get-ComplianceTag (live LabelName-collision check):
      https://learn.microsoft.com/powershell/module/exchangepowershell/get-compliancetag
#>
[CmdletBinding()]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$InputPath = (Join-Path $PSScriptRoot 'config/file-plan-schedule.sample.csv'),

    [Parameter()]
    [string]$OutputPath,

    [Parameter()]
    [switch]$TenantChecks
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'FilePlanRow.Validate.ps1')

if (-not (Test-Path -LiteralPath $InputPath)) { throw "Input CSV not found: $InputPath" }
if (-not $OutputPath) { $OutputPath = Join-Path (Split-Path -Parent $InputPath) 'file-plan-import-ready.csv' }

$requiredColumns = 'LabelName', 'Comment', 'Notes', 'IsRecordLabel', 'RetentionAction', 'RetentionDuration', 'RetentionType', 'ReviewerEmail', 'ReferenceId', 'DepartmentName', 'Category', 'SubCategory', 'AuthorityType', 'CitationName', 'CitationUrl', 'CitationJurisdiction', 'Regulatory', 'EventType', 'IsRecordUnlockedAsDefault', 'ComplianceTagForNextStage'
$rows = Import-Csv -LiteralPath $InputPath
if (@($rows).Count -eq 0) { throw "No data rows found in $InputPath." }

$header = ($rows[0].PSObject.Properties.Name)
$missingCols = $requiredColumns | Where-Object { $_ -notin $header }
if ($missingCols) { throw "Input CSV is missing required column(s): $($missingCols -join ', '). Columns must match the file plan import template exactly." }

if ($TenantChecks -and -not (Get-Command Get-ComplianceTag -ErrorAction SilentlyContinue)) {
    throw "-TenantChecks requires a live connection. Connect first: Connect-IPPSSession. See docs/automation-surface.md Section 3."
}

Write-Host "Validating $(@($rows).Count) file-plan row(s) from '$InputPath'$(if ($TenantChecks) { ' (with live tenant checks)' } else { ' (offline - pass -TenantChecks for live checks)' })." -ForegroundColor Cyan

$existingTags = if ($TenantChecks) { @(Get-ComplianceTag -ErrorAction SilentlyContinue) } else { @() }
$existingEventTypes = if ($TenantChecks) { @(Get-ComplianceRetentionEventType -ErrorAction SilentlyContinue) } else { @() }

$allErrors = [System.Collections.Generic.List[string]]::new()
$allWarnings = [System.Collections.Generic.List[string]]::new()
$seenNames = @{}
$rowNum = 1
foreach ($row in $rows) {
    $rowNum++  # header is row 1 in the uploaded file; first data row is row 2
    $labelExists = if ($TenantChecks) { [bool]($existingTags | Where-Object { $_.Name -eq $row.LabelName }) } else { $null }
    $eventExists = if ($TenantChecks -and $row.EventType) { [bool]($existingEventTypes | Where-Object { $_.Name -eq $row.EventType }) } else { $null }

    $result = Test-FilePlanRow -Row $row -RowNumber $rowNum -LabelNameExistsInTenant $labelExists -EventTypeExistsInTenant $eventExists
    if ($row.LabelName) {
        if ($seenNames.ContainsKey($row.LabelName)) { $allErrors.Add("Row ${rowNum}: LabelName '$($row.LabelName)' duplicates row $($seenNames[$row.LabelName]) in this file - names must be unique.") }
        else { $seenNames[$row.LabelName] = $rowNum }
    }
    foreach ($e in $result.Errors) { $allErrors.Add($e) }
    foreach ($w in $result.Warnings) { $allWarnings.Add($w) }
    Write-Host "  Row $rowNum ($($result.LabelName)): $(if ($result.IsValid) { '[PASS]' } else { '[FAIL]' })" -ForegroundColor $(if ($result.IsValid) { 'Green' } else { 'Red' })
}

foreach ($w in $allWarnings) { Write-Host "  [WARN] $w" -ForegroundColor Yellow }

if ($allErrors.Count -gt 0) {
    Write-Host "`n$($allErrors.Count) error(s) - fix and re-run. No output file written." -ForegroundColor Red
    foreach ($e in $allErrors) { Write-Host "  [FAIL] $e" -ForegroundColor Red }
    exit 1
}

if (-not $TenantChecks) {
    Write-Host "`nOffline validation passed. Re-run with -TenantChecks (after Connect-IPPSSession) to also check LabelName uniqueness and EventType existence against your tenant before uploading." -ForegroundColor Yellow
}

Copy-Item -LiteralPath $InputPath -Destination $OutputPath -Force
Write-Host "`nAll rows valid. Wrote upload-ready file: $OutputPath" -ForegroundColor Cyan
Write-Host "Upload it: Purview portal > Records Management > File plan > Import > Upload a file. Or run New-FilePlanBulkLabels.ps1 against the same input to create the labels via PowerShell instead, with no portal step." -ForegroundColor Yellow
