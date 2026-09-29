---
part: "runbook"
parent: "data-map/scan-credential-key-vault-backed"
---
## Implementation steps

### Portal path (for a first manual walkthrough / to validate intent before scripting)

1. **Store the secret.** In the Azure portal, open your **Key Vault → Settings → Secrets →
   + Generate/Import**. Enter a **Name** (this becomes `secretName`) and the **Value** (the SQL
   login's password, or the service principal's client secret). Select **Create**.
2. **Grant Purview access to the vault.** Match your vault's permission model - granting the wrong
   one silently does nothing:
   - *Access policy model:* **Key Vault → Access policies → Create**, **Secret permissions** =
     **Get** and **List**, principal = your **Purview account** (searchable by account name or
     managed-identity application ID). Compound identities - managed identity name *plus*
     application ID - are not supported.
   - *Azure RBAC model:* **Key Vault → Access control (IAM) → + Add**, role = **Key Vault Secrets
     User**, assignee = your Purview account.

   Either grant is **vault-wide over secrets** - Microsoft documents no per-secret scoping for
   this. Whichever model you use, prefer a Key Vault dedicated to Purview scan credentials so that
   granting Purview read access does not also expose unrelated application secrets.
3. **Register the Key Vault connection in Purview.** In the [Microsoft Purview
   portal](https://purview.microsoft.com) → **Data Map** → **Source management** → **Credentials**
   → **Manage Key Vault connections** → **+ New**. Supply the connection name and the vault, then
   **Create**, and confirm it appears in the list.
4. **Create the credential.** On the **Credentials** page, select **+ New**. Provide a **Name**,
   choose the **Authentication method** (SQL authentication, Basic authentication, or Service
   principal), pick the **Key Vault connection** from step 3 and the **Secret name** from step 1,
   plus the username or service-principal ID, and select **Create**. Verify it shows in the list
   view as ready to use.
5. **Reference it from a scan.** When creating a scan on a registered source, select this
   credential instead of the managed identity, then **Test connection**.

> Steps 3-5 are what this scenario automates. Steps 1-2 stay deliberately manual/out-of-band -
> see the design notes for why the deploy script does not write secrets or grant vault access.

### Script path

```powershell
# Dry run first - prints both REST calls, sends nothing.
./deploy/New-PurviewScanCredential.ps1 `
    -PurviewAccountName 'contoso-purview' -TenantId $TenantId `
    -AppId $AppId -ClientSecret $ClientSecret `
    -CredentialName 'onprem-sql-svc-account' `
    -CredentialType SqlAuth `
    -KeyVaultConnectionName 'kv-contoso-purview' `
    -KeyVaultBaseUrl 'https://kv-contoso-purview.vault.azure.net/' `
    -SecretName 'onprem-sql-scan-password' `
    -UserName 'purview_scanner' `
    -WhatIf

# Apply (drop -WhatIf).
./deploy/New-PurviewScanCredential.ps1 ... # same parameters, no -WhatIf

# Verify, including that the referenced Key Vault secret actually exists and is enabled.
./validate/Test-PurviewScanCredential.ps1 `
    -PurviewAccountName 'contoso-purview' -TenantId $TenantId `
    -AppId $AppId -ClientSecret $ClientSecret `
    -CredentialName 'onprem-sql-svc-account' `
    -KeyVaultConnectionName 'kv-contoso-purview' `
    -ExpectedSecretName 'onprem-sql-scan-password' `
    -ExpectedCredentialType SqlAuth `
    -CheckKeyVaultSecret
```

Service-principal variant (for an Entra-authenticated source reached over a self-hosted IR, where
SAMI is not an option):

```powershell
./deploy/New-PurviewScanCredential.ps1 `
    -PurviewAccountName 'contoso-purview' -TenantId $TenantId `
    -AppId $AppId -ClientSecret $ClientSecret `
    -CredentialName 'azuresql-scan-sp' -CredentialType ServicePrincipal `
    -KeyVaultConnectionName 'kv-contoso-purview' `
    -SecretName 'purview-scan-sp-secret' `
    -ServicePrincipalId $ScanSpAppId
```

Omitting `-KeyVaultBaseUrl` makes the script **require** that the named connection already exists
(it issues a `GET` and fails fast otherwise) rather than creating a credential whose store
reference dangles.

> **Run this against a pilot/non-production Purview account first.** Two field values in the
> credential body are corroborated structurally but not confirmed by any Purview-specific worked
> example. The cheapest way to settle them is to create one credential in the **portal**,
> `GET /scan/credentials/{name}`, and compare the `type` / `store.type` values against this
> scenario's defaults - then deploy with confidence (or with the two override parameters). Doing
> that once, in a pilot, converts this scenario's only open risk into a known value.

Then hand the credential name to a scan, e.g. in
*Scan On-Premises SQL Server and Classify Sensitive Columns*:

```powershell
./deploy/New-OnPremisesSqlServerDataMapScan.ps1 ... `
    -CredentialReferenceName 'onprem-sql-svc-account' -CredentialType 'SqlAuth'
```

## Configuration reference

### Objects created

| Object | Endpoint (`api-version=2023-09-01`) | Idempotency | Source |
|---|---|---|---|
| Key Vault connection | `PUT {endpoint}/scan/azureKeyVaults/{azureKeyVaultName}` | Create-or-replace | |
| Credential | `PUT {endpoint}/scan/credentials/{credentialName}` | Create-or-replace | |

`{endpoint}` is `https://<PurviewAccountName>.purview.azure.com`. Both names are constrained to
**3-63 characters** matching `^[A-Za-z0-9]+(?:-[A-Za-z0-9]+)*$` - alphanumerics separated by
single hyphens; no underscores, no leading/trailing hyphen.

### Key Vault connection body

| Property | Type | Required | Value |
|---|---|---|---|
| `properties.baseUrl` | string | Effectively yes | Vault DNS name, e.g. `https://kv-contoso-purview.vault.azure.net/` |
| `properties.description` | string | No | Free text |

### Credential body - kind → `typeProperties` shape

| `kind` | Portal name | `properties` type | `typeProperties` |
|---|---|---|---|
| `SqlAuth` | SQL authentication | `UserPassCredentialProperties` | `{ user, password: KeyVaultSecret }` |
| `BasicAuth` | Basic authentication | `UserPassCredentialProperties` | `{ user, password: KeyVaultSecret }` |
| `ServicePrincipal` | Service Principal | `ServicePrincipalAzureKeyVaultCredentialProperties` | `{ servicePrincipalId, servicePrincipalKey: KeyVaultSecret, tenant }` |

Microsoft's full `CredentialType` enum also includes `AccountKey`, `AmazonARN`, `ConsumerKeyAuth`,
`DelegatedAuth`, and `ManagedIdentity`. This scenario scripts the three that
the SQL-family scan kinds in this library actually consume; see the known limitations.

### `KeyVaultSecret` (the secret reference)

| Property | Type | Value written by this scenario |
|---|---|---|
| `secretName` | string | `-SecretName` - the secret's name in the vault |
| `secretVersion` | string | `-SecretVersion` if supplied; omitted otherwise |
| `store.referenceName` | string | `-KeyVaultConnectionName` |
| `store.type` | string | `LinkedServiceReference` - **VERIFY, see the known limitations** |
| `type` | string | `AzureKeyVaultSecret` - **VERIFY, see the known limitations** |

### Deploy script parameters (selected)

| Parameter | Default | Notes |
|---|---|---|
| `-CredentialType` | `SqlAuth` | `SqlAuth` \| `BasicAuth` \| `ServicePrincipal` |
| `-KeyVaultBaseUrl` | *(none)* | Supply to create/reconcile the connection; omit to require it already exists |
| `-SecretVersion` | *(none)* | Omit so rotations need no Purview change - see section 8 |
| `-UserName` | *(none)* | Required for `SqlAuth`/`BasicAuth` |
| `-ServicePrincipalId` | *(none)* | Required for `ServicePrincipal`; must **not** equal `-AppId` |
| `-ServicePrincipalTenantId` | `-TenantId` | Override for a cross-tenant service principal |
| `-SecretReferenceType` | `AzureKeyVaultSecret` | Parameterized because it is a VERIFY |
| `-SecretStoreReferenceType` | `LinkedServiceReference` | Same |
| `-ApiVersion` | `2023-09-01` | Version under which every endpoint here was grounded |

Worked request bodies for all three kinds: `deploy/policy/scan-credential-definitions.json`.

### Consuming scan kinds

| Scan kind | Used by | Typical credential |
|---|---|---|
| `AzureSqlDatabaseCredential` | Azure SQL where SAMI is unavailable (e.g. self-hosted IR) | `SqlAuth` or `ServicePrincipal` |
| `SqlServerDatabaseCredential` | *Scan On-Premises SQL Server and Classify Sensitive Columns* | `SqlAuth` (or `BasicAuth` for Windows auth - VERIFY, the known limitations) |

The scan references the credential as
`properties.credential = { credentialType = '<kind>'; referenceName = '<CredentialName>' }`.

## Operations and tuning

**Rotation is the main recurring operation.** Which path applies depends on one choice made at
deploy time:

| Deployed with | Rotating the secret in Key Vault | Purview change needed | Tradeoff |
|---|---|---|---|
| No `-SecretVersion` (default) | Add a new version of the secret | **None** - re-run `validate/` to confirm | Convenient, but it means **anyone who can write a new version of that secret can silently change what a scan authenticates as**, with no Purview-side change and no Purview-side record |
| `-SecretVersion` pinned | Add a new version | Re-run `deploy/New-PurviewScanCredential.ps1` with the new `-SecretVersion` | A vault-side change alone cannot take effect; the swap requires a Purview deploy that is visible in your pipeline's history |

This is a genuine security/operability tradeoff, not just a convenience setting. Omit the version
when the vault's own access control and audit logging are the intended boundary; **pin it when
Purview's configuration should be the change-control point** - for example when the vault is
administered by a different team from the one that owns scanning. (That the omitted case resolves
to "latest" is itself a VERIFY - the known limitations.)

**KPIs / what to watch**

| Signal | Where | Healthy | Act when |
|---|---|---|---|
| Scan runs using this credential | Purview portal → **Data Map → Monitoring** | `Succeeded` | Any authentication-class failure - go to the runbook below |
| Secret expiry | `validate/... -CheckKeyVaultSecret` | No expiry, or > 30 days out | Warned at ≤ 30 days; rotate before it lapses |
| Credential inventory drift, estate-wide | *Scan Credential Inventory & Drift Report* - scripted, scheduled, diffed against a checked-in expected-state file, all eight documented credential kinds | `Match` (or `NotTracked` for legitimate new onboarding) for every credential | Any `Drift`/`Missing` status - the estate-wide version of the single-credential check below, built specifically to close this section's compensating-control gap |
| Credential **re-point** (same name, different target) | `validate/...` run with **all** `-Expected*` parameters supplied, from a checked-in parameter file - or the estate-wide report above | All `[PASS]` | Any `[FAIL]` on secret name, connection, or kind - the object was re-pointed without being renamed; see the known limitations |
| Key Vault secret reads by Purview | Key Vault **diagnostic logs** (`AuditEvent`) | Reads correlate with scan schedule | Reads outside scan windows, or from an unexpected identity |

Run `validate/` on a schedule (weekly, or in the same pipeline that deploys scans) rather than
only at deploy time - it is the cheapest way to catch a secret that was deleted, disabled, or
allowed to expire before a scan fails on it.

**Runbook - a scan that was working starts failing to authenticate**

1. Run `validate/Test-PurviewScanCredential.ps1 ... -CheckKeyVaultSecret`. It distinguishes the
   four common causes immediately.
2. If the **secret is missing/disabled/expired** - restore or rotate it in Key Vault. No Purview
   change unless a version is pinned.
3. If the **credential object is gone or re-pointed** - someone re-ran deploy with different
   parameters, or deleted it. Re-deploy from your parameter file.
4. If **everything validates but the scan still fails** - the failure is on one of the two legs
   this scenario cannot inspect:
   - *Purview → Key Vault:* confirm the Purview managed identity still has **Get** + **List** on
     secrets (or **Key Vault Secrets User**), and that a vault firewall/private-endpoint change
     hasn't blocked it. Verify the secret **name and version**
     are exactly the ones the credential references.
   - *Credential → data source:* the stored password expired at the source, the SQL login was
     disabled, or its `db_datareader` grant was dropped.
5. Escalate if the credential and the vault both validate and the source login is confirmed good -
   that points at the scan object or the integration runtime, not this scenario's objects.

**Naming.** Name credentials after *what they authenticate to*, not the secret
(`onprem-sql-svc-account`, not `kv-secret-3`). The name is what appears in every scan object's
`referenceName` and is the only handle an operator sees when triaging.

## Rollback and decommission

See the rollback runbook. Summary: `deploy/Remove-PurviewScanCredential.ps1` deletes the credential, and
with `-RemoveKeyVaultConnection` the connection too - refusing that second delete while any other
credential still references the same connection (override with `-Force`). Both deletes return
`204 No Content` on success, and a `404` (already gone) is treated as success so
the script is safe to re-run. **Order matters:** re-point or remove any scan that references the
credential *first*, or that scan silently starts failing at its next run - the rollback runbook's
**Stage 0** enumerates those consumers, since no reverse lookup exists.

## References

1. [Credential - Create Or Replace (Purview Scanning data plane, 2023-09-01)](https://learn.microsoft.com/rest/api/purview/scanningdataplane/credential/create-or-replace) - `PUT /scan/credentials/{credentialName}`, all eight credential kinds, `KeyVaultSecret`/`Store`/`UserPassCredentialProperties`/`KeyVaultSecretServicePrinipalCredentialTypeProperties` definitions, name pattern, `CredentialType` enum.
2. [Credential - List](https://learn.microsoft.com/rest/api/purview/scanningdataplane/credential/list) - `GET /scan/credentials`, `{ count, nextLink, value[] }` envelope.
3. [Credential - Delete](https://learn.microsoft.com/rest/api/purview/scanningdataplane/credential/delete) - `DELETE /scan/credentials/{credentialName}` → 204.
4. [Key Vault Connections - Create Or Replace](https://learn.microsoft.com/rest/api/purview/scanningdataplane/key-vault-connections/create-or-replace) - `PUT /scan/azureKeyVaults/{azureKeyVaultName}`, `AzureKeyVaultProperties { baseUrl, description }`, worked example (whose response `id` ends in `/linkedservices/...`).
5. [Scanning Data Plane - REST operation groups](https://learn.microsoft.com/rest/api/purview/scanningdataplane/operation-groups) - confirms Credential and Key Vault Connections are first-class documented operation groups.
6. [Credentials for source authentication in Microsoft Purview Data Map](https://learn.microsoft.com/purview/data-map-data-scan-credentials) - supported credential types, Key Vault connection prerequisite, portal steps, and the Purview managed identity's **Get** + **List** secret permissions / **Key Vault Secrets User** role.
7. [Tutorial: Use REST APIs to authenticate for Microsoft Purview data-plane APIs](https://learn.microsoft.com/purview/data-gov-api-rest-data-plane) - token acquisition and data-plane role assignment.
8. [Microsoft.DataFactory linkedservices - `AzureKeyVaultSecretReference`](https://learn.microsoft.com/azure/templates/microsoft.datafactory/2017-09-01-preview/factories/linkedservices) - the structural analog behind this scenario's two VERIFY literal defaults: `type` is a required `'AzureKeyVaultSecret'`, `store` is a `LinkedServiceReference`, `secretVersion` defaults to the latest version.
9. [Troubleshoot your scans and connections in the Microsoft Purview Data Map](https://learn.microsoft.com/purview/troubleshoot-connections) - verifying the right secret name and version, and the Purview managed identity's Get/List permissions on the vault.
10. [Create a service principal for use with Microsoft Purview](https://learn.microsoft.com/purview/data-map-service-principal) - storing the service-principal secret in Key Vault and creating the matching credential.
11. [Get-AzKeyVaultSecret](https://learn.microsoft.com/powershell/module/az.keyvault/get-azkeyvaultsecret) - metadata read; the value is only returned with `-AsPlainText`, which `validate/` never passes.
12. [Scans and ingestion in Data Map](https://learn.microsoft.com/purview/data-map-scan-ingestion) - the supported authentication methods and Microsoft's "use a Managed Identity whenever possible" guidance.
13. [Audit logs, diagnostics, and activity history](https://learn.microsoft.com/purview/data-gov-classic-audit-logs-diagnostics) - the enumerated Management audit-event categories (Collections, Role assignments, Scan rule set, Classification rule, Scan, Data source). **Credentials and Key Vault connections do not appear.** Note this page is written for the classic governance portal and states more categories will be added - see the known limitations.
14. [Supported logs for microsoft.purview/accounts](https://learn.microsoft.com/azure/azure-monitor/reference/supported-logs/microsoft-purview-accounts-logs) - the three diagnostic-setting log categories (`DataSensitivityLogEvent`, `ScanStatusLogEvent`, `Security`) and the `PurviewSecurityLogs` table's documented scope.
15. [Manage domains and collections in Microsoft Purview Data Map](https://learn.microsoft.com/purview/data-map-domains-collections-manage) - the Data Map collection roles. **Data source administrator** is defined as managing "data sources and scans"; credentials are not named in any role description - see the VERIFY in the prerequisites.
16. [Data governance best practices for security - Credential management](https://learn.microsoft.com/purview/data-gov-classic-security-best-practices) - Microsoft's explicit credential priority order (Purview managed identity → user-assigned managed identity → service principal → account key/SQL auth) and the requirement that Purview have get/list access to secrets on the Key Vault resource.

Related scenarios in this library:
- *Scan On-Premises SQL Server and Classify Sensitive Columns* - the primary consumer
  (`SqlServerDatabaseCredential`); its `-CredentialReferenceName` prerequisite is what this
  scenario creates.
- *Scan Azure SQL Database and Classify Sensitive Columns* - the SAMI-based default path; use that unless
  you specifically cannot.
- *Scan Credential Inventory & Drift Report* - the estate-wide, scheduled drift-detection
  companion that closes this section's "no documented detective control" gap.
- *Scan Credentials: Remaining Kinds (Account Key, Role ARN, Consumer Key, Delegated Auth, User-Assigned Managed Identity)* - scripts the five credential kinds this
  scenario leaves out (`AccountKey`, `AmazonARN`, `ConsumerKeyAuth`, `DelegatedAuth`,
  `ManagedIdentity`), reusing this scenario's `Remove-PurviewScanCredential.ps1` for deletion.
- [RBAC model, section 5](/docs/rbac-model/#5-data-governance-roles-data-map--unified-catalog---a-separate-model) - Data Map collection roles.
- [Automation surface](/docs/automation-surface/) - surface 4 (Purview data-plane REST).