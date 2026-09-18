---
part: "rollback"
parent: "unified-catalog/manage-critical-data-elements-related-terms"
---
## Caution: unlinking is not purely metadata cleanup

If a related term carries its own access policy (e.g. a manager-approval requirement),
`README.md` §2 documents that policy as inheriting/aggregating onto every data product the
critical data element's mapped columns touch. Removing a term link may therefore **loosen** that
aggregated access requirement on downstream data products, not just tidy up unused metadata —
`deploy/Remove-CdeRelatedTerm.ps1` prints an explicit `Write-Warning` to this effect before every
unlink. Neither this scenario's scripts nor this build's grounding pass (Microsoft Learn page
fetches only) can confirm whether Microsoft's platform re-evaluates the aggregated policy view
immediately on unlink, on a delay, or only the next time the data product's policy is explicitly
reopened in the portal — treat a term unlink on a policy-bearing term as a change-management event
worth its own review, not a routine cleanup step, until this is confirmed against a pilot tenant.

## Recommended sequence

Unlike its `manage-critical-data-elements` sibling, this scenario has no multi-stage "publish
state" of its own to unwind — a relationship either exists or it doesn't. Rollback is a single
kind of action (unlink), offered in three scopes.

### Targeted unlink — undo exactly what this scenario added (reversible, seconds)

```powershell
./deploy/Remove-CdeRelatedTerm.ps1 `
    -PurviewAccountEndpoint 'https://api.purview-service.microsoft.com' `
    -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
    -DefinitionPath './deploy/config/customer-id-related-terms.sample.json'
```

With no `-TermNames`/`-RemoveAll` switch, this unlinks exactly the terms listed in the definition
file's `relatedTerms` array — the same set `Add-CdeRelatedTerm.ps1` would have added — resolving
each by name fresh rather than trusting a cached ID. Re-link instantly:

```powershell
./deploy/Add-CdeRelatedTerm.ps1 `
    -PurviewAccountEndpoint 'https://api.purview-service.microsoft.com' `
    -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
    -DefinitionPath './deploy/config/customer-id-related-terms.sample.json'
```

### Selective unlink — remove one specific term without touching the rest

```powershell
./deploy/Remove-CdeRelatedTerm.ps1 `
    -PurviewAccountEndpoint 'https://api.purview-service.microsoft.com' `
    -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
    -DefinitionPath './deploy/config/customer-id-related-terms.sample.json' `
    -TermNames 'Customer'
```

Use this when only one of several linked terms was a mistake — e.g. a term name typo that
resolved to the wrong (but existing) term.

### Full unlink — remove every related term, regardless of source (not scoped to the file)

```powershell
./deploy/Remove-CdeRelatedTerm.ps1 `
    -PurviewAccountEndpoint 'https://api.purview-service.microsoft.com' `
    -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
    -DefinitionPath './deploy/config/customer-id-related-terms.sample.json' `
    -RemoveAll
```

Enumerates the critical data element's current `entityType=TERM` relationships live from the API
and deletes every one — including a term linked outside this scenario's scripts entirely (the
portal's own **+ Add term** button, or the reciprocal "Add critical data element" flow from a
term's own Related tab, per `design.md` §4). **Required before permanently deleting the critical
data element itself** — see the next section.

## Interaction with `manage-critical-data-elements`'s own rollback

Microsoft's own documented delete prerequisite for a critical data element is explicit: "you need
to unpublish it and delete all columns within it, and any links to glossary terms"
(`README.md` §1, ref 1). `manage-critical-data-elements/deploy/Remove-CriticalDataElement.ps1`'s
own `-Purge` stage predates this scenario and only removes `entityType=DATACOLUMN` relationships
— it does **not** remove any `TERM` relationship this scenario created. If the CDE has any related
terms when `-Purge` is attempted, expect the delete call to fail against Microsoft's own stated
prerequisite (or, if the API is more permissive than the portal's stated procedure, to leave an
orphaned relationship pointing at a now-deleted CDE — neither behavior is confirmed without a
pilot tenant).

**Run this scenario's own full unlink first:**

```powershell
./deploy/Remove-CdeRelatedTerm.ps1 `
    -PurviewAccountEndpoint 'https://api.purview-service.microsoft.com' `
    -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
    -DefinitionPath './deploy/config/customer-id-related-terms.sample.json' -RemoveAll
```

then proceed with `manage-critical-data-elements/deploy/Remove-CriticalDataElement.ps1 -Purge` as
that scenario's own `rollback.md` documents.

## What rollback does **not** undo

- **The critical data element itself.** [`unified-catalog/manage-critical-data-elements`](/scenarios/unified-catalog/manage-critical-data-elements/)
  owns its lifecycle; this scenario only looks it up by name.
- **The glossary term(s) themselves.** [`unified-catalog/curate-business-glossary`](/scenarios/unified-catalog/curate-business-glossary/) owns
  their lifecycle; this scenario only looks them up by name. Unlinking a term from a CDE never
  deletes, unpublishes, or edits the term itself.
- **The governance domain.** Neither this scenario nor either of its two prerequisite siblings own
  its lifecycle.
- **Any access-policy aggregation the link enabled** (`README.md` §2/§8). Removing the link stops
  future aggregation going forward; this scenario has no way to script or verify how (or whether)
  Microsoft's platform re-evaluates a data product's already-computed inherited-policy view after
  the underlying link is removed — not confirmed by any Microsoft Learn page this build's
  grounding pass found.
- **Relationship history.** Same limitation every sibling Unified Catalog scenario in this repo
  already records — no separate audit trail for this class of object change was found distinct
  from the general Microsoft Purview audit log.

## Verification after rollback

```powershell
./validate/Test-CdeRelatedTerms.ps1 `
    -PurviewAccountEndpoint 'https://api.purview-service.microsoft.com' `
    -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
    -DefinitionPath './deploy/config/customer-id-related-terms.sample.json'
```

After a **targeted** or **selective** unlink, expect the corresponding term's "is linked" check to
`[FAIL]` (expected — the definition file still names it, but the link is gone) while the term's
own "exists" check still `[PASS]`s. After a **full unlink**, expect every term's "is linked" check
to `[FAIL]` and the informational total-relationship count to report `0`.
