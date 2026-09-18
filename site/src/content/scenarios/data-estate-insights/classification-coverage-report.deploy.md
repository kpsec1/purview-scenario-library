---
part: "deploy"
parent: "data-estate-insights/classification-coverage-report"
---
The scripts and configuration below deploy this scenario. Review them, then run in order — each is designed to be idempotent and has a matching rollback.


#### `Export-ClassificationCoverageReport.ps1`

```powershell
#Requires -Version 7.0
<#
.SYNOPSIS
    Produces an exportable, historical classification-coverage report for a Microsoft Purview Data
    Map estate, equivalent in substance to the native Data Estate Insights "Classic classifications"
    report's headline KPIs, but scriptable, least-privilege, and trended over time.

.DESCRIPTION
    Calls the Microsoft Purview Data Map Discovery - Query REST API (automation surface 4 per
    docs/automation-surface.md Section 1, API version 2023-09-01) to compute, per configured
    object type (default: Tables and Files):
      - The total asset count (from the response's authoritative "@search.count" field).
      - The classified vs. unclassified asset count and percentage, computed by paging through
        every SearchResultValue record (continuationToken, page size 1000 - the documented maximum)
        and testing each record's own documented 'classification' array field client-side. There is
        no documented Discovery - Query request filter for "has any classification" - see
        README.md Section 11 and design.md Section 2 goal 3 for why this script does not attempt to
        approximate one via an unconfirmed filter expression.
      - A histogram of every classification value seen, with asset counts.

    Every call is a read-only POST to search/query - this script never creates, modifies, or
    deletes any Purview object. The only side effect is the trend-log CSV and per-run breakdown
    file this script writes, which IS gated behind $PSCmdlet.ShouldProcess() so -WhatIf reports
    what would be written without touching disk.

    Idempotency model: unlike this repo's policy-deploying scenarios (which skip an already-existing
    object), a report has no such object to check against. Instead, re-running this script for the
    same -RunId (default: current UTC date, 'yyyy-MM-dd') REPLACES that RunId's row(s) in the trend
    log rather than appending a duplicate - so a retried or re-scheduled run never double-counts a
    day's numbers. See design.md Section 5.

    Author-only reference code. Never connects to a live tenant unless you supply real credentials
    and omit -WhatIf. Assumes the target collection(s) already have at least one completed Data Map
    scan - see README.md Section 3/6.

.PARAMETER PurviewAccountEndpoint
    Base URL of the Purview Data Map data-plane API. Use 'https://api.purview-service.microsoft.com'
    for tenants on the current Microsoft Purview portal, or 'https://<account>.purview.azure.com'
    for the classic portal - both are Microsoft's own documented valid values for this exact
    /datamap/api/... path family (README.md reference 11, the same dual-endpoint precedent already
    established in scenarios/data-lineage/end-to-end-lineage-validation/).

.PARAMETER TenantId
    Microsoft Entra tenant ID.

.PARAMETER AppId
    Application (client) ID of the service principal used to call the Discovery - Query API. Must
    hold at minimum the Data Reader role on the collection(s) in scope - deliberately narrower than
    the Data Curator role the native report's own "Export to CSV" button requires (README.md
    Section 3, design.md Section 2 goal 2).

.PARAMETER ClientSecret
    Client secret for -AppId, as a SecureString. Resolve from a vault at run time - never hard-code.

.PARAMETER ObjectTypes
    One or more Discovery - Query 'objectType' filter values to report on. Defaults to
    'Tables','Files', mirroring the native Classic classifications report's own
    classified-files/classified-tables split (README.md Section 6). Confirmed valid values per
    Microsoft's own worked examples: Tables, Files, Folders, Glossary terms, Dashboards,
    Data pipelines, Reports, Stored procedures.

.PARAMETER CollectionId
    Optional. Scopes every query to a single collection via the documented 'collectionId' filter
    (README.md Section 6). Omit to report across every collection the calling identity's Data
    Reader role can see.

.PARAMETER Mode
    'Full' (default): pages through every matching record and tallies classified/unclassified plus
    the classification histogram client-side - the only mode that can report an unclassified count
    or an exact (non-double-counted) classified count. 'Facets' : a single faceted query per object
    type, returning only a top-N classification histogram (like the native "Top classifications"
    chart) without pagination - cheaper, but cannot compute a classified/unclassified split, and
    (like the native chart) double-counts any asset carrying more than one classification. See
    design.md Section 5 and README.md Section 11.

.PARAMETER FacetTopN
    Facets mode only: number of top classification values to return per object type (Discovery -
    Query 'facet.count'). Defaults to 25. Ignored in Full mode, where every distinct classification
    value observed is reported.

.PARAMETER TrendLogPath
    Path to the append/replace-by-RunId CSV trend log. Created with a header row if it doesn't
    already exist. One row is written per (RunId, ObjectType) combination.

.PARAMETER BreakdownOutputDirectory
    Directory to write this run's full classification-value breakdown as
    '<RunId>-<ObjectType>-classifications.json'. Created if it doesn't already exist.

.PARAMETER RunId
    Identifier for this report run, used both as a trend-log column and to make re-runs replace
    rather than duplicate. Defaults to the current UTC date ('yyyy-MM-dd') - one row per day is the
    right granularity for a recurring scheduled report; pass an explicit value (e.g. a pipeline run
    ID) for a different cadence or for reproducible testing.

.PARAMETER ApiVersion
    Data Map Discovery REST API version to pin. Defaults to '2023-09-01', confirmed current via a
    direct fetch of the Discovery - Query REST reference page.

.PARAMETER WhatIf
    Standard PowerShell ShouldProcess dry-run. All read-only Discovery - Query calls still execute
    (needed to report accurate would-be numbers), but neither the trend-log CSV nor the breakdown
    file is written - the script prints what it would have written instead.

.EXAMPLE
    ./Export-ClassificationCoverageReport.ps1 -PurviewAccountEndpoint 'https://api.purview-service.microsoft.com' `
        -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
        -TrendLogPath './out/classification-coverage-trend.csv' `
        -BreakdownOutputDirectory './out/breakdowns' -WhatIf

    Dry run: queries live data and prints the computed KPIs, writes nothing to disk.

.EXAMPLE
    ./Export-ClassificationCoverageReport.ps1 -PurviewAccountEndpoint 'https://api.purview-service.microsoft.com' `
        -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
        -CollectionId 'customerdb' -TrendLogPath './out/classification-coverage-trend.csv' `
        -BreakdownOutputDirectory './out/breakdowns'

    Scopes to the 'customerdb' collection, appends/replaces today's row in the trend log, and writes
    a full classification-value breakdown file for today's run.

.NOTES
    VERIFY before production use (see README.md Section 11 for full detail):
    - At very large estate scale, -Mode Full's full page-through of every record in scope is a
      real, non-trivial number of API calls (records / 1000, rounded up, per object type). This
      script does not implement incremental/delta tallying. Consider -Mode Facets for a cheap
      top-N-only proxy at that scale, with its documented double-counting/no-unclassified-count
      trade-off.
    - This script reconciles the number of records actually paged against the response's own
      "@search.count" and emits a warning (not a hard failure) on a mismatch, since Microsoft's
      reference does not document this as an error condition - see the Test-ReconciledCount
      function below.

    Sources (Microsoft Learn, verify before production use):
    - Discovery - Query REST reference (API version 2023-09-01) - request/response shape,
      continuationToken pagination, @search.count semantics, facets:
      https://learn.microsoft.com/rest/api/purview/datamapdataplane/discovery/query
    - Understand the Microsoft Purview Data Estate Insights application (the native report this
      scenario reproduces the KPIs of, and its structural limits):
      https://learn.microsoft.com/purview/legacy/concept-insights
    - Access control in Data Estate Insights within Microsoft Purview (confirms Data Reader can
      view but not export; only Data Curator can select "Export to CSV"):
      https://learn.microsoft.com/purview/legacy/insights-permissions
    - Tutorial: Authenticate for Microsoft Purview data-plane APIs (token acquisition, Data Reader
      role for the Catalog Data plane):
      https://learn.microsoft.com/purview/data-gov-api-rest-data-plane
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Low')]
param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$PurviewAccountEndpoint,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$TenantId,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$AppId,

    [Parameter(Mandatory)]
    [SecureString]$ClientSecret,

    [Parameter()]
    [string[]]$ObjectTypes = @('Tables', 'Files'),

    [Parameter()]
    [string]$CollectionId,

    [Parameter()]
    [ValidateSet('Full', 'Facets')]
    [string]$Mode = 'Full',

    [Parameter()]
    [ValidateRange(1, 1000)]
    [int]$FacetTopN = 25,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$TrendLogPath,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$BreakdownOutputDirectory,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$RunId = ([datetime]::UtcNow.ToString('yyyy-MM-dd')),

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$ApiVersion = '2023-09-01'
)

$ErrorActionPreference = 'Stop'
$endpoint = $PurviewAccountEndpoint.TrimEnd('/')
$queryUri = "$endpoint/datamap/api/search/query?api-version=$ApiVersion"

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

function New-QueryFilter {
    param([Parameter(Mandatory)][string]$ObjectType)
    $filter = @{ objectType = $ObjectType }
    if ($CollectionId) {
        # Documented filter shape: {"collectionId": "<name>"} combined with objectType via an
        # implicit AND when both keys are present on the same filter object (Discovery_Query_And
        # worked example uses the same flat-object-as-AND pattern for two simple conditions).
        $filter = @{ and = @(@{ objectType = $ObjectType }, @{ collectionId = $CollectionId }) }
    }
    return $filter
}

function Get-FacetBreakdown {
    param([Parameter(Mandatory)][string]$ObjectType, [Parameter(Mandatory)][string]$Token)
    $body = @{
        keywords = $null
        limit    = 1
        filter   = (New-QueryFilter -ObjectType $ObjectType)
        facets   = @(@{ facet = 'classification'; count = $FacetTopN })
    }
    $response = Invoke-RestMethod -Method Post -Uri $queryUri -ContentType 'application/json' `
        -Headers @{ Authorization = "Bearer $Token" } -Body ($body | ConvertTo-Json -Depth 10)
    $histogram = [ordered]@{}
    foreach ($item in $response.'@search.facets'.classification) {
        $histogram[$item.value] = [int]$item.count
    }
    return [pscustomobject]@{
        TotalCount            = [int]$response.'@search.count'
        ClassificationCounts  = $histogram
        ClassifiedCount       = $null   # Not computable from facets alone - see README.md Section 11.
        UnclassifiedCount     = $null
    }
}

