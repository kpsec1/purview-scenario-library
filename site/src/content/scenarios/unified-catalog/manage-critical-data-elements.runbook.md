---
part: "runbook"
parent: "unified-catalog/manage-critical-data-elements"
---
## Implementation steps

### Portal path (for a first manual walkthrough / to validate intent before scripting)

1. Sign in to the [Microsoft Purview portal](https://purview.microsoft.com) → **Unified Catalog**
   → **Catalog management** → **Governance domains** → select `Customer Experience` → **Details**
   tab → **Critical data elements** card → **View all** → **New critical data element**.
2. **Basic details**: Name `Customer ID`, description as in the definition file, owner your Data
   Steward account, expected data type **Text**. **Next** → (no required custom attributes in
   this scenario) → **Create**.
3. On the new element's details page, select **+ Add column** → search for `customerdb.dbo.Customers`
   → select the `CustomerID` column → **Add**.
4. Note the **Associated data products** section below the columns list - it populates
   automatically once a mapped column belongs to an asset already linked to a data product.
5. Select **Status** → **Published** (only after confirming the governance domain itself shows as
   published).

### Script path (idempotent, parameterized, dry-run capable)

```powershell
# 1. Dry run - reports every change, makes none (still performs read-only lookups against the
#    live tenant, including the Data Map column-resolution call, to accurately report
#    create-vs-update - see Section 11)
./deploy/New-CriticalDataElement.ps1 `
    -PurviewAccountEndpoint 'https://api.purview-service.microsoft.com' `
    -DataMapEndpoint 'https://api.purview-service.microsoft.com' `
    -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
    -DefinitionPath './deploy/config/customer-id-cde.sample.json' -WhatIf

# 2. Deploy in DRAFT status (default) for review
./deploy/New-CriticalDataElement.ps1 `
    -PurviewAccountEndpoint 'https://api.purview-service.microsoft.com' `
    -DataMapEndpoint 'https://api.purview-service.microsoft.com' `
    -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
    -DefinitionPath './deploy/config/customer-id-cde.sample.json'

# 3. Publish once reviewed
./deploy/New-CriticalDataElement.ps1 `
    -PurviewAccountEndpoint 'https://api.purview-service.microsoft.com' `
    -DataMapEndpoint 'https://api.purview-service.microsoft.com' `
    -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
    -DefinitionPath './deploy/config/customer-id-cde.sample.json' -Publish

# 4. Validate, including the associated-data-products cross-check
./validate/Test-CriticalDataElement.ps1 `
    -PurviewAccountEndpoint 'https://api.purview-service.microsoft.com' `
    -DataMapEndpoint 'https://api.purview-service.microsoft.com' `
    -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
    -DefinitionPath './deploy/config/customer-id-cde.sample.json' -DataProductName 'Customer Master Data'
```

Before step 1, replace `columns[].dataMapAssetId` in the definition file with the real Data Map
asset GUID for `customerdb.dbo.Customers` - the same GUID *Manage a Data Product*' own definition
file uses, copied from the asset's **Overview** page in the portal after
*Scan Azure SQL Database and Classify Sensitive Columns* has scanned it at least once. Unlike
*Manage a Data Product*, you do **not** need to separately find a column-level GUID - the script
resolves it from `columnName`. The script refuses to run against the
placeholder nil GUID.

## Configuration reference

| Object | Field | Source | Notes |
|---|---|---|---|
| Critical data element | `id` | Client-generated GUID | Same identity model as glossary terms and data products - the design notes |
| Critical data element | `dataType` | `TEXT` (this scenario) - full enum: `TEXT`, `NUMBER`, `DATETIME`, `BOOLEAN` | Matches the portal's own four expected-data-type options exactly (unlike data products' 14-vs-11 type mismatch) |
| Critical data element | `status` | `DRAFT` → `PUBLISHED` → `EXPIRED` | No documented access-policy publish gate (contrast with data products - the prerequisites) |
| Critical data element | `contacts.owner[].id` | Entra object ID | Resolved from the definition file's UPN, same as *Manage a Data Product* |
| Data column (Unified Catalog) | `id` | Server-assigned GUID from **Data Columns - Ingest**, distinct from both the Data Map column's own GUID and the Data Map table's GUID | Critical Data Elements - Create Relationship links against *this* id |
| Data column (Unified Catalog) | `source.assetId` / `source.columnId` | The Data Map table GUID / the Data Map column GUID this scenario resolves | The only fields **Data Columns - Ingest** requires |
| Relationship | `entityType` | `CRITICALDATACOLUMN` | Confirmed 2026-09-27 against the `EntityCategory` enum on the Create/List/Delete Relationship reference pages - matches every worked example |
| Relationship | `relationshipType` | `Related` | The only value this scenario's script sends |

