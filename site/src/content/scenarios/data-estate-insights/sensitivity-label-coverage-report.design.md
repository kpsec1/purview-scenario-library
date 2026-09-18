---
part: "design"
parent: "data-estate-insights/sensitivity-label-coverage-report"
---
## 1. Problem statement

Microsoft Purview's **Data Estate Insights** application ships a **Classic sensitivity labels**
report (accessed today from **Unified Catalog → Health management → Reports** in the current portal,
or **Data Estate Insights** in the classic portal, `README.md` reference 1) with exactly the KPIs a
security-focused governance stakeholder wants: number of subscriptions found in the data, number of
unique sensitivity labels applied, number of sources with labels applied, number of files/tables
labeled, top labels applied across sources/files/tables, and a 30-day labeling-activity trend
[[1]](#references). It is automatically generated, requires no scripting, and is the right first stop
for anyone exploring their estate's labeling posture interactively.

It has the same three structural limits this repo's sibling
`scenarios/data-estate-insights/classification-coverage-report/` scenario already documents for the
**Classic classifications** report, because both reports are two faces of the same Data Estate
Insights "Curation and governance" application, built on the same underlying Data Map search index
[[9]](#references):

1. **No REST API of its own.** No documented endpoint returns the report's computed KPIs (unique-
   label count, top-labels list, etc.) for a script to consume.
2. **No export gated to the role a read-only automation identity would hold.** Microsoft's own
   access-control guidance for Data Estate Insights (`README.md` reference 4), written generically
   for the whole application, not specific to any one report, states plainly: a **Data Reader** with
   the **Insights Reader** role can view any Data Estate Insights report but **cannot** select
   **"Export to CSV"**; only a **Data Curator** can export.
3. **A rolling 30-day window, not a point-in-time or long-horizon trend.** The native "Labeling
   activity" chart shows the last 30 days on its own refresh cadence. It cannot answer "what was our
   labeled-asset percentage six months ago" or produce a diffable, source-controlled artifact for an
   auditor.

A fourth, label-specific consideration this scenario's own design must account for: **sensitivity
labels reaching the Data Map at all depends on a separate, Microsoft-labeled *preview* capability**
, "Extend sensitivity labels to assets in Microsoft Purview Data Map" [[6]](#references)[[7]](#references), 
that is off by default and requires its own licensing (Section 3/`README.md` §3). This report can
only ever be as complete as that upstream extension is turned on and populated; it does not, and
cannot, apply labels itself (Section 7).

A fifth consideration, distinct from the sibling scenario's own framing and important enough to state
in the design itself rather than only in `README.md` §11: **a label surfaced through this extension
is metadata only.** Microsoft's own FAQ for this capability states plainly that these labels "don't
modify your files and databases in any way," that Data Map does not currently support encryption or
content marking for the assets it labels, and that Data Map provides no DLP enforcement at all
[[7]](#references). This scenario's `PercentLabeled` metric is therefore a *labeling-coverage* signal
("is sensitivity known and recorded"), never a *protection-coverage* signal ("is access actually
restricted"), the two are easy to conflate in a report consumer's mind precisely because "labeled" and
"protected" are synonyms in ordinary English, so this scenario's own documentation says so explicitly
rather than letting a reader infer a stronger guarantee than the data supports.

## 2. Design goals

1. **Reproduce the report's headline KPIs from primitives Microsoft documents, not from the Insights
   application itself.** The Discovery - Query REST operation's response schema documents a `label`
   field on every `SearchResultValue` record, `string[]`, "The labels of the asset"
   [[2]](#references), the direct structural analog of the `classification` field the sibling
   scenario already uses, on the same operation, same schema, same automation surface (4). This
   scenario does not call, scrape, or attempt to automate the Insights application UI at all.
2. **Use a materially narrower role than viewing the native report requires.** Identical to the
   sibling scenario: Discovery - Query is a **Data Reader**-level, read-only Catalog Data-plane
   operation [[3]](#references)[[8]](#references), no Insights Reader role assignment, and no Data
   Curator escalation for export, is needed anywhere in this scenario.
3. **Compute "labeled vs. unlabeled," honestly, from confirmed primitives, never from a guessed
   filter.** A direct fetch of the Discovery - Query REST reference page for this build confirms the
   operation's *only* documented worked exact-value filter example (`Discovery_Query_Classification`)
   is for the `classification` field (`"classification": "MICROSOFT.PERSONAL.EMAIL",
   "includeSubClassifications": true`), no equivalent `Discovery_Query_Label` worked example, or any
   other documented `"label": "<value>"` request-filter shape, exists on that same page
   [[2]](#references). Rather than invent one, this scenario applies the identical client-side-tally
   design the sibling scenario already uses for `classification` (Goal 3 there) to the `label` field
   instead: page through actual `SearchResultValue` records and test each one's documented `label`
   array field (empty vs. non-empty).
4. **A trend log, not just a snapshot, the specific gap the native report's 30-day window leaves.**
   Identical mechanism to the sibling scenario (Section 5, below).
5. **Idempotent in the sense that matters for a report, not the sense that matters for a policy
   object.** Identical replace-by-`RunId` design to the sibling scenario, see Section 5.
6. **Compose with, don't duplicate, this repo's existing Data Governance narrative and its own
   classification-coverage sibling.** This scenario's worked example scopes to the same `customerdb`
   collection this repo's other Data Governance scenarios already use, and its deploy/validate scripts
   are structured identically to `classification-coverage-report`'s, a reviewer or operator who
   already understands one understands the other, field-name substitution aside. It is presented as a
   sibling report, not a superset or a replacement: a buyer who wants both classification and
   sensitivity-label coverage runs both scripts against the same estate.

## 3. Why a custom REST report (not the native export, not a third-party BI tool)

Identical reasoning to `classification-coverage-report/design.md` §3, reproduced here rather than
cross-referenced only, per this repo's per-scenario self-containment convention:

- **The native "Export to CSV" path** is a legitimate one-off for a human who already holds Data
  Curator and wants a single snapshot, but it cannot be scheduled, cannot be scoped to a
  least-privileged identity, and produces a snapshot with no built-in mechanism to diff against last
  month's export.
- **A third-party BI/reporting tool** would either duplicate Purview's own metadata store or require
  an additional connector Microsoft doesn't document for this purpose, fragmenting the automation
  surface this repo's other Data Governance scenarios already standardize on (surface 4).
- **The Discovery - Query REST API** is Microsoft's own documented mechanism for retrieving Data Map
  search results and facet aggregations [[2]](#references), the same index the Insights application
  itself is built on top of. A script built on it produces numbers directly reconcilable against what
  a Data Curator sees in the native report, while adding the export/schedule/trend/least-privilege
  properties the native report doesn't offer.

## 4. Object model and REST call sequence

```mermaid
sequenceDiagram
    participant Report as Export-SensitivityLabelCoverageReport.ps1
    participant AAD as Microsoft Entra ID
    participant API as Purview Data Map Discovery REST API

    Report->>AAD: OAuth2 client_credentials (resource=https://purview.azure.net)
    AAD-->>Report: Bearer token
    loop for each configured objectType (Tables, Files, ...)
        Report->>API: POST search/query {filter:{objectType, collectionId?}, keywords:null, limit:1}
        API-->>Report: "@search.count" (authoritative total for this objectType/scope)
        loop while continuationToken present
            Report->>API: POST search/query {filter:{...}, limit:1000, continuationToken}
            API-->>Report: value[] (each with its own label[] array), next continuationToken
            Report->>Report: tally labeled (label.Count > 0) vs. unlabeled per record;<br/>accumulate a per-label-value histogram
        end
        Report->>Report: reconcile tallied record count against "@search.count" (flags API/network<br/>truncation rather than silently under-reporting)
    end
    Report->>Report: write/replace this RunId's row(s) in the trend-log CSV;<br/>write a per-run label-breakdown CSV
```

Every call is a **read-only POST** to `search/query`, identical to the sibling scenario's own
sequence with `label` substituted for `classification` throughout. This scenario's only side effect
is the local (or blob-stored) report file it writes, wrapped in `$PSCmdlet.ShouldProcess()` so
`-WhatIf` shows exactly what would be written without touching disk. Full grounding:
`deploy/Export-SensitivityLabelCoverageReport.ps1`'s inline comments and `.NOTES`.

## 5. Key decisions

| Decision | Choice | Rationale |
|---|---|---|
| Data source for KPIs | `Discovery - Query` REST operation (paginated, per-record), `label` field | Only Microsoft-documented way to retrieve the label value(s) actually attached to each asset, Goal 1/3 |
| Labeled-vs-unlabeled computation | Client-side tally of each record's `label[]` array length, not a request-body filter | No documented "has any label" filter exists (Section 2 Goal 3); inventing one would violate `AGENTS.md` §4's no-invented-request-shape rule |
| Total-count source | The same query's own `@search.count` field | Identical to the sibling scenario, authoritative and free (no extra round-trip) |
| Role required | **Data Reader** only | Discovery - Query is a Catalog Data-plane read operation; deliberately narrower than the native report's own Data Curator export requirement, Goal 2 |
| Pagination | `continuationToken`, page size 1000 (the documented maximum) | Identical to the sibling scenario; every page's record count is reconciled against `@search.count` |
| Idempotency mechanism | Replace-by-`RunId` in the trend-log CSV, not append-only | Identical to the sibling scenario, Goal 5 |
| Output format | CSV trend log (one row per `RunId` × object type) + a per-run JSON label-value breakdown | CSV is the natural input to a board deck/spreadsheet or a SIEM's flat-file ingestion; JSON breakdown preserves the full per-label histogram a single trend row can't hold |
| Facet-only fast path | Offered as `-Mode Facets` (optional, off by default), using the confirmed `label` facet (one of exactly four documented Discovery - Query facets: `assetType`, `classification`, `contactId`, `label` [[2]](#references)) | Matches the native "Top labels applied across sources/files/tables" charts, but (like those charts) double-counts a multi-labeled asset under every label it carries, and cannot compute an unlabeled count |
| Scope parameters | `-ObjectTypes` (default `Tables`,`Files`), optional `-CollectionId` | Mirrors both the native report's files/tables-labeled split and the sibling scenario's own defaults |
| Script/file naming | `Export-SensitivityLabelCoverageReport.ps1` / `Test-SensitivityLabelCoverageReport.ps1`, distinct trend-log/breakdown file names (`sensitivity-label-coverage-trend.csv`, `<RunId>-<ObjectType>-labels.json`) | Runs alongside, never collides with, the sibling scenario's own output files when both are wired into the same scheduler/storage location |

## 6. What this scenario assumes already exists

- A Microsoft Purview account with Data Map enabled and at least one completed scan.
- **"Extend sensitivity labels to Data Map" turned on**, with at least one sensitivity label already
  applied to an asset in scope, either by autolabeling (a label scoped to "Files & other data
  assets" with autolabeling rules configured) or manual labeling
  [[6]](#references)[[7]](#references). Unlike the sibling `classification-coverage-report` scenario
  (whose classifications come "for free" from any completed scan), a labeled asset requires this
  additional, separately-licensed, preview capability to already be configured, this scenario reads
  labels, it does not apply them (Section 7).
- An app registration holding the **Data Reader** role on the collection(s) in scope.
- Wherever the trend-log CSV is written persists between runs (a repo path, a mounted file share, or
  blob storage), this scenario does not provision that storage.

## 7. Non-goals

- This scenario does not automate, scrape, or otherwise call the native Data Estate Insights
  application's own UI or any undocumented internal API behind it, only the public Discovery - Query
  REST operation (Section 2/3).
- **This scenario does not apply, create, or manage sensitivity labels, autolabeling policies, or the
  "extend sensitivity labels to Data Map" capability itself.** It reads whatever labels already exist
  on already-scanned assets. Authoring/publishing sensitivity labels and their autolabeling rules is a
  distinct concern this repo's Information Protection module scenarios
  (`scenarios/information-protection/auto-label-confidential-sharepoint/`) already cover for the
  Microsoft 365 workload side; extending an existing label's scope to "Files & other data assets" so
  it becomes visible to Data Map, and turning on the Data Map extension capability itself, remain
  manual portal prerequisites for this scenario (`README.md` §5), a natural follow-up fragment,
  tracked in `PROGRESS.md`.
- **Classification coverage** is out of scope here, already covered by the sibling
  `scenarios/data-estate-insights/classification-coverage-report/` scenario this fragment is
  deliberately structured to sit alongside, not replace.
- **Glossary/curation-rate coverage** (the native report's "Glossary insights"/"Data stewardship"
  dashboards) is likewise out of scope, different underlying data this scenario's Discovery -
  Query-based approach doesn't reach; already tracked as a separate follow-up in `PROGRESS.md`.
- This scenario does not push the report anywhere (no built-in Log Analytics/Sentinel/Power BI sink)
, it writes local/blob CSV and JSON files, identical to the sibling scenario's own scope.
- At extreme estate scale, `-Mode Full`'s full page-through has a real, non-trivial API-call and
  runtime cost; this scenario does not implement incremental/delta tallying, see `README.md` §11.
- This scenario does not check whether a scoped `-CollectionId`/`-ObjectTypes` combination actually
  corresponds to a source type Microsoft's Data Map sensitivity-label extension supports (a specific,
  named list, `README.md` §11) before reporting a labeled/unlabeled split for it. A `0%` result for
  an unsupported source type is indistinguishable, in this scenario's current output, from a `0%`
  result for a supported-but-never-labeled one, flagged as a Red Team/Blue Team finding in
  `reviews.md` and tracked as a follow-up in `PROGRESS.md` rather than resolved by guessing at a
  supported-source-list check this build did not independently verify as complete/current enough to
  hard-code as a validation rule.
- **No official Microsoft-named "Unlabeled assets" KPI exists to reproduce**, unlike the sibling
  scenario's `classification-coverage-report`, which reproduces the native Classic assets report's
  own explicitly-defined "Unclassified assets" KPI verbatim ("Assets with no system or custom
  classification on the entity or its columns" [[5]](#references)). This scenario's own "unlabeled"
  metric is this repo's own *designed analog*, assets whose `label` array is empty, not a
  reproduction of a Microsoft-defined term. See `README.md` §11 for this distinction stated plainly to
  a report consumer.
