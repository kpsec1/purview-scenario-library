---
part: "rollback"
parent: "data-map/scan-azure-sql-and-classify-managed-identity-credential"
---
## Recommended sequence

Like the base `scan-azure-sql-and-classify` scenario, rolling this back never touches the source
database or live Microsoft 365 traffic - it only changes which identity a future scan run
authenticates as. Rollback is staged so you can revert the scan's authentication without deleting
the UAMI or the `ManagedIdentity` credential object (e.g. you plan to reuse either later, or on a
different scan).

### Stage 1 - Revert the scan to SAMI authentication (keep the UAMI and credential object)

```powershell
./deploy/Remove-AzureSqlManagedIdentityCredentialScan.ps1 `
    -PurviewAccountName 'contoso-purview' -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
    -DataSourceName 'sql-contoso-prod-customerdb'
```

Reverts the scan's `kind` from `AzureSqlDatabaseCredential` back to `AzureSqlDatabaseMsi` (every
other property - database name, server endpoint, collection, scan rule set - left unchanged). The
UAMI and the `ManagedIdentity` credential object referencing it stay defined, so they can be
re-applied later, or wired into a different scan.

**Before running Stage 1**, confirm the Purview account's own SAMI still holds the Azure IAM Reader
grant and `db_datareader` external-provider user this scan depended on before the UAMI was adopted
(`scan-azure-sql-and-classify/README.md` §3/§5). If either was removed when the UAMI was granted
access, re-establish it first - otherwise the reverted scan will register successfully but fail on
its next run, the same failure mode `scan-azure-sql-and-classify/README.md` §8's incident-response
runbook already covers for a revoked SAMI grant.

Use this stage for: temporarily or permanently moving back to the shared-SAMI model (e.g.
decommissioning the per-source identity-separation program) while keeping the UAMI and credential
object available to re-apply to this or another scan later.

### Stage 2 - Also remove the credential object (and, separately, the UAMI itself)

This scenario's own scripts never delete the `ManagedIdentity` credential object or the UAMI - both
are prerequisites this scenario only ever consumed by reference (`design.md` §2 goal 2). To remove
them:

```powershell
# Remove the Purview credential object (only after confirming no other scan still references it -
# see scan-credential-remaining-kinds/rollback.md for the full staged procedure and its own caveats).
# Remove-PurviewScanCredential.ps1 is kind-agnostic and lives in the original parent scenario's
# deploy/ folder - scan-credential-remaining-kinds reuses it unmodified rather than duplicating it.
../scan-credential-key-vault-backed/deploy/Remove-PurviewScanCredential.ps1 `
    -PurviewAccountName 'contoso-purview' -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
    -CredentialName 'sql-contoso-uami'
```

Deleting the UAMI resource itself (and its Azure IAM/SQL grants) is an Azure-side action via the
Purview account's **Managed identities** blade or Azure Resource Manager - outside the Purview
Scanning data-plane API this repo's scripts call, and outside this scenario's scope. **Confirm no
other scan or credential object still references this UAMI before deleting it** - a UAMI is a
resource that can be shared across multiple credential objects and, in turn, multiple scans and
source types (`scan-credential-remaining-kinds/README.md` §3).

## What rollback does **not** undo

- **Classifications already applied by prior scan runs**, under either identity. Removing or
 reverting the authentication path only changes what a *future* scan run authenticates as; it does
 not retroactively change or remove classification tags already recorded on catalog assets.
- **The base scenario's data source and scan registration.** Both Stage 1 and Stage 2 only ever
 modify the scan's `kind`/`credential` properties or the credential object; deleting the scan or
 data source entirely is `scan-azure-sql-and-classify`'s own rollback - see that scenario's
 `rollback.md`.
- **The UAMI's Azure IAM Reader grant or SQL `db_datareader` permission.** Neither this scenario's
 scripts nor Stage 2's credential-object removal touch either grant - both are ARM/SQL-side objects
 outside the Purview Scanning data-plane API entirely. Remove them separately if the UAMI itself is
 being decommissioned.
- **Any other scan or credential object still referencing the same UAMI.** Stage 2's credential
 removal does nothing to detect a *different* credential object pointing at the same UAMI's
 `principalId`/`resourceId` - check manually (or via
 `scenarios/data-map/scan-credential-inventory-report/`) first.

## Verification after rollback

```powershell
$token = <acquire via the same client-credentials flow documented in the deploy script>
$headers = @{ Authorization = "Bearer $token" }

# Stage 1: confirm the scan is back on SAMI authentication.
$scan = Invoke-RestMethod -Method Get -Headers $headers `
    -Uri "https://<PurviewAccountName>.purview.azure.com/scan/datasources/<DataSourceName>/scans/<ScanName>?api-version=2023-09-01"
if ($scan.kind -eq 'AzureSqlDatabaseMsi') { Write-Host "Confirmed: scan reverted to SAMI authentication." -ForegroundColor Green }
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
