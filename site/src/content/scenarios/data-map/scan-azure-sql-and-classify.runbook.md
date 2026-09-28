---
part: "runbook"
parent: "data-map/scan-azure-sql-and-classify"
---
## Implementation steps

### Portal path (for a first manual walkthrough / to validate intent before scripting)

1. Sign in to the [Microsoft Purview portal](https://purview.microsoft.com) → **Data Map** →
   **Collections**. Create or select the collection this source belongs to.
2. Under **Sources**, select **Register** → **Azure SQL Database** → **Continue**.
3. Name the source, pick the **Azure subscription** and **Server name**, select the target
   **collection**, and select **Apply**.
4. If the SQL logical server has a firewall, either enable **Allow Azure services and resources
   to access this server** under **Security → Networking**, or set up a self-hosted integration
   runtime / managed virtual network. **Security tradeoff:** the "Allow Azure
   services" toggle opens the firewall to connection attempts from **any Azure-hosted resource in
   any subscription or tenant**, not just this Purview account - authentication (SQL/Entra
   credentials) is still required to actually read data, but it materially widens the network
   attack surface. For a production database, prefer a Purview managed virtual network or a
   self-hosted integration runtime instead (the latter requires switching off SAMI authentication
   to a service principal or SQL auth - see the known limitations).
5. Configure authentication (this scenario defaults to system-assigned managed identity - see
   the configuration reference for the alternatives and when to use them):
   - In Azure SQL, [configure Microsoft Entra authentication](https://learn.microsoft.com/azure/azure-sql/database/authentication-aad-configure)
     if not already done.
   - Run the T-SQL in the configuration reference's "Grant the scan identity database access" against the target database,
     using the **exact name of your Purview account** as `[Username]`.
   - In the Azure portal, on the **SQL Server resource itself** (not the resource group or
     subscription - see the prerequisites), grant the Purview account's name the **Reader** IAM role.
6. Back in the Purview portal, select **New Scan** under the registered source. Provide a name,
   select the **system-assigned managed identity** credential, select **Test connection**, then
   **Continue**.
7. Select or scope the database(s)/tables to scan, then choose a **scan rule set** - either the
   system default (all classifications, this scenario's default) or a custom rule set narrowed to
   the SITs you care about.
8. Choose a **scan trigger** - **Once** for an ad hoc first pass, or a recurring schedule - and
   select **Save and run**.
9. After the scan completes, browse the classified assets in **Unified Catalog** to confirm
   columns matching your target SITs are tagged.

### Script path (idempotent, parameterized, dry-run capable)

```powershell
# 1. Deploy (dry run first - reports every REST call that would be made, changes nothing)
./deploy/New-AzureSqlDataMapScan.ps1 `
    -PurviewAccountName 'contoso-purview' `
    -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
    -SubscriptionId $SubscriptionId -ResourceGroupName 'rg-contoso-data' `
    -SqlServerName 'sql-contoso-prod' -DatabaseName 'customerdb' -Location 'eastus' `
    -CollectionReferenceName 'a1b2c' `
    -WhatIf

# 2. Deploy for real - registers the source and the scan, does not run it yet
./deploy/New-AzureSqlDataMapScan.ps1 `
    -PurviewAccountName 'contoso-purview' `
    -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
    -SubscriptionId $SubscriptionId -ResourceGroupName 'rg-contoso-data' `
    -SqlServerName 'sql-contoso-prod' -DatabaseName 'customerdb' -Location 'eastus' `
    -CollectionReferenceName 'a1b2c'

# 3. Deploy, add a weekly recurring trigger, and kick off an immediate full scan
./deploy/New-AzureSqlDataMapScan.ps1 `
    -PurviewAccountName 'contoso-purview' `
    -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
    -SubscriptionId $SubscriptionId -ResourceGroupName 'rg-contoso-data' `
    -SqlServerName 'sql-contoso-prod' -DatabaseName 'customerdb' -Location 'eastus' `
    -CollectionReferenceName 'a1b2c' `
    -RecurrenceFrequency Week -RecurrenceInterval 1 -RunNow

# 4. Validate
./validate/Test-AzureSqlDataMapScan.ps1 `
    -PurviewAccountName 'contoso-purview' -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
    -DataSourceName 'sql-contoso-prod-customerdb'
```

The deploy script uses the **Microsoft Purview Data Map / Data Governance REST API** - automation
surface 4 per [Automation surface, section 1](/docs/automation-surface/#1-five-automation-surfaces-not-one-read-this-first) - because data source and scan objects have no
Security & Compliance PowerShell or Graph equivalent; they exist only on this data plane. Token
acquisition follows [Automation surface, section 3](/docs/automation-surface/#3-authentication-patterns---interactive-vs-unattended)'s client-credentials pattern.

## Configuration reference

| Setting | Value this scenario uses | Notes |
|---|---|---|
| Data source `kind` | `AzureSqlDatabase` | |
| Scan `kind` (default) | `AzureSqlDatabaseMsi` | SAMI-authenticated - no credential object to create or rotate |
| Scan `kind` (alternative) | `AzureSqlDatabaseCredential` | SQL authentication or service principal (Key Vault-backed, via *Key Vault-Backed Scan Credential (SQL Auth / Service Principal)*), **or** a user-assigned managed identity (UAMI) for per-source identity separation, scripted end-to-end by *UAMI Credential for the Azure SQL Database Scan* - the "portal-only" claim this scenario originally carried here was incorrect; see the known limitations |
| Collection reference | `{ "referenceName": "<5-char collection ID>", "type": "CollectionReference" }` | The ID is **not** the collection's friendly name - read it from the collection's URL in the portal or the `List Collections` API |
| Scan rule set (this scenario's default) | `scanRulesetName: "AzureSqlDatabase"`, `scanRulesetType: "System"` | Microsoft's system rule set - every classification available for this source type, roughly 200 built-in SITs including **U.S. Social Security Number (SSN)** and **Credit Card Number**, the same pair already established in *Auto-Label Confidential PII in SharePoint & OneDrive* and *PCI Teams Card-Data Exfiltration Block* |
| Scan rule set (narrower, PII-only) | A **custom** rule set built from the system default with unwanted classifications excluded | Supported by the product (portal, and the `Az.Purview` module's `New-AzPurviewAzureSqlDatabaseScanRulesetObject -ExcludedSystemClassification`) - this scenario's script does not create one programmatically; see the known limitations VERIFY |
| Scan level | `Full` (first run) → `Incremental` (subsequent scheduled runs) | Customizable per-source scan levels (L1/L2/L3) are supported for Azure SQL Database specifically |
| Recurring trigger | Optional; `RecurrenceFrequency`/`RecurrenceInterval` parameters | Trigger resource name is always `default` - one trigger per scan |
| API version pinned by this script | `2023-09-01` | Confirmed current for the Scans, Data Sources, Triggers, and (as of 2026-09-04) Run Scan/List Scan History operations - see the known limitations |

Full cmdlet/REST-body grounding: `deploy/New-AzureSqlDataMapScan.ps1` inline comments and its
`.NOTES` block cite the exact Microsoft Learn reference pages.

## Operations and tuning

**KPIs to watch (first 30 days):**
- **Assets discovered vs. assets classified** (per scan run, from the run history) - a large,
  stable gap between the two after several runs usually means the scan rule set's SITs aren't
  matching real content shapes in this database (tune SIT confidence/count thresholds) rather than
  a scan failure.
- **Scan duration trend** - a steadily growing duration on `Incremental` runs against a database
  whose schema isn't growing proportionally can indicate classification sampling is re-scanning
  more than expected; compare against the scan level setting in the configuration reference.
- **Scan failure rate** - track `Failed`/`TransientFailure`/`Canceled` run statuses; a recurring firewall or credential failure after a database migration is
  the most common cause.

**Alert routing:** Data Map scan failures do **not** generate a DLP-style alert/incident report -
there is no equivalent of `GenerateAlert` for scans. Poll scan run status via the REST API (or the
portal's **Monitoring** view) on the same cadence as the recurring trigger, and wire failures into
existing monitoring (a scheduled pipeline step that calls `validate/Test-AzureSqlDataMapScan.ps1`
and fails the pipeline on a non-`Completed` last-run status is the pattern this scenario's
validate script is built for).

**Incident-response runbook (scan repeatedly fails, or a run status stays non-`Succeeded`):**
1. **Triage** - pull the failing run's detail from the portal (**Data Map → Monitoring →** the
   run ID) or the scan history API; note the discovery-phase status and any error message.
2. **Classify the cause** - the most common failure classes, in order of likelihood: (a) the
   firewall/network path changed (SQL firewall rule removed, self-hosted IR machine offline); (b)
   the SAMI's `db_datareader` grant was revoked or the database user was dropped (e.g. after a
   point-in-time restore, which does not preserve Entra database users); (c) the SQL resource
   moved to a different resource group/subscription, breaking the Azure IAM `Reader` grant's ARM
   path (see the Review cadence note below); (d) a transient service-side issue (`TransientFailure` status) -
   safe to let the next scheduled run retry.
3. **Remediate** - re-apply the specific broken grant (T-SQL `db_datareader`, or the Azure IAM
   `Reader` assignment) rather than re-running the full deploy script blind; re-run
   `validate/Test-AzureSqlDataMapScan.ps1` to confirm the objects are still correctly configured
   before assuming the grants are the problem.
4. **Escalate** if `Failed` recurs after confirming both grants and the network path are intact -
   this points at a Purview-service-side issue worth a support case, not a configuration gap this
   scenario's script can fix.

**Review cadence:** re-run `validate/Test-AzureSqlDataMapScan.ps1` after any change to the target
database's firewall, Microsoft Entra admin configuration, or resource group/subscription move -
Purview's data-resource policies (and, by extension, this scan's Azure IAM `Reader` grant) are
tied to the SQL resource's ARM path, and a resource move silently breaks the grant without
breaking the scan's *registration*. Review the classification results
quarterly against the tenant's actual regulatory scope (see the known limitations's regional-SIT note) - a scan rule
set built once at rollout tends to drift out of date as new sensitive-data categories become
relevant.

**Downstream use:** once columns are classified, they become groundwork for
*Information Protection* auto-labeling scope decisions, *DLP* policy
targeting, and *Exportable, Historical Classification Coverage Report* - which turns this
scenario's own `customerdb.dbo.Customers` classification output into an exportable, historical
coverage trend line - this scenario intentionally stops at "classify and make visible," not "act on
the classification."

## Rollback and decommission

See the rollback runbook for the full staged procedure (disable trigger → delete scan → delete data
source). Quick reference: `./deploy/Remove-AzureSqlDataMapScan.ps1` removes the scan and its
trigger (reversible by re-running the deploy script); add `-RemoveDataSource` to also delete the
data source registration.

## References

1. Discover and govern Azure SQL Database in Microsoft Purview (registration, firewall, authentication options, scan setup, known limitations) - <https://learn.microsoft.com/purview/register-scan-azure-sql-database>
2. Microsoft Purview billing models (PAYG for Data Map) - <https://learn.microsoft.com/purview/purview-billing-models>
3. Tutorial: Authenticate for Microsoft Purview data-plane APIs (service principal setup, Data Source Administrator/Data Curator/Collection Admin/Policy Author role assignment, token acquisition) - <https://learn.microsoft.com/purview/data-gov-api-rest-data-plane>
4. Discover and govern Azure SQL Database - "Configure authentication for a scan" (SAMI/UAMI/service principal/SQL auth options, T-SQL grants, self-hosted IR incompatibility with managed identity) - <https://learn.microsoft.com/purview/register-scan-azure-sql-database#configure-authentication-for-a-scan>
5. Scans - Create Or Replace REST API reference (API version 2023-09-01; `AzureSqlDatabaseMsiScan`/`AzureSqlDatabaseCredentialScan` kinds and properties) - <https://learn.microsoft.com/rest/api/purview/scanningdataplane/scans/create-or-replace>
6. Connect to and manage Azure Synapse Analytics workspaces in Microsoft Purview - collection ID lookup via portal URL or List Collections API - <https://learn.microsoft.com/purview/register-scan-synapse-workspace#scan>
7. Scans and ingestion in Data Map (customizable scan levels for Azure SQL Database, scan rule sets) - <https://learn.microsoft.com/purview/data-map-scan-ingestion>
8. New-AzPurviewTrigger (Az.Purview PowerShell module) - trigger resource path pattern (`datasources/{name}/scans/{name}/triggers/default`), recurrence parameters - <https://learn.microsoft.com/powershell/module/az.purview/new-azpurviewtrigger>
9. Monitor Data Map population in Microsoft Purview (scan run statuses, 90-day run-history retention) - <https://learn.microsoft.com/purview/data-map-scan-run-monitor-population>
10. ScanRunStatus enumeration (Accepted/InProgress/TransientFailure/Succeeded/Failed/Canceled) - <https://learn.microsoft.com/rest/api/purview/scanningdataplane/scans/create-or-replace> (Definitions section)
11. Create a scan rule set in Data Map (system vs. custom rule sets, classification-rule selection) - <https://learn.microsoft.com/purview/data-map-scan-rule-set>
12. Classification best practices in the Microsoft Purview Data Map - <https://learn.microsoft.com/purview/data-gov-best-practices-classification>
13. AzureSqlDatabaseProperties / AzureDataSourceProperties interfaces (`@azure-rest/purview-scanning` JS SDK - `serverEndpoint`, `resourceName`, `resourceGroup`, `subscriptionId`, `location`, `collection` field confirmation) - <https://learn.microsoft.com/javascript/api/@azure-rest/purview-scanning/azuresqldatabaseproperties> and <https://learn.microsoft.com/javascript/api/@azure-rest/purview-scanning/azuredatasourceproperties>
14. Az.Purview PowerShell module reference (`New-AzPurviewDataSource`, `New-AzPurviewScan`, `Remove-AzPurviewDataSource`, `Remove-AzPurviewScan`, `Start-AzPurviewScanResultScan`) - <https://learn.microsoft.com/powershell/module/az.purview/>
15. Data governance roles and permissions in Microsoft Purview (classic Data Map role vocabulary - Data Source Administrator, Data Curator, Data Reader, Collection Admin) - <https://learn.microsoft.com/purview/data-gov-classic-permissions>
16. New-AzPurviewAzureSqlDatabaseScanRulesetObject (Az.Purview PowerShell module - confirms the exclusion-based custom scan rule set model via `-ExcludedSystemClassification`) - <https://learn.microsoft.com/powershell/module/az.purview/new-azpurviewazuresqldatabasescanrulesetobject>
17. Scan Result - Run Scan and Scan Result - List Scan History REST API references (confirmed the action-style `POST .../:run?runId=...` shape and the nested `discoveryExecutionDetails.statistics.assets` shape; direct-fetched during the Azure SQL Managed Instance sibling scenario's build and backported here 2026-09-04) - <https://learn.microsoft.com/rest/api/purview/scanningdataplane/scan-result/run-scan> and <https://learn.microsoft.com/rest/api/purview/scanningdataplane/scan-result/list-scan-history>
18. Data Sources - Create Or Replace REST API reference (confirmed `AzureSqlDatabaseDataSource`/`AzureSqlDatabaseProperties` schema - `serverEndpoint`, `resourceName`, `resourceGroup`, `subscriptionId`, `location`, `collection`; direct-fetched 2026-09-28) - <https://learn.microsoft.com/rest/api/purview/scanningdataplane/data-sources/create-or-replace>
19. Triggers - Create Or Replace REST API reference (confirmed `properties.recurrence`/`TriggerRecurrence` schema - `startTime`, `endTime`, `interval`, `frequency`, `schedule`; direct-fetched 2026-09-28) - <https://learn.microsoft.com/rest/api/purview/scanningdataplane/triggers/create-or-replace>

> Re-verify all links, API versions, and REST body shapes against current Microsoft Learn before a
> customer-facing deployment - the Data Map REST surface is explicitly called out by Microsoft as
> evolving. One VERIFY item remains open in the known limitations (the custom scan-rule-set REST creation body shape)
> and should be closed against a pilot tenant or a direct Microsoft Learn fetch of the Scan Rule
> Sets - Create Or Replace reference page.