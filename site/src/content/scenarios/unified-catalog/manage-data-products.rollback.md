---
part: "rollback"
parent: "unified-catalog/manage-data-products"
---
## Recommended sequence

A published data product may already have active access requests and consumers relying on it —
roll back in stages rather than deleting outright.

### Stage 1 — Unpublish (reversible, seconds)

```powershell
./deploy/Remove-DataProduct.ps1 `
    -PurviewAccountEndpoint 'https://api.purview-service.microsoft.com' `
    -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
    -DefinitionPath './deploy/config/customer-master-data-product.sample.json'
```

Sets the data product back to `DRAFT` via `PUT`, reusing its own currently-stored fields (fetched
via `GET`) rather than the local definition file — a portal-made edit this script doesn't know
about survives an unpublish. Nothing is deleted or unlinked; the product remains visible to Data
Product Owners, Data Stewards, and Governance Domain Owners. Re-publish instantly (once the access
policy prerequisite still holds — README.md §3):

```powershell
./deploy/New-DataProduct.ps1 `
    -PurviewAccountEndpoint 'https://api.purview-service.microsoft.com' `
    -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
    -DefinitionPath './deploy/config/customer-master-data-product.sample.json' -Publish
```

Use this stage for: a description/use-case error discovered after publishing, or a temporary pause
while the underlying asset or its data quality is under review.

### Stage 2 — Remove links (reversible, but breaks the product's usefulness)

```powershell
./deploy/Remove-DataProduct.ps1 `
    -PurviewAccountEndpoint 'https://api.purview-service.microsoft.com' `
    -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
    -DefinitionPath './deploy/config/customer-master-data-product.sample.json' -RemoveLinks
```

Deletes the data-asset and both term relationships (`DELETE .../relationships`). The Unified
Catalog data asset **wrapper** and the glossary terms themselves are left untouched — they may be
referenced by other data products this scenario doesn't know about. A data product with no linked
assets still exists but is no longer a meaningful grouping; re-run `New-DataProduct.ps1` to
re-establish the links (idempotent — it re-adds only what's missing).

### Stage 3 — Permanent removal (not reversible)

```powershell
./deploy/Remove-DataProduct.ps1 `
    -PurviewAccountEndpoint 'https://api.purview-service.microsoft.com' `
    -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
    -DefinitionPath './deploy/config/customer-master-data-product.sample.json' -Purge
```

`-Purge` implies `-RemoveLinks`, then deletes the data product itself
(`DELETE /dataProducts/{id}`). There is no "undo" — re-establishing the product means re-running
`deploy/New-DataProduct.ps1` from scratch, which generates a **new** data product ID (any external
system that recorded the old ID, e.g. a saved access-request link, must be re-created against the
new one).

**Add `-DeleteDataAssetWrapper` only if you have separately confirmed** (via the portal, or a
manual `Data Assets - Query` call) that no *other* data product still references the same Unified
Catalog data asset wrapper. `Remove-DataProduct.ps1` has no reverse lookup to check this for you —
deleting a wrapper another product still links to would silently orphan that product's asset count
and classification rollup. When in doubt, leave the wrapper in place; it costs nothing extra to
leave orphaned (§10 of `README.md` — billing is per governed asset actually linked to *something*,
and an unlinked wrapper with no relationships is effectively inert).

## What rollback does **not** undo

- **The underlying Data Map asset.** [`data-map/scan-azure-sql-and-classify`](/scenarios/data-map/scan-azure-sql-and-classify/) owns that
  asset's lifecycle; this scenario's rollback never touches it.
- **The governance domain or glossary terms.** [`unified-catalog/curate-business-glossary`](/scenarios/unified-catalog/curate-business-glossary/)
  owns their lifecycle; this scenario only looks them up by name.
- **Data product/asset history.** Microsoft Learn does not document a separate audit trail for
  Unified Catalog object changes distinct from the general Microsoft Purview audit log; this
  scenario does not script audit-log retrieval for these changes (same limitation
  `curate-business-glossary/rollback.md` records).
- **In-flight or completed access requests.** If consumers already requested and were granted
  access to this data product before rollback, `Remove-DataProduct.ps1` does not revoke that
  access — per Microsoft's own documented process, the request approver must separately remove the
  underlying data-asset provisioning *and* delete the access request in the portal
  (README.md reference 4) before an unpublish/purge fully closes the loop.
- **The data product access policy configuration itself** — portal-only, not scripted by this
  scenario in either direction (`design.md` §5).

## Verification after rollback

```powershell
./validate/Test-DataProduct.ps1 `
    -PurviewAccountEndpoint 'https://api.purview-service.microsoft.com' `
    -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
    -DefinitionPath './deploy/config/customer-master-data-product.sample.json'
```

After **Stage 1**, expect the "is published" check to `[WARN]` (DRAFT is a valid state) while
existence/link checks still `[PASS]`. After **Stage 2**, expect both relationship checks to
`[FAIL]` while the product itself still `[PASS]`s existence. After **Stage 3**, expect every
existence check to `[FAIL]` — confirming the data product is gone, not merely unlinked.
