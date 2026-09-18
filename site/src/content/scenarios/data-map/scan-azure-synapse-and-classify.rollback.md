---
part: "rollback"
parent: "data-map/scan-azure-synapse-and-classify"
---
## Recommended sequence

Structurally identical to both sibling scenarios' rollback: a Data Map scan does not act on live
traffic, so removing it stops future discovery/classification but never affects the Synapse workspace
or any Microsoft 365 control. Rollback is staged so you can pause at "stop the recurring schedule"
without losing the registration.

### Stage 1, Remove the recurring trigger only (keep the scan and source)

```powershell
# No dedicated flag in Remove-AzureSynapseDataMapScan.ps1 for trigger-only removal beyond what running
# it without -RemoveDataSource already does (both the trigger and the scan are removed together in
# Stage 2). To pause without removing anything else, delete the trigger explicitly:
$token = <acquire via the same client-credentials flow documented in the deploy script>
Invoke-RestMethod -Method Delete `
    -Uri "https://<PurviewAccountName>.purview.azure.com/scan/datasources/<DataSourceName>/scans/<ScanName>/triggers/default?api-version=2023-09-01" `
    -Headers @{ Authorization = "Bearer $token" }
```

Use this stage for: pausing the recurring schedule (e.g. during a change freeze) while keeping the
scan and data source registered for a later on-demand run via `-RunNow`.

### Stage 2, Remove the scan and trigger, keep the data source registered

```powershell
./deploy/Remove-AzureSynapseDataMapScan.ps1 `
    -PurviewAccountName 'contoso-purview' -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
    -DataSourceName 'ws-contoso-prod'
```

Removes the scan object and its trigger (if any). The data source (the workspace registration) stays
registered under its collection. Catalog assets already ingested from prior scan runs are **not**
deleted, same documented behavior as both sibling scenarios.

### Stage 3, Full removal (data source too)

```powershell
./deploy/Remove-AzureSynapseDataMapScan.ps1 `
    -PurviewAccountName 'contoso-purview' -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
    -DataSourceName 'ws-contoso-prod' -RemoveDataSource
```

Also deletes the data source registration. Re-establishing the control means re-running
`deploy/New-AzureSynapseDataMapScan.ps1` from scratch, including re-verifying all out-of-band
prerequisites (workspace Reader grant, serverless-only Storage Blob Data Reader grant, per-database
enumeration login and `db_datareader` grants, workspace firewall setting) are still in place.

### Stage 4 (optional, Synapse-specific), Revoke the serverless-only Azure IAM grants

Unlike the logical-server sibling scenario (whose only Azure IAM grant is a single Reader role) and
similar in spirit to the Managed Instance sibling's tenant-level Directory Readers step, this
scenario's serverless scanning depends on a **second** Azure IAM grant (Storage Blob Data Reader on
the associated storage account) beyond the shared workspace-level Reader role. If a full teardown
should also revert it:

1. Confirm no other workload depends on the Purview account's SAMI holding Storage Blob Data Reader on
   this storage account, revoking it can affect any other Purview scan that reuses the same SAMI
   against the same storage account (e.g. an ADLS Gen2 Data Map scenario sharing the account).
2. An **Owner** or **User Access Administrator** removes the Purview account's Storage Blob Data
   Reader role assignment on the resource group/subscription scope it was granted at (Azure portal →
   the scope → **Access control (IAM)** → find the assignment → **Remove**).

This step is deliberately **not** part of `Remove-AzureSynapseDataMapScan.ps1`, it is an Azure IAM
change outside this scenario's automation identity's own Purview role scope, and revoking it can
silently break unrelated Purview scans sharing the same SAMI and storage account. Treat it as a
manually-confirmed, out-of-band step.

## What rollback does **not** undo

- **Catalog assets and classifications already ingested.** Same as both sibling scenarios, no
  cascading delete.
- **The out-of-band grants and settings.** This scenario's deploy script does not create the workspace
  Reader grant, the serverless-only Storage Blob Data Reader grant, the per-database `CREATE
  LOGIN`/`CREATE USER`/`db_datareader` grants, the external-table scoped-credential grant, or the
  workspace firewall setting, removing the scan does not remove any of them either. Clean up
  separately if the intent is a full teardown; see Stage 4 above for the serverless-specific Azure IAM
  grant.
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
