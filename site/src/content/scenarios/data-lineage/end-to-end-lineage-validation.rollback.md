---
part: "rollback"
parent: "data-lineage/end-to-end-lineage-validation"
---
## Recommended sequence

Like this repo's Data Map and Data Quality scenarios, custom lineage relationships don't act on
live M365 traffic or the underlying source data — removing them stops the asserted lineage edge
from appearing in the graph, but never touches either the upstream or downstream table's actual
data or the nightly job that moves it.

### Remove the custom lineage relationship(s)

```powershell
./deploy/Remove-CustomLineageRelationship.ps1 `
    -PurviewAccountEndpoint 'https://api.purview-service.microsoft.com' `
    -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
    -LineageDefinitionPath './deploy/lineage/customer-risk-summary-lineage.json'
```

Deletes every relationship named in the definition file's `customLineageLinks` array via
`Relationship - Delete`, looked up by GUID through the same `Lineage - Get By Unique Attribute`
call the deploy script uses for its existence check — never a hard-coded relationship ID. A link
that's already gone (already deleted, or never successfully created) is reported and skipped
rather than treated as an error, so this script is safe to re-run.

Add `-WhatIf` first to see which relationships would be deleted without deleting them.

## What rollback does **not** undo

- **The upstream or downstream assets themselves.** Neither was created by this scenario (see
  `design.md` §6/§7), so rollback doesn't touch either one — only the lineage edge between them.
- **The nightly transform job.** Not created, deployed, or managed by this scenario; removing the
  lineage assertion has zero effect on whether the job itself keeps running.
- **Any natively-captured lineage elsewhere in the graph** (e.g. a future Power BI report built on
  `CustomerRiskSummary`) — this scenario only ever touched the one custom edge it created.

## Manual portal alternative

If the automation identity's credential is unavailable, the same relationship can be removed
manually: open the upstream asset's **Lineage** tab in the Purview portal, select the edge to
`analyticsdb.dbo.CustomerRiskSummary`, and use the portal's delete-lineage-entry action
(`README.md` reference 6). Prefer the script for anything beyond a single one-off removal — it's
idempotent and leaves an auditable command in a pipeline log.

## Verification after rollback

```powershell
# Expect a [FAIL] for the removed downstream asset's connectivity check — this is the correct,
# expected signal that rollback succeeded, not a problem to investigate.
./validate/Test-EndToEndLineage.ps1 `
    -PurviewAccountEndpoint 'https://api.purview-service.microsoft.com' `
    -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
    -LineageDefinitionPath './deploy/lineage/customer-risk-summary-lineage.json'
```

Re-run `deploy/New-CustomLineageRelationship.ps1` at any time afterward to restore the link — it
will correctly detect the relationship as missing and recreate it, exactly as it would after any
other cause of the link going missing (see `README.md` §8's incident-response runbook).
