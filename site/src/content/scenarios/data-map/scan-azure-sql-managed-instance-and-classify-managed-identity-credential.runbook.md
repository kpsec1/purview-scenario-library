---
part: "runbook"
parent: "data-map/scan-azure-sql-managed-instance-and-classify-managed-identity-credential"
---
## Implementation steps

### Portal path (for a first manual walkthrough / to validate intent before scripting)

1. Complete *Scan Credentials: Remaining Kinds (Account Key, Role ARN, Consumer Key, Delegated Auth, User-Assigned Managed Identity)*'s portal or script path for a
   `ManagedIdentity` credential first - this requires a UAMI already added under the Purview
   account's **Managed identities** blade.
2. In Azure SQL Managed Instance, run the T-SQL grant against the target database, using the UAMI's
   **exact managed identity name** as `[Username]`:
   ```sql
   CREATE USER [Username] FROM EXTERNAL PROVIDER
   GO
   EXEC sp_addrolemember 'db_datareader', [Username]
   GO
   ```
. No separate Azure IAM role assignment applies - see the known limitations for the grounding.
3. Back in the Purview portal, open the base scenario's already-registered scan and select **Edit**.
   Under **Credential**, switch from the system-assigned managed identity to the UAMI, select **Test
   connection**, then **Save**.
4. Re-run (or wait for the next scheduled trigger) and confirm the scan still completes
   successfully under the new identity.

### Script path (idempotent, parameterized, dry-run capable)

```powershell
# 0. Prerequisite: build the ManagedIdentity credential first (if not already done)
../scan-credential-remaining-kinds/deploy/New-PurviewScanCredentialExtended.ps1 `
    -PurviewAccountName 'contoso-purview' -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
    -CredentialName 'mi-contoso-uami' -CredentialType ManagedIdentity `
    -PrincipalId $UamiPrincipalId -ResourceId $UamiResourceId

# 1. Dry run first
./deploy/New-AzureSqlManagedInstanceManagedIdentityCredentialScan.ps1 `
    -PurviewAccountName 'contoso-purview' -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
    -DataSourceName 'mi-contoso-prod-customerdb' -CredentialReferenceName 'mi-contoso-uami' -WhatIf

# 2. Reconcile for real
./deploy/New-AzureSqlManagedInstanceManagedIdentityCredentialScan.ps1 `
    -PurviewAccountName 'contoso-purview' -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
    -DataSourceName 'mi-contoso-prod-customerdb' -CredentialReferenceName 'mi-contoso-uami'

# 3. Reconcile and immediately prove the new identity works
./deploy/New-AzureSqlManagedInstanceManagedIdentityCredentialScan.ps1 `
    -PurviewAccountName 'contoso-purview' -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
    -DataSourceName 'mi-contoso-prod-customerdb' -CredentialReferenceName 'mi-contoso-uami' -RunNow

# 4. Validate
./validate/Test-AzureSqlManagedInstanceManagedIdentityCredentialScan.ps1 `
    -PurviewAccountName 'contoso-purview' -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
    -DataSourceName 'mi-contoso-prod-customerdb' -ExpectedCredentialReferenceName 'mi-contoso-uami' `
    -CheckCredentialObject
