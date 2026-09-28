---
part: "runbook"
parent: "data-map/scan-azure-synapse-and-classify"
---
## Implementation steps

### Portal path (for a first manual walkthrough / to validate intent before scripting)

1. Sign in to the [Microsoft Purview portal](https://purview.microsoft.com) → **Sources** →
   **Register** → **Azure Synapse Analytics (multiple)** → **Continue**. Enter a name, optionally
   filter by subscription, select the **workspace**, confirm the auto-populated dedicated/serverless
   SQL endpoints, choose a collection, and select **Register**.
2. **Grant the Purview MSI Reader on the workspace.** Azure portal → the Synapse workspace →
   **Access control (IAM)** → **Add** → role **Reader** → assign to the Purview account's name
   (representing its MSI). Requires **Owner** or **User Access Administrator** on the resource. Required for both dedicated and serverless scanning; assign at a resource
   group/subscription scope instead if registering multiple workspaces.
3. **Serverless only - three-part enumeration setup:**
   a. (already done in step 2 - the workspace-level Reader grant applies here too.)
   b. **Storage account:** in the resource group/subscription containing the workspace's associated
      ADLS Gen2 storage account, **Access control (IAM)** → **Add** → role **Storage Blob Data
      Reader** → assign to the Purview account's name.
   c. **Enumeration login - server-scoped, run once, not per database.** `CREATE LOGIN` has always
      been a server-level statement in SQL Server/Azure SQL regardless of which database context
      executes it, and Synapse serverless is not documented as an exception - two directly-fetched
      Microsoft Learn pages confirm this login is created against `master` exactly once (see
      *Bulk-Grant Azure Synapse Serverless SQL Database Access* (the architecture) for the full grounding
      and citations). Microsoft's portal walkthrough below reads as repeating the step "per database"
      only because Synapse Studio's **New SQL script** entry point happens to be reached from inside a
      specific database's context - run it from any one serverless database once, not from every one:
      ```sql
      CREATE LOGIN [<PurviewAccountName>] FROM EXTERNAL PROVIDER;
      ```
     
4. **Grant database read access.** Different T-SQL per pool type - run against **each** database:
   - **Dedicated SQL pool:**
     ```sql
     CREATE USER [<PurviewAccountName>] FROM EXTERNAL PROVIDER
     GO
     EXEC sp_addrolemember 'db_datareader', [<PurviewAccountName>]
     GO
     ```
   - **Serverless SQL pool** (after step 3c's `CREATE LOGIN`):
     ```sql
     CREATE USER [<PurviewAccountName>] FOR LOGIN [<PurviewAccountName>];
     ALTER ROLE db_datareader ADD MEMBER [<PurviewAccountName>];
     ```
   - **If the workspace has external tables**, also run (once per scoped credential):
     ```sql
     GRANT REFERENCES ON DATABASE SCOPED CREDENTIAL::[scoped_credential] TO [<PurviewAccountName>];
     ```
     **This step is easy to miss because skipping it fails silently, not loudly:** the scan still
     completes and still classifies every ordinary table/column, so a workspace with external tables
     backed by a scoped credential this grant wasn't applied to will show a "successful" scan that
     quietly under-covers exactly the tables most likely to reference sensitive data sitting outside
     the database itself (flagged as a Red Team finding in the review notes). Confirm which databases have
     external tables and scoped credentials (`SELECT * FROM sys.database_scoped_credentials;`) before
     treating a clean scan run as complete coverage.
  
5. **Confirm the workspace firewall.** Azure portal → the workspace → **Firewalls** → **Allow Azure
   services and resources to access this workspace** = **On** → **Save**. If this control cannot be
   enabled for this workspace, stop here and use the REST-API + SQL-Auth fallback instead - see
   the known limitations.
6. Back in the Purview portal, select **New scan** under the registered source. In the **Type**
   dropdown, **SQL Database** is the only supported type for this source - select it. Choose the
   credential (the Purview account's MSI, this scenario's default), **Test connection**, then
   **Continue**.
7. Choose **Azure Synapse SQL** as the scan rule set, choose a scan trigger, and **Save and run**.
8. After the scan completes, browse the classified assets in **Unified Catalog** to confirm columns
   matching your target SITs are tagged.

### Script path (idempotent, parameterized, dry-run capable)

```powershell
# 1. Deploy (dry run first - reports every REST call that would be made, changes nothing)
./deploy/New-AzureSynapseDataMapScan.ps1 `
    -PurviewAccountName 'contoso-purview' `
    -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
    -SubscriptionId $SubscriptionId -ResourceGroupName 'rg-contoso-data' `
    -WorkspaceName 'ws-contoso-prod' `
    -DedicatedSqlEndpoint 'ws-contoso-prod.sql.azuresynapse.net' `
    -ServerlessSqlEndpoint 'ws-contoso-prod-ondemand.sql.azuresynapse.net' `
    -Location 'eastus' -CollectionReferenceName 'a1b2c' `
    -WhatIf

# 2. Deploy for real - registers the source and the scan, does not run it yet
./deploy/New-AzureSynapseDataMapScan.ps1 `
    -PurviewAccountName 'contoso-purview' `
    -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
    -SubscriptionId $SubscriptionId -ResourceGroupName 'rg-contoso-data' `
    -WorkspaceName 'ws-contoso-prod' `
    -DedicatedSqlEndpoint 'ws-contoso-prod.sql.azuresynapse.net' `
    -ServerlessSqlEndpoint 'ws-contoso-prod-ondemand.sql.azuresynapse.net' `
    -Location 'eastus' -CollectionReferenceName 'a1b2c'

# 3. Deploy, add a weekly recurring trigger, and kick off an immediate full scan
./deploy/New-AzureSynapseDataMapScan.ps1 `
    -PurviewAccountName 'contoso-purview' `
    -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
    -SubscriptionId $SubscriptionId -ResourceGroupName 'rg-contoso-data' `
    -WorkspaceName 'ws-contoso-prod' `
    -DedicatedSqlEndpoint 'ws-contoso-prod.sql.azuresynapse.net' `
    -ServerlessSqlEndpoint 'ws-contoso-prod-ondemand.sql.azuresynapse.net' `
    -Location 'eastus' -CollectionReferenceName 'a1b2c' `
    -RecurrenceFrequency Week -RunNow

# 4. Validate
./validate/Test-AzureSynapseDataMapScan.ps1 `
    -PurviewAccountName 'contoso-purview' -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
    -DataSourceName 'ws-contoso-prod'
```

The deploy script uses the **Microsoft Purview Data Map / Data Governance REST API** - automation
surface 4 per [Automation surface, section 1](/docs/automation-surface/#1-five-automation-surfaces-not-one-read-this-first). Steps 2-5 above (Reader grant, Storage Blob Data Reader,
per-database logins/grants, firewall) are one-time, out-of-band prerequisites this script does not
perform - see the design notes.

## Configuration reference

| Setting | Value this scenario uses | Notes |
|---|---|---|
| Data source `kind` | `AzureSynapseWorkspace` | Distinct from both sibling scenarios - one object per **workspace**, not per database |
| Scan `kind` (default) | `AzureSynapseWorkspaceMsi` | SAMI-authenticated - no credential object to create or rotate |
| Scan `kind` (alternative) | `AzureSynapseWorkspaceCredential` | SQL authentication or service principal (Key Vault-backed, via *Key Vault-Backed Scan Credential (SQL Auth / Service Principal)* - the "portal-only" claim this row originally carried was incorrect, corrected 2026-09-25, matching both sibling scenarios' own corrections), **or** a user-assigned managed identity (UAMI) for per-source identity separation, scripted end-to-end by *UAMI Credential for the Azure Synapse Workspace Scan*; see section 11 |
| `dedicatedSqlEndpoint` format | bare hostname, e.g. `ws-contoso-prod.sql.azuresynapse.net` | Optional - confirmed via Microsoft's own worked PowerShell example |
| `serverlessSqlEndpoint` format | bare hostname, e.g. `ws-contoso-prod-ondemand.sql.azuresynapse.net` | Optional - at least one of the two endpoints is required; confirmed via the same worked example |
| Collection reference | `{ "referenceName": "<5-char collection ID>", "type": "CollectionReference" }` | Same shape as both sibling scenarios - read the ID from the collection's URL in the portal, not its friendly name |
| Scan rule set (this scenario's default) | `scanRulesetName: "AzureSynapseSQL"`, `scanRulesetType: "System"` | A **different system rule set name** from both sibling scenarios - confirmed via Microsoft's own worked PowerShell example and the portal's own scan-setup documentation; includes the same SSN + Credit Card Number pair |
| Scan object `resourceTypes` property | **Omitted** by this scenario's deploy script | A worked example for its shape now exists (found while building the `-managed-identity-credential` sibling), but this scenario deliberately still omits it - auto-enumeration is a different, still-valid design choice from the worked example's named-database scoping - see the known limitations |
| Scan level | `Full` (first run) → `Incremental` (subsequent scheduled runs) | Same pattern as both sibling scenarios |
| Recurring trigger | Optional; `RecurrenceFrequency`/`RecurrenceInterval` parameters | Trigger resource name is always `default` - same generic shape both sibling scenarios confirmed |
| Run-scan call shape | `POST .../scans/{name}:run?runId={guid}&scanLevel={level}` | Action-style POST - the same generic shape confirmed by direct fetch during the Managed Instance sibling scenario's build; reused unchanged here since it does not vary by data source `kind` |
| API version pinned by this script | `2023-09-01` | Same version both sibling scenarios pin, for the same generic Data Sources/Scans/Triggers/Scan Result operations |

Full cmdlet/REST-body grounding: `deploy/New-AzureSynapseDataMapScan.ps1` inline comments and its
`.NOTES` block cite the exact Microsoft Learn reference pages.

## Operations and tuning

Same KPIs, alert-routing model (no `GenerateAlert`-style alerting for Data Map scans - poll instead),
and incident-response runbook shape as both sibling scenarios - see `scan-azure-sql-and-classify/
operations and tuning for the full text, not repeated here. Two Synapse-specific additions to the triage step,
alongside the sibling scenarios' own causes:

**Incident-response addition - Synapse-specific failure causes:** (e) the **serverless enumeration
login** (`CREATE LOGIN [<PurviewAccountName>] FROM EXTERNAL PROVIDER`) was never created, or the
**per-database `CREATE USER`/`db_datareader` grant** that depends on it was dropped during a database
restore/recreate - a database-level rebuild only affects that per-database grant, not the server-scoped
login itself (the architecture and the implementation steps step 3c) - the scan authenticates successfully against the workspace but silently
returns zero serverless assets, since the workspace-level Reader grant alone is not sufficient for
serverless enumeration; (f) the workspace's **Storage Blob Data Reader** grant on the
associated storage account was revoked (e.g. during a storage-account access review that didn't know
this scenario's serverless scan depended on it) - serverless enumeration fails even though the
dedicated pool (if also scanned) continues to work, since only serverless enumeration depends on this
grant.

**Review cadence:** same as both sibling scenarios, plus one Synapse-specific check: after any
database restore, recreate, or migration within the workspace, re-run
`validate/Test-AzureSynapseDataMapScan.ps1` and re-confirm the per-database `CREATE USER`/
`db_datareader` grant (the validation steps check 5) - a database-level rebuild silently drops this grant even though
the server-scoped `CREATE LOGIN` (the architecture and the implementation steps step 3c) and the workspace-level IAM roles (Reader, Storage
Blob Data Reader) are unaffected.

**Downstream use:** same as both sibling scenarios - this scenario stops at "classify and make
visible," feeding *Information Protection*, *DLP*, and any future Data Estate
Insights reporting fragment.

## Rollback and decommission

See the rollback runbook for the full staged procedure (disable trigger → delete scan → delete data source) -
structurally identical to both sibling scenarios'. Quick reference:
`./deploy/Remove-AzureSynapseDataMapScan.ps1` removes the scan and its trigger (reversible by
re-running the deploy script); add `-RemoveDataSource` to also delete the data source registration.
Rolling back the scan/data source objects does **not** revert the out-of-band prerequisites (Reader
grant, Storage Blob Data Reader, per-database logins/grants, firewall setting) - see the rollback runbook.

## References

1. Discover and govern Azure SQL Database in Microsoft Purview (shared regulatory-driver framing) - <https://learn.microsoft.com/purview/register-scan-azure-sql-database>
2. Connect to and manage Azure Synapse Analytics workspaces in Microsoft Purview (registration, enumeration/scan authentication for dedicated and serverless SQL, firewall requirement, scan wizard "Type" behavior, lake-database non-support) - <https://learn.microsoft.com/purview/register-scan-synapse-workspace>
3. New-AzPurviewAzureSynapseWorkspaceDataSourceObject (Az.Purview PowerShell module - confirms `dedicatedSqlEndpoint`/`serverlessSqlEndpoint` property names and format via its own worked example) - <https://learn.microsoft.com/powershell/module/az.purview/new-azpurviewazuresynapseworkspacedatasourceobject>
4. New-AzPurviewAzureSynapseWorkspaceMsiScanObject (Az.Purview PowerShell module - confirms `ScanRulesetName 'AzureSynapseSQL'` via its own worked example) - <https://learn.microsoft.com/powershell/module/az.purview/new-azpurviewazuresynapseworkspacemsiscanobject>
5. Data Sources - Create Or Replace REST API reference (API version 2023-09-01; generic shape confirmed by direct fetch during the *Scan Azure SQL Managed Instance and Classify Sensitive Columns* sibling scenario's build) - <https://learn.microsoft.com/rest/api/purview/scanningdataplane/data-sources/create-or-replace>
6. Scans - Create Or Replace REST API reference (API version 2023-09-01; same generic-shape confirmation) - <https://learn.microsoft.com/rest/api/purview/scanningdataplane/scans/create-or-replace>
7. Triggers - Create Or Replace REST API reference (API version 2023-09-01; same generic-shape confirmation) - <https://learn.microsoft.com/rest/api/purview/scanningdataplane/triggers/create-or-replace>
8. Scan Result - Run Scan / List Scan History REST API reference (API version 2023-09-01; confirms the `POST .../scans/{name}:run?runId=...` action-style shape and the nested `discoveryExecutionDetails.statistics.assets` shape) - <https://learn.microsoft.com/rest/api/purview/scanningdataplane/scan-result/run-scan> and <https://learn.microsoft.com/rest/api/purview/scanningdataplane/scan-result/list-scan-history>
9. Az.Purview PowerShell module reference (`Remove-AzPurviewDataSource`, `Remove-AzPurviewScan`) - <https://learn.microsoft.com/powershell/module/az.purview/>
10. Data governance roles and permissions in Microsoft Purview (classic Data Map role vocabulary) - <https://learn.microsoft.com/purview/data-gov-classic-permissions>
11. Managed virtual networks and private endpoints in Microsoft Purview (confirms Azure Synapse Analytics is among the data sources Microsoft documents as reachable via a Purview-managed private endpoint, distinct from the flat SAMI-over-private-endpoint restriction the Managed Instance sibling scenario documents - not exercised by this scenario's default public/firewall-open path) - <https://learn.microsoft.com/purview/data-governance-private-endpoints-managed-virtual-network>
12. *Scan Azure SQL Database and Classify Sensitive Columns* and *Scan Azure SQL Managed Instance and Classify Sensitive Columns* - the sibling scenarios this fragment extends; see their this page and the design notes for shared reasoning not repeated here.
13. Connect to and manage dedicated SQL pools (formerly SQL DW) in Microsoft Purview - the older, standalone data source this scenario deliberately does **not** use; cited here so a reader who lands on this page while researching Synapse scanning understands it documents a different, separate Purview data source `kind` from the workspace-based one this scenario automates - <https://learn.microsoft.com/purview/register-scan-azure-synapse-analytics>

> Re-verify all links and API versions against current Microsoft Learn before a customer-facing
> deployment - the Data Map REST surface is explicitly called out by Microsoft as evolving, and
> `learn.microsoft.com` was unreachable for direct verification throughout this build (see the known limitations's
> grounding-method note). The `resourceTypes` VERIFY was closed 2026-09-28 via a direct re-fetch of
> the canonical page once `learn.microsoft.com` access was available - see the known limitations.