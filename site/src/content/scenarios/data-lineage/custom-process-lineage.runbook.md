---
part: "runbook"
parent: "data-lineage/custom-process-lineage"
---
## Implementation steps

### Portal path (for a first manual walkthrough / to validate intent before scripting)

1. Confirm both DataSet assets already exist and copy their exact **Qualified name** values from
   each asset's **Overview** page in the Purview portal - same manual-copy step
   *Close Gaps and Validate End-to-End Customer Data Lineage* (the implementation steps) step 2 documents, and the same open VERIFY
   (the known limitations below) about the exact `azure_sql_table` qualifiedName format.
2. Assign the automation identity's *human* counterpart (or yourself, for this walkthrough) the
   **Data Curator** role on the collection containing both assets: **Data Map** -> **Collections**
   -> select the collection -> **Role assignments** -> add under **Data curators**.
3. After running the script (below), open the upstream asset's **Lineage** tab in the Purview
   portal and confirm a new node - the Process entity, named "Nightly customer risk-scoring job" -
   now sits between `customerdb.dbo.Customers` and `analyticsdb.dbo.CustomerRiskSummary`, with the
   `runbookUrl` and `scheduleExpression` attributes visible when you select it.

### Script path (idempotent, parameterized, dry-run capable)

```powershell
# 1. Copy the upstream/downstream assets' real Qualified Name values from the portal into the
# definition file first - see deploy/lineage/customer-risk-summary-process-lineage.json.
# (The Process entity's own qualifiedName is authored by this scenario, not copied - see the known limitations.)

# 2. Deploy (dry run first - reports what already exists and what would be created)
./deploy/New-CustomProcessLineage.ps1 `
    -PurviewAccountEndpoint 'https://api.purview-service.microsoft.com' `
    -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
    -LineageDefinitionPath './deploy/lineage/customer-risk-summary-process-lineage.json' `
    -WhatIf

# 3. Deploy for real - creates the custom type (if missing), upserts the Process entity, and
# creates either or both relationships if missing
./deploy/New-CustomProcessLineage.ps1 `
    -PurviewAccountEndpoint 'https://api.purview-service.microsoft.com' `
    -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
    -LineageDefinitionPath './deploy/lineage/customer-risk-summary-process-lineage.json'

# 4. Validate - confirms the full DataSet -> Process -> DataSet chain is connected
./validate/Test-ProcessLineage.ps1 `
    -PurviewAccountEndpoint 'https://api.purview-service.microsoft.com' `
    -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
    -LineageDefinitionPath './deploy/lineage/customer-risk-summary-process-lineage.json'
```

Both scripts use the **Microsoft Purview Data Map / Atlas v2 REST API** - automation surface 4 per
[Automation surface, section 1](/docs/automation-surface/#1-five-automation-surfaces-not-one-read-this-first) - the same surface *Close Gaps and Validate End-to-End Customer Data Lineage* uses, extended
here to the **Type** and (for the first time in this library) **Entity** operation groups. Token
acquisition follows the same client-credentials pattern already used by this library's other
surface-4 scripts.

## Configuration reference

| Setting | Value this scenario uses | Notes |
|---|---|---|
| Custom Process type name | `PurviewScenarioLibraryEtlProcess` | `superTypes: ["Process"]` - directly confirmed shape from Microsoft's "Create a Custom Process Type" worked example |
| Custom type attributes | `runbookUrl` (string), `scheduleExpression` (string), both `cardinality: SINGLE`, `isOptional: true` | Confirmed `AtlasAttributeDef` shape from Microsoft's own `Type - Bulk Create` worked example (`azure_sql_server_example`) |
| Process entity qualifiedName | `custom-lineage.nightly-customer-risk-scoring-job` | Authored by this scenario, not copied from the portal - the Process entity doesn't pre-exist as a scanned asset, so there is no format to match. Deliberately dot-namespaced, following the same convention as Microsoft's own worked example (`test_lineage.HiveQuery1`) |
| Relationship types | `dataset_process_inputs` (upstream DataSet -> Process), `process_dataset_outputs` (Process -> downstream DataSet) | Both directly confirmed via Microsoft's own worked Example 1 |
| Relationship end typeName for the Process node | Literal `Process` | Matches Microsoft's own worked example exactly - see the design notes. Not independently re-confirmed for a *custom* Process subtype specifically - section 11 |
| Column-level detail | `columnMapping` **on the Process entity's own attributes** (JSON-encoded string: `[{"DatasetMapping":{...},"ColumnMapping":[...]}]`) | Matches Microsoft's own worked DataSet -> Process -> DataSet example exactly - a genuinely different placement from the sibling scenario's direct-edge case, where `columnMapping` sits on the relationship instead |
| Process entity idempotency | Entity - Bulk Create Or Update's documented upsert-by-qualifiedName | No separate existence check needed - stronger grounding than the relationship/type idempotency mechanisms below |
| Type definition idempotency | `Type - Get Entity Def By Name` existence check before `Type - Bulk Create` | That operation's reference page warns "avoid recreating existing types" |
| Relationship idempotency | Single depth-2 `Lineage - Get By Unique Attribute` existence check (from the upstream asset) before either `Relationship - Create` POST | See the design notes |
| Deploy role | **Data Curator** | Catalog Data plane write access |
| Validate role | **Data Reader** | Catalog Data plane read-only access |
| API version pinned by both scripts | `2023-09-01` | Confirmed current via direct fetch of Microsoft's own REST reference pages for Entity - Bulk Create Or Update, Type - Bulk Create, Type - Get Entity Def By Name, Relationship - Create, and Lineage - Get By Unique Attribute |
| `-PurviewAccountEndpoint` accepted values | `https://api.purview-service.microsoft.com` (new portal) or `https://<account>.purview.azure.com` (classic portal) | Same dual-endpoint confirmation as the sibling scenario |

