#Requires -Version 7.0
<#
.SYNOPSIS
    Validates the audit-trail CSV this scenario's deploy script produces, and prints a manual
    verification checklist for cross-checking a spot sample against the Entra portal directly.

.DESCRIPTION
    Two categories of check, clearly separated in the output:

    1. AUTOMATED (hard pass/fail, contributes to exit code) - read-only, no tenant connection
       needed:
       - The CSV has the expected columns and at least the header (an empty file with zero data
         rows is not itself a failure - it means no privileged-role changes occurred in every
         window run so far, which is the expected common case for a quiet tenant).
       - No duplicate Id rows - proof the deploy script's merge-and-de-duplicate design
         (design.md Section 6) is actually holding across re-runs, not silently accumulating
         duplicates on every overlapping-window run.
       - Every row's ActivityDisplayName is one of the two monitored activities ("Add member to
         role" / "Remove member from role") and every row's RoleDisplayName is one of the
         monitored role names - catches a scenario where the CSV was hand-edited or produced by a
         different script by mistake.
       - ActivityDateTime values parse as valid timestamps and are monotonically non-decreasing
         after the deploy script's own Sort-Object.

    2. MANUAL (printed as a checklist, never fails the script) - spot-checking a sample row
       against the Entra admin center's own Audit logs blade, since this script's correctness
       ultimately rests on Microsoft's documented-but-not-independently-worked-example
       targetResources parsing (deploy script .NOTES, README.md Section 11).

    Exits non-zero only if an AUTOMATED check hard-fails. Safe to re-run any number of times; makes
    no mutating calls and needs no tenant connection at all for category 1.

.PARAMETER AuditTrailCsvPath
    Path to the CSV produced by deploy/Export-EntraPrivilegedRoleAuditTrail.ps1.

.PARAMETER PrivilegedRoleDisplayNames
    The same role-name list the deploy script was run with (for the automated
    "RoleDisplayName is one of the monitored roles" check). Defaults to the same four roles.

.EXAMPLE
    ./Test-EntraPrivilegedRoleAuditTrail.ps1 -AuditTrailCsvPath '../deploy/out/entra-privileged-role-audit-trail.csv'

.NOTES
    A CSV with zero data rows is expected and healthy the first time this scenario is deployed in a
    quiet tenant - it means no Global/Compliance/Compliance Data/Security Administrator assignment
    or removal has occurred in the queried window, not that the deploy script is broken. Re-run
    deploy/Export-EntraPrivilegedRoleAuditTrail.ps1 with a wider -StartDate (bounded by the tenant's
    actual Entra audit-log retention - README.md Section 11) to confirm the query itself works if
    this is unexpected.

    Sources: see deploy/Export-EntraPrivilegedRoleAuditTrail.ps1 .NOTES for the Microsoft Learn
    references this scenario's grounding rests on.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$AuditTrailCsvPath,

    [Parameter()]
    [string[]]$PrivilegedRoleDisplayNames = @(
        'Global Administrator',
        'Compliance Administrator',
        'Compliance Data Administrator',
        'Security Administrator'
    )
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
    Write-Host "`nCannot continue - file not found. Run deploy/Export-EntraPrivilegedRoleAuditTrail.ps1 first." -ForegroundColor Red
    exit 1
}

$rows = @(Import-Csv -Path $AuditTrailCsvPath)

$requiredColumns = 'Id', 'ActivityDateTime', 'ActivityDisplayName', 'RoleDisplayName', 'PrincipalDisplayName', 'InitiatedBy', 'Result', 'ResultReason', 'CorrelationId'
$actualColumns = if ($rows.Count -gt 0) {
    (Import-Csv -Path $AuditTrailCsvPath | Select-Object -First 1).PSObject.Properties.Name
} else {
    (Get-Content -Path $AuditTrailCsvPath -TotalCount 1) -split ','
}
foreach ($column in $requiredColumns) {
    Test-Check -Description "Column '$column' present" -Condition ($actualColumns -contains $column)
}

