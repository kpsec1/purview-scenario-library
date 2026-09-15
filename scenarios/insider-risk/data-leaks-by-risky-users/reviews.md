# Four-Lens Review — Insider Risk Management: Data Leaks by Risky Users

Reviewed after the initial draft of `README.md`, `design.md`, `deploy/`, and `validate/`. One round
of findings below; all **Fix** items were applied to the scenario before this file was finalized
(see "Resolution" under each). No **Fail** items were raised.

---

## 🔴 Red Team

**Verdict: Fix (resolved)**

1. **Coverage is bounded by the specific indicators selected, not "all exfiltration channels."**
   The original draft's §6/§8 described the Office-indicator scoring category without stating which
   channels it does NOT observe — printing, removable media/USB, and attachments sent from a
   personal (non-Microsoft-365) email account are all outside this template's indicator set unless
   a separately-scoped control also covers them.
   - **Resolution:** Added an explicit §11 bullet naming these three specific uncovered channels
     and cross-referencing that a device-control/endpoint-DLP scenario elsewhere in this library
     would be needed for that coverage, rather than leaving the gap implicit in "invisible to
     exfiltration channels outside the selected indicator set."
2. **Cumulative exfiltration detection's 30-day peer-group baseline has two evasion properties the
   original draft's §8 Entra-data-sharing note didn't capture:** a recently hired user has no
   established personal baseline yet, and a paced/slow-drip exfiltrator staying under peer-group
   norms is — by the documented design of this indicator — not detected by it.
   - **Resolution:** Added an explicit §11 bullet naming both properties as structural, Microsoft-
     controlled evasion vectors (not a configuration gap this scenario can close), parallel to how
     the Communication Compliance message-count threshold is already disclosed as an evasion
     vector in the same section.
3. **A disciplined insider could avoid both trigger paths simultaneously** (no qualifying HR event,
   staying under the CC message threshold) to remain permanently out of scope regardless of
   underlying exfiltration risk — the same structural gap the `security-policy-violations-by-
   risky-users` sibling's own Red Team review already found and disclosed for the identical trigger
   mechanism.
   - **Reviewed, no additional change needed:** already covered by this scenario's own §11 bullet
     on the CC threshold (carried forward from the sibling) combined with the AND/OR trigger-shape
     disclosure in §8/§11 — the honest answer is that this template's trigger coverage is bounded
     by its two documented mechanisms, with the base `Data leaks` template (unconditional scope) as
     the compensating control, exactly as the sibling's own README already states for the identical
     situation. No separate bullet needed beyond the existing cross-reference.

No remaining Fix/Fail after resolution.

---

## 🔵 Blue Team

**Verdict: Fix (resolved)**

1. **Operator-error risk: three near-identical HR-connector-upload invocations now exist in this
   library** (`departing-employee-data-theft`, `security-policy-violations-by-risky-users`, and
   this scenario), all using the same `Send-Hr*Record.ps1 -AppId ... -JobId ...` calling
   convention. The original draft didn't flag the risk of an operator pasting the wrong sibling's
   `-JobId` into a scheduled task for this scenario — a silent misdirection with no error, since the
   webhook itself has no scenario-awareness beyond the JobId.
   - **Resolution:** Added an explicit §11 bullet naming this risk, a corresponding §8 operational
     recommendation to verify the JobId/AppId pair before scheduling, and a new manual-checklist
     item in `validate/Test-DataLeaksRiskyUsersIrmSetup.ps1` calling it out explicitly rather than
     leaving it as an unstated assumption that operators will get the parameters right.
