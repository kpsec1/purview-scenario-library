---
part: "rollback"
parent: "records-management/graph-event-automation"
---
## ⚠️ Read first: deleting an event does not undo retention

The single most important fact about this scenario's rollback: **a fired retention event has already
started the retention clock for matching content, and deleting the event object does NOT stop or reverse
that retention.** Deletion here is **bookkeeping**, removing event/event-type records, not an undo.
There is no supported "un-fire". Do not run rollback expecting to release content from retention.

## Recommended sequence

### Stage 1, Delete event records (bookkeeping)

```powershell
Connect-MgGraph -Scopes 'RecordsManagement.ReadWrite.All'
./deploy/Remove-GraphRetentionEvent.ps1 -ConfigPath ./deploy/config/graph-event-automation.json -WhatIf
./deploy/Remove-GraphRetentionEvent.ps1 -ConfigPath ./deploy/config/graph-event-automation.json
```

Deletes retention **events** whose `displayName` matches the config
(`DELETE /security/triggers/retentionEvents/{id}`). The retention those events started is **unaffected**.
Use this to tidy up event records (e.g. remove a test event's object), not to cancel retention.

### Stage 2, Delete the event type (if retiring the schedule)

```powershell
./deploy/Remove-GraphRetentionEvent.ps1 -ConfigPath ./deploy/config/graph-event-automation.json -DeleteEventType
```

Also deletes the event type (`DELETE /security/triggerTypes/retentionEventTypes/{id}`) after removing
matching events. This **succeeds only if no label still references the event type**; otherwise the API
call fails and the script reports it (expected, leave the type in place while a label uses it). Do this
only when the event-based schedule is being permanently retired and its label decommissioned separately.

## What rollback does **not** undo

- **Retention already started by a fired event.** No Graph call stops a running clock, that's the
  records guarantee.
- **The event-based retention label and publish policy**, owned by the sibling PowerShell scenario /
  portal; decommission there if needed.
- **Content already retained, reviewed, or disposed**, unaffected.
- **The app registration and its `RecordsManagement.ReadWrite.All` grant**, remove that separately in
  Entra if decommissioning the integration identity.

## Verification after rollback

```powershell
Connect-MgGraph -Scopes 'RecordsManagement.Read.All'
./validate/Test-GraphRetentionEvent.ps1 -ConfigPath ./deploy/config/graph-event-automation.json
```

After **Stage 1**, expect no events listed for the config's `event.displayName` (the event records are
gone), while the event type still `[PASS]`es. After **Stage 2**, expect the event-type check to `[FAIL]`
(removed), unless it couldn't be removed because a label still references it, which is the expected,
safe outcome.
