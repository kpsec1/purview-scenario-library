# Four-Lens Review - Multi-Stage Disposition Review Panel

Reviewed after the initial draft of `README.md`, `design.md`, `deploy/`, and `validate/`. One round of
findings below; all **Fix** items were applied before this file was finalized (both are reflected in the
current `README.md` §8/§11 and `design.md` §6). No **Fail** items were raised.

---

## 🔴 Red Team

**Verdict: Fix (resolved)**

1. **`AutoApprovalPeriod` as a rushed-disposal lever.** Anyone holding the config role can set a short
   `AutoApprovalPeriod` (minimum 7 days) on the **final** stage specifically, so a record is disposed
   with zero human review while looking like ordinary configuration - the classic "insider abuses a
   legitimate feature" pattern, sharper here than in the parent scenario because the whole point of a
   chain is human sign-off, and this one setting can silently remove it from the last, most consequential
   stage.
   - **Resolution:** README §8 states this explicitly rather than treating `AutoApprovalPeriod` as a
     convenience default; recommends a shorter window paired with an operational alert at the
     penultimate→final stage transition rather than one global setting.
2. **Chain tampered with outside this repo's scripts.** Nothing stops someone with the Records
   Management / Retention Management role from calling `Set-ComplianceTag` directly to drop a stage,
   repoint reviewers to an attacker-controlled mailbox, or shorten `AutoApprovalPeriod` - invisible to
   this scenario's own deploy/validate scripts, which only check state at the time they're run.
   - **Resolution:** README §8 and `design.md` §6 now name this explicitly and recommend role
     restriction + `Search-UnifiedAuditLog` monitoring of `ComplianceTag` changes as a compensating
     control. The exact `RecordType`/`Operations` values weren't grounded in this fragment (would need
     its own dedicated grounding pass, per this repo's established pattern for audit-log facts) - tracked
     as a follow-up in `PROGRESS.md` rather than guessed.
3. **Event fired against everyone, not one employee.** Same foot-gun as the parent scenario: an event
   with no asset-ID query retains all content under the event type.
   - **Resolution:** Same mitigation as parent - sample config ships a single-employee asset-ID query;
     deploy prints a red CAUTION if none is set.
4. **Casual teardown of an in-force sign-off chain.** Deleting a label/event type that's actually gating
   real disposals.
   - **Resolution:** Rollback disables by default; `-Delete` only attempts and reports (never forces)
     removal of an in-use label/event type - identical discipline to the parent scenario.

No remaining Fix/Fail after resolution.

---

## 🔵 Blue Team

**Verdict: Fix (resolved)**

1. **Per-stage backlog isn't scriptable.** A chain adds a new operational failure mode the parent
   scenario doesn't have: a backlog stuck at Stage 1 never reaches Legal or Records Management at all,
   and looks identical to "nothing pending" from outside. No documented PowerShell/Graph cmdlet for
   per-stage queue depth was found during this build's grounding.
   - **Resolution:** README §8 names per-stage backlog (not just aggregate) as the key KPI; §11 states
     plainly that no scripted query was found - it's a portal-only check today, tracked as a follow-up
     rather than silently assumed to exist.
2. **Working dry-run that actually shows the payload.** `-WhatIf` doesn't function in S&C PowerShell, and
   a JSON-based parameter is exactly the kind of thing that's easy to get subtly wrong without seeing it.
   - **Resolution:** `-DryRun` prints the exact `-MultiStageReviewProperty` JSON before any live run, not
     just the cmdlet name.
3. **Reviewers can't see their stage's items.** Disposition Management role gap, same trap as the parent
   scenario, sharper here because it can silently strand one stage while the rest of the chain looks
   configured correctly.
   - **Resolution:** README §3/§11 call out the role requirement per stage explicitly.
4. **Validate must not hard-fail on an unconfirmed property.** If `MultiStageReviewerMetadata` turns out
   to be wrong (name, casing, shape), a validate script that hard-fails on it would block CI pipelines on
   a documentation gap, not a real misconfiguration.
   - **Resolution:** Every check touching that property is `[WARN]`, never `[FAIL]`, read defensively via
     `PSObject.Properties[...]`.

No remaining Fail.

---

## 🎩 CISO

**Verdict: Fix (resolved)**

1. **Funding a checkbox vs. funding a control.** A multi-stage panel sounds like stronger governance on
   a slide, but if `AutoApprovalPeriod` quietly does the disposing, the organization is paying
   reviewer-labor cost for stages that no longer review anything.
   - **Resolution:** README §8/§10 state this tension directly - the auto-approval risk is treated as a
     first-class operational decision to sign off on, not a footnote, and §10 ties the added stage cost
     explicitly to the risk it's meant to buy down.
2. **Litigation-exposure narrative is defensible and specific.** §2/§3 ground the "why a chain, not a
   single reviewer" argument in concrete U.S. recordkeeping floors (EEOC 1-year, FLSA 2/3-year) rather
   than a generic "best practice" claim, and explicitly avoid an outdated citation (EO 11246, rescinded
   effective Oct 26, 2026) that a less careful build would have reached for.
3. **Cost is honestly multiplied, not hidden.** §10 states plainly that a 3-stage chain is 3 teams' review
   time per disposal decision, not 1.
