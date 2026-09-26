# Four-Lens Review - eDiscovery Teams-Purge Hold Lifecycle Management

Reviewed after the initial draft of `README.md`, `design.md`, `deploy/`, and `validate/`. One round of
findings below; all **Fix** items were applied before this file was finalized. No **Fail** items
remain.

---

## 🔴 Red Team

**Verdict: Fix (resolved)**

1. **The initial draft conflated org-wide "Exchange" and "Group" retention policies into a single
   bucket, always remediating with `-AddExchangeLocationException`.** Microsoft's own `InPlaceHolds`
   reference draws a hard line: `mbx`-prefixed org-wide policies apply to Exchange mailboxes (all
   types, including 1xN Teams chats), but `grp`-prefixed org-wide policies apply **only** to
   Microsoft 365 Group mailboxes - a standard/shared channel's own parent-team mailbox, which this
   scenario's scripts directly target for that `sourceType`. The initial draft would have silently
   attempted the wrong exception mechanism (or missed the applicable policy entirely) for exactly the
   target-mailbox type this scenario exists to support.
   - **Resolution:** `Get-/Remove-/Restore-TeamsPurgeMailboxHolds.ps1` and `validate/
     Test-TeamsPurgeMailboxHoldLifecycle.ps1` now classify org-wide GUIDs by prefix, gate Group-policy
     applicability on `Get-Mailbox`'s own `RecipientTypeDetails -eq 'GroupMailbox'`, and route Group
     policies through the correct `-AddModernGroupLocationException`/`-RemoveModernGroupLocationException`
     parameters - confirmed to exist against the `Set-RetentionCompliancePolicy` full parameter syntax,
     not guessed by analogy. `design.md` §8 documents the full distinction and the one remaining
     disclosed gap (no confirmed `InPlaceHolds` notation exists for a Group-location exclusion, unlike
     the confirmed `-mbx<guid>` notation for Exchange-location exclusions).
2. **`-IncludeComplianceTagHold` could be used to strip a real preservation signal irreversibly**, with
   no scripted way back - a insider or a rushed operator under incident pressure could clear a
   retention-label hold that should have stayed in place, and this scenario cannot undo it.
   - **Resolution:** Opt-in only (never the default), gated behind an explicit switch the operator must
     read the `.PARAMETER`/`.DESCRIPTION` warning for; every invocation prints a `Write-Warning`
     naming the action as one-way before it runs; and the action itself is a standard `Set-Mailbox`
     call, fully visible in the unified audit log like any other change this scenario makes. `design.md`
     §5 and `README.md` §11 both state this is a deliberate, disclosed risk-acceptance, not a gap to
     close - the alternative (never allowing the clear at all) would leave a real, documented purge
     blocker with no scriptable remediation path at all.
3. **A stale or incomplete target-mailbox list creates the same false-containment risk this repo's
   `search-and-purge-teams-messages` sibling already disclosed** - a mailbox missing from
   `-DefinitionPath`/`-Mailbox` never gets its holds identified or removed, and the operator may
   believe the mailbox list is complete.
   - **Resolution:** Not re-solved here - this scenario deliberately reuses the sibling's own
     target-mailbox list (`design.md` §3 goal 1) rather than re-deriving it, so the sibling's own
     Red Team resolution (naming "bound target mailboxes vs. incident roster" as an explicit KPI,
     `search-and-purge-teams-messages/README.md` §8) already covers this scenario's identical exposure.
     Duplicating that finding here would be double-counting the same root cause.

No remaining Fix/Fail after resolution.

---

## 🔵 Blue Team

**Verdict: Fix (resolved)**

1. **No push notification on this scenario's own hold-removal/restore actions** - the same class of
   gap this repo already discloses and accepts for the sibling purge scenario's own `purgeData`
   completion.
   - **Resolution:** `README.md` §8 recommends forwarding the underlying `Set-Mailbox`/
     `Set-RetentionCompliancePolicy` audit events to Sentinel/SIEM alongside the sibling's own
     `ediscoveryCase` operation events, rather than leaving polling (`validate/
     Test-TeamsPurgeMailboxHoldLifecycle.ps1`) as the only signal undisclosed.
