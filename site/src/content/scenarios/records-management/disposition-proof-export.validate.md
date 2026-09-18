---
part: "validate"
parent: "records-management/disposition-proof-export"
---
Run these checks after deployment to confirm the control is working as designed.


#### `Test-DispositionProofExport.ps1`

```powershell
#Requires -Modules @{ ModuleName = 'ExchangeOnlineManagement'; ModuleVersion = '3.2.0' }
<#
.SYNOPSIS
    Checks whether disposition-review and record-deletion evidence is reachable in the unified
    audit log within a lookback window, and, if given a rolling CSV, checks that CSV's structural
    integrity. Reports evidence found/not found -- never a definitive "disposition happened or
    didn't" verdict.

.DESCRIPTION
    Read-only. Runs the same seven-Operation, no-RecordType-filter query as deploy/
    Export-DispositionProofEvidence.ps1 (design.md Section 2) and reports counts per Operation:
    AddReviewer, ApproveDisposal, ExtendRetention, RelabelItem (Disposition review activities);
    RecordDelete (File and page activities, "Deleted file marked as a record"); and LockRecord/
    UnlockRecord (File and page activities, record-lock status changes -- context added per
    reviews.md Red Team finding 2, surfaced but not itself asserted PASS/FAIL).

    This is deliberately reported as [PASS]/[INCONCLUSIVE] for the "evidence found" check, never
    [PASS]/[FAIL]: a zero-row result is equally consistent with (a) no retention label in the
    tenant having reached the end of its period yet, (b) a review-free regulatory-record label with
    no disposition-review Operations to emit at all (only RecordDelete would fire for that case),
    or (c) auditing not having been enabled at least one day before the first disposition action,
    which Microsoft states is a prerequisite for these events to be captured at all (README.md
    Section 3). Asserting [FAIL] on a zero-row result would overclaim certainty this script cannot
    have -- see README.md Section 7/11.

    If -CsvPath is supplied (the output of deploy/Export-DispositionProofEvidence.ps1), this script
    additionally validates the file's structural integrity as evidence: every row has a
    non-empty CompositeKey, no CompositeKey repeats (the de-duplication the deploy script's merge
    logic depends on), CreationDate parses on every row, and the file is sorted by CreationDate
    ascending (the deploy script's own merge/sort invariant) -- these ARE asserted [PASS]/[FAIL],
    because they are checking this script's own deterministic output, not the tenant's activity.

    Safe to re-run; safe to schedule (README.md Section 8 recommends running alongside deploy/
    Export-DispositionProofEvidence.ps1). Exits non-zero only on a hard infrastructure failure (no
    Exchange Online session) or a CSV structural-integrity failure -- never on a zero-evidence
    window, which is expected, common, and not itself a failure.

.PARAMETER LookbackDays
    How many days back to search for disposition-proof evidence. Defaults to 30 -- long enough to
    smooth over an infrequent disposition cadence (most retention periods are measured in years, so
    reviewer action clusters around whenever labels happen to expire) without requiring daily manual
    review, short enough to stay well inside the 180-day Standard Audit retention default (see
    deploy/Export-DispositionProofEvidence.ps1's own .NOTES).

.PARAMETER CsvPath
    Optional path to the rolling CSV produced by deploy/Export-DispositionProofEvidence.ps1. When
    supplied, the file's structural integrity is checked in addition to the live audit-log query.
    Omit to run only the live query.

.EXAMPLE
    Connect-ExchangeOnline -AppId $AppId -Certificate $Cert -Organization 'contoso.onmicrosoft.com'
    ./Test-DispositionProofExport.ps1

.EXAMPLE
    ./Test-DispositionProofExport.ps1 -LookbackDays 365 -CsvPath './out/disposition-proof.csv'

    Widens the live check to a full year and also validates the rolling evidence file's integrity --
    useful before handing the CSV to an auditor or examiner.
#>
[CmdletBinding()]
param(
    [Parameter()]
    [ValidateRange(1, 3650)]
    [int]$LookbackDays = 30,

    [Parameter()]
    [string]$CsvPath
)

$ErrorActionPreference = 'Stop'
$script:failures = 0
function Test-Check {
    param([string]$Description, [bool]$Condition, [switch]$Inconclusive)
    if ($Condition) { Write-Host "  [PASS] $Description" -ForegroundColor Green }
    elseif ($Inconclusive) { Write-Host "  [INCONCLUSIVE] $Description" -ForegroundColor Yellow }
    else { Write-Host "  [FAIL] $Description" -ForegroundColor Red; $script:failures++ }
}

if (-not (Get-Command Search-UnifiedAuditLog -ErrorAction SilentlyContinue)) {
    throw 'No Exchange Online PowerShell session found. Run Connect-ExchangeOnline first (see docs/automation-surface.md). The connecting identity also needs the View-Only Audit Logs or Audit Logs Exchange Online role - this is a DIFFERENT role than Disposition Management, which only governs the portal Disposition page (README.md Section 3, rbac-model.md Section 6).'
}

$startDate = ([datetime]::UtcNow.AddDays(-$LookbackDays))
$endDate = ([datetime]::UtcNow)
$dispositionReviewOps = @('AddReviewer', 'ApproveDisposal', 'ExtendRetention', 'RelabelItem')
$recordDeleteOp = 'RecordDelete'
$recordLockOps = @('LockRecord', 'UnlockRecord')
$operations = $dispositionReviewOps + $recordDeleteOp + $recordLockOps

Write-Host "Checking for disposition-proof evidence in the unified audit log, last $LookbackDays day(s) ($startDate to $endDate, UTC)..." -ForegroundColor Cyan

$records = @(Search-UnifiedAuditLog -StartDate $startDate -EndDate $endDate -Operations $operations -ResultSize 5000)

$counts = @{}
foreach ($op in $operations) {
    $counts[$op] = @($records | Where-Object { $_.Operations -eq $op }).Count
}
$dispositionReviewCount = ($dispositionReviewOps | ForEach-Object { $counts[$_] } | Measure-Object -Sum).Sum
$recordDeleteCount = $counts[$recordDeleteOp]

$unlockCount = $counts['UnlockRecord']
$lockCount = $counts['LockRecord']

Write-Host "Found $($records.Count) total event(s): $dispositionReviewCount disposition-review action(s) [AddReviewer=$($counts['AddReviewer']), ApproveDisposal=$($counts['ApproveDisposal']), ExtendRetention=$($counts['ExtendRetention']), RelabelItem=$($counts['RelabelItem'])], $recordDeleteCount record-deletion event(s) [RecordDelete], $lockCount lock/$unlockCount unlock event(s) [LockRecord/UnlockRecord]." -ForegroundColor Cyan

if ($records.Count -gt 0) {
    Test-Check -Description "Disposition-proof evidence found in the last $LookbackDays day(s) - at least one disposition-review action or record deletion has visibly occurred" -Condition $true
    $mostRecent = $records | Sort-Object CreationDate -Descending | Select-Object -First 1
    Write-Host "  Most recent event: $($mostRecent.CreationDate) UTC, user=$($mostRecent.UserIds), operation=$($mostRecent.Operations)" -ForegroundColor Cyan
    if ($counts['ApproveDisposal'] -gt 0 -and $recordDeleteCount -eq 0) {
        Write-Host "  NOTE: $($counts['ApproveDisposal']) ApproveDisposal event(s) with zero RecordDelete events in this window. ApproveDisposal on an interim stage moves an item to the NEXT stage rather than deleting it (README.md Section 6) - this is expected for a multi-stage reviewer chain, not necessarily a gap. Widen -LookbackDays or check scenarios/records-management/multi-stage-disposition-review/ if a final-stage approval was expected to have completed by now." -ForegroundColor Yellow
    }
    if ($unlockCount -gt 0 -and $recordDeleteCount -eq 0) {
        Write-Host "  NOTE: $unlockCount UnlockRecord event(s) with zero RecordDelete events in this window. An unlock with no follow-on deletion is not itself suspicious (a record can be unlocked for reasons other than disposal), but is worth cross-checking against README.md Section 8's out-of-process-deletion pattern if a delete was expected shortly after." -ForegroundColor Yellow
    }
}
else {
    Test-Check -Description "No disposition-proof evidence found in the last $LookbackDays day(s)" -Condition $false -Inconclusive
    Write-Host '  This does NOT confirm no disposition activity occurred, and it does NOT confirm auditing is misconfigured. A zero-row result is equally consistent with no label in the tenant having reached the end of its retention period yet, a review-free regulatory-record label with nothing pending review, or auditing having been enabled less than one day before the activity you expected (README.md Section 3/11). Cross-check the portal directly: Records Management -> Disposition (README.md Section 5).' -ForegroundColor Yellow
}

if ($CsvPath) {
    Write-Host "`nChecking structural integrity of rolling evidence file '$CsvPath'..." -ForegroundColor Cyan
    if (-not (Test-Path -Path $CsvPath -PathType Leaf)) {
        Test-Check -Description "Evidence file exists at '$CsvPath'" -Condition $false
    }
    else {
        Test-Check -Description "Evidence file exists at '$CsvPath'" -Condition $true
        $rows = @(Import-Csv -Path $CsvPath)
        Write-Host "  $($rows.Count) row(s) in evidence file." -ForegroundColor Cyan

        $emptyKeyCount = @($rows | Where-Object { [string]::IsNullOrWhiteSpace($_.CompositeKey) }).Count
        Test-Check -Description 'Every row has a non-empty CompositeKey' -Condition ($emptyKeyCount -eq 0)
        if ($emptyKeyCount -gt 0) { Write-Host "    $emptyKeyCount row(s) with an empty CompositeKey." -ForegroundColor Red }

        $duplicateKeyCount = ($rows | Group-Object CompositeKey | Where-Object { $_.Count -gt 1 }).Count
        Test-Check -Description 'No CompositeKey value repeats (de-duplication integrity)' -Condition ($duplicateKeyCount -eq 0)
        if ($duplicateKeyCount -gt 0) { Write-Host "    $duplicateKeyCount duplicate CompositeKey value(s) - the deploy script's merge logic should never produce this; investigate before trusting the file's row count as a true event count." -ForegroundColor Red }

        $unparseableDateCount = @($rows | Where-Object { -not [datetime]::TryParse($_.CreationDate, [ref]([datetime]::MinValue)) }).Count
        Test-Check -Description 'Every row has a parseable CreationDate' -Condition ($unparseableDateCount -eq 0)
        if ($unparseableDateCount -gt 0) { Write-Host "    $unparseableDateCount row(s) with an unparseable CreationDate." -ForegroundColor Red }

        if ($rows.Count -gt 1 -and $unparseableDateCount -eq 0) {
            $dates = $rows | ForEach-Object { [datetime]::Parse($_.CreationDate) }
            $sortedAscending = $true
            for ($i = 1; $i -lt $dates.Count; $i++) {
                if ($dates[$i] -lt $dates[$i - 1]) { $sortedAscending = $false; break }
            }
            Test-Check -Description 'File is sorted by CreationDate ascending (deploy script merge invariant)' -Condition $sortedAscending
        }
    }
}
else {
    Write-Host "`n(No -CsvPath supplied - skipping rolling-evidence-file integrity checks.)" -ForegroundColor DarkGray
}

Write-Host "`nResult: $($script:failures) hard failure(s)." -ForegroundColor $(if ($script:failures -eq 0) { 'Green' } else { 'Red' })
if ($script:failures -gt 0) { exit 1 }
```