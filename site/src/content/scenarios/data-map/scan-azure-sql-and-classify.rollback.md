---
part: "rollback"
parent: "data-map/scan-azure-sql-and-classify"
---
## Recommended sequence

Unlike a DLP or auto-labeling policy, a Data Map scan does not act on live traffic, removing it
stops future discovery/classification but never affects the source database or any Microsoft 365
control. Rollback here is lower-stakes, but still staged so you can pause at "stop the recurring
schedule" without losing the registration.

### Stage 1, Remove the recurring trigger only (keep the scan and source)

```powershell
# Manually, via REST (no dedicated flag in Remove-AzureSqlDataMapScan.ps1 for trigger-only removal
# beyond what running it without -RemoveDataSource already does - both the trigger and the scan
# are removed together in Stage 2). To pause without removing anything, disable the trigger by
# re-running the deploy script without -RecurrenceFrequency is NOT sufficient (create-or-replace
# would leave an existing trigger untouched, since no trigger call is made when the parameter is
# omitted) - delete the trigger explicitly:
$token = <acquire via the same client-credentials flow documented in the deploy script>
Invoke-RestMethod -Method Delete `
    -Uri "https://<PurviewAccountName>.purview.azure.com/scan/datasources/<DataSourceName>/scans/<ScanName>/triggers/default?api-version=2023-09-01" `
    -Headers @{ Authorization = "Bearer $token" }
```

Use this stage for: pausing the recurring schedule (e.g. during a change freeze) while keeping the
scan and data source registered for a later on-demand run via `-RunNow`.

### Stage 2, Remove the scan and trigger, keep the data source registered

```powershell
./deploy/Remove-AzureSqlDataMapScan.ps1 `
    -PurviewAccountName 'contoso-purview' -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
    -DataSourceName 'sql-contoso-prod-customerdb'
```

Removes the scan object and its trigger (if any). The data source stays registered under its
collection, so a new scan (potentially with a different scan rule set or authentication method)
can be added later without re-registering the source. Catalog assets already ingested from prior
scan runs are **not** deleted (Microsoft's own documentation: "Deleting your scan does not delete
catalog assets created from previous scans", `README.md` reference 1).

### Stage 3, Full removal (data source too)

```powershell
./deploy/Remove-AzureSqlDataMapScan.ps1 `
    -PurviewAccountName 'contoso-purview' -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
    -DataSourceName 'sql-contoso-prod-customerdb' -RemoveDataSource
```

Also deletes the data source registration. Re-establishing the control means re-running
`deploy/New-AzureSqlDataMapScan.ps1` from scratch, including re-verifying the two out-of-band
grants (Azure IAM Reader for the SAMI, `db_datareader` for the SAMI in the database) are still in
place.

## What rollback does **not** undo

- **Catalog assets and classifications already ingested.** Existing schema, lineage, and
  classification tags from prior successful scan runs remain in the Data Map/Unified Catalog after
  the scan or data source is removed. There is no cascading delete.
- **The two out-of-band grants.** This scenario's deploy script does not create the Azure IAM
  `Reader` role assignment or the SQL `db_datareader` grant for the Purview SAMI, removing the
  scan does not remove them either. Clean those up separately (Azure portal IAM removal; a T-SQL
  `DROP USER` for the SAMI's database user) if the intent is a full teardown rather than a
  scan-configuration rollback.
- **Scan run history.** Prior run records remain visible in the Purview portal's Monitoring view
  for their standard 90-day retention window regardless of whether the scan object still exists.

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

Or, in the portal: **Data Map → Data sources** → the source should show no scans (Stage 2) or
should no longer appear at all (Stage 3).