Full request/response shapes: `deploy/New-CriticalDataElement.ps1`'s inline comments and `.NOTES`
block cite the exact Microsoft Learn REST reference pages for every operation used.

## Operations and tuning

**Review-before-publish workflow:** identical discipline to *Manage a Data Product* (operations and tuning) -
this script's default (`DRAFT`, no `-Publish`) gives a human review point. Confirm the governance
domain itself is published before attempting `-Publish` on the element - Microsoft's docs state
this as a prerequisite for CDEs the same way they state it for glossary terms, even though (unlike data products) there is no separate access-policy gate
to configure first.

**Re-running after an edit:** add a column, adjust the description, or add a second source system
mapping the same logical concept, then re-run `New-CriticalDataElement.ps1`. The create/update
path always reconciles the element's own fields **to the definition file's current content** -
same caveat as *Manage a Data Product* (operations and tuning). Column mappings are purely additive on
re-run: removing a `columns[]` entry from the file does **not** unmap it (this script never
deletes a relationship - see the rollback runbook for the explicit unmapping path).

**"Associated data products" refresh lag:** Microsoft's own docs state this rollup "only refreshes
when you add or remove columns" - so a data product created or modified
*after* this scenario's last column-mapping run may not yet be reflected. Re-running
`New-CriticalDataElement.ps1` against an unchanged definition file is a no-op for the columns
themselves (idempotent - nothing to add or remove) and will **not** force a rollup refresh; if a
downstream consumer needs a live view, query the DATAPRODUCT relationship directly (as
`validate/Test-CriticalDataElement.ps1` does) rather than relying on cached portal state.

**Run validate after every deploy, not just on demand:** `New-CriticalDataElement.ps1` treats a
column that fails to resolve (wrong `columnName` casing, a Data Map asset that hasn't finished
scanning) as a non-fatal `Write-Warning`-and-skip, by design - one bad entry in a multi-column
`columns[]` array shouldn't abort mapping the rest. That design means the deploy script's own
console output is **not** a reliable signal that every configured column actually got mapped.
`validate/Test-CriticalDataElement.ps1` is the actual safety net (it hard-`[FAIL]`s an unresolved
column) - treat a deploy run as incomplete until validate has been run against it, especially in
unattended/CI-style execution where nobody is watching the deploy script's console output live.

**Compliance-evidence caution:** this feature is Microsoft-labeled preview - a CDE-based
regulated-data inventory is a genuinely strong internal governance narrative, but do not cite
it as the sole system of record in a formal regulatory audit response until the feature reaches
GA; preview features carry no Microsoft SLA or support commitment.

**Governed-asset billing awareness:** because this scenario typically maps a column belonging to
an asset another scenario (*Manage a Data Product*) already governs, it adds no incremental cost
in the common case - but the first time a *new*, previously-ungoverned asset gets its first column
mapped to a CDE, that asset becomes a governed asset and starts accruing the per-asset/day PAYG
meter. Track new CDE column mappings against previously-unscanned or previously-ungoverned
sources as a cost event, not just a governance event.

## Rollback and decommission

See the rollback runbook for the full staged procedure (unpublish → unmap columns → purge). Quick
reference: `./deploy/Remove-CriticalDataElement.ps1` unpublishes the critical data element
(reversible); add `-RemoveLinks` to also remove its column mappings; add `-Purge` to permanently
delete the critical data element itself. The underlying Unified Catalog data column wrapper
objects are never deleted by this scenario - the Data Columns operation group has no Delete
operation as of the API version this scenario targets.

