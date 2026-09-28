---
part: "runbook"
parent: "unified-catalog/manage-data-products"
---
## Implementation steps

### Portal path (for a first manual walkthrough / to validate intent before scripting)

1. Sign in to the [Microsoft Purview portal](https://purview.microsoft.com) → **Unified Catalog**
   → **Catalog management** → **Data products** → **New data product**.
2. **Basic details**: Name `Customer Master Data`, Type **Master and reference data**, Audience
   `Data Analyst`/`Business Analyst`/`Data Engineer`, Owner your Data Product Owner account.
   **Next**.
3. **Business details**: Governance domain `Customer Experience` (the same domain
   *Curate a Business Glossary* created), Use case as in the definition file. **Next** → **Create**.
4. On the new data product's details page, **Add data assets** → search for
   `customerdb.dbo.Customers` → select it → **Add**.
5. Under **Glossary terms**, select **+** → search for `Customer` and `Customer ID` → **Add**.
6. Select **Manage policies** → configure **Permitted access** purposes and **Access request
   approvers** (defaults to the data product owner).
7. Select **Publish** on the data product's details page.

### Script path (idempotent, parameterized, dry-run capable)

```powershell
# 1. Dry run - reports every change, makes none (still performs read-only lookups against the
# live tenant to accurately report create-vs-update - see this page Section 11)
./deploy/New-DataProduct.ps1 `
    -PurviewAccountEndpoint 'https://api.purview-service.microsoft.com' `
    -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
    -DefinitionPath './deploy/config/customer-master-data-product.sample.json' -WhatIf

# 2. Deploy in DRAFT status (default) for review
./deploy/New-DataProduct.ps1 `
    -PurviewAccountEndpoint 'https://api.purview-service.microsoft.com' `
    -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
    -DefinitionPath './deploy/config/customer-master-data-product.sample.json'

# 3. Configure the data product access policy in the portal (Section 3 - not scriptable), then:
./deploy/New-DataProduct.ps1 `
    -PurviewAccountEndpoint 'https://api.purview-service.microsoft.com' `
    -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
    -DefinitionPath './deploy/config/customer-master-data-product.sample.json' -Publish

# 4. Validate
./validate/Test-DataProduct.ps1 `
    -PurviewAccountEndpoint 'https://api.purview-service.microsoft.com' `
    -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
    -DefinitionPath './deploy/config/customer-master-data-product.sample.json'
```

Before step 1, replace `dataAsset.dataMapAssetId` in the definition file with the real Data Map
asset GUID for `customerdb.dbo.Customers` - copy it from the asset's **Overview** page in the
portal after *Scan Azure SQL Database and Classify Sensitive Columns* has scanned it at least once. The script refuses to run against the placeholder nil GUID.

## Configuration reference

| Object | Field | Source | Notes |
|---|---|---|---|
| Data product | `id` | Client-generated GUID | Same identity model as glossary terms - see the design notes |
| Data product | `type` | `Master` (this scenario) - full enum: `Master`, `Reference`, `Analytical`, `AI`, `MasterDataAndReferenceData`, `BusinessSystemOrApplication`, `ModelTypes`, `DashboardsOrReports`, `Operational`, `MLAITrainingDataSet`, `MLAITestingDataSet`, `TransactionalDataset`, `AnalyticsModel`, `SemanticModel` | The REST enum's 14 values don't map one-to-one onto the portal's 11 documented type labels - e.g. the portal shows "Master and reference data" as one option; the REST enum has both a standalone `Master` and a separate `MasterDataAndReferenceData`. This scenario uses `Master` for the customer-identity narrative; confirm the portal-vs-REST label mapping in a pilot tenant before presenting type choices to a non-technical curator |
| Data product | `status` | `DRAFT` → `PUBLISHED` | Publish additionally requires an access policy - the prerequisites, the design notes |
| Data product | `contacts.owner[].id` | Entra object ID | Resolved from the definition file's UPN, same as *Curate a Business Glossary* |
| Data asset (Unified Catalog) | `id` | Server-assigned GUID, **distinct** from the Data Map asset's own GUID | the design notes - Create Relationship links against *this* id |
| Data asset (Unified Catalog) | `source.assetId` | The Data Map asset's GUID | The only field this scenario sets on create; type/schema/classifications are server-inferred from Data Map |
| Relationship | `entityType` | `DATAASSET` \| `TERM` | This scenario's script links only these two entity types - the design notes lists the others (`CRITICALDATAELEMENT`, `OBJECTIVE`, etc.) as non-goals |
| Relationship | `relationshipType` | `Related` | The only value this scenario's script sends |

Full request/response shapes: `deploy/New-DataProduct.ps1`'s inline comments and `.NOTES` block
cite the exact Microsoft Learn REST reference pages for every operation used.

## Operations and tuning

**Review-before-publish workflow:** identical discipline to *Curate a Business Glossary* (operations and tuning) - this script's default (`DRAFT`, no `-Publish`) gives a human review point before the product
becomes requestable. Unlike a glossary term, though, a data product also needs its **access
policy** configured before `-Publish` will succeed at all - build that portal step into the
same review checklist, not as an afterthought discovered only when the publish call fails.

**Re-running after an edit:** change the definition file (add a term, adjust the use case, update
frequency) and re-run `New-DataProduct.ps1`. Like *Curate a Business Glossary*, the create/update
path always reconciles the data product **to the definition file's current content**, not a merge
- a portal-made edit not reflected in the file will be overwritten on the next deploy run. The
narrower `-Publish`-only status transition does not have this problem.

**Asset-count and quality-score drift:** the data product's `additionalProperties.assetCount` (this
scenario's `validate` script reports it as an informational KPI) and its aggregate
`dataQualityScore` both change independently of this scenario's own runs - a
portal user adding another asset, or *Configure Rules and Review Scorecards for a Governed Data Asset*'s scan
schedule producing a new score. Track both as operational metrics once the product portfolio grows
past what a human can eyeball weekly.

**Access-request backlog:** every access request against this data product is queued for the
approvers configured in its access policy - an unattended approver queue
defeats the "self-service" value proposition this scenario is built around. This is portal-only
operational hygiene, not something this scenario's scripts monitor.

## Rollback and decommission

See the rollback runbook for the full staged procedure (unpublish → unlink → purge). Quick reference:
`./deploy/Remove-DataProduct.ps1` unpublishes the data product (reversible); add `-RemoveLinks` to
also remove its asset/term relationships; add `-Purge` to permanently delete the data product
itself.

## References

1. Create and manage data products - creation flow, data product types, Publish prerequisites (assets + access policy) - <https://learn.microsoft.com/purview/unified-catalog-data-products-create-manage>
2. Master data management in Microsoft Purview - the register/scan → create product → link term → curate flow this scenario automates - <https://learn.microsoft.com/purview/data-governance-master-data-management>
3. Learn about Microsoft Purview Unified Catalog - data products feature overview, scalable-governance rationale - <https://learn.microsoft.com/purview/unified-catalog>
4. Manage data product access policies - Manage policies flow, approval tiers, request statuses - <https://learn.microsoft.com/purview/unified-catalog-data-product-access-policies>
5. Create and manage glossary terms - Link terms to data products, assets, and critical data elements (preview) - <https://learn.microsoft.com/purview/unified-catalog-glossary-terms-create-manage#link-terms-to-data-products-assets-and-critical-data-elements-preview>
6. Data governance roles and permissions in Microsoft Purview - Data Product Owner role - <https://learn.microsoft.com/purview/data-governance-roles-permissions>
7. Learn about data governance billing - governed assets, per-asset-per-day meter - <https://learn.microsoft.com/purview/data-governance-billing>
8. Data governance billing frequently asked questions - unattached domains/data products aren't charged, billing starts on asset attach - <https://learn.microsoft.com/purview/data-governance-billing-faq>
9. Purview Unified Catalog REST API - Data Assets operation group (Create/Update/Delete By Id/Get By Id/List/Query/Create Relationship/List Relationships/Delete Relationship) - <https://learn.microsoft.com/rest/api/purview/purview-unified-catalog/data-assets?view=rest-purview-purview-unified-catalog-2026-03-20-preview>
10. Data products in Unified Catalog - scalable data governance rationale (one request instead of many) - <https://learn.microsoft.com/purview/unified-catalog-data-products>
11. Purview Unified Catalog REST API - Data Products operation group (Create/Update/Delete/Get/List/Query/Create Relationship/List Relationships/Delete Relationship/Count/Get Facets) - <https://learn.microsoft.com/rest/api/purview/purview-unified-catalog/data-products?view=rest-purview-purview-unified-catalog-2026-03-20-preview>
12. Search for data products in Unified Catalog - data product details page, data asset details page's "other data products" list - <https://learn.microsoft.com/purview/unified-catalog-data-products-search>
13. Search for data assets - governed asset Governance tab (data products / terms / CDEs / quality score) - <https://learn.microsoft.com/purview/unified-catalog-data-assets-search>
14. Purview Unified Catalog REST API - Policies operation group (the RBAC authorization-policy engine, distinct from the portal's data product access policy feature - the design notes) - <https://learn.microsoft.com/rest/api/purview/purview-unified-catalog/policies?view=rest-purview-purview-unified-catalog-2026-03-20-preview>
15. Unified Catalog API (Public Preview) overview - scope, GA-only coverage, preview API versions, Swagger specification links - <https://learn.microsoft.com/rest/api/purview/unified-catalog-api-overview>
16. Tutorial: Authenticate for APIs - service principal setup, Unified Catalog role assignment, client-credentials token flow - <https://learn.microsoft.com/purview/data-gov-api-rest-data-plane>
17. Get a user (Microsoft Graph) - `User.Read.All` application permission - <https://learn.microsoft.com/graph/api/user-get>
18. Microsoft identity platform and the OAuth 2.0 client credentials flow - v2.0 token endpoint, `scope=.default` - <https://learn.microsoft.com/entra/identity-platform/v2-oauth2-client-creds-grant-flow>
19. Purview Unified Catalog REST API - Critical Data Elements operation group (Create/Update/Delete By Id/Get By Id/List/Query/Create Relationship/List Relationships/Delete Relationship) - <https://learn.microsoft.com/rest/api/purview/purview-unified-catalog/critical-data-elements?view=rest-purview-purview-unified-catalog-2026-03-20-preview>

> Re-verify all links against current Microsoft Learn before a customer-facing engagement - this
> scenario targets Unified Catalog's **preview** REST API surface (`2026-03-20-preview`), whose
> `Data Assets`/`Data Columns` operation groups were only added in this exact version
> and are therefore among the least-tenured of any REST surface this library
> depends on.