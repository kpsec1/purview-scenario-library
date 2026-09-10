# Four-Lens Review — eDiscovery Search-and-Purge for Data Spillage

Reviewed after the initial draft of `README.md`, `design.md`, `deploy/`, and `validate/`. One round
of findings below; all **Fix** items were applied before this file was finalized. No **Fail** items
remain.

---

## 🔴 Red Team

**Verdict: Fix (resolved)**

1. **A `dataSourceScopes: allTenantMailboxes` sweep with a generic query has real blast radius** —
   the 100-item-per-mailbox ceiling limits damage *per mailbox*, but a broad query against every
   mailbox in the tenant could still purge unrelated, legitimate content at scale before anyone
   notices.
   - **Resolution:** `README.md` §8 names the `contentQuery` as "the single highest-leverage
     control" and explicitly warns that "a `dataSourceScopes: allTenantMailboxes` sweep with a broad
     query risks false-positive purges"; both deploy scripts require reviewing the
     `estimateStatistics` `mailboxCount`/`indexedItemCount` before purging, and purge is a separate,
     explicitly-invoked script from search creation (`design.md` §2 goal 3).
2. **The `contentQuery` can itself carry the spilled data** (an exact phrase or filename from the
   leaked content), persisting on the live search object for the life of the case — a second,
   smaller exposure surface for anyone with case-read access.
   - **Resolution:** `README.md` §11 now states this explicitly; the sample config's own `_comment`
     flags the file as sensitive; `rollback.md` Stage 2 documents deleting the search once the
     incident closes, matching the retired walkthrough's own "delete the search query" step.
3. **Purge only addresses the copy still sitting in the mailbox — it says nothing about content
   already forwarded, downloaded, or synced elsewhere before the purge ran.** A responder who treats
   a successful `Recoverable` purge as "incident closed" without checking how far the message
   actually traveled is under-covering the incident.
   - **Resolution:** `README.md` §8 now names **Message trace** as a required complementary check
     for any incident with external recipients or wide internal reach, citing the same page the
     retired walkthrough's own Step 5 pointed at.

No remaining Fix/Fail after resolution.

---

## 🔵 Blue Team

**Verdict: Fix (resolved)**

