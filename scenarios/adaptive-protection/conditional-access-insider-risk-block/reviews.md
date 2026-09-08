# Four-Lens Review — Adaptive Protection: Conditional Access Insider Risk Block

Reviewed after the initial draft of `README.md`, `design.md`, `deploy/`, and `validate/`. One
round of findings below; all **Fix** items were applied to the scenario before this file was
finalized (see "Resolution" under each). No **Fail** items were raised.

---

## 🔴 Red Team

**Verdict: Fix (resolved)**

1. **An already-issued sign-in session is not necessarily killed the instant a user is flagged
   Elevated-risk.** The original draft implied this policy stops access "the moment" a risk level
   changes, without qualifying that Conditional Access evaluates at sign-in. For an application or
   tenant without Continuous Access Evaluation (CAE) enabled, a token issued before the risk-level
   change remains valid until it naturally expires — commonly up to an hour. A sophisticated
   insider who is mid-session when flagged retains access for that window, a real, exploitable
   timing gap this scenario's block control does not close on its own.
   - **Resolution:** Added an explicit bullet to `README.md` §11 naming CAE, the typical token
     lifetime, and that this is a disclosed bypass window, not a flaw unique to this policy.
2. **Legacy authentication clients are a documented Conditional Access blind spot this scenario
   doesn't address.** The original draft never mentioned legacy auth at all. A buyer who hasn't
   already deployed a separate "block legacy authentication" policy could reasonably assume this
   scenario's Insider Risk condition covers every sign-in path, when POP/IMAP/older non-modern-auth
   clients have long-standing gaps with several Conditional Access condition types.
   - **Resolution:** Added a `README.md` §11 bullet stating this plainly and naming the standard
     mitigating pattern (a separate legacy-auth-block policy), rather than silently assuming the
     buyer already has one.
3. **A patient attacker can wait out the same risk-level reset window the DLP sibling's own Red
   Team review already flagged.** Not a new finding specific to this scenario — the 7-day insider
   risk level timeframe and case-dismissal reset behavior are properties of Adaptive Protection
   itself, already reviewed in `dynamic-risk-dlp-enforcement/reviews.md` (Red Team finding 3) and
   the feeder IRM policy's own sequence/cumulative detection is the layer designed to catch this.
   No change needed in this scenario specifically.

No remaining Fix/Fail after resolution.

---

## 🔵 Blue Team

**Verdict: Fix (resolved), otherwise Pass**

1. **This policy's own Conditional Access change-propagation delay was not distinguished from
   Adaptive Protection's 36-hour risk-level delay.** The original draft's §11 only carried the
   36-hour figure inherited from the DLP sibling. An on-call analyst troubleshooting "why didn't a
   test sign-in get blocked five minutes after I deployed the policy" could easily (and
   incorrectly) conclude the whole control is broken, when it's simply mid-propagation on a much
   shorter timescale than the risk-level delay.
   - **Resolution:** Added a `README.md` §11 bullet stating both delays exist, are different, and
     giving the shorter policy-propagation figure (~15–30 minutes) distinctly from the 36-hour
     Adaptive Protection figure — mirroring the DLP sibling's own "two independent propagation
     delays" clarification (`dynamic-risk-dlp-enforcement/reviews.md`, Blue Team finding 3).
2. **No dedicated alert/export script for this policy's block events, unlike a SIEM-integrated
   detection.** Checked against this library's established precedent: neither the DLP sibling nor
   `pci-teams-exfil-block` ships a dedicated alert-export script either — both rely on native
   dashboards (DLP Alerts / Defender portal) plus `docs/automation-surface.md`'s general
   SIEM-integration guidance. This scenario's reliance on Entra sign-in logs / Conditional Access
   Insights and reporting is the direct Conditional-Access-side equivalent, consistent with — not
   a new gap versus — that precedent. No change needed.
3. **Manual correlation between a block event and the triggering IRM alert** is called out
   explicitly in `README.md` §8 step 2, matching the DLP sibling's own already-reviewed runbook
   language. Confirmed present and consistent; no change needed.

No Fail items. Detection-to-response latency (once the two propagation delays above are
correctly understood) and the runbook meet the bar for an operable control.

---

## 🎩 CISO

**Verdict: Pass (with one Fix)**

1. **The business-continuity impact of this control is qualitatively larger than the DLP
   sibling's, and the original draft's operations guidance didn't say so distinctly enough.** A
   blocked DLP share may go unnoticed by the user for a while; a blocked sign-in triggers an
   immediate help-desk call. The first draft's §8 reused the DLP sibling's HR/Legal coordination
   language nearly verbatim without adding the service-desk dimension this control specifically
   needs.
   - **Resolution:** Rewrote `README.md` §8's closing paragraph to name the sign-in-block-specific
     business-continuity distinction and add service-desk runbook readiness as an explicit
     rollout prerequisite alongside HR/Legal coordination.
