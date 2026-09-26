# Four-Lens Review - Adaptive Protection: Block Legacy Authentication

Reviewed after the initial draft of `README.md`, `design.md`, `deploy/`, and `validate/`. One
round of findings below; all **Fix** items were applied to the scenario before this file was
finalized (see "Resolution" under each). No **Fail** items were raised.

---

## 🔴 Red Team

**Verdict: Fix (resolved)**

1. **Conditional Access is a post-authentication control - the original draft didn't say so.** An
   early draft of this scenario presented the block as if it stopped an attacker's authentication
   attempt outright. Microsoft's own community guidance confirms Conditional Access is evaluated
   only *after* first-factor authentication succeeds - a credential-stuffing or password-spray
   attempt against a legacy-auth endpoint still confirms whether the guessed credentials were
   valid before this policy's grant control ever fires. This scenario stops the resulting
   *session*, not the *authentication attempt*.
   - **Resolution:** Added `design.md` §8 (dedicated section, not a footnote) and a `README.md`
     §11 bullet naming this plainly, with the Microsoft Q&A citation, plus a Non-goals entry
     pointing at Exchange-side authentication policies as the earlier-in-the-flow alternative this
     scenario does not script.
2. **Detect-and-stop against a Microsoft-managed policy has a time-of-check/time-of-use gap.**
   The deploy script only checks for a Microsoft-managed policy at the moment it's run. If an
   admin later disables that Microsoft-managed policy (accidentally, or as a result of a
   compromised Conditional Access Administrator account) and no custom policy was ever deployed
   because the check found one present at an earlier point in time, the tenant is left with **no**
   legacy-auth control at all and no automated signal that this happened.
   - **Resolution:** `README.md` §8 already recommended a quarterly re-check; this review adds an
     explicit call-out in the same section to re-run `validate/Test-BlockLegacyAuthenticationPolicy.ps1`
     on that cadence specifically because the deploy-time check is a point-in-time snapshot, not a
     standing guarantee. This is also why the validate script (Blue Team finding 1) now fails hard
     when the only policy present is disabled, rather than passing quietly.
3. **Service principal / workload identity sign-ins are never subject to this policy.** A
   documented, general Conditional Access limitation (user-scoped policies don't apply to service
   principal sign-ins) - not something this scenario can close; Conditional Access for workload
   identities is a separate, unscripted surface.
   - **Resolution:** Already stated as a Non-goal in the initial draft (`design.md` §7); confirmed
     accurate and left as-is - no fix needed beyond keeping the disclosure.

No remaining Fix/Fail after resolution.

---

## 🔵 Blue Team

**Verdict: Fix (resolved)**

1. **A disabled Microsoft-managed policy was under-signaled as WARN, not FAIL, in the original
   validate script draft.** The first draft treated any found Microsoft-managed policy - enabled,
   Report-only, or disabled - as "found, so not a hard failure," differentiating only with
   WARN/PASS. A tenant whose Microsoft-managed policy has been switched to **disabled** (opted
   out) with no custom policy deployed has **zero** legacy-auth coverage, which is operationally
   identical to "nothing found at all" - the original draft's final aggregate check
   (`if (-not $managed -and -not $policy)`) missed this because a disabled policy still counts as
   "$managed" being truthy.
   - **Resolution:** Rewrote the script's state handling: a disabled Microsoft-managed policy is
     now its own `FAIL`, and a new `$managedActive`/`$policyActive` pair (true only for `enabled`
     or `enabledForReportingButNotEnforced`) drives the final aggregate check, which now correctly
     fails when every policy object found is disabled - not just when none exist at all. See the
     current `validate/Test-BlockLegacyAuthenticationPolicy.ps1`.
2. **No dedicated alert/export script for this policy's block events.** Checked against this
   library's established precedent: neither `conditional-access-insider-risk-block` nor
   `conditional-access-insider-risk-step-up-auth` ships one either - both rely on native Entra
   sign-in logs / Conditional Access Insights and reporting, which this scenario also documents
   (`README.md` §8). Consistent with, not a new gap versus, that precedent. No change needed.
3. **The manual checklist didn't originally ask which control is the tenant's actual source of
   truth** when a Microsoft-managed policy, a custom policy, and Security defaults could
   theoretically all exist in some combination - a real signal-to-noise risk during an incident if
   an on-call analyst doesn't know which policy name to look for first.
   - **Resolution:** Added a dedicated checklist line in `validate/Test-BlockLegacyAuthenticationPolicy.ps1`'s
     manual checklist output asking exactly this.

No Fail items remain. Detection-to-response latency and the runbook (`README.md` §8) meet the bar
for an operable control once finding 1's fix is in place.

---

## 🎩 CISO

**Verdict: Pass (with one Fix)**

