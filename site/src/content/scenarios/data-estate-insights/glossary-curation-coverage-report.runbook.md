---
part: "runbook"
parent: "data-estate-insights/glossary-curation-coverage-report"
---
## Implementation steps

### Portal path (view the classic report first, to understand the gap this scenario closes)

1. Open the Microsoft Purview portal → **Unified Catalog** → **Health management** → **Reports**
   (or, on the classic portal, **Data Estate Insights**) → select the **Classic glossary** report. Note this report's status vocabulary (Draft/Approved/Alert/Expired) is
   from the classic glossary model, not the Unified Catalog Terms model this scenario reports on
   (the known limitations, the design notes point 4).
2. Confirm the target domain(s) already have glossary terms authored (e.g.
   *Curate a Business Glossary*'s `Customer Experience` domain).
3. On each domain's **Roles** tab, assign the automation identity's service principal the
   **Data Steward** role (for full status coverage) or **Local Catalog Reader** (for
   `-PublishedOnly` mode).

### Script path (idempotent by RunId, parameterized, dry-run capable)

```powershell
# 1. Dry run - queries live data and prints the computed KPIs, writes nothing to disk
./deploy/Export-GlossaryCurationCoverageReport.ps1 `
    -PurviewAccountEndpoint 'https://api.purview-service.microsoft.com' `
    -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
    -DomainIds $CustomerExperienceDomainId `
    -TrendLogPath './deploy/out/glossary-curation-trend.csv' `
    -BreakdownOutputDirectory './deploy/out/breakdowns' -WhatIf

# 2. Run for real - full status coverage, requires Data Steward on each domain
./deploy/Export-GlossaryCurationCoverageReport.ps1 `
    -PurviewAccountEndpoint 'https://api.purview-service.microsoft.com' `
    -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
    -DomainIds $CustomerExperienceDomainId `
    -TrendLogPath './deploy/out/glossary-curation-trend.csv' `
    -BreakdownOutputDirectory './deploy/out/breakdowns'

# 3. Lower-privilege alternative - Global/Local Catalog Reader only, published terms only
./deploy/Export-GlossaryCurationCoverageReport.ps1 `
    -PurviewAccountEndpoint 'https://api.purview-service.microsoft.com' `
    -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
    -DomainIds $CustomerExperienceDomainId -PublishedOnly `
    -TrendLogPath './deploy/out/glossary-curation-trend.csv' `
    -BreakdownOutputDirectory './deploy/out/breakdowns'

# 4. Validate
./validate/Test-GlossaryCurationCoverageReport.ps1 `
    -TrendLogPath './deploy/out/glossary-curation-trend.csv' `
    -PurviewAccountEndpoint 'https://api.purview-service.microsoft.com' `
    -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret -DomainIds $CustomerExperienceDomainId
```

Both scripts use the **Microsoft Purview Unified Catalog REST API** (`Invoke-RestMethod`) -
automation surface 4 per [Automation surface, section 1](/docs/automation-surface/#1-five-automation-surfaces-not-one-read-this-first), API version `2026-03-20-preview` - the
same surface and version *Curate a Business Glossary* already establishes. There is no PowerShell
cmdlet module for Unified Catalog term reads today.

**Scheduling:** this scenario ships no scheduler-specific code - wire
`deploy/Export-GlossaryCurationCoverageReport.ps1` into whatever recurring-execution mechanism the
organization already runs other PowerShell automation on, pointing `-TrendLogPath`/
`-BreakdownOutputDirectory` at persistent storage. Daily (the default `-RunId` grain) is the right
cadence for a board/GRC reporting use case.

## Configuration reference

| Setting | Value this scenario uses | Notes |
|---|---|---|
| Scope parameter | `-DomainIds` (one or more governance-domain GUIDs, required) | Unified Catalog domains are this API's native scoping unit - mirrors *Curate a Business Glossary*'s own domain-scoped model |
| Status values reported | `DRAFT`, `PUBLISHED`, `EXPIRED` | Confirmed `CatalogModelStatus` enum on the `Term` object - the classic report's fourth value, `Alert`, has no analog here |
| "Approved" mapping | `PUBLISHED` status | Closest documented correspondence to the classic report's "Approved" term - not a Microsoft-stated equivalence |
| Completeness checks | Empty/whitespace `description` ("missing definition"); empty `contacts.owner` ("missing steward" analog); empty `contacts.expert` ("missing expert"); 2+ of these = "missing multiple" | Client-side test of documented `Term`/`ContactsMap` fields - no unconfirmed facet/filter used |
| Asset-attachment check | Per-term `GET terms/{id}/relationships?entityType=DATAASSET` - non-empty `value[]` = "has assets" | Only documented relationship-read primitive for this question; an N+1 cost, opt out via `-SkipAssetLinkCheck` |
| Pagination | `skip`/`top` query parameters, `nextLink`-style paging | `PagedTerm` response shape - a different primitive from Discovery - Query's `continuationToken` (used by this scenario's *Exportable, Historical Classification Coverage Report* sibling); `-PageSize` defaults to 100 since Microsoft documents no maximum `top` value - see the known limitations |
| Report role | **Data Steward** (default) or **Global/Local Catalog Reader** (`-PublishedOnly`) | section 3 - the one place this scenario is *more* privileged than its *Exportable, Historical Classification Coverage Report* sibling, disclosed rather than glossed over |
| API version pinned by both scripts | `2026-03-20-preview` | Same version *Curate a Business Glossary* and [Automation surface, section 4](/docs/automation-surface/#4-routing-table---which-surface-for-which-purview-task) already pin - confirmed current via direct fetch of the Terms operation-group reference |
| `-PurviewAccountEndpoint` accepted values | `https://api.purview-service.microsoft.com` (new portal) or `https://<account>.purview.azure.com` (classic portal) | Same dual-endpoint precedent as *Curate a Business Glossary* and *Exportable, Historical Classification Coverage Report* |
| Idempotency key | `-RunId` (default: current UTC date, `yyyy-MM-dd`) | Re-running for the same `RunId` **replaces** that RunId's trend-log row(s) - see the design notes |

Full REST-body grounding: `deploy/Export-GlossaryCurationCoverageReport.ps1` and
`validate/Test-GlossaryCurationCoverageReport.ps1` inline comments and their `.NOTES` blocks cite the
exact Microsoft Learn reference pages.

## Operations and tuning

**KPIs to watch (first 30 days):**
- **Percent of `PUBLISHED` terms with at least one linked asset, trended over time, per domain.** A
  flat or declining trend after new terms are published is the same "curated but unused" signal the
  classic report's "Approved terms without assets" KPI exists to surface.
- **Percent of terms with zero incompleteness flags, trended over time.** A term missing an owner is
  a term nobody is accountable for - this library's *Curate a Business Glossary* (operations and tuning) already
  recommends folding glossary-owner review into offboarding/access-review; this KPI is the
  measurable version of that recommendation.
- **`DRAFT` terms aging past a organization-defined threshold** (this report doesn't compute an age itself
  - `systemData.createdAt` is available in the per-run breakdown JSON for a consuming report/BI tool
  to compute it) - a `DRAFT` term sitting unreviewed for months signals a stalled curation workflow.

**Alert routing:** this scenario produces flat files (CSV/JSON), not a Purview-native alert - there
is nothing to wire into a native Purview alert channel. Route
`validate/Test-GlossaryCurationCoverageReport.ps1`'s non-zero exit code into whatever CI/ops
alerting the deploying organization already uses for scheduled scripts, the same pattern
*Exportable, Historical Classification Coverage Report* (operations and tuning) recommends for its own validate script. This scenario
deliberately does not build a bespoke Sentinel/Log Analytics sink - ingest the trend-log CSV or
per-run breakdown JSON directly.

**Incident-response runbook (a `[WARN]`/`[FAIL]` appears):**
1. **Triage** - a **file-integrity `[FAIL]`** (arithmetic or duplicate-row check) points at the
   trend log itself, not live data: check for manual edits to the CSV, or a version of this script
   older than the one that introduced replace-by-RunId behavior. Always a hard failure worth
   blocking on.
2. **A live-reconciliation `[WARN]`** most often means the report is stale relative to newly created
   or expired terms since the last run - re-run `deploy/Export-GlossaryCurationCoverageReport.ps1`
   and re-validate before assuming anything is actually wrong. A soft signal, not a block.
3. **A `Write-Warning` for a role-permission mismatch** (e.g. the automation identity can't see
   `DRAFT` terms because it only holds Catalog Reader, not Data Steward, despite `-PublishedOnly`
   not being set) surfaces on PowerShell's warning stream - a scheduled/unattended pipeline must
   capture it explicitly (`-WarningVariable`, or redirecting stream 3) to not silently under-report
   Draft-term counts as zero when the real cause is a permission gap, not an empty glossary.

**Review cadence:** re-run on whatever cadence the consuming report needs - daily is the default
grain this scenario's `-RunId` assumes; review the trend for stalled Draft terms or declining
asset-attachment rates at least monthly regardless of automation cadence.

## Rollback and decommission

See the rollback runbook for the full procedure. Quick reference: this scenario creates **no Purview
object** - there is nothing in the Purview account itself to roll back. Decommissioning means
stopping the scheduled execution of `deploy/Export-GlossaryCurationCoverageReport.ps1`, removing the
Data Steward/Catalog Reader role assignment for the reporting service principal, and deciding what
to do with the already-produced trend-log/breakdown files.

## References

1. Understand the classic glossary report in Unified Catalog (KPIs, status snapshot, incomplete-term
   breakdown) - <https://learn.microsoft.com/purview/unified-catalog-reports-classic-glossary>
2. Understand the Microsoft Purview Data Estate Insights application (Health/Data stewardship and
   Catalog adoption dashboards - active-user and search-activity telemetry) - <https://learn.microsoft.com/purview/legacy/concept-insights>
3. Disable Data Estate Insights or report refresh (weekly default refresh cadence; no separate
   billing) - <https://learn.microsoft.com/purview/legacy/disable-data-estate-insights>
4. Purview Unified Catalog REST API - Terms - List / Terms - Get (Term object schema:
   `status` enum `DRAFT`/`PUBLISHED`/`EXPIRED`, `ContactsMap` `owner`/`expert`/`databaseAdmin`,
   `PagedTerm` `nextLink` pagination) - <https://learn.microsoft.com/rest/api/purview/purview-unified-catalog/terms/list?view=rest-purview-purview-unified-catalog-2026-03-20-preview>
5. Unified Catalog API (Public Preview) overview (GA-only coverage, preview API version status) - <https://learn.microsoft.com/rest/api/purview/unified-catalog-api-overview>
6. Create and manage glossary terms (DRAFT visibility limited to Data Stewards/Governance Domain
   Owners) - <https://learn.microsoft.com/purview/unified-catalog-glossary-terms-create-manage>
7. Purview Unified Catalog REST API - Terms - List Related Entities / Terms - Get Facets (asset-relationship read primitive; facet name enumeration gap) - <https://learn.microsoft.com/rest/api/purview/purview-unified-catalog/terms/list-related-entities?view=rest-purview-purview-unified-catalog-2026-03-20-preview>
8. Data governance roles and permissions in Microsoft Purview (Global Catalog Reader/Local Catalog
   Reader read only published artifacts; Data Steward reads/writes within its own domain) - <https://learn.microsoft.com/purview/data-governance-roles-permissions>
9. Search for data assets (governed-asset search, the **Governance** tab showing linked glossary
   terms per asset - the portal-side cross-check for this scenario's asset-attachment tally) - <https://learn.microsoft.com/purview/unified-catalog-data-assets-search>
10. Learn about data governance billing (governed assets, what counts, what doesn't) - <https://learn.microsoft.com/purview/data-governance-billing>
11. Tutorial: Authenticate for APIs (service principal setup, Unified Catalog role assignment,
    client-credentials token flow) - <https://learn.microsoft.com/purview/data-gov-api-rest-data-plane>

> Re-verify all links against current Microsoft Learn before a customer-facing engagement - this
> scenario targets Unified Catalog's **preview** REST API surface (`2026-03-20-preview`), which
> Microsoft explicitly documents as covering only GA Unified Catalog features and subject to change
> before general availability.