- **Risk reduction vs. cost:** the new Entra ID P2 requirement (§10) is a genuine incremental cost
  most buyers deploying only the DLP sibling won't already carry — this is disclosed plainly
  rather than folded into "no incremental cost," and the sizing note explicitly warns that P2
  coverage must extend to the entire population in this policy's `Users` scope, not just IT/
  security staff, to avoid a licensing-compliance gap discovered only after deployment.
- **Board-level narrative:** "we can automatically cut off Microsoft 365 access entirely for the
  specific users our insider risk program has flagged as Elevated, with a documented, reversible
  rollback path" is a strong narrative for a board already briefed on the DLP sibling's narrower
  version — best pitched as the escalation lever for confirmed cases, not the first response, per
  the pilot/maturity gate in §5 Step 7 and §8.
- **Would I fund this?** Yes, for a buyer who already has (or is deploying) both a tuned feeder
  IRM policy and this library's DLP sibling, has budgeted for Entra ID P2 across the relevant
  population, and has read and accepted the service-desk/HR/Legal coordination note. Not as an
  organization's first Purview investment, and not before the DLP sibling has proven out the
  detection-to-enforcement pattern at a smaller blast radius.

---

## 🟦 Microsoft Product Owner

**Verdict: Pass (with one Fix)**

1. **`conditions.insiderRiskLevels` is independently confirmed as a current, non-beta Graph v1.0
   property** — checked directly against the `conditionalAccessConditionSet` resource reference,
   which lists it with the exact four enum values this script uses (`minor`/`moderate`/`elevated`/
   `unknownFutureValue`). Not fabricated, not assumed by analogy to the DLP sibling's differently-
   shaped `-SharedByIRMUserRisk` parameter on a different object type.
2. **The original draft's Non-goals section did not flag that the DLP sibling's own `design.md`
   §7 statement — "a Microsoft-labeled preview integration as of this writing" for Conditional
   Access — is now out of date.** This build's fresh grounding pass found no preview label on
   either the current portal procedure doc or the Graph v1.0 resource property, and independent
   reporting places GA at June 2024. Leaving the DLP sibling's stale claim uncorrected anywhere in
   this new scenario's own docs would let a reader stumble on the contradiction unexplained.
   - **Resolution:** Added `design.md` §8, "Correction to the DLP sibling scenario's stated
     non-goal," documenting the finding and noting the `PROGRESS.md` follow-up to backport the
     correction into the DLP sibling's own files (not done in this fragment, per `AGENTS.md` §6
     one-fragment-per-turn discipline).
3. **The exact permission set for creating/updating a Conditional Access policy
   (`Policy.ReadWrite.ConditionalAccess` + `Policy.Read.All`, least-privileged) is independently
   confirmed** against the `conditionalaccesspolicy-update` permissions reference, not assumed by
   analogy to a differently-scoped Graph permission elsewhere in this library.
4. **Policy naming does not overclaim collision-avoidance with Microsoft's Quick Setup wizard.**
   Unlike the DLP sibling (which independently confirmed its own collision-avoidance claim), this
   build could not confirm Microsoft Quick Setup's exact auto-generated Conditional Access policy
   name — checked and confirmed the README/design docs state this as an open VERIFY rather than
   asserting a name that wasn't independently checked.
5. **Licensing citation accuracy** — the new Entra ID P2 requirement is scoped correctly as
   "required for the Conditional Access Insider Risk *condition* specifically," distinct from the
   already-documented, broader "P1/P2 for administrative units" prerequisite in
   `docs/licensing-matrix.md` §4 — checked to confirm this scenario doesn't conflate the two or
   imply a buyer already covered for administrative-unit P1 automatically satisfies this
   scenario's P2-specific requirement (P1 does not).

No remaining Fix/Fail after resolution.

---

## Summary

| Lens | Initial verdict | Findings | Resolution |
|---|---|---|---|
| 🔴 Red Team | Fix | 3 (2 closed with documentation additions, 1 confirmed already correctly mitigated by the feeder IRM policy's own detection design, per the DLP sibling's precedent) | Closed |
| 🔵 Blue Team | Fix | 3 (1 closed with a propagation-delay clarification, 2 confirmed consistent with existing library precedent) | Closed |
| 🎩 CISO | Pass (1 Fix) | 1 closed with an operations-guidance rewrite; overall verdict Pass | Closed |
| 🟦 Microsoft Product Owner | Pass (1 Fix) | 5 (1 closed by adding a correction section for the DLP sibling's stale preview claim, 4 confirmed correct/well-grounded) | Closed |

All Fix items from this round are resolved in the current state of `README.md`, `design.md`,
`deploy/New-InsiderRiskConditionalAccessPolicy.ps1`, and
`deploy/Remove-InsiderRiskConditionalAccessPolicy.ps1`. No Fail items were raised. This fragment
meets the definition of done in `AGENTS.md` §9.
