---
part: "rollback"
parent: "records-management/disposition-proof-export"
---
## What there is to roll back

Identical in kind to [`data-estate-insights/sensitivity-label-coverage-report`](/scenarios/data-estate-insights/sensitivity-label-coverage-report/)'s own
rollback: this scenario creates **no object inside Microsoft Purview at all** — no retention label,
no policy, no rule, no event type. Every call `deploy/Export-DispositionProofEvidence.ps1` makes is
a read-only `Search-UnifiedAuditLog` query. "Rollback" here means two things, neither of which
touches the Purview account itself:

1. Stop the scheduled execution of `deploy/Export-DispositionProofEvidence.ps1`.
2. Decide what to do with the already-produced rolling evidence CSV file(s).

## 1. Stop the schedule

This scenario ships no scheduler-specific code (README.md §8) — remove or disable whatever
recurring-execution mechanism was wired up (an Azure Automation runbook, a scheduled Azure Function,
a cron entry, or a Windows Task Scheduler task) using that platform's own removal procedure. There is
nothing Purview-side to undo as part of this step.

If the connecting identity's **View-Only Audit Logs** / **Audit Logs** Exchange Online role
assignment was granted specifically to run this scenario's script and is not needed for any other
purpose in this repo (several other audit-trail scripts in this library rely on the same role — see
`docs/rbac-model.md` §6), remove the role assignment via the Exchange admin center or Security &
Compliance PowerShell. Confirm no sibling scenario's own export script (e.g.
`scenarios/ediscovery/premium-legal-hold-and-export/deploy/Export-EdiscoveryAuditTrail.ps1` or
`scenarios/data-lifecycle-management/adaptive-protection-deleted-content-preservation/deploy/
Export-AdaptiveProtectionPreservationEvidence.ps1`) still depends on it before removing.

## 2. Decide the fate of already-produced evidence files

- **The rolling CSV** (wherever `-OutputCsvPath` pointed) is an ordinary file this scenario wrote
  outside of Purview — delete it, archive it, or leave it in place per the buyer's own
  data-retention/evidence-retention policy. As README.md §11 notes, this file is itself a
  compliance evidentiary record (proof that disposition activity did or did not occur in a given
  window) — apply the same handling discipline that governed it while active; do not move it to
  less-protected storage, or delete it, as a matter of routine cleanup.
- **If a matter, audit, or litigation hold is open** that this evidence trail was supporting, do
  **not** delete the CSV as part of rollback — preserve it under whatever hold or evidence-retention
  process governs the matter, independent of whether the export schedule itself continues.
- If the CSV was committed to a source-control repository (the recommended pattern for preserving
  history over time, matching this repo's other report-style scenarios), treat its removal like
  removing any other tracked evidentiary file: a deliberate commit, not an ad hoc delete.

## What rollback does **not** undo

- **Any retention label, event type, policy, or disposition-review configuration.** Entirely out of
  this scenario's scope — owned by [`records-management/regulatory-records-disposition`](/scenarios/records-management/regulatory-records-disposition/),
  [`records-management/multi-stage-disposition-review`](/scenarios/records-management/multi-stage-disposition-review/), or whichever records-management
  scenario configured them. Removing this scenario's export automation has zero effect on any of
  them.
- **The disposition activity itself.** Items already reviewed, approved, relabeled, or deleted stay
  that way — this scenario never had write access to any content or Purview object to begin with.
- **The portal's own Disposition page Filter+Export workflow** (README.md §5) — entirely independent
  of this scenario's automation; it continues to work exactly as before regardless of whether this
  scenario's script is scheduled.
- **Already-collected evidence in the CSV.** Stopping the schedule does not retroactively invalidate
  or need to be reconciled against previously exported rows — they remain a valid point-in-time
  record of what the audit log showed when each row was collected.

## Re-enabling later

Re-running `deploy/Export-DispositionProofEvidence.ps1` after a rollback is safe at any time:
re-assign the Audit Logs / View-Only Audit Logs role (step 1, reversed), point `-OutputCsvPath` at
either a fresh file or the previously-archived CSV (the merge/de-duplication logic handles both
identically), and resume scheduling. Because this scenario's idempotency model is a composite-key
merge rather than depending on any created Purview object's existence, there is no "was it fully
torn down" ambiguity to resolve before resuming — the only consideration is whether the audit
window between the last collected row and the resume date still falls inside the tenant's configured
audit-retention tier (README.md §8); if the gap exceeds that tier, evidence for the dormant period is
unrecoverable regardless of this scenario's own state.
