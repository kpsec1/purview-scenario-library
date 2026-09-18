---
part: "deploy"
parent: "records-management/file-plan-bulk-import"
---
The scripts and configuration below deploy this scenario. Review them, then run in order — each is designed to be idempotent and has a matching rollback.


#### `config/file-plan-schedule.sample.csv`

```
LabelName,Comment,Notes,IsRecordLabel,RetentionAction,RetentionDuration,RetentionType,ReviewerEmail,ReferenceId,DepartmentName,Category,SubCategory,AuthorityType,CitationName,CitationUrl,CitationJurisdiction,Regulatory,EventType,IsRecordUnlockedAsDefault,ComplianceTagForNextStage
HR - Personnel Files - 10yr Post-Modification,Personnel file record class - see design.md row 1,This item is a personnel record and is retained for 10 years,TRUE,KeepAndDelete,3653,ModificationAgeInDays,hr-records@contoso.com,HR-001,Human Resources,Personnel Records,Employee Files,Regulatory,Fair Labor Standards Act (FLSA) recordkeeping requirements,https://www.dol.gov/agencies/whd/flsa,U.S. Department of Labor,FALSE,,FALSE,
Finance - Accounts Payable Ledger - 7yr,Financial books-and-records class,This item is a financial record retained for 7 years,TRUE,Keep,2555,CreationAgeInDays,,FIN-001,Finance,Accounts Payable,,Regulatory,Sarbanes-Oxley Act of 2002,https://www.congress.gov/107/plaws/publ204/PLAW-107publ204.pdf,U.S. Securities and Exchange Commission (SEC),FALSE,,FALSE,
Finance - Corporate Tax Filings - 7yr,Tax records class,This item is a tax record retained for 7 years,TRUE,KeepAndDelete,2555,CreationAgeInDays,finance-records@contoso.com,FIN-002,Finance,Tax,Corporate Tax,Regulatory,Internal Revenue Code Section 6001,https://www.irs.gov/irm/part4/irm_04-010-002,U.S. Internal Revenue Service (IRS),FALSE,,FALSE,
Legal - Executed Contracts - 7yr Post-Signature,Contract records class (creation-age variant - the event-anchored variant is the sibling records-disposition scenario),This item is a contract record retained for 7 years,TRUE,Keep,2555,CreationAgeInDays,,LEGAL-001,Legal,Contracts,Executed Agreements,Business,,,,FALSE,,FALSE,
Legal - Active Litigation Holds - Keep Indefinitely,Litigation-hold record class - no disposal until outside counsel releases the matter,This item is retained indefinitely pending litigation,TRUE,Keep,Unlimited,ModificationAgeInDays,,LEGAL-002,Legal,Litigation,,Business,,,,FALSE,,FALSE,
IT - Security Incident Records - 3yr,Security operations record class,This item is retained for 3 years for incident post-mortems,FALSE,Keep,1095,CreationAgeInDays,,IT-001,Information Technology,Security,Incident Response,Internal Policy,,,,FALSE,,FALSE,
IT - Access Control Change Logs - 1yr,Non-record operational retention (not a declared record),This item is deleted automatically after 1 year,FALSE,Delete,365,ModificationAgeInDays,,IT-002,Information Technology,Access Management,,Internal Policy,,,,FALSE,,FALSE,
Sales - Signed Customer Order Forms - 6yr,Contract-adjacent commercial record class,This item is a sales record retained for 6 years,TRUE,Keep,2190,CreationAgeInDays,,SALES-001,Sales,Customer Contracts,,Business,,,,FALSE,,FALSE,
Marketing - Campaign Creative Assets - 2yr,Non-record marketing collateral,This item is deleted automatically after 2 years,FALSE,Delete,730,CreationAgeInDays,,MKT-001,Marketing,Campaign Assets,,Internal Policy,,,,FALSE,,FALSE,
Compliance - Regulatory Correspondence - 10yr Review,Regulator correspondence record class - disposition reviewed,This item is reviewed before disposal after 10 years,TRUE,KeepAndDelete,3653,CreationAgeInDays,compliance-records@contoso.com,COMP-001,Compliance,Regulatory Correspondence,,Regulatory,,,,FALSE,,FALSE,
```

