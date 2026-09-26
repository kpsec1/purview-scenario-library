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
   doesn't address.** The original draft never mentioned legacy auth at all. An organization that hasn't
   already deployed a separate "block legacy authentication" policy could reasonably assume this
   scenario's Insider Risk condition covers every sign-in path, when POP/IMAP/older non-modern-auth
   clients have long-standing gaps with several Conditional Access condition types.
   - **Resolution:** Added a `README.md` §11 bullet stating this plainly and naming the standard
     mitigating pattern (a separate legacy-auth-block policy), rather than silently assuming the
     organization already has one.
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
  most organizations deploying only the DLP sibling won't already carry — this is disclosed plainly
  rather than folded into "no incremental cost," and the sizing note explicitly warns that P2
  coverage must extend to the entire population in this policy's `Users` scope, not just IT/
  security staff, to avoid a licensing-compliance gap discovered only after deployment.
- **Board-level narrative:** "we can automatically cut off Microsoft 365 access entirely for the
  specific users our insider risk program has flagged as Elevated, with a documented, reversible
  rollback path" is a strong narrative for a board already briefed on the DLP sibling's narrower
  version — best pitched as the escalation lever for confirmed cases, not the first response, per
  the pilot/maturity gate in §5 Step 7 and §8.
- **Would I fund this?** Yes, for an organization that already has (or is deploying) both a tuned feeder
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
   imply an organization already covered for administrative-unit P1 automatically satisfies this
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

---

## Round 2 — scripting the `excludeGuestsOrExternalUsers` nested condition (PROGRESS.md follow-up)

Reviewed after adding `-ExcludeGuestOrExternalUserTypes` to `deploy/
New-InsiderRiskConditionalAccessPolicy.ps1` (and the matching validation check), closing the
follow-up Round 1's Non-goals (§7) and `README.md` §11 originally deferred. One round of findings
below; all **Fix** items were applied before this file was finalized. No **Fail** items were
raised.

### 🔴 Red Team

**Verdict: Fix (resolved)**

