---
part: "rollback"
parent: "unified-catalog/governance-domain-hierarchy"
---
## Recommended sequence

A published domain tree may already carry data products, glossary terms, critical data elements,
OKRs, or a data estate mapping, roll back in stages, deepest-first, rather than deleting outright.

### Stage 1, Unpublish (reversible, seconds)

```powershell
./deploy/Remove-GovernanceDomainHierarchy.ps1 `
    -PurviewAccountEndpoint 'https://api.purview-service.microsoft.com' `
    -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
    -HierarchyDefinitionPath './deploy/hierarchy/corporate-sales-marketing-hierarchy.json' -Unpublish
```

This sets every domain in the tree back to `DRAFT` status via `PUT`, **children before parents**
(`Sales - EMEA`, then `Sales` and `Marketing`, then `Corporate`), reusing each domain's own
currently-stored fields (fetched via the same `Enumerate` pass this scenario's deploy script uses)
rather than the local definition file, a portal-made edit this script doesn't know about (an
added attribute value, a data estate mapping set directly in the portal) survives an unpublish.
Nothing is deleted; every domain remains visible to Data Stewards and Governance Domain Owners.
Re-publish instantly:

```powershell
./deploy/New-GovernanceDomainHierarchy.ps1 `
    -PurviewAccountEndpoint 'https://api.purview-service.microsoft.com' `
    -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
    -HierarchyDefinitionPath './deploy/hierarchy/corporate-sales-marketing-hierarchy.json' -Publish
```

Use this stage for: a definition error discovered after publishing, a sub-domain that needs rework
before it's shown tenant-wide again, or a temporary pause during a larger reorganization.

### Stage 2, Permanent removal (not reversible)

```powershell
./deploy/Remove-GovernanceDomainHierarchy.ps1 `
    -PurviewAccountEndpoint 'https://api.purview-service.microsoft.com' `
    -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
    -HierarchyDefinitionPath './deploy/hierarchy/corporate-sales-marketing-hierarchy.json' -Purge
```

This deletes every domain in the tree (`DELETE /businessdomains/{id}`), **children before parents**
, Microsoft's own portal guidance for deleting a governance domain requires first unpublishing it
and removing all business concepts within it, **including any subdomains**
, and this script's deepest-first ordering exists specifically to
satisfy that documented requirement without a manual pre-step. There is no "undo", re-establishing
the hierarchy means re-running `deploy/New-GovernanceDomainHierarchy.ps1` from scratch, which
generates **new** domain IDs (any external system that recorded the old IDs, e.g. a data product
or glossary term's `domain` reference, must be re-pointed at the new ones).

**Prerequisite the script does not check for you:** if a domain in this tree has glossary terms,
data products, OKRs, or critical data elements this scenario didn't create (via
`curate-business-glossary`, `manage-data-products`, `manage-okrs`, or
`manage-critical-data-elements` pointed at one of these domains, per `design.md` §7's non-goal
list), the domain `Delete` call may fail server-side until those business concepts are also
removed, check each domain's **Details** tab in the portal for other business concepts before
purging, especially `Corporate` and `Sales`, which this scenario's own worked example expects other
scenarios to build on top of.

## What rollback does **not** undo

- **Domain history.** Same as `curate-business-glossary/rollback.md`, Microsoft Learn does not
 document a separate audit trail for Unified Catalog object changes distinct from the general
 Microsoft Purview audit log.
- **The attribute *definitions* themselves.** This scenario's scripts only ever set/clear values on
 the domain object's `managedAttributes` array; they never touch the tenant's
 **Custom metadata (preview)** attribute-group/attribute definitions (`design.md` §7).
- **The target Data Map collection(s)** a data estate mapping referenced. This scenario never
 creates or deletes Data Map collections, only the Unified Catalog-side mapping record.
- **Links from data products, glossary terms, or critical data elements in other scenarios that
 point at one of these domains.** A deleted domain leaves those objects' `domain`/`domainIds`
 reference dangling; check the portal before purging a domain other scenarios build on.

## Verification after rollback

```powershell
./validate/Test-GovernanceDomainHierarchy.ps1 `
    -PurviewAccountEndpoint 'https://api.purview-service.microsoft.com' `
    -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
    -HierarchyDefinitionPath './deploy/hierarchy/corporate-sales-marketing-hierarchy.json'
```

After **Stage 1**, expect every domain's existence/content/attribute checks to still `[PASS]`
while the publish-status check reports `[WARN]` (DRAFT is a valid state, not a hard failure).
After **Stage 2**, expect every existence check to `[FAIL]`, confirming the tree is gone, not
merely unpublished.
