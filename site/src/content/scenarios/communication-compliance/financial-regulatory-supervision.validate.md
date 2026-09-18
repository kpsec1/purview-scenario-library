---
part: "validate"
parent: "communication-compliance/financial-regulatory-supervision"
---
Run these checks after deployment to confirm the control is working as designed.


#### `Test-FinraSupervisionEvidence.ps1`

```powershell
#Requires -Version 7.0
<#
.SYNOPSIS
    Validates the audit-trail and FINRA 3110(b)(4) evidence-of-review CSVs this scenario's deploy
    script produces, and prints a manual verification checklist for the policy itself, which has no
    read API to check programmatically.

.DESCRIPTION
    Two categories of check, clearly separated in the output:

    1. AUTOMATED (hard pass/fail, contributes to exit code) - read-only, no tenant connection
       needed:
       - Both CSVs have the expected columns and at least a header row.
       - No duplicate CompositeKey rows in either file (proof the deploy script's merge-and-
         de-duplicate design - design.md Section 8 - is holding across re-runs).
       - Audit-trail CSV: every row's Category is one of the three documented query categories, and
         every row's Operation is one of the five documented Communication Compliance operations.
       - Evidence-of-review CSV: every row has a non-empty Reviewer and ReviewDate, and flags (as a
         WARN, not a FAIL - this is a documented, disclosed gap, not a script defect) any row whose
         ActionTaken still carries the "UNCONFIRMED" marker the deploy script emits when none of its
         candidate AuditData property names matched (README.md Section 11).
       - CreationDate/ReviewDate values parse as valid timestamps and are monotonically
         non-decreasing after the deploy script's own Sort-Object.

    2. MANUAL (printed as a checklist, never fails the script) - the policy's existence, population
       scope, classifiers, reviewers' FINRA-registration status, and WSP alignment, none of which have
       a documented read API (design.md Section 2) or are things Purview itself can attest to
       (FINRA registration status - design.md Section 6).

    Exits non-zero only if an AUTOMATED check hard-fails. Safe to re-run any number of times; makes no
    mutating calls and needs no tenant connection at all.

.PARAMETER AuditTrailCsvPath
    Path to the CSV produced by deploy/Export-FinraSupervisionEvidence.ps1's -AuditTrailCsvPath.

.PARAMETER EvidenceOfReviewCsvPath
    Path to the CSV produced by deploy/Export-FinraSupervisionEvidence.ps1's -EvidenceOfReviewCsvPath.

.PARAMETER PolicyName
    Display name used for the manual-checklist output only (no API call is made against it - design.md
    Section 2). Defaults to the name used throughout this scenario's docs and
    deploy/policy/financial-regulatory-supervision-manifest.json.

.EXAMPLE
    ./Test-FinraSupervisionEvidence.ps1 `
        -AuditTrailCsvPath '../deploy/out/finra-audit-trail.csv' `
        -EvidenceOfReviewCsvPath '../deploy/out/finra-evidence-of-review.csv'

.NOTES
    Both CSVs having zero data rows is expected and healthy the first time this scenario is deployed
    in a quiet tenant, or immediately after deployment before the ~1 hour policy-activation window
    (README.md Section 11) has elapsed - it does not mean the deploy script is broken.

    Sources: see deploy/Export-FinraSupervisionEvidence.ps1's .NOTES for the grounding references.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$AuditTrailCsvPath,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$EvidenceOfReviewCsvPath,

    [Parameter()]
    [string]$PolicyName = 'Financial Regulatory Compliance Supervision - Registered Representatives'
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

function Test-CsvFile {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string[]]$RequiredColumns,
        [Parameter(Mandatory)][string]$Label
    )
    Write-Host "=== AUTOMATED CHECKS: $Label ($Path) ===" -ForegroundColor Cyan
    Test-Check -Description "File exists at $Path" -Condition (Test-Path -Path $Path -PathType Leaf)
    if (-not (Test-Path -Path $Path -PathType Leaf)) {
        Write-Host "  Cannot continue checks for this file - not found. Run deploy/Export-FinraSupervisionEvidence.ps1 first.`n" -ForegroundColor Red
        return @()
    }

    $rows = @(Import-Csv -Path $Path)
    $actualColumns = if ($rows.Count -gt 0) {
        $rows[0].PSObject.Properties.Name
    } else {
        (Get-Content -Path $Path -TotalCount 1) -split ','
    }
    foreach ($column in $RequiredColumns) {
        Test-Check -Description "Column '$column' present" -Condition ($actualColumns -contains $column)
    }

    if ($rows.Count -eq 0) {
        Write-Host "  [PASS] File contains a header with no data rows - healthy if no matching events occurred in the queried window(s) so far." -ForegroundColor Green
    }
    else {
        $duplicateKeys = $rows | Group-Object CompositeKey | Where-Object { $_.Count -gt 1 }
        Test-Check -Description "No duplicate CompositeKey rows (de-duplication merge is holding)" -Condition ($duplicateKeys.Count -eq 0)
        if ($duplicateKeys.Count -gt 0) {
            Write-Host "         Duplicate keys: $($duplicateKeys.Name -join '; ')" -ForegroundColor Yellow
        }
    }
    Write-Host ''
    return $rows
}

