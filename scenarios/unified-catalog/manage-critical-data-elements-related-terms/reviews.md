# Four-Lens Review - Link a Critical Data Element to Related Glossary Terms

Reviewed after the initial draft of `README.md`, `design.md`, `deploy/`, and `validate/`. One
round of findings below; all **Fix** items were applied to the scenario before this file was
finalized (see "Resolution" under each). No **Fail** items were raised.

---

## 🔴 Red Team

**Verdict: Fix (resolved)**

1. **Unlinking a term is framed as metadata cleanup, but it can silently loosen a real access
   control.** `README.md` §2 documents that a policy set on a linked term (e.g. manager approval)
   aggregates onto every data product the critical data element's mapped columns touch. The
   initial draft of `deploy/Remove-CdeRelatedTerm.ps1` and `rollback.md` described unlinking only
   in terms of tidying up a relationship, with no warning that removing a policy-bearing term's
   link could reduce a downstream data product's effective access requirement - a real,
   security-relevant consequence dressed up as routine cleanup, and exactly the kind of change an
   operator running `-RemoveAll` in a hurry (e.g. to unblock a `-Purge`) could make without
   realizing its blast radius extends beyond the CDE itself.
   - **Resolution:** `deploy/Remove-CdeRelatedTerm.ps1` now prints an explicit `Write-Warning`
     before every unlink stating this consequence by name. `rollback.md` now opens with a
     dedicated "Caution: unlinking is not purely metadata cleanup" section making the same point
     and stating plainly that this build cannot confirm whether or when Microsoft's platform
     re-evaluates the aggregated policy view after an unlink - recommending the unlink be treated
     as a change-management event, not resolved by guessing at the platform's refresh timing.
2. **Silently-skipped term names give false confidence, the same class of finding
   `manage-critical-data-elements/reviews.md` Red Team finding 1 already raised for its own
   column resolution.** `Add-CdeRelatedTerm.ps1`'s per-term loop treats an unresolvable term name
   as `Write-Warning`-and-`continue`, and the script still exits 0.
   - **Resolution:** Confirmed intentional (one bad name in a multi-term array shouldn't abort the
     rest), and already covered by the same "run validate after every deploy" discipline the
     sibling scenario established - `README.md` §8 states this explicitly for this scenario too
     rather than leaving it to be inferred by analogy.
3. **The Data Steward-only role claim is asserted from documentation silence, not a confirmed
   minimum** (see Microsoft Product Owner finding 1, below, for the full analysis) - a Red-Team
   angle on the same gap: an operator who under-provisions the automation identity based on this
   scenario's initial claim could hit an unexplained 403 with no guidance to try Data Product Owner
   next.
   - **Resolution:** Covered by the Product Owner fix below; cross-referenced here to confirm the
     Red Team lens independently flagged the same risk rather than missing it.

No remaining Fix/Fail after resolution.

---

## 🔵 Blue Team

**Verdict: Fix (resolved)**

1. **No machine-parseable signal distinguishes "term skipped due to resolution failure" from
   "term already linked, nothing to do"** in the deploy script's console output - the same
   already-established pattern this repo's sibling scenarios address via their validate scripts'
   exit codes, not the deploy script itself.
   - **Resolution:** Confirmed `validate/Test-CdeRelatedTerms.ps1`'s non-zero exit on any hard
     failure is the CI-gateable signal, matching this repo's deploy-then-validate convention;
     `README.md` §8 states the "treat a deploy run as incomplete until validate confirms it"
     discipline explicitly for this scenario rather than only for its sibling.
2. **A term link removed outside this scenario's control (portal, or another automation) has no
   alerting story** - `validate/Test-CdeRelatedTerms.ps1`'s informational total-relationship-count
   check surfaces a mismatch only when someone runs it, with no history or trend.
   - **Resolution:** Confirmed intentional scope, the same "no documented Graph/REST query API for
     this class of change event" gap this repo's other Unified Catalog and IRM-adjacent follow-ups
     already record. A scheduled re-run of validate, diffed against a prior run's output, remains
     the only unattended detection mechanism - already implied by the existing operational
     guidance; no code change needed beyond what Red Team finding 1's warning already surfaces to
     an operator running the removal path specifically.

No remaining Fail. Both findings resolved by pointing to the existing deploy-then-validate pattern
and, for finding 2, the new Red Team warning covering the removal-side detection gap specifically.

---

## 🎩 CISO

**Verdict: Pass**

- **Genuinely low-cost, low-risk fragment - worth funding as a quick win, not a hard sell.** §10
  confirms zero incremental governed-asset cost (a relationship, not an asset), no new license
  tier, and no new REST surface to secure or monitor beyond what `manage-critical-data-elements`
  and `curate-business-glossary` already require. This is the kind of fast-follow a CISO can
  approve without a fresh risk-assessment cycle.
