# Four-Lens Review - eDiscovery: Roster-to-Hold-Locations Hand-Off

Reviewed after the initial draft of `README.md`, `design.md`, `deploy/`, and `validate/`. One round
of findings below; all **Fix** items were applied to the scenario before this file was finalized
(see "Resolution" under each). No **Fail** items were raised.

---

## 🔴 Red Team

**Verdict: Fix (resolved)**

1. **`-AddToHold`'s reconciliation loop only iterated `$toAdd` (emails newly written to the
   definition file this run), not the full `$selectedEmails` set.** Concretely: run 1 merges three
   selected members into the definition file but is not given `-AddToHold` (the safer default,
   README.md §5 step 4). Run 2, days later, is given `-AddToHold` for the first time - but because
   all three emails are now already present in the definition file, `$toAdd` is empty and the
   original draft's Stage 2 skipped reconciliation entirely with a "No new members to reconcile"
   message, silently leaving all three members off the live hold despite the operator's explicit
   `-AddToHold` request. A caller reading only the summary line ("Reconciled 0 member(s)") could
   reasonably believe reconciliation ran and found nothing to do, rather than that it never checked
   the live hold at all.
   - **Resolution:** Stage 2 now iterates every email in `$selectedEmails`, not just `$toAdd`.
     `Confirm-UserSourceOnHold` is already its own idempotent find-or-create (identical to both
     sibling scenarios' own), so reconciling the full selection on every `-AddToHold` run is both
     correct and still a no-op for members already present on the live hold - this only changes
     behavior for the exact gap described above. `deploy/Merge-RosterIntoHoldDefinition.ps1`,
     `.SYNOPSIS`/`.DESCRIPTION`/`.PARAMETER AddToHold` updated to describe the corrected behavior.
2. **An email in `-SelectionPath`'s `selectedEmails` array that isn't found in `-RosterPath` was
   correctly treated as a hard error (`design.md` §4) - confirmed this is the right call, not a
   gap.** The alternative (skip-and-warn) would let a selection file with a real typo produce a
   merged definition file that looks complete (exit code 0) while quietly missing a person counsel
   actually decided needed preservation. Checked, not changed.
3. **A malformed `-SelectionPath` file that omits the `selectedEmails` key entirely would throw an
   unhandled `PropertyNotFoundException` under `Set-StrictMode -Version Latest`, rather than this
   script's own clear error message** - the exact `PSCustomObject`-dot-access-on-a-missing-key
   gotcha `teams-group-hold-resolution/reviews.md`'s own Red Team round already caught and fixed for
   its sibling script's `resolveMembers` field. The original draft here checked `reason`'s presence
   correctly but not `selectedEmails`'s.
   - **Resolution:** Added the same `PSObject.Properties.Name -contains 'selectedEmails'`
     presence check before access, in both `deploy/Merge-RosterIntoHoldDefinition.ps1` and
     `validate/Test-RosterHoldDefinitionMerge.ps1` (which had the identical gap independently).
4. **`Select-Object -Unique` on `selectedEmails` is case-sensitive** - a selection file listing both
   `Alex@contoso.com` and `alex@contoso.com` (a plausible copy-paste-from-two-sources mistake) would
   be treated as two distinct emails, producing two `Confirm-UserSourceOnHold` calls for what Graph
   itself treats as the same mailbox (the sibling scripts' own `Confirm-UserSource`/
   `Confirm-UserSourceOnHold` already compare `-eq` case-sensitively too, but at least only ever see
   one calling convention's casing per run there - this script's own de-duplication step is a new
   surface for the same class of issue to slip through unnoticed).
   - **Resolution:** Replaced with an explicit case-insensitive de-duplication
     (`HashSet[string]` keyed on `ToLowerInvariant()`, preserving first-seen casing) in
     `deploy/Merge-RosterIntoHoldDefinition.ps1`.
5. **Checked: does `-InPlace`'s `.bak-*` backup mechanism have a failure mode where the backup step
   is skipped but the overwrite still happens?** No - both are gated by the same
   `$PSCmdlet.ShouldProcess()` pattern used elsewhere in this repo, and the backup `ShouldProcess`
   call happens unconditionally before the write `ShouldProcess` call whenever `-InPlace` and
   `$toAdd.Count -gt 0` are both true; a `-WhatIf` run skips both consistently, never one without the
   other.
   - **Not a new finding requiring a change** - confirmed the initial draft already handles this
     correctly. No fix needed.

No remaining Fix/Fail after resolution.

---

## 🔵 Blue Team

**Verdict: Fix (resolved)**

1. **Same finding as Red Team #1, from a detectability angle** - the original `-AddToHold`
   `$toAdd`-only scoping meant an operator monitoring only this script's own summary line ("Reconciled
   N member(s)") would see a plausible-looking `0` with no indication anything was actually wrong,
   rather than a signal that reconciliation was skipped for reasons unrelated to the live hold's
   actual state.
   - **Resolution:** Same fix as Red Team #1 - reconciling the full selection set makes the summary
     line accurate in every case, not a separate detectability-specific change.
2. **`validate/Test-RosterHoldDefinitionMerge.ps1`'s completeness check (Check 2) correctly flags a
   duplicate `userSources[]` entry for the same email as a `FAIL`, not silently picking the first
   match** - confirmed a manual edit to the merged file that introduces a duplicate is caught, not
   masked by the `Select-Object -First 1`-style pattern the hold-reconciliation check (Check 3) uses
   for a different reason (Graph's own `userSources` list is not expected to ever contain a
   duplicate for the same email, since `Confirm-UserSourceOnHold` itself prevents that server-side).
   - **Not a new finding** - already present in the initial draft. No fix needed.
3. **The same `PropertyNotFoundException`-under-StrictMode gap flagged in Red Team #3 also existed
   independently in `validate/Test-RosterHoldDefinitionMerge.ps1`'s own `selectedEmails` access, and
   separately in Check 2's `$matches[0].note` access** (a merged `userSources[]` entry added by hand
   outside this script, without a `note` field, would crash the validate script instead of producing
   the intended `WARN`).
   - **Resolution:** Added the same property-presence guard to the validate script's
     `selectedEmails` access (shared fix with Red Team #3), and a parallel guard on `.note` access
     in Check 2 so a hand-added entry without one is correctly reported as `WARN`, not a crash.

No remaining Fail. The scenario is operable and its residual gaps (no live group-membership
re-check, local-only `.bak-*` backups) are disclosed in README.md §11, not silent.

---

## 🎩 CISO

**Verdict: Pass**

1. **This scenario only ever adds preservation scope, never removes it** - same asymmetric-risk
   reasoning `teams-group-hold-resolution/reviews.md`'s own CISO round already established for the
   sibling scenario applies unchanged here: "over-preserve a person who turns out not to matter"
   (cost, not spoliation exposure) versus "under-preserve, or improperly release, a person who does
   matter" (real legal exposure) means the removal-side counsel-confirmation gate belongs on
   `location-scoped-legal-hold`'s own removal path, not bolted onto this scenario's addition-only
   design.
2. **The hard-error-on-unresolved-selection design (`design.md` §4) is a real, if modest, risk
   reduction** - it converts a category of mistake (a mistyped or dropped email in a hand-edited
   JSON file) from "silently wrong, discovered later if at all" into "the script refuses to run
   until you fix it." That is exactly the kind of small, auditable control a CISO can point to when
   asked how a firm prevents an under-preservation gap in a live matter.
3. **The `-SelectionPath` `reason` field, carried into each merged `userSource`'s `note`, creates a
   durable, per-mailbox audit trail answering "why was this specific person's mailbox preserved
   individually"** - a genuine improvement over a hand-edited JSON file with no equivalent
   provenance, and the kind of artifact outside counsel or an internal audit would actually want to
   see.
4. **Cost:** zero incremental licensing or billable objects, confirmed accurate in §10 - this
   scenario only prepares and, optionally, applies `userSources[]` entries the already-licensed
   `location-scoped-legal-hold` hold policy accepts.
5. **Would I fund this?** Yes - a small, cheap fragment that removes a specific, named source of
   manual-transcription error at exactly the moment (a narrowing matter scope) where that error is
   most consequential.

No Fix/Fail items from this lens.

---

## 🟦 Microsoft Product Owner

**Verdict: Pass**

1. **Introduces no new Microsoft product facts.** Every citation this fragment depends on (the
   `userSources[]` shape, the `Create userSource` v1.0 Graph endpoint, the roster CSV's own column
   shape) was already grounded in the two sibling scenarios' own README.md §12 sections - confirmed
   this fragment correctly re-links rather than re-derives or restates those facts from memory.
2. **Correctly scopes module dependencies leaner than either sibling scenario's** - this script
   never needs an Exchange Online PowerShell connection at all (Stage 1 is pure file I/O; Stage 2
   only calls `Invoke-MgGraphRequest`), so its `#Requires` correctly lists only
   `Microsoft.Graph.Authentication`, not `ExchangeOnlineManagement` - accurate, not an oversight
   (confirmed by re-reading the full script for any hidden EXO cmdlet call; there is none).
3. **v1.0 vs. beta Graph namespace discipline holds** - the one Graph call this script's `-AddToHold`
   path makes targets `https://graph.microsoft.com/v1.0`, matching both sibling scenarios' own
   discipline.
4. **Correctly reuses, rather than reinvents, the sibling scenarios' find-or-create idempotency
   pattern** - now a third duplicated copy (`design.md` §5), consistent with this repo's established
   convention and its own documented trade-off (drift risk across copies, deferred to a future
   shared-module refactor rather than solved unprompted in a single fragment).
5. **Positioned correctly as a hand-off between two existing scenarios, not a new hold-management
   capability** - this fragment never calls a hold/case-creation endpoint, never removes a source,
   and is explicitly documented (`design.md` §6) as not attempting the two adjacent things
   (`siteSource` attachment, OneDrive) that would have required new, ungrounded product research to
   support correctly.

No Fix/Fail items from this lens.

---

## Summary

| Lens | Initial verdict | Findings | Resolution |
|---|---|---|---|
| 🔴 Red Team | Fix | 5 (3 closed with code changes - `-AddToHold` full-selection scoping, `selectedEmails` StrictMode guard, case-insensitive de-dup - 2 confirmed already correctly scoped) | Closed |
| 🔵 Blue Team | Fix | 3 (2 closed - shared `-AddToHold` fix, StrictMode guards in both scripts - 1 confirmed already correct) | Closed |
| 🎩 CISO | Pass | 5 (asymmetric-risk reasoning, audit-trail value, cost, narrative all confirmed sound) | - |
| 🟦 Microsoft Product Owner | Pass | 5 (no new product facts, dependency scoping, namespace discipline, correct positioning all confirmed correct) | - |

All Fix items from this round are resolved in the current state of `deploy/`, `validate/`,
`README.md`, and `design.md`. No Fail items were raised. This fragment meets the definition of done
in `AGENTS.md` §9.
