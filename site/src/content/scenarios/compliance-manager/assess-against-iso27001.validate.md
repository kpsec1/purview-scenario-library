---
part: "validate"
parent: "compliance-manager/assess-against-iso27001"
---
Run these checks after deployment to confirm the control is working as designed.


#### `Test-ComplianceManagerAuditTrail.ps1`

```powershell
#Requires -Version 7.0
<#
.SYNOPSIS
    Validates the audit-trail CSV this scenario's deploy script produces, and prints a manual
    verification checklist for the assessment itself, which has no read API to check programmatically.

.DESCRIPTION
    Two categories of check, clearly separated in the output:

    1. AUTOMATED (hard pass/fail, contributes to exit code) - read-only, no tenant connection
       needed:
       - The CSV has the expected columns and at least the header (an empty file with zero data
         rows is not itself a failure - it means no matching audit events occurred in every
         window run so far, which is the expected common case).
       - No duplicate CompositeKey rows - proof the deploy script's merge-and-de-duplicate design
         (design.md Section 8) is actually holding across re-runs, not silently accumulating
         duplicates on every overlapping-window run.
       - Every row's Operation value is one of the three documented Compliance Manager operations
         (design.md Section 4) - catches a scenario where the CSV was hand-edited or produced by a
         different script by mistake.
       - CreationDate values parse as valid timestamps and are monotonically non-decreasing after
         the deploy script's own Sort-Object (a stronger check than "is a date" - proves the file
         wasn't reordered or corrupted by an external edit).

    2. MANUAL (printed as a checklist, never fails the script) - the assessment's existence,
       scope, group, and role assignments, none of which have a documented read API (design.md
       Section 2). This is not a gap in this script - it is Compliance Manager's current product
       surface.

    Exits non-zero only if an AUTOMATED check hard-fails. Safe to re-run any number of times; makes
    no mutating calls and needs no tenant connection at all for category 1.

.PARAMETER AuditTrailCsvPath
    Path to the CSV produced by deploy/Export-ComplianceManagerAuditTrail.ps1.

.PARAMETER AssessmentName
    Display name used for the manual-checklist output only (no API call is made against it - see
    design.md Section 2 for why no such call exists). Defaults to the name used throughout this
    scenario's docs and deploy/policy/iso27001-assessment-manifest.json.

.EXAMPLE
    ./Test-ComplianceManagerAuditTrail.ps1 -AuditTrailCsvPath '../deploy/out/compliance-manager-audit-trail.csv'

.NOTES
    A CSV with zero data rows is expected and healthy the first time this scenario is deployed in a
    quiet tenant - it means no Compliance Manager role or automation-trust changes have occurred in
    the queried window, not that the deploy script is broken. Re-run deploy/
    Export-ComplianceManagerAuditTrail.ps1 with a wider -StartDate to confirm the query itself
    works if this is unexpected.

    Sources: see deploy/Export-ComplianceManagerAuditTrail.ps1 .NOTES for the Microsoft Learn
    references this scenario's grounding rests on.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$AuditTrailCsvPath,

    [Parameter()]
    [string]$AssessmentName = 'ISO/IEC 27001:2022 - Microsoft 365 Estate'
)

$ErrorActionPreference = 'Stop'
$script:failures = 0

function Test-Check {
    param([string]$Description, [bool]$Condition, [switch]$Warn)
    if ($Condition) {
        Write-Host "  [PASS] $Description" -ForegroundColor Green
    }
    elseif ($Warn) {
        Write-Host "  [WARN] $Description" -ForegroundColor Yellow
    }
    else {
        Write-Host "  [FAIL] $Description" -ForegroundColor Red
        $script:failures++
    }
}

Write-Host "=== AUTOMATED CHECKS: $AuditTrailCsvPath ===" -ForegroundColor Cyan

Test-Check -Description "File exists at -AuditTrailCsvPath" -Condition (Test-Path -Path $AuditTrailCsvPath -PathType Leaf)
if (-not (Test-Path -Path $AuditTrailCsvPath -PathType Leaf)) {
    Write-Host "`nCannot continue - file not found. Run deploy/Export-ComplianceManagerAuditTrail.ps1 first." -ForegroundColor Red
    exit 1
}

$rows = @(Import-Csv -Path $AuditTrailCsvPath)

$requiredColumns = 'CreationDate', 'Operation', 'UserIds', 'RecordType', 'AuditDataObjectId', 'AuditData', 'CompositeKey'
$actualColumns = if ($rows.Count -gt 0) {
    (Import-Csv -Path $AuditTrailCsvPath | Select-Object -First 1).PSObject.Properties.Name
} else {
    (Get-Content -Path $AuditTrailCsvPath -TotalCount 1) -split ','
}
foreach ($column in $requiredColumns) {
    Test-Check -Description "Column '$column' present" -Condition ($actualColumns -contains $column)
}

