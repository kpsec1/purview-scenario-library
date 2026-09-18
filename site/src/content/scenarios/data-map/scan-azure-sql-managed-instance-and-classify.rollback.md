---
part: "rollback"
parent: "data-map/scan-azure-sql-managed-instance-and-classify"
---
## Recommended sequence

Structurally identical to the sibling `scan-azure-sql-and-classify` scenario's rollback: a Data Map
scan does not act on live traffic, so removing it stops future discovery/classification but never
affects the managed instance or any Microsoft 365 control. Rollback is staged so you can pause at
"stop the recurring schedule" without losing the registration.

### Stage 1, Remove the recurring trigger only (keep the scan and source)

```powershell
# No dedicated flag in Remove-AzureSqlManagedInstanceDataMapScan.ps1 for trigger-only removal beyond
# what running it without -RemoveDataSource already does (both the trigger and the scan are removed
# together in Stage 2). To pause without removing anything else, delete the trigger explicitly:
$token = <acquire via the same client-credentials flow documented in the deploy script>
Invoke-RestMethod -Method Delete `
    -Uri "https://<PurviewAccountName>.purview.azure.com/scan/datasources/<DataSourceName>/scans/<ScanName>/triggers/default?api-version=2023-09-01" `
    -Headers @{ Authorization = "Bearer $token" }
```

Use this stage for: pausing the recurring schedule (e.g. during a change freeze) while keeping the
scan and data source registered for a later on-demand run via `-RunNow`.

### Stage 2, Remove the scan and trigger, keep the data source registered

```powershell
./deploy/Remove-AzureSqlManagedInstanceDataMapScan.ps1 `
    -PurviewAccountName 'contoso-purview' -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
    -DataSourceName 'mi-contoso-prod-customerdb'
```

Removes the scan object and its trigger (if any). The data source stays registered under its
collection. Catalog assets already ingested from prior scan runs are **not** deleted (Microsoft's
own documentation: "Deleting your scan does not delete catalog assets created from previous scans"
, `README.md` reference 2).

### Stage 3, Full removal (data source too)

```powershell
./deploy/Remove-AzureSqlManagedInstanceDataMapScan.ps1 `
    -PurviewAccountName 'contoso-purview' -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
    -DataSourceName 'mi-contoso-prod-customerdb' -RemoveDataSource
```

Also deletes the data source registration. Re-establishing the control means re-running
`deploy/New-AzureSqlManagedInstanceDataMapScan.ps1` from scratch, including re-verifying all five
out-of-band prerequisites (Microsoft Entra admin on the instance, Directory Readers role,
`db_datareader`, Azure IAM Reader, public endpoint/NSG) are still in place.

### Stage 4 (optional, Managed-Instance-specific), Revoke the Directory Readers role

Unlike the sibling scenario, this scenario's SAMI-authenticated scan depends on a **tenant-level**
Microsoft Entra role grant (Directory Readers) on the managed instance's own managed identity, not
just Purview/Azure IAM roles. If a full teardown should also revert that grant:

1. Confirm no other workload on this managed instance depends on Microsoft Entra authentication, 
 revoking Directory Readers breaks Entra authentication for **all** logins on the instance, not
 just this scenario's scan.
2. A **Privileged Role Administrator** removes the instance's managed identity from the Directory
 Readers role (Azure portal → Microsoft Entra ID → Roles and administrators → Directory Readers →
 remove the member; or the PowerShell equivalent of the grant script in `README.md` reference 3).

This step is deliberately **not** part of `Remove-AzureSqlManagedInstanceDataMapScan.ps1`, it is a
tenant-wide-flavored change outside this scenario's automation identity's own role scope, and
revoking it can silently break unrelated Entra-authenticated logins on the same instance. Treat it
as a manually-confirmed, out-of-band step, same posture this repo takes toward the sibling
scenario's Azure IAM Reader grant.

## What rollback does **not** undo

- **Catalog assets and classifications already ingested.** Same as the sibling scenario, no
 cascading delete.
- **The four out-of-band grants and settings.** This scenario's deploy script does not create the
 Microsoft Entra admin assignment, the Directory Readers role grant, the `db_datareader` grant, the
 Azure IAM `Reader` role assignment, or the public-endpoint/NSG configuration, removing the scan
 does not remove any of them either. Clean up separately if the intent is a full teardown; see
 Stage 4 above for Directory Readers specifically.
- **Scan run history.** Prior run records remain visible in the Purview portal's Monitoring view for
 their standard 90-day retention window regardless of whether the scan object still exists.

## Verification after rollback

```powershell
# Confirms the scan is gone (expect a 404) and, if -RemoveDataSource was used, the data source too.
$token = <acquire via the same client-credentials flow documented in the deploy script>
try {
    Invoke-RestMethod -Method Get `
        -Uri "https://<PurviewAccountName>.purview.azure.com/scan/datasources/<DataSourceName>/scans/<ScanName>?api-version=2023-09-01" `
        -Headers @{ Authorization = "Bearer $token" }
    Write-Warning "Scan still exists."
}
catch {
    if ($_.Exception.Response.StatusCode -eq 404) { Write-Host "Confirmed: scan removed." -ForegroundColor Green }
    else { throw }
}
```

Or, in the portal: **Data Map → Data sources** → the source should show no scans (Stage 2) or should
no longer appear at all (Stage 3).
