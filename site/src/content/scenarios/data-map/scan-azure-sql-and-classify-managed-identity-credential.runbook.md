---
part: "runbook"
parent: "data-map/scan-azure-sql-and-classify-managed-identity-credential"
---
## Implementation steps

### Portal path (for a first manual walkthrough / to validate intent before scripting)

1. Complete *Scan Credentials: Remaining Kinds (Account Key, Role ARN, Consumer Key, Delegated Auth, User-Assigned Managed Identity)*'s portal or script path for a
   `ManagedIdentity` credential first - this requires a UAMI already added under the Purview
   account's **Managed identities** blade in the Azure portal.
2. In Azure SQL, run the T-SQL grant against the target database, using the UAMI's **exact managed
   identity name** as `[Username]`:
   ```sql
   CREATE USER [Username] FROM EXTERNAL PROVIDER
   GO
   EXEC sp_addrolemember 'db_datareader', [Username]
   GO
   ```
  
3. In the Azure portal, on the **SQL Server resource itself**, grant the **Reader** IAM role to the
   UAMI (select it by name in the same **Access control (IAM)** pane the base scenario's SAMI grant
   used).
4. Back in the Purview portal, open the base scenario's already-registered scan and select **Edit**.
   Under **Credential**, switch from the system-assigned managed identity to the UAMI, select **Test
   connection**, then **Save**.
5. Re-run (or wait for the next scheduled trigger) and confirm the scan still completes
   successfully under the new identity.

### Script path (idempotent, parameterized, dry-run capable)

```powershell
# 0. Prerequisite: build the ManagedIdentity credential first (if not already done)
../scan-credential-remaining-kinds/deploy/New-PurviewScanCredentialExtended.ps1 `
    -PurviewAccountName 'contoso-purview' -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
    -CredentialName 'sql-contoso-uami' -CredentialType ManagedIdentity `
    -PrincipalId $UamiPrincipalId -ResourceId $UamiResourceId

# 1. Dry run first - reports every REST call that would be made, changes nothing
./deploy/New-AzureSqlManagedIdentityCredentialScan.ps1 `
    -PurviewAccountName 'contoso-purview' -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
    -DataSourceName 'sql-contoso-prod-customerdb' -CredentialReferenceName 'sql-contoso-uami' -WhatIf

# 2. Reconcile for real
./deploy/New-AzureSqlManagedIdentityCredentialScan.ps1 `
    -PurviewAccountName 'contoso-purview' -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
    -DataSourceName 'sql-contoso-prod-customerdb' -CredentialReferenceName 'sql-contoso-uami'

# 3. Reconcile and immediately prove the new identity works
./deploy/New-AzureSqlManagedIdentityCredentialScan.ps1 `
    -PurviewAccountName 'contoso-purview' -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
    -DataSourceName 'sql-contoso-prod-customerdb' -CredentialReferenceName 'sql-contoso-uami' -RunNow

# 4. Validate
./validate/Test-AzureSqlManagedIdentityCredentialScan.ps1 `
    -PurviewAccountName 'contoso-purview' -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
    -DataSourceName 'sql-contoso-prod-customerdb' -ExpectedCredentialReferenceName 'sql-contoso-uami' `
    -CheckCredentialObject
