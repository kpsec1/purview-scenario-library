---
part: "design"
parent: "data-estate-insights/classification-coverage-report"
---
## 1. Problem statement

Microsoft Purview's **Data Estate Insights** application (accessed today from **Unified Catalog →
Health management → Reports** in the current portal, or **Data Estate Insights** in the classic
portal, `README.md` reference 1) already ships a **Classic classifications** report showing
exactly the KPIs a governance stakeholder wants: number of classified sources/files/tables, top
classification categories, and a 30-day classification-activity trend. It is automatically
generated, requires no scripting, and is the right first stop for anyone exploring their estate's
classification posture interactively.

It has three structural limits that make it insufficient as the *only* mechanism for a buyer that
needs this data outside the portal:

1. **No REST API of its own.** The report is a managed Power BI-style dashboard; there is no
 documented endpoint that returns its computed KPIs (classified-source count, top-classification
 list, etc.) for a script to consume. A team that wants these numbers in a board deck, a GRC tool,
 or a SIEM has no supported way to pull them out programmatically.
2. **No export gated to the role a read-only automation identity would hold.** Microsoft's own
 access-control guidance for this application (`README.md` reference 7) states plainly: a **Data
 Reader** with the **Insights Reader** role can view the report but **cannot** select
 **"Export to CSV"**, only a **Data Curator** can export. Building a recurring export around this
 report would require granting the automation identity a materially more privileged role
 (Data Curator: create/modify/delete on every asset in scope) than the read-only task actually
 needs.
3. **A rolling 30-day window, not a point-in-time or long-horizon trend.** The native "Classification
 activity" chart shows the last 30 days and re-renders on its own refresh cadence (weekly by
 default, `README.md` reference 4). It cannot answer "what was our classified-asset percentage
 six months ago" or produce a diffable, source-controlled artifact for an auditor.

## 2. Design goals

1. **Reproduce the report's headline KPIs from primitives Microsoft documents, not from the Insights
 application itself.** The native "Classic assets" report defines its own headline "Unclassified
 assets" KPI precisely: "Assets with no system or custom classification on the entity or its
 columns" (`README.md` reference 3), this scenario's `-Mode Full` unclassified count is designed
 to match that same definition (an asset whose `classification` array is empty), computed from a
 different, scriptable primitive rather than the report itself. The native report's other
 building blocks, asset counts, per-classification counts, are likewise all derivable from the
 **Discovery - Query** REST
 operation on the Data Map/Unified Catalog search index (`README.md` reference 5), which every
 scenario in this repo's Data Governance area already treats as automation surface 4. This
 scenario does not call, scrape, or attempt to automate the Insights application UI at all.
2. **Use a materially narrower role than viewing the native report requires.** Discovery - Query is
 a **Data Reader**-level, read-only Catalog Data-plane operation (`README.md` reference 6), no
 Insights Reader role assignment, and no Data Curator escalation for export, is needed anywhere in
 this scenario. This is a concrete, citable improvement over the native export path's own
 documented privilege requirement (Goal/Problem 2 above).
3. **Compute "classified vs. unclassified," honestly, from confirmed primitives, never from a
 guessed filter.** Microsoft's own community Q&A on this exact question (`README.md` reference 8)
 confirms there is **no documented Discovery - Query filter for "has any classification"/"has no
 classification"**, only a filter for a *specific* classification value
 (`"classification": "<value>"`). Rather than invent an unverified filter expression (e.g. a
 `prefix` match against `"MICROSOFT."`) to approximate it, this scenario computes the split by
 paging through actual `SearchResultValue` records and testing each one's documented
 `classification` array field client-side (empty vs. non-empty), grounded directly in the
 `Discovery - Query` response schema (`README.md` reference 5), not in an unconfirmed request
 shape. See Section 4/`README.md` §11 for the one remaining approximation this still requires at
 very large scale.
4. **A trend log, not just a snapshot, the specific gap the native report's 30-day window leaves.**
 Each run appends (or replaces, for the same `-RunId`) one row per object type to a
 source-controllable CSV, so a buyer gets exactly the longitudinal history the native report
 discards after 30 days.
