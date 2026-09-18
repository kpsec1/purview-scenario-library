---
part: "rollback"
parent: "data-lifecycle-management/priority-cleanup-exchange-data-spillage"
---
## ⚠️ Read first: a completed approval cannot be recalled

Priority cleanup is designed to permanently delete content, overriding retention policies,
litigation holds, eDiscovery holds, and Preservation Lock (delete-only). Once every required
approval for an item is complete, it is deleted, Microsoft states explicitly that deleted items
"cannot be restored by users, by admins, or by Microsoft" [[1]](#references). **Rollback here can
disable or delete the policy going forward; it cannot undo a deletion that already happened**, and
Microsoft also warns that disabling/deleting the policy does not reliably stop an **in-flight**
approval that has already gathered all required sign-offs from completing [[2]](#references). If you
deployed against the wrong mailboxes or an over-broad query, act immediately (Stage 1 below) and, if
anything is still pending, get every remaining approver to **decline** (Relabel) it in the portal
before assuming disabling the policy is sufficient.

## Recommended sequence

### Stage 0, If items are pending approval and must NOT be deleted

This is portal-only; there is no PowerShell/Graph equivalent. Go to **Data Lifecycle Management →
Priority cleanup → Pending cleanups**, select the affected items, choose **Relabel**, and apply an
existing, appropriate retention label instead of allowing the deletion approval to complete. Do this
**before** or **in addition to** Stage 1, disabling the policy alone does not guarantee an
in-flight approval stops.

### Stage 1, Disable the policy (stops identifying new items)

```powershell
Connect-IPPSSession -AppId $AppId -Certificate $Cert -Organization 'contoso.onmicrosoft.com'
./deploy/Remove-PriorityCleanupExchangePolicy.ps1 -ConfigPath ./deploy/config/priority-cleanup-exchange.json -DryRun
./deploy/Remove-PriorityCleanupExchangePolicy.ps1 -ConfigPath ./deploy/config/priority-cleanup-exchange.json
```

Sets the policy `-Enabled $false`, no *new* mailbox items are identified for deletion. The label,
rule, and any items already fully approved and deleted are unaffected (the deletions already
happened and cannot be recalled). Reversible: re-run the deploy script to re-enable.

### Stage 2, Delete the policy and rule

```powershell
./deploy/Remove-PriorityCleanupExchangePolicy.ps1 -ConfigPath ./deploy/config/priority-cleanup-exchange.json -Delete
```

Removes the policy (and its rule). Per Microsoft's own limitation notice, **items already through
the approval process may still be permanently deleted even after the policy is deleted**
[[2]](#references), this is not a bug in the script, it's documented platform behavior.

### Stage 3, Remove the label (optional)

```powershell
./deploy/Remove-PriorityCleanupExchangePolicy.ps1 -ConfigPath ./deploy/config/priority-cleanup-exchange.json -Delete -TryRemoveLabel
```

Attempts `Remove-ComplianceTag`. Reports rather than forces if the service refuses.

## What rollback does **not** undo

- **Any item already permanently deleted by a completed approval.** No admin action, and no action by
  Microsoft, can restore it.
- **An in-flight approval that completes after you disable/delete the policy.** Use Stage 0 first if
  anything must not be deleted.
- **The audit trail.** `PriorityCleanupTagApplied`/`PriorityCleanupDelete` events remain in the audit
  log regardless of policy state, this is a feature (evidentiary record of what happened and when),
  not something to try to undo.

## Verification after rollback

```powershell
Connect-IPPSSession -AppId $AppId -Certificate $Cert -Organization 'contoso.onmicrosoft.com'
./validate/Test-PriorityCleanupExchangePolicy.ps1 -ConfigPath ./deploy/config/priority-cleanup-exchange.json
```

After **Stage 1**, expect `Enabled: False` in the validate script's output. After **Stage 2**, expect
the policy/rule existence checks to `[FAIL]`. Then search the audit log by the policy's Cleanup ID to
confirm no further `PriorityCleanupDelete` events post-date the rollback, this is the only reliable
way to confirm the in-flight-approval risk in Stage 0 didn't materialize.

## References

1. Approval process for a priority cleanup policy ("cannot be restored by users, by admins, or by Microsoft"), <https://learn.microsoft.com/purview/priority-cleanup-exchange#approval-process-for-a-priority-cleanup-policy>
2. Limitations of priority cleanup ("items might still be permanently deleted" after policy deletion), <https://learn.microsoft.com/purview/priority-cleanup-exchange#limitations-of-priority-cleanup>
