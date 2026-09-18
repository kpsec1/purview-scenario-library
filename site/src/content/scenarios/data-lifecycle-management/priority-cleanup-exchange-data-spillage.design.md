---
part: "design"
parent: "data-lifecycle-management/priority-cleanup-exchange-data-spillage"
---
## 1. Problem statement

A sensitive document (an M&A target list, in this scenario's worked example) was emailed to a
handful of internal mailboxes that should never have received it. Some of those mailboxes are
covered by a 2-year retention policy; one is on an active litigation hold. Waiting for retention to
expire, or for the hold to be released, is not an option, the exposure needs to end now. Microsoft
Purview's **Priority cleanup** feature (Data Lifecycle Management) is built for exactly this: it
permanently deletes matching content **even when retention, holds, or Preservation Lock would
otherwise prevent it** [[1]](#references). This scenario builds that control as code, for the
Exchange mailbox workload specifically, with guardrails proportional to a capability that is, by
design, more dangerous than everything else in this repo's Data Lifecycle Management coverage.

## 2. Design goals

1. **Script the real mechanism, not a guess.** Priority cleanup is not a separate product surface, 
   "under the covers, priority cleanup uses retention labels with auto-apply policies" [[1]](#references),
   and Microsoft's own `New-ComplianceTag`/`New-RetentionCompliancePolicy`/`New-RetentionComplianceRule`
   reference pages document an official `-PriorityCleanup` parameter set on each. This scenario uses
   that documented parameter set directly rather than approximating the portal wizard by hand.
2. **Never deploy live by accident.** No default-on path exists: the deploy script refuses to run
   without an explicit `-Simulate` or `-Enabled` choice (or `-DryRun`).
3. **Be honest about where the paper trail ends.** There is no documented PowerShell/Graph cmdlet to
   approve pending priority-cleanup items, that step is portal-only. The scripts don't pretend
   otherwise; they stop at policy/label/rule provisioning and validation, and point at the portal and
   auditing solution for what happens next.
4. **Disclose every place this scenario had to make a judgment call.** The `-MultiStageReviewProperty`
   JSON that encodes the three required approval stages, and the `RetentionDuration`/`RetentionType`
   values for "delete as soon as possible," are this scenario's own construction from documented
   building blocks, not values copied from a Microsoft worked example specific to priority cleanup.
   Both are flagged as VERIFY, not asserted as fact (`AGENTS.md` §4).
5. **Match the irreversibility with the guardrail.** Idempotency is create-or-report (never silently
   mutate a live priority cleanup object); rollback is explicit about what it cannot undo.

## 3. Why Exchange, not SharePoint/OneDrive (and not both in one fragment)

Microsoft documents priority cleanup as materially different per workload, different typical use
case, different approver set, different simulation requirement, different Preservation-Lock-override
scope [[1]](#references)[[2]](#references):

| | Exchange | SharePoint/OneDrive |
|---|---|---|
| Typical use | Data spillage / compliance deletion (rare) | Stale Teams recordings, Preservation Hold library cleanup (continual) |
| Approvers | Priority cleanup admin + retention manager + eDiscovery admin (3 stages) | eDiscovery admin only (1 stage beyond the creator) |
| Simulation | Recommended, not required | Required before every enable |
| Overrides Preservation Lock | Yes | Only if delete-only |

This fragment builds the **Exchange, data-spillage** variant, the use case Microsoft's own docs lead
with, and the one with the richest (3-stage) approval model. The SharePoint/OneDrive variant (stale
Teams recordings / Preservation Hold library cleanup, and the separate public-preview **permanent
deletion** sub-feature for that workload [[3]](#references)) is now built as its own sibling fragment,
`scenarios/data-lifecycle-management/priority-cleanup-sharepoint-onedrive/`, a different approver
model (eDiscovery-admin-only, conditional) and a required (not merely recommended) simulation step,
per that scenario's own `design.md` §3.

## 4. Object model and the two open construction choices

```mermaid
sequenceDiagram
    participant Script as New-PriorityCleanupExchangePolicy.ps1
    participant SCC as Security & Compliance PowerShell

    Script->>SCC: Get-ComplianceTag -PriorityCleanup (label exists?)
    alt not found
        Script->>SCC: New-ComplianceTag -PriorityCleanup -RetentionAction Delete<br/>-RetentionDuration 0 -RetentionType TaggedAgeInDays<br/>-MultiStageReviewProperty '{3-stage JSON}'
    end
    Script->>SCC: Get-RetentionCompliancePolicy -PriorityCleanup (policy exists?)
    alt not found
        Script->>SCC: New-RetentionCompliancePolicy -PriorityCleanup<br/>-SkipPriorityCleanupConfirmation -ExchangeLocation <mailboxes><br/>-IsSimulation (recommended) or -Enabled $true
    end
    Script->>SCC: Get-RetentionComplianceRule -PriorityCleanup -Policy (rule exists?)
    alt not found
        Script->>SCC: New-RetentionComplianceRule -PriorityCleanup<br/>-ApplyComplianceTag <label> -ContentMatchQuery <KeyQL>
    end
    Note over SCC: matching runs (up to 7 days); approvals happen in the PORTAL ONLY<br/>(Pending cleanups) - no documented approval cmdlet exists
```

Two places this scenario had to construct something Microsoft's reference doesn't spell out for
priority cleanup specifically, both flagged inline (deploy script `.NOTES`, config `_labelNote`,
`README.md` §11) rather than guessed silently:

- **`-MultiStageReviewProperty` as the approver mechanism.** `New-ComplianceTag`'s official
  `PriorityCleanup` parameter set lists `-MultiStageReviewProperty` as **mandatory**, direct evidence
  it's required, and the parameter's own description ("StageName", "Reviewers") matches the
  three-approver structure Microsoft describes in prose (priority cleanup admin → retention manager →
  eDiscovery admin) [[1]](#references)[[4]](#references). But no Microsoft-published example ties this
  parameter to priority cleanup specifically, or confirms whether stage **order** in the JSON array
  must match the documented approval sequence, or whether stage **names** are meaningful to the
  service versus purely a display label. This scenario's `StageName` values
  (`PriorityCleanupAdmin`/`RetentionManager`/`EDiscoveryAdmin`) are its own construction. Failure mode
  if wrong: Microsoft's docs state policy creation **fails with an error** if a listed reviewer lacks
  the required role for their stage [[5]](#references), so an incorrect mapping surfaces as a loud,
  synchronous failure at deploy time, not a silent misconfiguration.
- **`RetentionDuration`/`RetentionType` for "delete as soon as possible."** The portal wizard offers a
  binary choice, delete ASAP, or retain for a period then delete [[1]](#references), but the cmdlet
  reference doesn't publish the literal duration value ASAP maps to. This scenario defaults to
  `RetentionDuration 0` / `RetentionType TaggedAgeInDays` (the clock starts when the label lands, with
  zero days to wait) as the closest literal reading of "as soon as possible," corroborated loosely by
  the end-user-facing `(-1 days)` countdown Microsoft's docs show for this exact mode
  [[1]](#references), but this is this scenario's inference, not a confirmed default.

## 5. Idempotency and safety posture

Idempotency is **create-or-report**: each object is located via the official `-PriorityCleanup`
filter switch on `Get-ComplianceTag`/`Get-RetentionCompliancePolicy`/`Get-RetentionComplianceRule`
(deliberately not an assumed boolean property name on the returned object, none is documented) and,
if present, reported rather than mutated. Deploying requires an explicit `-Simulate` or `-Enabled`
choice; there is no default-on path. `-EnforceSimulation` is a separate, deliberate invocation gated
on a second admin having reviewed simulation results in the portal, this script cannot review or
export those results itself (no documented API). Rollback disables/deletes the policy but never
force-removes the label, and states plainly that a disable/delete cannot recall an approval that has
already completed, matching Microsoft's own limitation notice [[5]](#references).

## 6. Key decisions

| Decision | Choice | Rationale |
|---|---|---|
| Workload | Exchange (data spillage) | Richest approval model; Microsoft's lead use case; SharePoint/OneDrive is a separate follow-up |
| Scope | Static `-ExchangeLocation` (named mailboxes) | Matches "known recipients" data-spillage framing; group mailboxes need adaptive scopes (out of scope, follow-up) |
| Deploy default | Refuse without `-Simulate`/`-Enabled`/`-DryRun` | No silent default-on path for a hold-overriding, irreversible control |
| Approver encoding | `-MultiStageReviewProperty`, 3 stages | Only documented mechanism connecting to the 3-approver requirement; explicitly flagged as this scenario's construction, not a confirmed shape |
| "Delete ASAP" mapping | `RetentionDuration 0`, `RetentionType TaggedAgeInDays` | Closest literal reading available; flagged VERIFY |
| Idempotency | Create-or-report via `-PriorityCleanup` filtered `Get-*` | Avoids inventing an unconfirmed boolean property; matches this repo's high-consequence-object precedent (`retention-labels-financial-records`) |
| Approval execution | Not scripted | No documented PowerShell/Graph cmdlet exists for the "Pending cleanups" approval queue |
| Rollback | Disable/delete policy; never force-remove label; explicit "can't recall a completed approval" warning | Mirrors the irreversibility Microsoft itself documents |

## 7. Non-goals

- **SharePoint/OneDrive priority cleanup** (stale recordings, Preservation Hold library), now built
  as `scenarios/data-lifecycle-management/priority-cleanup-sharepoint-onedrive/`. That sibling's own
  separate public-preview **permanent-deletion** sub-feature remains out of scope and tracked as a
  follow-up in `PROGRESS.md`.
- **Adaptive-scope targeting** (needed for group mailboxes), this scenario is static-scope only.
- **Scripting the approval workflow itself**, no documented API exists; portal-only by design.
- **Tenant-wide on/off toggle automation**, the "Priority cleanup settings" configuration page has no
  confirmed PowerShell/Graph equivalent found during this build's grounding pass; tracked as an open
  gap in `README.md` §11, not fabricated as a cmdlet.
- **eDiscovery search-and-purge as an alternative path**, Microsoft's own tip suggests purging
  (soft-delete) first, then applying priority cleanup to permanently delete the already-soft-deleted
  items, to avoid showing end users the "Retention: ... (-1 days)" message bar [[1]](#references).
  **Built** as `scenarios/ediscovery/search-and-purge-data-spillage/`, that scenario's `README.md`
  §5 step 4 documents the combined workflow explicitly (its own `-PurgeType Recoverable` run, then
  this scenario's `ContentMatchQuery` pointed at the same content) rather than leaving it as an
  implied follow-up.

## References

See `README.md` §12 for the full, numbered source list shared with this file.
