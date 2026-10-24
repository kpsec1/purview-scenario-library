---
part: "runbook"
parent: "data-map/scan-azure-sql-managed-instance-and-classify"
---
## Implementation steps

### Portal path (for a first manual walkthrough / to validate intent before scripting)

1. Sign in to the [Microsoft Purview portal](https://purview.microsoft.com) → **Data Map** →
   **Register** → **Azure SQL Managed Instance** → **Continue**. Select **From Azure subscription**,
   the subscription, and the server; provide the instance's **public endpoint fully qualified domain
   name and port** (e.g. `mi-contoso-prod.public.ac1b2c3d4e5f.database.windows.net,3342`), then
   **Register**. **Security tradeoff:** enabling the public endpoint puts that
   FQDN on the public internet - a strictly larger network exposure than the sibling scenario's
   "Allow Azure services" firewall toggle, which keeps the connection path inside Azure's own network
   fabric. Authentication (Entra/SQL) is still required to read data either way, but for a production
   instance prefer a **private endpoint** with a self-hosted integration runtime instead (this
   requires switching authentication off SAMI - see the known limitations).
2. **Set the Microsoft Entra admin on the instance** (not the logical server - there isn't one for a
   managed instance): Azure portal → the managed instance → **Microsoft Entra ID** → **Set admin**,
   or `Set-AzSqlInstanceActiveDirectoryAdministrator`.
3. **Grant Directory Readers.** On the instance's **Microsoft Entra ID** pane, select the banner
   prompting you to grant Directory Reader permissions to the instance's managed identity (requires
   signing in as a **Privileged Role Administrator**), or run the PowerShell script Microsoft
   publishes for this step. Skipping this step means Microsoft Entra
   authentication - including the SAMI-based scan this scenario configures - does not work at all.
4. **Grant database access to the Purview SAMI.** Against the target database:
   ```sql
   CREATE USER [<exact name of your Purview account>] FROM EXTERNAL PROVIDER;
   ```
   then grant it `db_datareader` (e.g. `ALTER ROLE db_datareader ADD MEMBER [<PurviewAccountName>];`). This T-SQL grant - not an Azure IAM role assignment on the instance resource -
   is the only access grant Microsoft documents for SAMI/UAMI scan authentication against Managed
   Instance; see the known limitations for a prior revision of this step that assumed otherwise.
5. **Confirm the network path.** If the instance uses the public endpoint, confirm its Network
   Security Group has an inbound rule allowing the `AzureCloud` service tag over the ports its
   connection type requires (Redirect: `1433` + `11000`-`11999`; Proxy: `3342`).
6. Back in the Purview portal, select **New scan** under the registered source, choose the Azure
   integration runtime (public endpoint) or a self-hosted IR (private endpoint - see the known limitations), select the
   SAMI credential, **Test connection**, then **Continue**.