Full REST-body grounding: `deploy/New-CustomProcessLineage.ps1`, `deploy/
Remove-CustomProcessLineage.ps1`, and `validate/Test-ProcessLineage.ps1` inline comments and their
`.NOTES` blocks cite the exact Microsoft Learn reference pages.

## Operations and tuning

**KPIs to watch (first 30 days):** same validation-pass/fail-trend pattern
*Close Gaps and Validate End-to-End Customer Data Lineage* (operations and tuning) already establishes - wire
`validate/Test-ProcessLineage.ps1` into the same recurring scheduled check. This scenario adds one
additional signal worth tracking: **Process entity attribute drift** - if `runbookUrl` starts
returning stale links (404s, or pointing at a decommissioned wiki), that's a maintenance signal
distinct from a connectivity failure; this scenario's validate script does not check the URL is
live (that would require a network call outside Purview's own data plane - explicitly out of scope,
the design notes), only that the attribute is non-empty.

**Alert routing:** no Purview-native alert for a broken or drifted lineage relationship - identical
situation to the sibling scenario. The recurring `validate/` run **is** the detection mechanism;
route its non-zero exit code the same way *Close Gaps and Validate End-to-End Customer Data Lineage* (operations and tuning) recommends.

**Incident-response runbook (validation reports a gap):** follow
*Close Gaps and Validate End-to-End Customer Data Lineage* (operations and tuning)'s runbook for the "asset re-created with a new GUID"
and "relationship deleted" cases - both apply identically here, just with the Process entity as an
additional node that can independently go missing or be re-created with a new GUID. One
scenario-specific addition: if **only** the Process entity check fails (both DataSet assets still
present and, if the sibling scenario is also deployed, still connected via the direct edge), the
transform job's context is missing but the underlying data-flow claim isn't - a lower-severity
finding than a full connectivity gap, worth triaging separately.

**Review cadence:** re-run `validate/Test-ProcessLineage.ps1` on the same cadence as the sibling
scenario's validate script - at minimum monthly, and after any change to either DataSet asset or
the transform job's ownership/schedule (which should also trigger an update to the Process entity's
`runbookUrl`/`scheduleExpression` attributes via a re-run of the deploy script).

## Rollback and decommission

See the rollback runbook for the full procedure. Quick reference:
`./deploy/Remove-CustomProcessLineage.ps1` deletes both lineage relationships and the Process
entity; the upstream/downstream assets and the custom Process type definition are left untouched.

## References

