---
part: "design"
parent: "unified-catalog/manage-data-products"
---
## 1. Problem statement

A governance domain and a curated glossary ([`unified-catalog/curate-business-glossary`](/scenarios/unified-catalog/curate-business-glossary/))
and a scanned, classified table ([`data-map/scan-azure-sql-and-classify`](/scenarios/data-map/scan-azure-sql-and-classify/)) each solve one
piece of "can a consumer find and trust this data" — but none of them, alone, answer "which table
is *the* authoritative customer table, and how do I get access to it." That is what a **data
product** is for: a named, ownable, requestable grouping of one or more data assets with a
business use case attached, so a consumer requests access to "Customer Master Data" once instead
of reverse-engineering which of several similarly-named SQL tables is the real source
[[1]](README.md#12-references). Microsoft's own "Master data management in Microsoft Purview"
article documents this exact five-step flow — register/scan a source, create a data product,
create a glossary term and link it, then curate the product by reviewing its linked assets
[[2]](README.md#12-references) — which this scenario automates end to end, reusing the domain and
terms this repo's two prior Unified Catalog/Data Map scenarios already created.

## 2. Design goals

1. Create/update a data product from a declarative JSON file, the same idempotent-upsert pattern
   [`unified-catalog/curate-business-glossary`](/scenarios/unified-catalog/curate-business-glossary/)'s `New-BusinessGlossary.ps1` established
   for terms (Section 3).
2. Wrap an already-scanned Data Map asset as the newer (2026-03-20-preview) Unified Catalog "data
   asset" object type, and link it to the data product — closing the follow-up this repo's
   `PROGRESS.md` recorded against both `curate-business-glossary` and `data-quality/
   rules-and-scorecards`, which each deferred "a Data Products scenario" as a shared prerequisite
   (Section 4).
3. Link the data product to the glossary terms `curate-business-glossary` already created,
   reproducing the portal's own "link terms to data products" feature as code
   [[5]](README.md#12-references) (Section 5).
4. Ship "draft" by default, matching this repo's established Unified Catalog pattern; `-Publish`
   is a separate, explicit flag — and this scenario is honest about what `-Publish` does **not**
   do for the consumer, unlike a scenario that quietly assumes publish equals "ready to use"
   (Section 6).
5. Everything idempotent and re-runnable per `AGENTS.md` §4, with a `-WhatIf` dry-run path.

## 3. Idempotency design

Reuses `curate-business-glossary`'s exact identity-resolution pattern for the same reason it
applies here: **Create** requires a caller-generated `id`, and there is no server-assigned,
name-derived identity to key off. `Find-DataProductByName` queries
`POST /datagovernance/catalog/dataProducts/query` scoped to the domain (`domainIds`) with a
`nameKeyword` filter, then filters client-side for an exact (case-insensitive) name match before
deciding create vs. update — the identical mitigation `curate-business-glossary/design.md` Section
4 records for the same undocumented `nameKeyword` match-semantics gap.

The Unified Catalog **data asset** wrapper has a cleaner idempotency story: **Data Assets - Query**
exposes a `sourceAssetIds` filter that matches directly against the underlying Data Map asset's own
GUID [[11]](README.md#12-references) — an exact-match server-side filter, not a name-based
approximation — so `Find-DataAssetBySourceId` trusts it directly rather than re-checking
client-side.

Relationships (data-asset-to-product, term-to-product) are idempotent via a **list-before-create**
check: `Test-RelationshipExists` calls **List Relationships** for the target `entityType` and skips
the **Create Relationship** call if the target `entityId` is already present. This is simpler than
the term-relationship pattern in `curate-business-glossary` (which has no such list-before-create
guard and instead accepts that `Add-TermRelationship`'s idempotency is unconfirmed) — worth noting
as an incremental improvement this scenario's narrower relationship set made practical.

## 4. Why a separate Unified Catalog "data asset" object, not the Data Map asset directly

The 2026-03-20-preview API version introduced a `Data Assets` operation group distinct from the
Data Map/Atlas entity API this repo's `scan-azure-sql-and-classify` and
`end-to-end-lineage-validation` scenarios call directly [[9]](README.md#12-references). A Unified
Catalog data asset is a thin wrapper: **Create** takes only `source.assetId` (the Data Map GUID),
`contacts`, and `openInUrl`; the server resolves the asset's type, schema, and classifications from
Data Map itself and returns a fully-typed `DataAssetAzureSqlTable`/`DataAssetAdlsGen2Path`/
`DataAssetGeneral` object with its **own**, separate GUID [[10]](README.md#12-references). **Data
Products - Create Relationship** links against *this* wrapper's GUID (`entityType=DATAASSET`), not
the original Data Map asset GUID — a detail this scenario's validate script makes visible by
reporting both IDs rather than treating them as interchangeable.

**Why this matters operationally:** a data product's linked-asset count and classification rollup
are computed from the Unified Catalog data asset, not the raw Data Map entity — so an asset scanned
by `scan-azure-sql-and-classify` is invisible to any data product until this scenario's (or an
equivalent) wrap-and-link step runs. This is the missing link the `PROGRESS.md` follow-up under
`data-estate-insights/classification-coverage-report` implicitly assumed would exist once a Data
Products scenario landed.

## 5. Publish is gated on a portal-only access policy this scenario does not script

Microsoft's own documentation states plainly: **"Before you can publish, you need to add data
assets to your data product and set up a data access policy so users can request access to your
data product"** [[1]](README.md#12-references). A **data product access policy** (who can request
access, whether manager/privacy approval is required, the terms-of-use attestation) is configured
entirely in the portal's **Manage policies** flow [[4]](README.md#12-references) — this build's
grounding pass found no REST operation group covering it. (The REST API does expose an operation
group literally named `Policies`, but its `List`/`Update` operations return a very different
object — RBAC-style attribute/decision rules keyed by domain/data-product GUIDs, the underlying
authorization-policy engine, not the "who can request access and what do they attest to" feature
the portal calls a data product access policy. Confirmed by direct inspection of the `Policies -
List` worked example; not conflated in this scenario's code or docs.)

This scenario's `Publish-DataProduct` function therefore does exactly what
`New-BusinessGlossary.ps1`'s `Publish-Term` does — a full-replace `PUT` reusing the server's own
current fields, changing only `status` — but adds a loud `Write-Warning` before attempting it,
naming the access-policy prerequisite explicitly, because there is no REST-scriptable way for this
automation to configure or even confirm that prerequisite itself. Whether the REST `Update`
operation *enforces* the same rule server-side (rejecting the PUT) or only the portal UI enforces
it is an open **VERIFY** — see `README.md` Section 11.

## 6. Non-goals

- **Configuring the data product access policy itself** (Section 5) — portal-only, no REST surface
  found during this build's grounding pass.
- **Critical data elements.** Linking assets/columns to critical data elements is a related but
  distinct Unified Catalog capability (`entityType=CRITICALDATAELEMENT`/`CRITICALDATACOLUMN`) with
  its own worked REST example this scenario deliberately does not reuse for asset/term linking
  (`README.md` Section 11's VERIFY on the `Create Relationship` body shape) — a natural follow-up.
- **OKR linking.** Data products can link to Objectives and Key Results the same way they link to
  terms; this scenario's definition file and scripts cover only `TERM` and `DATAASSET` entity
  types, matching the "Customer 360" narrative's actual needs rather than exercising every
  `EntityCategory` value for its own sake.
- **Bulk import (preview) of many data products from CSV.** Same rationale
  `curate-business-glossary/design.md` Section 3 gives for glossary terms: a one-time seed tool,
  not an update-safe glossary/product-as-code mechanism, since Microsoft's own bulk-import feature
  cannot edit existing records.
- **Registering or scanning the underlying Data Map asset.** This scenario assumes
  [`data-map/scan-azure-sql-and-classify`](/scenarios/data-map/scan-azure-sql-and-classify/) has already run at least once; it consumes that
  scenario's output (a Data Map asset GUID), it does not produce one.