#### `FilePlanRow.Validate.ps1`

```powershell
#Requires -Version 7.0
<#
.SYNOPSIS
    Shared, dot-sourced validation logic for a single file-plan-import row, reproducing every
    documented rule from "Import retention labels into your file plan" so a bad row is caught
    locally instead of on tenant upload/creation.

.DESCRIPTION
    Dot-sourced by New-FilePlanImportCsv.ps1, New-FilePlanBulkLabels.ps1, and
    validate/Test-FilePlanBulkImport.ps1 so the three scripts can never drift on what counts as a
    valid row. Exposes Test-FilePlanRow, which returns hard Errors (the row cannot be imported /
    created as-is) and soft Warnings (accepted, but worth a second look) - never mutates anything
    and never calls a network/tenant cmdlet itself; callers pass in the results of any live
    Get-* lookups (LabelName collision, EventType existence) they already performed.

.NOTES
    Grounded in Microsoft Learn (verify before production use):
    - Import retention labels into your file plan (property table: required-ness, valid values,
      group dependencies, max lengths, LabelName character set, "not supported for import: multi-
      stage disposition review"):
      https://learn.microsoft.com/purview/file-plan-manager#import-retention-labels-into-your-file-plan
    - New-ComplianceTag (RetentionAction/RetentionDuration/RetentionType/ReviewerEmail valid values
      match the CSV import's, confirmed against both pages):
      https://learn.microsoft.com/powershell/module/exchangepowershell/new-compliancetag
#>

function Test-FilePlanRow {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][PSCustomObject]$Row,
        [Parameter(Mandatory)][int]$RowNumber,
        # Optional live-lookup results the caller already gathered (Test-FilePlanImportCsv.ps1 §-TenantChecks).
        [Nullable[bool]]$LabelNameExistsInTenant = $null,
        [Nullable[bool]]$EventTypeExistsInTenant = $null
    )

    $errors = [System.Collections.Generic.List[string]]::new()
    $warnings = [System.Collections.Generic.List[string]]::new()
    function Get-Cell([string]$Name) {
        if ($Row.PSObject.Properties.Name -contains $Name) { return "$($Row.$Name)".Trim() }
        return ''
    }
    function Test-Bool([string]$Value) { $Value -eq 'TRUE' -or $Value -eq 'FALSE' -or $Value -eq '' }
    function ConvertTo-FpBool([string]$Value) { return $Value -eq 'TRUE' }

    $labelName = Get-Cell 'LabelName'
    $comment = Get-Cell 'Comment'
    $notes = Get-Cell 'Notes'
    $isRecordLabel = Get-Cell 'IsRecordLabel'
    $retentionAction = Get-Cell 'RetentionAction'
    $retentionDuration = Get-Cell 'RetentionDuration'
    $retentionType = Get-Cell 'RetentionType'
    $reviewerEmail = Get-Cell 'ReviewerEmail'
    $regulatory = Get-Cell 'Regulatory'
    $eventType = Get-Cell 'EventType'
    $isRecordUnlockedAsDefault = Get-Cell 'IsRecordUnlockedAsDefault'
    $complianceTagForNextStage = Get-Cell 'ComplianceTagForNextStage'

    # --- LabelName: required, <=64 chars, a-z A-Z 0-9 hyphen space only, unique in file+tenant ---
    if ([string]::IsNullOrWhiteSpace($labelName)) {
        $errors.Add("Row ${RowNumber}: LabelName is required.")
    }
    else {
        if ($labelName.Length -gt 64) { $errors.Add("Row ${RowNumber}: LabelName '$labelName' is $($labelName.Length) characters - maximum is 64.") }
        if ($labelName -notmatch '^[A-Za-z0-9\- ]+$') { $errors.Add("Row ${RowNumber}: LabelName '$labelName' uses unsupported characters - only a-z, A-Z, 0-9, hyphen, and space are supported for import.") }
        if ($LabelNameExistsInTenant -eq $true) { $errors.Add("Row ${RowNumber}: LabelName '$labelName' already exists as a retention label in the tenant - names must be unique.") }
    }

    # --- Comment / Notes: <=1024 chars ---
    if ($comment.Length -gt 1024) { $errors.Add("Row ${RowNumber}: Comment is $($comment.Length) characters - maximum is 1024.") }
    if ($notes.Length -gt 1024) { $errors.Add("Row ${RowNumber}: Notes is $($notes.Length) characters - maximum is 1024.") }

    # --- Boolean-shaped columns must be TRUE, FALSE, or blank (blank = default FALSE) ---
    foreach ($b in @{ IsRecordLabel = $isRecordLabel; Regulatory = $regulatory; IsRecordUnlockedAsDefault = $isRecordUnlockedAsDefault }.GetEnumerator()) {
        if (-not (Test-Bool $b.Value)) { $errors.Add("Row ${RowNumber}: $($b.Key) must be TRUE, FALSE, or blank - found '$($b.Value)'.") }
    }

    # --- The RetentionAction/RetentionDuration/RetentionType group (mutually required as a set) ---
    $retentionGroupTouched = $retentionAction -or $retentionDuration -or $retentionType -or $reviewerEmail -or ($isRecordLabel -ne '')
    if ($retentionGroupTouched) {
        if (-not $retentionAction) { $errors.Add("Row ${RowNumber}: RetentionAction is required once RetentionDuration/RetentionType/ReviewerEmail/IsRecordLabel are specified.") }
        elseif ($retentionAction -notin @('Delete', 'Keep', 'KeepAndDelete')) { $errors.Add("Row ${RowNumber}: RetentionAction '$retentionAction' is invalid - valid values are Delete, Keep, KeepAndDelete.") }
        if (-not $retentionDuration) { $errors.Add("Row ${RowNumber}: RetentionDuration is required once RetentionAction/RetentionType/ReviewerEmail/IsRecordLabel are specified.") }
        elseif ($retentionDuration -ne 'Unlimited') {
            $durInt = 0
            if (-not [int]::TryParse($retentionDuration, [ref]$durInt) -or $durInt -le 0) { $errors.Add("Row ${RowNumber}: RetentionDuration '$retentionDuration' must be 'Unlimited' or a positive integer.") }
            elseif ($durInt -gt 36525) { $errors.Add("Row ${RowNumber}: RetentionDuration $durInt exceeds the maximum of 36525 (100 years) - use 'Unlimited' instead.") }
        }
        if (-not $retentionType) { $errors.Add("Row ${RowNumber}: RetentionType is required once RetentionAction/RetentionDuration/ReviewerEmail/IsRecordLabel are specified.") }
        elseif ($retentionType -notin @('CreationAgeInDays', 'EventAgeInDays', 'TaggedAgeInDays', 'ModificationAgeInDays')) {
            $errors.Add("Row ${RowNumber}: RetentionType '$retentionType' is invalid - valid values are CreationAgeInDays, EventAgeInDays, TaggedAgeInDays, ModificationAgeInDays.")
        }
    }

    # --- ReviewerEmail: only meaningful with RetentionAction=KeepAndDelete ---
    if ($reviewerEmail) {
        if ($retentionAction -ne 'KeepAndDelete') { $errors.Add("Row ${RowNumber}: ReviewerEmail is set but RetentionAction is '$retentionAction' - disposition review requires RetentionAction=KeepAndDelete.") }
        foreach ($addr in ($reviewerEmail -split ';' | Where-Object { $_ })) {
            if ($addr.Trim() -notmatch '^[^@\s]+@[^@\s]+\.[^@\s]+$') { $warnings.Add("Row ${RowNumber}: ReviewerEmail entry '$addr' does not look like a valid SMTP address.") }
        }
    }
    elseif ($retentionAction -eq 'KeepAndDelete') {
        $warnings.Add("Row ${RowNumber}: RetentionAction is KeepAndDelete with no ReviewerEmail - content auto-deletes at end of retention with NO disposition review.")
    }

    # --- EventType: required iff RetentionType=EventAgeInDays; must pre-exist in the tenant ---
    if ($retentionType -eq 'EventAgeInDays' -and -not $eventType) {
        $errors.Add("Row ${RowNumber}: RetentionType is EventAgeInDays but EventType is blank - an event type is required.")
    }
    if ($eventType -and $retentionType -ne 'EventAgeInDays') {
        $warnings.Add("Row ${RowNumber}: EventType '$eventType' is set but RetentionType is '$retentionType', not EventAgeInDays - EventType will be ignored.")
    }
    if ($eventType -and $EventTypeExistsInTenant -eq $false) {
        $errors.Add("Row ${RowNumber}: EventType '$eventType' does not exist in the tenant (Records Management > Events > Manage event types) - it must be created before this row can import/deploy.")
    }

    # --- Regulatory / IsRecordUnlockedAsDefault / ComplianceTagForNextStage interactions ---
    $isRecord = ConvertTo-FpBool $isRecordLabel
    $isRegulatory = ConvertTo-FpBool $regulatory
    $isUnlockedDefault = ConvertTo-FpBool $isRecordUnlockedAsDefault
    if ($isRegulatory -and -not $isRecord) { $errors.Add("Row ${RowNumber}: Regulatory=TRUE requires IsRecordLabel=TRUE.") }
    if ($isRegulatory) { $warnings.Add("Row ${RowNumber}: Regulatory=TRUE - this also requires the tenant be configured to display the regulatory-record option, or import validation fails. VERIFY this tenant setting before uploading/deploying.") }
    if ($isUnlockedDefault -and -not $isRecord) { $errors.Add("Row ${RowNumber}: IsRecordUnlockedAsDefault=TRUE requires IsRecordLabel=TRUE.") }
    if ($isUnlockedDefault -and $isRegulatory) { $errors.Add("Row ${RowNumber}: IsRecordUnlockedAsDefault=TRUE is not allowed when Regulatory=TRUE.") }
    if ($complianceTagForNextStage -and $isRegulatory) { $errors.Add("Row ${RowNumber}: ComplianceTagForNextStage must not be set when Regulatory=TRUE.") }

    # --- CSV/formula-injection guard (not a Microsoft-documented rule - a general defensive control).
    # The workflow this scenario documents has a human open the generated CSV in a spreadsheet app
    # before uploading it (README.md Section 5); a free-text cell starting with =, +, -, or @ can
    # execute as a formula there (the classic OWASP "CSV injection" vector). Free-text columns only -
    # not the enum/numeric columns, which are already constrained above.
    foreach ($col in 'Comment', 'Notes', 'ReferenceId', 'DepartmentName', 'Category', 'SubCategory', 'AuthorityType', 'CitationName', 'CitationUrl', 'CitationJurisdiction') {
        $val = Get-Cell $col
        if ($val -and $val.Length -gt 0 -and $val[0] -in @('=', '+', '-', '@')) {
            $errors.Add("Row ${RowNumber}: $col starts with '$($val[0])' - refused as a possible CSV/formula-injection payload if this file is opened in a spreadsheet app. Prefix with a space or apostrophe if the leading character is intentional.")
        }
        if ($val -match "[`t`r`n]") {
            $errors.Add("Row ${RowNumber}: $col contains a raw tab/CR/LF character - not supported for import and a possible CSV-structure-injection vector.")
        }
    }

    return [PSCustomObject]@{
        RowNumber = $RowNumber
        LabelName = $labelName
        IsValid   = ($errors.Count -eq 0)
        Errors    = $errors
        Warnings  = $warnings
    }
}
```

#### `New-FilePlanBulkLabels.ps1`

```powershell
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
```

#### `New-FilePlanImportCsv.ps1`

```powershell
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
```

#### `Remove-FilePlanBulkLabels.ps1`

```powershell
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
```