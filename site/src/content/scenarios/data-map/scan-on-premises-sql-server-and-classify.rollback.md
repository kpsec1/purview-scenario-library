---
part: "rollback"
parent: "data-map/scan-on-premises-sql-server-and-classify"
---
## Recommended sequence

Extends the three Azure sibling scenarios' rollback pattern with one extra stage: a Data Map scan does
not act on live traffic, so removing it stops future discovery/classification but never affects the
on-premises SQL Server or any Microsoft 365 control. Rollback is staged so you can pause at "stop the
recurring schedule" without losing the registration, or go all the way to decommissioning the SHIR.

### Stage 1, Remove the recurring trigger only (keep the scan, source, and integration runtime)

```powershell
# No dedicated flag in Remove-OnPremisesSqlServerDataMapScan.ps1 for trigger-only removal beyond what
# running it without -RemoveDataSource already does (both the trigger and the scan are removed
# together in Stage 2). To pause without removing anything else, delete the trigger explicitly:
$token = <acquire via the same client-credentials flow documented in the deploy script>
Invoke-RestMethod -Method Delete `
    -Uri "https://<PurviewAccountName>.purview.azure.com/scan/datasources/<DataSourceName>/scans/<ScanName>/triggers/default?api-version=2023-09-01" `
    -Headers @{ Authorization = "Bearer $token" }
```

Use this stage for: pausing the recurring schedule (e.g. during a change freeze) while keeping the
scan, data source, and integration runtime registered for a later on-demand run via `-RunNow`.

### Stage 2, Remove the scan and trigger, keep the data source and integration runtime registered

```powershell
./deploy/Remove-OnPremisesSqlServerDataMapScan.ps1 `
    -PurviewAccountName 'contoso-purview' -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
    -DataSourceName 'sql01-contoso-local'
```

Removes the scan object and its trigger (if any). The data source and integration runtime stay
registered. Catalog assets already ingested from prior scan runs are **not** deleted (Microsoft's own
documentation: "Deleting your scan does not delete catalog assets created from previous scans", 
`README.md` reference 3).

### Stage 3, Also remove the data source registration

```powershell
./deploy/Remove-OnPremisesSqlServerDataMapScan.ps1 `
    -PurviewAccountName 'contoso-purview' -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
    -DataSourceName 'sql01-contoso-local' -RemoveDataSource
```

Deletes the data source registration. The integration runtime resource stays registered, leave it in
place if any other data source's scan still references it. Re-establishing the control means
re-running `deploy/New-OnPremisesSqlServerDataMapScan.ps1` from scratch for the data source and scan
(but not necessarily the integration runtime, if it's still present and healthy).

### Stage 4, Also remove the integration runtime resource (only if nothing else uses it)

```powershell
./deploy/Remove-OnPremisesSqlServerDataMapScan.ps1 `
    -PurviewAccountName 'contoso-purview' -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
    -DataSourceName 'sql01-contoso-local' -RemoveDataSource `
    -IntegrationRuntimeName 'shir-onprem-sql' -RemoveIntegrationRuntime
```

**Before running this stage:** confirm no other data source's scan in this Purview account still
references `-IntegrationRuntimeName`, a single self-hosted integration runtime is commonly shared
across many on-premises sources. Removing the *resource* does not stop the SHIR *software* or its
Windows service on whatever host it's running on; it only removes Purview's registration of it. If the
SHIR node tries to check in after this, it will fail to authenticate (its key is tied to the deleted
resource) but the Windows service itself keeps running until stopped separately.

### Stage 5 (optional, full decommission), Decommission the SHIR host

Not scripted by this repo, this is host-level administration, not a Purview REST operation:

1. On the SHIR host, stop and uninstall the Integration Runtime Windows service (or decommission the
 VM entirely if it was dedicated to this purpose).
2. If the SHIR host also served other integration runtimes or other Purview accounts, do **not**
 decommission it, only remove the node registration specific to this integration runtime (Purview
 portal → **Integration runtimes** → the runtime → **Nodes** tab → select the node → delete).

### What rollback does **not** undo

- **Catalog assets and classifications already ingested.** Same as every sibling scenario, no
 cascading delete.
- **The SHIR software installation and Windows service on its host.** Stage 4 removes Purview's
 registration only, see Stage 5 for the host-level cleanup this repo does not script.
- **The SQL/Windows login, its `db_datareader` grant, the Key Vault secret, and the Purview credential
 object.** This scenario's deploy script never created any of these (§8/§11 of `design.md`/`README.md`)
, removing the scan does not remove any of them either. Clean up separately if the intent is a full
 teardown: drop the login in SSMS, delete the Key Vault secret, and delete the credential object in
 Purview's **Credentials** page.
- **Scan run history.** Prior run records remain visible in the Purview portal's Monitoring view for
 their standard 90-day retention window regardless of whether the scan object still exists.

## Verification after rollback

```powershell
# Confirms the scan is gone (expect a 404) and, if -RemoveDataSource/-RemoveIntegrationRuntime were
# used, the data source and integration runtime too.
$token = <acquire via the same client-credentials flow documented in the deploy script>
foreach ($check in @(
    @{ Label = 'Scan';                 Uri = "https://<PurviewAccountName>.purview.azure.com/scan/datasources/<DataSourceName>/scans/<ScanName>?api-version=2023-09-01" },
    @{ Label = 'Data source';          Uri = "https://<PurviewAccountName>.purview.azure.com/scan/datasources/<DataSourceName>?api-version=2023-09-01" },
    @{ Label = 'Integration runtime';  Uri = "https://<PurviewAccountName>.purview.azure.com/scan/integrationruntimes/<IntegrationRuntimeName>?api-version=2023-09-01" }
)) {
    try {
        Invoke-RestMethod -Method Get -Uri $check.Uri -Headers @{ Authorization = "Bearer $token" } | Out-Null
        Write-Warning "$($check.Label) still exists."
    }
    catch {
        if ($_.Exception.Response.StatusCode -eq 404) { Write-Host "Confirmed: $($check.Label) removed." -ForegroundColor Green }
        else { throw }
    }
}
```

Or, in the portal: **Data Map → Data sources** → the source should show no scans (Stage 2) or should
no longer appear at all (Stage 3); **Data Map → Integration runtimes** → the runtime should no longer
appear (Stage 4).