if ($rows.Count -eq 0) {
    Write-Host "  [PASS] File contains a header with no data rows - healthy if no monitored privileged-role change occurred in the queried window(s) so far." -ForegroundColor Green
}
else {
    $duplicateIds = $rows | Group-Object Id | Where-Object { $_.Count -gt 1 }
    Test-Check -Description "No duplicate Id rows (de-duplication merge is holding)" -Condition ($duplicateIds.Count -eq 0)
    if ($duplicateIds.Count -gt 0) {
        Write-Host "         Duplicate Ids: $($duplicateIds.Name -join '; ')" -ForegroundColor Yellow
    }

    $validActivities = @(
        'Add member to role',
        'Add member to role scoped over Restricted Management Administrative Unit',
        'Add scoped member to role',
        'Remove member from role',
        'Remove member from role scoped over Restricted Management Administrative Unit',
        'Remove scoped member from role'
    )
    $invalidActivityRows = $rows | Where-Object { $_.ActivityDisplayName -notin $validActivities }
    Test-Check -Description "Every row's ActivityDisplayName is one of the 6 monitored activities" -Condition ($invalidActivityRows.Count -eq 0)
    if ($invalidActivityRows.Count -gt 0) {
        Write-Host "         Unexpected activity value(s): $(($invalidActivityRows.ActivityDisplayName | Select-Object -Unique) -join ', ')" -ForegroundColor Yellow
    }

    $invalidRoleRows = $rows | Where-Object { $_.RoleDisplayName -notin $PrivilegedRoleDisplayNames }
    Test-Check -Description "Every row's RoleDisplayName is one of the monitored roles" -Condition ($invalidRoleRows.Count -eq 0)
    if ($invalidRoleRows.Count -gt 0) {
        Write-Host "         Unexpected role value(s): $(($invalidRoleRows.RoleDisplayName | Select-Object -Unique) -join ', ')" -ForegroundColor Yellow
    }

    $parsedDates = foreach ($row in $rows) {
        $parsed = $null
        $ok = [datetime]::TryParse($row.ActivityDateTime, [ref]$parsed)
        [pscustomobject]@{ Raw = $row.ActivityDateTime; Parsed = $parsed; Ok = $ok }
    }
    Test-Check -Description "Every ActivityDateTime value parses as a valid timestamp" -Condition (($parsedDates | Where-Object { -not $_.Ok }).Count -eq 0)

    $sortedCheck = $true
    for ($i = 1; $i -lt $parsedDates.Count; $i++) {
        if ($parsedDates[$i].Parsed -lt $parsedDates[$i - 1].Parsed) { $sortedCheck = $false; break }
    }
    Test-Check -Description "ActivityDateTime values are non-decreasing (file wasn't reordered/corrupted after the deploy script's own sort)" -Condition $sortedCheck

    $globalAdminChanges = @($rows | Where-Object { $_.RoleDisplayName -eq 'Global Administrator' })
    if ($globalAdminChanges.Count -gt 0) {
        Write-Host "  [WARN] $($globalAdminChanges.Count) Global Administrator role change event(s) present in this file - review each per README.md Section 8 incident-response guidance, do not treat their mere presence as a failure of this script." -ForegroundColor Yellow
    }
}

Write-Host "`n=== MANUAL VERIFICATION CHECKLIST (spot-check this script's parsing against the portal directly) ===" -ForegroundColor Cyan
$manualChecklist = @(
    "Pick one row from this CSV (or, in a quiet tenant, make a throwaway test assignment/removal on a non-privileged test role first). In the Microsoft Entra admin center > Identity > Monitoring & health > Audit logs, filter Activity to 'Add member to role' or 'Remove member from role' for the same time window."
    "Confirm the portal's own record for that event shows the same role name (RoleDisplayName column) and target user (PrincipalDisplayName column) this script extracted from targetResources - see the deploy script's VERIFY note in its .NOTES about unconfirmed targetResources array shape."
    "Confirm InitiatedBy in this CSV matches the portal's 'Initiated by (actor)' column for the same event."
    "If this file shows 0 events but you know a privileged-role change occurred: check whether the change was PIM-mediated (eligible activation / time-bound assignment) rather than a direct/permanent assignment - this script deliberately does not cover that activity family yet (README.md Section 11), or whether the tenant's Entra audit-log retention (7 days Free / 30 days P1-P2) already expired the event before this script ran."
    "Cross-reference any row here against scenarios/compliance-manager/assess-against-iso27001/deploy/out/compliance-manager-audit-trail.csv for the same time window: a Global/Compliance/Compliance Data/Security Administrator role change here, with no corresponding ComplianceManagerRolesChange row there, is exactly the previously-undetectable blind spot this scenario exists to close - confirm you now see it."
)
$manualChecklist | ForEach-Object { Write-Host "  [ ] $_" -ForegroundColor Yellow }

Write-Host "`n$(if ($script:failures -eq 0) { 'All automated checks passed.' } else { "$script:failures automated check(s) failed." }) Manual checklist above still requires a human to confirm in the portal." `
    -ForegroundColor $(if ($script:failures -eq 0) { 'Green' } else { 'Red' })

if ($script:failures -gt 0) { exit 1 }
