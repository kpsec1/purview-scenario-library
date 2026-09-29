---
part: "runbook"
parent: "data-estate-insights/sensitivity-label-coverage-report"
---
## Implementation steps

### Portal path (view the native report first, to understand what this scenario reproduces)

1. Confirm "Extend sensitivity labels to Data Map" is turned on for the tenant and at least one
   asset already carries a label - **Microsoft Purview portal → Information Protection →
   Sensitivity labels**, confirm the label(s) in scope are scoped to **Files & other data assets**,
   then re-scan (or wait for the next scheduled scan of) the target source. This is a manual, licensed, preview-capability prerequisite -
   see the prerequisites and the known limitations - not something this scenario's scripts configure.
2. Open the Microsoft Purview portal → **Unified Catalog** → **Health management** → **Reports** (or,
   on the classic portal, **Data Estate Insights**) → select the **Classic sensitivity labels** report.
3. Note the KPIs shown - number of subscriptions, unique labels applied, sources/files/tables
   labeled, top labels applied, a 30-day labeling-activity trend - and, if you hold Data Curator, try
   **Export to CSV**. A Data Reader with only the Insights Reader (or Data health reader) role will
   see the report but not the export option - this is the specific gap this
   scenario's script closes at a lower privilege level.
4. Confirm the target collection(s) already have at least one completed scan and at least one labeled
   asset (step 1).
5. Assign the automation identity's service principal the **Data Reader** role on the collection(s) in
   scope: **Data Map** → **Collections** → select the collection → **Role assignments** → add under
   **Data readers**.

### Script path (idempotent by RunId, parameterized, dry-run capable)

```powershell
# 1. Dry run - queries live data and prints the computed KPIs, writes nothing to disk
./deploy/Export-SensitivityLabelCoverageReport.ps1 `
    -PurviewAccountEndpoint 'https://api.purview-service.microsoft.com' `
    -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
    -ObjectTypes 'Tables','Files' -CollectionId 'customerdb' `
    -TrendLogPath './deploy/out/sensitivity-label-coverage-trend.csv' `
    -BreakdownOutputDirectory './deploy/out/breakdowns' -WhatIf

# 2. Run for real - writes/replaces today's row(s) in the trend log and a breakdown file per object type
./deploy/Export-SensitivityLabelCoverageReport.ps1 `
    -PurviewAccountEndpoint 'https://api.purview-service.microsoft.com' `
    -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
    -ObjectTypes 'Tables','Files' -CollectionId 'customerdb' `
    -TrendLogPath './deploy/out/sensitivity-label-coverage-trend.csv' `
    -BreakdownOutputDirectory './deploy/out/breakdowns'

# 3. Validate - file-integrity checks, plus an optional live reconciliation against current data
./validate/Test-SensitivityLabelCoverageReport.ps1 `
    -TrendLogPath './deploy/out/sensitivity-label-coverage-trend.csv' `
    -PurviewAccountEndpoint 'https://api.purview-service.microsoft.com' `
    -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret
```

Both scripts use the **Microsoft Purview Data Map / Discovery REST API** - automation surface 4 per
[Automation surface, section 1](/docs/automation-surface/#1-five-automation-surfaces-not-one-read-this-first) - the same surface this library's Data Map, Unified Catalog, Data
Lineage, and sibling *Exportable, Historical Classification Coverage Report* scenarios already use. Token acquisition follows
the same client-credentials pattern already established by this library's other surface-4 scripts.

**Scheduling:** this scenario ships no scheduler-specific code - wire
`deploy/Export-SensitivityLabelCoverageReport.ps1` into whatever recurring-execution mechanism the
organization already runs other PowerShell automation on (Azure Automation runbook, a scheduled Azure
Function, cron, or Windows Task Scheduler), pointing `-TrendLogPath`/`-BreakdownOutputDirectory` at
persistent storage. Run it alongside (never in place of) the sibling
`classification-coverage-report/deploy/Export-ClassificationCoverageReport.ps1` - the two scripts
write distinct file names and never collide. One run per day (the default `-RunId` grain) is the right
cadence for a board/GRC reporting use case; a higher-frequency SIEM feed should pass an explicit
`-RunId` per invocation instead.

## Configuration reference

| Setting | Value this scenario uses | Notes |
|---|---|---|
| Object types reported by default | `Tables`, `Files` | Mirrors both the native Classic sensitivity labels report's own files/tables-labeled split and the sibling *Exportable, Historical Classification Coverage Report* scenario's default |
| Labeled/unlabeled computation | Client-side tally of each `SearchResultValue.label[]` array (empty vs. non-empty), from paginated `-Mode Full` results | No documented Discovery - Query request filter exists for "has any/no label" (only a documented `classification`-value filter) - see the known limitations |
| Total-count source | The same query's own `@search.count` field | Documented as authoritative - "the total number of search results, not the number of documents in a single page" |
| Pagination | `continuationToken`, page size 1000 (the documented maximum) | Every page's record count is reconciled against `@search.count`; a mismatch is a warning, not a silent gap - see the known limitations |
| Fast-path alternative | `-Mode Facets` - one faceted query per object type, using the confirmed `label` facet, top-N label counts only | Matches the native "Top labels applied across sources/files/tables" charts' own double-counting behavior for multi-labeled assets; cannot compute an unlabeled count - see the known limitations |
| Report role | **Data Reader** | Catalog Data-plane read access - narrower than the native report's own Data-Curator-only export gate |
| API version pinned by both scripts | `2023-09-01` | Same Discovery - Query REST reference page and version already confirmed current for the sibling *Exportable, Historical Classification Coverage Report* scenario, re-confirmed via direct fetch for this build |
| `-PurviewAccountEndpoint` accepted values | `https://api.purview-service.microsoft.com` (new portal) or `https://<account>.purview.azure.com` (classic portal) | Both explicitly confirmed valid for this `/datamap/api/...` path family - same dual-endpoint precedent as the sibling scenario and *Close Gaps and Validate End-to-End Customer Data Lineage* |
| Idempotency key | `-RunId` (default: current UTC date, `yyyy-MM-dd`) | Re-running for the same `RunId` **replaces** that RunId's trend-log row(s) rather than duplicating - see the design notes |

