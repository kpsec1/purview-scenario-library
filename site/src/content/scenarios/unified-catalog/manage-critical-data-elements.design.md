---
part: "design"
parent: "unified-catalog/manage-critical-data-elements"
---
## 1. Problem statement

`scenarios/unified-catalog/manage-data-products/` groups a scanned table into one requestable
"Customer Master Data" product. That solves discovery at the *table* level. It doesn't solve a
different, narrower problem: the same logical piece of information — a customer's identifier —
usually exists as differently-named **columns** scattered across several source systems
(`CustID` in one table, `CID` in another, `CustomerID` in a third), with no single object in
Purview that says "these are the same thing." A **critical data element (CDE)** is Microsoft's
answer: a named, governance-domain-scoped logical container that maps physical columns from one
or more data assets into a single concept a data quality rule, an access policy, or a data
consumer can reason about once instead of once per source
[[1]](README.md#12-references) [[6]](README.md#12-references). This scenario creates one CDE,
maps a real, already-scanned column to it, and — because Microsoft's own portal automatically
rolls a CDE's mapped columns up into "associated data products" — validates that rollup as a live
cross-check against `manage-data-products`' own output, closing the follow-up
`PROGRESS.md` recorded against this repo's Unified Catalog coverage.

## 2. Design goals

1. Create/update a critical data element from a declarative JSON file, the identical
   idempotent-upsert pattern this repo's other Unified Catalog scenarios established
   (Section 3).
2. Map one or more Data Map columns to the CDE — the part neither `curate-business-glossary` nor
   `manage-data-products` needed, because neither of them operates below the table/asset level.
   This requires bridging two different REST surfaces this repo has so far kept separate: the
   Unified Catalog API's new (2026-03-20-preview) **Data Columns** operation group, and the
   Data Map/Atlas **Entity** API `end-to-end-lineage-validation`/`custom-process-lineage` already
   use — because a Data Map column's own GUID is not something a curator can copy from the portal
   the way a table's asset GUID can (Section 4).
3. Treat the CDE-to-data-product "associated data products" rollup Microsoft's portal computes
   automatically as something this scenario **observes**, not something it creates — there is no
   "link this CDE to that data product" operation to script, by design (Section 5).
4. Ship DRAFT by default; `-Publish` is a separate, explicit flag, matching this repo's other
   Unified Catalog scenarios' review-before-publish discipline.
5. Everything idempotent and re-runnable per `AGENTS.md` §4, with a `-WhatIf` dry-run path.

## 3. Idempotency design

The critical data element itself follows `manage-data-products`' exact pattern: **Create**
requires a caller-generated `id` (confirmed in the Critical Data Elements - Create REST
reference — `id` is a required UUID field in the request body, not server-assigned), so
`Find-CriticalDataElementByName` queries **Critical Data Elements - Query**
(`POST .../criticalDataElements/query`) scoped to the domain (`domainIds`) with a `nameKeyword`
filter, then filters client-side for an exact (case-insensitive) name match before deciding
create vs. update — the same `nameKeyword`-match-semantics mitigation `curate-business-glossary`
and `manage-data-products` already use for the identical undocumented-match-semantics gap
(`README.md` Section 11 in each).

Each mapped column has a two-stage idempotency check, mirroring `manage-data-products`' own
two-stage "wrap, then link" design for its data asset:

1. **Column wrapper.** **Data Columns - Query** exposes `filter.sourceAssetId`/
   `filter.sourceColumnId` field filters that match directly against the underlying Data Map
   asset/column GUIDs — an exact-match server-side filter, not a name approximation — so
   `Find-DataColumnBySource` trusts it directly, passing `includingOrphans: true` so a column
   wrapper created by a previous run that isn't (yet) linked to anything is still found rather
   than silently re-ingested a second time.
2. **CDE-to-column relationship.** `Test-CdeRelationshipExists` calls **Critical Data Elements -
   List Relationships** for the target entity category and skips **Create Relationship** if the
   target `entityId` is already present — the identical list-before-create guard
   `manage-data-products`' `Test-RelationshipExists` uses for its own DATAASSET/TERM links.

## 4. Resolving a Data Map column's own GUID — the piece no prior scenario needed

`manage-data-products`' definition file asks the operator to copy a **table's** Data Map asset
GUID from the portal's Overview page. That pattern doesn't extend to columns: Microsoft Purview's
portal doesn't expose a column-level GUID anywhere a curator could copy it from, and a table can
have dozens of columns, so requiring a curator to somehow obtain one by hand doesn't scale the
way it does for a single table GUID per scenario run.

Instead, this scenario's definition file asks only for what a curator *can* read off the portal's
Schema tab — the table's own Data Map asset GUID (already known, reused from
`scan-azure-sql-and-classify`/`manage-data-products`) plus the column's plain display name (e.g.
`CustomerID`) — and `Resolve-DataMapColumnId` derives the column's GUID itself:

