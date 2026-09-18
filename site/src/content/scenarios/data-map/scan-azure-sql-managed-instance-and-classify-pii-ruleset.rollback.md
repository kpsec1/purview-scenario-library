---
part: "rollback"
parent: "data-map/scan-azure-sql-managed-instance-and-classify-pii-ruleset"
---
## Recommended sequence

Like the base `scan-azure-sql-managed-instance-and-classify` scenario, rolling this back never
touches the managed instance's data or live Microsoft 365 traffic — it only changes which
classifications a future scan run compares columns against. Rollback is staged so you can revert
the scan without deleting the ruleset object (e.g. you plan to reuse it on another scan later).

### Stage 1 — Revert the scan to the System default ruleset (keep the custom ruleset object)

```powershell
./deploy/Remove-PiiOnlyScanRuleset.ps1 `
    -PurviewAccountName 'contoso-purview' -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
    -DataSourceName 'mi-contoso-prod-customerdb'
```

Reverts `scanRulesetName`/`scanRulesetType` on the target scan back to
`AzureSqlDatabaseManagedInstance`/`System` (every other scan property — authentication kind, server
endpoint, database name, collection — left unchanged). The custom
`AzureSqlDatabaseManagedInstance-PiiOnly` ruleset object stays defined, so a differently configured
scan (or this same scan again later) can reference it without recreating it.

**This source type has no naming trap** — the revert target's ruleset **name**
(`AzureSqlDatabaseManagedInstance`) is the identical string to the ruleset `kind` used when
creating the custom object, confirmed independently for this source type rather than assumed from
either sibling scenario — see `design.md` §2 goal 6 and `README.md` §11. (Contrast with the Azure
Synapse Analytics sibling, where the revert-target name and the custom ruleset `kind` are two
different strings — do not carry that scenario's `-RevertToRulesetName` value over here, or vice
versa.)

Use this stage for: temporarily reverting to full-spectrum classification (e.g. a one-time audit
that needs the full ~200-classification sweep) while keeping the PII-only ruleset available to
re-apply afterward.

### Stage 2 — Also delete the custom ruleset object

```powershell
./deploy/Remove-PiiOnlyScanRuleset.ps1 `
    -PurviewAccountName 'contoso-purview' -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
    -DataSourceName 'mi-contoso-prod-customerdb' -DeleteRuleset
```

Performs Stage 1's scan revert first, then deletes the `AzureSqlDatabaseManagedInstance-PiiOnly`
scan rule set object itself. **Confirm no other scan in the account still references this ruleset
name before running with `-DeleteRuleset`** — scan rule sets are account-wide objects (design.md
§2), so a ruleset created for one instance's scan may already be reused by another.

## What rollback does **not** undo

- **Classifications already applied by prior scan runs.** Removing or narrowing the ruleset only
  changes what a *future* scan run compares columns against. Classification tags already recorded
  on catalog assets from runs made under the PII-only ruleset (or the System ruleset, before this
  scenario was applied) are not retroactively changed or removed.
- **The base scenario's data source and scan registration, or the out-of-band ARM/Entra/SQL
  prerequisites.** This scenario only ever modifies the scan's `scanRulesetName`/`scanRulesetType`
  properties. Removing the scan or data source entirely, un-granting the Azure IAM Reader role and
  the `db_datareader` SQL grant, disabling the public endpoint, or removing the Directory Readers
  Microsoft Entra role assignment is `scan-azure-sql-managed-instance-and-classify`'s own rollback
  — see that scenario's `rollback.md`.
- **Any other scan still referencing this ruleset.** Stage 2's delete only proceeds after this
  scenario's own scan has been detached; it does nothing to detect or detach a *different* scan
  that references the same ruleset name. Check manually (or via
  `validate/Test-PiiOnlyScanRuleset.ps1` against each candidate data source/scan pair) first.

## Verification after rollback

```powershell
$token = <acquire via the same client-credentials flow documented in the deploy script>
$headers = @{ Authorization = "Bearer $token" }

# Stage 1: confirm the scan is back on the System ruleset.
$scan = Invoke-RestMethod -Method Get -Headers $headers `
    -Uri "https://<PurviewAccountName>.purview.azure.com/scan/datasources/<DataSourceName>/scans/<ScanName>?api-version=2023-09-01"
if ($scan.properties.scanRulesetType -eq 'System') { Write-Host "Confirmed: scan reverted to System ruleset ($($scan.properties.scanRulesetName))." -ForegroundColor Green }
else { Write-Warning "Scan still references a Custom ruleset: $($scan.properties.scanRulesetName)" }

# Stage 2: confirm the ruleset object is gone (expect a 404).
try {
    Invoke-RestMethod -Method Get -Headers $headers `
        -Uri "https://<PurviewAccountName>.purview.azure.com/scan/scanrulesets/<ScanRulesetName>?api-version=2023-09-01"
    Write-Warning "Scan rule set still exists."
}
catch {
    if ($_.Exception.Response.StatusCode -eq 404) { Write-Host "Confirmed: scan rule set removed." -ForegroundColor Green }
    else { throw }
}
```

Or, in the portal: **Data Map → Management → Scan rule sets → Custom** tab should no longer list
the ruleset (Stage 2), and the scan's configuration pane should show
**AzureSqlDatabaseManagedInstance (System)** as its rule set (Stage 1).
