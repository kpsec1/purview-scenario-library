---
part: "validate"
parent: "data-estate-insights/glossary-curation-coverage-report"
---
Run these checks after deployment to confirm the control is working as designed.


#### `Test-GlossaryCurationCoverageReport.ps1`

```powershell
#Requires -Version 7.0
<#
.SYNOPSIS
    Read-only integrity check for the glossary-curation-coverage trend log and breakdown files this
    scenario's deploy script produces - confirms the report's own internal arithmetic and shape, and
    optionally re-derives one domain's headline numbers against live Unified Catalog Terms data.

.DESCRIPTION
    Two categories of check, both read-only (same role as the deploy script - no additional
    privilege needed):
      1. Report-file integrity (no Purview call needed): the trend log has the expected columns, no
         duplicate RunId+DomainId rows (proof this scenario's replace-by-RunId idempotency design is
         actually holding), TotalTerms equals DraftTerms+PublishedTerms+ExpiredTerms for every row
         where status coverage wasn't limited by -PublishedOnly, and PublishedTerms equals
         PublishedWithAssets+PublishedWithoutAssets for every row where the asset-link check wasn't
         skipped.
      2. Live reconciliation (one Terms - List call per domain): re-fetches the current term count
         for the most recent run's domain(s) and confirms it's still reasonably close to what the
         report recorded - a large drift means the report is stale, not wrong, a different
         remediation (re-run the export) than an actual bug.
    Exits with a non-zero code if any hard check fails - safe to wire into a recurring scheduled
    check, the same pattern classification-coverage-report/validate/ uses.

.PARAMETER TrendLogPath
    Path to the trend-log CSV produced by deploy/Export-GlossaryCurationCoverageReport.ps1.

.PARAMETER PurviewAccountEndpoint
    Base URL of the Purview Unified Catalog data-plane API. Required only for the
    live-reconciliation check (2, above) - omit together with the auth parameters to run the
    file-integrity checks (1) only.

.PARAMETER TenantId
    Microsoft Entra tenant ID. Required only for the live-reconciliation check.

.PARAMETER AppId
    Application (client) ID of a service principal holding at least Global/Local Catalog Reader (or
    Data Steward, for full coverage) on the domain(s) being reconciled. Required only for the
    live-reconciliation check.

.PARAMETER ClientSecret
    Client secret for -AppId, as a SecureString. Required only for the live-reconciliation check.

.PARAMETER DomainIds
    Domain(s) to reconcile against live data. Required only for the live-reconciliation check -
    defaults to every distinct DomainId present in the trend log's most recent RunId if omitted.

.PARAMETER DriftWarningThresholdPercent
    Live-reconciliation check only: percentage difference between the report's recorded TotalTerms
    and the live term count above which this script warns (not fails) that the report may be stale.
    Defaults to 10.

.PARAMETER PageSize
    Terms - List 'top' page size used for the live-reconciliation count. Defaults to 100, matching
    the deploy script's own default.

.PARAMETER ApiVersion
    Unified Catalog REST API version to pin. Defaults to '2026-03-20-preview'.

.EXAMPLE
    ./Test-GlossaryCurationCoverageReport.ps1 -TrendLogPath '../deploy/out/glossary-curation-trend.csv'

    File-integrity checks only (no tenant credentials supplied).

.EXAMPLE
    ./Test-GlossaryCurationCoverageReport.ps1 -TrendLogPath '../deploy/out/glossary-curation-trend.csv' `
        -PurviewAccountEndpoint 'https://api.purview-service.microsoft.com' `
        -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret

    Full check: file integrity plus a live reconciliation of the most recent run's domain(s) against
    current Unified Catalog Terms totals.

.NOTES
    A [WARN] on live-reconciliation drift is not, by itself, proof of a bug - it is the expected
    signal after any term created/expired since the last report run. Re-run
    deploy/Export-GlossaryCurationCoverageReport.ps1 and re-check; a [WARN] that persists after
    re-export deserves investigation, one that clears does not.

    A row with PublishedOnly=True intentionally leaves DraftTerms/ExpiredTerms blank ("N/A") - this
    script treats a blank value there as "not applicable," never as 0, and skips the
    TotalTerms-equals-sum check for that row's Draft/Expired components accordingly (design.md
    Section 2 goal 2, README.md Section 11).

    Sources (Microsoft Learn, verify before production use):
    - Purview Unified Catalog REST API - Terms - List:
      https://learn.microsoft.com/rest/api/purview/purview-unified-catalog/terms/list?view=rest-purview-purview-unified-catalog-2026-03-20-preview
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
    [string[]]$DomainIds,

    [Parameter()]
    [ValidateRange(1, 100)]
    [int]$DriftWarningThresholdPercent = 10,

    [Parameter()]
    [ValidateRange(1, 1000)]
    [int]$PageSize = 100,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$ApiVersion = '2026-03-20-preview'
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

function Test-IsBlank {
    param([string]$Value)
    return [string]::IsNullOrWhiteSpace($Value)
}

Write-Host "Checking trend-log file integrity: $TrendLogPath" -ForegroundColor Cyan
$rows = @(Import-Csv -Path $TrendLogPath)

Test-Check -Description "Trend log has at least one row" -Condition ($rows.Count -gt 0)
if ($rows.Count -eq 0) {
    Write-Host "`nCannot continue - no rows to validate." -ForegroundColor Red
    exit 1
}

