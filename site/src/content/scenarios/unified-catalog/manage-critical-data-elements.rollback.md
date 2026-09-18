---
part: "rollback"
parent: "unified-catalog/manage-critical-data-elements"
---
## Recommended sequence

A published critical data element may already be relied on by a data quality rule, an access
policy, or a downstream data product's "associated" rollup, roll back in stages rather than
deleting outright, the same discipline `manage-data-products/rollback.md` uses.

### Stage 1, Unpublish (reversible, seconds)

```powershell
./deploy/Remove-CriticalDataElement.ps1 `
    -PurviewAccountEndpoint 'https://api.purview-service.microsoft.com' `
    -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
    -DefinitionPath './deploy/config/customer-id-cde.sample.json'
```

Sets the critical data element back to `DRAFT` via `PUT`, reusing its own currently-stored fields
(fetched via `GET`) rather than the local definition file, a portal-made edit this script
doesn't know about survives an unpublish. Nothing is deleted or unmapped; the element remains
visible to Data Stewards, Data Product Owners, and Governance Domain Owners. Re-publish instantly:

```powershell
./deploy/New-CriticalDataElement.ps1 `
    -PurviewAccountEndpoint 'https://api.purview-service.microsoft.com' `
    -DataMapEndpoint 'https://api.purview-service.microsoft.com' `
    -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
    -DefinitionPath './deploy/config/customer-id-cde.sample.json' -Publish
```

Use this stage for: a description or data-type correction discovered after publishing, or a
temporary pause while a mapped column's quality is under review.

### Stage 2, Remove links (reversible, but breaks the element's usefulness)

```powershell
./deploy/Remove-CriticalDataElement.ps1 `
    -PurviewAccountEndpoint 'https://api.purview-service.microsoft.com' `
    -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
    -DefinitionPath './deploy/config/customer-id-cde.sample.json' -RemoveLinks
```

Deletes every `entityType=DATACOLUMN` relationship the critical data element has
(`DELETE .../criticalDataElements/{id}/relationships`), enumerated directly from the element's
own current relationships, not re-derived from the definition file, so this also cleans up any
column mapped outside this scenario's scripts (e.g. via the portal's own **+ Add column** button).

**The underlying Unified Catalog data column wrapper object(s) are left in place.** As of API
version `2026-03-20-preview`, the **Data Columns** operation group has no `Delete` operation at
all, `Get`, `Ingest`, `Query`, `Add Related Entity`, `Delete Related`, and `List Related
Entities` are the only operations Microsoft documents (design.md §7). This is a real capability
gap in the current API surface, not a safety choice this scenario made, an unmapped data column
wrapper simply has no way to be permanently removed via REST today. It costs nothing to leave in
place: per Microsoft's own billing FAQ, only an asset actually *attached* to a governance concept
is a billed governed asset (§10 of `README.md`), and an unlinked wrapper has no relationships.

A critical data element with no mapped columns still exists but is no longer a meaningful
concept; re-run `New-CriticalDataElement.ps1` to re-establish the mappings (idempotent, it
re-adds only what's missing, re-ingesting the same underlying wrapper rather than creating a
duplicate).

### Stage 3, Permanent removal (not reversible)

```powershell
./deploy/Remove-CriticalDataElement.ps1 `
    -PurviewAccountEndpoint 'https://api.purview-service.microsoft.com' `
    -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
    -DefinitionPath './deploy/config/customer-id-cde.sample.json' -Purge
```

`-Purge` implies `-RemoveLinks`, then deletes the critical data element itself
(`DELETE /criticalDataElements/{id}`). There is no "undo", re-establishing the element means
re-running `deploy/New-CriticalDataElement.ps1` from scratch, which generates a **new** critical
data element ID. Microsoft's own portal procedure for manual deletion requires unpublishing,
removing all columns, and removing all term links first [[1]](README.md#12-references), this
script's `-Purge` (preceded by `-RemoveLinks`) reproduces the column-removal and status
requirements; it does not need to remove term links because this scenario never creates any
(design.md §7).

## What rollback does **not** undo

- **The underlying Data Map asset or its columns.** `scenarios/data-map/scan-azure-sql-and-classify/`
  owns that asset's lifecycle; this scenario's rollback never touches it.
- **The governance domain.** `scenarios/unified-catalog/curate-business-glossary/` owns its
  lifecycle; this scenario only looks it up by name.
- **The Unified Catalog data column wrapper object(s)**, see Stage 2 above; there is currently no
  REST operation to delete one.
- **Any data product's own relationships or its "associated data products" computation.** That
  rollup is entirely computed by Microsoft's platform from the shared underlying Data Map asset
  (design.md §5); nothing this scenario's rollback does can or needs to touch it directly, it
  will simply stop showing this critical data element once the mapped column(s) are removed
  (subject to the refresh-lag caveat in `README.md` §8).
- **Critical data element/column history.** Same limitation `curate-business-glossary/rollback.md`
  and `manage-data-products/rollback.md` record, no separate audit trail for Unified Catalog
  object changes was found distinct from the general Microsoft Purview audit log.

## Verification after rollback

```powershell
./validate/Test-CriticalDataElement.ps1 `
    -PurviewAccountEndpoint 'https://api.purview-service.microsoft.com' `
    -DataMapEndpoint 'https://api.purview-service.microsoft.com' `
    -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
    -DefinitionPath './deploy/config/customer-id-cde.sample.json'
```

After **Stage 1**, expect the "is published" check to `[WARN]` (DRAFT is a valid state) while
existence and column-mapping checks still `[PASS]`. After **Stage 2**, expect the column-mapping
checks to `[FAIL]` (the data column wrapper itself may still `[PASS]` its own existence check,
since it isn't deleted) while the critical data element still `[PASS]`s existence. After
**Stage 3**, expect every existence check to `[FAIL]`, confirming the critical data element is
gone, not merely unmapped.
