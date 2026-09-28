---
part: "runbook"
parent: "data-lineage/end-to-end-lineage-validation"
---
## Implementation steps

### Portal path (for a first manual walkthrough / to validate intent before scripting)

1. Confirm both assets already exist: **Data Map** → the source registered and scanned (for
   `customerdb.dbo.Customers`, this is *Scan Azure SQL Database and Classify Sensitive Columns*'s own
   output); repeat the same scan pattern against the analytics database for
   `analyticsdb.dbo.CustomerRiskSummary`.
2. Open each asset's **Overview** page in the Purview portal and copy its exact **Qualified name**
   - this build's grounding pass did not independently confirm the precise qualifiedName string
   format Purview assigns to an `azure_sql_table` asset, so this scenario does not construct or
   guess it; copy it directly from the portal (or resolve it via the Data Map GraphQL/search API)
   into the definition file.
3. To create a lineage link manually first (to see the intended result before scripting it): open
   the upstream asset's **Lineage** tab → look for a manual-lineage option, or use the portal's
   documented manual-lineage entry flow. This scenario's script path (below) is
   the repeatable, code-reviewable equivalent.
4. Assign the automation identity's *human* counterpart (or yourself, for this walkthrough) the
   **Data Curator** role on the collection containing both assets: **Data Map** → **Collections** →
   select the collection → **Role assignments** → add under **Data curators**.
5. After creating the link (via script, below), open the upstream asset's **Lineage** tab in the
   portal and confirm the downstream asset now appears, connected by an edge, with the column-level
   mapping visible when you select the edge.

### Script path (idempotent, parameterized, dry-run capable)

```powershell
# 1. Copy the assets' real Qualified Name values from the portal into the definition file first -
#    see deploy/lineage/customer-risk-summary-lineage.json and README.md Section 11.

# 2. Deploy (dry run first - reports which links already exist and which would be created)
./deploy/New-CustomLineageRelationship.ps1 `
    -PurviewAccountEndpoint 'https://api.purview-service.microsoft.com' `
    -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
    -LineageDefinitionPath './deploy/lineage/customer-risk-summary-lineage.json' `
    -WhatIf

# 3. Deploy for real - creates any missing custom lineage relationships, skips ones that already exist
./deploy/New-CustomLineageRelationship.ps1 `
    -PurviewAccountEndpoint 'https://api.purview-service.microsoft.com' `
    -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
    -LineageDefinitionPath './deploy/lineage/customer-risk-summary-lineage.json'

# 4. Validate - proves the full chain from the origin asset is connected end-to-end
./validate/Test-EndToEndLineage.ps1 `
    -PurviewAccountEndpoint 'https://api.purview-service.microsoft.com' `
    -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
    -LineageDefinitionPath './deploy/lineage/customer-risk-summary-lineage.json'
```

Both scripts use the **Microsoft Purview Data Map / Atlas v2 REST API** - automation surface 4 per
[Automation surface, section 1](/docs/automation-surface/#1-five-automation-surfaces-not-one-read-this-first) - because entity/relationship/lineage objects have no Security &
Compliance PowerShell or Graph equivalent. Token acquisition follows the same client-credentials
pattern already used by this library's other surface-4 scripts.

## Configuration reference

| Setting | Value this scenario uses | Notes |
|---|---|---|
| Entity type (both ends) | `azure_sql_table` | Confirmed Purview asset type name for an Azure SQL Database table |
| Relationship type | `direct_lineage_dataset_dataset` | "DataSet1 is the upstream of DataSet2, although we wouldn't know exactly which Process is between them" - the documented shape for a custom link with no modeled intermediate process |
| Column-level detail | `attributes.columnMapping` - a **JSON-encoded string** (not a nested object), matching Microsoft's own worked example exactly | `[{"Source":"CustomerId","Sink":"CustomerId"}]` in the shipped example - see the known limitations for the scope of what this scenario validates about it |
| Idempotency mechanism | `Lineage - Get By Unique Attribute` (direction `OUTPUT`, depth 1) existence check before every `Relationship - Create` POST | See the design notes |
| Deploy role | **Data Curator** | Catalog Data plane write access |
| Validate role | **Data Reader** | Catalog Data plane read-only access |
| API version pinned by both scripts | `2023-09-01` | Confirmed current via direct fetch of Microsoft's own REST reference pages for all four operations this scenario uses (Relationship - Create, Relationship - Delete, Lineage - Get, Lineage - Get By Unique Attribute) |
| `-PurviewAccountEndpoint` accepted values | `https://api.purview-service.microsoft.com` (new portal) or `https://<account>.purview.azure.com` (classic portal) | Both explicitly confirmed as valid for this `/datamap/api/...` path family |

