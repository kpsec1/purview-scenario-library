---
part: "rollback"
parent: "data-lifecycle-management/priority-cleanup-permanent-deletion"
---
## No recovery once deleted, the opposite posture from the sibling scenario

Unlike `priority-cleanup-sharepoint-onedrive`, this scenario's terminal state (once fully configured
via the portal's "Delete data permanently" step and an approval completes) bypasses **both**
SharePoint/OneDrive Recycle Bins. Microsoft states the deleted content is "no longer discoverable in
SharePoint search, Microsoft 365 Copilot, or eDiscovery" [[1]](#references), there is no Recycle Bin
recovery step for rollback.md to document here, because none exists. Everything below is about
**stopping further items from being identified and disposed of**, it is not, and cannot be, an undo
for anything already deleted.

## Recommended sequence

### Stage 0, If items are pending approval and must NOT be permanently deleted

This is portal-only; there is no PowerShell/Graph equivalent. Go to **Data Lifecycle Management →
Priority cleanup → Pending cleanups**, select the affected items, choose **Relabel**, and apply an
existing, appropriate retention label instead of allowing the disposal approval to complete. Do this
**immediately** on any sign the query is broader than intended, this is the only intervention point
before deletion becomes irreversible.

### Stage 1, Disable the policy (stops identifying new items)

```powershell
Connect-IPPSSession -AppId $AppId -Certificate $Cert -Organization 'contoso.onmicrosoft.com'
./deploy/Remove-PriorityCleanupPermanentDeletionPolicy.ps1 -ConfigPath ./deploy/config/priority-cleanup-permanent-deletion.json -DryRun
./deploy/Remove-PriorityCleanupPermanentDeletionPolicy.ps1 -ConfigPath ./deploy/config/priority-cleanup-permanent-deletion.json
```

Sets the policy `-Enabled $false`, no *new* items are identified. Per Microsoft's own limitation
notice for the base feature, **items already through the approval process may still be deleted even
after the policy is disabled or deleted** [[2]](#references), disabling the policy is not a
guaranteed stop for items already in flight; use Stage 0 first for anything that must not be deleted.

### Stage 2, Delete the policy and rule

```powershell
./deploy/Remove-PriorityCleanupPermanentDeletionPolicy.ps1 -ConfigPath ./deploy/config/priority-cleanup-permanent-deletion.json -Delete
```

Removes the policy (and its rule). Same in-flight-approval caveat as Stage 1 applies.

### Stage 3, Remove the label (optional)

```powershell
./deploy/Remove-PriorityCleanupPermanentDeletionPolicy.ps1 -ConfigPath ./deploy/config/priority-cleanup-permanent-deletion.json -Delete -TryRemoveLabel
```

Attempts `Remove-ComplianceTag`. Reports rather than forces if the service refuses.

### Stage 4, There is no Stage 4

The `priority-cleanup-sharepoint-onedrive` sibling's rollback has a Stage 4 (Recycle Bin recovery).
This scenario does not, by design: once `PriorityCleanupFileDeleted` has fired for an item, it is
gone. If content was deleted that should not have been, treat it as a **data-loss incident**, not a
rollback exercise, engage your organization's backup/restore process (e.g. a third-party SharePoint/
OneDrive backup solution, if one exists independently of Microsoft Purview) rather than looking for a
Purview-native recovery path, because none is documented.

## What rollback does **not** undo

- **Anything for which `PriorityCleanupFileDeleted` has already fired.** No recovery path exists, 
  this is this scenario's defining, disclosed risk (README.md §2/§11).
- **An in-flight approval that completes after you disable/delete the policy.** Use Stage 0 first.
- **The audit trail.** `PriorityCleanupFileDeleted` events remain in the audit log regardless of
  policy state, this is the evidentiary record of what happened and when, and should be preserved,
  not treated as something to undo.

## Before you ever reach Stage 1, the real safeguard is upstream

Because there is no downstream recovery, the operational safeguards that matter are **all upstream**
of deletion: mandatory simulation review by a second admin, a deliberately narrow and reviewed
`contentMatchQuery`, and confirming the "Delete data permanently" portal step was applied to the
intended policy and no other. Treat every deployment of this scenario as a reviewed, incident-scoped
action, never a standing, continually-running policy the way the sibling scenario's stale-recordings
use case is.

## Verification after rollback

```powershell
Connect-IPPSSession -AppId $AppId -Certificate $Cert -Organization 'contoso.onmicrosoft.com'
./validate/Test-PriorityCleanupPermanentDeletionPolicy.ps1 -ConfigPath ./deploy/config/priority-cleanup-permanent-deletion.json
```

After **Stage 1**, expect `Enabled: False`. After **Stage 2**, expect the policy/rule existence
checks to `[FAIL]`. Then search the audit log by the policy's Cleanup ID for `PriorityCleanupFileDeleted`
events to build a complete record of exactly what was permanently deleted before the rollback, this
is the only way to know the full scope of what happened, since nothing about it can be reversed.

## References

1. Permanently delete files with Microsoft Purview Priority Cleanup, deletion is not discoverable in search/Copilot/eDiscovery after it occurs, <https://learn.microsoft.com/purview/priority-cleanup-permanent-deletion>
2. Override holds to clean up files for Copilot and reclaim storage, limitations ("items might still be deleted" after policy deletion, shared base-feature behavior), <https://learn.microsoft.com/purview/priority-cleanup-onedrive-sharepoint#prerequisites-for-priority-cleanup>
