---
part: "rollback"
parent: "records-management/regulatory-records-disposition"
---
## ⚠️ Read first: records disposition has irreversible edges

Two things this rollback **cannot** undo, by design of the records-management platform:

1. **A triggered event cannot be cancelled.** Deleting an event does **not** stop the retention it
   already started. Content whose `EventAgeInDays` clock a prior event began keeps counting down.
2. **An applied record label cannot be deleted**, and its retention cannot be shortened. `Remove-ComplianceTag`
   succeeds only for a label that has **not** been applied and is **not** in a policy.

So rollback here means "stop offering the label and clean up unused definitions", not "reverse
retention already in force". Do not run any stage until **Records/Legal confirm** the schedule is being
retired or corrected. When in doubt, keep it.

## Recommended sequence

### Stage 1, Disable the publish policy (stop new application)

```powershell
Connect-IPPSSession -AppId $AppId -Certificate $Cert -Organization 'contoso.onmicrosoft.com'
./deploy/Remove-RecordsDisposition.ps1 -ConfigPath ./deploy/config/records-disposition.json -DryRun
./deploy/Remove-RecordsDisposition.ps1 -ConfigPath ./deploy/config/records-disposition.json
```

Runs `Set-RetentionCompliancePolicy -Enabled $false`, the label is no longer published to the target
locations, so it can't be newly applied. The label, event type, and any content already labeled are
untouched. Re-enable by re-running the deploy. Use this to pause the schedule without discarding it.

### Stage 2, Delete the policy/rule and attempt to remove label + event type

```powershell
./deploy/Remove-RecordsDisposition.ps1 -ConfigPath ./deploy/config/records-disposition.json -Delete
```

Runs `Remove-RetentionCompliancePolicy` (removes the policy and its rule), then **attempts**
`Remove-ComplianceTag` (the label) and `Remove-ComplianceRetentionEventType` (the event type). These
last two **succeed only if the objects are unused**:

- The **label** is removed only if it was never applied and isn't in a policy. If it has been applied to
  any content, removal fails, the script reports this and leaves it in place (expected).
- The **event type** is removed only if no label still references it and (in practice) it has no
  triggered events. Otherwise removal fails and is reported.

Use Stage 2 only when permanently retiring an **unused** schedule, or cleaning up a lab.

## What rollback does **not** undo

- **A triggered event / retention already in force.** No cmdlet here stops a running `EventAgeInDays`
  clock, that's the records guarantee.
- **Content already retained or disposed.** Items already declared records, retained, or disposed
  (with proof) are unaffected.
- **Pending disposition items.** In-flight disposition reviews continue; manage them in the portal
  (Records Management → Disposition).
- **Proof of disposition** and audit records of the configuration, retained per their own policy.

## Verification after rollback

```powershell
Connect-IPPSSession -AppId $AppId -Certificate $Cert -Organization 'contoso.onmicrosoft.com'
./validate/Test-RecordsDisposition.ps1 -ConfigPath ./deploy/config/records-disposition.json
```

After **Stage 1**, expect the policy to exist but be disabled (the "Policy is enabled" check `[WARN]`s).
After **Stage 2**, expect the policy/rule checks to `[FAIL]` (removed); the label and event-type checks
may still `[PASS]` if they couldn't be removed because they're in use, that's the expected, safe
outcome for records already in force.
