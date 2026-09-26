# Four-Lens Review - Event-Based Retention and Multi-Stage Disposition for Employee Records

Reviewed after the initial draft of `README.md`, `design.md`, `deploy/`, and `validate/`. One round
of findings below; all **Fix** items were applied before this file was finalized (see the "Apply the
label at hire, not at departure" callout in `README.md` §5/§11 and `design.md` §4). No **Fail** items
were raised.

---

## 🔴 Red Team

**Verdict: Fix (resolved)**

1. **The protection window before a record is labeled.** A publish-based label protects nothing
   until a records manager actually applies it. If the operating assumption is "apply the label when
   the employee leaves," there's a real window - hours to days, depending on HR/records workload -
   where a departing employee's own records are ordinary, editable/deletable content, not a locked
   record. A departing employee (or anyone else with access) could alter or delete material during
   exactly that window.
   - **Resolution:** `README.md` §5/§11 and `design.md` §4 now explicitly recommend applying the
     label (and setting `ComplianceAssetID`) **at hire/onboarding**, not at offboarding - so the only
     action required at departure is firing the event, which is instantaneous and scripted. The gap
     is disclosed as a limitation of the publish-based design rather than silently assumed away.
2. **Unscoped event = tenant-wide retention of that event type.** Firing an event with no Asset ID
   scope starts the retention (and eventual disposition/deletion) clock for **every** item under
   that event type, not just one employee's - a single mistaken command has a blast radius far
   beyond its intent.
   - **Resolution:** `New-RetentionTriggerEvent.ps1` **requires** `-EmployeeId` and throws if it's
     omitted unless `-Force` is explicitly passed; `README.md` §10/§11 name this as the dominant risk.
3. **Duplicate/redundant events under different names aren't detected.** The trigger script refuses
   to re-fire an event with an identical `-Name`, but has no way to detect that a *different-named*
   event was already fired for the same employee (no documented query-by-Asset-ID cmdlet exists) -
   a careless second run with a slightly different name could fire a second, redundant event.
   - **Resolution:** Disclosed explicitly in the script's own `.DESCRIPTION`, `README.md` §11, and
     `design.md` §5, with a naming convention (`<event type> - <employee ID>`) recommended as the
     only available mitigation. Firing a second event for an already-covered employee is redundant,
     not destructive (Microsoft's model runs each event's own retention/disposition independently),
     so this is a hygiene finding, not a data-loss one.

No remaining Fail after resolution.

---

## 🔵 Blue Team

**Verdict: Fix (resolved)**

1. **No reconciliation between HR terminations and fired events.** Without a "which departed
   employees have no matching event" report, a missed event means that employee's records simply
   never start their retention clock - a silent gap, not a loud failure.
   - **Resolution:** Named explicitly as a non-goal (`design.md` §7) and a limitation
     (`README.md` §8/§11), tracked as a follow-up in `PROGRESS.md` rather than silently omitted. The
     validate script's own closing note points operators at `Get-ComplianceRetentionEvent` for
     manual, per-employee spot-checks in the meantime.
2. **No audit-trail export.** Operators have no scripted way to pull a history of event creation,
   label application, or disposition decisions for this scenario specifically (the pattern several
   sibling scenarios in this repo use for their own audit trails).
   - **Resolution:** Disclosed in `README.md` §11 rather than fabricating `Search-UnifiedAuditLog`
     `RecordType`/`Operations` values that weren't grounded in this build; tracked as a follow-up in
     `PROGRESS.md`.
3. **Operability of validation.** Need a fast, safe pre-flight that doesn't require reading portal
   screens.
   - **Resolution:** `validate/Test-EventBasedRetentionAndDisposition.ps1` read-only-checks the event
     type, label (action/type/duration/event-binding/record flag/review config), policy
     (enabled + location), and rule (publishes the expected label); exits non-zero for CI. It also
     explicitly tells the operator what it does **not** check (individual fired events) rather than
     implying full coverage.

No remaining Fail.

---

## 🎩 CISO

**Verdict: Fix (resolved)**

1. **This is a people/process control wearing a technology hat.** The technology only works if HR
   actually tells Purview when someone leaves - no automated HR-system trigger is wired up. Funding
   the Purview capability without funding the operational discipline (an HR-to-Records handoff SLA)
   buys a false sense of compliance.
   - **Resolution:** `README.md` §8 frames "events fired vs. departed employees" as a KPI to track,
     and §11/`design.md` §7 are explicit that the HR-feed connector is a scoped-out follow-up, not a
     solved problem - the narrative to a CISO is "this is the Purview half of the control; you still
     need the HR-process half," not "deploy this and you're done."
2. **Risk vs. cost:** the control is E5 entitlement plus real reviewer workload (two stages, per
   departed employee, at end of retention) - honestly stated in §10 rather than presented as a
   set-and-forget automation.
3. **Board/records-committee narrative:** "departed-employee records are retained for the
   organization's actual post-separation obligation, starting from the real departure date, and
   nothing is permanently destroyed without HR **and** Legal sign-off" - a stronger, more defensible
   narrative than a single-approver or auto-delete pattern.
4. **Change management:** the event type's permanent binding to a label (§6) is called out
   explicitly as a reason to plan the event-type taxonomy before deploying, not after.
5. **Would I fund this?** Yes - it directly addresses both over-retention (unbounded storage/legal
   exposure) and premature deletion (spoliation risk), with the operational dependency honestly
   scoped rather than hidden.

No remaining Fix/Fail after resolution.

---

## 🟦 Microsoft Product Owner

**Verdict: Fix (resolved)**

1. **Correct, current cmdlets.** `New-ComplianceRetentionEventType`, `New-ComplianceTag -EventType`
   (with `-RetentionAction`/`-RetentionType`/`-RetentionDuration`/`-IsRecordLabel`/
   `-MultiStageReviewProperty`/`-AutoApprovalPeriod`), `New-RetentionCompliancePolicy`,
   `New-RetentionComplianceRule -PublishComplianceTag`, and `New-ComplianceRetentionEvent` were all
   fetched directly from their official Microsoft Learn reference pages in this build (2026-09-10),
   not reproduced from a secondary source.
2. **Right feature for the job, and the right automation surface.** Event-based retention
   (`EventAgeInDays`) is correctly distinguished from this module's creation-age sibling, and from
   the Graph-based records-management API surface - Microsoft's own "Automate events by using
   PowerShell" section lists the exact cmdlets this scenario uses as the current, supported path; a
   **separate**, older REST API for automating events is the thing that's deprecated, not this one
   [[1]](#references) - correctly not used here.
3. **Publish over auto-apply is the right call, not a shortcut.** `design.md` §4 explains why: no
   per-employee content signal exists for auto-apply to match on. This mirrors Microsoft's own
   worked event-based examples, which all describe manual application with an Asset ID.
4. **Accurate licensing.** E3 for retention labels/policies; E5/E5 Compliance/Purview Suite for
   event-based retention, disposition review, and record labels - consistent with this module's
   sibling scenario and the cross-cutting licensing matrix.
5. **Honest about documentation gaps instead of guessing.** `-AutoApprovalPeriod`'s stub description,
   the undocumented `MultiStageReviewProperty`/`ReviewerEmail` read-back shape, and their possible
   coexistence are all flagged as VERIFY rather than asserted - consistent with `AGENTS.md` §4.

No remaining Fail after resolution.

---

## Summary

| Lens | Initial verdict | Findings | Resolution |
|---|---|---|---|
| 🔴 Red Team | Fix | 3 (protection-window gap + hire-time mitigation; unscoped-event guard; undetectable duplicate-name events) | Closed |
| 🔵 Blue Team | Fix | 3 (HR/event reconciliation gap disclosed; no audit-trail export disclosed; validate pre-flight scope stated honestly) | Closed |
| 🎩 CISO | Fix | 1 (people/process dependency framed honestly); Pass on cost/narrative/change-management | Closed |
| 🟦 Microsoft Product Owner | Fix | 1 (documentation-gap honesty); 4 confirmed correct | Closed |

All Fix items are resolved in the current state of `README.md`, `design.md`,
`deploy/New-EventBasedRetentionAndDisposition.ps1`, `deploy/New-RetentionTriggerEvent.ps1`,
`deploy/Remove-EventBasedRetentionAndDisposition.ps1`,
`deploy/config/employee-departure-retention.sample.json`, and
`validate/Test-EventBasedRetentionAndDisposition.ps1`. No Fail items were raised. This fragment meets
the definition of done in `AGENTS.md` §9; product facts are grounded in Microsoft Learn pages fetched
directly during this build (no invented cmdlets), and undocumented edges (event read-back shapes,
`-AutoApprovalPeriod`) are flagged inline rather than guessed.
