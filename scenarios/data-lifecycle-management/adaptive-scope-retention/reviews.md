# Four-Lens Review — Adaptive-Scope Retention

Reviewed after the initial draft of `README.md`, `design.md`, `deploy/`, and `validate/`. One round
of findings below; all **Fix** items were applied (to `README.md` and this file) before this file
was finalized. No **Fail** items were raised.

---

## 🔴 Red Team

**Verdict: Fix (resolved)**

1. **Stale or over-broad `Title` query silently under- or over-covers the population.** Unlike a
   static distribution list that visibly needs updating, a stale adaptive-scope query fails quietly
   — nothing breaks, the wrong people are (or aren't) retained.
   - **Resolution:** `README.md` §8 calls out periodic `Title` review as a tuning task and
     specifically frames query drift as "the adaptive-scope equivalent of the distribution list
     going stale, just quieter." §11 repeats the caution against widening the query without
     validation.
2. **Whoever can edit the `Title` attribute controls who's in scope.** Because membership is purely
   attribute-driven and re-evaluated daily, a user with self-service profile-edit rights (or an
   admin, or a loosely-owned HR sync) could remove themselves from the retained population just
   before a sensitive period and restore it after — the adaptive-scope equivalent of quietly
   dropping off a distribution list, but self-service and less visible.
   - **Resolution:** `README.md` §11 names this bypass explicitly and recommends sourcing `Title`
     from an authoritative HR feed rather than self-service edit; §8 adds a concrete detection
     signal (`SetAdaptiveScope`/`ApplicableAdaptiveScopeChange` audit monitoring, §14 reference).
     The scenario doesn't claim to prevent this — only to make it detectable, which is honest given
     the object model has no built-in defense against attribute tampering.
3. **The disclosed location-scope gap (design.md §4) could go the wrong way for a defender.** If
   the undocumented behavior turns out to *under*-cover (e.g. Teams chats aren't actually included
   for a `User`-type scope despite the documented attribute table), that's an unmonitored egress
   path an attacker could rely on without the defender knowing.
   - **Resolution:** Rather than assert an answer either way, `README.md` §11 and `design.md` §4
     flag this as `VERIFY (pilot tenant)` and explicitly warn not to assume "Exchange + OneDrive
     only" in a customer deployment — the safe posture is to verify actual coverage, not guess
     narrower or broader than what's documented.

No remaining Fix/Fail after resolution.

---

## 🔵 Blue Team

**Verdict: Fix (resolved)**

1. **No detection signal for scope or policy tampering.** The initial draft had no operational
   monitoring guidance beyond "review the query periodically."
   - **Resolution:** `README.md` §8 now cites the specific, documented audit operations
     (`NewAdaptiveScope`/`SetAdaptiveScope`/`RemoveAdaptiveScope`/`ApplicableAdaptiveScopeChange`
     and the matching `*RetentionCompliancePolicy`/`*RetentionComplianceRule` operations) and a
     concrete `Search-UnifiedAuditLog -Operations` starting point, grounded against Microsoft's
     "Audit log activities" reference (§14) rather than invented.
2. **Membership visibility during the up-to-5-day population window.** An operator deploying this
   and immediately checking membership would see an empty or partial scope and might (wrongly)
   conclude the deploy failed.
   - **Resolution:** The deploy script, validate script, and `README.md` §4/§7/§8/§11 all
     independently call out the 5-day population delay and the separate policy-distribution delay,
     so "just deployed" isn't mistaken for "already enforced."
3. **Operability of validation.** Needed a fast, safe pre-flight plus a way to sanity-check actual
   coverage without waiting on the portal.
   - **Resolution:** `validate/Test-AdaptiveScopeRetention.ps1` read-only-checks scope/policy/rule
     existence and settings (exits non-zero for CI), and adds a non-failing
     `Get-AdaptiveScopeMembers` sample so an operator can see real membership without a portal
     round-trip. Its result-metadata property names aren't documented, so the script prints them
     generically (`Format-List`) instead of guessing a property name — disclosed in `README.md`
     §11 rather than silently risking a runtime property-not-found error.

No remaining Fail.

---

## 🎩 CISO

**Verdict: Fix (resolved)**

1. **Conflation risk: governance retention vs. litigation hold.** An early read of the scenario
   could be mistaken for "this is how we handle litigation" — it isn't; it's a standing governance
   baseline.
   - **Resolution:** `README.md` §11 adds an explicit distinction: this is a governance baseline,
     not a matter-scoped hold, and points to the `scenarios/ediscovery/` family for actual legal
     holds. Avoids a CISO over-representing this control's coverage to the board or to counsel.
2. **Risk vs. cost.** The control itself is cheap relative to the E5 entitlement most Purview
   customers already carry for other reasons; the real cost is the discipline to keep the `Title`
   query accurate — honestly stated in §10 rather than glossed as "set and forget."
3. **Board/governance-committee narrative:** "executive communications are retained for litigation-
   readiness automatically as the org chart changes, with no distribution list to fall out of
   date, and with an audit trail if anyone edits who's covered." A materially stronger narrative
   than a static list precisely because it names its own known weakness (attribute tampering) and
   the mitigation, rather than presenting adaptive scopes as maintenance-free security theater.
4. **Change management.** Scope query and retention settings are both config-file-driven and
   create-or-report — consistent with this repo's established retention-object discipline.
5. **Would I fund this?** Yes — it removes a real, recurring operational failure mode (stale
   distribution lists) at E5 entitlement cost the org likely already has, with an honest accounting
   of what it does and doesn't defend against.

No remaining Fix/Fail after resolution.

---

## 🟦 Microsoft Product Owner

**Verdict: Fix (resolved)**

1. **Correct, current cmdlets.** `New-AdaptiveScope` (`-LocationType`/`-FilterConditions`/
   `-RawQuery`/`-AdministrativeUnit`), `New-RetentionCompliancePolicy -AdaptiveScopeLocation`, and
   `New-RetentionComplianceRule` (`-RetentionDuration`/`-RetentionComplianceAction`/
   `-ExpirationDateOption`) are reproduced from their references, not invented.
2. **The parameter-surface gap disclosure is exactly what this lens exists to catch.** The initial
   draft could have silently assumed the portal's per-policy location-selection step has a
   PowerShell equivalent; it doesn't, as far as this build's grounding pass could confirm. Flagging
   it as `VERIFY (pilot tenant)` rather than fabricating an `-ExchangeLocation` parameter that
   doesn't exist in this parameter set is the correct call — a fabricated parameter would fail at
   runtime and erode trust in every other cmdlet in this script.
   - **Resolution:** already reflected in `README.md` §11 and `design.md` §4 at initial draft;
     this lens confirms no further correction is needed.
3. **Right feature for the driver.** Adaptive scope (attribute-driven, no group to maintain) is the
   product-recommended answer for exactly the population-changes-over-time problem this scenario
   states, and matches Microsoft's own worked example (executives, `Title` attribute) rather than
   inventing a scenario Microsoft doesn't itself illustrate.
4. **Accurate licensing.** E5 (or IP&G add-on) for adaptive scopes specifically, cited from this
   repo's own `docs/licensing-matrix.md` (which itself distinguishes basic E3 Data Lifecycle
   Management from the E5-gated adaptive-scope capability) rather than assuming the E3 baseline
   that covers the *static*-scope sibling scenario.