1. **The original draft's cost section didn't distinguish "this control is likely already free"
   from "this control needs new spend" clearly enough**, which risks an oversell: pitching this
   scenario to a P2/Business Premium organization as a net-new capability when Microsoft may have already
   deployed the equivalent for free.
   - **Resolution:** Rewrote `README.md` §10 to lead with the "likely already free for a P2/
     Business Premium tenant" case before the P1-only incremental-cost case, and added the
     Microsoft-managed-policy check as the first thing §10 points back to.
- **Risk reduction vs. cost:** among the highest risk-reduction-per-dollar controls in this
  library - Microsoft's own attack-statistics citation (97%/99% of two major attack classes use
  legacy auth) is a strong, specific number for a board narrative, and the licensing floor (P1,
  not P2) means most organizations already on Microsoft 365 E3 pay nothing incremental for it.
- **Board-level narrative:** "we block the authentication protocols responsible for the vast
  majority of credential-stuffing and password-spray compromises, at effectively no incremental
  license cost, and we've verified Microsoft hasn't already silently deployed (or is about to
  auto-enable) an equivalent policy without our review" is a clean, specific, low-controversy pitch
  - the kind of prerequisite hygiene a board expects to already be in place, not a hard sell.
- **Business-continuity coordination:** `README.md` §8's tuning guidance (multifunction devices,
  legacy SMTP relays) correctly flags the realistic source of break-glass-adjacent friction for
  this specific control - not sign-in lockouts of end users (most modern clients are unaffected),
  but infrastructure/integrations still wired for basic auth. Confirmed present and specific
  enough for a change-management conversation; no further change needed.
- **Would I fund this?** Yes, and with unusually little hesitation relative to the rest of this
  library - low cost, high-confidence attack-statistic justification, and (via the Microsoft-
  managed-policy check) no risk of paying to duplicate a control Microsoft already gives away.

---

## 🟦 Microsoft Product Owner

**Verdict: Pass**

1. **The core design decision - check for a Microsoft-managed equivalent before building a custom
   one - is correctly grounded, not assumed.** Verified directly against Microsoft's current
   "Microsoft-managed Conditional Access policies" reference: the auto-deployment behavior, the
   30-day auto-enable clock, the P2/Business Premium eligibility gate, and the "duplicate if you
   need more changes" guidance are all confirmed on that one page, not stitched together from
   inference. This is exactly the kind of "don't reinvent a native capability" check `AGENTS.md`
   §5 asks this lens to make, and it was built in from the first draft rather than added as a
   review fix.
2. **`clientAppTypes = ['exchangeActiveSync', 'other']` is independently confirmed as the correct,
   narrower scoping** - checked against both the conceptual "Conditions" documentation (which
   explicitly names these as the two legacy-authentication client-app categories, distinct from
   Browser/Mobile apps and desktop clients) and the `conditionalAccessConditionSet` Graph v1.0
   resource's own enum. Not fabricated, not assumed by analogy to a sibling scenario's differently-
   scoped condition.
3. **The Entra ID P1 (not P2) licensing floor is independently confirmed** against Microsoft's
   Conditional Access overview and licensing references, directly contradicting what a reader who
   only knew this library's other two Conditional-Access-based scenarios (both P2) might assume by
   pattern-matching. Correctly called out as a distinguishing fact in `README.md` §3/§10 and
   `docs/licensing-matrix.md` §9, not silently left for a reader to assume incorrectly.
4. **The Microsoft-managed-policy detection heuristic is honestly scoped as best-effort**, not
   oversold as a reliable API check - the v1.0 `conditionalAccessPolicy` resource reference was
   checked directly and confirmed to have no documented boolean flag for this; the displayName-
   prefix heuristic and its "not independently confirmed word-for-word" caveat are stated plainly
   in `README.md` §11 and the deploy script's own `.NOTES` rather than presented with false
   confidence.
5. **No deprecated or superseded API paths used.** `clientAppTypes`'s `.NOTES`-documented
   deprecation of `easUnsupported` in favor of `exchangeActiveSync` was checked and confirmed this
   scenario already uses the current, non-deprecated value.

No Fix/Fail raised.

---

## Summary

| Lens | Initial verdict | Findings | Resolution |
|---|---|---|---|
| 🔴 Red Team | Fix | 3 (2 closed with documentation/script additions, 1 confirmed already correctly disclosed) | Closed |
| 🔵 Blue Team | Fix | 3 (1 closed with a genuine validate-script logic correction, 2 confirmed consistent with existing library precedent or closed with a checklist addition) | Closed |
| 🎩 CISO | Pass (1 Fix) | 1 closed with a cost-section rewrite; overall verdict Pass | Closed |
| 🟦 Microsoft Product Owner | Pass | 5 confirmed correct/well-grounded, no fixes needed | Closed |

All Fix items from this round are resolved in the current state of `README.md`, `design.md`,
`deploy/New-BlockLegacyAuthenticationPolicy.ps1`, `deploy/Remove-BlockLegacyAuthenticationPolicy.ps1`,
and `validate/Test-BlockLegacyAuthenticationPolicy.ps1`. No Fail items were raised. This fragment
meets the definition of done in `AGENTS.md` §9.