1. **A default that silently narrows coverage is worse than no default.** The original draft of
   this change set `-ExcludeGuestOrExternalUserTypes`'s default without stating plainly, in the
   same place a reader would look, that these three categories are *excluded from the block* —
   i.e., a B2B direct-connect user, service-provider user, or "other external" user who is
   assigned Elevated insider risk is **not** blocked by this policy by default, even though the
   Insider Risk Management side may still flag them. An organization skimming only the parameter name
   could misread "Exclude" as "these get extra scrutiny" rather than "these are exempted."
   - **Resolution:** `deploy/New-InsiderRiskConditionalAccessPolicy.ps1`'s `.PARAMETER
     ExcludeGuestOrExternalUserTypes` block and `README.md` §11 both state the exemption directly
     and name the escape hatch (`-ExcludeGuestOrExternalUserTypes @()`) for an organization that wants no
     guest/external carve-out at all — not just that the parameter exists.
2. **The unconfirmed wire-format assumption (comma, no space) is a real, if narrow, correctness
   risk for the *matching* control itself.** If Microsoft's actual serialization differs (e.g.
   requires no whitespace variations, a different delimiter, or a specific member ordering) and
   this script's idempotency check consequently never reports a match, `-Force` reconciliation
   would PATCH the identical desired state on every run — harmless to the policy's actual
   enforcement (the block condition itself would still evaluate correctly against Graph's side,
   since Graph parses whatever it stores), but a false "drift" signal an operator could waste time
   chasing.
   - **Resolution:** Confirmed the risk is cosmetic to *this script's own drift reporting*, not to
     the deployed policy's actual behavior (Graph is the source of truth for how the condition
     evaluates, not this script's local string comparison) — stated explicitly in the deploy
     script's `.NOTES` and `README.md` §11 rather than left implicit.

No remaining Fix/Fail after resolution.

### 🔵 Blue Team

**Verdict: Pass**

1. **The new automated check follows this scenario's own established two-part pattern** (automated
   Graph-object check + manual checklist for what can't be queried) — no new manual-checklist item
   was needed, since `excludeGuestsOrExternalUsers` is fully queryable via the same
   `Get-MgIdentityConditionalAccessPolicy` call the rest of the script already uses. Confirmed
   consistent, no gap.
2. **A WARN, not a FAIL, when the exclusion is empty** — `validate/
   Test-InsiderRiskConditionalAccessPolicy.ps1` treats `-ExpectedExcludeGuestOrExternalUserTypes
   @()` as a WARN (not a silent PASS, not a hard FAIL) precisely because an intentionally-empty
   exclusion is a valid organization choice (§7 in `design.md`) but one worth surfacing to an operator
   reviewing validation output, not burying. Checked and confirmed appropriate — matches this
   library's existing severity convention for "correctly configured but worth a second look."

No Fail items.

### 🎩 CISO

**Verdict: Pass**

- **No new licensing, cost, or business-continuity dimension.** This change adds a narrower
  *exclusion* to an already-reviewed block control — it does not expand what the policy blocks,
  change its licensing prerequisite (still Entra ID P2, §10), or alter the service-desk/HR/Legal
  rollout coordination Round 1 already established. No update needed to `README.md` §8 or §10.
- **Risk framing:** narrowing the block's population (by exempting three external-user categories
  Microsoft itself recommends exempting) is a *risk-reducing* change from a lockout/business-
  continuity standpoint, at the cost of a correspondingly narrower insider-risk enforcement
  surface for those specific external-user categories — an explicit, disclosed trade-off
  (`design.md` §7), not a silent one. Would sign off on this as a low-risk refinement to an
  already-funded control, not a decision requiring separate re-approval.

### 🟦 Microsoft Product Owner

**Verdict: Pass**

1. **`conditions.users.excludeGuestsOrExternalUsers.guestOrExternalUserTypes` and its seven
   real enum members are independently confirmed** on the `conditionalAccessUsers`,
   `conditionalAccessGuestsOrExternalUsers`, and enum Microsoft Learn resource references — not
   fabricated, not inferred by analogy to a differently-shaped property elsewhere in this library.
2. **The default value set reproduces Microsoft's own documented procedure exactly** — the
   `policy-risk-based-insider-block` guide's Users step names precisely `b2bDirectConnectUser`
   (B2B direct connect users), `serviceProvider` (Service provider users), and `otherExternalUser`
   (Other external users) as the categories to exclude; this build's default matches that list
   member-for-member, not a superset or subset chosen by inference.
3. **The one thing NOT scripted (`externalTenants`) is correctly scoped as a non-goal, not a
   silent gap** — Microsoft's own guide does not scope this exclusion by external tenant, so
   omitting that sibling property matches the guide's own reference configuration rather than
   under-delivering against it. Checked and confirmed this distinction is stated plainly in
   `design.md` §7, not conflated with the genuinely-unconfirmed wire-format detail.
4. **The one remaining VERIFY (multi-value separator format) is narrowly scoped and honestly
   labeled** — it affects only this script's own local idempotency/drift detection, not the
   correctness of the deployed Conditional Access policy itself (confirmed in the Red Team
   resolution above). Not overstated as a functional risk it isn't.

No remaining Fix/Fail after resolution.

### Round 2 summary

| Lens | Initial verdict | Findings | Resolution |
|---|---|---|---|
| 🔴 Red Team | Fix | 2 (both closed with documentation clarifications; no code-behavior change needed) | Closed |
| 🔵 Blue Team | Pass | 2 (both confirmed consistent with existing library conventions) | Closed |
| 🎩 CISO | Pass | 0 (confirmed no new cost/licensing/business-continuity dimension) | N/A |
| 🟦 Microsoft Product Owner | Pass | 4 (all confirmed correct/well-grounded) | Closed |

All Fix items from Round 2 are resolved in the current state of `README.md`, `design.md`,
`deploy/New-InsiderRiskConditionalAccessPolicy.ps1`, and `validate/
Test-InsiderRiskConditionalAccessPolicy.ps1`. No Fail items were raised. This follow-up fragment
meets the definition of done in `AGENTS.md` §9.
