#Requires -Version 7.0
<#
.SYNOPSIS
    Validates the audit-trail CSV that deploy/Export-EdiscoveryAuditTrail.ps1 produces.

.DESCRIPTION
    Automated (hard pass/fail, contributes to exit code) checks, read-only and needing no tenant
    connection:
    - The CSV has the expected columns and at least a header row (zero data rows is expected and
      healthy the first time this scenario is deployed, or in any quiet window - it is not itself
      a failure).
    - No duplicate CompositeKey rows - proof the deploy script's merge-and-de-duplicate design is
      actually holding across re-runs.
    - Every row's Category value is one of the 2 documented query categories, and every row's
      Operation value is one of the 9 documented eDiscovery case/hold-policy-lifecycle operations
      (deploy/Export-EdiscoveryAuditTrail.ps1's own .NOTES) - catches a scenario where the CSV was
      hand-edited or produced by a different script by mistake.
    - CreationDate values parse as valid timestamps and are monotonically non-decreasing after the
      deploy script's own Sort-Object.

    Exits non-zero only if an automated check hard-fails. Safe to re-run any number of times; makes
    no mutating calls and needs no tenant connection at all.

.PARAMETER AuditTrailCsvPath
    Path to the CSV produced by deploy/Export-EdiscoveryAuditTrail.ps1.

.EXAMPLE
    ./Test-EdiscoveryAuditTrail.ps1 -AuditTrailCsvPath '../deploy/out/edisc-audit-trail.csv'

.NOTES
    A CSV with zero data rows is expected and healthy immediately after this scenario is deployed
    in a quiet tenant, or before the first weekly scheduled run has had a chance to observe a
    case-close/hold-release action - it does not mean the deploy script is broken.

    This script cannot confirm whether HoldCreated/HoldUpdated/HoldRemoved/HoldRetryDistributionSync
    rows correspond to this scenario's own custodian-scoped hold apply/release actions, or only to
    the separate case-level ediscoveryHoldPolicy object - see
    deploy/Export-EdiscoveryAuditTrail.ps1's own .DESCRIPTION/.NOTES for the open VERIFY.

    Sources: see deploy/Export-EdiscoveryAuditTrail.ps1 .NOTES for the Microsoft Learn references
    this scenario's grounding rests on.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$AuditTrailCsvPath
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
    Write-Host "`nCannot continue - file not found. Run deploy/Export-EdiscoveryAuditTrail.ps1 first." -ForegroundColor Red
    exit 1
}

$rows = @(Import-Csv -Path $AuditTrailCsvPath)

$requiredColumns = 'CreationDate', 'Category', 'Operation', 'RecordType', 'CaseId', 'CaseName', 'ObjectType', 'ObjectName', 'ResultStatus', 'UserIds', 'AuditData', 'CompositeKey'
$actualColumns = if ($rows.Count -gt 0) {
    (Import-Csv -Path $AuditTrailCsvPath | Select-Object -First 1).PSObject.Properties.Name
} else {
    (Get-Content -Path $AuditTrailCsvPath -TotalCount 1) -split ','
}
foreach ($column in $requiredColumns) {
    Test-Check -Description "Column '$column' present" -Condition ($actualColumns -contains $column)
}

if ($rows.Count -eq 0) {
    Write-Host "  [PASS] File contains a header with no data rows - healthy if no case or hold-policy lifecycle events occurred in the queried window(s) so far." -ForegroundColor Green
}
else {
    $duplicateKeys = $rows | Group-Object CompositeKey | Where-Object { $_.Count -gt 1 }
    Test-Check -Description "No duplicate CompositeKey rows (de-duplication merge is holding)" -Condition ($duplicateKeys.Count -eq 0)
    if ($duplicateKeys.Count -gt 0) {
        Write-Host "         Duplicate keys: $($duplicateKeys.Name -join '; ')" -ForegroundColor Yellow
    }

    $validCategories = 'CaseLifecycle', 'HoldPolicyLifecycle'
    $invalidCategoryRows = $rows | Where-Object { $_.Category -notin $validCategories }
    Test-Check -Description "Every row's Category is one of the 2 documented query categories" -Condition ($invalidCategoryRows.Count -eq 0)

    $validOperations = 'CaseAdded', 'CaseUpdated', 'CaseClosed', 'CaseReopened', 'CaseRemoved', 'HoldCreated', 'HoldUpdated', 'HoldRemoved', 'HoldRetryDistributionSync'
    $invalidOperationRows = $rows | Where-Object { $_.Operation -notin $validOperations }
    Test-Check -Description "Every row's Operation is one of the 9 documented eDiscovery lifecycle operations" -Condition ($invalidOperationRows.Count -eq 0)
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

    $caseRemovedCount = @($rows | Where-Object { $_.Operation -eq 'CaseRemoved' }).Count
    if ($caseRemovedCount -gt 0) {
        Write-Host "  [WARN] $caseRemovedCount case-deletion event(s) present in this file - confirm each matches an intended, documented action per rollback.md Stage 4, do not treat their mere presence as a failure of this script." -ForegroundColor Yellow
    }

    $holdRemovedCount = @($rows | Where-Object { $_.Operation -eq 'HoldRemoved' }).Count
    if ($holdRemovedCount -gt 0) {
        Write-Host "  [WARN] $holdRemovedCount hold-policy-deletion event(s) present in this file - confirm each matches a counsel-confirmed, documented release per README.md Section 3's gating prerequisite and rollback.md." -ForegroundColor Yellow
    }
}

Write-Host "`n$(if ($script:failures -eq 0) { 'All automated checks passed.' } else { "$script:failures automated check(s) failed." })" `
    -ForegroundColor $(if ($script:failures -eq 0) { 'Green' } else { 'Red' })

if ($script:failures -gt 0) { exit 1 }