7. Scope the scan, choose a scan rule set (system default, this scenario's default), choose a scan
   trigger, and **Save and run**.
8. After the scan completes, browse the classified assets in **Unified Catalog** to confirm columns
   matching your target SITs are tagged.

### Script path (idempotent, parameterized, dry-run capable)

```powershell
# 1. Deploy (dry run first - reports every REST call that would be made, changes nothing)
./deploy/New-AzureSqlManagedInstanceDataMapScan.ps1 `
    -PurviewAccountName 'contoso-purview' `
    -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
    -SubscriptionId $SubscriptionId -ResourceGroupName 'rg-contoso-data' `
    -InstanceName 'mi-contoso-prod' `
    -PublicEndpointFqdn 'mi-contoso-prod.public.ac1b2c3d4e5f.database.windows.net' `
    -DatabaseName 'customerdb' -Location 'eastus' -CollectionReferenceName 'a1b2c' `
    -WhatIf

# 2. Deploy for real - registers the source and the scan, does not run it yet
./deploy/New-AzureSqlManagedInstanceDataMapScan.ps1 `
    -PurviewAccountName 'contoso-purview' `
    -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
    -SubscriptionId $SubscriptionId -ResourceGroupName 'rg-contoso-data' `
    -InstanceName 'mi-contoso-prod' `
    -PublicEndpointFqdn 'mi-contoso-prod.public.ac1b2c3d4e5f.database.windows.net' `
    -DatabaseName 'customerdb' -Location 'eastus' -CollectionReferenceName 'a1b2c'

# 3. Deploy, add a weekly recurring trigger, and kick off an immediate full scan
./deploy/New-AzureSqlManagedInstanceDataMapScan.ps1 `
    -PurviewAccountName 'contoso-purview' `
    -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
    -SubscriptionId $SubscriptionId -ResourceGroupName 'rg-contoso-data' `
    -InstanceName 'mi-contoso-prod' `
    -PublicEndpointFqdn 'mi-contoso-prod.public.ac1b2c3d4e5f.database.windows.net' `
    -DatabaseName 'customerdb' -Location 'eastus' -CollectionReferenceName 'a1b2c' `
    -RecurrenceFrequency Week -RunNow

# 4. Validate
./validate/Test-AzureSqlManagedInstanceDataMapScan.ps1 `
    -PurviewAccountName 'contoso-purview' -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
    -DataSourceName 'mi-contoso-prod-customerdb'
```

The deploy script uses the **Microsoft Purview Data Map / Data Governance REST API** - automation
surface 4 per [Automation surface, section 1](/docs/automation-surface/#1-five-automation-surfaces-not-one-read-this-first). Steps 2-5 above (Entra admin, Directory Readers,
database grant, network) are one-time, out-of-band prerequisites this script does not
perform - see the design notes.

## Configuration reference

| Setting | Value this scenario uses | Notes |
|---|---|---|
| Data source `kind` | `AzureSqlDatabaseManagedInstance` | Distinct from the sibling scenario's `AzureSqlDatabase` |
| Scan `kind` (default) | `AzureSqlDatabaseManagedInstanceMsi` | SAMI-authenticated - no credential object to create or rotate |
| Scan `kind` (alternative) | `AzureSqlDatabaseManagedInstanceCredential` | SQL authentication or service principal (Key Vault-backed, via *Key Vault-Backed Scan Credential (SQL Auth / Service Principal)* - the "portal-only" claim this row originally carried was incorrect, corrected 2026-09-25), **or** a user-assigned managed identity (UAMI) for per-source identity separation, scripted end-to-end by *UAMI Credential for the Azure SQL Managed Instance Scan*; see section 11 |
| `serverEndpoint` format | `tcp:<PublicEndpointFqdn>,<Port>` (e.g. `tcp:mi-contoso-prod.public.ac1b2c3d4e5f.database.windows.net,3342`) | Distinct from the sibling scenario's bare hostname - confirmed via Microsoft's own worked PowerShell example |
| Default public-endpoint port | `3342` | Microsoft's own worked *registration* example uses this port. **Distinct from the NSG *network-path* ports** in section 3's table: since October 2025, Redirect is Microsoft's default connection type for connections originating inside Azure (Proxy remains default for connections originating outside Azure), which determines whether the NSG needs `1433`+`11000`-`11999` (Redirect) or just `3342` (Proxy) - confirm both the registration port and the connection type independently against the instance's actual configuration before relying on either default |
| Collection reference | `{ "referenceName": "<5-char collection ID>", "type": "CollectionReference" }` | Same shape as the sibling scenario - read the ID from the collection's URL in the portal, not its friendly name |
| Scan rule set (this scenario's default) | `scanRulesetName: "AzureSqlDatabaseManagedInstance"`, `scanRulesetType: "System"` | A **different system rule set name** from the sibling scenario's `AzureSqlDatabase` - confirmed via Microsoft's own worked PowerShell example; includes the same SSN + Credit Card Number pair |
| Scan level | `Full` (first run) → `Incremental` (subsequent scheduled runs) | Same pattern as the sibling scenario |
| Recurring trigger | Optional; `RecurrenceFrequency`/`RecurrenceInterval` parameters | Trigger resource name is always `default` - confirmed via Microsoft's own worked Triggers example |
| Run-scan call shape | `POST .../scans/{name}:run?runId={guid}&scanLevel={level}` | **Corrected from the sibling scenario's assumed shape** - an action-style POST, not a resource-style `PUT .../runs/{runId}`; confirmed via direct fetch of Microsoft's own REST reference - see the design notes |
| API version pinned by this script | `2023-09-01` | Confirmed current for all four REST operations this script uses, via direct fetch of each operation's own canonical reference page - see the known limitations |

Full cmdlet/REST-body grounding: `deploy/New-AzureSqlManagedInstanceDataMapScan.ps1` inline comments
and its `.NOTES` block cite the exact Microsoft Learn reference pages.

## Operations and tuning

Same KPIs, alert-routing model (no `GenerateAlert`-style alerting for Data Map scans - poll instead),
and incident-response runbook shape as the sibling scenario - see `scan-azure-sql-and-classify/
operations and tuning for the full text, not repeated here. One Managed-Instance-specific addition to the
triage step:

**Incident-response addition - Managed Instance-specific failure causes**, in order of likelihood
alongside the sibling scenario's four: (e) the **Directory Readers** role was revoked from the
instance's managed identity (e.g. during a security review that didn't know this scenario's scan
depended on it) - Microsoft Entra authentication fails tenant-wide for the instance until it's
re-granted, not just for this scan; (f) the instance's **public endpoint** was disabled (e.g. as a
network-hardening change) - re-enable it, or migrate this scenario to the private-endpoint +
self-hosted IR path (the known limitations, not scripted by this scenario).

**Review cadence:** same as the sibling scenario, plus two Managed-Instance-specific checks: (a)
re-run `validate/Test-AzureSqlManagedInstanceDataMapScan.ps1` after any change to the instance's
public-endpoint setting, connection type (Redirect/Proxy), or NSG rules - network levers with no
equivalent on a logical server; (b) run
*Verify Purview / Azure SQL Managed Instance Microsoft Entra Prerequisites*
on a schedule (that scenario's own operations and tuning recommends daily/weekly) to confirm the instance's
managed identity is still a Directory Readers member, and to catch drift - a *different*,
unrelated identity being added to the same tenant-wide-flavored role since this scenario was
deployed - automatically, closing the gap this scenario's own tooling cannot see (the validation steps check 4).

**Downstream use:** same as the sibling scenario - this scenario stops at "classify and make
visible," feeding *Information Protection*, *DLP*, and any future Data Estate
Insights reporting fragment.

## Rollback and decommission

See the rollback runbook for the full staged procedure (disable trigger → delete scan → delete data
source) - structurally identical to the sibling scenario's. Quick reference:
`./deploy/Remove-AzureSqlManagedInstanceDataMapScan.ps1` removes the scan and its trigger (reversible
by re-running the deploy script); add `-RemoveDataSource` to also delete the data source
registration. Rolling back the scan/data source objects does **not** revert the four out-of-band
Managed-Instance-specific prerequisites (Entra admin, Directory Readers, database grant,
public endpoint) - see the rollback runbook.

## References

1. Discover and govern Azure SQL Database in Microsoft Purview (shared regulatory-driver framing) - <https://learn.microsoft.com/purview/register-scan-azure-sql-database>
2. Connect to and manage an Azure SQL Managed Instance in Microsoft Purview (registration, public endpoint, scan setup) - <https://learn.microsoft.com/purview/register-scan-azure-sql-managed-instance>
3. Configure and manage Microsoft Entra authentication with Azure SQL - "Set Microsoft Entra admin" (Azure SQL Managed Instance) and "Assign Microsoft Graph permissions" (Directory Readers role requirement) - <https://learn.microsoft.com/azure/azure-sql/database/authentication-aad-configure>
4. Configure and manage Microsoft Entra authentication with Azure SQL - "Create Microsoft Entra principals in SQL" (`CREATE USER ... FROM EXTERNAL PROVIDER` syntax) - <https://learn.microsoft.com/azure/azure-sql/database/authentication-aad-configure#create-contained-users-mapped-to-azure-ad-identities>
5. Check Azure data source readiness to register and scan in Microsoft Purview - Azure SQL Managed Instance (AzureSQLMI) network/NSG/ProxyOverride checklist - <https://learn.microsoft.com/purview/data-map-data-sources-check-azure-readiness>
6. AzureSqlDatabaseManagedInstanceDataSource (Data Sources - Create Or Replace REST reference, API version 2023-09-01) - <https://learn.microsoft.com/rest/api/purview/scanningdataplane/data-sources/create-or-replace>
7. AzureSqlDatabaseManagedInstanceMsiScan / AzureSqlDatabaseManagedInstanceMsiScanProperties (Scans - Create Or Replace REST reference, API version 2023-09-01) - <https://learn.microsoft.com/rest/api/purview/scanningdataplane/scans/create-or-replace>
8. New-AzPurviewAzureSqlDatabaseManagedInstanceDataSourceObject (Az.Purview PowerShell module - confirms the `tcp:<fqdn>,<port>` ServerEndpoint format via its own worked example) - <https://learn.microsoft.com/powershell/module/az.purview/new-azpurviewazuresqldatabasemanagedinstancedatasourceobject>
9. New-AzPurviewAzureSqlDatabaseManagedInstanceMsiScanObject (Az.Purview PowerShell module - confirms `ScanRulesetName 'AzureSqlDatabaseManagedInstance'` via its own worked example) - <https://learn.microsoft.com/powershell/module/az.purview/new-azpurviewazuresqldatabasemanagedinstancemsiscanobject>
10. Monitor Data Map population in Microsoft Purview (scan run statuses, 90-day run-history retention) - <https://learn.microsoft.com/purview/data-map-scan-run-monitor-population>
11. Triggers - Create Or Replace REST API reference (API version 2023-09-01, worked example confirming the trigger body shape and the `triggers/default` path) - <https://learn.microsoft.com/rest/api/purview/scanningdataplane/triggers/create-or-replace>
12. Scan Result - Run Scan REST API reference (API version 2023-09-01; confirms the `POST .../scans/{name}:run?runId=...` action-style shape) and Scan Result - List Scan History (confirms the nested `discoveryExecutionDetails.statistics.assets` shape) - <https://learn.microsoft.com/rest/api/purview/scanningdataplane/scan-result/run-scan> and <https://learn.microsoft.com/rest/api/purview/scanningdataplane/scan-result/list-scan-history>
13. Connect to and manage an Azure SQL Managed Instance in Microsoft Purview - "System or user assigned managed identity to register" (private-endpoint managed-identity limitation) - <https://learn.microsoft.com/purview/register-scan-azure-sql-managed-instance#register>
14. Az.Purview PowerShell module reference (`Remove-AzPurviewDataSource`, `Remove-AzPurviewScan`) - <https://learn.microsoft.com/powershell/module/az.purview/>
15. Data governance roles and permissions in Microsoft Purview (classic Data Map role vocabulary) - <https://learn.microsoft.com/purview/data-gov-classic-permissions>
16. *Scan Azure SQL Database and Classify Sensitive Columns* - the sibling scenario this fragment extends; see its this page and the design notes for the shared reasoning not repeated here.
17. Microsoft Purview (formerly Azure Purview) deployment checklist - item 16, "Grant Azure RBAC Reader role to Microsoft Purview MSI at data sources' Subscriptions" (lists Azure SQL Managed Instance among the applicable source types, scoped to the subscription) - <https://learn.microsoft.com/purview/legacy/tutorial-azure-purview-checklist>; cross-checked against Check Azure data source readiness to register and scan in Microsoft Purview, whose Managed-Instance-specific check list has no RBAC/Reader item - <https://learn.microsoft.com/purview/data-map-data-sources-check-azure-readiness#more-information>

> Re-verify all links, API versions, and the default public-endpoint port against current Microsoft
> Learn before a customer-facing deployment - the Data Map REST surface is explicitly called out by
> Microsoft as evolving, and the remaining VERIFY item in the known limitations should be closed against a pilot tenant
> first.