5. **Idempotent in the sense that matters for a report, not the sense that matters for a policy
 object.** This scenario creates no Purview object, so there is nothing to "already exist" and
 skip creating. Idempotency here means: re-running the script for the same `-RunId` (default: the
 current UTC date) produces the same trend-log outcome, it **replaces** that `RunId`'s row rather
 than appending a duplicate, so a retried or re-scheduled run never corrupts the trend history
 with double-counted rows. See Section 5.
6. **Compose with, don't duplicate, this repo's existing Data Governance narrative.** The scenario's
 worked example scopes to the same `customerdb` collection and re-surfaces the SSN / Credit Card
 Number classifications `scenarios/data-map/scan-azure-sql-and-classify/` already establishes, 
 this report is presented as the natural "what did all that scanning actually produce, in
 board-deck-ready numbers, over time" companion to that scenario, not a replacement for it.

## 3. Why a custom REST report (not the native export, not a third-party BI tool)

- **The native "Export to CSV" path** (`README.md` reference 7) is a legitimate one-off for a human
 who already holds Data Curator and wants a single snapshot, but it cannot be scheduled, cannot be
 scoped to a least-privileged identity, and produces a snapshot with no built-in mechanism to diff
 against last month's export other than a human filing the files away themselves.
- **A third-party BI/reporting tool reading Purview's data some other way** would either duplicate
 Purview's own metadata store or require an additional connector/export Microsoft doesn't document
 for this purpose, and would sit outside the same Data Map / Unified Catalog surface this repo's
 other Data Governance scenarios (Data Map scan-and-classify, Data Quality, Data Lineage, Unified
 Catalog glossary) already standardize on, fragmenting the automation surface for no benefit.
- **The Discovery - Query REST API** is Microsoft's own documented mechanism for retrieving Data
 Map search results and facet aggregations (`README.md` reference 5), the same index the Insights
 application itself is built on top of, and the same automation surface (4) every other scenario
 in this repo's Data Governance area already uses. A script built on it produces numbers that are
 directly reconcilable against what a Data Curator sees in the native report (same underlying
 index), while adding the export/schedule/trend/least-privilege properties the native report
 doesn't offer.

## 4. Object model and REST call sequence

```mermaid
sequenceDiagram
    participant Report as Export-ClassificationCoverageReport.ps1
    participant AAD as Microsoft Entra ID
    participant API as Purview Data Map Discovery REST API

    Report->>AAD: OAuth2 client_credentials (resource=https://purview.azure.net)
    AAD-->>Report: Bearer token
    loop for each configured objectType (Tables, Files, ...)
        Report->>API: POST search/query {filter:{objectType, collectionId?}, keywords:null, limit:1}
        API-->>Report: "@search.count" (authoritative total for this objectType/scope)
        loop while continuationToken present
            Report->>API: POST search/query {filter:{...}, limit:1000, continuationToken}
            API-->>Report: value[] (each with its own classification[] array), next continuationToken
            Report->>Report: tally classified (classification.Count > 0) vs. unclassified per record;<br/>accumulate a per-classification-value histogram
        end
        Report->>Report: reconcile tallied record count against "@search.count" (flags API/network<br/>truncation rather than silently under-reporting)
    end
    Report->>Report: write/replace this RunId's row(s) in the trend-log CSV;<br/>write a per-run classification-breakdown CSV
```

Every call is a **read-only POST** to `search/query`, Discovery - Query is documented as a search
operation, not a mutation, and requires no `ShouldProcess` gate on the Purview side; this scenario's
only side effect is the local (or blob-stored) report file it writes, which **is** wrapped in
`$PSCmdlet.ShouldProcess()` so `-WhatIf` shows exactly what would be written without touching disk.
Full grounding: `deploy/Export-ClassificationCoverageReport.ps1`'s inline comments and `.NOTES`.

## 5. Key decisions

