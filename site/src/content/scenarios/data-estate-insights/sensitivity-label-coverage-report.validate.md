---
part: "validate"
parent: "data-estate-insights/sensitivity-label-coverage-report"
---
Run these checks after deployment to confirm the control is working as designed.


#### `Test-SensitivityLabelCoverageReport.ps1`

```powershell
#Requires -Version 7.0
<#
.SYNOPSIS
    Read-only integrity check for the sensitivity-label-coverage trend log and breakdown files this
    scenario's deploy script produces - confirms the report's own internal arithmetic and shape, and
    independently re-derives one object type's headline numbers against live Discovery - Query data to
    confirm the exported report isn't stale or silently wrong.

.DESCRIPTION
    Two categories of check, both read-only (Data Reader role, same as the deploy script - no
    additional privilege needed):
      1. Report-file integrity (no Purview call needed): the trend log has the expected columns, no
         duplicate RunId+ObjectType rows (proof this scenario's replace-by-RunId idempotency design is
         actually holding), LabeledAssets + UnlabeledAssets sums to TotalAssets for every Full-mode
         row, and PercentLabeled is internally consistent with those two counts.
      2. Live reconciliation (one Discovery - Query call): re-fetches the current "@search.count" for
         the most recent run's ObjectType/CollectionId scope and confirms it's still reasonably close
         to what the report recorded - a large drift means the report is stale (a rescan, a bulk
         relabeling, or a bulk asset deletion happened since the last export) rather than wrong, which
         is a different remediation (re-run the export) than an actual bug.
    Exits with a non-zero code if any hard check fails - safe to wire into a recurring scheduled check,
    the same pattern this repo's other validate/ scripts (including the sibling
    classification-coverage-report scenario) use.

.PARAMETER TrendLogPath
    Path to the trend-log CSV produced by deploy/Export-SensitivityLabelCoverageReport.ps1.

.PARAMETER PurviewAccountEndpoint
    Base URL of the Purview Data Map data-plane API. Required only for the live-reconciliation check
    (2, above) - omit together with the auth parameters to run the file-integrity checks (1) only, e.g.
    in a context with no network access to the tenant.

.PARAMETER TenantId
    Microsoft Entra tenant ID. Required only for the live-reconciliation check.

.PARAMETER AppId
    Application (client) ID of a service principal holding at least the Data Reader role on the
    collection(s) in scope. Required only for the live-reconciliation check.

.PARAMETER ClientSecret
    Client secret for -AppId, as a SecureString. Required only for the live-reconciliation check.

.PARAMETER DriftWarningThresholdPercent
    Live-reconciliation check only: percentage difference between the report's recorded TotalAssets and
    the live @search.count above which this script warns (not fails) that the report may be stale.
    Defaults to 10.

.PARAMETER ApiVersion
    Data Map Discovery REST API version to pin. Defaults to '2023-09-01'.

.EXAMPLE
    ./Test-SensitivityLabelCoverageReport.ps1 -TrendLogPath '../deploy/out/sensitivity-label-coverage-trend.csv'

    File-integrity checks only (no tenant credentials supplied) - confirms the trend log's own
    arithmetic and idempotency, without a live Discovery - Query call.

.EXAMPLE
    ./Test-SensitivityLabelCoverageReport.ps1 -TrendLogPath '../deploy/out/sensitivity-label-coverage-trend.csv' `
        -PurviewAccountEndpoint 'https://api.purview-service.microsoft.com' `
        -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret

    Full check: file integrity plus a live reconciliation of the most recent run's row(s) against
    current Discovery - Query totals.

.NOTES
    A [WARN] on live-reconciliation drift is not, by itself, proof of a bug - it is the expected signal
    after any rescan, bulk relabeling, bulk asset deletion, or new source onboarded since the last
    report run. Re-run deploy/Export-SensitivityLabelCoverageReport.ps1 and re-check; a [WARN] that
    persists after re-export deserves investigation, one that clears does not.

    Sources (Microsoft Learn, verify before production use):
    - Discovery - Query REST reference (API version 2023-09-01):
      https://learn.microsoft.com/rest/api/purview/datamapdataplane/discovery/query
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateScript({ Test-Path $_ -PathType Leaf })]
    [string]$TrendLogPath,

    [Parameter()]
    [string]$PurviewAccountEndpoint,

    [Parameter()]
    [string]$TenantId,

    [Parameter()]
    [string]$AppId,

    [Parameter()]
    [SecureString]$ClientSecret,

    [Parameter()]
    [ValidateRange(1, 100)]
    [int]$DriftWarningThresholdPercent = 10,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$ApiVersion = '2023-09-01'
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

Write-Host "Checking trend-log file integrity: $TrendLogPath" -ForegroundColor Cyan
$rows = @(Import-Csv -Path $TrendLogPath)

Test-Check -Description "Trend log has at least one row" -Condition ($rows.Count -gt 0)
if ($rows.Count -eq 0) {
    Write-Host "`nCannot continue - no rows to validate." -ForegroundColor Red
    exit 1
}