2. **A `[FAIL]` from `validate/Test-TeamsPurgeMailboxHoldLifecycle.ps1` Mode 1 does not distinguish
   "this scenario can fix it" from "this scenario can never fix it"** (an eDiscovery case hold or
   legacy In-Place Hold FAILs identically to a removable Litigation Hold) - a risk of alert fatigue or
   a responder repeatedly re-running `Remove-TeamsPurgeMailboxHolds.ps1` against a blocker it was
   never going to clear.
   - **Resolution:** Accepted as the correct default, not fixed by softening the exit code - a purge
     genuinely will not succeed while either hold type remains, so a `[FAIL]` here is accurate
     regardless of whether this scenario's own tooling can act on it. `Remove-TeamsPurgeMailboxHolds.ps1`
     already prints which specific blockers are non-scriptable (`$anyUnresolvedBlockers` path) so the
     distinction is visible at the remediation step, even though the validation script's own exit code
     doesn't separately encode it. Flagged in `README.md` §11 rather than silently left ambiguous.
3. **`Get-TeamsPurgeMailboxHoldState.ps1`'s `-OutputPath` JSON write (`$report | ConvertTo-Json`) can
   emit a bare JSON object instead of a one-element array when exactly one target mailbox is reported**
   - a well-known PowerShell pipeline quirk (piping a single-element array collapses it) that could
   break downstream tooling expecting an array.
   - **Resolution:** Accepted, not changed - this report is explicitly documented as "consumed by
     nothing in this scenario directly" (audit-record purposes only), and the same `$x | ConvertTo-Json`
     pattern is already the established convention across this repo's other scenarios (e.g.
     `teams-group-hold-resolution`, `roster-to-hold-locations`). Introducing a one-off `-AsArray` fix
     here would be an inconsistent pattern for a non-functional, cosmetic edge case; noted here for a
     future cross-cutting pass if this repo ever standardizes its own JSON-array-output convention.
4. **This scenario's three deploy scripts each carry their own copy of `ConvertTo-ParsedInPlaceHolds`/
   `Resolve-RetentionPolicyName`/`Get-TargetMailboxList`, rather than a shared module** - a
   maintenance-surface risk if one copy is fixed (as the Red Team finding 1 fix required) without the
   others.
   - **Resolution:** Accepted as this repo's established per-scenario self-containment convention (no
     shared PowerShell module exists anywhere else in this repo's `scenarios/` tree either) rather than
     introducing a new cross-scenario dependency for one fragment. The Red Team finding 1 fix was
     applied identically to all four affected files (`Get-`/`Remove-`/`Restore-`/`Test-`) as part of
     this same review round specifically to close the drift risk this finding raises - verified by
     direct re-read of all four files after the fix, not assumed.

No remaining Fail.

---

## 🎩 CISO

**Verdict: Pass (with confirmed disclosures)**

1. **Would I fund this?** Yes - it converts a documented, error-prone manual sequence (Microsoft's own
   guidance explicitly warns that skipping hold removal silently defeats the purge) into a repeatable,
   auditable script with a recorded state trail, at no additional licensing cost beyond what the
   sibling purge scenario already requires.
2. **The opt-in-for-irreversible-action pattern (`-IncludeComplianceTagHold`) is the correct governance
   posture**, matching this repo's own precedent (`priority-cleanup-exchange-data-spillage`'s
   `-Enabled` switch) rather than a scenario-specific improvisation - consistent risk language across
   the product.
3. **The state-file design (record only what changed, restore only what was recorded) is itself a
   control**, not just an implementation convenience: a partial removal failure cannot silently drift
   into an over-broad or under-scoped restore, which matters directly for preservation-duty compliance
   (a mailbox left off-hold longer than necessary is a real regulatory exposure, not just an
   operational inconvenience).
4. **The Red Team finding 1 fix (Exchange vs. Group org-wide policy conflation) is exactly the kind of
   defect that would have produced a false sense of remediation** - a standard/shared-channel purge
   attempt appearing "hold-cleared" by this scenario's own report while an applicable Group-scoped
   policy silently remained in force. Catching and fixing this before shipping, rather than after a
   customer hit it, is the material difference between a reference implementation and a liability.

