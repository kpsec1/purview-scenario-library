# Four-Lens Review - eDiscovery Search-and-Purge for Microsoft Teams Messages

Reviewed after the initial draft of `README.md`, `design.md`, `deploy/`, and `validate/`. One round
of findings below; all **Fix** items were applied before this file was finalized. No **Fail** items
remain.

---

## 🔴 Red Team

**Verdict: Fix (resolved)**

1. **Muscle-memory risk from the mailbox sibling's own pattern.** An operator trained on
   `search-and-purge-data-spillage`, where `-PurgeType Recoverable` is genuinely the safe default,
   could reasonably assume the same is true here and treat `-PurgeType Recoverable` as low-risk for
   Teams - when it is, in fact, exactly as irreversible for the user-visible message as
   `PermanentlyDelete`.
   - **Resolution:** `Invoke-TeamsMessagePurge.ps1` requires `-ConfirmPermanentDelete`
     **unconditionally**, for both `-PurgeType` values, throwing a specific error naming the
     mailbox-sibling contrast if omitted. `README.md` §2's warning banner and §6's configuration
     table both state this before the reader reaches the step-by-step section, not only in a
     footnote.
2. **A stale or incomplete `targetMailboxes` list creates a false sense of containment.** Because
   this scenario has no tenant-wide scope (by design - `design.md` §3 goal 3), a mailbox missing from
   the definition file (a chat participant not yet identified, or a private-channel mailbox model
   this scenario's own `README.md` §11 flags as unconfirmed) means that copy of the message survives
   the purge entirely, while the operator may believe the incident is closed.
   - **Resolution:** `README.md` §8 names "the number of bound target mailboxes vs. the incident
     roster" as an explicit KPI to check, not just a validation-script pass/fail; `design.md` §4
     documents the Standard/shared-channel vs. 1:1/group-chat vs. private-channel resolution paths
     explicitly rather than implying one mailbox always suffices; the private-channel storage-model
     ambiguity is flagged as an open VERIFY rather than resolved by guessing which of Microsoft's two
     descriptions is authoritative.
3. **The `contentQuery` and target-mailbox list can themselves carry sensitive incident detail**
   (a distinctive phrase, or the identities of everyone involved), persisting on the live search and
   case objects for the life of the case - the same exposure class the mailbox sibling already
   disclosed.
   - **Resolution:** The sample config's own `_comment` and `README.md` §11 flag this; `rollback.md`
     Stage 2 documents deleting the search once the incident closes, matching the mailbox sibling's
     own precedent.

No remaining Fix/Fail after resolution.

---

## 🔵 Blue Team

**Verdict: Fix (resolved)**

1. **No push notification on `purgeData` completion or failure**, the same gap already disclosed and
   accepted for the mailbox sibling.
   - **Resolution:** `README.md` §8 carries forward the same SIEM-forwarding recommendation for
     `ediscoveryCase` operation-completion events, rather than leaving polling as the only option
     undisclosed.
2. **Nothing in this scenario can programmatically confirm a target mailbox's hold was actually
   removed before the purge, or reapplied afterward** - a real audit gap, since a skipped removal
   silently no-ops the purge (content is retained, not deleted) while a skipped reapplication is a
   preservation-duty lapse that could go unnoticed for a mailbox otherwise still under a broader
   organizational hold policy.
   - **Resolution:** `README.md` §8 names the hold-removal/reapplication sequence as "the single
     biggest operational risk in this workflow" rather than a routine step buried in §5, and both
     `Invoke-TeamsMessagePurge.ps1`'s pre-purge warning and its post-purge output explicitly remind
     the operator of the still-pending reapplication step. `validate/
     Test-TeamsMessagePurgeSearchAndPurge.ps1`'s `.NOTES` and closing summary line both state plainly
     that hold state is outside what this script can check.
3. **The `DisplayName`-matching idempotency heuristic for a case-level `noncustodialDataSource`**
   (`Get-OrNewTargetSource` in the deploy script) could silently create a duplicate source object
   for the same mailbox if Graph populates `DisplayName` differently than a mailbox's own SMTP
   address for a `userSource` - this build found a worked example only for a `siteSource`'s
   `DisplayName` (a SharePoint site title), not a `userSource`'s.
   - **Resolution:** Disclosed directly in the deploy script's own `.NOTES`, `design.md` §6, and
     `README.md` §11 as an open VERIFY; `validate/Test-TeamsMessagePurgeSearchAndPurge.ps1` reports a
     source-binding match as `[WARN]`, never `[PASS]`, pending confirmation - the same honest,
     not-silently-assumed pattern this repo already uses elsewhere for unconfirmed property shapes.
4. **This scenario calls an unconfirmed-by-typed-cmdlet raw HTTP request** (`Invoke-MgGraphRequest`
   for the `noncustodialSources/$ref` bind) rather than a typed SDK cmdlet, which is a smaller
   long-term maintenance surface than the rest of the script (no compile-time parameter validation).
   - **Resolution:** Accepted as the correct trade-off per `AGENTS.md` §4 (never guess an unconfirmed
     cmdlet name) rather than a defect - flagged plainly in the deploy script's `.NOTES` and
     `design.md` §6 so a future maintainer knows to swap in a typed cmdlet once one is confirmed,
     rather than assuming the current code is final. **Update 2026-09-27:** re-grounded via the
     Microsoft.Graph.Security v1.0 module's own cmdlet index - no typed cmdlet exists for this noun
     beyond `Get-`, so the raw-HTTP call is confirmed as the only way to perform this action, not
     merely an accepted placeholder. `README.md` §11 / `design.md` §6 updated accordingly.

No remaining Fail.

---

## 🎩 CISO

**Verdict: Pass (with confirmed disclosures)**

1. **Would I fund this?** Yes - it closes a real content-type gap the mailbox-only sibling
   deliberately left open, using an entitlement (eDiscovery Premium) the org likely already holds if
   it funded that sibling.
2. **The irreversibility framing is the correct governance posture, not just a technical detail.**
   Requiring `-ConfirmPermanentDelete` unconditionally (§7 Red Team finding 1's resolution) means no
   approval workflow can route a Teams purge through a "low-risk" fast path by mistake - every
   invocation gets the same deliberate, named confirmation regardless of which `purgeType` an
   approver picked.
3. **The hold-removal/reapplication process is now an assigned operational responsibility, not an
   implied one.** §8's KPI framing and the scripts' own reminders mean a runbook built from this
   scenario's docs won't quietly drop that step - a real risk given it's a heavier ask than the
   mailbox sibling's "purge, held mailboxes are just skipped" model.
4. **This build's correction to the mailbox sibling's own prior claim is itself a positive
   governance signal**, not a defect to be embarrassed about: a previously-recorded assumption was
   re-checked against current Microsoft Learn during directly related follow-on work and fixed in
   place rather than left standing next to a scenario that contradicts it - see `design.md` §2.

No Fix/Fail raised - the initial draft already covered the material CISO-level risks; this pass
confirmed rather than found gaps.

---

## 🟦 Microsoft Product Owner

**Verdict: Pass**

1. **Correct, current API surface**, and correctly rejects the legacy path. Built on the Graph
   `ediscoverySearch`/`purgeData` action with `purgeAreas: teamsMessages` (v1.0, non-preview) - and
   Microsoft's own current guidance for this exact workflow says to **avoid** the classic
   cmdlet-based purge for Teams specifically ("the user copy isn't deleted"), which independently
   confirms this scenario's Graph-only design choice for a second, Teams-specific reason beyond the
   automation-surface rationale the mailbox sibling already established.
2. **The permanent-deletion behavior is quoted verbatim from the authoritative source, not
   inferred.** The `purgeData` Graph reference's own note ("the Teams messages are permanently
   deleted" for either `purgeType` value) is the single fact this entire scenario's safety design
   rests on, and it's cited directly rather than assumed by analogy to the mailbox sibling's
   different behavior.
3. **Correctly identifies and resolves a genuine documentation conflict rather than picking one side
   silently.** Two current, non-retired Microsoft Learn pages describe private-channel compliance
   storage differently (a single dedicated mailbox vs. every member's own mailbox); this scenario
   states both and flags the conflict as an open VERIFY instead of asserting whichever one made the
   script simpler.
4. **Right feature for the job, complementary rather than duplicative** with the mailbox sibling -
   the two scenarios now correctly agree on `purgeAreas`'s two values' actual behavior after this
   build's correction, rather than one silently contradicting the other.
5. **Accurate licensing and role citation**, including a nuance the mailbox sibling's own citation
   didn't carry: Microsoft's Teams-specific purge-role documentation states a **broader** default
   role-group assignment (Data Investigator **and** Organization Management) than the mailbox
   page's own "Organization Management only" phrasing - both are cited accurately rather than
   silently merged into one claim.
6. **Every genuine gap is flagged as VERIFY, not asserted as fact:** the private-channel storage
   model, the unconfirmed `$ref`-bind SDK cmdlet name, the `noncustodialDataSource` `DisplayName`
   shape for a `userSource`, and whether `purgeType` still affects the compliance copy's timing - all
   four are stated as open questions in `README.md` §11 and `design.md`, not guessed.

No Fix/Fail raised.

---

## Summary

| Lens | Initial verdict | Findings | Resolution |
|---|---|---|---|
| 🔴 Red Team | Fix | 3 (safe-default muscle memory from the mailbox sibling; stale/incomplete target-mailbox list creates false containment confidence; sensitive query/target persistence) | Closed |
| 🔵 Blue Team | Fix | 4 (no completion alerting - SIEM recommendation carried forward; no programmatic hold-state confirmation - elevated to a named top operational risk; unconfirmed DisplayName-matching idempotency heuristic - disclosed as VERIFY; raw-HTTP $ref bind vs. a typed cmdlet - accepted trade-off, disclosed) | Closed |
| 🎩 CISO | Pass | 0 new findings; funding rationale, unconditional-confirmation governance value, assigned hold-process ownership, and the sibling-correction's own governance signal all confirmed | - |
| 🟦 Microsoft Product Owner | Pass | 0 new findings; current non-legacy API surface with an independent Teams-specific reason to avoid the cmdlet path, verbatim-quoted safety fact, an honestly-flagged documentation conflict, accurate differentiated role citation, and four honestly-flagged VERIFYs all confirmed | - |

All Fix items are resolved in the current state of `README.md`, `design.md`,
`deploy/New-TeamsMessagePurgeSearch.ps1`, `deploy/Invoke-TeamsMessagePurge.ps1`,
`deploy/policy/teams-message-purge-search-definition.sample.json`,
`validate/Test-TeamsMessagePurgeSearchAndPurge.ps1`, and `rollback.md`. No Fail items were raised.
This fragment meets the definition of done in `AGENTS.md` §9; product facts are grounded in
Microsoft Learn (no invented cmdlets - the unconfirmed `$ref`-bind SDK cmdlet name and
`noncustodialDataSource` `DisplayName` shape are disclosed as VERIFY, not presented as confirmed),
and the corrected understanding that no Teams purge is reversible for the user-visible message is
treated as this scenario's central safety constraint throughout, mirrored by the unconditional
`-ConfirmPermanentDelete` gate in `Invoke-TeamsMessagePurge.ps1`.

---

## Correction addendum (2026-09-27, maintenance pass - no new four-lens round per `AGENTS.md` §6)

The private-channel compliance-copy storage "conflict" referenced in items 2/6 above (Red Team,
Microsoft Product Owner) and cited as an open VERIFY in `README.md` §11/`design.md` §4 has been
**reconciled, not left open**: Microsoft documents it as a completed migration from a per-member
mailbox model to a single dedicated group mailbox, confirmable per tenant/channel via
`Get-TenantPrivateChannelMigrationStatus`. This is a doc/fact correction only - no script, policy,
or architecture change - so it doesn't reopen either lens's verdict above; it tightens the
Microsoft Product Owner lens's "honestly-flagged documentation conflict" finding from an unresolved
gap to a resolved fact with a residual per-tenant migration check.

## Correction addendum (2026-09-28, maintenance pass - no new four-lens round per `AGENTS.md` §6)

The `-PurgeType`-affects-compliance-copy-timing question referenced in item 6 above (Microsoft
Product Owner) and cited as an open VERIFY in `README.md` §11/`design.md` §7 has been **closed, not
left open**: the `ediscoverySearch: purgeData` Graph reference - the authoritative source for the
`purgeType` parameter itself - states that for `purgeAreas: teamsMessages`, either `purgeType`
value results in permanent deletion, documenting no separate compliance-copy retention or
hold-interaction behavior per value. This is a doc/fact correction only - no script, policy, or
architecture change (`Invoke-TeamsMessagePurge.ps1` already required `-ConfirmPermanentDelete`
unconditionally for both values, which this finding confirms rather than changes) - so it doesn't
reopen the Microsoft Product Owner lens's verdict above; it tightens item 6's "flagged as an open
question" finding from an unresolved gap to a resolved, cited fact. Two of the original four items
in that finding remain open VERIFYs - the SDK cmdlet name and the `userSource` `DisplayName` shape
(private-channel storage was separately reconciled above; `-PurgeType` timing is closed by this
addendum).