$auditRows = Test-CsvFile -Path $AuditTrailCsvPath `
    -RequiredColumns @('CreationDate', 'Category', 'Operation', 'UserIds', 'RecordType', 'AuditData', 'CompositeKey') `
    -Label 'Audit trail'

if (@($auditRows).Count -gt 0) {
    Write-Host "=== Audit-trail content checks ===" -ForegroundColor Cyan
    $validCategories = 'PolicyMatch', 'PolicyUpdate', 'ReviewTag'
    $invalidCategoryRows = @($auditRows | Where-Object { $_.Category -notin $validCategories })
    Test-Check -Description "Every row's Category is one of the 3 documented query categories" -Condition ($invalidCategoryRows.Count -eq 0)

    $validOperations = 'SupervisionRuleMatch', 'SupervisionPolicyCreated', 'SupervisionPolicyUpdated', 'SupervisionPolicyDeleted', 'SupervisoryReviewTag'
    $invalidOperationRows = @($auditRows | Where-Object { $_.Operation -notin $validOperations })
    Test-Check -Description "Every row's Operation is one of the 5 documented Communication Compliance operations" -Condition ($invalidOperationRows.Count -eq 0)
    if ($invalidOperationRows.Count -gt 0) {
        Write-Host "         Unexpected operation value(s): $(($invalidOperationRows.Operation | Select-Object -Unique) -join ', ')" -ForegroundColor Yellow
    }

    $parsedDates = foreach ($row in $auditRows) {
        $parsed = $null
        $ok = [datetime]::TryParse($row.CreationDate, [ref]$parsed)
        [pscustomobject]@{ Parsed = $parsed; Ok = $ok }
    }
    Test-Check -Description "Every CreationDate value parses as a valid timestamp" -Condition (@($parsedDates | Where-Object { -not $_.Ok }).Count -eq 0)

    $sortedCheck = $true
    for ($i = 1; $i -lt $parsedDates.Count; $i++) {
        if ($parsedDates[$i].Parsed -lt $parsedDates[$i - 1].Parsed) { $sortedCheck = $false; break }
    }
    Test-Check -Description "CreationDate values are non-decreasing (file wasn't reordered/corrupted after the deploy script's own sort)" -Condition $sortedCheck

    $policyUpdateCount = @($auditRows | Where-Object { $_.Category -eq 'PolicyUpdate' }).Count
    if ($policyUpdateCount -gt 0) {
        Write-Host "  [WARN] $policyUpdateCount policy-change event(s) present - review each per README.md Section 8, and confirm the firm's WSPs still describe the policy accurately (README.md Section 5 step 11)." -ForegroundColor Yellow
    }
    Write-Host ''
}

$evidenceRows = Test-CsvFile -Path $EvidenceOfReviewCsvPath `
    -RequiredColumns @('Reviewer', 'ReviewDate', 'ContentReference', 'ActionTaken', 'AuditData', 'CompositeKey') `
    -Label 'FINRA 3110(b)(4) evidence-of-review'

