---
part: "rollback"
parent: "unified-catalog/manage-okrs"
---
## Recommended sequence

A published objective may already be cited in a business review deck or linked from a data
product's own details page, roll back in stages rather than deleting outright, the same
discipline `manage-data-products/rollback.md` and `manage-critical-data-elements/rollback.md`
use.

### Stage 1, Unpublish (reversible, seconds)

```powershell
./deploy/Remove-Okr.ps1 `
    -PurviewAccountEndpoint 'https://api.purview-service.microsoft.com' `
    -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
    -DefinitionPath './deploy/config/customer-data-trust-okr.sample.json'
```

Sets the objective back to `Draft` via `PUT`, reusing its own currently-stored fields (fetched via
`GET`) rather than the local definition file, a portal-made edit this script doesn't know about
survives an unpublish. Nothing is deleted or unlinked; the objective remains visible to Data
Stewards and Governance Domain Owners. Re-publish instantly:

```powershell
./deploy/New-Okr.ps1 `
    -PurviewAccountEndpoint 'https://api.purview-service.microsoft.com' `
    -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
    -DefinitionPath './deploy/config/customer-data-trust-okr.sample.json' -Publish
```

Use this stage for: a wording correction discovered after publishing, or a temporary pause while
a key result's underlying metric is under review.

### Stage 2, Remove data-product links (reversible, but breaks the "why it matters" story)

```powershell
./deploy/Remove-Okr.ps1 `
    -PurviewAccountEndpoint 'https://api.purview-service.microsoft.com' `
    -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
    -DefinitionPath './deploy/config/customer-data-trust-okr.sample.json' -RemoveLinks
```

Deletes the `entityType=OBJECTIVE` relationship on each data product named in the definition
file's `relatedDataProducts` array (`DELETE.../dataProducts/{id}/relationships`), enumerated
from the **definition file**, not from the objective, because the Okr operation group has no
"list every data product this objective is linked to" call of its own (design.md §4). **A
data-product link created outside this scenario's scripts (e.g. via the portal's own + Link data
product button, or naming a product this definition file doesn't list) is not touched by this
stage**, a real limitation of enumerating from the file rather than a live authoritative list,
called out explicitly rather than silently assumed complete.

An objective with no linked data products still exists but no longer connects to any governed
data; re-run `New-Okr.ps1` to re-establish the links (idempotent, it re-adds only what's
missing).

### Stage 3, Permanent removal (not reversible)

```powershell
./deploy/Remove-Okr.ps1 `
    -PurviewAccountEndpoint 'https://api.purview-service.microsoft.com' `
    -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
    -DefinitionPath './deploy/config/customer-data-trust-okr.sample.json' -Purge
```

`-Purge` implies `-RemoveLinks`, then deletes every key result
(`DELETE.../objectives/{id}/keyResults/{keyResultId}`) and finally the objective itself
(`DELETE.../objectives/{id}`), matching Microsoft's own documented manual deletion order: "To
delete an OKR, first unpublish it and delete any key results and links to related data products.
Then select Delete". There is no "undo" at the API level, but
unlike this repo's name-identified sibling scenarios, re-running `deploy/New-Okr.ps1` against the
**same, unmodified definition file** after a purge will attempt to `PUT` (update) an id that no
longer exists on the server and receive a 404 on the initial `GET`, the script correctly falls
back to **Create**, which re-creates the objective **using that same id** rather than minting a
new one (design.md §3). This is different from `manage-data-products`/`manage-critical-data-
elements`, where a purge-then-recreate always produces a new id.

## The progress-trend companion needs no rollback of its own

`deploy/Export-OkrProgressTrend.ps1` never mutates the tenant (README.md §8/design.md §8), its
only output is the local trend-log CSV (default `deploy/out/okr-progress-trend.csv`, inside the
repo-gitignored `out/` directory). Deleting that file is the entire "rollback": there is nothing to
undo server-side, and the next `Export-OkrProgressTrend.ps1` run simply re-baselines every entity
(every row reports `ChangeState: Baseline` again, see design.md §8) rather than failing. Do this
whenever the trend log's staleness history is no longer wanted (e.g. after a long pause in this
scenario's use), not as part of Stage 1-3 above.

## What rollback does **not** undo

- **The underlying data product(s).** `scenarios/unified-catalog/manage-data-products/` owns
 their lifecycle; this scenario only looks them up by name.
- **The governance domain.** `scenarios/unified-catalog/curate-business-glossary/` owns its
 lifecycle; this scenario only looks it up by name.
- **A data-product link created outside this scenario's own `relatedDataProducts` list**, see
 Stage 2's explicit caveat above.
- **OKR history.** Same limitation `curate-business-glossary/rollback.md`,
 `manage-data-products/rollback.md`, and `manage-critical-data-elements/rollback.md` record, no
 separate audit trail for Unified Catalog object changes was found distinct from the general
 Microsoft Purview audit log.

## Verification after rollback

```powershell
./validate/Test-Okr.ps1 `
    -PurviewAccountEndpoint 'https://api.purview-service.microsoft.com' `
    -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
    -DefinitionPath './deploy/config/customer-data-trust-okr.sample.json'
```

After **Stage 1**, expect the "is published" check to `[WARN]` (Draft is a valid state) while
existence and key-result checks still `[PASS]`. After **Stage 2**, expect the data-product-link
checks to `[WARN]` (they're informational, not hard failures, README.md §7) while the objective
and key results still `[PASS]` their own existence checks. After **Stage 3**, expect the objective
and every key result existence check to `[FAIL]`, confirming they're actually gone, not merely
unpublished or unlinked.