$requiredColumns = 'RunId', 'RunTimestampUtc', 'DomainId', 'PublishedOnly', 'AssetLinkCheckSkipped', `
    'TotalTerms', 'DraftTerms', 'PublishedTerms', 'ExpiredTerms', 'MissingDefinition', `
    'MissingOwner', 'MissingExpert', 'MissingMultiple', 'PublishedWithAssets', `
    'PublishedWithoutAssets', 'ExpiredWithAssets'
$actualColumns = $rows[0].PSObject.Properties.Name
foreach ($column in $requiredColumns) {
    Test-Check -Description "Column '$column' present" -Condition ($actualColumns -contains $column)
}

# --- No duplicate RunId+DomainId rows: proof the deploy script's replace-by-RunId idempotency
# design (design.md Section 5) is actually holding, not silently appending on every re-run.
$duplicateKeys = $rows | Group-Object { "$($_.RunId)|$($_.DomainId)" } | Where-Object { $_.Count -gt 1 }
Test-Check -Description "No duplicate (RunId, DomainId) rows in the trend log" -Condition ($duplicateKeys.Count -eq 0)
if ($duplicateKeys.Count -gt 0) {
    Write-Host "         Duplicate keys: $($duplicateKeys.Name -join ', ')" -ForegroundColor Yellow
}

# --- Per-row arithmetic ---
foreach ($row in $rows) {
    $isPublishedOnly = ($row.PublishedOnly -eq 'True')
    $assetLinkSkipped = ($row.AssetLinkCheckSkipped -eq 'True')
    $total = [int]$row.TotalTerms

    if (-not $isPublishedOnly -and -not (Test-IsBlank $row.DraftTerms) -and -not (Test-IsBlank $row.ExpiredTerms)) {
        $draft = [int]$row.DraftTerms
        $published = [int]$row.PublishedTerms
        $expired = [int]$row.ExpiredTerms
        Test-Check -Description "[$($row.RunId)/$($row.DomainId)] DraftTerms + PublishedTerms + ExpiredTerms ($draft + $published + $expired) equals TotalTerms ($total)" `
            -Condition ($draft + $published + $expired -eq $total)
    }
    else {
        Write-Host "  [SKIP] [$($row.RunId)/$($row.DomainId)] Status-sum check (PublishedOnly=$($row.PublishedOnly) - Draft/Expired not measured)" -ForegroundColor DarkGray
    }

    if (-not $assetLinkSkipped -and -not (Test-IsBlank $row.PublishedWithAssets) -and -not (Test-IsBlank $row.PublishedWithoutAssets)) {
        $withAssets = [int]$row.PublishedWithAssets
        $withoutAssets = [int]$row.PublishedWithoutAssets
        $published = [int]$row.PublishedTerms
        Test-Check -Description "[$($row.RunId)/$($row.DomainId)] PublishedWithAssets + PublishedWithoutAssets ($withAssets + $withoutAssets) equals PublishedTerms ($published)" `
            -Condition ($withAssets + $withoutAssets -eq $published)
    }
    else {
        Write-Host "  [SKIP] [$($row.RunId)/$($row.DomainId)] Asset-linkage-sum check (AssetLinkCheckSkipped=$($row.AssetLinkCheckSkipped))" -ForegroundColor DarkGray
    }

    if (-not (Test-IsBlank $row.MissingMultiple) -and -not (Test-IsBlank $row.MissingDefinition)) {
        Test-Check -Description "[$($row.RunId)/$($row.DomainId)] MissingMultiple ($($row.MissingMultiple)) does not exceed TotalTerms ($total)" `
            -Condition ([int]$row.MissingMultiple -le $total)
    }
}

# --- Optional live reconciliation against the most recent run ---
if ($PurviewAccountEndpoint -and $TenantId -and $AppId -and $ClientSecret) {
    Write-Host "`nReconciling the most recent run against live Unified Catalog Terms data..." -ForegroundColor Cyan

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

    function Get-LiveTermCount {
        param([Parameter(Mandatory)][string]$DomainId, [Parameter(Mandatory)][string]$Token, [Parameter(Mandatory)][string]$Endpoint)
        $count = 0
        $skip = 0
        do {
            $uri = "$Endpoint/datagovernance/catalog/terms?api-version=$ApiVersion&domainId=$DomainId&skip=$skip&top=$PageSize"
            $response = Invoke-RestMethod -Method Get -Uri $uri -Headers @{ Authorization = "Bearer $Token" }
            $count += @($response.value).Count
            $skip += $PageSize
        } while ($response.nextLink)
        return $count
    }

    $plainSecret = ConvertTo-PlainText -Secure $ClientSecret
    try {
        $token = Get-PurviewAccessToken -TenantId $TenantId -AppId $AppId -PlainSecret $plainSecret
    }
    finally {
        $plainSecret = $null
    }

    $trimmedEndpoint = $PurviewAccountEndpoint.TrimEnd('/')
    $latestRunId = ($rows | Sort-Object RunId -Descending | Select-Object -First 1).RunId
    $latestRows = $rows | Where-Object { $_.RunId -eq $latestRunId }
    if ($DomainIds) { $latestRows = $latestRows | Where-Object { $_.DomainId -in $DomainIds } }

    foreach ($row in $latestRows) {
        $liveCount = Get-LiveTermCount -DomainId $row.DomainId -Token $token -Endpoint $trimmedEndpoint
        $recordedCount = [int]$row.TotalTerms

        $driftPercent = if ($recordedCount -gt 0) {
            [math]::Abs(100.0 * ($liveCount - $recordedCount) / $recordedCount)
        } elseif ($liveCount -eq 0) { 0 } else { 100 }

        Test-Check -Description "[$latestRunId/$($row.DomainId)] Live term count ($liveCount) within $DriftWarningThresholdPercent% of reported TotalTerms ($recordedCount)" `
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