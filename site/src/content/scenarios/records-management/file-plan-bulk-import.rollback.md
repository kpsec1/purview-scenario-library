---
part: "rollback"
parent: "records-management/file-plan-bulk-import"
---
## ⚠️ Read first: label deletion has real limits, and there is no bulk-delete

Neither deploy path has a bulk-undo. **Path A** (CSV import) has no bulk-delete mechanism at all in
the portal, labels it creates are removed one at a time, the same as any other label. **Path B**
(`New-FilePlanBulkLabels.ps1`) creates a `Remove-FilePlanBulkLabels.ps1` companion that loops the
same schedule, but `Remove-ComplianceTag` itself only succeeds for a label that:

- has never been applied to any content,
- isn't configured for event-based retention,
- isn't marked a regulatory record, and
- isn't currently published or in an auto-apply policy.

A label that fails any of those is **reported, not forced**, this scenario never uses a
force-deletion path for records objects. Do not run rollback until Records/Legal confirm the
schedule (or specific classes in it) are actually being retired.

## Recommended sequence

### Stage 1, Dry-run (see what would happen)

```powershell
Connect-IPPSSession -AppId $AppId -Certificate $Cert -Organization 'contoso.onmicrosoft.com'
./deploy/Remove-FilePlanBulkLabels.ps1 -InputPath ./deploy/config/file-plan-schedule.sample.csv -DryRun
```

Prints the `Remove-ComplianceTag` call for every row in the schedule and removes nothing.

### Stage 2, Remove what's actually unused

```powershell
./deploy/Remove-FilePlanBulkLabels.ps1 -InputPath ./deploy/config/file-plan-schedule.sample.csv
```

For each row: if the label doesn't exist, it's reported and skipped. If it exists and is unused (per
the four conditions above), it's removed. If it exists and is in use, the attempt fails and the
script reports why, this is expected and safe; leave those labels in place.

### What this rollback does **not** do

- **Descriptor objects are never removed.** `Department`/`Category`/`SubCategory`/`Citation`/
 `ReferenceId`/`Authority` objects `New-FilePlanBulkLabels.ps1` created are shared, tenant-wide
 picklist values, other labels (including ones outside this schedule) may already reference them.
 Deleting them is out of scope; do it manually and only after confirming nothing else uses them.
- **Content already labeled.** Removing a label definition does not remove or relabel content that
 already carries it. Applied labels generally block their own removal anyway (see above).
- **Path A (CSV-imported) labels via bulk script.** `Remove-FilePlanBulkLabels.ps1` works against
 *any* label matching the schedule's `LabelName` column, regardless of which path created it, so
 it's safe to use for cleaning up a Path A (portal-imported) test run too.

## Verification after rollback

```powershell
Connect-IPPSSession -AppId $AppId -Certificate $Cert -Organization 'contoso.onmicrosoft.com'
./validate/Test-FilePlanBulkImport.ps1
```

Expect the "Retention label exists in tenant" check to `[FAIL]` for every row that was successfully
removed, and to still `[PASS]` for any row whose label couldn't be removed because it's in use, that
second outcome is the expected, safe result for records already in force.

## References

1. Delete retention labels (succeeds only if not applied/published/event-based/regulatory), 
 <https://learn.microsoft.com/purview/file-plan-manager#delete-retention-labels>
