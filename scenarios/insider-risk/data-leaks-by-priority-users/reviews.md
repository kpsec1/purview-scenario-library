# Four-Lens Review - Insider Risk Management: Data Leaks by Priority Users

Reviewed after the initial draft of `README.md`, `design.md`, `deploy/`, and `validate/`. One round
of findings below; all **Fix** items were applied to the scenario before this file was finalized
(see "Resolution" under each). No **Fail** items were raised.

---

## 🔴 Red Team

**Verdict: Fix (resolved)**

1. **Reusing an existing priority user group across this template and the already-built
   `Security policy violations by priority users` sibling silently collapses reviewer-access
   scoping for both policies.** The original draft's §5 Step 4 told the operator to "skip this step
   and reuse the existing priority user group if one already exists for this population" without
   stating that reviewer-permission scoping is a property of the **group**, not the policy -an
   operator who deliberately restricted a group's reviewers for the sibling's own sensitive
   population, then reused the same group for this scenario's policy, would silently grant that
   same reviewer set visibility into this policy's alerts too, with no per-policy override
   available to prevent it. A red-teamer inside the reviewer set for one template gains visibility
   into the other simply because an operator reused a group for convenience.
   - **Resolution:** Added an explicit warning to `README.md` §5 Step 4 before the "reuse an
     existing group" suggestion, plus supporting bullets in §8 (Operations & tuning) and §11
     (Known limitations), stating this as a property of priority user groups generally, not a
     defect unique to this scenario, and recommending a second, dedicated group when two templates'
     alerts need different reviewers for the same population.
2. **A red-teamer aware that priority-group membership only boosts scoring if the "User is a member
   of a priority user group" risk score booster is separately selected could deliberately target a
   population whose operator assigned the group but never selected the booster** - identical
   underlying activity would then score no differently than it would for a non-priority user,
   defeating the entire purpose of choosing this template over the base `Data leaks` template.
   - **Reviewed, already correctly disclosed and treated as the scenario's central finding, not a
     footnote:** `README.md` §5 Step 5, §8's first bullet, §11's first bullet, and `design.md` §2
     goal 4/§5 all state this explicitly and prominently - this is the fragment's own most
     operationally significant grounded finding, called out ahead of every other limitation rather
     than buried. No additional change needed.
3. **This control is invisible to any exfiltration channel outside the specific DLP policies wired
   into the global indicator list or the specific built-in indicators selected** - the same
   structural, disclosed-not-fabricated limitation every Data-leaks-family scenario in this library
   carries.
   - **Reviewed, already correctly disclosed:** `README.md` §11's closing bullet already states
     this. No change needed.

No remaining Fix/Fail after resolution.

---

## 🔵 Blue Team

**Verdict: Fix (resolved)**

1. **The validation script's manual checklist originally compressed three independently-actionable
   checks - the global DLP-alerts-indicator-list addition, the parent policy's `Mode`, and the
   double-scoping overlap - into a single checklist line.** An operator working through the
   checklist could check that single line off after confirming only the first of the three
   (the policy appears in the global list) and never independently verify `Mode` or the
   scope-overlap, since both were folded silently into the same bullet - a materially different
   auditability posture from `../data-leaks/validate/Test-DataLeaksIrmSetup.ps1`'s own checklist,
   which tracks all three as separate items.
   - **Resolution:** Split `validate/Test-DataLeaksPriorityUsersIrmSetup.ps1`'s manual checklist
     into three separate `-DlpTriggerConfigured`-gated items (indicator-list addition, `Mode`
     check, double-scoping cross-check), matching the base `Data leaks` scenario's own granularity
     rather than introducing a less-auditable variant for this sibling.
2. **Is there any detective control confirming the risk score booster is actually selected, versus
   trusting it was configured correctly at setup time?** No Graph/PowerShell read API exists for
   Insider Risk Management policy indicator configuration (`design.md` §2 goal 7) - the same
   disclosed gap every portal-only setting in this library carries.
   - **Reviewed, correctly scoped:** already captured as an explicit, prominently-placed manual
     checklist item in `validate/Test-DataLeaksPriorityUsersIrmSetup.ps1` (marked `CRITICAL`) rather
     than fabricated as an automated check the tooling can't actually perform. No change needed.
3. **The 1,000-actively-scored cap has no query API to check current cumulative usage against**,
   and the dual-cap interaction above 1,000 members remains genuinely unconfirmed for this exact
   template.
   - **Reviewed, already correctly disclosed:** `README.md` §6/§8/§11 and `design.md` §3 all state
     this explicitly, correctly distinguishing it from the (also unconfirmed, but now-corrected as
     non-shared) `security-policy-violations-by-priority-users` sibling's own cap. No change needed.

No remaining Fail. Detection, sizing, and the runbook meet the bar for an operable control once
the Fix above is applied.

---

## 🎩 CISO

**Verdict: Pass**

- **Risk reduction vs. cost:** proportionate - no new licensing tier beyond the base Insider Risk
  Management entitlement, and every scriptable mechanism this scenario needs already exists in two
  sibling scenarios, reused rather than re-licensed or re-engineered. `README.md` §10 states this
  plainly.
- **Board-level narrative:** "our DLP-correlated exfiltration detection is unconditional for the
  general population, and materially more sensitive for our formally designated highest-risk
  population" is a clear, differentiated narrative distinguishing this template from all three of
  its already-built family/cousin siblings (`base Data leaks`, `Data leaks by risky users`,
  `Security policy violations by priority users`) - `README.md` §1/§2 make each distinction
  explicit rather than presenting this as a redundant fifth IRM scenario.