if (@($evidenceRows).Count -gt 0) {
    Write-Host "=== Evidence-of-review content checks (FINRA Rule 3110(b)(4)'s four required elements) ===" -ForegroundColor Cyan
    $missingReviewer = @($evidenceRows | Where-Object { [string]::IsNullOrWhiteSpace($_.Reviewer) })
    Test-Check -Description "Every row has a non-empty Reviewer (element 1 of 4)" -Condition ($missingReviewer.Count -eq 0)

    $parsedReviewDates = foreach ($row in $evidenceRows) {
        $parsed = $null
        $ok = [datetime]::TryParse($row.ReviewDate, [ref]$parsed)
        [pscustomobject]@{ Ok = $ok }
    }
    Test-Check -Description "Every row has a valid ReviewDate (element 3 of 4)" -Condition (@($parsedReviewDates | Where-Object { -not $_.Ok }).Count -eq 0)

    $missingContentRef = @($evidenceRows | Where-Object { [string]::IsNullOrWhiteSpace($_.ContentReference) })
    Test-Check -Description "Every row has a non-empty ContentReference (element 2 of 4 - see README.md Section 11 for what this reference does and does not contain)" -Condition ($missingContentRef.Count -eq 0)

    $unconfirmedActionRows = @($evidenceRows | Where-Object { $_.ActionTaken -like 'UNCONFIRMED*' })
    Test-Check -Description "Every row's ActionTaken (element 4 of 4) resolved to a recognized AuditData property, not the UNCONFIRMED fallback" `
        -Condition ($unconfirmedActionRows.Count -eq 0) -Warn
    if ($unconfirmedActionRows.Count -gt 0) {
        Write-Host "         $($unconfirmedActionRows.Count) row(s) fell back to the raw-AuditData UNCONFIRMED marker - this is a disclosed, tracked gap (README.md Section 11, deploy script .NOTES), not a script defect. Update `$actionPropertyCandidates` in the deploy script once the real property name is confirmed against a pilot tenant." -ForegroundColor Yellow
    }
    Write-Host ''
}

Write-Host "=== MANUAL VERIFICATION CHECKLIST (no read API exists to automate these - design.md Section 2/Section 6) ===" -ForegroundColor Cyan
$manualChecklist = @(
    "Purview portal > Communication Compliance > Policies: a policy named '$PolicyName' exists, status Active (not Paused/Error), scoped to Exchange Online + Microsoft Teams."
    "Policy's Users in scope is the firm's FINRA-registered-representative group/adaptive scope - NOT 'All users' - matching deploy/policy/financial-regulatory-supervision-manifest.json's usersInScope."
    "Policy's conditions include all 7 trainable classifiers (Corporate sabotage, Customer complaints, Gifts & entertainment, Money laundering, [Workplace/Regulatory] collusion, Stock manipulation, Unauthorized disclosure) plus the custom keyword dictionary from deploy/policy/finra-supervision-evasion-phrases.txt."
    "GATING: every named reviewer in Communication Compliance Investigators for this policy separately holds an appropriate FINRA registration (e.g. Series 24 principal) or a documented delegated-review designation under the firm's WSPs - Purview's own RBAC does not verify this (design.md Section 6)."
    "The firm's written supervisory procedures (WSPs) document the review percentage (README.md Section 8), escalation path, and registered-principal assignments this policy actually implements - not left undocumented or inconsistent with the deployed configuration."
    "Settings > Communication Compliance > Privacy tab: 'Show anonymized versions of usernames' is enabled, per the manifest's privacySettings."
    "Policies page: the policy's storage-limit indicator is not approaching 80/90/95% of the 100 GB / 1,000,000-message per-policy limit (README.md Section 11)."
    "If the firm also supervises Bloomberg/ICE Chat/Reuters/Symphony or other third-party messaging: confirm those connectors are configured separately - this scenario does not cover them (README.md Section 11, design.md Section 7)."
    "scenarios/data-lifecycle-management/retention-labels-financial-records/ is deployed alongside this scenario for SEC 17a-4/FINRA 4511 retention of the underlying communications - this scenario's evidence-of-review CSV is not a substitute for that control (README.md Section 8)."
)
$manualChecklist | ForEach-Object { Write-Host "  [ ] $_" -ForegroundColor Yellow }

Write-Host "`n$(if ($script:failures -eq 0) { 'All automated checks passed.' } else { "$script:failures automated check(s) failed." }) Manual checklist above still requires a human to confirm in the portal and against the firm's WSPs." `
    -ForegroundColor $(if ($script:failures -eq 0) { 'Green' } else { 'Red' })

if ($script:failures -gt 0) { exit 1 }
```