No Fix/Fail raised - the initial draft already covered the material CISO-level risks; this pass
confirmed rather than found additional gaps.

---

## 🟦 Microsoft Product Owner

**Verdict: Pass**

1. **Every cmdlet and parameter this scenario calls is grounded against a direct Microsoft Learn
   fetch, not inferred by analogy** - including the less commonly documented
   `-AddModernGroupLocationException`/`-RemoveModernGroupLocationException` pair, confirmed against
   `Set-RetentionCompliancePolicy`'s full parameter syntax rather than assumed to exist because
   `-AddExchangeLocationException` does.
2. **Correctly respects this repo's own established automation-surface boundary.** eDiscovery case
   holds are identify-only specifically because resolving them needs `Get-CaseHoldPolicy`/
   `Get-ComplianceCase` - eDiscovery cmdlets in Security & Compliance PowerShell, the one documented
   app-only-unsupported exception `docs/automation-surface.md` §3 already carries for this entire
   repo. This scenario doesn't quietly work around that boundary for a narrow, "just read-only" case.
3. **Correctly identifies and respects a retirement boundary.** Legacy In-Place Holds are identified
   but never targeted for removal, citing Microsoft's own current guidance that they're not removable
   for an active mailbox - right feature, not a deprecated one, for every action this scenario takes.
4. **Every genuine gap is flagged as a VERIFY or a disclosed non-goal, not silently assumed:** the
   24-hour synchronization timing for mailbox-scoped policy changes (confirmed for the org-wide
   exclusion path only), the delay-hold pre-emptive-call behavior, the unconfirmed Group-location
   exclusion `InPlaceHolds` notation, and the newer-location (`*-AppRetentionCompliancePolicy`)
   per-mailbox applicability gap are all stated as open questions in `README.md` §11 and `design.md`,
   not guessed.
5. **Correctly scoped as a companion, not a fork.** Reuses the sibling scenario's own
   `-DefinitionPath` schema and target-mailbox resolution rather than duplicating that logic, and never
   modifies the sibling's own `deploy/`/`validate/` scripts.

No Fix/Fail raised.

---

## Summary

| Lens | Initial verdict | Findings | Resolution |
|---|---|---|---|
| 🔴 Red Team | Fix | 3 (Exchange/Group org-wide policy conflation - a real remediation-accuracy bug, fixed across all four scripts; irreversible retention-label-hold clear - accepted, disclosed opt-in; stale target-mailbox list - inherited from and already covered by the sibling scenario) | Closed |
| 🔵 Blue Team | Fix | 4 (no completion alerting - SIEM recommendation added; undifferentiated FAIL for non-scriptable blockers - accepted trade-off, disclosed; single-element JSON array collapse on the informational report - accepted, matches repo convention; duplicated helper functions across scripts - accepted repo convention, verified consistently patched) | Closed |
| 🎩 CISO | Pass | 0 new findings; funding rationale, opt-in-irreversibility governance pattern, state-file-as-control design, and the value of catching the Red Team finding 1 defect pre-ship all confirmed | - |
| 🟦 Microsoft Product Owner | Pass | 0 new findings; grounded cmdlet/parameter usage including the less-common Group-location parameters, correct automation-surface and retirement-boundary respect, honestly-flagged VERIFYs, and correct companion scoping all confirmed | - |

All Fix items are resolved in the current state of `README.md`, `design.md`,
`deploy/Get-TeamsPurgeMailboxHoldState.ps1`, `deploy/Remove-TeamsPurgeMailboxHolds.ps1`,
`deploy/Restore-TeamsPurgeMailboxHolds.ps1`, `deploy/policy/
teams-purge-hold-lifecycle-mailboxes.sample.json`, `validate/Test-TeamsPurgeMailboxHoldLifecycle.ps1`,
and `rollback.md`. No Fail items were raised. This fragment meets the definition of done in
`AGENTS.md` §9; product facts are grounded in Microsoft Learn (no invented cmdlets or parameters -
every `Set-Mailbox`/`Set-RetentionCompliancePolicy` parameter this scenario calls, including the
Group-location pair, was confirmed against a direct Microsoft Learn fetch before use), and every
disclosed gap (eDiscovery case holds, legacy In-Place Holds, newer-location policies, the
Group-location-exclusion notation) is stated as such rather than guessed around.