$requiredColumns = 'RunId', 'RunTimestampUtc', 'ObjectType', 'Mode', 'TotalAssets', `
    'LabeledAssets', 'UnlabeledAssets', 'PercentLabeled'
$actualColumns = $rows[0].PSObject.Properties.Name
foreach ($column in $requiredColumns) {
    Test-Check -Description "Column '$column' present" -Condition ($actualColumns -contains $column)
}

# --- No duplicate RunId+ObjectType rows: proof the deploy script's replace-by-RunId idempotency
# design (design.md Section 5) is actually holding, not silently appending on every re-run.
$duplicateKeys = $rows | Group-Object { "$($_.RunId)|$($_.ObjectType)" } | Where-Object { $_.Count -gt 1 }
Test-Check -Description "No duplicate (RunId, ObjectType) rows in the trend log" -Condition ($duplicateKeys.Count -eq 0)
if ($duplicateKeys.Count -gt 0) {
    Write-Host "         Duplicate keys: $($duplicateKeys.Name -join ', ')" -ForegroundColor Yellow
}

# --- Per-row arithmetic: LabeledAssets + UnlabeledAssets == TotalAssets (Full mode only - Facets mode
# rows leave both blank by design, see README.md Section 11).
foreach ($row in $rows) {
    if ($row.Mode -eq 'Full') {
        $total = [int]$row.TotalAssets
        $labeled = [int]$row.LabeledAssets
        $unlabeled = [int]$row.UnlabeledAssets
        Test-Check -Description "[$($row.RunId)/$($row.ObjectType)] LabeledAssets + UnlabeledAssets ($labeled + $unlabeled) equals TotalAssets ($total)" `
            -Condition ($labeled + $unlabeled -eq $total)

        if ($total -gt 0) {
            $expectedPct = [math]::Round(100.0 * $labeled / $total, 1)
            $recordedPct = [double]$row.PercentLabeled
            Test-Check -Description "[$($row.RunId)/$($row.ObjectType)] PercentLabeled ($recordedPct) matches recomputed value ($expectedPct)" `
                -Condition ([math]::Abs($expectedPct - $recordedPct) -le 0.1)
        }
    }
}

# --- Optional live reconciliation against the most recent run ---
if ($PurviewAccountEndpoint -and $TenantId -and $AppId -and $ClientSecret) {
    Write-Host "`nReconciling the most recent run against live Discovery - Query data..." -ForegroundColor Cyan

    function ConvertTo-PlainText {
        param([Parameter(Mandatory)][SecureString]$Secure)
        $ptr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($Secure)
        try { return [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($ptr) }
        finally { [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr) }
    }

    function Get-PurviewAccessToken {
        param(
            [Parameter(Mandatory)][string]$TenantId,
            [Parameter(Mandatory)][string]$AppId,
            [Parameter(Mandatory)][string]$PlainSecret
        )
        $body = @{
            client_id     = $AppId
            client_secret = $PlainSecret
            grant_type    = 'client_credentials'
            resource      = 'https://purview.azure.net'
        }
        $response = Invoke-RestMethod -Method Post `
            -Uri "https://login.microsoftonline.com/$TenantId/oauth2/token" -Body $body
        return $response.access_token
    }

    $plainSecret = ConvertTo-PlainText -Secure $ClientSecret
    try {
        $token = Get-PurviewAccessToken -TenantId $TenantId -AppId $AppId -PlainSecret $plainSecret
    }
    finally {
        $plainSecret = $null
    }

    $endpoint = $PurviewAccountEndpoint.TrimEnd('/')
    $queryUri = "$endpoint/datamap/api/search/query?api-version=$ApiVersion"

    $latestRunId = ($rows | Sort-Object RunId -Descending | Select-Object -First 1).RunId
    $latestRows = $rows | Where-Object { $_.RunId -eq $latestRunId }

    foreach ($row in $latestRows) {
        $filter = @{ objectType = $row.ObjectType }
        if ($row.CollectionId) {
            $filter = @{ and = @(@{ objectType = $row.ObjectType }, @{ collectionId = $row.CollectionId }) }
        }
        $body = @{ keywords = $null; limit = 1; filter = $filter }
        $response = Invoke-RestMethod -Method Post -Uri $queryUri -ContentType 'application/json' `
            -Headers @{ Authorization = "Bearer $token" } -Body ($body | ConvertTo-Json -Depth 10)
        $liveCount = [int]$response.'@search.count'
        $recordedCount = [int]$row.TotalAssets

        $driftPercent = if ($recordedCount -gt 0) {
            [math]::Abs(100.0 * ($liveCount - $recordedCount) / $recordedCount)
        } elseif ($liveCount -eq 0) { 0 } else { 100 }

        Test-Check -Description "[$latestRunId/$($row.ObjectType)] Live @search.count ($liveCount) within $DriftWarningThresholdPercent% of reported TotalAssets ($recordedCount)" `
            -Condition ($driftPercent -le $DriftWarningThresholdPercent) -Warn
    }
}
else {
    Write-Host "`nSkipping live reconciliation - PurviewAccountEndpoint/TenantId/AppId/ClientSecret not all supplied. File-integrity checks only." -ForegroundColor Yellow
}

Write-Host "`n$(if ($script:failures -eq 0) { 'All hard checks passed.' } else { "$script:failures hard check(s) failed." })" `
    -ForegroundColor $(if ($script:failures -eq 0) { 'Green' } else { 'Red' })

if ($script:failures -gt 0) { exit 1 }
```