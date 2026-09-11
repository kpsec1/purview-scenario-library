# Four-Lens Review — Adaptive-Scope Auto-Apply Label

Reviewed after the initial draft of `README.md`, `design.md`, `deploy/`, and `validate/`. One round
of findings below; all **Fix** items were applied before this file was finalized. No **Fail** items
were raised.

---

## 🔴 Red Team

**Verdict: Fix (resolved)**

1. **Query drift now locks the wrong content as a record, not just retains it.** Same underlying
   weakness as the `adaptive-scope-retention` sibling (a stale or over-broad `Title` query fails
   quietly), but the consequence here is stronger: matching content gets a record label applied, and
   that label can only be removed by a records manager — an operator who notices the drift late has
   already created cleanup work, not just a coverage gap.
   - **Resolution:** `README.md` §2, §8, and §11 all state the elevated consequence explicitly rather
     than reusing the Keep-only sibling's lighter framing; §8 recommends treating query review as
     higher-priority than the sibling's equivalent task.
2. **Attribute tampering (`Title` edit) now causes record-locking, not just retention, of the wrong
   person's content.** Same bypass vector as the sibling (self-service profile edit, a loosely-owned
   HR sync, or an admin editing `Title`), but a materially worse outcome once the adaptive scope feeds
   a record label instead of a Keep action.
   - **Resolution:** `README.md` §11 names this explicitly with the elevated framing; §8 carries
     forward the same `SetAdaptiveScope`/`ApplicableAdaptiveScopeChange` audit-monitoring
     recommendation as the concrete detection control, since this scenario doesn't otherwise defend
     against attribute tampering any more than the sibling does.
3. **Scope-sharing design amplifies blast radius if both sibling scenarios are deployed together.**
   This scenario defaults to reusing the Keep-only sibling's adaptive scope by name (`design.md` §2) —
   a deliberate design choice to avoid drifting duplicate queries, but it means a single tampered or
   stale query now affects **two** controls (retention and record-locking) instead of one, for anyone
   who deploys both.
   - **Resolution:** `README.md` §8 and `rollback.md` (Stage 3) both call this out explicitly — the
     shared-scope tradeoff is disclosed, not hidden, and rollback guidance warns against removing a
     scope that the sibling might still depend on.
