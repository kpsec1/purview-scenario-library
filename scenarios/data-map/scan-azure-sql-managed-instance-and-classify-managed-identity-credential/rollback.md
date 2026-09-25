# Rollback — UAMI Credential for the Azure SQL Managed Instance Scan

## Recommended sequence

Identical staging to the Azure SQL Database sibling
(`scan-azure-sql-and-classify-managed-identity-credential/rollback.md`) — rolling this back never
touches the source database or live Microsoft 365 traffic, only which identity a future scan run
authenticates as.

### Stage 1 — Revert the scan to SAMI authentication (keep the UAMI and credential object)

```powershell
./deploy/Remove-AzureSqlManagedInstanceManagedIdentityCredentialScan.ps1 `
    -PurviewAccountName 'contoso-purview' -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
    -DataSourceName 'mi-contoso-prod-customerdb'
```

Reverts the scan's `kind` from `AzureSqlDatabaseManagedInstanceCredential` back to
`AzureSqlDatabaseManagedInstanceMsi` (every other property — database name, server endpoint,
collection, scan rule set — left unchanged). The UAMI and the `ManagedIdentity` credential object
referencing it stay defined.

**Before running Stage 1**, confirm the Purview account's own SAMI still holds the Azure IAM Reader
grant and `db_datareader` external-provider user this scan depended on before the UAMI was adopted
(`scan-azure-sql-managed-instance-and-classify/README.md` §3/§5). If either was removed, re-establish
it first — otherwise the reverted scan will register successfully but fail on its next run. This
scenario's rollback does **not** need to re-verify the instance-level prerequisites (public
endpoint, Microsoft Entra admin, Directory Readers) — those are orthogonal to which Purview identity
authenticates (`design.md` §2) and are untouched by this scenario's scripts in either direction.

### Stage 2 — Also remove the credential object (and, separately, the UAMI itself)

```powershell
# Remove-PurviewScanCredential.ps1 is kind-agnostic and lives in the original parent scenario's
# deploy/ folder - scan-credential-remaining-kinds reuses it unmodified rather than duplicating it.
../scan-credential-key-vault-backed/deploy/Remove-PurviewScanCredential.ps1 `
    -PurviewAccountName 'contoso-purview' -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
    -CredentialName 'mi-contoso-uami'
```

Deleting the UAMI resource itself is an Azure-side action via the Purview account's **Managed
identities** blade — outside this repo's Scanning data-plane scripts entirely. **Confirm no other
scan or credential object still references this UAMI before deleting it** — the same shared-resource
caveat as the Database sibling.

## What rollback does **not** undo

Identical scope boundary to the Database sibling
(`scan-azure-sql-and-classify-managed-identity-credential/rollback.md`): classifications already
applied by prior scan runs; the base scenario's data source and scan registration (delete via that
scenario's own `rollback.md`); the UAMI's Azure IAM Reader grant or SQL `db_datareader` permission;
any other scan or credential object still referencing the same UAMI. Additionally: the Managed
Instance-specific instance-level prerequisites (public endpoint, Microsoft Entra admin, Directory
Readers role) are never touched by either stage — decommissioning those, if desired, is the base
scenario's own `rollback.md`'s scope, not this fragment's.

## Verification after rollback

```powershell
$token = <acquire via the same client-credentials flow documented in the deploy script>
$headers = @{ Authorization = "Bearer $token" }

# Stage 1: confirm the scan is back on SAMI authentication.
$scan = Invoke-RestMethod -Method Get -Headers $headers `
    -Uri "https://<PurviewAccountName>.purview.azure.com/scan/datasources/<DataSourceName>/scans/<ScanName>?api-version=2023-09-01"
if ($scan.kind -eq 'AzureSqlDatabaseManagedInstanceMsi') { Write-Host "Confirmed: scan reverted to SAMI authentication." -ForegroundColor Green }
else { Write-Warning "Scan still references a credential: kind $($scan.kind), credential $($scan.properties.credential.referenceName)" }

# Stage 2: confirm the credential object is gone (expect a 404).
try {
    Invoke-RestMethod -Method Get -Headers $headers `
        -Uri "https://<PurviewAccountName>.purview.azure.com/scan/credentials/<CredentialName>?api-version=2023-09-01"
    Write-Warning "Credential object still exists."
}
catch {
    if ($_.Exception.Response.StatusCode -eq 404) { Write-Host "Confirmed: credential object removed." -ForegroundColor Green }
    else { throw }
}
```

Or, in the portal: the scan's **Edit** pane should show the system-assigned managed identity under
**Credential** (Stage 1), and **Data Map → Management → Credentials** should no longer list the
named credential object (Stage 2).
