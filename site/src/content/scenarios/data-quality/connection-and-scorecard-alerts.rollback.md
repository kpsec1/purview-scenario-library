---
part: "rollback"
parent: "data-quality/connection-and-scorecard-alerts"
---
## Recommended sequence

Like the sibling `rules-and-scorecards` scenario, this scenario's objects don't act on live M365
traffic — removing them stops future scans (removing the connection) or future notifications
(removing an alert), but never touches the source data or any Microsoft 365 control. Rollback is
staged so you can stop alerting without losing a comparatively expensive-to-reprovision connection.

### Stage 1 — Remove the alerts only (keep the connection)

```powershell
./deploy/Remove-DataQualityConnectionAndAlerts.ps1 `
    -PurviewAccountEndpoint 'https://api.purview-service.microsoft.com' `
    -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
    -AlertDefinitionPath './deploy/alerts/customer-master-score-alerts.json'
```

Deletes every alert named in the definition file. The connection stays in place — scans scheduled
by `rules-and-scorecards` continue to run and score the asset, but no notification fires on a
regression.

Use this stage for: pausing alerting (e.g. during a known data-migration change freeze where score
regressions are expected and would otherwise generate noise) while keeping the connection intact.
For a shorter pause where you intend to resume with the same alert definitions, prefer
`New-DataQualityAlert.ps1 -SetStatus Disabled` instead (see below) — it's non-destructive and
faster to reverse than a delete/recreate cycle.

If the product-level companion example (`customer-360-product-score-alert.json`, README.md §11)
was also deployed, run this same command a second time with
`-AlertDefinitionPath './deploy/alerts/customer-360-product-score-alert.json'` — each definition
file is removed independently, matching how each was deployed.

### Stage 2 — Also remove the data-source connection

```powershell
./deploy/Remove-DataQualityConnectionAndAlerts.ps1 `
    -PurviewAccountEndpoint 'https://api.purview-service.microsoft.com' `
    -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
    -AlertDefinitionPath './deploy/alerts/customer-master-score-alerts.json' `
    -ConnectionDefinitionPath './deploy/connection/customer-sql-connection.json' `
    -RemoveConnection
```

Deletes both the alerts (Stage 1) and the data-source connection. **Any scan scheduled by
`rules-and-scorecards` against this connection will start failing** the next time it fires —
remove or repoint that schedule first if a hard stop of scanning (not just alerting) isn't the
intent.

### Alternative to deletion — pause without removing

```powershell
# Pause both alerts without deleting their definitions
./deploy/New-DataQualityAlert.ps1 `
    -PurviewAccountEndpoint 'https://api.purview-service.microsoft.com' `
    -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
    -AlertDefinitionPath './deploy/alerts/customer-master-score-alerts.json' `
    -SetStatus Disabled

# Resume later
./deploy/New-DataQualityAlert.ps1 `
    -PurviewAccountEndpoint 'https://api.purview-service.microsoft.com' `
    -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
    -AlertDefinitionPath './deploy/alerts/customer-master-score-alerts.json' `
    -SetStatus Enabled
```

Prefer this over Stage 1 when the intent is a temporary pause rather than a teardown — it's a
single lightweight `PATCH` per alert (`Update Alert Status`) rather than a delete followed by a
full re-create, and it preserves `createdAt`/`createdBy` history on the alert object.

## What rollback does **not** undo

- **The managed-VNet compute location or private endpoint**, if `-EnableManagedVNet` was used.
  Deleting the connection object does not de-provision either — both are shared, per-region,
  per-Purview-account resources (`design.md` §3) that other connections in other governance
  domains may also depend on. De-provision the region explicitly under **Settings > Unified
  Catalog > Virtual network** only after confirming no other connection still needs it — deleting a
  region cascades to remove *every* connection linked to it, not just this scenario's
  (`README.md` reference 5).
- **The source database's read grant** (e.g. `db_datareader`) — a source-side action this scenario
  never created; remove it separately if the intent is a full teardown.
- **The governance domain, data product, or data asset.** None of these were created by this
  scenario — see `design.md` §6/§7 — so none are removed by rollback.
- **The Data Quality rules or scan schedule** from `scenarios/data-quality/rules-and-scorecards/` —
  a separate scenario with its own rollback procedure. Removing this scenario's connection without
  also addressing that schedule leaves it pointing at a now-deleted connection (it will fail, not
  silently no-op).
- **Prior alert-fire history** (past notification emails already sent) — nothing to undo; email
  delivery isn't a Purview-managed record.

## Verification after rollback

```powershell
# After Stage 1: expect the alert GET(s) to 404; connection GET to still succeed.
# After Stage 2: expect both the alert GET(s) and the connection GET to 404/fail.
./validate/Test-DataQualityConnectionAndAlerts.ps1 `
    -PurviewAccountEndpoint 'https://api.purview-service.microsoft.com' `
    -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
    -ConnectionDefinitionPath './deploy/connection/customer-sql-connection.json' `
    -AlertDefinitionPath './deploy/alerts/customer-master-score-alerts.json'
```

After Stage 1, expect `[FAIL]` on every alert-existence check and `[PASS]` on the connection
checks — this is the correct, expected signal that Stage 1 succeeded, not a problem. After Stage 2,
expect `[FAIL]` on the connection-existence check too. Treat a non-zero exit code as expected in
both post-rollback contexts rather than as a regression.