## References

1. Critical data elements (preview) - concept, prerequisites, Add columns flow, Associated data
   products rollup, delete/edit procedures - <https://learn.microsoft.com/purview/unified-catalog-critical-data-elements>
2. Data Quality for Critical Data Elements in Unified Catalog (preview) - CDE-level quality
   scoring - <https://learn.microsoft.com/purview/unified-catalog-data-quality-critical-data-elements>
3. Learn about Microsoft Purview Unified Catalog - critical data elements feature overview -
   <https://learn.microsoft.com/purview/unified-catalog>
4. Data governance roles and permissions in Microsoft Purview - Data Steward and Data Product
   Owner roles - <https://learn.microsoft.com/purview/data-governance-roles-permissions>
5. Governance domains in Unified Catalog - critical data elements as a governance-domain business
   concept - <https://learn.microsoft.com/purview/unified-catalog-governance-domains>
6. Critical data elements (preview) - "Customer ID" CustID/CID mapping example, blueprint framing
   - <https://learn.microsoft.com/purview/unified-catalog-critical-data-elements>
7. Learn about data governance billing - Unified Catalog billing, governed assets defined via data
   products or critical data elements - <https://learn.microsoft.com/purview/data-governance-billing>
8. Learn about data governance billing - per-asset-per-day meter - <https://learn.microsoft.com/purview/data-governance-billing>
9. Data governance billing frequently asked questions - data-product/CDE dedup, confirmed verbatim
   - <https://learn.microsoft.com/purview/data-governance-billing-faq>
10. Purview Unified Catalog REST API - Critical Data Elements operation group (Count/Create/Create
    Relationship/Delete/Delete Relationship/Get/Get Facets/List/List Relationships/Query/Update) -
    <https://learn.microsoft.com/rest/api/purview/purview-unified-catalog/critical-data-elements?view=rest-purview-purview-unified-catalog-2026-03-20-preview>
11. Purview Unified Catalog REST API - Data Columns operation group (Add Related Entity/Delete
    Related/Get/Ingest/List Related Entities/Query) -
    <https://learn.microsoft.com/rest/api/purview/purview-unified-catalog/data-columns?view=rest-purview-purview-unified-catalog-2026-03-20-preview>
12. Unified Catalog API (Public Preview) overview - release notes confirming Data Columns APIs and
    Critical Data Elements Count added in `2026-03-20-preview` -
    <https://learn.microsoft.com/rest/api/purview/unified-catalog-api-overview>
13. Search for data assets - governed asset Governance tab, "Critical data elements associated
    with columns in the asset" - <https://learn.microsoft.com/purview/unified-catalog-data-assets-search>
14. Type definitions and how to create custom types - `azure_sql_table`'s `columns`
    relationshipAttributeDefs (`relationshipTypeName: azure_sql_table_columns`), confirmed via
    Microsoft's own worked example for this exact entity type -
    <https://learn.microsoft.com/purview/data-gov-api-custom-types>
15. Entity - Get (Data Map/Atlas REST API, `GET /datamap/api/atlas/v2/entity/guid/{guid}`) -
    <https://learn.microsoft.com/rest/api/purview/datamapdataplane/entity/get?view=rest-purview-datamapdataplane-2023-09-01>
16. Tutorial: Authenticate for APIs - service principal setup, Unified Catalog role assignment,
    client-credentials token flow - <https://learn.microsoft.com/purview/data-gov-api-rest-data-plane>
17. Get a user (Microsoft Graph) - `User.Read.All` application permission -
    <https://learn.microsoft.com/graph/api/user-get>

> Re-verify all links against current Microsoft Learn before a customer-facing engagement - this
> scenario targets Unified Catalog's **preview** REST API surface (`2026-03-20-preview`), whose
> `Data Columns` operation group and the `Critical Data Elements` `Count` operation were only
> added in this exact version, and the underlying critical-data-elements
> *feature itself* (not just its API) is separately Microsoft-labeled preview.