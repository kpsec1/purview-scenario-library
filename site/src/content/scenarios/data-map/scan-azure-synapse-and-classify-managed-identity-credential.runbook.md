---
part: "runbook"
parent: "data-map/scan-azure-synapse-and-classify-managed-identity-credential"
---
## Implementation steps

### Portal path (for a first manual walkthrough / to validate intent before scripting)

1. Complete *Scan Credentials: Remaining Kinds (Account Key, Role ARN, Consumer Key, Delegated Auth, User-Assigned Managed Identity)*'s portal or script path for a
   `ManagedIdentity` credential first - this requires a UAMI already added under the Purview
   account's **Managed identities** blade.
2. Grant the UAMI **Reader** on the Synapse workspace (Azure portal → workspace → **Access control
   (IAM)** → **Add role assignment**), the same pane the base scenario's SAMI grant used.
3. **Serverless pools only:** grant the UAMI **Storage Blob Data Reader** on the workspace's
   associated storage account, then run the enumeration login in Synapse Studio using the UAMI's
   exact managed-identity name:
   ```sql
   CREATE LOGIN [Username] FROM EXTERNAL PROVIDER;
   ```
  
4. Per database (dedicated or serverless), run the matching read grant using the UAMI's exact
   managed-identity name as `[Username]` - dedicated:
   ```sql
   CREATE USER [Username] FROM EXTERNAL PROVIDER
   GO
   EXEC sp_addrolemember 'db_datareader', [Username]
   GO
   ```
   serverless:
   ```sql
   CREATE USER [Username] FOR LOGIN [Username];
   ALTER ROLE db_datareader ADD MEMBER [Username];
   ```
  
5. Back in the Purview portal, open the base scenario's already-registered scan and select **Edit**.
   Under **Credential**, switch from the system-assigned managed identity to the UAMI, select **Test
   connection**, then **Save**.
6. Re-run (or wait for the next scheduled trigger) and confirm the scan still completes successfully
   under the new identity.

### Script path (idempotent, parameterized, dry-run capable)

```powershell
# 0. Prerequisite: build the ManagedIdentity credential first (if not already done)
../scan-credential-remaining-kinds/deploy/New-PurviewScanCredentialExtended.ps1 `
    -PurviewAccountName 'contoso-purview' -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
    -CredentialName 'synapse-contoso-uami' -CredentialType ManagedIdentity `
    -PrincipalId $UamiPrincipalId -ResourceId $UamiResourceId

# 1. Dry run first
./deploy/New-AzureSynapseManagedIdentityCredentialScan.ps1 `
    -PurviewAccountName 'contoso-purview' -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
    -DataSourceName 'ws-contoso-prod' -CredentialReferenceName 'synapse-contoso-uami' -WhatIf

# 2. Reconcile for real
./deploy/New-AzureSynapseManagedIdentityCredentialScan.ps1 `
    -PurviewAccountName 'contoso-purview' -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
    -DataSourceName 'ws-contoso-prod' -CredentialReferenceName 'synapse-contoso-uami'

# 3. Reconcile and immediately prove the new identity works
./deploy/New-AzureSynapseManagedIdentityCredentialScan.ps1 `
    -PurviewAccountName 'contoso-purview' -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
    -DataSourceName 'ws-contoso-prod' -CredentialReferenceName 'synapse-contoso-uami' -RunNow

# 4. Validate
./validate/Test-AzureSynapseManagedIdentityCredentialScan.ps1 `
    -PurviewAccountName 'contoso-purview' -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
    -DataSourceName 'ws-contoso-prod' -ExpectedCredentialReferenceName 'synapse-contoso-uami' `
    -CheckCredentialObject