1. `GET /datamap/api/atlas/v2/entity/guid/{dataMapAssetId}?api-version=2023-09-01` (the same
   **Entity** operation group and API version `docs/automation-surface.md` §4 already pins for
   this repo's Data Map/Atlas work) returns the table entity with its `relationshipAttributes`
   populated.
2. Microsoft's own "Type definitions and how to create custom types" tutorial documents
   `azure_sql_table`'s exact type definition: its `options.schemaElementsAttribute` is `columns`,
   and `relationshipAttributeDefs` lists a `columns` attribute (`typeName: array<azure_sql_column>`,
   `relationshipTypeName: azure_sql_table_columns`) — confirming, from Microsoft's own worked
   example for this exact entity type (not a generic Atlas assumption), that
   `entity.relationshipAttributes.columns` is a real, populated array of column references, each
   carrying its own `guid` and `displayText` (the column's name) [[16]](README.md#12-references).
3. `Resolve-DataMapColumnId` matches `columnName` from the definition file against each
   referenced column's `displayText` (case-sensitive exact match) and returns that column's
   `guid` — the `dataMapColumnId` **Data Columns - Ingest** needs.

This is the first scenario in this repo to call both the Unified Catalog API and the Data
Map/Atlas API from the same script for the same object graph. `docs/automation-surface.md` §4's
routing table is extended (a small, doc-only addition to this fragment, not a separate one) to
record that a curator-facing "column name" in a Unified Catalog critical-data-element definition
resolves through the Data Map/Atlas Entity API, not the Unified Catalog API itself.

## 5. The data-product rollup is observed, never created

Microsoft's own critical-data-elements documentation states plainly that a CDE's details page
shows "**Associated data products**: An automatically generated list of data products that have
assets associated with your critical data element," refreshed only when columns are added or
removed [[1]](README.md#12-references) — there is no "attach this CDE to that data product"
action anywhere in the portal or, as far as this build's grounding pass found, in the REST API.
The mechanism is one-directional and asset-mediated: `manage-data-products` links a data product
to a Unified Catalog **data asset**; this scenario links a CDE to a Unified Catalog **data
column** that belongs to the same underlying Data Map asset; Microsoft's platform computes the
data-product association from that shared underlying asset, not from any relationship this
scenario's script creates directly between the CDE and the data product.

This scenario's validate script reads that computed rollup back — **Critical Data Elements - List
Relationships** with `entityType=DATAPRODUCT` — and reports (as an informational, non-fatal
check) whether `manage-data-products`' own "Customer Master Data" product appears in it. Whether
the `DATAPRODUCT` entity category is actually populated by this specific rollup (as opposed to
only by a relationship this scenario's script would have to create itself, which per the above it
does not) is not directly confirmed by any Microsoft Learn page this build's grounding pass found
— flagged as an explicit VERIFY in `README.md` §11 rather than asserted as fact, per `AGENTS.md`
§4's no-guessing standard. If the check finds nothing, that is reported as a `[WARN]`, not
proof the underlying platform behavior itself doesn't exist — see `README.md` §7.

## 6. The `entityType=DATACOLUMN` vs. `CRITICALDATACOLUMN` discrepancy

Every worked request/response example this build fetched for the Critical Data Elements **Create
Relationship**, **List Relationships**, and **Delete Relationship** operations uses
`entityType=CRITICALDATACOLUMN` in its sample URL — but the `EntityCategory` enum each of those
same three reference pages formally documents has no `CRITICALDATACOLUMN` value at all; it lists
`DATACOLUMN` instead (alongside `DOMAIN`, `DATAPRODUCT`, `TERM`, `DATAASSET`, `OBJECTIVE`,
`KEYRESULT`, `CRITICALDATAELEMENT`, `CUSTOMMETADATA`, `ATTRIBUTE`, `ATTRIBUTEINSTANCE`,
`WORKFLOW`, `CATALOGSNAPSHOT`, `WORKFLOWRUN`). This is a genuine, internally-inconsistent
Microsoft Learn reference page, not a gap this build failed to research — the same
`CRITICALDATACOLUMN`-in-example-vs-not-in-enum pattern repeats identically across all three
operations, so it is not an isolated typo.

This scenario's scripts send `entityType=DATACOLUMN` — the value the enum table actually
declares as valid — reasoning that a formally-documented enum is more likely to reflect the real
API contract than a copy-pasted example value. This is a judgment call, not a confirmed fact:
`README.md` §11 states the discrepancy explicitly and names `CRITICALDATACOLUMN` as the fallback
value to try first if a tenant rejects `DATACOLUMN`, rather than silently picking one and hiding
the ambiguity.

## 7. Non-goals

- **Linking the CDE to glossary terms.** Microsoft's portal exposes a "Manage related terms"
  action on a CDE's details page; this scenario's definition file and scripts don't script it.
  `manage-data-products`' own term-linking code (`entityType=TERM` on a **Create Relationship**
  call) would extend to a CDE with no new grounding required — a natural, small follow-up, not
  built here to keep this fragment scoped to the column-mapping capability `PROGRESS.md` asked
  for.
- **Critical data element access policies.** Microsoft's docs describe a **Manage policies**
  action on a CDE, portal-only, with the same "two different 'Policies' concepts" trap
  `manage-data-products/design.md` §5 already documents for data products — no REST operation for
  this specific access-request-policy feature was found during this build's grounding pass either.
- **Bulk import (preview) of many critical data elements from CSV.** Same rationale
  `curate-business-glossary/design.md` §3 and `manage-data-products/design.md` §6 give for their
  own object types: a one-time seed tool, not an update-safe elements-as-code mechanism, since
  Microsoft's own bulk-import feature can't edit existing records (confirmed for CDEs
  specifically: "The bulk import process can't be used to edit or update critical data
  elements.").
- **Deleting the Unified Catalog data column wrapper object.** As of the `2026-03-20-preview` API
  version, the **Data Columns** operation group has no `Delete` operation at all (only `Get`,
  `Ingest`, `Query`, `Add Related Entity`, `Delete Related`, `List Related Entities`) — this is
  not a scope choice this scenario made but a real capability gap in the current API surface,
  documented plainly in `rollback.md` rather than worked around.
- **Custom attributes and expected-data-type validation beyond the four base `dataType` values**
  (`TEXT`, `NUMBER`, `DATETIME`, `BOOLEAN`). Microsoft's portal supports custom attribute groups
  scoped per governance domain (the same mechanism `unified-catalog-attributes-business-concept`
  documents for data products); this scenario's definition file doesn't model them.
