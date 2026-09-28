---
part: "runbook"
parent: "unified-catalog/manage-okrs"
---
## Implementation steps

### Portal path (for a first manual walkthrough / to validate intent before scripting)

1. Sign in to the [Microsoft Purview portal](https://purview.microsoft.com) → **Unified Catalog**
   → **Catalog management** → **Governance domains** → select `Customer Experience` → **Details**
   tab → **OKRs** card → **View all** → **New OKR**.
2. **Basic details**: Objective `Increase trust in customer master data by reducing duplicate and
   inconsistent customer records across source systems`, owner your Data Steward account, target
   date `2026-12-31`. **Next** → (no required custom attributes in this scenario) → **Create**.
3. On the new objective's details page, select **Add key result** twice to create the two key
   results in the sample definition file, then select **+ Link data product** and choose
   `Customer Master Data`.
4. Select **Publish** (only after confirming the governance domain itself shows as published).

### Script path (idempotent, parameterized, dry-run capable)

Before step 1, generate real GUIDs for `objective.id` and each `keyResults[].id` in the definition
file - this scenario's identity model is **not** name-based, unlike this library's
other Unified Catalog scenarios:

```powershell
[guid]::NewGuid()   # run this three times (once per id) and paste the results into the JSON file
```

```powershell
# 1. Dry run - reports every change, makes none (still performs read-only lookups against the
#    live tenant to accurately report create-vs-update - see Section 11)
./deploy/New-Okr.ps1 `
    -PurviewAccountEndpoint 'https://api.purview-service.microsoft.com' `
    -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
    -DefinitionPath './deploy/config/customer-data-trust-okr.sample.json' -WhatIf

# 2. Deploy in Draft status (default) for review
./deploy/New-Okr.ps1 `
    -PurviewAccountEndpoint 'https://api.purview-service.microsoft.com' `
    -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
    -DefinitionPath './deploy/config/customer-data-trust-okr.sample.json'

# 3. Publish once reviewed
./deploy/New-Okr.ps1 `
    -PurviewAccountEndpoint 'https://api.purview-service.microsoft.com' `
    -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
    -DefinitionPath './deploy/config/customer-data-trust-okr.sample.json' -Publish

# 4. Validate
./validate/Test-Okr.ps1 `
    -PurviewAccountEndpoint 'https://api.purview-service.microsoft.com' `
    -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
    -DefinitionPath './deploy/config/customer-data-trust-okr.sample.json'

# 5. Optional, on a recurring schedule (Windows Task Scheduler / cron / Azure Automation runbook -
#    see Section 8): trend progress over time and flag a key result that has stopped changing.
./deploy/Export-OkrProgressTrend.ps1 `
    -PurviewAccountEndpoint 'https://api.purview-service.microsoft.com' `
    -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
    -DefinitionPath './deploy/config/customer-data-trust-okr.sample.json' `
    -TrendLogPath './deploy/out/okr-progress-trend.csv'
./validate/Test-OkrProgressTrend.ps1 -TrendLogPath './deploy/out/okr-progress-trend.csv' -FailOnStale
```

## Configuration reference

| Object | Field | Source | Notes |
|---|---|---|---|
| Objective | `id` | **Caller-generated GUID, pinned in the definition file before the first run** | Unlike every other object type in this library, identity is never re-derived from a name lookup - the design notes |
| Objective | `status` | `Draft` → `Published` → `Closed` | Note the **TitleCase** spelling - data products and critical data elements in this library's other scenarios use `DRAFT`/`PUBLISHED` (all caps); OKRs use a differently-cased enum for the same concept. A genuine Microsoft-side inconsistency, not a typo in this scenario's scripts |
| Objective | `contacts.owner[].id` | Entra object ID | Resolved from the definition file's UPN, same pattern as this library's other Unified Catalog scenarios |
| Key result | `id` | **Caller-generated GUID**, same model as the objective | Checked via `GET .../keyResults/{id}` before create-vs-update |
| Key result | `domainId` | The parent objective's own domain id | Required by the API on a sub-resource of that same objective - a documented redundancy, not independently configurable via the portal |
| Key result | `status` | `NotTracked` \| `OnTrack` \| `Behind` \| `AtRisk` | **Different enum, same field name, from the objective's own `status`** - a second, easy-to-confuse case of this API using the word "status" for two unrelated enums on parent and child objects |
| Key result | `progress` / `goal` / `max` | Plain numbers (percentage or absolute, operator's choice) | Direction-agnostic: nothing in the API or portal docs states whether a metric should increase toward `goal` or decrease toward it (the sample file's first key result decreases - a duplicate rate going from 8% down to a 2% goal) - see the known limitations |
| Data-product relationship | `entityType` | `OBJECTIVE` (this scenario's link) | Confirmed value in the `EntityCategory` enum shared by the **Data Products** operation group's relationship operations - the design notes. `KEYRESULT` is also a documented value but has no discoverable portal caller; not scripted here |
| Data-product relationship | direction | Created via `POST dataProducts/{id}/relationships`, **not** any Okr-side call | The Okr operation group has no relationship operation of its own - the design notes |

Full request/response shapes: `deploy/New-Okr.ps1`'s inline comments and `.NOTES` block cite the
exact Microsoft Learn REST reference pages for every operation used.

## Operations and tuning

**Review-before-publish workflow:** identical discipline to *Manage a Data Product* (operations and tuning) -
this script's default (`Draft`, no `-Publish`) gives a human review point. Confirm the governance
domain itself is published before attempting `-Publish`.

**Re-running after an edit:** update a key result's `progress` as the underlying metric moves,
then re-run `New-Okr.ps1` - the objective and every key result are always reconciled to the
definition file's current content (full-body `PUT`), the same "declarative file is the source of
truth" discipline this library's other Unified Catalog scenarios use. Because identity is id-based, editing the `definition` text of an existing objective or key result is a safe,
in-place rename - it does **not** risk creating a duplicate the way editing a name-identified
object's name would in this library's other scenarios.

**Run validate after every deploy, not just on demand:** same operational discipline
*Manage a Critical Data Element* (operations and tuning) established - a data-product link that silently
fails to resolve (a mistyped product name) is a non-fatal `Write-Warning`-and-skip in the deploy
script by design, so a deploy run's own console output is not proof every configured link
actually landed.

**Progress tracking is manual, not computed from a live metric source.** Nothing in this
scenario, or in Microsoft's own OKR feature, wires a key result's `progress` value to a live query
against the underlying data (e.g. an actual duplicate-rate calculation from
*Data Quality*). An operator (or a separate, scheduled script reading from wherever the
real metric lives) must update `progress` in the definition file and re-run `New-Okr.ps1` for the
key result to reflect reality - treat a stale, un-refreshed OKR as worse than no OKR for the
board-legible-narrative goal in why this matters, since a stale "on track" reads as false assurance.

**Detecting that staleness, unattended:** run `deploy/Export-OkrProgressTrend.ps1` on the same
cadence as your business review (weekly/monthly) - it re-fetches the objective and every key
result, appends a row per entity to a local trend-log CSV, and flags any entity whose
definition/progress/goal/max/status has stayed **completely unchanged** for `-StalenessThresholdDays`
(default 30) or more. It does not compute or validate progress against any real metric (no such
source exists to check against - see the paragraph above); it only detects the absence of any
recorded change, which is the best unattended proxy available today for "has anyone actually looked
at this key result lately." Pair it with `validate/Test-OkrProgressTrend.ps1 -FailOnStale` as the
pipeline gate, and `validate/Test-Okr.ps1` for existence/definition drift on the same schedule -
the two validate scripts check different things and neither replaces the other.

**Compliance-evidence caution:** this feature is Microsoft-labeled preview - do not cite
an OKR's own progress tracking as a compliance control in a formal audit response; it is a
business-narrative tool, not a system of record for a regulatory requirement (contrast
*Manage a Critical Data Element* (operations and tuning)'s similar caution, which is about audit *evidence*
rather than business narrative).

## Rollback and decommission

See the rollback runbook for the full staged procedure (unpublish → unlink → delete). Quick reference:
`./deploy/Remove-Okr.ps1` unpublishes the objective (reversible); add `-RemoveLinks` to also
remove its data-product links; add `-Purge` to permanently delete every key result and then the
objective itself.

## References

1. Objectives and key results (OKRs) in Unified Catalog - concept, business-value framing -
   <https://learn.microsoft.com/purview/unified-catalog-okrs>
2. Create and manage OKRs in Unified Catalog - portal flow, steward-role prerequisite, duplicate-name behavior, publish gating on the governance domain, key results, data-product linking -
   <https://learn.microsoft.com/purview/unified-catalog-okrs-create-manage>
3. Get started with Microsoft Purview data governance - worked "Customer Response" OKR /
   email-campaign-results data product example -
   <https://learn.microsoft.com/purview/data-governance-get-started>
4. Data governance roles and permissions in Microsoft Purview - steward role, governance-domain-level permissions - <https://learn.microsoft.com/purview/data-governance-roles-permissions>
5. Learn about Microsoft Purview Unified Catalog - OKRs feature overview -
   <https://learn.microsoft.com/purview/unified-catalog>
6. Create and manage OKRs in Unified Catalog - "Ensure your governance domain is published before
   you publish your OKRs" - <https://learn.microsoft.com/purview/unified-catalog-okrs-create-manage>
7. Learn about data governance billing - governed-asset definition and enumeration (data
   products, critical data elements, glossary terms, data quality) -
   <https://learn.microsoft.com/purview/data-governance-billing>
8. Purview Unified Catalog REST API - Okr operation group (Count/Create/Create Key Result/Delete/
   Delete Key Result/Get/Get Facets/Get Key Result/List/List Key Results/Query/Update/Update Key
   Result) -
   <https://learn.microsoft.com/rest/api/purview/purview-unified-catalog/okr?view=rest-purview-purview-unified-catalog-2026-03-20-preview>
9. Purview Unified Catalog REST API - Data Products operation group, Create/List/Delete
   Relationship operations and their shared `EntityCategory` enum (confirms `OBJECTIVE` and
   `KEYRESULT` as valid values) -
   <https://learn.microsoft.com/rest/api/purview/purview-unified-catalog/data-products/create-relationship?view=rest-purview-purview-unified-catalog-2026-03-20-preview>
10. Purview Unified Catalog REST API - operation groups index (confirms the Okr operation group has
    no relationship operation, unlike Data Products/Critical Data Elements/Terms) -
    <https://learn.microsoft.com/rest/api/purview/purview-unified-catalog/operation-groups>
11. Unified Catalog API (Public Preview) overview - release notes confirming OKRs shipped in the
    first public preview API version (`2025-09-15-preview`) -
    <https://learn.microsoft.com/rest/api/purview/unified-catalog-api-overview>
12. Data governance billing frequently asked questions -
    <https://learn.microsoft.com/purview/data-governance-billing-faq>
13. Get a user (Microsoft Graph) - `User.Read.All` application permission -
    <https://learn.microsoft.com/graph/api/user-get>
14. Audit log activities - "Microsoft Purview governance activities" category, checked for an
    Objective/KeyResult/OKR-specific operation (none found; supports but does not conclusively prove
    the no-notification-surface finding the known limitations discloses for the progress-trend companion) -
    <https://learn.microsoft.com/purview/audit-log-activities#microsoft-purview-governance-activities>

> Re-verify all links against current Microsoft Learn before a customer-facing engagement - this
> scenario targets Unified Catalog's **preview** REST API surface (`2026-03-20-preview`), and the
> underlying OKRs *feature itself* (not just its API) is separately Microsoft-labeled preview.