---
part: "rollback"
parent: "data-lifecycle-management/event-based-retention-and-disposition"
---
## ⚠️ Read first: fired events and record locks don't undo

Two things this rollback **cannot** touch, by design:

- **A fired retention event.** Once `New-RetentionTriggerEvent.ps1` (or the portal) creates an event,
  Microsoft's documentation states it **cannot be canceled** [[1]](#references). Any content already
  in scope for that event keeps its retention clock running regardless of what you do to the policy
  or label afterward.
- **A record-locked item.** Content already labeled with `IsRecordLabel = $true` and whose event has
  fired is locked, it can't be edited, deleted, or have its label removed, until it completes
  disposition review. Disabling or deleting the publish policy stops **new** labeling; it does not
  unlock existing records.

If you deployed to the wrong locations or with the wrong reviewers, fix the config and re-deploy
*before* any events are fired against affected content, that's the only fully reversible window.

## Recommended sequence

### Stage 1, Disable the publish policy (stops new labeling)

```powershell
Connect-IPPSSession -AppId $AppId -Certificate $Cert -Organization 'contoso.onmicrosoft.com'
./deploy/Remove-EventBasedRetentionAndDisposition.ps1 -ConfigPath ./deploy/config/employee-departure-retention.json -DryRun
./deploy/Remove-EventBasedRetentionAndDisposition.ps1 -ConfigPath ./deploy/config/employee-departure-retention.json
```

Sets the policy `-Enabled $false`, records managers no longer see the label to apply to *new*
content. The label, event type, any already-fired events, and any already-labeled content are
untouched. Reversible: re-run the deploy to re-enable. Use this to pause a mis-scoped rollout
**before** more content is labeled.

### Stage 2, Delete the publish policy and rule

```powershell
./deploy/Remove-EventBasedRetentionAndDisposition.ps1 -ConfigPath ./deploy/config/employee-departure-retention.json -Delete
```

Removes the policy (and its rule). Records managers can no longer apply the label at all through
this policy. Still does **not** unlock any content already labeled, and does not affect any
already-fired events' retention clocks.

### Stage 3, Remove the label (only if it was never applied)

```powershell
./deploy/Remove-EventBasedRetentionAndDisposition.ps1 -ConfigPath ./deploy/config/employee-departure-retention.json -Delete -TryRemoveLabel
```

Attempts `Remove-ComplianceTag`. This **succeeds only if the label was never applied**, or (for
already-applied, non-record content) isn't otherwise in active use. For content that's a locked
record, or has an event already counting down against it, the service **refuses** the delete, the
script reports that refusal rather than forcing it.

### Retention event types and fired events are never removed by this script

`Remove-ComplianceRetentionEventType` exists as a documented cmdlet [[2]](#references), and
retention events are visible via `Get-ComplianceRetentionEvent`, but neither is scripted here. This
scenario treats the event type and every fired event as an **append-only audit record of what
happened**, deleting an event type doesn't cancel the retention it already started
[[1]](#references), so removing it has no protective effect and only destroys the record of *why*
retention started for the content still under it. If you genuinely need to retire an event type,
do so deliberately in the portal after confirming no content is still relying on it.

## What rollback does **not** undo

- **Any retention event already fired**, cannot be canceled, per Microsoft's own documentation.
- **Any content already locked as a record**, stays locked until it completes disposition review.
- **Retention clocks already counting down** on content whose event fired.
- **Storage consumed** by retained content, it can't be deleted early.

## Verification after rollback

```powershell
Connect-IPPSSession -AppId $AppId -Certificate $Cert -Organization 'contoso.onmicrosoft.com'
./validate/Test-EventBasedRetentionAndDisposition.ps1 -ConfigPath ./deploy/config/employee-departure-retention.json
```

After **Stage 1**, expect the "Policy is enabled" check to `[WARN]`/`[FAIL]` while the event type,
label, and rule still exist. After **Stage 2**, expect the policy/rule existence checks to `[FAIL]`.
After **Stage 3**, the label check `[FAIL]`s only if the label was actually removable; otherwise it
still `[PASS]`es, confirming an in-use label (correctly) could not be deleted. To check whether a
specific employee's event already fired, run `Get-ComplianceRetentionEvent -Identity '<EventName>'`
directly, not covered by the validate script, which checks policy state, not individual events.

## References

1. Start retention when an event occurs (events can't be canceled once triggered; deleting an event
   type doesn't cancel retention it already started), <https://learn.microsoft.com/purview/event-driven-retention>
2. PowerShell cmdlets available for event-based retention automation (includes
   Remove-ComplianceRetentionEventType), <https://learn.microsoft.com/purview/event-driven-retention#automate-events-by-using-powershell>
