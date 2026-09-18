---
part: "validate"
parent: "data-map/verify-purview-entra-graph-prerequisites"
---
Run these checks after deployment to confirm the control is working as designed.


#### `Test-DirectoryReadersMembershipInputs.ps1`

```powershell
#Requires -Version 7.0
<#
.SYNOPSIS
    Validates the managed-instance inventory CSV before it is handed to
    deploy/Confirm-DirectoryReadersMembership.ps1, and (if present) sanity-checks that script's own
    JSON report output. Prints a manual verification checklist for cross-checking a sample finding
    against the Entra admin center directly.

.DESCRIPTION
    Two categories of check, clearly separated in the output, mirroring
    scenarios/compliance-manager/entra-privileged-role-monitoring/validate/'s split:

    1. AUTOMATED (hard pass/fail, contributes to exit code) - read-only, no tenant connection
       needed:
       - -ManagedInstanceInventoryPath exists, has the required InstanceName/PrincipalObjectId
         columns, no empty values in either, no duplicate PrincipalObjectId rows (the same managed
         identity listed twice would double-count in the drift computation), and every
         PrincipalObjectId parses as a GUID (Microsoft Entra object IDs are GUIDs - a non-GUID
         value is almost always a copy-paste error, e.g. pasting the instance's Azure *resource*
         ID instead of its identity's *object* ID).
       - If -ReportPath is also supplied (a report the deploy script already produced), confirms it
         parses as JSON, has the expected top-level shape (GeneratedUtc, Instances, DriftMembers),
         and that every row in -ManagedInstanceInventoryPath has a corresponding entry in the
         report's Instances array with a matching PrincipalObjectId - catching a report generated
         against a stale or different inventory file by mistake.

    2. MANUAL (printed as a checklist, never fails the script) - spot-checking a FAIL or WARN
       finding against the Microsoft Entra admin center directly, since this scenario's correctness
       ultimately rests on Get-MgDirectoryRoleMember's documented-but-not-independently-worked-
       example return shape for non-user member types (deploy script .NOTES).

    Exits non-zero only if an AUTOMATED check hard-fails. Safe to re-run any number of times; makes
    no mutating calls and needs no tenant connection at all.

.PARAMETER ManagedInstanceInventoryPath
    Path to the same CSV inventory passed to deploy/Confirm-DirectoryReadersMembership.ps1's
    -ManagedInstanceInventoryPath.

.PARAMETER ReportPath
    Optional. Path to a JSON report already produced by
    deploy/Confirm-DirectoryReadersMembership.ps1's -ReportPath. If omitted, only the inventory
    file is validated (still a useful pre-flight check before the first live run).

.EXAMPLE
    ./Test-DirectoryReadersMembershipInputs.ps1 -ManagedInstanceInventoryPath '../deploy/managed-instances.csv'

    Pre-flight: validates the inventory file's shape before the first live run against a tenant.

.EXAMPLE
    ./Test-DirectoryReadersMembershipInputs.ps1 `
        -ManagedInstanceInventoryPath '../deploy/managed-instances.csv' `
        -ReportPath '../deploy/out/directory-readers-membership-report.json'

    Post-run: also cross-checks a produced report against the inventory it should have been run
    against.

.NOTES
    A GUID-format PrincipalObjectId does not by itself prove it is the CORRECT object ID for that
    instance's managed identity - only that it is syntactically plausible. Cross-check it against
    (Get-AzSqlInstance -ResourceGroupName <rg> -Name <instance>).Identity.PrincipalId directly
    (README.md Section 5) before relying on a FAIL/PASS result for a production decision.

    Sources: see deploy/Confirm-DirectoryReadersMembership.ps1 .NOTES for the Microsoft Learn
    references this scenario's grounding rests on.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$ManagedInstanceInventoryPath,

    [Parameter()]
    [string]$ReportPath
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

Write-Host "=== AUTOMATED CHECKS: inventory file '$ManagedInstanceInventoryPath' ===" -ForegroundColor Cyan

Test-Check -Description "Inventory file exists" -Condition (Test-Path -Path $ManagedInstanceInventoryPath -PathType Leaf)
if (-not (Test-Path -Path $ManagedInstanceInventoryPath -PathType Leaf)) {
    Write-Host "`nCannot continue - inventory file not found." -ForegroundColor Red
    exit 1
}

$inventory = @(Import-Csv -Path $ManagedInstanceInventoryPath)
Test-Check -Description "Inventory has at least one data row" -Condition ($inventory.Count -gt 0)
if ($inventory.Count -eq 0) {
    Write-Host "`nCannot continue - no data rows to validate." -ForegroundColor Red
    exit 1
}

$actualColumns = $inventory[0].PSObject.Properties.Name
foreach ($requiredColumn in 'InstanceName', 'PrincipalObjectId') {
    Test-Check -Description "Required column '$requiredColumn' present" -Condition ($actualColumns -contains $requiredColumn)
}
foreach ($optionalColumn in 'ResourceGroupName', 'PurviewDataSourceName') {
    Test-Check -Description "Optional column '$optionalColumn' present (recommended for readable reports, not required)" -Condition ($actualColumns -contains $optionalColumn) -Warn
}

$emptyInstanceNameRows = @($inventory | Where-Object { [string]::IsNullOrWhiteSpace($_.InstanceName) })
Test-Check -Description "No rows with an empty InstanceName" -Condition ($emptyInstanceNameRows.Count -eq 0)

