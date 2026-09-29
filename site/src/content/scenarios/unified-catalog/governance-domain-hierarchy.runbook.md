---
part: "runbook"
parent: "unified-catalog/governance-domain-hierarchy"
---
## Implementation steps

### Portal path (for a first manual walkthrough / to validate intent before scripting)

1. Sign in to the [Microsoft Purview portal](https://purview.microsoft.com) → **Unified Catalog** →
   **Catalog management** → **Governance domains** → **New Governance domain**.
2. Name: `Corporate`. Type: **Functional unit**. Leave **parent domain** blank. On **Custom
   attributes**, set `Data Classification Tier` = `Tier 1 - Enterprise-wide` (the attribute must
   already exist - see the prerequisites). **Create**.
3. **New Governance domain** again. Name: `Sales`. Type: **Line of business**. **Parent domain**:
   `Corporate`. Set the same attribute to `Tier 2 - Line of business`. **Create**. Repeat for
   `Marketing` (also parented to `Corporate`).
4. **New Governance domain** once more. Name: `Sales - EMEA`. Type: **Regulatory**. **Parent
   domain**: `Sales`. Set `Tier 3 - Regional/restricted`. Toggle domain **restricted** if your
   tenant exposes that control on this page. **Create**.
5. On each domain's **Data estate mappings** tab, use **Select a mapping** to associate the domain
   with its intended Data Map collection.
6. **Publish** each domain, parent before children (a child cannot be published usefully before
   its own concepts are visible, and Microsoft requires the domain itself published before any
   business concept within it can be published).

### Script path (idempotent, parameterized, dry-run capable)

```powershell
# 1. Dry run - reports every domain that would be created/updated, makes no mutating call
./deploy/New-GovernanceDomainHierarchy.ps1 `
    -PurviewAccountEndpoint 'https://api.purview-service.microsoft.com' `
    -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
    -HierarchyDefinitionPath './deploy/hierarchy/corporate-sales-marketing-hierarchy.json' -WhatIf

# 2. First real run - recommended to skip the data estate mapping until verified (Section 11)
./deploy/New-GovernanceDomainHierarchy.ps1 `
    -PurviewAccountEndpoint 'https://api.purview-service.microsoft.com' `
    -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
    -HierarchyDefinitionPath './deploy/hierarchy/corporate-sales-marketing-hierarchy.json' `
    -SkipDataEstateMapping

# 3. After confirming data estate mapping behavior in a pilot tenant (Section 11), re-run without
# -SkipDataEstateMapping to reconcile the mapping in too, then publish
./deploy/New-GovernanceDomainHierarchy.ps1 `
    -PurviewAccountEndpoint 'https://api.purview-service.microsoft.com' `
    -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
    -HierarchyDefinitionPath './deploy/hierarchy/corporate-sales-marketing-hierarchy.json' -Publish

# 4. Validate
./validate/Test-GovernanceDomainHierarchy.ps1 `
    -PurviewAccountEndpoint 'https://api.purview-service.microsoft.com' `
    -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
    -HierarchyDefinitionPath './deploy/hierarchy/corporate-sales-marketing-hierarchy.json'
```

The deploy script uses the Purview Unified Catalog REST API directly (`Invoke-RestMethod`) -
automation surface 4 per [Automation surface, section 1](/docs/automation-surface/#1-five-automation-surfaces-not-one-read-this-first); there is no PowerShell cmdlet module for
Unified Catalog domain authoring today.

## Configuration reference

| Object | Field | Source | Notes |
|---|---|---|---|
| Governance domain | `type` | `FunctionalUnit` \| `LineOfBusiness` \| `DataDomain` \| `Regulatory` \| `Project` | Descriptive only - no documented behavioral difference |
| Governance domain | `parentId` | Another domain's `id`, or omitted for a root domain | Up to **five levels of depth**, up to **200 domains**, tenant-wide - this script enforces the depth ceiling client-side (throws before calling the API) and only warns on the count ceiling, since server-side enforcement of either is unconfirmed (the design notes below) |
| Governance domain | `isRestricted` | boolean | Sent only when the definition file's node includes it; omitted otherwise (not cleared on existing domains this scenario doesn't explicitly set it for) |
| Governance domain | `managedAttributes[].name`/`.value` | Must match an attribute **definition** an admin already created, scoped to include Governance Domains | This scenario only sets values - see the prerequisites and the known limitations, the design notes |
| Governance domain | `domains[].relatedCollections[]` (this scenario's `dataEstateMapping` block) | Opt-in per node; omit to skip | **VERIFY** - undocumented field semantics, section 11, the design notes |
| Governance domain | `status` lifecycle | `DRAFT` → `PUBLISHED` → `EXPIRED` | Same lifecycle as *Curate a Business Glossary*; this scenario's `-Publish` walks the tree top-down |

Full request/response shapes: `deploy/New-GovernanceDomainHierarchy.ps1`'s inline comments and
`.NOTES` block cite the exact Microsoft Learn REST reference pages for every operation used.

## Operations and tuning

**Review-before-publish workflow:** same two-step `DRAFT` → `-Publish` discipline as
*Curate a Business Glossary* section 8 - a domain in `DRAFT` is visible only to Data Stewards and Governance
Domain Owners, giving a human review point before a domain (and anything inside it) becomes visible
tenant-wide.

**Growing the tree without re-touching siblings:** because idempotency matches on
`(name, parentId)` rather than name alone, adding one new child domain to the
definition file and re-running only creates that one domain - every existing sibling and ancestor
is matched, seeded from its live state, and left with the same net content (barring a deliberate
attribute-value or description edit in the file).

**Domain sprawl toward the 200-domain / 5-level ceiling:** this script warns once the tenant-wide
domain count (from its own full `Enumerate` pass) is at or above 200, and refuses (throws) before
creating any node past depth 5. Track domain count as an operational metric once multiple business
units start self-service authoring - the whole point of a hierarchy is to delegate authoring
without needing a flat, ungoverned domain-per-team sprawl; a domain nearing the ceiling is a signal
to consolidate via deeper nesting under an existing parent rather than adding new siblings.

**Attribute-definition drift:** this scenario assumes the attribute names in its definition file
are already defined by an admin. If an admin renames or expires an attribute definition after
this scenario's tree is deployed, the next deploy run's `managedAttributes` update will either fail
(a renamed attribute is a "not found" API error, not a script bug) or silently keep setting a value
for an expired attribute (Microsoft does not document expired-attribute write behavior). Re-run
`validate/Test-GovernanceDomainHierarchy.ps1` after any attribute-definition change in
**Custom metadata (preview)** to catch drift.

## Rollback and decommission

See the rollback runbook for the full staged procedure (unpublish → purge, deepest-first). Quick
reference: `./deploy/Remove-GovernanceDomainHierarchy.ps1 -Unpublish` reversibly unpublishes the
whole tree, children before parents; add `-Purge` to permanently delete it, also children before
parents - Microsoft's own guidance requires subdomains be removed before their parent.

## References

1. Create and manage business concept attributes (preview) - attribute groups, field types,
   scope, portal/admin-only definitions - <https://learn.microsoft.com/purview/unified-catalog-attributes-business-concept>
2. Custom metadata (preview) in Unified Catalog - <https://learn.microsoft.com/purview/unified-catalog-custom-metadata>
3. Disaster recovery for Unified Catalog (manual) - CDMC control templates - <https://learn.microsoft.com/purview/unified-catalog-disaster-recovery>
4. Learn about data governance billing (governed assets, what counts) - <https://learn.microsoft.com/purview/data-governance-billing>
5. Learn about Microsoft Purview billing models (PAYG, Azure subscription prerequisite) - <https://learn.microsoft.com/purview/purview-billing-models>
6. Create and manage governance domains - "Delete governance domains" (unpublish + delete
   subdomains first), "Configure data estate mappings", "Manage governance domains" (edit requires
   the governance domain owner role) - <https://learn.microsoft.com/purview/unified-catalog-governance-domains-create-manage>
7. Create and manage governance domains - "Create governance domains" (parent domain selection,
   200-domain/5-level ceiling, publish-domain-before-concepts requirement) - <https://learn.microsoft.com/purview/unified-catalog-governance-domains-create-manage#create-governance-domains>
8. Sample setup for data governance - Corporate/Sales worked example, "key points of federation" - <https://learn.microsoft.com/purview/data-governance-setup-sample>
9. Create and manage governance domains - "Configure data estate mappings" - <https://learn.microsoft.com/purview/unified-catalog-governance-domains-create-manage#manage-governance-domains>
10. Governance domains in Unified Catalog - domain types, 200-domain/5-level hierarchy limit - <https://learn.microsoft.com/purview/unified-catalog-governance-domains>
11. Purview Unified Catalog REST API - Business Domain operation group (Create/Update/Delete/Get/Enumerate) - <https://learn.microsoft.com/rest/api/purview/purview-unified-catalog/business-domain?view=rest-purview-purview-unified-catalog-2026-03-20-preview>
12. Unified Catalog API (Public Preview) overview - documented resource list (no Attributes
    resource), GA-only coverage, preview API versions - <https://learn.microsoft.com/rest/api/purview/unified-catalog-api-overview>
13. Data governance roles and permissions in Microsoft Purview - Governance Domain Creator/Owner,
    Data Steward - <https://learn.microsoft.com/purview/data-governance-roles-permissions>
14. Tutorial: Authenticate for APIs - service principal setup, Unified Catalog role assignment,
    client-credentials token flow - <https://learn.microsoft.com/purview/data-gov-api-rest-data-plane>
15. Microsoft identity platform and the OAuth 2.0 client credentials flow - <https://learn.microsoft.com/entra/identity-platform/v2-oauth2-client-creds-grant-flow>
16. Data governance billing frequently asked questions - unattached domains aren't charged - <https://learn.microsoft.com/purview/data-governance-billing-faq>

> Re-verify all links against current Microsoft Learn before a customer-facing engagement - this
> scenario targets Unified Catalog's **preview** REST API surface (`2026-03-20-preview`), which
> Microsoft explicitly documents as covering only GA Unified Catalog features and subject to
> change before general availability.