5. **Not reinventing native capability.** Uses the native `New-AdaptiveScope`/
   `New-RetentionCompliancePolicy`/`New-RetentionComplianceRule` object model end to end; doesn't
   attempt to simulate adaptive membership with a scheduled script against a static list, which
   would defeat the entire point of the scenario.

No remaining Fail after resolution.

---

## Summary

| Lens | Initial verdict | Findings | Resolution |
|---|---|---|---|
| 🔴 Red Team | Fix | 3 (query drift; attribute-tampering bypass; location-scope-gap direction) | Closed |
| 🔵 Blue Team | Fix | 3 (audit-operation monitoring; population-delay confusion; validate operability) | Closed |
| 🎩 CISO | Fix | 1 (governance-vs-hold conflation); Pass on cost/narrative/change-management | Closed |
| 🟦 Microsoft Product Owner | Fix | 1 (confirming the disclosed parameter-surface gap was the right call, not a defect); 4 confirmed correct | Closed |

All Fix items are resolved in the current state of `README.md`, `design.md`,
`deploy/New-AdaptiveScopeRetention.ps1`, `deploy/Remove-AdaptiveScopeRetention.ps1`,
`deploy/config/adaptive-scope-retention.sample.json`, and
`validate/Test-AdaptiveScopeRetention.ps1`. No Fail items were raised. This fragment meets the
definition of done in `AGENTS.md` §9; product facts are grounded in Microsoft Learn (no invented
cmdlets), and the one genuine gap this build's grounding pass could not close (which locations an
`AdaptiveScopeLocation`-scoped policy actually covers) is disclosed as `VERIFY (pilot tenant)`
rather than guessed, per `AGENTS.md` §4.