4. **No content-match condition by default means any content in the scope's locations gets locked,
   not just genuinely sensitive executive communications.** An executive's routine, non-sensitive
   OneDrive files (personal templates, calendar exports) get the same record lock as anything else in
   their mailbox/OneDrive.
   - **Resolution:** This is disclosed as a deliberate design tradeoff, not silently accepted:
     `design.md` §6 states the scenario is intentionally population-based (matching the Keep-only
     sibling's own no-query design) rather than content-based, and `README.md` §6 documents that the
     `contentMatchQuery` config field is available (same as the financial-records sibling) if an
     operator wants to narrow further. Not treated as a defect because it mirrors the Keep-only
     sibling's own documented scope precisely — a customer who wants content-level narrowing has the
     field to do it.

No remaining Fix/Fail after resolution.

---

## 🔵 Blue Team

**Verdict: Fix (resolved)**

1. **Two independent delays stacking is a genuine operability trap.** An operator who validates
   immediately after deploying (and sees the scope, label, policy, and rule all `[PASS]` as existing)
   could easily conclude coverage is live, when actual labeling can lag by up to 12 days (5-day scope
   population + 7-day auto-apply distribution, worst case, not necessarily additive but not
   guaranteed to overlap either).
   - **Resolution:** `README.md` §4, §6, §7, and §11 all independently state that the two delays are
     separate and can stack; the validate script's closing message repeats this explicitly rather than
     only stating it once in the README where it could be missed.
2. **No automated signal for "has item X actually been labeled yet."** Neither `Get-
   RetentionCompliancePolicy`'s `DistributionStatus` nor `Get-AdaptiveScopeMembers` confirms individual
   content has been labeled — they confirm configuration and population membership, not labeling
   outcome.
   - **Resolution:** `README.md` §7 (validation step 5) and §8 point operators to content search /
     Records Management reporting as the actual labeling-confirmation mechanism, rather than implying
     the validate script's `[PASS]` checks are sufficient proof of coverage.
3. **Regulatory-record config path needed its own validation branch, not a generic failure.** A
   naive validate script would report the (correctly, by design) absent policy/rule as a `[FAIL]` for
   a regulatory-record config, training operators to ignore real failures in that mode.
   - **Resolution:** `validate/Test-AdaptiveScopeAutoApplyLabel.ps1` branches explicitly on
     `label.regulatory`: it confirms the policy is correctly **absent** (`[WARN]` if unexpectedly
     present, flagged for manual review) rather than treating the documented skip as an error.
4. **Detection signal reuse from the sibling was appropriate, not a shortcut taken to save effort.**
   Confirmed the same audit operations (`SetAdaptiveScope` etc.) genuinely apply unchanged here, since
   the underlying adaptive-scope object model doesn't differ between the two scenarios — re-verified
   rather than assumed correct by inheritance.

No remaining Fail.

---

## 🎩 CISO

**Verdict: Fix (resolved)**

1. **Risk vs. cost is not simply "the sibling's cost, plus a label."** A record label creates
   standing unlock/removal overhead that a Keep-only policy doesn't — if the query is ever wrong, a
   records manager's time is now a real, recurring cost line, not a policy edit.
   - **Resolution:** `README.md` §10 states this explicitly as a distinct cost driver from the
     Keep-only sibling's, rather than reusing that sibling's "storage growth is the main cost" framing
     unchanged.
2. **Conflation risk, same as the sibling, but worth restating for this control specifically.** A
   board narrative could overstate this as "litigation-ready by default" when it's a standing
   governance/records baseline, not a matter-scoped hold.
   - **Resolution:** `README.md` §11 restates the same distinction the Keep-only sibling draws,
     scoped to this record-label variant rather than assumed to carry over silently.
3. **Board/governance-committee narrative:** "executive communications are locked as records
   automatically as the org chart changes, with no distribution list to fall out of date — and with a
   disclosed, honest accounting of the one thing this doesn't do: automatically unwind a mistake."
   Materially credible precisely because the scenario names its own higher-consequence failure mode
   (record-locking the wrong content) rather than presenting adaptive auto-apply as risk-free
   automation.
4. **Change management.** Config-file-driven, create-or-report, consistent with this repo's retention-
   object discipline — same standard as both parent scenarios.
5. **Would I fund this?** Yes, but with a narrower initial rollout than the Keep-only sibling: pilot
   the query against a small, well-understood population first (the CFO/CEO/COO/General Counsel roles
   the sample config already illustrates), confirm labeling behavior in a lab tenant, and only then
   widen — the review does not recommend deploying this scenario's default config directly to a large
   or loosely-defined population on day one.

No remaining Fix/Fail after resolution.

---

## 🟦 Microsoft Product Owner

**Verdict: Fix (resolved)**

1. **Genuine grounding defect caught and corrected, not silently inherited.** This lens is exactly
   where a copied pattern's defect should surface: the financial-records sibling's `New-
   RetentionComplianceRule` call passes both `-Name` and `-ApplyComplianceTag`, which Microsoft's own
   reference documents as mutually exclusive. Reusing that exact pattern here without checking would
   have propagated a real defect into a second script.
   - **Resolution:** This scenario's deploy script omits `-Name` when calling `-ApplyComplianceTag`,
     matching the documented `ComplianceTag` parameter set (`design.md` §3). The sibling's defect is
     recorded as a `PROGRESS.md` follow-up for a future fragment to fix — flagging it here, in the
     lens whose job is exactly this kind of catch, rather than only in this scenario's own files.
2. **Adaptive scopes + auto-apply label policies are confirmed, documented, and Microsoft-recommended
   — stronger grounding than the Keep-only sibling's own equivalent claim.** Microsoft's
   "Automatically apply a retention label" guidance states plainly that adaptive scopes are a
   supported input, selected during retention-label-policy creation, and recommends them for
   production over static scopes. This is a directly-cited product statement, not an inference from
   parameter-set compatibility the way the Keep-only sibling's design.md §7 non-goal originally
   reasoned it through.
   - **Resolution:** `README.md` §2 and `design.md` §1 cite this directly; the location-scope gap
     (§11) remains disclosed as `VERIFY (pilot tenant)` rather than being treated as resolved by this
     stronger citation, since the citation confirms adaptive-scope *support*, not the specific
     *location-granularity* question the gap is about — those are different claims and this build
     doesn't conflate them.
3. **Accurate licensing.** E5 for both adaptive scopes and records management, correctly distinguished
   from the E3 baseline, consistent with `docs/licensing-matrix.md`.
4. **Right feature for the driver, and doesn't reinvent a native capability.** Uses `New-AdaptiveScope`
   / `New-ComplianceTag` / `New-RetentionCompliancePolicy` / `New-RetentionComplianceRule` end to end;
   doesn't attempt to simulate record-locking with a scheduled script, which would defeat the point.
5. **Correctly scoped regulatory-record guard.** Verified independently (not just copied) that the
   "auto-apply doesn't support regulatory records" restriction is a property of auto-apply itself, not
   of static vs. adaptive scopes specifically — so carrying the guard forward unchanged from the
   financial-records sibling is the right call, not an unexamined assumption.

No remaining Fail after resolution.

---

## Summary

| Lens | Initial verdict | Findings | Resolution |
|---|---|---|---|
| 🔴 Red Team | Fix | 4 (query drift now record-locks; attribute-tampering consequence raised; scope-sharing blast radius; no-content-query disclosed as deliberate) | Closed |
| 🔵 Blue Team | Fix | 4 (stacking-delay operability trap; no per-item labeling signal; regulatory-config validation branch; audit-signal reuse re-verified) | Closed |
| 🎩 CISO | Fix | 2 (distinct cost driver; conflation restated); Pass on narrative/change-management/funding-with-phased-rollout recommendation | Closed |
| 🟦 Microsoft Product Owner | Fix | 1 (caught and corrected the `-Name`/`-ApplyComplianceTag` defect inherited from the sibling pattern); 4 confirmed correct, including a stronger direct citation for adaptive-scope + auto-apply-label support than the Keep-only sibling has | Closed |

All Fix items are resolved in the current state of `README.md`, `design.md`,
`deploy/New-AdaptiveScopeAutoApplyLabel.ps1`, `deploy/Remove-AdaptiveScopeAutoApplyLabel.ps1`,
`deploy/config/adaptive-scope-auto-apply-label.sample.json`, and
`validate/Test-AdaptiveScopeAutoApplyLabel.ps1`. No Fail items were raised. This fragment meets the
definition of done in `AGENTS.md` §9; product facts are grounded in Microsoft Learn (no invented
cmdlets), and the one genuine defect this build's grounding pass found in a sibling, already-`DONE`
fragment is disclosed and tracked as a follow-up (`PROGRESS.md`) rather than silently repeated or
silently fixed out of scope.