---

## Round 2 - the mailbox-scoped Exchange-vs-Group-location conflation (PROGRESS.md follow-up)

Reviewed after grounding a `PROGRESS.md` follow-up asking whether a mailbox-scoped (non-org-wide)
retention policy on a Group/team mailbox is reachable via `-RemoveExchangeLocation`/`-AddExchangeLocation`
(as the initial draft assumed) or needs the `-ModernGroupLocation` parameter family instead - see
`design.md` §8.1 for the full grounding and fix.

### 🔴 Red Team

**Verdict: Fix (resolved)**

1. **The initial draft's `ConvertTo-ParsedInPlaceHolds` classified `mbx`/`skp`/`grp`-prefixed
   mailbox-scoped entries as one interchangeable bucket, always remediated with
   `-RemoveExchangeLocation`/`-AddExchangeLocation`.** This is the exact same class of bug Round 1's
   Red Team finding 1 caught for the org-wide case - it simply hadn't been re-checked for the
   mailbox-scoped path. Two freshly-fetched Microsoft Learn pages this round confirm it's real: the
   "Exchange mailboxes" location (org-wide **or** specific-location) flatly rejects a Microsoft 365
   Group mailbox ("RemoteGroupMailbox isn't a valid selection"), and the specific-location `InPlaceHolds`
   prefix table documents only `mbx`/`skp`, never `grp`. Had this scenario ever encountered a group/team
   mailbox carrying a mailbox-scoped Group-location policy, `Remove-TeamsPurgeMailboxHolds.ps1` would
   have issued a call Microsoft's own documentation proves cannot succeed against that location - a real
   remediation-accuracy bug for exactly the target-mailbox type (`sourceType` standard/shared channel)
   this scenario exists to support, the same failure mode Round 1 already fixed for the org-wide sibling.
   - **Resolution:** `grp` is now parsed separately from `mbx`/`skp` in all four scripts. A `grp`-prefixed,
     non-org-wide entry on a confirmed group/team mailbox is removed/restored via
     `-RemoveModernGroupLocation`/`-AddModernGroupLocation`; the identical entry on any other mailbox is
     reported as `UnrecognizedPolicyGuids` and never acted on. `applicableOrgWideExchange`'s gating was
     also corrected to exclude group/team mailboxes, mirroring the pre-existing Group-side gate.