2. **Is there a detective control confirming the (third) dedicated HR connector wasn't accidentally
   created pointing at the wrong app registration or scenario mapping?** No Graph/PowerShell read
   API exists for HR connector configuration — same disclosed gap as both sibling scenarios.
   - **Reviewed, correctly scoped:** already captured in the manual checklist as an explicit item
     naming this as the THIRD dedicated connector (distinct from both siblings') with a recent
     import log entry required. The honest answer remains "no automated detective control exists
     for connector configuration itself." No change needed beyond the existing checklist wording,
     which already distinguishes this connector from both siblings' by name.
3. **Does the reused plain alert-export script (`departing-employee-data-theft/deploy/
   Export-InsiderRiskAlerts.ps1`) correctly avoid doing wasted work for this template, given the
   sibling's own export script exists specifically to join Defender for Endpoint alerts?**
   - **Reviewed, correctly scoped:** `design.md` §2 goal 3/§6 already states explicitly why the
     plain, non-joining script is the correct reuse target for this template (no Defender for
     Endpoint signal exists to join against) — this was a design decision made correctly from the
     first draft, not a gap found during review. No change needed.

No remaining Fail. Detection, sizing, and the runbook meet the bar for an operable control once the
Fix above is applied.

---

## 🎩 CISO

**Verdict: Fix (resolved)**

1. **Two "risky users" templates now exist in this library, sharing an identical trigger mechanism
   and a numerically identical (but separately tracked) 7,500-user cap — the original draft didn't
   address the cost/complexity question of deploying both against the same population.** A CISO
   evaluating this scenario alongside the already-built `security-policy-violations-by-risky-users`
   sibling needs guidance on when one template alone is sufficient versus when both are justified,
   since running both against an overlapping population doubles the HR-connector/Communication-
   Compliance operational surface without necessarily doubling detection value if the two
   templates' indicator sets don't both matter for that population.
   - **Resolution:** Added an explicit §11 bullet recommending the population/template mapping be
     documented and justified rather than defaulting to "deploy both," and cross-referenced this
     from `README.md` §2 (via the shared governance framing) as a cost-and-complexity
     consideration a CISO should expect to be asked about.
2. **HR/Legal governance carryover, correctly handled.** The original draft already restated the
   sibling's HR/Legal sign-off recommendation in §2/§8 rather than treating it as sibling-specific —
   confirmed during this review as the correct posture, since the underlying HR-connector mechanism
   and its retaliation-perception risk are identical between the two templates. No change needed.
- **Risk reduction vs. cost:** favorable relative to the sibling for a tenant that hasn't licensed
  or deployed Microsoft Defender for Endpoint — this template reaches the same employment-stressor-
  triggered detection value without that dependency, correctly framed in §2/§10 as the scenario's
  differentiator.
- **Board-level narrative:** "we correlate behavioral/employment-stressor signals with data-
  exfiltration activity, independent of endpoint security tooling" is a distinct, defensible
  narrative from the sibling's Defender-for-Endpoint-dependent framing — §1/§2 state this clearly.
- **Compliance mapping:** correctly scoped as data-exfiltration monitoring evidence for a
  behaviorally-flagged population, not tied to a named regulatory requirement — same honest framing
  as every other Insider Risk Management scenario in this library.
- **Open questions are surfaced as open, not resolved by optimistic assumption** — the "third HR
  connector required" question and the "does the cloud-indicator category actually apply to this
  template" question (§6, `design.md` §2 goal 5/6) are both exactly the kind of unresolved detail a
  CISO would want flagged before committing this template to a customer-facing assessment.
- **Would I fund this?** Yes — particularly for a tenant that wants risky-user-triggered detection
  without a Defender for Endpoint prerequisite, or as a complement to the sibling template for a
  population where both endpoint-violation and exfiltration-activity coverage matter — **conditioned
  on the same HR/Legal sign-off as the sibling**, and on documenting which population maps to which
  template (or both, deliberately) per the new §11 guidance.

No remaining Fix/Fail after resolution.

---

## 🟦 Microsoft Product Owner

**Verdict: Pass**

1. **Template description, prerequisites table, indicator categories, and the 7,500-user cap are
   all directly grounded via the Microsoft Learn MCP tool's live search/fetch of
   `insider-risk-management-policy-templates`, `communication-compliance-policies`,
   `insider-risk-management-policies` (cumulative exfiltration detection section),
   `insider-risk-management-configure` (cloud apps section), and `insider-risk-management-limits`**
   — direct-fetch grounding, not analogy to the sibling scenario alone.
2. **The claim that Communication Compliance content and generative-AI indicators ARE selectable
   SCORING indicators for this template (unlike its Security-policy-violations-by-risky-users
   cousin) is sourced directly from Microsoft's own "Select Insider Risk Management policy
   indicators for data-based policy templates" and "Select generative AI policy indicators for
   policy templates" sections, which name this template explicitly in both lists.** Correctly
   distinguishes the two roles Communication Compliance plays in this one policy (trigger vs.
   scoring indicator) rather than treating the CC integration as a single monolithic option.
3. **The cloud-indicator applicability question is disclosed as an open VERIFY, not asserted either
   way.** Microsoft's per-template description text names "cloud indicators" explicitly for `Data
   theft by departing users` and the base `Data leaks` template but not, in the same descriptive
   paragraph, for `Data leaks by risky users` — while the general cloud-apps configuration article
   doesn't restrict by template. This build searched for a definitive statement either way and
   found none; disclosing the gap (§5 Step 6, §6, §11, `design.md` §2 goal 5) rather than assuming
   inclusion or exclusion is the correct call per `AGENTS.md` §4.
4. **No fabricated Communication Compliance or Insider Risk Management authoring API.** Consistent
   with every other scenario in this library and this product family, this build found and
   restated Microsoft's own explicit statement that PowerShell isn't supported for Communication
   Compliance policy management, and IRM policy authoring itself remains portal-only.
5. **The decision to reuse `Send-HrRiskIndicatorRecord.ps1` and
   `Export-InsiderRiskAlerts.ps1` unmodified, rather than fork either, is correctly justified by a
   genuine technical match (identical HR schema; no Defender for Endpoint signal to join against)
   — not reuse for its own sake.** `design.md` §2 goals 1 and 3 state the specific reasoning for
   each reuse decision independently rather than treating "reuse where possible" as a blanket rule.
6. **The template/cap/indicator distinctions from the `Security policy violations by risky users`
   cousin are stated precisely** — same trigger mechanism and numerically identical cap, but a
   fundamentally different indicator family and no Defender for Endpoint dependency. `design.md` §3
   presents this as a structured comparison table rather than a prose aside, reducing the risk of a
   reader conflating the two templates' actual capabilities.

No Fix/Fail items from this lens.

---

## Summary

| Lens | Initial verdict | Findings | Resolution |
|---|---|---|---|
| 🔴 Red Team | Fix | 3 (2 closed with new README §11 bullets, 1 confirmed already covered by existing cross-references) | Closed |
| 🔵 Blue Team | Fix | 3 (1 closed with README §8/§11 additions plus a new validate-script checklist item, 2 confirmed already correctly scoped) | Closed |
| 🎩 CISO | Fix | 2 (1 closed with a new README §11 bullet on template-overlap cost/complexity, 1 confirmed already correctly handled) | Closed |
| 🟦 Microsoft Product Owner | Pass | — | — |

The Blue Team finding — a real operator-error risk now that three near-identical HR-connector
upload invocations exist across this library's "risky users" scenarios — was the most operationally
actionable finding of this round, closed with both a documentation fix and a new automated-checklist
item rather than a documentation-only fix. The Red Team findings extended this scenario's disclosed
evasion-vector list (channel coverage, cumulative-exfiltration baseline gaming) beyond what the
sibling scenario's own review already established, rather than re-litigating the sibling's findings.
The CISO finding — cost/complexity guidance for tenants considering both "risky users" templates —
gives a concrete answer instead of leaving template selection as an unstated judgment call. No Fail
items were raised. This fragment meets the definition of done in `AGENTS.md` §9.