if ($rows.Count -eq 0) {
    Write-Host "  [PASS] File contains a header with no data rows - healthy if no Compliance Manager role/automation-level changes occurred in the queried window(s) so far." -ForegroundColor Green
}
else {
    $duplicateKeys = $rows | Group-Object CompositeKey | Where-Object { $_.Count -gt 1 }
    Test-Check -Description "No duplicate CompositeKey rows (de-duplication merge is holding)" -Condition ($duplicateKeys.Count -eq 0)
    if ($duplicateKeys.Count -gt 0) {
        Write-Host "         Duplicate keys: $($duplicateKeys.Name -join '; ')" -ForegroundColor Yellow
    }

    $validOperations = 'ComplianceManagerRolesChange', 'ComplianceManagerAutomationLevelChange', 'ComplianceManagerAutomationChange'
    $invalidOperationRows = $rows | Where-Object { $_.Operation -notin $validOperations }
    Test-Check -Description "Every row's Operation is one of the 3 documented Compliance Manager operations" -Condition ($invalidOperationRows.Count -eq 0)
    if ($invalidOperationRows.Count -gt 0) {
        Write-Host "         Unexpected operation value(s): $(($invalidOperationRows.Operation | Select-Object -Unique) -join ', ')" -ForegroundColor Yellow
    }

    $parsedDates = foreach ($row in $rows) {
        $parsed = $null
        $ok = [datetime]::TryParse($row.CreationDate, [ref]$parsed)
        [pscustomobject]@{ Raw = $row.CreationDate; Parsed = $parsed; Ok = $ok }
    }
    Test-Check -Description "Every CreationDate value parses as a valid timestamp" -Condition (($parsedDates | Where-Object { -not $_.Ok }).Count -eq 0)

    $sortedCheck = $true
    for ($i = 1; $i -lt $parsedDates.Count; $i++) {
        if ($parsedDates[$i].Parsed -lt $parsedDates[$i - 1].Parsed) { $sortedCheck = $false; break }
    }
    Test-Check -Description "CreationDate values are non-decreasing (file wasn't reordered/corrupted after the deploy script's own sort)" -Condition $sortedCheck

    $automationChanges = @($rows | Where-Object { $_.Operation -match 'AutomationLevel|AutomationChange' })
    if ($automationChanges.Count -gt 0) {
        Write-Host "  [WARN] $($automationChanges.Count) automation-trust change event(s) present in this file - review each per README.md Section 8 incident-response guidance, do not treat their mere presence as a failure of this script." -ForegroundColor Yellow
    }
}

Write-Host "`n=== MANUAL VERIFICATION CHECKLIST (no read API exists to automate these - design.md Section 2) ===" -ForegroundColor Cyan
$manualChecklist = @(
    "Purview portal > Compliance Manager > Assessments: an assessment named '$AssessmentName' exists, based on the ISO/IEC 27001:2022 regulation, with status other than blank/None (i.e. at least one control has been tested)."
    "Assessment's Services tab shows Microsoft 365 in scope, matching deploy/policy/iso27001-assessment-manifest.json's servicesInScope."
    "Assessment belongs to the group named in deploy/policy/iso27001-assessment-manifest.json's group.name - confirm before adding further assessments to it, since group membership can't be changed later."
    "Compliance Manager > Settings > User access (or the assessment's own Manage user access pane): role assignments match deploy/policy/iso27001-assessment-manifest.json's roleAssignments - no one holds Administration who only needs Assessor/Reader."
    "Compliance Manager > Improvement actions, filtered to this assessment: spot-check that at least some actions show a 'Passed'/tested status sourced from built-in automation (design.md Section 6), confirming already-deployed DLP/Information Protection/IRM scenarios are actually feeding this assessment."
    "If this file shows 0 automation-trust-change events but Compliance Manager > Settings shows an unexpected automation level: the audit window may predate the change, or Audit (Standard)'s 180-day retention has already expired it (README.md Section 11) - do not assume 'no events in this file' means 'no changes ever happened.'"
)
$manualChecklist | ForEach-Object { Write-Host "  [ ] $_" -ForegroundColor Yellow }

Write-Host "`n$(if ($script:failures -eq 0) { 'All automated checks passed.' } else { "$script:failures automated check(s) failed." }) Manual checklist above still requires a human to confirm in the portal." `
    -ForegroundColor $(if ($script:failures -eq 0) { 'Green' } else { 'Red' })

if ($script:failures -gt 0) { exit 1 }
```