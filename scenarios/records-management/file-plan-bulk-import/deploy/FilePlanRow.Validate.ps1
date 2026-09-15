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
