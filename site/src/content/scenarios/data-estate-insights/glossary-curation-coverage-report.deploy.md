---
part: "deploy"
parent: "data-estate-insights/glossary-curation-coverage-report"
---
The scripts and configuration below deploy this scenario. Review them, then run in order — each is designed to be idempotent and has a matching rollback.


#### `Export-GlossaryCurationCoverageReport.ps1`

```powershell
#Requires -Version 7.0
<#
.SYNOPSIS
    Produces an exportable, historical glossary-curation-coverage report for Microsoft Purview
    Unified Catalog terms, reproducing the KPI *categories* of the native Data Estate Insights
    "Classic glossary" report against the term model this repo's own glossary scenario actually
    uses (Unified Catalog Terms), not the classic report's own Atlas-based model.

.DESCRIPTION
    Calls the Microsoft Purview Unified Catalog REST API (automation surface 4 per
    docs/automation-surface.md Section 1, API version 2026-03-20-preview - the same version
    scenarios/unified-catalog/curate-business-glossary/ already pins) to compute, per configured
    governance domain:
      - Total term count, by status (DRAFT / PUBLISHED / EXPIRED - the confirmed CatalogModelStatus
        enum; the classic report's fourth status, "Alert", has no field on the new Term object and
        is never fabricated here - see README.md Section 11 and design.md Section 4/8).
      - Completeness: terms missing a definition (empty/whitespace description), missing an owner
        (empty contacts.owner - the closest documented analog of the classic report's "steward"
        concept, not a confirmed equivalence), missing an expert (empty contacts.expert), or missing
        multiple (2+ of the above).
      - Asset attachment: for each term, whether it is linked to at least one data asset, via the
        only documented relationship-read primitive for this question - GET
        terms/{id}/relationships?entityType=DATAASSET (an N+1 API-call pattern, opt out with
        -SkipAssetLinkCheck - see README.md Section 11).

    Every call is a read-only GET - this script never creates, modifies, or deletes any Purview
    object. The only side effect is the trend-log CSV and per-run breakdown file this script writes,
    which IS gated behind $PSCmdlet.ShouldProcess() so -WhatIf reports what would be written without
    touching disk (the read calls themselves still execute under -WhatIf, so the console summary is
    accurate - same precedent as curate-business-glossary/README.md Section 11).

    Idempotency model: re-running this script for the same -RunId (default: current UTC date,
    'yyyy-MM-dd') REPLACES that RunId's row(s) in the trend log rather than appending a duplicate.
    See design.md Section 5.

    Role model (design.md Section 2 goal 2): a DRAFT-status term is documented as visible only to
    Data Stewards and Governance Domain Owners - a pure reader credential cannot see it. This script
    therefore defaults to requiring Data Steward on every -DomainIds value (full status coverage).
    Pass -PublishedOnly to run as Global/Local Catalog Reader instead - Draft/Expired-dependent KPIs
    are reported as $null ("N/A") in that mode, never a false zero.

    Author-only reference code. Never connects to a live tenant unless you supply real credentials
    and omit -WhatIf. Assumes the target domain(s) already have glossary terms authored - see
    README.md Section 3/6.

.PARAMETER PurviewAccountEndpoint
    Base URL of the Purview Unified Catalog data-plane API. Use
    'https://api.purview-service.microsoft.com' for tenants on the current Microsoft Purview portal,
    or 'https://<account>.purview.azure.com' for the classic portal - same dual-endpoint precedent as
    curate-business-glossary and classification-coverage-report.

.PARAMETER TenantId
    Microsoft Entra tenant ID.

.PARAMETER AppId
    Application (client) ID of the service principal used to call the Unified Catalog Terms API.
    Must hold Data Steward (default mode) or Global/Local Catalog Reader (-PublishedOnly) on every
    domain in -DomainIds.

.PARAMETER ClientSecret
    Client secret for -AppId, as a SecureString. Resolve from a vault at run time - never hard-code.

.PARAMETER DomainIds
    One or more Unified Catalog governance-domain GUIDs to report on. Required - this API has no
    "all domains" scope the calling identity's role would otherwise limit implicitly.

.PARAMETER PublishedOnly
    Switch. Runs the report using only the Terms - List operation's own visibility for a
    non-Data-Steward caller (Global/Local Catalog Reader), which Microsoft documents as returning
    only published artifacts. Draft- and Expired-count/completeness KPIs are reported as $null
    ("N/A") rather than 0 in this mode, since they cannot be measured accurately without Data
    Steward - see README.md Section 11.

.PARAMETER SkipAssetLinkCheck
    Switch. Skips the per-term List Related Entities call that determines with-assets/without-assets
    status. Use at large glossary scale to avoid the N+1 API-call cost (design.md Section 2 goal 3);
    the report's AssetLinkage-dependent fields are written as "Skipped" rather than computed.

.PARAMETER PageSize
    Terms - List 'top' page size. Microsoft's reference documents no maximum for this parameter, so
    this defaults to a conservative 100 rather than assuming Discovery - Query's unrelated 1000-row
    maximum applies here too - see README.md Section 11.

.PARAMETER TrendLogPath
    Path to the append/replace-by-RunId CSV trend log. Created with a header row if it doesn't
    already exist. One row is written per (RunId, DomainId) combination.

.PARAMETER BreakdownOutputDirectory
    Directory to write this run's full breakdown (incomplete-term names, unlinked-published-term
    names) as '<RunId>-<DomainId>-glossary-breakdown.json'. Created if it doesn't already exist.

.PARAMETER RunId
    Identifier for this report run, used both as a trend-log column and to make re-runs replace
    rather than duplicate. Defaults to the current UTC date ('yyyy-MM-dd').

.PARAMETER ApiVersion
    Unified Catalog REST API version to pin. Defaults to '2026-03-20-preview', the same version
    curate-business-glossary and docs/automation-surface.md Section 4 already pin.

.PARAMETER WhatIf
    Standard PowerShell ShouldProcess dry-run. All read-only Terms calls still execute (needed to
    report accurate would-be numbers), but neither the trend-log CSV nor the breakdown file is
    written - the script prints what it would have written instead.

.EXAMPLE
    ./Export-GlossaryCurationCoverageReport.ps1 -PurviewAccountEndpoint 'https://api.purview-service.microsoft.com' `
        -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret -DomainIds $DomainId `
        -TrendLogPath './out/glossary-curation-trend.csv' -BreakdownOutputDirectory './out/breakdowns' -WhatIf

    Dry run: queries live data and prints the computed KPIs, writes nothing to disk.

.EXAMPLE
    ./Export-GlossaryCurationCoverageReport.ps1 -PurviewAccountEndpoint 'https://api.purview-service.microsoft.com' `
        -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret -DomainIds $DomainId -PublishedOnly `
        -TrendLogPath './out/glossary-curation-trend.csv' -BreakdownOutputDirectory './out/breakdowns'

    Lower-privilege run (Global/Local Catalog Reader) - published terms only, Draft/Expired KPIs
    reported as N/A.

.NOTES
    VERIFY before production use (see README.md Section 11 for full detail):
    - No documented maximum 'top' value for Terms - List - -PageSize defaults conservatively to 100.
    - Terms - Get Facets' facets[].name values are not enumerated by Microsoft (only a worked
      'owner' example exists) - this script does not attempt an unconfirmed 'status'/'hasAssets'
      facet request as a faster alternative to the client-side tally implemented here.
    - The classic glossary report's "Approved"/"Alert" status vocabulary and "steward" contact
      concept do not map 1:1 onto the new Term object's DRAFT/PUBLISHED/EXPIRED status and
      owner/expert/databaseAdmin contact types - this script's mapping choices are documented in
      design.md Section 4, not asserted as Microsoft-confirmed equivalences.

    Sources (Microsoft Learn, verify before production use):
    - Purview Unified Catalog REST API - Terms - List / Terms - Get (Term schema, status enum,
      ContactsMap, PagedTerm nextLink pagination):
      https://learn.microsoft.com/rest/api/purview/purview-unified-catalog/terms/list?view=rest-purview-purview-unified-catalog-2026-03-20-preview
    - Purview Unified Catalog REST API - Terms - List Related Entities:
      https://learn.microsoft.com/rest/api/purview/purview-unified-catalog/terms/list-related-entities?view=rest-purview-purview-unified-catalog-2026-03-20-preview
    - Understand the classic glossary report in Unified Catalog (the native report this scenario
      reproduces the KPI categories, not the exact source, of):
      https://learn.microsoft.com/purview/unified-catalog-reports-classic-glossary
    - Create and manage glossary terms (DRAFT visibility limited to Data Stewards/Governance Domain
      Owners):
      https://learn.microsoft.com/purview/unified-catalog-glossary-terms-create-manage
    - Data governance roles and permissions in Microsoft Purview (Global/Local Catalog Reader read
      only published artifacts):
      https://learn.microsoft.com/purview/data-governance-roles-permissions
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

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string[]]$DomainIds,

    [Parameter()]
    [switch]$PublishedOnly,

    [Parameter()]
    [switch]$SkipAssetLinkCheck,

    [Parameter()]
    [ValidateRange(1, 1000)]
    [int]$PageSize = 100,

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
    [string]$ApiVersion = '2026-03-20-preview'
)

$ErrorActionPreference = 'Stop'
$endpoint = $PurviewAccountEndpoint.TrimEnd('/')

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

function Get-AllTermsInDomain {
    # Pages Terms - List via 'nextLink' (skip/top), a different pagination primitive from Discovery
    # - Query's continuationToken (classification-coverage-report's own sibling) - see design.md
    # Section 6. No documented maximum 'top' exists, so -PageSize defaults conservatively.
    param([Parameter(Mandatory)][string]$DomainId, [Parameter(Mandatory)][string]$Token)

    $terms = [System.Collections.Generic.List[object]]::new()
    $skip = 0
    do {
        $uri = "$endpoint/datagovernance/catalog/terms?api-version=$ApiVersion&domainId=$DomainId&skip=$skip&top=$PageSize"
        $response = Invoke-RestMethod -Method Get -Uri $uri -Headers @{ Authorization = "Bearer $Token" }
        foreach ($term in $response.value) { $terms.Add($term) }
        $skip += $PageSize
    } while ($response.nextLink)

    return $terms
}

function Test-TermHasAssets {
    # Only documented primitive for "is this term linked to any data asset" - GET
    # terms/{id}/relationships?entityType=DATAASSET. An N+1 call per term - design.md Section 2 goal 3.
    param([Parameter(Mandatory)][string]$TermId, [Parameter(Mandatory)][string]$Token)

    $uri = "$endpoint/datagovernance/catalog/terms/$TermId/relationships?api-version=$ApiVersion&entityType=DATAASSET"
    $response = Invoke-RestMethod -Method Get -Uri $uri -Headers @{ Authorization = "Bearer $Token" }
    return @($response.value).Count -gt 0
}

function Get-DomainBreakdown {
    param([Parameter(Mandatory)][string]$DomainId, [Parameter(Mandatory)][string]$Token)

    $terms = Get-AllTermsInDomain -DomainId $DomainId -Token $Token

    $statusCounts = [ordered]@{ DRAFT = 0; PUBLISHED = 0; EXPIRED = 0 }
    $incompleteNames = [System.Collections.Generic.List[string]]::new()
    $missingDefinition = 0; $missingOwner = 0; $missingExpert = 0; $missingMultiple = 0
    $publishedWithAssets = 0; $publishedWithoutAssets = 0
    $expiredWithAssets = 0
    $unlinkedPublishedNames = [System.Collections.Generic.List[string]]::new()

    foreach ($term in $terms) {
        $status = [string]$term.status
        if ($statusCounts.Contains($status)) { $statusCounts[$status]++ }

        $noDefinition = [string]::IsNullOrWhiteSpace($term.description)
        $noOwner = -not ($term.contacts -and $term.contacts.owner -and @($term.contacts.owner).Count -gt 0)
        $noExpert = -not ($term.contacts -and $term.contacts.expert -and @($term.contacts.expert).Count -gt 0)
        $gapCount = @($noDefinition, $noOwner, $noExpert) | Where-Object { $_ } | Measure-Object | Select-Object -ExpandProperty Count

        if ($noDefinition) { $missingDefinition++ }
        if ($noOwner) { $missingOwner++ }
        if ($noExpert) { $missingExpert++ }
        if ($gapCount -ge 2) { $missingMultiple++ }
        if ($gapCount -ge 1) { $incompleteNames.Add($term.name) }

        if (-not $SkipAssetLinkCheck -and ($status -eq 'PUBLISHED' -or $status -eq 'EXPIRED')) {
            $hasAssets = Test-TermHasAssets -TermId $term.id -Token $Token
            if ($status -eq 'PUBLISHED') {
                if ($hasAssets) { $publishedWithAssets++ } else { $publishedWithoutAssets++; $unlinkedPublishedNames.Add($term.name) }
            }
            elseif ($status -eq 'EXPIRED' -and $hasAssets) {
                $expiredWithAssets++
            }
        }
    }

    return [pscustomobject]@{
        TotalTerms              = $terms.Count
        StatusCounts            = $statusCounts
        MissingDefinition       = $missingDefinition
        MissingOwner            = $missingOwner
        MissingExpert           = $missingExpert
        MissingMultiple         = $missingMultiple
        IncompleteTermNames     = $incompleteNames
        PublishedWithAssets     = if ($SkipAssetLinkCheck) { $null } else { $publishedWithAssets }
        PublishedWithoutAssets  = if ($SkipAssetLinkCheck) { $null } else { $publishedWithoutAssets }
        ExpiredWithAssets       = if ($SkipAssetLinkCheck) { $null } else { $expiredWithAssets }
        UnlinkedPublishedNames  = $unlinkedPublishedNames
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

if ($PublishedOnly) {
    Write-Host "Running in -PublishedOnly mode: Draft/Expired-dependent KPIs will be reported as N/A. Requires only Global/Local Catalog Reader." -ForegroundColor Yellow
}

# --- Compute KPIs for every configured domain ---
$results = foreach ($domainId in $DomainIds) {
    Write-Host "Querying glossary curation coverage for domain '$domainId'..." -ForegroundColor Cyan
    $breakdown = Get-DomainBreakdown -DomainId $domainId -Token $token

    $draftCount = if ($PublishedOnly) { $null } else { $breakdown.StatusCounts.DRAFT }
    $expiredCount = if ($PublishedOnly) { $null } else { $breakdown.StatusCounts.EXPIRED }

    [pscustomobject]@{
        RunId                  = $RunId
        RunTimestampUtc        = [datetime]::UtcNow.ToString('o')
        DomainId               = $domainId
        PublishedOnly          = [bool]$PublishedOnly
        AssetLinkCheckSkipped  = [bool]$SkipAssetLinkCheck
        TotalTerms             = $breakdown.TotalTerms
        DraftTerms             = $draftCount
        PublishedTerms         = $breakdown.StatusCounts.PUBLISHED
        ExpiredTerms           = $expiredCount
        MissingDefinition      = $breakdown.MissingDefinition
        MissingOwner           = $breakdown.MissingOwner
        MissingExpert          = $breakdown.MissingExpert
        MissingMultiple        = $breakdown.MissingMultiple
        PublishedWithAssets    = $breakdown.PublishedWithAssets
        PublishedWithoutAssets = $breakdown.PublishedWithoutAssets
        ExpiredWithAssets      = $breakdown.ExpiredWithAssets
        IncompleteTermNames    = $breakdown.IncompleteTermNames
        UnlinkedPublishedNames = $breakdown.UnlinkedPublishedNames
    }
}

# --- Report to console regardless of -WhatIf, so a dry run still shows the computed numbers ---
foreach ($row in $results) {
    Write-Host ("[{0}] Domain {1}: {2} total terms (Draft={3}, Published={4}, Expired={5}); " +
        "Published-with-assets={6}, Published-without-assets={7}; {8} incomplete term(s)" -f `
        $row.RunId, $row.DomainId, $row.TotalTerms, ($row.DraftTerms ?? 'N/A'), $row.PublishedTerms, `
        ($row.ExpiredTerms ?? 'N/A'), ($row.PublishedWithAssets ?? 'skipped'), `
        ($row.PublishedWithoutAssets ?? 'skipped'), $row.IncompleteTermNames.Count) -ForegroundColor Green
}