Full REST-body grounding: `deploy/Export-SensitivityLabelCoverageReport.ps1` and
`validate/Test-SensitivityLabelCoverageReport.ps1` inline comments and their `.NOTES` blocks cite the
exact Microsoft Learn reference pages.

## Operations and tuning

**KPIs to watch (first 30 days):**
- **Percent labeled, trended over time, per object type.** A flat or declining trend after new
  sources are onboarded is the signal this report exists to surface - Microsoft's own guidance frames
  the equivalent native purpose the same way: "identify the sensitivity labels found in your content
  and understand required actions, such as managing access to specific repositories or files".
- **Distinct label values observed, per run.** A sudden drop can mean the "extend sensitivity labels
  to Data Map" capability was disabled, a scoped label's scope was changed away from "Files & other
  data assets," or a scan failed silently; a sudden rise can mean a new, unreviewed label taxonomy
  entered the estate.
- **`PercentLabeled` broken out by `-ObjectTypes`/`-CollectionId`, not read as one blended estate-wide
  number.** Onboarding a new collection or object type that is on Microsoft's documented list of Data
  Map sensitivity-label sources (Azure Blob Storage, ADLS Gen1/Gen2, SQL Server, Azure SQL Database,
  Azure SQL Managed Instance, Amazon S3, Amazon RDS (preview), Power BI) but has not yet had
  autolabeling run against it will show as 0% labeled - a coverage gap worth acting on. Onboarding a
  collection whose source type is *not* on that list will also show as 0% labeled, for a structurally
  different reason (labeling isn't available there yet, not that it was skipped) - see the known limitations. Tune
  `-ObjectTypes`/`-CollectionId` scope, or read the per-run breakdown JSON, before treating a blended
  drop as a single incident.
- **The gap between this report's `PercentLabeled` and the sibling *Exportable, Historical Classification Coverage Report*'s
  `PercentClassified`, for the same collection.** A collection with high classification coverage but
  low label coverage is a concrete signal that sensitive data has been *found* but not yet *protected*
  - the specific security-operations gap this report exists to surface, distinct from the sibling
  report's discovery-focused narrative.
- **`[WARN]` frequency from the live-reconciliation check** - a `[WARN]` that clears on the next
  scheduled run is expected drift; one that persists across two or more runs is worth investigating as
  a possible stale trend log or a scope (`-CollectionId`) mismatch.

**Alert routing:** identical to the sibling scenario - this scenario produces flat files (CSV/JSON),
not a Purview-native alert. Route `validate/Test-SensitivityLabelCoverageReport.ps1`'s non-zero exit
code into whatever CI/ops alerting the deploying organization already uses for scheduled scripts. For a SIEM feed,
ingest the trend-log CSV or per-run breakdown JSON directly - this scenario deliberately does not
build a bespoke Sentinel/Log Analytics sink.

**Incident-response runbook (a `[WARN]`/`[FAIL]` appears):** identical two-severity treatment to the
sibling scenario's own runbook - reproduced here for self-containment.
1. **Triage** - a **file-integrity `[FAIL]`** (arithmetic or duplicate-row check) points at the trend
   log itself, not live data: check for manual edits to the CSV, or a version of this script older
   than the one that introduced the replace-by-RunId behavior. This category is always a hard failure
   worth blocking on.
2. **A live-reconciliation `[WARN]`** most often means the report is stale relative to a rescan, a
   bulk relabeling, or a bulk change - re-run `deploy/Export-SensitivityLabelCoverageReport.ps1` and
   re-validate before assuming anything is actually wrong. This category is a soft signal, not a
   block.
3. **A `Write-Warning` from the deploy script itself** ("paged N record(s) but @search.count reported
   M") means the pagination loop's tally and the API's own reported total disagree. `Write-Warning`
   output is on PowerShell's warning stream, not the `Write-Host` console summary a human glancing at
   scheduled-job output might see - a scheduled/unattended pipeline must capture the warning stream
   explicitly (e.g. `-WarningVariable`, or redirecting stream 3) to not miss this signal. Re-run
   before trusting that run's labeled/unlabeled split.

**Review cadence:** re-run on whatever cadence the consuming report needs - daily is the default grain
this scenario's `-RunId` assumes; review the trend for unexpected drops in label coverage at least
monthly regardless of automation cadence, and specifically after any change to the upstream
"extend sensitivity labels to Data Map" configuration.

## Rollback and decommission

See the rollback runbook for the full procedure. Quick reference: this scenario creates **no Purview
object** - there is nothing in the Purview account itself to roll back. Decommissioning means
stopping the scheduled execution of `deploy/Export-SensitivityLabelCoverageReport.ps1`, removing the
Data Reader role assignment for the reporting service principal, and deciding what to do with the
already-produced trend-log/breakdown files per the deploying organization's own data-retention policy.

## References

1. Understand the classic sensitivity labels report in Unified Catalog (report contents, prerequisites
   including the "data curator role or insight reader role" / "data health reader" permission split,
   drilldown) - <https://learn.microsoft.com/purview/unified-catalog-reports-classic-sensitivity-labels>
2. Discovery - Query REST reference (API version 2023-09-01) - request/response shape, the `label`
   response field (`string[]`, "The labels of the asset"), the `label` facet (one of exactly four
   documented facets: `assetType`, `classification`, `contactId`, `label`), `continuationToken`
   pagination, `@search.count` semantics, and the operation's only documented worked exact-value filter
   example (`Discovery_Query_Classification`, for `classification` - no equivalent for `label`) - <https://learn.microsoft.com/rest/api/purview/datamapdataplane/discovery/query>
3. Access control in the classic Microsoft Purview governance portal (Data reader/Data curator/
   Insights reader/Collection administrator role definitions) - <https://learn.microsoft.com/purview/data-gov-classic-permissions>
4. Access control in Data Estate Insights within Microsoft Purview (Insights Reader role assignment;
   confirms a Data Reader can view but not export the native report - generic to every Data Estate
   Insights report, including sensitivity labels) - <https://learn.microsoft.com/purview/legacy/insights-permissions>
5. Understand the Microsoft Purview Data Estate Insights application (report categories; the
   "Sensitivity Labels" report's own stated purpose - "enables security administrators to ensure the
   security of the data... by identifying where sensitive data is stored") - <https://learn.microsoft.com/purview/legacy/concept-insights>
6. Learn about sensitivity labels in Data Map (preview) - the "extend sensitivity labels to Data Map"
   capability this scenario depends on, its preview status, and supported data sources - <https://learn.microsoft.com/purview/data-map-sensitivity-labels>
7. Sensitivity labels in Data Map FAQ (preview) - licensing requirements (M365 E5/A5/G5-tier license
   or PAYG for non-Microsoft-365 sources) - <https://learn.microsoft.com/purview/data-map-sensitivity-labels-faq>
8. Tutorial: Authenticate for Microsoft Purview data-plane APIs (service principal setup, Data Reader
   role for the Catalog Data plane, token acquisition) - <https://learn.microsoft.com/purview/data-gov-api-rest-data-plane>
9. Microsoft Purview data governance glossary (Data reader, Data curator, Data Estate Insights, Data
   Map definitions) - <https://learn.microsoft.com/purview/data-governance-glossary>
10. GraphQL API with Microsoft Purview (preview) - confirms both `api.purview-service.microsoft.com`
    (new portal) and `{account}.purview.azure.com` (classic portal) as valid endpoint hosts for the
    `/datamap/api/...` path family - <https://learn.microsoft.com/purview/data-gov-api-graphql>

> Re-verify all links, the preview-status callout, and the known limitations limitations against current Microsoft
> Learn before a customer-facing deployment - both this scenario's own upstream dependency (reference
> 6/7) and Microsoft's Data Map REST surface generally are explicitly called out elsewhere in this
> repo (*Scan Azure SQL Database and Classify Sensitive Columns* (the known limitations)) as evolving.