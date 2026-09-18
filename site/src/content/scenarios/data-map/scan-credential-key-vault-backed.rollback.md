---
part: "rollback"
parent: "data-map/scan-credential-key-vault-backed"
---
## Before you start, order matters here

Unlike a DLP or labeling policy, this scenario's objects act on nothing by themselves. But they are
a **dependency** of something that does: any scan whose `properties.credential.referenceName`
points at this credential. Deleting the credential first leaves that scan configured and
apparently healthy, and it starts failing at its **next scheduled run** with an authentication
error, possibly days later, with no obvious link back to this rollback.

So the staged sequence below runs consumer-first. There is no API that tells you who the consumers
are (`README.md` §11), so Stage 0 is a manual inventory step, not an optional one.

## Stage 0, Inventory the consumers (do not skip)

List the scans that reference this credential, per data source:

```powershell
# For each registered data source, list its scans and check properties.credential.referenceName.
$token = <acquire via the same client-credentials flow documented in the deploy script>
$endpoint = 'https://<PurviewAccountName>.purview.azure.com'
$headers  = @{ Authorization = "Bearer $token" }

$dataSources = (Invoke-RestMethod -Method Get -Headers $headers `
    -Uri "$endpoint/scan/datasources?api-version=2023-09-01").value

foreach ($ds in $dataSources) {
    $scans = (Invoke-RestMethod -Method Get -Headers $headers `
        -Uri "$endpoint/scan/datasources/$($ds.name)/scans?api-version=2023-09-01").value
    foreach ($s in $scans) {
        if ($s.properties.credential.referenceName -eq '<CredentialName>') {
            "CONSUMER: data source '$($ds.name)' -> scan '$($s.name)'"
        }
    }
}
```

Re-point or remove every scan this prints before continuing. Re-pointing means re-running the
owning scenario's deploy script with a different `-CredentialReferenceName`; removing means that
scenario's own `Remove-*` script (for example
`scenarios/data-map/scan-on-premises-sql-server-and-classify/deploy/Remove-OnPremisesSqlServerDataMapScan.ps1`).

## Stage 1, Remove the credential only (keep the Key Vault connection)

```powershell
./deploy/Remove-PurviewScanCredential.ps1 `
    -PurviewAccountName 'contoso-purview' -TenantId $TenantId -AppId $AppId `
    -ClientSecret $ClientSecret -CredentialName 'onprem-sql-svc-account' -WhatIf
# then re-run without -WhatIf
```

Use this stage for: retiring one credential while other credentials continue to use the same Key
Vault connection, the common case. `DELETE /scan/credentials/{name}` returns 204; a 404 (already
gone) is treated as success, so the script is safe to re-run.

## Stage 2, Full removal (Key Vault connection too)

```powershell
./deploy/Remove-PurviewScanCredential.ps1 `
    -PurviewAccountName 'contoso-purview' -TenantId $TenantId -AppId $AppId `
    -ClientSecret $ClientSecret -CredentialName 'onprem-sql-svc-account' `
    -KeyVaultConnectionName 'kv-contoso-purview' -RemoveKeyVaultConnection
```

The script lists every remaining credential in the account and **refuses** the connection delete
if any other credential still references `kv-contoso-purview`, naming them. That check is
read-only and runs under `-WhatIf` too, so a dry run tells you whether the delete would be blocked.

Override with `-Force` only when those other credentials are also being retired in the same
teardown, deleting the connection out from under them leaves them resolvable as metadata but
broken at scan time.

## Stage 3, Azure-side cleanup (manual, outside this scenario)

Nothing in `deploy/` created these, so nothing in `deploy/` removes them. Do them in this order:

1. **Revoke Purview's access to the vault**, remove the Purview account's access-policy entry
 (Secret permissions Get/List), or its **Key Vault Secrets User** role assignment.
2. **Disable, then delete, the secret**, disable first so a missed consumer surfaces as a clean
 failure rather than a silent fallback. Note the vault's soft-delete retention window: the
 secret remains recoverable (and its name reserved) until it is purged.
3. **Retire the identity the credential pointed at**, drop the SQL login / `db_datareader` grant,
 or delete the scan service principal's app registration and its client secret.

## What rollback does **not** undo

- **Catalog assets and classifications** already ingested by scans that used this credential.
 Removing a credential has no cascading effect on the Data Map, same as removing a scan.
- **Scan run history.** Prior run records stay visible in **Data Map → Monitoring** for their
 standard retention window.
- **The Key Vault secret's value.** A Purview credential never held it, so deleting the credential
 cannot remove or rotate it. Stage 3 step 2.
- **Any scan object.** See Stage 0, this is the failure mode worth repeating.

## Verification after rollback

```powershell
# Expect [FAIL] "Credential ... does not exist", which is the intended post-rollback result.
./validate/Test-PurviewScanCredential.ps1 `
    -PurviewAccountName 'contoso-purview' -TenantId $TenantId -AppId $AppId `
    -ClientSecret $ClientSecret -CredentialName 'onprem-sql-svc-account' `
    -KeyVaultConnectionName 'kv-contoso-purview'
```

The validate script exits 1 when the credential is absent. After a deliberate rollback that
non-zero exit **is** the pass condition, don't wire this invocation into a pipeline gate without
inverting the expectation.

Or, in the portal: **Data Map → Source management → Credentials**, the credential should no
longer be listed, and (after Stage 2) **Manage Key Vault connections** should no longer list the
connection.