- **Governance tradeoff, stated rather than hidden:** the risk score booster requirement (§8/§11)
  and the reviewer-scoping-is-per-group finding (this review's Red Team item 1) are exactly the
  kind of "the benefit isn't automatic, and reuse has a side effect" details a CISO needs before
  approving this as the control that justifies a formally-designated priority population, rather
  than discovering either gap post-deployment.
- **Compliance mapping:** correctly scoped as DLP-correlated exfiltration-monitoring evidence for a
  formally designated population, not tied to a named regulatory requirement - same honest framing
  as every other Insider Risk Management scenario in this library.
- **Open questions are surfaced as open, not resolved by optimistic assumption** - the dual-cap
  interaction above 1,000 members and the cloud-indicator applicability are both stated as
  unconfirmed rather than guessed, exactly what a CISO would want before committing a genuinely
  sensitive population (e.g., the full executive team) to this template.
- **Would I fund this?** Yes, for a tenant that already runs the base `Data leaks` template and has
  a genuinely higher-risk population warranting both DLP-correlated exfiltration detection and
  restricted reviewer access - with the explicit caveat that the risk score booster must be
  confirmed selected at every deployment sign-off, and that a shared priority user group means
  shared reviewer visibility across every policy that references it.

No Fix/Fail items from this lens.

---

## 🟦 Microsoft Product Owner

**Verdict: Pass**

1. **This scenario's core distinguishing claims - the two-trigger-option shape (matching the base
   `Data leaks` template, not the fixed single-trigger `Security policy violations by priority
   users` shape), the "Add or edit priority user groups" step name, the admin-unit restriction, the
   separately-selectable risk score booster, and the per-exact-template (not per-family) cap - were
   all confirmed by direct Microsoft Learn MCP fetch during this build**, not WebSearch snippets
   alone. Where this build's own findings add precision beyond an already-built sibling scenario's
   earlier grounding pass (the DLP-workload exclusion list's Microsoft 365 Copilot entry; the
   cap-sharing correction), `README.md` §11 and `design.md` §2 goals 5-6 state this explicitly
   rather than silently overriding the sibling or presenting the new findings as though the sibling
   scenarios were wrong when built (they were grounded correctly against what this build's own
   direct-fetch pass could not access from a WebSearch-only session at the time).
2. **The decision not to edit `security-policy-violations-by-priority-users/README.md` or
   `../data-leaks/README.md` directly to carry these corrections/additions back into those
   scenarios is the correct application of this library's fragment-discipline rule**
   (`AGENTS.md` §6) - both are flagged as candidate follow-ups in `design.md` §7 and `README.md`
   §11, recorded for `PROGRESS.md`, not silently left unmentioned.
3. **No fabricated Insider Risk Management policy-authoring, priority-user-group-authoring, or
   DLP-to-IRM scope-comparison API.** Consistent with every other scenario in this library, every
   portal-only gap already disclosed by the two ancestor scenarios is carried forward unchanged,
   not re-litigated or guessed at differently.
4. **The decision to reuse `../data-leaks/deploy/Test-DlpPolicyIrmTriggerReadiness.ps1`,
   `../security-policy-violations-by-priority-users/deploy/
   Get-PriorityUserGroupScopeCandidates.ps1`, and `../departing-employee-data-theft/deploy/
   Export-InsiderRiskAlerts.ps1` unmodified - writing zero new `deploy/` scripts - is correctly
   justified**, not reuse for its own sake: every mechanism this template needs (DLP-trigger
   readiness, priority-group dual-cap sizing, plain alert export) was already built for exactly
   this purpose by two different sibling scenarios, and this template's own requirements introduce
   no new logic either script would need to acquire. `design.md` §2 goals 1-3 state this
   reasoning explicitly rather than assuming reuse is correct without checking.
5. **The explicit `-MaxActivelyScored 1000 -MaxGroupMembers 10000` arguments in §5 Step 3, rather
   than relying silently on the reused script's matching defaults, correctly document that this
   template's cap was independently verified**, not assumed identical to the sibling's number by
   coincidence of a shared default value - a subtle but real grounding-integrity distinction this
   review confirms was handled correctly rather than glossed over.

No Fix/Fail items from this lens.

---

## Summary

| Lens | Initial verdict | Findings | Resolution |
|---|---|---|---|
| 🔴 Red Team | Fix | 3 (1 closed with a README §5/§8/§11 addition, 2 confirmed already correctly disclosed) | Closed |
| 🔵 Blue Team | Fix | 3 (1 closed with a validate-script checklist split, 2 confirmed already correctly scoped) | Closed |
| 🎩 CISO | Pass | - | - |
| 🟦 Microsoft Product Owner | Pass | - | - |

The Red Team finding - that reusing a priority user group across two policies silently collapses
reviewer-access scoping to a single shared set, with no per-policy override - was the most
operationally significant new finding of this round, closed with documentation in three places
(§5 Step 4, §8, §11) rather than left implicit in the general "priority user groups are
standalone objects" framing already present. The Blue Team finding improved the validation script's
auditability to match the granularity already established by this scenario's own base-template
ancestor, rather than accepting a quietly less-rigorous checklist for this sibling. No Fail items
were raised. This fragment meets the definition of done in `AGENTS.md` §9.
