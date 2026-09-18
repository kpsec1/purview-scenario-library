---
part: "rollback"
parent: "unified-catalog/curate-business-glossary"
---
## Recommended sequence

A published glossary term is visible catalog-wide and may already be linked to data products,
assets, or another term's relationship, roll back in stages rather than deleting outright.

### Stage 1, Unpublish (reversible, seconds)

```powershell
./deploy/Remove-BusinessGlossary.ps1 `
    -PurviewAccountEndpoint 'https://api.purview-service.microsoft.com' `
    -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
    -GlossaryDefinitionPath './deploy/glossary/customer-experience-glossary.json'
```

This sets every term and the governance domain itself back to `DRAFT` status via `PUT`, reusing
each object's own currently-stored fields (fetched via `GET`) rather than the local definition
file, a portal-made edit this script doesn't know about (a custom attribute, an added resource)
survives an unpublish. Nothing is deleted; the domain and terms remain visible to Data Stewards
and Governance Domain Owners. Re-publish instantly:

```powershell
./deploy/New-BusinessGlossary.ps1 `
    -PurviewAccountEndpoint 'https://api.purview-service.microsoft.com' `
    -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
    -GlossaryDefinitionPath './deploy/glossary/customer-experience-glossary.json' -Publish
```

Use this stage for: a definition error discovered after publishing, a term that needs rework
before it's shown catalog-wide again, or a temporary pause during a larger glossary restructuring.

### Stage 2, Permanent removal (not reversible)

```powershell
./deploy/Remove-BusinessGlossary.ps1 `
    -PurviewAccountEndpoint 'https://api.purview-service.microsoft.com' `
    -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
    -GlossaryDefinitionPath './deploy/glossary/customer-experience-glossary.json' -Purge
```

This deletes every term in the definition file (`DELETE /terms/{id}`), then the governance domain
itself (`DELETE /businessdomains/{id}`). There is no "undo", re-establishing the glossary means
re-running `deploy/New-BusinessGlossary.ps1` from scratch, which generates **new** term/domain IDs
(any external system that recorded the old IDs, e.g. a data product's term link, must be
re-created against the new ones). Only do this when the domain is being permanently retired, not
as a routine way to "reset and re-seed."

**Prerequisite the script does not check for you:** Microsoft's portal guidance for deleting a
governance domain requires first unpublishing it and removing all business concepts within it
. This script deletes the terms it knows about (from the definition
file) before deleting the domain, but if the domain has **other** terms, data products, OKRs, or
critical data elements this script didn't create, the domain delete call may fail server-side
until those are also removed, check the domain in the portal first if it's been used for anything
beyond this scenario's four terms.

## What rollback does **not** undo

- **Term/domain history.** Microsoft Learn does not document a separate audit trail for
 Unified Catalog object changes distinct from the general Microsoft Purview audit log; this
 scenario does not script audit-log retrieval for these changes.
- **Links from data products, other terms, or critical data elements to a deleted term.** If a
 term this script deletes was linked to a data product or another domain's term (§7 non-goal
 in `design.md` notwithstanding, a human could have added such a link via the portal after
 deployment), that link becomes a dangling reference; check the portal's **Related** tab on
 anything that might reference these terms before purging.
- **Any custom attribute values a Governance Domain admin configured** on these terms via the
 portal, the domain's custom-attribute-group definitions themselves are not touched by this
 scenario's scripts (create/update/delete act only on the terms and domain object, not on the
 tenant's custom-attribute schema).

## Verification after rollback

```powershell
./validate/Test-BusinessGlossary.ps1 `
    -PurviewAccountEndpoint 'https://api.purview-service.microsoft.com' `
    -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
    -GlossaryDefinitionPath './deploy/glossary/customer-experience-glossary.json'
```

After **Stage 1**, expect every "is published" check to report `[WARN]` (DRAFT is a valid state,
not a hard failure) while existence/content checks still `[PASS]`. After **Stage 2**, expect every
existence check to `[FAIL]`, confirming the terms and domain are gone, not merely unpublished.