1. Data lineage in classic Data Catalog (overview, use cases, granularity) - <https://learn.microsoft.com/purview/data-gov-classic-lineage>
2. Data lineage user guide for classic Data Catalog (supported systems table, known limitations, manual lineage) - <https://learn.microsoft.com/purview/data-gov-classic-lineage-user-guide>
3. Data governance and security baselines with Microsoft Purview - "Data visibility baseline" (Recommendation: "Enable automated lineage where available and close gaps manually where required") - <https://learn.microsoft.com/azure/cloud-adoption-framework/data/governance-security-baselines-purview-data-estate-unify-data-platform>
4. Type definitions and how to create custom types (asset/type concepts, `Referenceable`/`Asset`/`DataSet`/`Process` base types) - <https://learn.microsoft.com/purview/data-gov-api-custom-types>
5. Tutorial: Authenticate for Microsoft Purview data-plane APIs (service principal setup, Data Curator/Data Reader roles for the Catalog Data plane, token acquisition) - <https://learn.microsoft.com/purview/data-gov-api-rest-data-plane>
6. Create and get lineage relationships using the REST API - Example 1 (DataSet -> Process -> DataSet: create a Process entity via Entity Bulk Create, then `dataset_process_inputs`/`process_dataset_outputs` relationships) and "Create New Custom Types" (custom Process/DataSet type bodies) - <https://learn.microsoft.com/purview/data-gov-api-create-lineage-relationships>
7. Custom classifications in Data Map - confirms "data curator or data source administrator permission on a domain or collection... at any collection level" for the closely related custom-classification-creation action - <https://learn.microsoft.com/purview/data-map-classification-custom>
8. Data lineage user guide for classic Data Catalog - manual lineage entries and portal Lineage tab - <https://learn.microsoft.com/purview/data-gov-classic-lineage-user-guide#manual-lineage>
9. Manage domains and collections in Microsoft Purview Data Map - Data Curator/Data Reader/Collection Administrator role definitions - <https://learn.microsoft.com/purview/data-map-domains-collections-manage#add-roles-and-restrict-access>
10. Type - Bulk Create REST reference (API version 2023-09-01; "Please avoid recreating existing types"; `azure_sql_server_example` worked `AtlasAttributeDef` shape) - <https://learn.microsoft.com/rest/api/purview/datamapdataplane/type/bulk-create>
11. GraphQL API with Microsoft Purview (preview) - confirms both `api.purview-service.microsoft.com` and `{account}.purview.azure.com` as valid endpoint hosts for the `/datamap/api/...` path family - <https://learn.microsoft.com/purview/data-gov-api-graphql>
12. Entity - Bulk Create Or Update REST reference (API version 2023-09-01; confirms upsert-by-qualifiedName semantics directly in its own description) - <https://learn.microsoft.com/rest/api/purview/datamapdataplane/entity/bulk-create-or-update>
13. Type - Get Entity Def By Name REST reference (API version 2023-09-01) - <https://learn.microsoft.com/rest/api/purview/datamapdataplane/type/get-entity-def-by-name>
14. Relationship - Create REST reference (API version 2023-09-01) - <https://learn.microsoft.com/rest/api/purview/datamapdataplane/relationship/create>
15. Relationship - Delete REST reference (API version 2023-09-01) - <https://learn.microsoft.com/rest/api/purview/datamapdataplane/relationship/delete>
16. Lineage - Get By Unique Attribute REST reference (API version 2023-09-01) - <https://learn.microsoft.com/rest/api/purview/datamapdataplane/lineage/get-by-unique-attribute>
17. Entity.DeleteByUniqueAttribute method (.NET SDK; confirms `DELETE /datamap/api/atlas/v2/entity/uniqueAttribute/type/{typeName}?attr:qualifiedName={qn}` - this build's grounding pass did not independently fetch a canonical REST-reference page at the same depth as the other operations cited here - see the rollback runbook and the removal script's `.NOTES`) - <https://learn.microsoft.com/dotnet/api/azure.analytics.purview.datamap.entity.deletebyuniqueattribute>
18. Type - Delete REST reference (API version 2023-09-01; confirms `DELETE {endpoint}/datamap/api/atlas/v2/types/typedef/name/{name}` and 204 No Content on success - closed 2026-09-28 via direct Microsoft Learn MCP fetch; in-use-type deletion behavior still not documented, see the rollback runbook) - <https://learn.microsoft.com/rest/api/purview/datamapdataplane/type/delete>
19. Manage assets with metamodel - prerequisites confirm "Data Curator role on the collection where the data asset is housed" is sufficient for "Create and modify asset types" (no broader/root-level grant required) - <https://learn.microsoft.com/purview/legacy/how-to-metamodel#prerequisites>

> Re-verify all links and the VERIFY items in the known limitations against current Microsoft Learn before a
> customer-facing deployment - Microsoft's own Data Map REST surface is explicitly called out
> elsewhere in this library (*Scan Azure SQL Database and Classify Sensitive Columns* (the known limitations)) as
> evolving.