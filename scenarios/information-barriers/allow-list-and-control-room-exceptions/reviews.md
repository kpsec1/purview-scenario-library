# Four-Lens Review — Allow-List Topologies and Control-Room/Compliance Exceptions

Reviewed after the initial draft of `README.md`, `design.md`, `deploy/`, and `validate/`. One round of
findings below; all **Fix** items were applied before this file was finalized. No **Fail** items were
raised.

---

## 🔴 Red Team

**Verdict: Fix (resolved)**

1. **Legacy-mode Allow policy silently isolates the exception segment from the rest of the company —
   a collateral-damage bug dressed as a compliance control.** In Legacy IB mode, assigning an Allow
   policy to `ComplianceControlRoom` hides **every** non-IB user/group from that segment's members,
   not just the segments left off the allow list. A control-room analyst who suddenly can't reach
   their own manager or the IT helpdesk is exactly the kind of self-inflicted outage that gets an
   ethical-wall program rolled back in a panic — worse, it could push an org toward disabling IB
   altogether rather than diagnosing the real cause.
   - **Resolution:** Grounded via Microsoft Learn (multi-segment support page, Legacy-mode
     visibility rule) and scripted as a live, non-fatal check: both
     `deploy/New-ControlRoomAllowException.ps1` and `validate/Test-ControlRoomAllowException.ps1`
     call `Get-PolicyConfig` and print a loud `CAUTION`/`[WARN]` if the tenant is in Legacy mode.
     `README.md` §3 and §11 (top of the gotcha list) and `design.md` §5 require **SingleSegment**
     mode explicitly, not "Legacy or SingleSegment" as an earlier draft of this scenario assumed.
2. **Allow-list scope creep is a slower, quieter version of the same bypass a Block wall prevents.**
   Every name added to `ComplianceControlRoom`'s membership is a standing exception to the wall; an
   uncontrolled or rubber-stamped growth path defeats the wall's intent without ever touching a
   policy object.
   - **Resolution:** `README.md` §8 frames a growing exception segment as a finding, recommends
     `Legal`'s narrower, one-sided allow-list as the default model over "sees everything," and points
     out that IB itself doesn't detect misuse — only unauthorized access — so this is explicitly
     flagged as a governance responsibility, not something the code can enforce.
3. **A user matching two segments' attribute filters (e.g. someone tagged both `Trading` and
   `ComplianceControlRoom`) would defeat the wall outright** if it ever happened, since SingleSegment
   mode assumes exactly one segment per user but doesn't itself prevent an attribute misconfiguration
   that satisfies two filters.
   - **Resolution:** `deploy/config/control-room-allow-exceptions.sample.json`'s `_segmentsNote`
     explicitly calls out that no one in the exception segments should also sit in `Trading`/
     `Research`; `README.md` §8 lists membership-count review as an operational signal for exactly
     this kind of drift.