4. **Change management:** the reviewer chain is versioned config, not a portal-only setting nobody can
   diff; changing it deliberately requires going outside the deploy script, which is itself documented as
   intentional (not an oversight).
5. **Would I fund this?** Yes, for the record classes that actually carry this level of exposure - with
   the explicit caveat that funding it without the `AutoApprovalPeriod` and audit-monitoring discipline in
   §8 buys a compliance narrative, not the actual risk reduction.

No remaining Fix/Fail after resolution.

---

## 🟦 Microsoft Product Owner

**Verdict: Pass**

1. **Correct, current cmdlets and parameters.** `-MultiStageReviewProperty` and `-ComplianceTagForNextStage`
   on both `New-ComplianceTag` and `Set-ComplianceTag` were verified against Microsoft's own published
   parameter reference (via the GitHub-mirrored `MicrosoftDocs/office-docs-powershell` source, fetched
   directly - two independent pages, both showing the same JSON syntax and the same unfilled
   `-ComplianceTagForNextStage` description). `-AutoApprovalPeriod`'s 7-365 day range and default, and
   the stage/reviewer limits (5 stages, 10 reviewers/stage), match Microsoft's disposition documentation.
2. **Right feature for the job, not reinvented.** This is Microsoft's own documented mechanism for a
   sign-off chain - no custom approval workflow was built where Purview already ships one.
3. **Correctly distinguishes documented-but-unexplained from confirmed, and doesn't conflate two
   different mechanisms.** `-MultiStageReviewProperty` (the reviewer chain) and `-ComplianceTagForNextStage`
   (an end-of-retention relabel, by the closest documented analog) are two separate, easily-confused
   parameters on the same cmdlet. Rather than either inventing a description for the latter or silently
   dropping it, the scenario cites Microsoft's own placeholder text verbatim, offers the Graph
   `labelToBeApplied` analog only as context labeled "not confirmed identical," and keeps the two
   concepts textually distinct throughout `README.md`, `design.md`, and the deploy script's `.DESCRIPTION`.
4. **Create-or-report is a deliberate, repo-wide stance, not a gap.** The portal does let an admin edit a
   label's disposition stages after creation; this scenario's scripts deliberately don't automate that,
   consistent with how the parent scenario already treats every records object as high-consequence and
   never silently mutated. Noted as an intentional conservatism, not a missing feature.
5. **Accurate licensing.** Same E5/E5 Compliance/Purview Suite records-management entitlement as the
   parent scenario - multi-stage review isn't a separately licensed add-on.

No Fix or Fail findings raised.

---

## Summary

| Lens | Initial verdict | Findings | Resolution |
|---|---|---|---|
| 🔴 Red Team | Fix | 4 (auto-approval-as-rushed-disposal named explicitly; chain-tampering + audit-monitoring recommendation; asset-ID-scoped events; governed teardown) | Closed |
| 🔵 Blue Team | Fix | 4 (per-stage backlog named as unscriptable, not assumed; JSON-printing dry-run; per-stage RBAC; defensive/WARN-only read-back) | Closed |
| 🎩 CISO | Fix | 2 (checkbox-vs-control risk named; multiplied cost stated); Pass on litigation narrative, change-mgmt, funding decision | Closed |
| 🟦 Microsoft Product Owner | Pass | 0 blocking findings; 5 confirmed correct (cmdlets/parameters, right feature, documented-vs-confirmed handling, deliberate create-or-report stance, licensing) | Closed |

All Fix items are resolved in the current state of `README.md`, `design.md`,
`deploy/New-MultiStageDispositionReview.ps1`, `deploy/Remove-MultiStageDispositionReview.ps1`,
`deploy/config/multi-stage-disposition-review.sample.json`, and
`validate/Test-MultiStageDispositionReview.ps1`. No Fail items were raised. This fragment meets the
definition of done in `AGENTS.md` §9; product facts are grounded in Microsoft Learn - verified directly
against Microsoft's own published PowerShell reference source (New-ComplianceTag.md / Set-ComplianceTag.md
via the `MicrosoftDocs/office-docs-powershell` GitHub mirror) and the `disposition`/`event-driven-retention`
conceptual documentation - with the two remaining genuine gaps (the `MultiStageReviewerMetadata` read-back
property and `-ComplianceTagForNextStage`'s actual behavior) disclosed as VERIFY items rather than resolved
by guessing, per `AGENTS.md` §4.

---

## Correction addendum (2026-09-27, maintenance pass - no new four-lens round per `AGENTS.md` §6)

The `-ComplianceTagForNextStage` VERIFY referenced in finding 1/3 above (Microsoft Product Owner) and
cited as open in `README.md` §11/`design.md` §5 has been **grounded, not left open**: Microsoft's file
plan manager documents an identically-named `ComplianceTagForNextStage` import property ("the name of a
replacement label to be applied at the end of the retention period"), and its "Relabeling at the end of
the retention period" reference confirms the full mechanics. The Graph `labelToBeApplied` analog cited in
finding 3 is now a corroborating source, not the primary grounding. This is a doc/fact correction only -
the parameter stays opt-in (off by default) in the deploy script, so it doesn't reopen the Product Owner
lens's Pass verdict; it tightens finding 1/3 from "documented-but-unexplained, closest analog only" to
"confirmed via a same-name Microsoft-documented property." The `MultiStageReviewerMetadata` read-back
property remains the one open VERIFY for this scenario.