```

Same REST surface as the base scenario - Microsoft Purview Data Map / Data Governance REST API,
automation surface 4 per [Automation surface, section 1](/docs/automation-surface/#1-five-automation-surfaces-not-one-read-this-first). Token acquisition follows
[Automation surface, section 3](/docs/automation-surface/#3-authentication-patterns---interactive-vs-unattended)'s client-credentials pattern.

## Configuration reference

| Setting | Value this scenario uses | Notes |
|---|---|---|
| Scan `kind` (before) | `AzureSqlDatabaseMsi` | SAMI-authenticated - the base scenario's default |
| Scan `kind` (after) | `AzureSqlDatabaseCredential` | Confirmed via direct fetch of the Scans - Create Or Replace REST reference |
| `properties.credential.credentialType` | `ManagedIdentity` | One of `CredentialType`'s eight documented enum values |
| `properties.credential.referenceName` | Name of a pre-existing `ManagedIdentity`-kind credential object | Built via *Scan Credentials: Remaining Kinds (Account Key, Role ARN, Consumer Key, Delegated Auth, User-Assigned Managed Identity)* - see the prerequisites |
| Properties preserved unchanged from the existing scan | `databaseName`, `serverEndpoint`, `collection`, `scanRulesetName`, `scanRulesetType` | GET-then-PUT reconciliation - see the design notes goal 1 |
| `-SkipCredentialPrecheck` | Off by default | Skips the read-only GET against the credential object before reconciling - use if `-AppId` cannot read the credential's collection. Does not suppress the hard stop below |
| `-Force` | Off by default | Required to proceed past a precheck that found the credential object but confirmed it is **not** kind `ManagedIdentity` - a deterministic misconfiguration, unlike an ambiguous 404, so it hard-stops by default |
| `-RunNow` | Off by default | Starts an immediate scan run to prove the new identity actually authenticates, not just that the object was accepted |
| API version pinned by this script | `2023-09-01` | Matches the base scenario |

Full cmdlet/REST-body grounding: `deploy/New-AzureSqlManagedIdentityCredentialScan.ps1`'s inline
comments and `.NOTES` block.

## Operations and tuning

All of the base scenario's operations and tuning KPI and incident-response guidance applies unchanged - this scenario
only changes *which identity* authenticates the same scan, not its scan behavior, scheduling, or
failure classification. Two additions specific to the UAMI path:

- **The UAMI credential has no Key Vault-side detective control.** Like `AmazonARN`, the
  `ManagedIdentity` kind carries no secret - there is nothing for a Key Vault `AuditEvent` diagnostic
  log to catch if the credential object is silently re-pointed at a different UAMI. The only
  detective control is *Scan Credential Inventory & Drift Report*'s estate-wide drift
  report, run on the same daily cadence *Scan Credentials: Remaining Kinds (Account Key, Role ARN, Consumer Key, Delegated Auth, User-Assigned Managed Identity)* (operations and tuning) recommends for
  this kind.
- **A UAMI can be deleted or detached from the Purview account independently of this scan's
  configuration.** If a scan that previously succeeded starts failing authentication with no
  configuration change on the Purview side, check the Azure portal's **Managed identities** blade on
  the Purview account first - the UAMI resource itself, not just the credential object, is the
  most likely point of silent failure.
- **No detective control exists for the scan's own `credential.referenceName` drifting away from
  the intended UAMI credential.** *Scan Credential Inventory & Drift Report* monitors
  drift on a *credential object's own content* (its `principalId`/`resourceId`/`tenantId`); it has
  no concept of which *scans* reference which credential, so it would not catch an operator
  (accidentally or deliberately) re-pointing this scan at a different, still-valid `ManagedIdentity`
  credential. The only detective control for that specific drift is re-running
  `validate/Test-AzureSqlManagedIdentityCredentialScan.ps1 -ExpectedCredentialReferenceName` on a
  schedule - there is no Purview audit event or alert for a scan's credential reference changing
  (the same "no `GenerateAlert` for scans" gap *Scan Azure SQL Database and Classify Sensitive Columns* (operations and tuning) already
  discloses generally).
- **Adopt selectively, not as a blanket replacement for SAMI.** Each UAMI is one more Azure identity
  a team must provision, grant, and monitor - the identity-separation benefit is highest for a
  small number of high-sensitivity sources (e.g. an MSSP's per-customer databases), and lowest for a
  large fleet of low-sensitivity sources where the coordination overhead likely outweighs the
  blast-radius reduction. Start with the sources whose compromise would be most consequential, not
  every scan the base scenario has ever registered.

## Rollback and decommission

See the rollback runbook for the full staged procedure. Quick reference:
`./deploy/Remove-AzureSqlManagedIdentityCredentialScan.ps1` reverts the scan's `kind` back to
`AzureSqlDatabaseMsi` (SAMI), preserving every other scan property - reversible by re-running this
scenario's own deploy script again. It does not delete the UAMI, its Azure IAM/SQL grants, or the
`ManagedIdentity` credential object.

## References

1. Discover and govern Azure SQL Database in Microsoft Purview - <https://learn.microsoft.com/purview/register-scan-azure-sql-database>
2. Microsoft Purview billing models (PAYG for Data Map) - <https://learn.microsoft.com/purview/purview-billing-models>
3. Tutorial: Authenticate for Microsoft Purview data-plane APIs - <https://learn.microsoft.com/purview/data-gov-api-rest-data-plane>
4. Discover and govern Azure SQL Database - "Configure authentication for a scan" / "Managed identity" tab (UAMI supported source, T-SQL grant using the exact managed identity name, Azure IAM Reader accepting "your Microsoft Purview account name or UAMI", SAMI/UAMI incompatibility with self-hosted integration runtime) - <https://learn.microsoft.com/purview/register-scan-azure-sql-database#configure-authentication-for-a-scan>
5. Scans - Create Or Replace REST API reference (API version 2023-09-01; confirmed `AzureSqlDatabaseCredentialScanProperties`, `CredentialReference { credentialType, referenceName }`, and the `CredentialType` enum including `ManagedIdentity`) - <https://learn.microsoft.com/rest/api/purview/scanningdataplane/scans/create-or-replace>
6. Connect to and manage Azure Synapse Analytics workspaces in Microsoft Purview - collection ID lookup - <https://learn.microsoft.com/purview/register-scan-synapse-workspace#scan>
7. Scans and ingestion in Data Map - <https://learn.microsoft.com/purview/data-map-scan-ingestion>
8. Data governance best practices for security - Credential management (Microsoft's explicit credential priority order: Purview managed identity → user-assigned managed identity → service principal → account key/SQL auth/other) - <https://learn.microsoft.com/purview/data-gov-classic-security-best-practices>
9. Credentials for source authentication in Microsoft Purview Data Map - "Create a user-assigned managed identity" (UAMI creation via the Purview account's Managed identities blade; confirms Azure SQL Database as a UAMI-supported source) - <https://learn.microsoft.com/purview/data-map-data-scan-credentials#create-a-user-assigned-managed-identity>
10. Credential - Get / List REST API reference (object shape used by this scenario's optional `-CheckCredentialObject`/precheck) - <https://learn.microsoft.com/rest/api/purview/scanningdataplane/credential>
11. *Scan Credentials: Remaining Kinds (Account Key, Role ARN, Consumer Key, Delegated Auth, User-Assigned Managed Identity)* - the `ManagedIdentity` credential kind this scenario consumes (creation, grounding, and its own known limitations).
12. *Scan Azure SQL Database and Classify Sensitive Columns* - the base scenario this fragment extends (data source registration, SAMI defaults, full prerequisite table this scenario's own table is additive to).

> Re-verify all links, API versions, and REST body shapes against current Microsoft Learn before a
> customer-facing deployment. The `ManagedIdentity` credential kind remains Microsoft-labeled
> Preview as of this writing - see the known limitations.