1. **No push notification on `purgeData` completion or failure** — an operator must poll
   `Get-MgSecurityCaseEdiscoveryCaseOperation` or re-run the validate script; nothing alerts a SOC on
   its own.
   - **Resolution:** `README.md` §8 recommends forwarding `ediscoveryCase` operation-completion
     events to Sentinel/SIEM via the audit-log export pattern this repo's `premium-legal-hold-and-
     export` sibling already established, rather than leaving polling as the only option undisclosed.
2. **The prior-purge-operations listing is case-wide, not search-specific**, because `caseOperation`
   doesn't expose which search a completed `purgeData` operation targeted without a further,
   undocumented expand — a real risk of misattributing a purge to the wrong search in a
   multi-search case.
   - **Resolution:** Disclosed directly in `Invoke-DataSpillagePurge.ps1`'s
     `Get-PriorPurgeOperations` comment and elevated into `README.md` §11 as a named gotcha, rather
     than silently presenting the listing as search-scoped.
3. **The async-operation `Location` header format was assumed inconsistently across this repo.**
   Microsoft's own `estimateStatistics` example shows an OData-canonical
   `.../operations('698514cc...')` style, while the `premium-legal-hold-and-export` sibling's
   shipped script assumed a plain `.../operations/abc123` path-segment style for its own polling —
   picking the wrong one silently corrupts the extracted operation ID (e.g. yielding
   `operations698514cc...` instead of the bare ID) rather than failing loudly.
   - **Resolution:** Both of this scenario's scripts now use a shared `Get-OperationIdFromLocation`
     helper that tries the OData-parens form first and falls back to the path-segment form, with a
     comment explaining why neither is assumed outright; caught during this review by tracing the
     actual example response Microsoft's documentation shows for this action family.
4. **The purge job report's download-link lifetime is undocumented** — if it expires quickly and
   nobody downloads it promptly, the most detailed per-item proof-of-purge record could become
   permanently unavailable.
   - **Resolution:** Flagged as an open VERIFY in `README.md` §11, with explicit guidance to download
     and archive the report immediately rather than treating the printed URL as durable.

No remaining Fail.

---

## 🎩 CISO

**Verdict: Pass (with confirmed disclosures)**

1. **Would I fund this?** Yes — it's the fast, low-friction containment tool most spillage incidents
   actually need, priced entirely inside an entitlement the org likely already holds for
   `premium-legal-hold-and-export` (eDiscovery Premium), with no separate meter (§10).
2. **The two-tool story (this scenario vs. `priority-cleanup-exchange-data-spillage`) needs to be a
   deliberate choice, not confusion about which to reach for.** A team that doesn't understand the
   hold-override distinction could pick the wrong tool for a held mailbox and believe an incident is
   closed when it isn't.
   - **Confirmed:** §10 puts the two tools side by side with the deciding factor (hold-override
     capability) stated plainly; §2's warning banner and §5 step 4 repeat the hand-off at the point a
     responder would actually need it, not just once in a comparison table.
3. **Governance of the destructive path is already least-privilege by design**, not left to a broad
   role grant: §3's prerequisites table recommends a custom role group scoped to just Compliance
   Search + Search And Purge + Case Management, rather than defaulting to full Organization
   Management membership, and the script itself requires two independent, named flags
   (`-PurgeType PermanentlyDelete` + `-ConfirmPermanentDelete`) before an irreversible action can
   fire.
4. **Incident-record hygiene is addressed, not assumed**: §8's change-management guidance (one case
   per incident, named to the incident ticket) keeps the audit trail scoped and reviewable, and
   `rollback.md` gives a clear close-vs-delete decision for the case record afterward.

No Fix/Fail raised — the initial draft already covered the material CISO-level risks; this pass
confirmed rather than found gaps.

---

## 🟦 Microsoft Product Owner

**Verdict: Pass**

1. **Correct, current API surface.** Built on the Graph `ediscoveryCase`/`ediscoverySearch`/
   `purgeData` resources (v1.0, non-preview), not the retired classic Content Search UI or its
   dedicated data-spillage walkthrough (both confirmed carrying the 2025-08-31 retirement banner
   during this build's own grounding pass) — `design.md` §2 goal 1.
2. **Follows this repo's own established automation-surface guidance** rather than reopening a path
   this repo already ruled out: `docs/automation-surface.md` §3 states app-only auth for eDiscovery
   S&C PowerShell cmdlets is unsupported by Microsoft, and this scenario is built on Graph for
   exactly that reason, matching its `premium-legal-hold-and-export` sibling.
3. **Enum values and cmdlet names verified directly against the Graph reference pages**, not
   guessed by analogy: `purgeType` (`recoverable`/`permanentlyDelete`), `purgeAreas`
   (`mailboxes`/`teamsMessages`), and the exact SDK cmdlet names
   (`New-MgSecurityCaseEdiscoveryCaseSearch`, `Invoke-MgEstimateSecurityCaseEdiscoveryCaseSearchStatistics`,
   `Clear-MgSecurityCaseEdiscoveryCaseSearchData`) all come from the cited Microsoft Learn pages
   verbatim.
4. **Right feature for the job, complementary rather than duplicative.** This scenario and
   `priority-cleanup-exchange-data-spillage` solve different halves of the same problem family
   (fast, non-hold-overriding containment vs. slow, hold-overriding permanent deletion) — the design
   explicitly cites Microsoft's own documented tip connecting the two rather than inventing an
   overlap.
5. **Accurate licensing**, derived correctly (not assumed): a Graph-created case is
   Premium-configured per Microsoft's own Standard-vs-Premium FAQ, so this scenario correctly cites
   the eDiscovery (Premium) E5/Suite/add-on tier rather than the cheaper Standard/E3 tier its
   PowerShell-only sibling path would use.
6. **One genuine gap correctly flagged as VERIFY, not asserted as fact:** whether a litigation hold
   suppresses `purgeData` identically to the documented PowerShell-path behavior — `README.md` §11
   and `design.md` §2 goal 5 state this as unconfirmed for the Graph action specifically, rather than
   assuming the two paths behave identically just because they likely share an underlying engine.

No Fix/Fail raised.

---

## Summary

| Lens | Initial verdict | Findings | Resolution |
|---|---|---|---|
| 🔴 Red Team | Fix | 3 (tenant-wide sweep blast radius; sensitive contentQuery persistence; purge ≠ full containment without message trace) | Closed |
| 🔵 Blue Team | Fix | 4 (no completion alerting — disclosed with a SIEM recommendation; case-wide not search-specific purge listing; inconsistent async-operation Location-header format across this repo — fixed with a shared helper; undocumented report-link lifetime) | Closed |
| 🎩 CISO | Pass | 0 new findings; funding rationale, tool-choice clarity, least-privilege governance, and incident-record hygiene all confirmed already addressed | — |
| 🟦 Microsoft Product Owner | Pass | 0 new findings; current non-retired API surface, correct enum/cmdlet grounding, complementary tool positioning, accurate Premium-tier licensing, and one honestly-flagged VERIFY all confirmed | — |

All Fix items are resolved in the current state of `README.md`, `design.md`,
`deploy/New-DataSpillageSearch.ps1`, `deploy/Invoke-DataSpillagePurge.ps1`,
`deploy/policy/data-spillage-search-definition.sample.json`,
`validate/Test-DataSpillageSearchAndPurge.ps1`, and `rollback.md`. No Fail items were raised. This
fragment meets the definition of done in `AGENTS.md` §9; product facts are grounded in Microsoft
Learn (no invented cmdlets — the litigation-hold-on-Graph-purgeData gap is disclosed as VERIFY, not
presented as confirmed), and the irreversibility of `PermanentlyDelete` is treated as the scenario's
central safety constraint throughout, mirrored by the double-flag gate in
`Invoke-DataSpillagePurge.ps1`.