4. **Editing an Active Allow policy's membership and forgetting to reactivate leaves a stale
   allow-list silently enforced** (a new analyst added to config but never actually granted access,
   or an offboarded one still walking around with access because reactivation didn't happen).
   - **Resolution:** The deploy script always leaves a reconciled, previously-Active policy
     **Inactive** and prints an explicit warning requiring a fresh `-Activate`; it never silently
     reactivates. `validate/Test-ControlRoomAllowException.ps1`'s `SegmentsAllowed`-matches-config
     check plus its `-RequireActive` state check together catch this: a reconciled-but-not-reactivated
     policy shows the right membership but a `[WARN]`/`[FAIL]` state, making the gap visible.

No remaining Fix/Fail after resolution.

---

## 🔵 Blue Team

**Verdict: Fix (resolved)**

1. **"Did the reconciliation actually take effect?" is non-obvious**, especially since a
   `SegmentsAllowed` edit forces a state round-trip (Active → Inactive → back to Active) that's easy
   to lose track of across two separate script runs.
   - **Resolution:** The deploy script prints an explicit `[policy] '<name>' reconciled...(was Active
     - now Inactive; re-run with -Activate...)` message; the validate script's combined
     membership-match + state checks give a single place to confirm both landed.
2. **Detecting misuse of a legitimate cross-wall exception isn't an IB concern at all**, and a reader
   could mistake this scenario for a complete monitoring solution.
   - **Resolution:** `README.md` §8 and `design.md` §6 state plainly that usage monitoring is a
     DLP/Activity Explorer/insider-risk concern layered on top, not something this scenario or IB
     policy configuration provides.
3. **Working dry-run and idempotent reconciliation.** `-WhatIf` doesn't function in S&C PowerShell,
   and a naive "always call New-/Set-" script would either error on existing objects or blindly
   re-issue Set- calls every run.
   - **Resolution:** `-DryRun` is implemented on both scripts; the deploy script only calls `Set-`
     when a genuine `SegmentsAllowed` drift is detected (order-independent, case-insensitive
     comparison), so a clean re-run reports `already matches config` and changes nothing.

No remaining Fail.

---

## 🎩 CISO

**Verdict: Fix (resolved)**

1. **The Legacy-mode finding above is also a board-level risk item, not just an engineering bug**: an
   outage caused by a poorly-understood compliance control (control room loses contact with the rest
   of the company) is reputationally worse than no control at all, and erodes trust in future
   compliance tooling.
   - **Resolution:** Elevated to the top of `README.md` §11's gotcha list (not buried), with an
     explicit remediation command (`Set-PolicyConfig -InformationBarrierMode SingleSegment`) and a
     scripted, automatic warning rather than relying on a reader to find it in prose.
2. **Examiner narrative for the exception itself.** A regulator reviewing the ethical wall will ask
   "who can see across it, and why" — this needs to be a clean answer, not a shrug.
   - **Resolution:** The config file is the versioned, diffable list of exactly which segments have
     standing cross-wall access and to what scope (`ComplianceControlRoom`: both sides;
     `Legal`: one side only) — `README.md` §2 and §8 frame this as the audit artifact.
3. **Risk vs. cost:** no incremental licensing; the real cost is the governance discipline of keeping
   exception membership narrow — stated honestly in §10, consistent with the base scenario's own
   framing.
4. **Board/compliance narrative:** "our ethical wall has a controlled, reviewable, narrowly-scoped
   supervisory exception, with the same activation discipline as the wall itself" — strengthens
   rather than undermines the base scenario's own narrative.
5. **Would I fund this?** Yes — it closes a real gap (an unsupervisable wall is itself a finding) with
   guardrails proportional to both the wall's and the exception's live-communication impact.

No remaining Fix/Fail after resolution.

---

## 🟦 Microsoft Product Owner

**Verdict: Fix (resolved)**

1. **Correct, current cmdlets.** `New-InformationBarrierPolicy -SegmentsAllowed`,
   `Set-InformationBarrierPolicy -SegmentsAllowed` (with the documented deactivate-before-edit
   workflow), and `Get-PolicyConfig -InformationBarrierMode` are reproduced from Microsoft's own
   cmdlet references and edit-workflow guidance, not invented.
2. **Product-idiomatic pattern, verbatim from Microsoft's own walkthrough.** The "Get started with
   Information Barriers" doc's own worked example describes a third segment (their example: HR)
   staying compatible with two segments a Block policy keeps apart — this scenario's
   `ComplianceControlRoom` plays that exact role for `Trading`/`Research`; not a novel or
   unsupported topology.
3. **Accurate, non-obvious mode guidance.** The Legacy-vs-SingleSegment-vs-MultiSegment distinction —
   including the specific Legacy-mode Allow-policy visibility rule most write-ups gloss over — is
   surfaced and enforced by a live tenant check rather than left as a footnote.
4. **Honest about an unconfirmed mechanic.** The replace-vs-merge semantics of
   `Set-InformationBarrierPolicy -SegmentsAllowed` aren't stated explicitly in Microsoft's own
   reference; this scenario states its assumption (replace) and flags it as an open pilot-tenant
   VERIFY rather than presenting it as confirmed fact.
5. **Not reinventing native capability, and correctly scoped as a companion.** Uses native cmdlets
   only, explicitly refuses to touch the base scenario's objects, and doesn't attempt the
   MultiSegment/all-Allow-policy rebuild that a different (larger) scenario would need.
6. **Accurate licensing.** No incremental entitlement beyond the base scenario's E5/E5
   Compliance/IRM/IB add-on.

No remaining Fail after resolution.

---

## Summary

| Lens | Initial verdict | Findings | Resolution |
|---|---|---|---|
| 🔴 Red Team | Fix | 4 (Legacy-mode collateral isolation + scripted check; allow-list scope-creep governance; mutually-exclusive-segment drift; reactivation-forgetting gap) | Closed |
| 🔵 Blue Team | Fix | 3 (reconciliation-landed visibility; misuse-monitoring scope disclaimer; working dry-run/idempotent reconciliation) | Closed |
| 🎩 CISO | Fix | 2 (Legacy-mode risk elevated to board-relevant; examiner narrative for the exception); Pass on cost/board-narrative/funding | Closed |
| 🟦 Microsoft Product Owner | Fix | 1 (mode guidance surfaced + enforced); 5 confirmed correct | Closed |

The Legacy-mode Allow-policy visibility rule (🔴 Red Team finding 1 / 🎩 CISO finding 1) was the
substantive discovery of this review round — grounded via Microsoft Learn rather than assumed, and
resolved by requiring SingleSegment mode explicitly (not "Legacy or SingleSegment," as this
scenario's design would otherwise have allowed) plus a live, scripted `Get-PolicyConfig` check in
both `deploy/New-ControlRoomAllowException.ps1` and `validate/Test-ControlRoomAllowException.ps1`.
All other Fix items are resolved in the current state of `README.md`, `design.md`,
`deploy/New-ControlRoomAllowException.ps1`, `deploy/Remove-ControlRoomAllowException.ps1`,
`deploy/config/control-room-allow-exceptions.sample.json`, and
`validate/Test-ControlRoomAllowException.ps1`. No Fail items were raised. This fragment meets the
definition of done in `AGENTS.md` §9; product facts are grounded in Microsoft Learn (no invented
cmdlets), the one genuinely unconfirmed mechanic is flagged as VERIFY rather than guessed, and the
live-communication impact of both activation and reconciliation is treated as a first-class safety
constraint.