| Decision | Choice | Rationale |
|---|---|---|
| Data source for KPIs | `Discovery - Query` REST operation (paginated, per-record) | Only Microsoft-documented way to retrieve the classification value(s) actually attached to each asset, Goal 1/3 |
| Classified-vs-unclassified computation | Client-side tally of each record's `classification[]` array length, not a request-body filter | No documented "has any classification" filter exists (`README.md` reference 8); inventing one would violate `AGENTS.md` §4's no-invented-request-shape rule, Goal 3 |
| Total-count source | The same query's own `@search.count` field, the `limit:1` facets call in `-Mode Facets`, or the last paged response in `-Mode Full` | Documented as "the total number of search results (not the number of documents in a single page)", authoritative, and free (no extra round-trip) since every mode already makes a query whose response carries it |
| Role required | **Data Reader** only | Discovery - Query is a Catalog Data-plane read operation; deliberately narrower than the native report's own Data Curator export requirement, Goal 2 |
| Pagination | `continuationToken`, page size 1000 (the documented maximum) | Minimizes round-trips at scale; every page's record count is reconciled against `@search.count` to catch a silently-truncated pull rather than trust the loop terminated correctly |
| Idempotency mechanism | Replace-by-`RunId` in the trend-log CSV, not append-only | A report has no "already exists, skip" object to check against; replace-on-rerun is the report-specific equivalent of this repo's usual existence-check idempotency (Goal 5) |
| Output format | CSV trend log (one row per `RunId` × object type) + a per-run JSON/CSV classification-value breakdown | CSV is the natural input to a board deck/spreadsheet or a SIEM's flat-file ingestion; JSON breakdown preserves the full per-classification histogram a single trend row can't hold |
| Facet-only fast path | Offered as `-Mode Facets` (optional, off by default) | The `facets` parameter on the same operation returns top-N per-classification counts in one call without pagination, cheap and matches the native "Top classifications" chart, but (like that chart) double-counts a multi-classified asset under every classification it carries, and cannot compute an unclassified count at all. Documented as a deliberate, named trade-off, not silently substituted for `-Mode Full`'s per-record tally |
| Scope parameters | `-ObjectTypes` (default `Tables`,`Files`), optional `-CollectionId` | Mirrors the native report's own "classified files"/"classified tables" split and its collection-scoped drill-down (`README.md` reference 2) |

## 6. What this scenario assumes already exists

- A Microsoft Purview account with Data Map enabled and at least one completed scan, the worked
 example reuses `customerdb.dbo.Customers` from `scenarios/data-map/scan-azure-sql-and-classify/`.
- An app registration holding the **Data Reader** role on the collection(s) in scope.
- Wherever the trend-log CSV is written persists between runs (a repo path, a mounted file share, or
 blob storage), this scenario does not provision that storage; see `README.md` §6/§9.

## 7. Non-goals

- This scenario does not automate, scrape, or otherwise call the native Data Estate Insights
 application's own UI or any undocumented internal API behind it, only the public Discovery -
 Query REST operation (Section 2/3).
- **Sensitivity-label coverage** (the native report's separate "Labeling insights") is out of scope
 here, a natural sibling fragment, tracked in `PROGRESS.md`, since the same per-record pagination
 pattern applies to the `label` field on `SearchResultValue`.
- **Glossary/curation-rate coverage** (the native report's "Glossary insights"/"Data stewardship"
 dashboards) is likewise out of scope, different underlying data (term-to-asset attachment rates,
 active-user counts) this scenario's Discovery - Query-based approach doesn't reach.
- This scenario does not push the report anywhere (no built-in Log Analytics/Sentinel/Power BI
 sink), it writes local/blob CSV and JSON files and leaves routing them into a SIEM or BI tool as
 an integration the buyer's own pipeline performs, consistent with `README.md` §8.
- At extreme estate scale (an object type with several hundred thousand+ assets), `-Mode Full`'s
 full page-through has a real, non-trivial API-call and runtime cost; this scenario does not
 implement incremental/delta tallying (e.g. only re-tallying assets modified since the last run), 
 see `README.md` §11.
