---
part: "runbook"
parent: "data-map/scan-credential-remaining-kinds"
---
## Implementation steps

### Portal path (for a first manual walkthrough / to validate intent before scripting)

Steps 1-2 (store the secret, grant Purview vault access) are the parent scenario's the implementation steps steps 1-2 and
apply unchanged to `AccountKey`, `ConsumerKeyAuth`, and `DelegatedAuth` (skip them entirely for
`AmazonARN` and `ManagedIdentity` - neither uses a Key Vault secret). Then, on the Purview
**Credentials** page → **+ New**:

| Kind | Authentication method (portal) | Fields |
|---|---|---|
| `AccountKey` | **Account Key** | Key Vault connection, secret name |
| `AmazonARN` | **Role ARN** | Role ARN (paste after creating the AWS-side role - see section 3) |
| `ConsumerKeyAuth` | **Consumer Key** | User name, consumer key (plain text field), Key Vault connection + secret name for the consumer secret, Key Vault connection + secret name for the password |
| `DelegatedAuth` | **Delegated auth** | Client ID, user name, Key Vault connection + secret name for the password |
| `ManagedIdentity` | **Managed identity** | Select from the **User assigned managed identities** dropdown (populated from the Purview account's own **Managed identities** blade - this build found no free-text principal/resource/tenant ID entry in the portal path) |

> The portal's `ManagedIdentity` path is a dropdown selection, not a form of raw IDs - but the REST
> body it produces underneath is the same `principalId`/`resourceId`/`tenantId` shape the configuration reference documents,
> confirmed by the Scanning-data-plane reference independent of the portal UI.

### Script path

```powershell
# AccountKey - Azure Storage / ADLS Gen1+2 / Azure Files / Cosmos DB account key.
./deploy/New-PurviewScanCredentialExtended.ps1 `
    -PurviewAccountName 'contoso-purview' -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
    -CredentialName 'adls-account-key' -CredentialType AccountKey `
    -KeyVaultConnectionName 'kv-contoso-purview' -SecretName 'adls-storage-account-key' -WhatIf

# AmazonARN - Amazon S3. No Key Vault connection at all; the role must already trust Microsoft
# (README.md Section 3/11 - external ID: scriptable via Get-AzPurviewAccount; Microsoft account ID:
# PORTAL-only, not this script).
./deploy/New-PurviewScanCredentialExtended.ps1 `
    -PurviewAccountName 'contoso-purview' -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
    -CredentialName 's3-role-arn' -CredentialType AmazonARN `
    -RoleArn 'arn:aws:iam::181328463391:role/PurviewS3ScanRole'

# ConsumerKeyAuth - Salesforce. Two independent Key Vault secrets; ConsumerKey itself is NOT a
# secret reference (Microsoft's schema types it as a plain string - see Section 6).
./deploy/New-PurviewScanCredentialExtended.ps1 `
    -PurviewAccountName 'contoso-purview' -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
    -CredentialName 'salesforce-consumer-key' -CredentialType ConsumerKeyAuth `
    -KeyVaultConnectionName 'kv-contoso-purview' -UserName 'purview-integration@contoso.com' `
    -ConsumerKey '3MVG9...' -ConsumerSecretName 'salesforce-consumer-secret' -SecretName 'salesforce-password'

# DelegatedAuth - Microsoft Fabric / Power BI (cross-tenant, or same-tenant over a self-hosted IR).
./deploy/New-PurviewScanCredentialExtended.ps1 `
    -PurviewAccountName 'contoso-purview' -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
    -CredentialName 'fabric-delegated-auth' -CredentialType DelegatedAuth `
    -KeyVaultConnectionName 'kv-contoso-purview' -ClientId $FabricAppRegistrationAppId `
    -UserName 'fabric-admin@contoso.com' -SecretName 'fabric-admin-password'

# ManagedIdentity - a user-assigned managed identity already added to the Purview account and
# supported by the target source (Azure Data Lake Gen1/Gen2, Azure SQL Database, Azure SQL Managed
# Instance, Azure Synapse dedicated SQL pools, Azure Blob Storage - Section 6). PREVIEW - Section 11.
./deploy/New-PurviewScanCredentialExtended.ps1 `
    -PurviewAccountName 'contoso-purview' -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
    -CredentialName 'adls-uami' -CredentialType ManagedIdentity `
    -PrincipalId $UamiPrincipalId -ResourceId $UamiResourceId

# Verify any of the above (kind-aware).
./validate/Test-PurviewScanCredentialExtended.ps1 `
    -PurviewAccountName 'contoso-purview' -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
    -CredentialName 'adls-account-key' -ExpectedCredentialType AccountKey -CheckKeyVaultSecret
```

Omitting `-KeyVaultBaseUrl` on a kind that needs a Key Vault connection (`AccountKey`,
`ConsumerKeyAuth`, `DelegatedAuth`) makes the script **require** that `-KeyVaultConnectionName`
already exists, exactly like the parent scenario - most deployments reuse the connection the parent
scenario already created rather than making a new one per credential kind.

## Configuration reference

### Credential body - kind → `typeProperties` shape

All five confirmed directly against the Scanning-data-plane **Credential - Create Or Replace**
reference, the same source the parent scenario used for its three kinds, and
cross-checked against *Scan Credential Inventory & Drift Report*'s independently-built
per-kind fingerprint table (the configuration reference there), which reached the identical shapes from the read side.

| `kind` | `properties` type | `typeProperties` type | Fields |
|---|---|---|---|
| `AccountKey` | `AccountKeyCredentialProperties` | `KeyVaultSecretAccountKeyCredentialTypeProperties` | `{ accountKey: KeyVaultSecret }` |
| `AmazonARN` | `RoleARNCredentialProperties` | `RoleARNCredentialTypeProperties` | `{ roleARN: string }` - **no** `KeyVaultSecret` anywhere in this kind |
| `ConsumerKeyAuth` | `ConsumerKeyCredentialProperties` | `KeyVaultSecretConsumerKeyCredentialTypeProperties` | `{ user: string, consumerKey: string, consumerSecret: KeyVaultSecret, password: KeyVaultSecret }` - **two** independent secret references; `consumerKey` itself is a plain string, not a secret reference |
| `DelegatedAuth` | `DelegatedAuthCredentialProperties` | `KeyVaultSecretDelegatedAuthCredentialTypeProperties` | `{ clientId: string, user: string, password: KeyVaultSecret }` |
| `ManagedIdentity` | `ManagedIdentityAzureKeyVaultCredentialProperties` | `KeyVaultSecretManagedIdentityAzureKeyVaultCredentialTypeProperties` | `{ principalId: string, resourceId: string, tenantId: string }` - **no** `KeyVaultSecret` anywhere in this kind, the same structural absence as `AmazonARN` |

The `KeyVaultSecret`/`Store` sub-object and its two open-VERIFY discriminator literals (`type`,
`store.type`) are identical to the parent scenario - this fragment's script reuses the same
`-SecretReferenceType`/`-SecretStoreReferenceType` parameters and defaults. See the parent scenario's configuration reference and the known limitations and the design notes; not re-derived here.

### Consuming scan kinds / source types (Microsoft's own documented pairing)

| Kind | Confirmed for | Source |
|---|---|---|
| `AccountKey` | Azure Blob Storage, ADLS Gen1, ADLS Gen2, Azure Files, Azure Cosmos DB (SQL API) | |
| `AmazonARN` | Amazon S3 (the **only** documented auth method for this source - no managed identity or service principal option exists for S3) | |
| `ConsumerKeyAuth` | Salesforce (the **only** documented auth method for this source) | |
| `DelegatedAuth` | Microsoft Fabric (same-tenant and cross-tenant), Power BI tenant (same-tenant and cross-tenant) | |
| `ManagedIdentity` | Azure Data Lake Gen1, Azure Data Lake Gen2, Azure SQL Database, Azure SQL Managed Instance, Azure Synapse dedicated SQL pools, Azure Blob Storage | |

No scenario in this library scans Amazon S3, Salesforce, Microsoft Fabric, or Power BI yet - those
are natural future fragments this one hands a working credential to. The
`ManagedIdentity` row **did** overlap this library's existing scan scenarios
(*Scan Azure SQL Database and Classify Sensitive Columns*, *Scan Azure SQL Managed Instance and Classify Sensitive Columns*,
*Scan Azure Synapse Analytics Workspace and Classify Sensitive Columns*) - wiring a UAMI credential into each as an alternative to SAMI was
this fragment's most immediately actionable follow-up. **RESOLVED for all three:**
*UAMI Credential for the Azure SQL Database Scan*,
*UAMI Credential for the Azure SQL Managed Instance Scan*, and
*UAMI Credential for the Azure Synapse Workspace Scan* each reconcile
their base scenario's scan onto a `ManagedIdentity` credential built here. The Synapse sibling found
the strongest direct grounding of the three - a worked JSON example on its own base scenario's
canonical page explicitly confirms `ManagedIdentity` as a valid `credentialType` for that exact scan
`kind`, rather than inferring it from a separate generic "supported sources" list as the other two
had to.

### Deploy script parameters (selected)

| Parameter | Applies to | Notes |
|---|---|---|
| `-CredentialType` | All | `AccountKey` \| `AmazonARN` \| `ConsumerKeyAuth` \| `DelegatedAuth` \| `ManagedIdentity` |
| `-KeyVaultConnectionName` / `-KeyVaultBaseUrl` | `AccountKey`, `ConsumerKeyAuth`, `DelegatedAuth` | Same semantics as the parent scenario; **rejected** (script throws) if supplied for `AmazonARN`/`ManagedIdentity`, which reference no Key Vault connection at all |
| `-SecretName` / `-SecretVersion` | `AccountKey` (the account key), `DelegatedAuth` (the password), `ConsumerKeyAuth` (the password only - see `-ConsumerSecretName`) | |
| `-ConsumerSecretName` / `-ConsumerSecretVersion` | `ConsumerKeyAuth` only | The **second**, independent secret reference (`consumerSecret`) |
| `-UserName` | `ConsumerKeyAuth`, `DelegatedAuth` | |
| `-ConsumerKey` | `ConsumerKeyAuth` only | Plain string, written verbatim into the credential's metadata - not a Key Vault reference |
| `-ClientId` | `DelegatedAuth` only | The scanning app registration's Application (client) ID - see the Microsoft Fabric/Power BI worked examples |
| `-RoleArn` | `AmazonARN` only | e.g. `arn:aws:iam::<account>:role/<role-name>` |
| `-PrincipalId` / `-ResourceId` / `-ManagedIdentityTenantId` | `ManagedIdentity` only | Identify an **existing** UAMI already added to the Purview account; `-ManagedIdentityTenantId` defaults to `-TenantId` |
| `-SecretReferenceType` / `-SecretStoreReferenceType` | Any secret-bearing kind | Same VERIFY-driven parameters as the parent scenario, same defaults |
| `-ApiVersion` | All | Defaults to `2023-09-01`, matching the parent scenario |

Worked request bodies for all five kinds: `deploy/policy/scan-credential-extended-definitions.json`.

## Operations and tuning

All of the parent scenario's operations and tuning guidance applies unchanged - rotation tradeoffs for the
secret-bearing kinds, the credential re-point risk, and the estate-wide drift report in
*Scan Credential Inventory & Drift Report*, which **already** fingerprints all eight
kinds including these five - this fragment's credentials are covered by that report with no changes
needed there.

**`AmazonARN`/`ManagedIdentity` have a strictly smaller detection surface than every other kind in
this library, and that is worth stating plainly rather than folding into a general note.** The
parent scenario's compensating control for a silent credential re-point is *two* independent
signals: the estate-wide inventory report, **and** Key Vault `AuditEvent` diagnostic logs (which
record which identity read which secret, catching a re-point at the *vault* side even when Purview's
own audit log stays silent - the parent scenario's known limitations). `AmazonARN` and `ManagedIdentity` credentials
have no Key Vault secret at all, so that second signal **does not exist** for them - the estate-wide
inventory report is the *only* detective control, full stop. Run it on at least a daily cadence for
any tenant relying on either kind, not the weekly-or-pipeline cadence the parent scenario treats as
sufficient when a Key Vault-side backstop is also in play.

**A short runbook for the two kinds that don't fit the parent scenario's Key Vault-centric triage:**

| Kind | First check | If that passes but the scan still fails |
|---|---|---|
| `AmazonARN` | `validate/... -ExpectedCredentialType AmazonARN` - confirms the ARN's string shape only | The failure is entirely on the AWS side: the IAM role's trust policy, its `AmazonS3ReadOnlyAccess`-equivalent permissions, a bucket policy, or an SCP policy blocking the connection. This scenario's validate script cannot reach into AWS at all - escalate straight to an AWS console check |
| `ManagedIdentity` | `validate/... -ExpectedCredentialType ManagedIdentity` - confirms the three ID strings are present, non-empty, and internally consistent | Confirm the referenced UAMI is still listed under the Purview account's **Managed identities** blade (it can be deleted there independently of this credential object, per the rollback plan), then confirm it still holds the access grant the source-specific registration steps describe (the configuration reference references). Also re-confirm current Preview status - a preview-stage capability changing behavior without a corresponding REST reference update is a real possibility, not a hypothetical one |

**Kind-specific operational notes:**

| Kind | What changes operationally vs. the parent's three kinds |
|---|---|
| `AccountKey` | Rotating the storage account key is an **Azure Storage/Cosmos DB** operation, not a Key Vault one - the new key must be written into the *same* secret name/version pattern this scenario's credential already references |
| `AmazonARN` | No secret to rotate. The only "credential rotation" concept is replacing the Role ARN itself (e.g. after an AWS-side role rename) - re-run this scenario's deploy script with the new `-RoleArn` |
| `ConsumerKeyAuth` | **Two** secrets to track, not one - a Salesforce connected-app secret rotation and a Salesforce user password rotation are independent events, each requiring its own Key Vault write (and, if versions are pinned, its own re-deploy) |
| `DelegatedAuth` | The Fabric/Power BI admin account's password expiring is a common, easy-to-miss failure mode for this kind specifically - Microsoft's own troubleshooting guidance for Fabric/Power BI scans distinguishes an "Access - Failed" test-connection result (user authentication) from an "Assets - Failed" result (Purview-Fabric authorization), which maps directly to "check this credential" vs. "check the Purview managed identity's Fabric security-group membership" |
| `ManagedIdentity` | No secret at all - monitor instead via the estate-wide inventory report (drift on `PrincipalId`/`ResourceId`/`TenantId`) and via the **preview** status itself: re-check Microsoft's documentation periodically for GA changes that could alter behavior |

## Rollback and decommission

See the rollback runbook. Summary: this fragment adds **no new script** for deletion - the parent
scenario's `deploy/Remove-PurviewScanCredential.ps1` is a plain `DELETE /scan/credentials/{name}`
call that is already fully kind-agnostic (it never inspects `typeProperties` to delete), so it
deletes credentials created by this scenario exactly as it deletes the parent's three kinds. One
disclosed nuance: its `-RemoveKeyVaultConnection` safety check (which lists *other* credentials
still referencing a connection before allowing the connection's own deletion) only ever finds
`AccountKey`/`ConsumerKeyAuth`/`DelegatedAuth` credentials that way, by construction -
`AmazonARN`/`ManagedIdentity` credentials never reference a Key Vault connection, so they are
correctly invisible to that check, not missed by it.

## References

1. [Credential - Create Or Replace (Purview Scanning data plane, 2023-09-01)](https://learn.microsoft.com/rest/api/purview/scanningdataplane/credential/create-or-replace) - all eight `CredentialType` kinds, every `typeProperties` definition used in the configuration reference's table, the `RoleARNCredential`/`DelegatedAuthCredentialTypeProperties` description text quoted in the known limitations, `credentialName` pattern.
2. [Connect to Azure Data Lake Storage in Microsoft Purview](https://learn.microsoft.com/purview/register-scan-adls-gen2#scan) - the Account Key authentication path for ADLS Gen2.
3. [Connect to and manage Azure Files in Microsoft Purview](https://learn.microsoft.com/purview/register-scan-azure-files-storage-source#register) - Account Key as the only registration auth method for Azure Files.
4. [Connect to Azure Cosmos DB for SQL API in Microsoft Purview](https://learn.microsoft.com/purview/register-scan-azure-cosmos-database#scan) - Account Key as the only scan auth method for Cosmos DB.
5. [Connect to Azure Blob storage in Microsoft Purview](https://learn.microsoft.com/purview/register-scan-azure-blob-storage-source#scan) - Account Key alongside managed identity/service principal for Blob Storage.
6. [Amazon S3 Multicloud Scanning Connector for Microsoft Purview](https://learn.microsoft.com/purview/register-scan-amazon-s3) - Role ARN as the only auth method for S3; the portal-displayed Microsoft account ID/external ID (the prerequisites and the known limitations - external ID now also confirmed scriptable per); the AWS IAM role trust setup.
7. [Credentials for source authentication in Microsoft Purview Data Map](https://learn.microsoft.com/purview/data-map-data-scan-credentials) - the enumerated credential-type list including Consumer Key ("For Salesforce data sources"), Account Key, Role ARN, and User-assigned managed identity (preview); the UAMI creation/deletion procedure and its six supported source types.
8. [Data governance best practices for security - Credential management](https://learn.microsoft.com/purview/data-gov-classic-security-best-practices) - Microsoft's explicit credential priority order (Purview managed identity → user-assigned managed identity → service principal → account key/SQL auth/other), cited in why this matters.
9. [Connect to your Microsoft Fabric tenant in the same tenant as Microsoft Purview](https://learn.microsoft.com/purview/register-scan-fabric-tenant#authentication-to-scan) - the Delegated Auth credential fields (Client ID, User name, Password) worked example and the Access-vs-Assets test-connection failure distinction.
10. [Connect to and manage a Power BI tenant in Microsoft Purview (cross-tenant)](https://learn.microsoft.com/purview/register-scan-power-bi-tenant-cross-tenant#scan-cross-tenant-power-bi) - the cross-tenant Delegated Auth worked example.
11. [Get-AzKeyVaultSecret](https://learn.microsoft.com/powershell/module/az.keyvault/get-azkeyvaultsecret) - metadata-only read used by `-CheckKeyVaultSecret`, same as the parent scenario.
12. [Account.CloudConnectorAwsExternalId Property (Az.Purview)](https://learn.microsoft.com/dotnet/api/microsoft.azure.powershell.cmdlets.purview.models.account.cloudconnectorawsexternalid) - the read-only `Microsoft.Purview/accounts` control-plane property confirming the `AmazonARN` external ID (but not the Microsoft account ID) is scriptable via `Get-AzPurviewAccount`, cited in the known limitations.

Related scenarios in this library:
- *Key Vault-Backed Scan Credential (SQL Auth / Service Principal)* - the parent scenario (`SqlAuth`,
  `BasicAuth`, `ServicePrincipal`); this fragment shares its deletion script, Key Vault connection
  model, and open VERIFYs.
- *Scan Credential Inventory & Drift Report* - already fingerprints all eight
  `CredentialType` kinds, including the five this fragment creates; no change needed there.
- *UAMI Credential for the Azure SQL Database Scan*,
  `scan-azure-sql-managed-instance-and-classify-managed-identity-credential/`,
  `scan-azure-synapse-and-classify-managed-identity-credential/` - wire this fragment's
  `ManagedIdentity` credential kind into the Azure SQL Database, Managed Instance, and Synapse
  workspace scans as an alternative to SAMI. **All three built** - see section 6.
- [RBAC model, section 5](/docs/rbac-model/#5-data-governance-roles-data-map--unified-catalog---a-separate-model) - Data Map collection roles.
- [Automation surface](/docs/automation-surface/) - surface 4 (Purview data-plane REST).