# --- Write the trend-log CSV (replace-by-RunId) and per-run breakdown files ---
$trendDescription = "Write/replace RunId '$RunId' row(s) in trend log '$TrendLogPath' and breakdown file(s) in '$BreakdownOutputDirectory'"
if ($PSCmdlet.ShouldProcess($trendDescription, 'Write report files')) {
    $existingRows = @()
    if (Test-Path -Path $TrendLogPath -PathType Leaf) {
        $existingRows = @(Import-Csv -Path $TrendLogPath | Where-Object { $_.RunId -ne $RunId })
    }
    $trendRows = $existingRows + ($results | Select-Object RunId, RunTimestampUtc, DomainId, PublishedOnly, `
        AssetLinkCheckSkipped, TotalTerms, DraftTerms, PublishedTerms, ExpiredTerms, MissingDefinition, `
        MissingOwner, MissingExpert, MissingMultiple, PublishedWithAssets, PublishedWithoutAssets, ExpiredWithAssets)
    $trendRows | Sort-Object RunId, DomainId | Export-Csv -Path $TrendLogPath -NoTypeInformation

    New-Item -Path $BreakdownOutputDirectory -ItemType Directory -Force | Out-Null
    foreach ($row in $results) {
        $breakdownPath = Join-Path $BreakdownOutputDirectory "$RunId-$($row.DomainId)-glossary-breakdown.json"
        $row | ConvertTo-Json -Depth 10 | Set-Content -Path $breakdownPath -Encoding utf8
    }
    Write-Host "`nTrend log updated: $TrendLogPath" -ForegroundColor Cyan
    Write-Host "Per-run breakdown files written to: $BreakdownOutputDirectory" -ForegroundColor Cyan
}
else {
    Write-Verbose "WhatIf: would $trendDescription"
}
```