$emptyPrincipalIdRows = @($inventory | Where-Object { [string]::IsNullOrWhiteSpace($_.PrincipalObjectId) })
Test-Check -Description "No rows with an empty PrincipalObjectId" -Condition ($emptyPrincipalIdRows.Count -eq 0)

$duplicatePrincipalIds = $inventory | Where-Object { -not [string]::IsNullOrWhiteSpace($_.PrincipalObjectId) } |
    Group-Object PrincipalObjectId | Where-Object { $_.Count -gt 1 }
Test-Check -Description "No duplicate PrincipalObjectId values (would double-count in the drift computation)" -Condition ($duplicatePrincipalIds.Count -eq 0)
if ($duplicatePrincipalIds.Count -gt 0) {
    Write-Host "         Duplicate PrincipalObjectId value(s): $($duplicatePrincipalIds.Name -join '; ')" -ForegroundColor Yellow
}

$guidPattern = '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
$nonGuidRows = @($inventory | Where-Object { -not [string]::IsNullOrWhiteSpace($_.PrincipalObjectId) -and $_.PrincipalObjectId -notmatch $guidPattern })
Test-Check -Description "Every non-empty PrincipalObjectId parses as a GUID" -Condition ($nonGuidRows.Count -eq 0)
if ($nonGuidRows.Count -gt 0) {
    Write-Host "         Non-GUID value(s): $(($nonGuidRows.PrincipalObjectId) -join '; ') - common cause: pasting the instance's Azure *resource* ID instead of its managed identity's *object* ID (README.md Section 5)." -ForegroundColor Yellow
}

if ($ReportPath) {
    Write-Host "`n=== AUTOMATED CHECKS: report file '$ReportPath' ===" -ForegroundColor Cyan
    Test-Check -Description "Report file exists" -Condition (Test-Path -Path $ReportPath -PathType Leaf)
    if (Test-Path -Path $ReportPath -PathType Leaf) {
        $reportOk = $true
        try {
            $report = Get-Content -Path $ReportPath -Raw | ConvertFrom-Json -ErrorAction Stop
        }
        catch {
            $reportOk = $false
        }
        Test-Check -Description "Report parses as valid JSON" -Condition $reportOk
        if ($reportOk) {
            foreach ($requiredProperty in 'GeneratedUtc', 'Instances', 'DriftMembers', 'DriftMemberCount') {
                Test-Check -Description "Report has top-level property '$requiredProperty'" -Condition ($null -ne $report.PSObject.Properties[$requiredProperty])
            }

            $reportPrincipalIds = @($report.Instances | ForEach-Object { $_.PrincipalObjectId })
            $missingFromReport = @($inventory | Where-Object { $_.PrincipalObjectId -notin $reportPrincipalIds })
            Test-Check -Description "Every inventory row has a matching entry in the report's Instances array (report matches this inventory, not a stale/different one)" -Condition ($missingFromReport.Count -eq 0)
            if ($missingFromReport.Count -gt 0) {
                Write-Host "         Inventory InstanceName(s) missing from report: $(($missingFromReport.InstanceName) -join '; ')" -ForegroundColor Yellow
            }

            $failedInstances = @($report.Instances | Where-Object { $_.Status -eq 'FAIL' })
            if ($failedInstances.Count -gt 0) {
                Write-Host "  [WARN] Report shows $($failedInstances.Count) FAILing instance(s): $(($failedInstances.InstanceName) -join ', '). Not a validation-script failure - review and remediate per README.md Section 5." -ForegroundColor Yellow
            }
        }
    }
}

Write-Host "`n=== MANUAL VERIFICATION CHECKLIST (spot-check a finding against the portal directly) ===" -ForegroundColor Cyan
$manualChecklist = @(
    "Pick one inventory row (prefer one the deploy script reported as FAIL or that appears in DriftMembers, if you have a report). In the Microsoft Entra admin center > Identity > Roles & administrators > Directory Readers > Assignments, confirm whether that PrincipalObjectId's identity is actually listed."
    "For a FAIL row: confirm in the Azure portal (the managed instance > Microsoft Entra ID pane) whether the 'grant Directory Reader permissions' banner is showing - its presence corroborates this script's FAIL finding independently."
    "For a WARN drift entry: confirm with the identity/IAM team whether the unexpected member is a known, authorized workload (e.g. a different Managed Instance's identity, or an unrelated automation service principal) before treating it as suspicious - Directory Readers is legitimately shared across multiple workloads in most tenants (README.md Section 11)."
    "Cross-check the PrincipalObjectId itself: run (Get-AzSqlInstance -ResourceGroupName <rg> -Name <instance>).Identity.PrincipalId directly against the managed instance and confirm it matches the inventory row's PrincipalObjectId exactly - a stale or copy-pasted ID would otherwise silently produce a false PASS or FAIL for the wrong identity."
)
$manualChecklist | ForEach-Object { Write-Host "  [ ] $_" -ForegroundColor Yellow }

Write-Host "`n$(if ($script:failures -eq 0) { 'All automated checks passed.' } else { "$script:failures automated check(s) failed." }) Manual checklist above still requires a human to confirm in the portal." `
    -ForegroundColor $(if ($script:failures -eq 0) { 'Green' } else { 'Red' })

if ($script:failures -gt 0) { exit 1 }
```