2. **Is `-RemoveModernGroupLocation` actually the right mechanism, or a second guess replacing the
   first one?** Simply swapping one assumed parameter for another without confirming it exists would
   just move the bug, not fix it.
   - **Resolution:** `-AddModernGroupLocation`/`-RemoveModernGroupLocation` were directly confirmed
     against `New-/Set-RetentionCompliancePolicy`'s own Microsoft Learn syntax (fetched this round, not
     inferred by analogy with the already-confirmed exception-parameter pair). What is **not** confirmed
     - the exact `InPlaceHolds` notation this mechanism stamps on the mailbox - is disclosed as an open
     VERIFY (`README.md` §11, this script's `.NOTES`) rather than asserted with false confidence.
3. **Could the fix silently drop coverage for a mailbox that legitimately needs the anomaly bucket
   acted on?** `UnrecognizedPolicyGuids` is identify-only by design - does that leave a real purge
   blocker unresolved with no path forward?
   - **Resolution:** Yes, and that's stated plainly, not hidden - `Remove-TeamsPurgeMailboxHolds.ps1`
     sets `$anyUnresolvedBlockers = $true` and warns loudly per mailbox; `Get-`/`validate/Test-` surface
     it as a blocker in `BlocksPurge`/`[FAIL]`. The alternative (guessing a removal mechanism for a case
     no citation explains) risks a worse outcome - an API call against the wrong location parameter, or
     silently claiming success for content that's still on hold - which is exactly the bug this round
     fixes for the confirmed case. No worse than Round 1's own eDiscovery-hold/legacy-hold precedent for
     "real blocker, disclosed as identify-only."

No remaining Fail.

### 🔵 Blue Team

**Verdict: Pass**

- `Get-TeamsPurgeMailboxHoldState.ps1`'s per-mailbox output and JSON report now distinguish
  `MailboxScopedGroupPolicyNames` from `UnrecognizedPolicyNames` - an operator reading the console
  output (or a SIEM ingesting the JSON) can tell "scriptable Group-location policy, handled" apart from
  "anomaly, needs manual investigation" instead of both collapsing into one ambiguous bucket.
- `validate/Test-TeamsPurgeMailboxHoldLifecycle.ps1`'s Mode 2 check for
  `mailboxScopedGroupPoliciesRemoved` follows the same `[PASS]`/`[FAIL]` pattern as the pre-existing
  Exchange-location check - no new verdict semantics for an on-call responder to learn.
- The new `Write-Warning` in `Remove-TeamsPurgeMailboxHolds.ps1` names the VERIFY inline, at the moment
  it matters (right before the mutating call), not buried only in `.NOTES` - a responder running this
  interactively sees the caveat in real time.

No Fix/Fail items from this lens.

### 🎩 CISO

**Verdict: Pass**

- Same no-new-license-tier, same-scenario-scope profile as Round 1 - this is a same-day correctness
  fix to already-funded automation, not a new spend decision.
- Materially reduces a real operational risk: without this fix, an incident responder running this
  scenario against a standard/shared Teams channel with its own mailbox-scoped retention policy would
  have hit a silent or confusing failure mid-incident, under time pressure, for exactly the target type
  this scenario was built to support.
- The disclosed VERIFY (unconfirmed `InPlaceHolds` notation for the Group-location mailbox-scoped case)
  is a narrower, better-understood gap than the bug it replaces - "we act on the only plausible
  mechanism and flag the one open question" is a stronger audit answer than "we call a parameter that
  provably cannot work."

No Fix/Fail items from this lens.

### 🟦 Microsoft Product Owner

**Verdict: Pass**

- Both newly-cited Microsoft Learn pages (`retention-settings`, the specific-location half of
  `edisc-hold-types-mailboxes`) were fetched directly and in full this round, not inferred from a search
  snippet, consistent with `AGENTS.md` §4.
- `-AddModernGroupLocation`/`-RemoveModernGroupLocation` are the Microsoft-documented, current mechanism
  for this exact location - no deprecated or reinvented path introduced.
- The fix correctly distinguishes a *confirmed* fact (Exchange-location categorically rejects group
  mailboxes) from an *unconfirmed* one (the resulting notation for the Group-location mailbox-scoped
  case) rather than treating both with the same certainty - the disclosed VERIFY is accurate, not
  overclaimed.

No Fix/Fail items from this lens.

### Round 2 Summary

| Lens | Initial verdict | Findings | Resolution |
|---|---|---|---|
| 🔴 Red Team | Fix | 3 (Exchange/Group mailbox-scoped conflation - a real remediation-accuracy bug, fixed across all four scripts; confirmed the replacement mechanism is grounded, not a second guess; disclosed rather than hid the residual `UnrecognizedPolicyGuids` gap) | Closed |
| 🔵 Blue Team | Pass | 0 new findings; distinguishable report buckets and inline VERIFY warning confirmed | - |
| 🎩 CISO | Pass | 0 new findings; low-cost correctness fix with real operational-risk reduction confirmed | - |
| 🟦 Microsoft Product Owner | Pass | 0 new findings; both new citations fetched directly, current (non-deprecated) mechanism used, confidence levels accurately disclosed | - |

All Fix items from this round are resolved in the current state of `deploy/`, `validate/`, `README.md`,
and `design.md`. No Fail items were raised. The residual `InPlaceHolds`-notation VERIFY for the
Group-location mailbox-scoped case is deliberately left open (not guessed at) and tracked in
`PROGRESS.md`.
