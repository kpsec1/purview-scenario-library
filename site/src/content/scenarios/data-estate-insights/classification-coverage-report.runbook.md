---
part: "runbook"
parent: "data-estate-insights/classification-coverage-report"
---
## Implementation steps

### Portal path (view the native report first, to understand what this scenario reproduces)

1. Open the Microsoft Purview portal → **Unified Catalog** → **Health management** → **Reports**
   (or, on the classic portal, **Data Estate Insights**) → select the **Classic classifications**
   report.
2. Note the KPIs shown - classified sources/files/tables, top classification categories, a 30-day
   classification-activity trend - and, if you hold Data Curator, try **Export to CSV**. A Data
   Reader with only the Insights Reader role will see the report but not the export option
   - this is the specific gap this scenario's script closes at a lower privilege
   level.
3. Confirm the target collection(s) already have at least one completed scan (e.g.
   *Scan Azure SQL Database and Classify Sensitive Columns*'s own output for `customerdb.dbo.Customers`).
4. Assign the automation identity's service principal the **Data Reader** role on the collection(s)
   in scope: **Data Map** → **Collections** → select the collection → **Role assignments** → add
   under **Data readers**.

### Script path (idempotent by RunId, parameterized, dry-run capable)

```powershell
# 1. Dry run - queries live data and prints the computed KPIs, writes nothing to disk
./deploy/Export-ClassificationCoverageReport.ps1 `
    -PurviewAccountEndpoint 'https://api.purview-service.microsoft.com' `
    -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
    -ObjectTypes 'Tables','Files' -CollectionId 'customerdb' `
    -TrendLogPath './deploy/out/classification-coverage-trend.csv' `
    -BreakdownOutputDirectory './deploy/out/breakdowns' -WhatIf

# 2. Run for real - writes/replaces today's row(s) in the trend log and a breakdown file per object type
./deploy/Export-ClassificationCoverageReport.ps1 `
    -PurviewAccountEndpoint 'https://api.purview-service.microsoft.com' `
    -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
    -ObjectTypes 'Tables','Files' -CollectionId 'customerdb' `
    -TrendLogPath './deploy/out/classification-coverage-trend.csv' `
    -BreakdownOutputDirectory './deploy/out/breakdowns'

# 3. Validate - file-integrity checks, plus an optional live reconciliation against current data
./validate/Test-ClassificationCoverageReport.ps1 `
    -TrendLogPath './deploy/out/classification-coverage-trend.csv' `
    -PurviewAccountEndpoint 'https://api.purview-service.microsoft.com' `
    -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret
```

Both scripts use the **Microsoft Purview Data Map / Discovery REST API** - automation surface 4 per
[Automation surface, section 1](/docs/automation-surface/#1-five-automation-surfaces-not-one-read-this-first) - the same surface this library's Data Map, Unified Catalog, and Data
Lineage scenarios already use. Token acquisition follows the same client-credentials pattern already
established by this library's other surface-4 scripts.

**Scheduling:** this scenario ships no scheduler-specific code - wire
`deploy/Export-ClassificationCoverageReport.ps1` into whatever recurring-execution mechanism the
organization already runs other PowerShell automation on (Azure Automation runbook, a scheduled Azure
Function, cron, or Windows Task Scheduler), pointing `-TrendLogPath`/`-BreakdownOutputDirectory` at
persistent storage (a repo path that gets committed, a mounted share, or blob storage). One run per
day (the default `-RunId` grain) is the right cadence for a board/GRC reporting use case; a
higher-frequency SIEM feed should pass an explicit `-RunId` per invocation instead.

## Configuration reference

| Setting | Value this scenario uses | Notes |
|---|---|---|
| Object types reported by default | `Tables`, `Files` | Mirrors the native Classic classifications report's own classified-files/classified-tables split. Other confirmed valid values: `Folders`, `Glossary terms`, `Dashboards`, `Data pipelines`, `Reports`, `Stored procedures` |
| Classified/unclassified computation | Client-side tally of each `SearchResultValue.classification[]` array (empty vs. non-empty), from paginated `-Mode Full` results | Matches the native "Unclassified assets" KPI's own definition - "Assets with no system or custom classification on the entity or its columns" - computed from a different, scriptable primitive. No documented Discovery - Query request filter exists for "has any/no classification" - see the known limitations |
| Total-count source | The same query's own `@search.count` field | Documented as authoritative - "the total number of search results, not the number of documents in a single page" |
| Pagination | `continuationToken`, page size 1000 (the documented maximum) | Every page's record count is reconciled against `@search.count`; a mismatch is a warning, not a silent gap - see the known limitations |
| Fast-path alternative | `-Mode Facets` - one faceted query per object type, top-N classification counts only | Matches the native "Top classifications" chart's own double-counting behavior for multi-classified assets; cannot compute an unclassified count - see the known limitations |
| Report role | **Data Reader** | Catalog Data-plane read access - narrower than the native report's own Data-Curator-only export gate |
| API version pinned by both scripts | `2023-09-01` | Confirmed current via direct fetch of the Discovery - Query REST reference page |
| `-PurviewAccountEndpoint` accepted values | `https://api.purview-service.microsoft.com` (new portal) or `https://<account>.purview.azure.com` (classic portal) | Both explicitly confirmed valid for this `/datamap/api/...` path family - same dual-endpoint precedent as *Close Gaps and Validate End-to-End Customer Data Lineage* |
| Idempotency key | `-RunId` (default: current UTC date, `yyyy-MM-dd`) | Re-running for the same `RunId` **replaces** that RunId's trend-log row(s) rather than duplicating - see the design notes |

Full REST-body grounding: `deploy/Export-ClassificationCoverageReport.ps1` and
`validate/Test-ClassificationCoverageReport.ps1` inline comments and their `.NOTES` blocks cite the
exact Microsoft Learn reference pages.

## Operations and tuning

**KPIs to watch (first 30 days):**
- **Percent classified, trended over time, per object type.** A flat or declining trend after new
  sources are onboarded is the signal this report exists to surface - Microsoft's own guidance
  frames the equivalent native metric the same way, as something to act on ("identify content...
  and understand required actions, such as adding extra security... or moving content to a more
  secure location").
- **Distinct classification values observed, per run.** A sudden drop can mean a scan failed
  silently or a scan rule set was narrowed; a sudden rise can mean a new, unreviewed data pattern
  entered the estate.
- **`[WARN]` frequency from the live-reconciliation check** - a `[WARN]` that clears on the next
  scheduled run is expected drift (a rescan happened between runs); one that persists across two or
  more runs is worth investigating as a possible stale trend log or a scope (`-CollectionId`)
  mismatch.

**Alert routing:** this scenario produces flat files (CSV/JSON), not a Purview-native alert or a
`GenerateAlert`-style action - there is nothing to wire into a native Purview alert channel. Route
`validate/Test-ClassificationCoverageReport.ps1`'s non-zero exit code into whatever CI/ops alerting
the deploying organization already uses for scheduled scripts, the same pattern this library's Data Quality and Data
Lineage scenarios recommend for their own validate scripts. For a SIEM feed, ingest the trend-log
CSV or per-run breakdown JSON directly - this scenario deliberately does not build a bespoke
Sentinel/Log Analytics sink.

**Incident-response runbook (a `[WARN]`/`[FAIL]` appears):** the validate script's two check
categories map to two different severities and two different remediations - a pipeline's alerting
should be built to treat them differently, not react identically to every non-`[PASS]` line.
1. **Triage** - a **file-integrity `[FAIL]`** (arithmetic or duplicate-row check) points at the trend
   log itself, not live data: check for manual edits to the CSV, or a version of this script older
   than the one that introduced the replace-by-RunId behavior. This category is always a hard
   failure worth blocking on.
2. **A live-reconciliation `[WARN]`** most often means the report is stale relative to a rescan or
   bulk change - re-run `deploy/Export-ClassificationCoverageReport.ps1` and re-validate before
   assuming anything is actually wrong. This category is a soft signal, not a block.
3. **A `Write-Warning` from the deploy script itself** ("paged N record(s) but @search.count
   reported M") means the pagination loop's tally and the API's own reported total disagree.
   `Write-Warning` output is on PowerShell's warning stream, not the `Write-Host` console summary a
   human glancing at scheduled-job output might see - a scheduled/unattended pipeline must capture
   the warning stream explicitly (e.g. `-WarningVariable`, or redirecting stream 3) to not miss this
   signal. Re-run before trusting that run's classified/unclassified split; if it recurs, treat it as
   a signal worth raising with Microsoft support rather than silently trusting either number.

**Review cadence:** re-run on whatever cadence the consuming report (board deck, GRC tool, SIEM)
needs - daily is the default grain this scenario's `-RunId` assumes; review the trend for
unexpected drops in coverage at least monthly regardless of automation cadence.

## Rollback and decommission

See the rollback runbook for the full procedure. Quick reference: this scenario creates **no Purview
object** - there is nothing in the Purview account itself to roll back. Decommissioning means
stopping the scheduled execution of `deploy/Export-ClassificationCoverageReport.ps1`, removing the
Data Reader role assignment for the reporting service principal, and deciding what to do with the
already-produced trend-log/breakdown files per the deploying organization's own data-retention policy.

## References

1. Understand the Microsoft Purview Data Estate Insights application (report categories: Health,
   Inventory and ownership, Curation and governance) - <https://learn.microsoft.com/purview/legacy/concept-insights>
2. Understand the classic classifications report in Unified Catalog (report contents, prerequisites,
   permissions, drilldown) - <https://learn.microsoft.com/purview/unified-catalog-reports-classic-classifications>
3. Understand the classic assets report in Unified Catalog ("Unclassified assets" KPI definition) - <https://learn.microsoft.com/purview/unified-catalog-reports-classic-assets>
4. Disable Data Estate Insights or report refresh (weekly default refresh cadence; no separate
   billing) - <https://learn.microsoft.com/purview/legacy/disable-data-estate-insights>
5. Discovery - Query REST reference (API version 2023-09-01) - request/response shape, facets,
   continuationToken pagination, @search.count semantics, worked filter/facet examples - <https://learn.microsoft.com/rest/api/purview/datamapdataplane/discovery/query>
6. Access control in the classic Microsoft Purview governance portal (Data reader/Data curator/
   Insights reader/Collection administrator role definitions) - <https://learn.microsoft.com/purview/data-gov-classic-permissions>
7. Access control in Data Estate Insights within Microsoft Purview (Insights Reader role assignment;
   confirms a Data Reader can view but not export the native report) - <https://learn.microsoft.com/purview/legacy/insights-permissions>
8. [Microsoft Purview] How to filter Entity by classification - Microsoft Q&A (corroborates that no
   "has any/no classification" Discovery - Query filter is documented) - <https://learn.microsoft.com/answers/a/12132915>
9. Tutorial: Authenticate for Microsoft Purview data-plane APIs (service principal setup, Data Reader
   role for the Catalog Data plane, token acquisition) - <https://learn.microsoft.com/purview/data-gov-api-rest-data-plane>
10. Microsoft Purview data governance glossary (Data reader, Data curator, Data Estate Insights, Data
    Map definitions) - <https://learn.microsoft.com/purview/data-governance-glossary>
11. GraphQL API with Microsoft Purview (preview) - confirms both `api.purview-service.microsoft.com`
    (new portal) and `{account}.purview.azure.com` (classic portal) as valid endpoint hosts for the
    `/datamap/api/...` path family - <https://learn.microsoft.com/purview/data-gov-api-graphql>

> Re-verify all links and the known limitations limitations against current Microsoft Learn before a
> customer-facing deployment - Microsoft's own Data Map REST surface is explicitly called out
> elsewhere in this library (*Scan Azure SQL Database and Classify Sensitive Columns* (the known limitations)) as
> evolving.