```

Same REST surface as the base scenario - Microsoft Purview Data Map / Data Governance REST API,
automation surface 4 per [Automation surface, section 1](/docs/automation-surface/#1-five-automation-surfaces-not-one-read-this-first).

## Configuration reference

| Setting | Value this scenario uses | Notes |
|---|---|---|
| Scan `kind` (before) | `AzureSynapseWorkspaceMsi` | SAMI-authenticated - the base scenario's default |
| Scan `kind` (after) | `AzureSynapseWorkspaceCredential` | Confirmed via direct fetch of the Scans - Create Or Replace REST reference AND a worked JSON example on the base scenario's own registration page - see the design notes |
| `properties.credential.credentialType` | `ManagedIdentity` | Directly confirmed for this exact scan kind by Microsoft's own worked example, not inferred from a generic list |
| `properties.credential.referenceName` | Name of a pre-existing `ManagedIdentity`-kind credential object | Built via *Scan Credentials: Remaining Kinds (Account Key, Role ARN, Consumer Key, Delegated Auth, User-Assigned Managed Identity)* - see the prerequisites |
| Properties preserved unchanged from the existing scan | `collection`, `scanRulesetName`, `scanRulesetType` only - **no** `databaseName`/`serverEndpoint` | `AzureSynapseWorkspaceCredentialScanProperties` carries neither field; both dedicated/serverless endpoints live on the data source object - the design notes goal 1 |
| `-SkipCredentialPrecheck` | Off by default | Skips the read-only GET against the credential object before reconciling |
| `-Force` | Off by default | Required to proceed past a precheck that found the credential object but confirmed it is **not** kind `ManagedIdentity` |
| `-RunNow` | Off by default | Starts an immediate scan run to prove the new identity actually authenticates |
| API version pinned by this script | `2023-09-01` | Matches the base scenario |

Full cmdlet/REST-body grounding: `deploy/New-AzureSynapseManagedIdentityCredentialScan.ps1`'s inline
comments and `.NOTES` block.

## Operations and tuning

All of the base scenario's operations and tuning KPI and incident-response guidance applies unchanged. Two additions
specific to the UAMI path, identical to both siblings' own disclosure:

- **No Key Vault-side detective control.** `ManagedIdentity` carries no secret - the only detective
  control is *Scan Credential Inventory & Drift Report*'s estate-wide drift report.
- **No detective control for the scan's own credential reference drifting**, as distinct from the
  credential object's content drifting. The only mitigation is re-running
  `validate/Test-AzureSynapseManagedIdentityCredentialScan.ps1 -ExpectedCredentialReferenceName` on a
  schedule.
- **Adopt selectively.** Same phased-rollout recommendation as both siblings - and arguably the
  strongest candidate of the three for early adoption, given Synapse's role as an aggregation point
  for sensitive data from many upstream systems.

## Rollback and decommission

See the rollback runbook for the full staged procedure. Quick reference:
`./deploy/Remove-AzureSynapseManagedIdentityCredentialScan.ps1` reverts the scan's `kind` back to
`AzureSynapseWorkspaceMsi` (SAMI), preserving every other scan property. It does not delete the
UAMI, its grants, or the `ManagedIdentity` credential object.

## References

1. Connect to and manage Azure Synapse Analytics workspaces in Microsoft Purview - <https://learn.microsoft.com/purview/register-scan-synapse-workspace>
2. Microsoft Purview billing models (PAYG for Data Map) - <https://learn.microsoft.com/purview/purview-billing-models>
3. Tutorial: Authenticate for Microsoft Purview data-plane APIs - <https://learn.microsoft.com/purview/data-gov-api-rest-data-plane>
4. Connect to and manage Azure Synapse Analytics workspaces in Microsoft Purview - "Scan" / enumeration authentication and per-database grant sections (Reader + Storage Blob Data Reader + per-database CREATE LOGIN/CREATE USER for managed identity authentication) - <https://learn.microsoft.com/purview/register-scan-synapse-workspace#scan>
5. Scans - Create Or Replace REST API reference (API version 2023-09-01; confirmed `AzureSynapseWorkspaceCredentialScanProperties` field names - no `databaseName`/`serverEndpoint`; the shared `CredentialType` enum including `ManagedIdentity`) - <https://learn.microsoft.com/rest/api/purview/scanningdataplane/scans/create-or-replace>
6. Connect to and manage Azure Synapse Analytics workspaces in Microsoft Purview - "Set up a scan by using an API" (Microsoft's own worked JSON body explicitly showing `"credentialType":"SqlAuth | ServicePrincipal | ManagedIdentity (if UAMI authentication)"` for `"kind":"AzureSynapseWorkspaceCredential"` - the strongest direct confirmation of the three sibling scenarios) - <https://learn.microsoft.com/purview/register-scan-synapse-workspace#set-up-a-scan-by-using-an-api>
7. Scans and ingestion in Data Map - <https://learn.microsoft.com/purview/data-map-scan-ingestion>
8. Data governance best practices for security - Credential management (Microsoft's credential priority order) - <https://learn.microsoft.com/purview/data-gov-classic-security-best-practices>
9. Credentials for source authentication in Microsoft Purview Data Map - "Create a user-assigned managed identity" - <https://learn.microsoft.com/purview/data-map-data-scan-credentials#create-a-user-assigned-managed-identity>
10. Credential - Get / List REST API reference - <https://learn.microsoft.com/rest/api/purview/scanningdataplane/credential>
11. *Scan Credentials: Remaining Kinds (Account Key, Role ARN, Consumer Key, Delegated Auth, User-Assigned Managed Identity)* - the `ManagedIdentity` credential kind this scenario consumes.
12. *UAMI Credential for the Azure SQL Database Scan*, `scan-azure-sql-managed-instance-and-classify-managed-identity-credential/` - the two sibling scenarios this scenario ports the reconciliation pattern from; see the design notes for the confirmed differences.

> Re-verify all links, API versions, and REST body shapes against current Microsoft Learn before a
> customer-facing deployment. The `ManagedIdentity` credential kind remains Microsoft-labeled
> Preview as of this writing - see the known limitations.