```

Same REST surface as the base scenario - Microsoft Purview Data Map / Data Governance REST API,
automation surface 4 per [Automation surface, section 1](/docs/automation-surface/#1-five-automation-surfaces-not-one-read-this-first).

## Configuration reference

| Setting | Value this scenario uses | Notes |
|---|---|---|
| Scan `kind` (before) | `AzureSqlDatabaseManagedInstanceMsi` | SAMI-authenticated - the base scenario's default |
| Scan `kind` (after) | `AzureSqlDatabaseManagedInstanceCredential` | Confirmed via direct fetch of the Scans - Create Or Replace REST reference - a distinct enum member from the Database sibling's `AzureSqlDatabaseCredential` |
| `properties.credential.credentialType` | `ManagedIdentity` | Same shared `CredentialType` enum as the Database sibling |
| `properties.credential.referenceName` | Name of a pre-existing `ManagedIdentity`-kind credential object | Built via *Scan Credentials: Remaining Kinds (Account Key, Role ARN, Consumer Key, Delegated Auth, User-Assigned Managed Identity)* - see the prerequisites |
| Properties preserved unchanged from the existing scan | `databaseName`, `serverEndpoint` (the `tcp:<fqdn>,<port>` form), `collection`, `scanRulesetName`, `scanRulesetType` | GET-then-PUT reconciliation - see the design notes goal 1 |
| `-SkipCredentialPrecheck` | Off by default | Skips the read-only GET against the credential object before reconciling |
| `-Force` | Off by default | Required to proceed past a precheck that found the credential object but confirmed it is **not** kind `ManagedIdentity` |
| `-RunNow` | Off by default | Starts an immediate scan run to prove the new identity actually authenticates |
| API version pinned by this script | `2023-09-01` | Matches the base scenario |

Full cmdlet/REST-body grounding: `deploy/New-AzureSqlManagedInstanceManagedIdentityCredentialScan.ps1`'s
inline comments and `.NOTES` block.

## Operations and tuning

All of the base scenario's operations and tuning KPI and incident-response guidance applies unchanged - this scenario
only changes *which identity* authenticates the same scan. Two additions specific to the UAMI path,
identical to the Database sibling's own disclosure (*UAMI Credential for the Azure SQL Database Scan* (operations and tuning)):

- **No Key Vault-side detective control.** `ManagedIdentity` carries no secret - the only detective
  control is *Scan Credential Inventory & Drift Report*'s estate-wide drift report.
- **No detective control for the scan's own credential reference drifting**, as distinct from the
  credential object's content drifting - the inventory report monitors the latter, not which scan
  references which credential. The only mitigation is re-running
  `validate/Test-AzureSqlManagedInstanceManagedIdentityCredentialScan.ps1
  -ExpectedCredentialReferenceName` on a schedule.
- **Adopt selectively.** Same phased-rollout recommendation as the Database sibling - start with the
  highest-sensitivity Managed Instance databases, not a blanket switch for every registered scan.

## Rollback and decommission

See the rollback runbook for the full staged procedure. Quick reference:
`./deploy/Remove-AzureSqlManagedInstanceManagedIdentityCredentialScan.ps1` reverts the scan's `kind`
back to `AzureSqlDatabaseManagedInstanceMsi` (SAMI), preserving every other scan property. It does
not delete the UAMI, its grants, or the `ManagedIdentity` credential object.

## References

1. Connect to and manage an Azure SQL Managed Instance in Microsoft Purview - <https://learn.microsoft.com/purview/register-scan-azure-sql-managed-instance>
2. Microsoft Purview billing models (PAYG for Data Map) - <https://learn.microsoft.com/purview/purview-billing-models>
3. Tutorial: Authenticate for Microsoft Purview data-plane APIs - <https://learn.microsoft.com/purview/data-gov-api-rest-data-plane>
4. Connect to and manage an Azure SQL Managed Instance in Microsoft Purview - "Register" / authentication section (System or user-assigned managed identity registration; T-SQL grant using the exact managed identity name; confirms "Either managed identity will need permission to get metadata for the database, schemas and tables, and to query the tables for classification") - <https://learn.microsoft.com/purview/register-scan-azure-sql-managed-instance#register>
5. Scans - Create Or Replace REST API reference (API version 2023-09-01; confirmed `AzureSqlDatabaseManagedInstanceCredentialScanProperties`, identical field names to the Database sibling's properties object; the shared `CredentialType` enum including `ManagedIdentity`) - <https://learn.microsoft.com/rest/api/purview/scanningdataplane/scans/create-or-replace>
6. Scans and ingestion in Data Map - <https://learn.microsoft.com/purview/data-map-scan-ingestion>
7. *Scan Azure SQL Managed Instance and Classify Sensitive Columns* - the base scenario this fragment extends (data source registration, SAMI defaults, the Managed-Instance-specific prerequisite deltas from the Database sibling this scenario's own table is additive to).
8. Data governance best practices for security - Credential management (Microsoft's credential priority order) - <https://learn.microsoft.com/purview/data-gov-classic-security-best-practices>
9. Credentials for source authentication in Microsoft Purview Data Map - "Create a user-assigned managed identity" - <https://learn.microsoft.com/purview/data-map-data-scan-credentials#create-a-user-assigned-managed-identity>
10. Credential - Get / List REST API reference - <https://learn.microsoft.com/rest/api/purview/scanningdataplane/credential>
11. *Scan Credentials: Remaining Kinds (Account Key, Role ARN, Consumer Key, Delegated Auth, User-Assigned Managed Identity)* - the `ManagedIdentity` credential kind this scenario consumes.
12. *UAMI Credential for the Azure SQL Database Scan* - the Azure SQL Database sibling this scenario ports the reconciliation pattern from; see the design notes for the confirmed differences.

> Re-verify all links, API versions, and REST body shapes against current Microsoft Learn before a
> customer-facing deployment. The `ManagedIdentity` credential kind remains Microsoft-labeled
> Preview as of this writing - see the known limitations.