Full REST-body grounding: `deploy/New-CustomLineageRelationship.ps1` and
`validate/Test-EndToEndLineage.ps1` inline comments and their `.NOTES` blocks cite the exact
Microsoft Learn reference pages.

## Operations and tuning

**KPIs to watch (first 30 days):**
- **Validation pass/fail trend** - wire `validate/Test-EndToEndLineage.ps1` into a recurring
  scheduled check (matching the pattern this library's Data Quality scenario recommends for its own
  validate script). A sudden `[FAIL]` after a run that previously passed usually means either the
  custom relationship was deleted (accidentally, or by an unrelated cleanup script), or one of the
  two assets was re-scanned in a way that changed its qualifiedName - both worth investigating, not
  ignoring as a flake.
- **Chain length / breadth over time** - as more custom hops get added to `expectedDownstreamChain`,
  track how many are asserted (this scenario's pattern) vs. natively captured - a growing share of
  custom-asserted links is a signal worth raising with the platform team: it may mean a
  transform workload should be migrated onto Azure Data Factory or another natively-integrated
  system instead of accumulating more manually-maintained lineage assertions.

**Alert routing:** there is no Purview-native alert for "a lineage relationship was deleted" or "a
lineage graph developed a gap" - unlike DLP or Data Quality, lineage has no `GenerateAlert`
equivalent. The recurring `validate/Test-EndToEndLineage.ps1` run (above) **is** the detection
mechanism for this control; route its non-zero exit code into whatever CI/ops alerting this
organization already has, the same way *Configure Rules and Review Scorecards for a Governed Data Asset* (operations and tuning)
recommends for its own validate script.

**Incident-response runbook (validation reports a gap):**
1. **Triage** - read which specific check failed: "present but not connected" is an unambiguous
   graph topology issue (e.g. the relationship exists but between the wrong GUIDs after one asset
   was re-created by a rescan) - `-MaxDepth` cannot explain it, since the asset already had to be
   within the traversed depth to be "present" at all. "Not present at all" is ambiguous between a
   deleted relationship, a stale qualifiedName in the definition file, and `-MaxDepth` simply being
   too shallow to reach it - rule out the last one first by re-running with a larger `-MaxDepth`
   before assuming the link is genuinely missing.
2. **Classify the cause**, in order of likelihood: (a) `deploy/Remove-CustomLineageRelationship.ps1`
   or a manual portal deletion removed the link; (b) one of the two assets was deleted and
   re-created by a subsequent Data Map rescan, which assigns a **new** GUID even if the
   qualifiedName is unchanged - the old relationship (pointing at the old GUID) silently becomes
   orphaned; (c) the qualifiedName in the definition file is simply wrong or stale.
3. **Remediate** - re-run `deploy/New-CustomLineageRelationship.ps1`; its existence check will
   correctly detect the (b) case as "missing" (the old GUID's relationship is irrelevant once the
   asset itself has a new GUID) and create a fresh, correctly-targeted relationship.
4. **Escalate** if the gap recurs immediately after remediation - likely means the custom transform
   job's target table is being dropped and recreated (not just truncated/reloaded) on every run,
   which will always orphan lineage; that's a signal for the data engineering team to change the
   job's write pattern, not something this scenario's script can work around.

**Review cadence:** re-run `validate/Test-EndToEndLineage.ps1` after any change to either asset's
underlying schema or any rescan of either source, and at minimum monthly as a standing health
check - lineage gaps have no other native detection mechanism (see Alert routing, above).

## Rollback and decommission

See the rollback runbook for the full procedure. Quick reference:
`./deploy/Remove-CustomLineageRelationship.ps1` deletes the custom lineage relationship(s) named in
the definition file; the upstream and downstream assets themselves are never touched (this scenario
didn't create them).

## References

1. Data lineage in classic Data Catalog (overview, use cases, granularity) - <https://learn.microsoft.com/purview/data-gov-classic-lineage>
2. Data lineage user guide for classic Data Catalog (lineage collection, supported systems table, known limitations) - <https://learn.microsoft.com/purview/data-gov-classic-lineage-user-guide>
3. Data governance and security baselines with Microsoft Purview - "Data visibility baseline" (Recommendation: "Enable automated lineage where available and close gaps manually where required") - <https://learn.microsoft.com/azure/cloud-adoption-framework/data/governance-security-baselines-purview-data-estate-unify-data-platform>
4. Data lineage user guide for classic Data Catalog - supported data-processing-system lineage table (ADF, Synapse, Azure SQL Database preview, Airflow/OpenLineage, Azure Data Share) - <https://learn.microsoft.com/purview/data-gov-classic-lineage-user-guide#lineage-collection>
5. Create and get lineage relationships using the REST API (concepts, relationship types, worked Bulk Create/Create Relationship/Get Lineage examples, `direct_lineage_dataset_dataset` shape) - <https://learn.microsoft.com/purview/data-gov-api-create-lineage-relationships>
6. Data lineage user guide for classic Data Catalog - manual lineage entries and portal Lineage tab - <https://learn.microsoft.com/purview/data-gov-classic-lineage-user-guide#manual-lineage>
7. Tutorial: Authenticate for Microsoft Purview data-plane APIs (service principal setup, Data Curator/Data Reader roles for the Catalog Data plane, token acquisition) - <https://learn.microsoft.com/purview/data-gov-api-rest-data-plane>
8. Type definitions and how to create custom types - confirms `azure_sql_table` as the Azure SQL Table asset type name - <https://learn.microsoft.com/purview/data-gov-api-custom-types>
9. GraphQL API with Microsoft Purview (preview) - confirms both `api.purview-service.microsoft.com` (new portal) and `{account}.purview.azure.com` (classic portal) as valid endpoint hosts for the `/datamap/api/...` path family - <https://learn.microsoft.com/purview/data-gov-api-graphql>
10. Relationship - Create REST reference (API version 2023-09-01) - <https://learn.microsoft.com/rest/api/purview/datamapdataplane/relationship/create>
11. Relationship - Delete REST reference (API version 2023-09-01) - <https://learn.microsoft.com/rest/api/purview/datamapdataplane/relationship/delete>
12. Lineage - Get REST reference (API version 2023-09-01) - <https://learn.microsoft.com/rest/api/purview/datamapdataplane/lineage/get>
13. Lineage - Get By Unique Attribute REST reference (API version 2023-09-01) - <https://learn.microsoft.com/rest/api/purview/datamapdataplane/lineage/get-by-unique-attribute>
14. Entity - Bulk Create Or Update REST reference (API version 2023-09-01; upsert-by-qualifiedName semantics, referenced for contrast in the design notes) - <https://learn.microsoft.com/rest/api/purview/datamapdataplane/entity/bulk-create-or-update>
15. Discovery - Query REST reference (API version 2023-09-01; `Discovery_Query_Classification` and `Discovery_Query_Collection` worked examples confirm the `mssql://` qualifiedName scheme for `azure_sql_table`) - <https://learn.microsoft.com/rest/api/purview/catalogdataplane/discovery/query>

> Re-verify all links and the one remaining VERIFY item in the known limitations against current Microsoft Learn
> before a customer-facing deployment - Microsoft's own Data Map REST surface is explicitly called
> out elsewhere in this library (*Scan Azure SQL Database and Classify Sensitive Columns* (the known limitations)) as
> evolving.