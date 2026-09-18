---
part: "rollback"
parent: "records-management/multi-stage-disposition-review"
---
## ⚠️ Read first: same irreversible edges as the parent scenario, plus in-flight reviews

Three things this rollback **cannot** undo:

1. **A triggered event cannot be cancelled.** Deleting an event does **not** stop the retention it
   already started.
2. **An applied record label cannot be deleted**, and its reviewer chain/retention cannot be shortened or
   edited. `Remove-ComplianceTag` succeeds only for a label that has **not** been applied and is **not**
   in a policy.
3. **An in-flight disposition review, at any stage, is not touched by this rollback.** If an item is
   already sitting in Stage 2's queue, disabling or deleting the publish policy does not remove it from
   that queue or change who can act on it — manage pending items in the portal (Records Management →
   Disposition), not here.

So rollback here means "stop offering the label and clean up unused definitions" — not "reverse
retention or review decisions already in force". Do not run any stage until **Records/Legal/HR confirm**
the schedule or chain is being retired or corrected. When in doubt, keep it.

## Recommended sequence

### Stage 1 — Disable the publish policy (stop new application)

```powershell
Connect-IPPSSession -AppId $AppId -Certificate $Cert -Organization 'contoso.onmicrosoft.com'
./deploy/Remove-MultiStageDispositionReview.ps1 -ConfigPath ./deploy/config/multi-stage-disposition-review.json -DryRun
./deploy/Remove-MultiStageDispositionReview.ps1 -ConfigPath ./deploy/config/multi-stage-disposition-review.json
```

Runs `Set-RetentionCompliancePolicy -Enabled $false` — the label (and its full reviewer chain) is no
longer published to the target locations, so it can't be newly applied. The label, event type, reviewer
chain, and any content already labeled are untouched. Re-enable by re-running the deploy. Use this to
pause the schedule without discarding the sign-off chain.

### Stage 2 — Delete the policy/rule and attempt to remove label + event type

```powershell
./deploy/Remove-MultiStageDispositionReview.ps1 -ConfigPath ./deploy/config/multi-stage-disposition-review.json -Delete
```

Runs `Remove-RetentionCompliancePolicy` (removes the policy and its rule), then **attempts**
`Remove-ComplianceTag` (the label, including its reviewer chain) and
`Remove-ComplianceRetentionEventType` (the event type). These last two **succeed only if the objects are
unused**:

- The **label** is removed only if it was never applied and isn't in a policy. If it has been applied to
  any content, removal fails — the script reports this and leaves it (and its reviewer chain) in place.
- The **event type** is removed only if no label still references it and it has no triggered events.
  Otherwise removal fails and is reported.

Use Stage 2 only when permanently retiring an **unused** schedule/chain, or cleaning up a lab.

## What rollback does **not** undo

- **A triggered event / retention already in force.** No cmdlet here stops a running `EventAgeInDays`
  clock.
- **Content already retained or disposed.** Items already declared records, retained, or disposed (with
  proof) are unaffected.
- **Pending disposition items, at any stage.** In-flight reviews continue exactly where they are; a
  Stage-1 item stays queued for Stage 1's reviewers regardless of this rollback. Manage them in the
  portal.
- **The reviewer chain itself, on a label still in use.** This scenario's scripts never call
  `Set-ComplianceTag` to edit reviewers — that is a deliberate, out-of-band, Records/Legal/HR-reviewed
  action per `design.md` §7, not something rollback performs.
- **Proof of disposition** and audit records of the configuration — retained per their own policy.

## Verification after rollback

```powershell
Connect-IPPSSession -AppId $AppId -Certificate $Cert -Organization 'contoso.onmicrosoft.com'
./validate/Test-MultiStageDispositionReview.ps1 -ConfigPath ./deploy/config/multi-stage-disposition-review.json
```

After **Stage 1**, expect the policy to exist but be disabled (the "Policy is enabled" check `[WARN]`s);
the reviewer-chain checks should be unaffected. After **Stage 2**, expect the policy/rule checks to
`[FAIL]` (removed); the label and event-type checks may still `[PASS]` if they couldn't be removed
because they're in use — that's the expected, safe outcome for records and reviews already in force.