function Get-FullBreakdown {
    # Pages through every record of this object type (page size 1000, the documented maximum) and
    # tallies classified/unclassified plus a per-classification-value histogram client-side, since
    # no Discovery - Query filter for "has any classification" is documented (README.md Section 11).
    param([Parameter(Mandatory)][string]$ObjectType, [Parameter(Mandatory)][string]$Token)

    $histogram = [ordered]@{}
    $classified = 0
    $unclassified = 0
    $recordsSeen = 0
    $continuationToken = $null

    do {
        $body = @{ keywords = $null; limit = 1000; filter = (New-QueryFilter -ObjectType $ObjectType) }
        if ($continuationToken) { $body.continuationToken = $continuationToken }

        $response = Invoke-RestMethod -Method Post -Uri $queryUri -ContentType 'application/json' `
            -Headers @{ Authorization = "Bearer $Token" } -Body ($body | ConvertTo-Json -Depth 10)

        foreach ($record in $response.value) {
            $recordsSeen++
            if ($record.classification -and $record.classification.Count -gt 0) {
                $classified++
                foreach ($value in $record.classification) {
                    $histogram[$value] = ([int]($histogram[$value] ?? 0)) + 1
                }
            }
            else {
                $unclassified++
            }
        }

        $continuationToken = $response.continuationToken
    } while ($continuationToken)

    $totalCount = [int]$response.'@search.count'
    if ($recordsSeen -ne $totalCount) {
        Write-Warning ("ObjectType '{0}': paged {1} record(s) but @search.count reported {2}. " +
            "Microsoft's reference does not document this as an error condition, but this scenario " +
            "treats a mismatch as worth investigating before trusting the classified/unclassified " +
            "split below - see README.md Section 11." -f $ObjectType, $recordsSeen, $totalCount)
    }

    return [pscustomobject]@{
        TotalCount           = $totalCount
        ClassificationCounts = $histogram
        ClassifiedCount      = $classified
        UnclassifiedCount    = $unclassified
    }
}

# --- Authenticate ---
$plainSecret = ConvertTo-PlainText -Secure $ClientSecret
try {
    $token = Get-PurviewAccessToken -TenantId $TenantId -AppId $AppId -PlainSecret $plainSecret
}
finally {
    $plainSecret = $null
}

# --- Compute KPIs for every configured object type ---
$results = foreach ($objectType in $ObjectTypes) {
    Write-Host "Querying classification coverage for objectType '$objectType'$(if ($CollectionId) { " in collection '$CollectionId'" })..." -ForegroundColor Cyan
    $breakdown = if ($Mode -eq 'Facets') { Get-FacetBreakdown -ObjectType $objectType -Token $token }
                 else { Get-FullBreakdown -ObjectType $objectType -Token $token }

    $pctClassified = if ($breakdown.TotalCount -gt 0 -and $null -ne $breakdown.ClassifiedCount) {
        [math]::Round(100.0 * $breakdown.ClassifiedCount / $breakdown.TotalCount, 1)
    } else { $null }

    [pscustomobject]@{
        RunId             = $RunId
        RunTimestampUtc   = [datetime]::UtcNow.ToString('o')
        ObjectType        = $objectType
        CollectionId      = $CollectionId
        Mode              = $Mode
        TotalAssets       = $breakdown.TotalCount
        ClassifiedAssets  = $breakdown.ClassifiedCount
        UnclassifiedAssets = $breakdown.UnclassifiedCount
        PercentClassified = $pctClassified
        DistinctClassificationValues = $breakdown.ClassificationCounts.Keys.Count
        Breakdown         = $breakdown.ClassificationCounts
    }
}

# --- Report to console regardless of -WhatIf, so a dry run still shows the computed numbers ---
foreach ($row in $results) {
    Write-Host ("[{0}] {1}: {2} total, {3} classified, {4} unclassified{5}" -f `
        $row.RunId, $row.ObjectType, $row.TotalAssets, `
        ($row.ClassifiedAssets ?? 'n/a'), ($row.UnclassifiedAssets ?? 'n/a'), `
        (if ($null -ne $row.PercentClassified) { " ($($row.PercentClassified)% classified)" } else { '' })) -ForegroundColor Green
}