- **The access-policy-inheritance driver (§2) is a real, board-legible reason to do this, not
  filler** - turning a manual "remember to configure the same approval policy on every related
  data product" chore into "set the policy once on the term, let it aggregate" is a concrete
  operational-risk reduction (fewer places a policy can be forgotten), correctly caveated (§8) as
  something this scenario enables but cannot itself verify end-to-end.
- **Red Team finding 1's fix is exactly the kind of caution a CISO needs before this is handed to
  a junior operator for routine use** - unlinking a term is now documented as a
  change-management-worthy action, not a checkbox cleanup step, which is the right posture for
  anything that can loosen an access control even indirectly.
- **Preview-status caveat is already carried over correctly from the sibling scenarios** (§11) -
  no separate finding needed; confirmed present, not assumed.

No Fix/Fail. Funding recommendation: **yes**, no conditions beyond the two VERIFY items already
tracked (Microsoft Product Owner lens, below).

---

## 🟦 Microsoft Product Owner

**Verdict: Fix (resolved)**

1. **The "Data Steward alone is sufficient" role claim in the initial README draft was an
   unstated leap from documentation silence, not a confirmed fact.** Microsoft's
   critical-data-elements page states Data Steward **and** Data Product Owner are both required
   for CDE creation and column-adding, but simply doesn't repeat a role requirement when
   describing "Manage related terms" specifically. The initial draft read that silence as "Data
   Steward alone is enough for this one action" - a plausible but unconfirmed inference presented
   with more confidence than the source supports.
   - **Resolution:** `README.md` §3's prerequisite table and its own prose note now label this
     explicitly as an unconfirmed inference from documentation silence, with a fallback
     instruction (grant Data Product Owner too if a pilot-tenant run 403s) rather than stating the
     lesser requirement as settled fact. This is the same "don't fabricate certainty a source
     doesn't provide" standard `AGENTS.md` §4 requires, applied to a role-permission claim rather
     than a cmdlet name or REST shape.
2. **Correct, independently-confirmed choice of `entityType=TERM`** - this build's own fresh
   direct fetch of all three relationship reference pages (Create/List/Delete) found `TERM`
   formally documented with **no** competing example-only value in tension with it, unlike the
   sibling scenario's `DATACOLUMN`-vs-`CRITICALDATACOLUMN` finding. `design.md` §3 states this
   contrast explicitly rather than silently assuming the sibling's own caveat carries over
   unchanged.
3. **Correct, disclosed-not-guessed handling of the two-sided linking ambiguity** (`design.md`
   §4/§5) - rather than picking whichever of the two documented flows "sounded more official" or
   silently assuming both write to the same object, this build states both possible readings of
   the Draft-state discrepancy explicitly and defers to a pilot-tenant test, matching this repo's
   established no-guessing standard for a genuine documentation gap (the same treatment
   `manage-critical-data-elements/design.md` §6 gives its own `DATACOLUMN`-vs-`CRITICALDATACOLUMN`
   finding).
4. **Correct scope boundary: no access-policy configuration scripted.** Consistent with
   `manage-data-products/design.md` §5's own finding that no REST operation for this specific
   access-request-policy feature exists - this scenario doesn't attempt to script it either,
   confirmed independently rather than assumed to still hold without re-checking.

No remaining Fail after resolution.

---

## Summary

| Lens | Initial verdict | Findings | Resolution |
|---|---|---|---|
| 🔴 Red Team | Fix | 3 (unlink-loosens-access-policy risk now warned explicitly in code and rollback.md; silent-skip risk confirmed already covered by validate discipline; role-claim risk cross-referenced to the Product Owner fix) | Closed |
| 🔵 Blue Team | Fix | 2 (deploy-vs-validate signal confirmed to be validate's exit code; outside-this-scenario removal detection gap confirmed covered by the new unlink warning plus the existing validate-as-monitoring pattern) | Closed |
| 🎩 CISO | Pass | 0 (low-cost, well-caveated fragment; funding recommendation yes with no new conditions) | N/A |
| 🟦 Microsoft Product Owner | Fix | 4 (Data-Steward-sufficiency claim corrected from asserted fact to disclosed inference; TERM enum choice independently confirmed clean; two-sided linking ambiguity confirmed handled by disclosure, not guessing; access-policy-configuration scope boundary confirmed correct) | Closed |

All Fix items from this round are resolved in the current state of `README.md`, `design.md`,
`deploy/Add-CdeRelatedTerm.ps1`, `deploy/Remove-CdeRelatedTerm.ps1`, `rollback.md`, and
`validate/Test-CdeRelatedTerms.ps1`. No Fail items were raised. This fragment meets the definition
of done in `AGENTS.md` §9.

---

## Addendum (2026-09-27)

The sibling scenario's `entityType=DATACOLUMN`-vs-`CRITICALDATACOLUMN` question, referenced above
as context for why `TERM` carries no analogous ambiguity, is now resolved -
`CRITICALDATACOLUMN` is the confirmed value (see `manage-critical-data-elements/reviews.md`
addendum). This scenario's own findings and `TERM` choice are unaffected; cross-references to the
sibling's value were updated for consistency.
