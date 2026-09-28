---
part: "runbook"
parent: "data-map/bulk-grant-synapse-serverless-access"
---
## Implementation steps

### Portal path (for a first manual walkthrough / to validate intent before scripting)

This scenario automates a bulk version of Microsoft's own documented manual procedure - see
*Scan Azure Synapse Analytics Workspace and Classify Sensitive Columns* (the implementation steps) steps 3c-4 for the equivalent single-database portal
walkthrough (Synapse Studio → **Data** → a database's **...** menu → new SQL script). This scenario's
script exists specifically to replace repeating that walkthrough once per database.

### Script path (idempotent, parameterized, dry-run capable)

```powershell
# 1. Dry run - reports every login/user/role statement that would run, changes nothing
./deploy/Grant-SynapseServerlessDatabaseAccess.ps1 `
    -ServerlessSqlEndpoint 'ws-contoso-prod-ondemand.sql.azuresynapse.net' `
    -PrincipalName 'contoso-purview' `
    -TenantId $TenantId -AppId $OperatorAppId -ClientSecret $OperatorClientSecret `
    -WhatIf

# 2. Apply for real, across every serverless database in the workspace
./deploy/Grant-SynapseServerlessDatabaseAccess.ps1 `
    -ServerlessSqlEndpoint 'ws-contoso-prod-ondemand.sql.azuresynapse.net' `
    -PrincipalName 'contoso-purview' `
    -TenantId $TenantId -AppId $OperatorAppId -ClientSecret $OperatorClientSecret

# 3. Apply, excluding a known read-only Spark/Lake-replicated database
./deploy/Grant-SynapseServerlessDatabaseAccess.ps1 `
    -ServerlessSqlEndpoint 'ws-contoso-prod-ondemand.sql.azuresynapse.net' `
    -PrincipalName 'contoso-purview' `
    -TenantId $TenantId -AppId $OperatorAppId -ClientSecret $OperatorClientSecret `
    -ExcludeDatabase 'spark_replica_db'

# 4. Validate (lower-privileged, read-only identity)
./validate/Test-SynapseServerlessDatabaseAccess.ps1 `
    -ServerlessSqlEndpoint 'ws-contoso-prod-ondemand.sql.azuresynapse.net' `
    -PrincipalName 'contoso-purview' `
    -TenantId $TenantId -AppId $ReaderAppId -ClientSecret $ReaderClientSecret
```

Run this scenario's deploy script **before** `scan-azure-synapse-and-classify/deploy/
New-AzureSynapseDataMapScan.ps1 -RunNow` (or before its recurring trigger's next fire) - the parent
scenario's scan silently returns zero serverless assets for any database this scenario hasn't yet
granted access to, per that scenario's own operations and tuning incident-response cause (e).

> **Always run step 1 (`-WhatIf`) first and read the printed database count/list before step 2.**
> The manual, one-database-at-a-time portal walkthrough this script replaces has built-in friction
> that forces a human to look at each database before granting it access; a single bulk run against
> the wrong `-ServerlessSqlEndpoint`, or without `-ExcludeDatabase` for databases that shouldn't be
> in scope, removes that friction and can grant read access across every database in a workspace in
> one shot (flagged as a Red Team finding in the review notes). For a workspace that mixes
> sensitivity levels across databases, prefer an explicit `-Database` allow-list over the
> full-workspace default until you've confirmed the scope is what you intend.

## Configuration reference

| Setting | Value this scenario uses | Notes |
|---|---|---|
| Login creation | **Once**, `CREATE LOGIN [...] FROM EXTERNAL PROVIDER`, run against `master` | Corrected from the parent scenario's per-database framing - see the design notes |
| Per-database user | `CREATE USER [...] FOR LOGIN [...];` | Skipped if the user already exists (idempotent) |
| Per-database role membership | `ALTER ROLE db_datareader ADD MEMBER [...];` | Skipped if already a member (idempotent) |
| Database enumeration | `SELECT name FROM sys.databases WHERE name NOT IN ('master')` against the built-in pool's `master` | Confirmed via Microsoft's own worked example, see the design notes; override with `-Database` |
| Connection mechanism | `Invoke-Sqlcmd -ServerInstance <endpoint> -Database <db> -AccessToken <token>` | Confirmed via `Invoke-Sqlcmd`'s own "Example 12: Connect to Azure SQL Database (or Managed Instance) using a Service Principal" reference |
| Token resource/audience | `https://database.windows.net/` | Distinct from the parent scenario's `https://purview.azure.net` - this script never calls the Purview control plane |
| Login-existence check | `SELECT COUNT(*) FROM sys.server_principals WHERE name = @p AND type IN ('E','X')` | `'E'`/`'X'` are the external/Azure-AD server-principal type codes, per Microsoft's own troubleshooting-doc worked example |
| User/role-membership check | `sys.database_principals` joined to `sys.database_role_members` | Same join shape as Microsoft's own `register-scan-synapse-workspace` verification query, narrowed to the target principal |
| Untrusted-input handling | `-PrincipalName` validated by `ValidatePattern`, then bracket/literal-escaped before use in generated T-SQL | See both scripts' `.NOTES` |

## Operations and tuning

**When to run this scenario:** on first deployment of `scan-azure-synapse-and-classify/` against a
serverless-pool-bearing workspace, and again whenever a new serverless database is added to that
workspace (this script is safe to re-run against the whole workspace each time - already-granted
databases are skipped, only new ones are touched).

**KPI:** `Error` count in the deploy script's own result table, trending to zero. A persistent non-zero
count after excluding known read-only replicas indicates a database with some other, unexpected
access problem worth a direct look (e.g. the operator identity's Synapse Administrator role was revoked,
or the workspace firewall setting was reverted).

**Review cadence:** re-run alongside the parent scenario's own review cadence
(*Scan Azure Synapse Analytics Workspace and Classify Sensitive Columns* (operations and tuning)) - specifically, after any new serverless database is
added to the workspace, and after any database restore/recreate (which, per that scenario's own
incident-response cause (e), silently drops these grants).

**Downstream use:** feeds directly into `scan-azure-synapse-and-classify/`'s serverless scanning path -
this scenario produces no classification or catalog output of its own.

**Change-management note:** because one run can touch every database in a workspace, treat a `-WhatIf`
preview's printed target list as the artifact your change-approval process reviews - the same role a
single pull request diff plays for a code change - rather than approving "run the bulk-grant script"
as an undifferentiated one-line change request (flagged as a CISO finding in the review notes).

**Audit trail:** this script's own console output (the per-database result table) is not persisted
anywhere by default - redirect it to a transcript (`Start-Transcript`) or capture it in your pipeline's
own run log if you need a durable record of which run granted which database. The authoritative,
tamper-evident record of the actual `CREATE LOGIN`/`CREATE USER`/`ALTER ROLE` statements is Azure SQL/
Synapse's own **SQL auditing** (workspace **Auditing** blade → diagnostic logs), which this scenario
does not configure or verify - flagged as a Blue Team finding in the review notes and out of scope for this
fragment (a candidate for a future cross-cutting Data Map auditing scenario, not built here).

## Rollback and decommission

See the rollback runbook for the full procedure (revoke `db_datareader` membership per database, optionally
drop the server-level login). Quick reference: this scenario's deploy script has no corresponding
`Remove-*` script - revocation is a small enough, low-frequency operation that this fragment documents
it as direct T-SQL in the rollback runbook rather than shipping a third script; see that file for the exact
statements and staging.

## References

1. Connect to and manage Azure Synapse Analytics workspaces in Microsoft Purview (per-database
   `CREATE USER`/`ALTER ROLE`/verification-query T-SQL this scenario's per-database logic is modeled
   on) - <https://learn.microsoft.com/purview/register-scan-synapse-workspace>
2. Invoke-Sqlcmd (SqlServer PowerShell module reference - confirms the `-AccessToken`
   client-credentials connection pattern via its own "Example 12" worked example) - <https://learn.microsoft.com/powershell/module/sqlserver/invoke-sqlcmd>
3. Access lake databases using serverless SQL pool (confirms `SELECT * FROM sys.databases` as the
   documented way to enumerate databases visible to a serverless SQL pool, and the once-only
   `CREATE LOGIN` "Create workspace-level data reader" example) - <https://learn.microsoft.com/azure/synapse-analytics/metadata/database>
4. Troubleshoot serverless SQL pool in Azure Synapse Analytics (confirms `CREATE LOGIN` as a
   `master`-scoped, server-level statement, and the `sys.server_principals` login-existence query) - <https://learn.microsoft.com/azure/synapse-analytics/sql/resources-self-help-sql-on-demand>
5. Azure Synapse workspace access control overview (confirms the Synapse Administrator role's
   `db_owner` permission on the serverless pool and its authority to grant others access) - <https://learn.microsoft.com/azure/synapse-analytics/security/synapse-workspace-access-control-overview>
6. SQL Authentication in Azure Synapse Analytics (confirms bracket-quoted `CREATE LOGIN`/`CREATE USER`
   syntax forms for both SQL and Microsoft Entra-backed principals) - <https://learn.microsoft.com/azure/synapse-analytics/sql/sql-authentication>
7. *Scan Azure Synapse Analytics Workspace and Classify Sensitive Columns* - the parent scenario this one is a
   prerequisite-automation companion to; see its the prerequisites (the CISO-flagged cost note this
   scenario resolves) and the CISO review (finding 1).

> Re-verify all cmdlet parameters, T-SQL syntax, and RBAC role names against current Microsoft Learn
> before a customer-facing deployment. This build's `learn.microsoft.com` fetches succeeded directly
> (via the Microsoft Learn documentation tool) rather than needing the WebSearch-only fallback several
> earlier Data Map fragments in this library recorded.