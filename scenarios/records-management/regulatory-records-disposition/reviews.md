# Four-Lens Review - Event-Based Records Disposition with Disposition Review

Reviewed after the initial draft of `README.md`, `design.md`, `deploy/`, and `validate/`. One round of
findings below; all **Fix** items were applied before this file was finalized. No **Fail** items were
raised.

---

## 🔴 Red Team

**Verdict: Fix (resolved)**

1. **An event fired against everything.** The classic event-based-retention foot-gun: a
   `New-ComplianceRetentionEvent` with no asset-ID query starts the retention clock for **all** content
   carrying that event-type label - a broad, un-cancellable action.
   - **Resolution:** The sample config ships a `sharePointAssetIdQuery`, and the deploy prints a **red
     CAUTION** if no asset-ID query is set before firing an event; `README.md` §8/§11 and `design.md` §6
     call this out as the dominant risk.
2. **Accidental clock start.** Someone runs the deploy and unknowingly triggers live retention.
   - **Resolution:** The event is created **only** when `-TriggerEvent` is passed **and** the config's
     `event.create` is true; the default deploy builds the type/label/policy and starts **no** clock.
     Both scripts warn loudly before any event is fired.
3. **Silent auto-delete masquerading as "disposition".** A `KeepAndDelete` label with no reviewer just
   deletes records at end of retention - no review, no proof - while everyone assumes there was a review.
   - **Resolution:** Deploy and validate both **warn** when `reviewerEmail` is empty; `README.md` §6/§11
     and `design.md` §6 make the disposition reviewer the best-practice default.
4. **Casual teardown of a records control.** Deleting labels/event types that are actually holding
   records.
   - **Resolution:** Rollback disables by default; `-Delete` only **attempts** removal and **reports**
     (never forces) failures for applied labels / referenced event types; `-ForceDeletion` is
     deliberately **not** used. `rollback.md` opens with the irreversibility warning.

No remaining Fix/Fail after resolution.

---

## 🔵 Blue Team

**Verdict: Fix (resolved)**

1. **"Did the clock actually start?" is non-obvious.** Event sync is delayed and events are easy to
   miss.
   - **Resolution:** The validate script reports **triggered events** for the event type (count + dates)
     and warns that each is an irreversible start; `README.md` §7/§8 document the 7-day sync and make
     disposition backlog the key operational signal.
2. **Reviewers can't see disposition items.** The Disposition Management role isn't granted to admins by
   default - a silent RBAC trap that strands the whole review step.
   - **Resolution:** `README.md` §3/§11 call out the separate Disposition Management role and that
     reviewers are users or mail-enabled security groups (not M365 Groups).
3. **Working dry-run.** `-WhatIf` doesn't function in S&C PowerShell.
   - **Resolution:** Both scripts implement `-DryRun` printing the exact cmdlets; `README.md` §5 makes
     dry-run the first step, and it starts nothing.

No remaining Fail.

---

## 🎩 CISO

**Verdict: Fix (resolved)**

1. **Examiner-grade reproducibility of the schedule.** Auditors probe how a record class is retained and
   how disposal is decided and evidenced.
   - **Resolution:** The config file is the versioned, diffable records schedule; `README.md` §2 maps to
     DoD 5015.02 / SEC 17a-4 / FINRA 4511 / GDPR storage-limitation, and §7 ties disposal to a reviewed,
     proof-bearing disposition.
2. **Risk vs. cost:** honestly stated in §10 - E5 entitlement (no meter); the real costs are storage for
   event-anchored (possibly indefinite) retention and **human review labor**, with auto-approval offered
   where defensible.
3. **Board/compliance narrative:** "records are retained from the business event that starts their life,
   and disposed only after a reviewed, evidenced decision - defined as reproducible code" - a defensible
   position.
4. **Change management:** the event type is immutable once a label uses it, and triggering is
   irreversible, so both are treated as controlled, signed-off actions.
5. **Would I fund this?** Yes - it operationalizes a records schedule with defensible disposition, the
   part regulators actually test.

No remaining Fix/Fail after resolution.

---

## 🟦 Microsoft Product Owner

**Verdict: Fix (resolved)**

1. **Correct, current cmdlets and flow.** `New-ComplianceRetentionEventType`, `New-ComplianceTag`
   (`-RetentionType EventAgeInDays`, `-EventType`, `-RetentionAction KeepAndDelete`, `-ReviewerEmail`,
   `-IsRecordLabel`), `New-RetentionCompliancePolicy` + `New-RetentionComplianceRule
   -PublishComplianceTag`, and `New-ComplianceRetentionEvent` (`-EventDateTime`,
   `-SharePointAssetIdQuery`) are reproduced from Microsoft's own event-based-retention guidance; the
   Get/Remove `-Identity` parameters were verified.
2. **Right pattern for the obligation.** Event-based retention + disposition review is Microsoft's
   documented model for event-anchored records - not reinvented with age-based labels or custom code.
3. **Publish vs. auto-apply distinction respected.** Uses `-PublishComplianceTag` (deliberate/record
   declaration) rather than `-ApplyComplianceTag`, which is the idiomatic fit and cleanly distinguishes
   this from the sibling DLM auto-apply scenario.
4. **Accurate behavior + limits.** 7-day publish/sync latency, event immutability, can't-cancel events,
   can't-delete applied records, and the 15-day post-approval deletion are stated per the docs; the
   Graph records-management APIs are noted as the modern event-automation path (REST deprecated).
5. **Accurate licensing.** E5 / E5 Compliance / Purview Suite records management.

No remaining Fail after resolution.

---

## Summary

| Lens | Initial verdict | Findings | Resolution |
|---|---|---|---|
| 🔴 Red Team | Fix | 4 (asset-ID-scoped events + caution; gated irreversible trigger; reviewer-required disposition; governed teardown, no ForceDeletion) | Closed |
| 🔵 Blue Team | Fix | 3 (event-triggered reporting in validate; separate Disposition Management RBAC; working `-DryRun`) | Closed |
| 🎩 CISO | Fix | 1 (examiner-grade schedule reproducibility); Pass on cost/narrative/change-mgmt | Closed |
| 🟦 Microsoft Product Owner | Fix | 1 (limits/latency/immutability documented); 4 confirmed correct | Closed |

All Fix items are resolved in the current state of `README.md`, `design.md`,
`deploy/New-RecordsDisposition.ps1`, `deploy/Remove-RecordsDisposition.ps1`,
`deploy/config/records-disposition.sample.json`, and `validate/Test-RecordsDisposition.ps1`. No Fail
items were raised. This fragment meets the definition of done in `AGENTS.md` §9; product facts are
grounded in Microsoft Learn (no invented cmdlets - Get/Remove/New event-type and event parameters were
verified) and the irreversibility of triggered events and applied record labels is treated as a
first-class safety constraint.
