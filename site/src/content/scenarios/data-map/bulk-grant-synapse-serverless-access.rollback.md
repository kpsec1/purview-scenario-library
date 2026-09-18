---
part: "rollback"
parent: "data-map/bulk-grant-synapse-serverless-access"
---
## Recommended sequence

This scenario only grants read (`db_datareader`) access - rollback is a straightforward revoke, staged
so you can pause after removing database-level access without also removing the server-level login (in
case other databases still need it).

### Stage 1 — Remove `db_datareader` membership for specific databases (keep the login)

Run against each database to revoke, using an operator identity with Synapse Administrator privilege
(the same identity class the deploy script's `-AppId` requires):

```sql
ALTER ROLE db_datareader DROP MEMBER [<PrincipalName>];
```

The contained database user itself is left in place (harmless with no role membership); drop it too if
a full per-database cleanup is wanted:

```sql
DROP USER [<PrincipalName>];
```

Use this stage for: narrowing scope after a database is decommissioned or moved out of the parent
scenario's scan target, without affecting the other databases this scenario granted access to.

### Stage 2 — Remove the server-level login (only after every database's user/role has been dropped)

```sql
-- Run against master. Confirm no other database still has a user mapped to this login first -
-- dropping a login with dependent database users elsewhere leaves those users "orphaned"
-- (present but unusable), the same orphaned-user hazard any SQL Server login removal carries.
DROP LOGIN [<PrincipalName>];
```

**Before running this**, confirm via the query in `README.md` §7 check 2 (across every database the
principal might have been granted in - not just the ones this run of the deploy script touched) that no
database still references this login. If the parent scenario's scan (or any other consumer) still
depends on this principal's access anywhere, do not drop the login.

### Verification after rollback

```powershell
./validate/Test-SynapseServerlessDatabaseAccess.ps1 `
    -ServerlessSqlEndpoint 'ws-contoso-prod-ondemand.sql.azuresynapse.net' `
    -PrincipalName 'contoso-purview' -TenantId $TenantId -AppId $ReaderAppId -ClientSecret $ReaderClientSecret
```

Expect `[FAIL]` for every database whose access was revoked (and, if Stage 2 was also run, `[FAIL]` on
the server-level login check too) - a full `[FAIL]` sweep confirms complete rollback.

## What rollback does **not** undo

- **Any Data Map assets or classifications already ingested** by the parent scenario's scan while this
  scenario's grants were in place. Revoking read access here doesn't retroactively un-classify anything
  already in the catalog - same behavior as the parent scenario's own rollback.
- **The operator identity's own Synapse Administrator role assignment** - this scenario never creates
  that (a documented prerequisite, `README.md` §3), so rollback doesn't touch it either. Revoke it
  separately via Azure Synapse's own RBAC management if a full teardown of the operator identity itself
  is intended.
- **The workspace firewall setting** - unchanged by this scenario in either direction.
