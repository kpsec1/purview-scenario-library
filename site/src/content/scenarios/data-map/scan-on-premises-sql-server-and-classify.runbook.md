---
part: "runbook"
parent: "data-map/scan-on-premises-sql-server-and-classify"
---
## Implementation steps

### Portal path (for a first manual walkthrough / to validate intent before scripting)

1. **Set up the self-hosted integration runtime.** In the Microsoft Purview portal (or the classic
   governance portal) → **Data Map** → **Integration runtimes** → **+ New** → **Self-Hosted** → name
   it → **Create**. Copy the authentication key shown, then download and install the [self-hosted
   integration runtime](https://go.microsoft.com/fwlink/?linkid=2246619) on a Windows host with
   network access to the target SQL Server, and paste the key into the installer's "Register
   Integration Runtime (Self-hosted)" screen. Confirm the node shows **Running**.
2. **Configure authentication.** In SQL Server Management Studio (SSMS), confirm **Server
   Properties → Security → Server authentication** allows the method you intend (SQL Server and
   Windows Authentication mode for SQL Authentication; either mode works for Windows Authentication).
   A change here requires restarting the SQL Server instance and Agent.
3. **Create a login and user.** In SSMS, create a new login (Windows or SQL) with **public** server
   role, then under **User mapping** select every database to scan and grant the **db\_datareader**
   database role. This account needs access to the `master` database because `sys.databases` lives
   there. Microsoft publishes a ready-made T-SQL script for this exact step. If SQL Authentication, set a permanent password on the new login (the initial
   password must be changed immediately per SQL Server's policy).
4. **Store the password and create the Purview credential.** In Azure Key Vault → **Secrets** → **+
   Generate/Import**, store the login's password. Connect that Key Vault to Purview if not already
   connected, then in Purview → **Credentials** → **+ New**, select **SQL authentication** (or
   **Windows authentication**), and reference the Key Vault secret.
5. Back in the Purview portal, **Data Map** → **Data sources** → **Register** → **SQL Server** →
   **Continue**. Provide a friendly name and the server endpoint (hostname, IP, or
   `<host>\<namedInstance>`) → **Finish**.
6. Select the registered source → **New scan** → choose the self-hosted integration runtime you
   registered in step 1 → select the credential from step 4 → **Test connection** → **Continue**.
7. Enter the database name to scope the scan (or leave blank to scan the whole instance), choose a
   scan rule set (system default, this scenario's default), choose a scan trigger, and **Save and
   run**.
8. After the scan completes, browse the classified assets in **Unified Catalog** to confirm columns
   matching your target SITs are tagged.

### Script path (idempotent, parameterized, dry-run capable)

```powershell
# 1. Deploy (dry run first - reports every REST call that would be made, changes nothing)
./deploy/New-OnPremisesSqlServerDataMapScan.ps1 `
    -PurviewAccountName 'contoso-purview' `
    -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
    -IntegrationRuntimeName 'shir-onprem-sql' `
    -ServerEndpoint 'sql01.contoso.local' -DatabaseName 'CustomerDB' `
    -CollectionReferenceName 'a1b2c' -CredentialReferenceName 'onprem-sql-svc-account' `
    -WhatIf

# 2. Deploy for real - creates the integration runtime resource (prints its auth key ONCE),
#    registers the source and the scan. Does not run it yet.
./deploy/New-OnPremisesSqlServerDataMapScan.ps1 `
    -PurviewAccountName 'contoso-purview' `
    -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
    -IntegrationRuntimeName 'shir-onprem-sql' `
    -ServerEndpoint 'sql01.contoso.local' -DatabaseName 'CustomerDB' `
    -CollectionReferenceName 'a1b2c' -CredentialReferenceName 'onprem-sql-svc-account'

# --- Manual, out-of-band, between steps 2 and 3 ---
#   a. Install the SHIR software on a Windows host with network access to sql01.contoso.local,
#      pasting in the auth key step 2 printed. Confirm the node shows "Running" in the portal.
#   b. Create the SQL/Windows login + db_datareader grant, store its password in Key Vault, and
#      create the 'onprem-sql-svc-account' credential object in Purview (README.md Section 5,
#      steps 2-4). None of this is scriptable from this repo's automation identity - see Section 11.

# 3. Once (a) and (b) above are confirmed done, add a weekly recurring trigger and kick off an
#    immediate full scan. -SkipIntegrationRuntimeAuthKey avoids rotating the key the SHIR node
#    already registered with.
./deploy/New-OnPremisesSqlServerDataMapScan.ps1 `
    -PurviewAccountName 'contoso-purview' `
    -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
    -IntegrationRuntimeName 'shir-onprem-sql' -SkipIntegrationRuntimeAuthKey `
    -ServerEndpoint 'sql01.contoso.local' -DatabaseName 'CustomerDB' `
    -CollectionReferenceName 'a1b2c' -CredentialReferenceName 'onprem-sql-svc-account' `
    -RecurrenceFrequency Week -RunNow

# 4. Validate
./validate/Test-OnPremisesSqlServerDataMapScan.ps1 `
    -PurviewAccountName 'contoso-purview' -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
    -DataSourceName 'sql01-contoso-local' -IntegrationRuntimeName 'shir-onprem-sql'
```

The deploy script uses the **Microsoft Purview Data Map / Data Governance REST API** - automation
surface 4 per [Automation surface, section 1](/docs/automation-surface/#1-five-automation-surfaces-not-one-read-this-first). Unlike the three Azure sibling scenarios, step 2 above
*does* script one genuine out-of-band prerequisite (the integration runtime resource + auth key) -
only the physical software install (a) and the credential object (b) remain manual; see the design notes.

## Configuration reference

| Setting | Value this scenario uses | Notes |
|---|---|---|
| Data source `kind` | `SqlServerDatabase` | Distinct from all three Azure siblings' `kind` values |
| Data source `properties` | Only `serverEndpoint` + `collection` set | `resourceGroup`/`resourceName`/`subscriptionId`/`location` deliberately omitted - confirmed via Microsoft's own `New-AzPurviewSqlServerDatabaseDataSourceObject` worked example, which leaves them blank because no Azure resource backs an on-premises instance |
| Scan `kind` | `SqlServerDatabaseCredential` | The **only** scan kind for this source type - no `...Msi` managed-identity variant exists |
| `serverEndpoint` format | Hostname, IP address, or `<host>\<namedInstance>` | Confirmed via Microsoft's own worked PowerShell example (a bare IP address, `'10.1.2.1'`); this script passes the value through unmodified |
| `connectedVia` | `{ "integrationRuntimeType": "SelfHosted", "referenceName": "<IntegrationRuntimeName>" }` | **Required** for this source type - confirmed directly from the `ConnectedVia` REST definition |
| `credential` | `{ "credentialType": "SqlAuth", "referenceName": "<CredentialReferenceName>" }` | `credentialType` confirmed via Microsoft's own worked PowerShell example for this exact scan kind; `SqlAuth` is this script's default (see the known limitations for the Windows-Authentication VERIFY) |
| Integration runtime `kind` | `SelfHosted` | The only kind this scenario creates - `Managed` (Azure-autoresolved) needs no resource object at all and is irrelevant here |
| Collection reference | `{ "referenceName": "<5-char collection ID>", "type": "CollectionReference" }` | Same shape as every Data Map sibling scenario - read the ID from the collection's URL in the portal, not its friendly name |
| Scan rule set (this scenario's default) | `scanRulesetName: "SqlServerDatabase"`, `scanRulesetType: "System"` | Confirmed via the System Scan Rulesets - Get REST reference's own worked example, which returns `"name": "AzureStorage"` for `kind: "AzureStorage"` - establishing that a system scan ruleset's `name` is always identical to its `kind`; `SqlServerDatabase` is a documented `kind`/`DataSourceType` value in that same schema |
| Scan level | `Full` (first run) → `Incremental` (subsequent scheduled runs) | Same pattern as every sibling scenario |
| Recurring trigger | Optional; `RecurrenceFrequency`/`RecurrenceInterval` parameters | Trigger resource name is always `default` - same confirmed shape every sibling scenario uses |
| Run-scan call shape | `POST .../scans/{name}:run?runId={guid}&scanLevel={level}` | Reused unchanged from *Scan Azure SQL Managed Instance and Classify Sensitive Columns*'s directly-confirmed shape (source-type-agnostic Scan Result operation) |
| API version pinned by this script | `2023-09-01` | Confirmed current for the Integration Runtimes (Create Or Replace, Regenerate Auth Key), Data Sources, and Scans REST operations this script uses, via direct fetch of each operation's own canonical reference page - see the known limitations |

Full cmdlet/REST-body grounding: `deploy/New-OnPremisesSqlServerDataMapScan.ps1` inline comments and
its `.NOTES` block cite the exact Microsoft Learn reference pages.

## Operations and tuning

Same core KPIs and no-alerting-for-Data-Map-scans posture as the three Azure sibling scenarios - see
*Scan Azure SQL Database and Classify Sensitive Columns* (operations and tuning) for the full text, not repeated here. Two
on-premises-specific additions:

**Incident-response addition - on-premises-specific failure causes**, in order of likelihood, ahead of
any cause shared with the Azure siblings: (a) the **SHIR node isn't running** - the single most common
cause of an on-premises scan failing when the Azure siblings' equivalent scan would have succeeded;
check the Nodes tab first, every time (the validation steps check 2); (b) the **stored credential's password rotated**
without the Purview credential object being updated - SQL/Windows login password rotation policies
rarely know Purview depends on them; (c) a **network/firewall change** blocked the SHIR host from
reaching either the SQL Server instance or the Purview service endpoints (both directions matter - the
SHIR calls out to Purview over HTTPS/Azure Relay, and separately connects inbound-from-the-SHIR's-perspective to the SQL Server); (d) the SHIR software **expired** - each version expires one year after
release, with warnings starting 90 days out, and auto-update requires the node to be online to receive
it.

**Review cadence:** same monthly/quarterly rhythm as the Azure siblings (operations and tuning there), plus: (a) confirm
the SHIR node's **Version** tab isn't approaching its one-year expiration; (b) if multiple SHIR nodes
share this integration runtime for high availability, confirm all are healthy, not just one (a single
healthy node keeps the scan running and can mask a partial outage); (c) re-run
`validate/Test-OnPremisesSqlServerDataMapScan.ps1` after any credential-object update; (d) confirm the
SHIR host's owning team (infrastructure/on-prem-ops, per the prerequisites) still has this dependency on their own
patching/decommissioning checklist - a host repurposed or retired without anyone remembering Purview
depends on it silently breaks every scan wired to it, with no alert from Purview itself.

**Blast-radius note:** every data source whose scan names the same `-IntegrationRuntimeName` is only as
trustworthy as that one SHIR host. If the host is compromised, an attacker with access to it can see
(or interfere with) every scan job Purview dispatches to it - not just this scenario's. For a tenant
running multiple on-premises sources at different sensitivity tiers, consider dedicating separate SHIR
hosts per tier rather than sharing one runtime across all of them, the same way network segmentation
would apply to any other shared administrative chokepoint.

**Downstream use:** same as every sibling scenario - this scenario stops at "classify and make
visible," feeding *Information Protection*, *DLP*, and any future Data Estate
Insights reporting fragment.

## Rollback and decommission

See the rollback runbook for the full staged procedure (disable trigger → delete scan → delete data source →
optionally delete the integration runtime resource → optionally decommission the SHIR host) -
structurally an extension of the Azure siblings' rollback with one extra stage. Quick reference:
`./deploy/Remove-OnPremisesSqlServerDataMapScan.ps1` removes the scan and its trigger (reversible by
re-running the deploy script); add `-RemoveDataSource` to also delete the data source registration,
and `-RemoveIntegrationRuntime -IntegrationRuntimeName <name>` to also delete the integration runtime
resource (only if no other scan still uses it). Rolling back the Purview-side objects does **not**
uninstall the SHIR software from its host, revert the SQL/Windows login and grant, delete the Key Vault
secret, or remove the Purview credential object - see the rollback runbook.

## References

1. Discover and govern Azure SQL Database in Microsoft Purview (shared regulatory-driver framing) - <https://learn.microsoft.com/purview/register-scan-azure-sql-database>
2. Connect to and manage an on-premises SQL server instance in Microsoft Purview - "Prerequisites" (enterprise version requirement, Data Source Administrator + Data Reader roles) - <https://learn.microsoft.com/purview/register-scan-on-premises-sql-server#prerequisites>
3. Connect to and manage an on-premises SQL server instance in Microsoft Purview - "Register" and "Scan" (mandatory SHIR, SQL Server 2005+/no Express LocalDB, authentication configuration, login/user creation, master database access requirement) - <https://learn.microsoft.com/purview/register-scan-on-premises-sql-server>
4. Credentials for source authentication in Microsoft Purview Data Map - "Create a new credential" (SQL/Windows authentication, Key Vault-backed secrets) - <https://learn.microsoft.com/purview/data-map-data-scan-credentials#create-a-new-credential>
5. Create and manage a self-hosted integration runtime - "Setting up a self-hosted integration runtime" (portal creation flow, auth key, download/install/register steps, node status) - <https://learn.microsoft.com/purview/data-map-integration-runtime-self-hosted#setting-up-a-self-hosted-integration-runtime>
6. Connect to and manage an on-premises SQL server instance in Microsoft Purview - "Creating a new login and user" (T-SQL grant script reference) - <https://learn.microsoft.com/purview/register-scan-on-premises-sql-server#scan>; T-SQL sample: <https://github.com/Azure/Purview-Samples/blob/master/TSQL-Code-Permissions/grant-access-to-on-prem-sql-databases.sql>
7. SqlServerDatabaseDataSource / SqlServerDatabaseProperties (Data Sources - Create Or Replace REST reference, API version 2023-09-01) - <https://learn.microsoft.com/rest/api/purview/scanningdataplane/data-sources/create-or-replace>
8. New-AzPurviewSqlServerDatabaseDataSourceObject (Az.Purview PowerShell module - worked example confirms resourceGroup/resourceName/subscriptionId/location are left unset) - <https://learn.microsoft.com/powershell/module/az.purview/new-azpurviewsqlserverdatabasedatasourceobject>
9. New-AzPurviewSqlServerDatabaseCredentialScanObject (Az.Purview PowerShell module - worked example confirms Kind, CredentialType 'SqlAuth', ServerEndpoint, ConnectedViaReferenceName) - <https://learn.microsoft.com/powershell/module/az.purview/new-azpurviewsqlserverdatabasecredentialscanobject>
10. ConnectedVia / CredentialReference / CredentialType definitions (Data Sources - Create Or Replace REST reference, shared data-plane definitions, API version 2023-09-01) - <https://learn.microsoft.com/rest/api/purview/scanningdataplane/data-sources/create-or-replace>
11. Integration Runtimes - Create Or Replace and Integration Runtimes - Regenerate Auth Key (REST reference, API version 2023-09-01, full worked HTTP examples) - <https://learn.microsoft.com/rest/api/purview/scanningdataplane/integration-runtimes/create-or-replace> and <https://learn.microsoft.com/rest/api/purview/scanningdataplane/integration-runtimes/regenerate-auth-key>
12. Monitor Data Map population in Microsoft Purview (scan run statuses, 90-day run-history retention) - <https://learn.microsoft.com/purview/data-map-scan-run-monitor-population>
13. Disaster recovery and migration best practices for Microsoft Purview data governance (classic) - confirms no REST API exists to extract/create credentials, and that SHIR physical registration "must be done manually inside the SHIRs' hosts" - <https://learn.microsoft.com/purview/data-gov-best-practices-disaster-recovery-migration>
14. System Scan Rulesets - Get (REST reference, API version 2023-09-01 - worked example confirms a system scan ruleset's `name` equals its `kind`, e.g. `kind: "AzureStorage"` → `name: "AzureStorage"`, `id: "systemscanrulesets/AzureStorage"`; `SqlServerDatabase` is a documented `kind`/`DataSourceType` value in the same schema) - <https://learn.microsoft.com/rest/api/purview/scanningdataplane/system-scan-rulesets/get>
15. Kubernetes supported self-hosted data integration runtime for on-premises data sources (preview) - the distinct, containerized alternative this scenario does not cover - <https://learn.microsoft.com/purview/unified-catalog-data-integration-runtime-kubernetes>
16. Data governance roles and permissions in Microsoft Purview (classic Data Map role vocabulary) - <https://learn.microsoft.com/purview/data-gov-classic-permissions>
17. *Scan Azure SQL Database and Classify Sensitive Columns*, `scan-azure-sql-managed-instance-and-classify/`, `scan-azure-synapse-and-classify/` - the three sibling scenarios this fragment extends; see their this page/the design notes for shared reasoning not repeated here.

> Re-verify all links and the one remaining VERIFY item in the known limitations (Windows Authentication's
> `CredentialType` value) against current Microsoft Learn before a customer-facing deployment - the
> Data Map REST surface is explicitly called out by Microsoft as evolving. The system scan rule set
> name VERIFY was closed 2026-09-26.