# --- Write the trend-log CSV (replace-by-RunId) and per-run breakdown files ---
$trendDescription = "Write/replace RunId '$RunId' row(s) in trend log '$TrendLogPath' and breakdown file(s) in '$BreakdownOutputDirectory'"
if ($PSCmdlet.ShouldProcess($trendDescription, 'Write report files')) {
    $existingRows = @()
    if (Test-Path -Path $TrendLogPath -PathType Leaf) {
        $existingRows = @(Import-Csv -Path $TrendLogPath | Where-Object { $_.RunId -ne $RunId })
    }
    $trendRows = $existingRows + ($results | Select-Object RunId, RunTimestampUtc, ObjectType, CollectionId, Mode, `
        TotalAssets, ClassifiedAssets, UnclassifiedAssets, PercentClassified, DistinctClassificationValues)
    $trendRows | Sort-Object RunId, ObjectType | Export-Csv -Path $TrendLogPath -NoTypeInformation

    New-Item -Path $BreakdownOutputDirectory -ItemType Directory -Force | Out-Null
    foreach ($row in $results) {
        $safeObjectType = ($row.ObjectType -replace '[^A-Za-z0-9]', '')
        $breakdownPath = Join-Path $BreakdownOutputDirectory "$RunId-$safeObjectType-classifications.json"
        $row | ConvertTo-Json -Depth 10 | Set-Content -Path $breakdownPath -Encoding utf8
    }
    Write-Host "`nTrend log updated: $TrendLogPath" -ForegroundColor Cyan
    Write-Host "Per-run breakdown files written to: $BreakdownOutputDirectory" -ForegroundColor Cyan
}
else {
    Write-Verbose "WhatIf: would $trendDescription"
}
```