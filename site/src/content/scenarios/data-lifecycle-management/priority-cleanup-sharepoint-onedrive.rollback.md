---
part: "rollback"
parent: "data-lifecycle-management/priority-cleanup-sharepoint-onedrive"
---
## A softer rollback story than the Exchange sibling, but not a free one

Unlike the Exchange sibling scenario, this workload's deletion mechanism moves matching items to
the **second-stage Recycle Bin** rather than deleting them instantly and permanently
. That means an item disposed of by a completed approval **can** still be
recovered from the Recycle Bin within its own retention window, this is real, meaningful recourse
the Exchange sibling does not have. It is not, however, a reason to be careless: Microsoft still
states that disabling or deleting the policy does **not** reliably stop an **in-flight** approval
that has already gathered its required sign-off from completing, and the
Recycle Bin's own retention window is finite. Act promptly if you deployed against the wrong
locations or an over-broad query.

## Recommended sequence

### Stage 0, If items are pending approval and must NOT move to the Recycle Bin

This is portal-only; there is no PowerShell/Graph equivalent. Go to **Data Lifecycle Management →
Priority cleanup → Pending cleanups**, select the affected items, choose **Relabel**, and apply an
existing, appropriate retention label instead of allowing the disposal approval to complete. Do
this **before** or **in addition to** Stage 1, disabling the policy alone does not guarantee an
in-flight approval stops.

### Stage 1, Disable the policy (stops identifying new items)

```powershell
Connect-IPPSSession -AppId $AppId -Certificate $Cert -Organization 'contoso.onmicrosoft.com'
./deploy/Remove-PriorityCleanupSharePointOneDrivePolicy.ps1 -ConfigPath ./deploy/config/priority-cleanup-sharepoint-onedrive.json -DryRun
./deploy/Remove-PriorityCleanupSharePointOneDrivePolicy.ps1 -ConfigPath ./deploy/config/priority-cleanup-sharepoint-onedrive.json
```

Sets the policy `-Enabled $false`, no *new* items are identified. The label, rule, and any items
already fully approved and moved to the Recycle Bin are unaffected by this step alone. Reversible:
re-run the deploy script to re-enable (subject to the same mandatory-simulation requirement as
initial setup, see `README.md` §5/§11, since re-enabling after a meaningful change may itself
require a fresh simulation run).

### Stage 2, Delete the policy and rule

```powershell
./deploy/Remove-PriorityCleanupSharePointOneDrivePolicy.ps1 -ConfigPath ./deploy/config/priority-cleanup-sharepoint-onedrive.json -Delete
```

Removes the policy (and its rule). Per Microsoft's own limitation notice, **items already through
the approval process may still be moved to the Recycle Bin even after the policy is deleted**
, this is not a bug in the script, it's documented platform behavior, the same
principle as the Exchange sibling's equivalent limitation.

### Stage 3, Remove the label (optional)

```powershell
./deploy/Remove-PriorityCleanupSharePointOneDrivePolicy.ps1 -ConfigPath ./deploy/config/priority-cleanup-sharepoint-onedrive.json -Delete -TryRemoveLabel
```

Attempts `Remove-ComplianceTag`. Reports rather than forces if the service refuses.

### Stage 4, Recover from the Recycle Bin (the SharePoint/OneDrive-specific recourse)

If items were moved to the second-stage Recycle Bin by a completed disposal you now want to undo,
recover them directly from the site's or OneDrive account's Recycle Bin, the same recovery path
as any other SharePoint/OneDrive deletion, **before** its retention window expires. This script
set does not automate that recovery; it is a standard SharePoint/OneDrive admin action outside
Data Lifecycle Management.

## What rollback does **not** undo

- **An item whose Recycle Bin retention window has already expired.** At that point it follows the
 same permanent-deletion path as any other expired Recycle Bin item.
- **An in-flight approval that completes after you disable/delete the policy.** Use Stage 0 first
 if anything must not move to the Recycle Bin.
- **The audit trail.** `PriorityCleanupTagApplied`/`PriorityCleanupFileRecycled` events remain in
 the audit log regardless of policy state, this is a feature (evidentiary record of what
 happened and when), not something to try to undo.

## Verification after rollback

```powershell
Connect-IPPSSession -AppId $AppId -Certificate $Cert -Organization 'contoso.onmicrosoft.com'
./validate/Test-PriorityCleanupSharePointOneDrivePolicy.ps1 -ConfigPath ./deploy/config/priority-cleanup-sharepoint-onedrive.json
```

After **Stage 1**, expect `Enabled: False` in the validate script's output. After **Stage 2**,
expect the policy/rule existence checks to `[FAIL]`. Then search the audit log by the policy's
Cleanup ID to confirm no further `PriorityCleanupFileRecycled` events post-date the rollback, and
check the relevant Recycle Bin(s) directly if Stage 4 recovery was needed.

## References

1. Override holds to clean up files for Copilot and reclaim storage, Recycle Bin deletion mechanism, <https://learn.microsoft.com/purview/priority-cleanup-onedrive-sharepoint>
2. Override holds to clean up files for Copilot and reclaim storage, limitations ("items might still be deleted" after policy deletion), <https://learn.microsoft.com/purview/priority-cleanup-onedrive-sharepoint#prerequisites-for-priority-cleanup>
