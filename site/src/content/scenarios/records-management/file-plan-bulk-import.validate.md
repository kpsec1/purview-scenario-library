---
part: "validate"
parent: "records-management/file-plan-bulk-import"
---
Run these checks after deployment to confirm the control is working as designed.


#### `Test-FilePlanBulkImport.ps1`

```powershell
#Requires -Version 7.0
<#
.SYNOPSIS
    Verifies a file-plan schedule CSV against the same rules the portal's own Import validates
    (schema-only, always available), and - once connected - that every row's label actually exists
    in the tenant with the expected retention settings.

.DESCRIPTION
    Read-only; never modifies any object. Two tiers, like the deploy scripts:
      1. Schema validation (dot-sources deploy/FilePlanRow.Validate.ps1 - always runs, no
         connection needed) - the pre-flight every row must pass before either deploy path
         (portal CSV upload or New-FilePlanBulkLabels.ps1) will accept it.
      2. Tenant reconciliation (only if Get-ComplianceTag is available) - for each row, confirms a
         retention label of that name exists and its RetentionAction/RetentionType/RetentionDuration/
         IsRecordLabel match the source row. File-plan-descriptor read-back (Department/Category/etc.)
         is reported informationally, not hard-checked - VERIFY (pilot tenant): the exact property
         name(s) Get-ComplianceTag exposes for file-plan descriptors were not confirmed against
         Microsoft Learn, so this script does not assert on them; see README.md Section 11.
    Exits non-zero on any hard failure (safe for a CI-style pre-flight). Safe to re-run.

.PARAMETER InputPath
    Path to the file-plan schedule CSV to validate. Defaults to
    '../deploy/config/file-plan-schedule.sample.csv'.

.EXAMPLE
    ./Test-FilePlanBulkImport.ps1
    # Schema-only - no tenant connection required.

.EXAMPLE
    Connect-IPPSSession -AppId $AppId -Certificate $Cert -Organization 'contoso.onmicrosoft.com'
    ./Test-FilePlanBulkImport.ps1
    # Also reconciles every row against the live tenant.
#>
[CmdletBinding()]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$InputPath = (Join-Path $PSScriptRoot '../deploy/config/file-plan-schedule.sample.csv')
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '../deploy/FilePlanRow.Validate.ps1')
$script:failures = 0
function Test-Check {
    param([string]$Description, [bool]$Condition, [switch]$Warn)
    if ($Condition) { Write-Host "  [PASS] $Description" -ForegroundColor Green }
    elseif ($Warn) { Write-Host "  [WARN] $Description" -ForegroundColor Yellow }
    else { Write-Host "  [FAIL] $Description" -ForegroundColor Red; $script:failures++ }
}

if (-not (Test-Path -LiteralPath $InputPath)) { throw "Input CSV not found: $InputPath" }
$rows = Import-Csv -LiteralPath $InputPath
$connected = [bool](Get-Command Get-ComplianceTag -ErrorAction SilentlyContinue)
Write-Host "Validating $(@($rows).Count) file-plan row(s) from '$InputPath'$(if ($connected) { ' (tenant-connected - also reconciling)' } else { ' (schema-only - not connected)' })." -ForegroundColor Cyan

$existingTags = if ($connected) { @(Get-ComplianceTag -ErrorAction SilentlyContinue) } else { @() }
$existingEventTypes = if ($connected) { @(Get-ComplianceRetentionEventType -ErrorAction SilentlyContinue) } else { @() }

$seenNames = @{}
$rowNum = 1
foreach ($row in $rows) {
    $rowNum++
    Write-Host "`nRow ${rowNum}: '$($row.LabelName)'" -ForegroundColor Cyan
    $existingTag = $existingTags | Where-Object { $_.Name -eq $row.LabelName } | Select-Object -First 1
    $eventExists = if ($connected -and $row.EventType) { [bool]($existingEventTypes | Where-Object { $_.Name -eq $row.EventType }) } else { $null }

    $result = Test-FilePlanRow -Row $row -RowNumber $rowNum -LabelNameExistsInTenant $null -EventTypeExistsInTenant $eventExists
    Test-Check -Description "Schema valid (no hard errors)" -Condition $result.IsValid
    foreach ($e in $result.Errors) { Write-Host "    - $e" -ForegroundColor Red }
    foreach ($w in $result.Warnings) { Write-Host "    - $w" -ForegroundColor Yellow }

    if ($row.LabelName) {
        if ($seenNames.ContainsKey($row.LabelName)) { Test-Check -Description "LabelName unique within this file" -Condition $false }
        else { $seenNames[$row.LabelName] = $rowNum }
    }

    if (-not $connected) { continue }
    Test-Check -Description "Retention label exists in tenant" -Condition ($null -ne $existingTag)
    if ($existingTag) {
        Test-Check -Description "  RetentionAction matches (want $($row.RetentionAction), have $($existingTag.RetentionAction))" -Condition ("$($existingTag.RetentionAction)" -eq "$($row.RetentionAction)")
        Test-Check -Description "  RetentionType matches (want $($row.RetentionType), have $($existingTag.RetentionType))" -Condition ("$($existingTag.RetentionType)" -eq "$($row.RetentionType)")
        Test-Check -Description "  RetentionDuration matches (want $($row.RetentionDuration), have $($existingTag.RetentionDuration))" -Condition ("$($existingTag.RetentionDuration)" -eq "$($row.RetentionDuration)") -Warn
        $wantRecord = ($row.IsRecordLabel -eq 'TRUE')
        Test-Check -Description "  IsRecordLabel matches (want $wantRecord, have $([bool]$existingTag.IsRecordLabel))" -Condition ($wantRecord -eq [bool]$existingTag.IsRecordLabel) -Warn
        if ($row.ReviewerEmail) {
            Test-Check -Description "  Disposition reviewer(s) present (current count: $(@($existingTag.ReviewerEmail).Count))" -Condition (@($existingTag.ReviewerEmail).Count -gt 0) -Warn
        }
    }
}

Write-Host "`nNote: file-plan-descriptor read-back (Department/Category/SubCategory/Citation/ReferenceId/Authority) is not hard-checked - see this script's .DESCRIPTION and README.md Section 11 (VERIFY)." -ForegroundColor Cyan
Write-Host "$(if ($script:failures -eq 0) { 'All hard checks passed.' } else { "$script:failures hard check(s) failed." })" -ForegroundColor $(if ($script:failures -eq 0) { 'Green' } else { 'Red' })
if ($script:failures -gt 0) { exit 1 }
```