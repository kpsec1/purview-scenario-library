---
part: "design"
parent: "ediscovery/search-and-purge-data-spillage"
---
## 1. Problem statement

A confidential document (an internal legal memo, in this scenario's worked example) was emailed to
recipients who should never have received it. The exposure needs to end **now**, not after a
retention period lapses — but unlike this repo's `priority-cleanup-exchange-data-spillage` sibling
(a slow, multi-approval, 7-day-propagation control built for the small number of spillage incidents
that need a hold-overriding, fully audited permanent deletion), most spillage incidents are simpler:
the recipient mailboxes aren't on hold, and the goal is immediate containment — get the message out
of the recipients' visible mailboxes right away, with a full audit trail of what was searched, found,
and removed. **eDiscovery search-and-purge** is Microsoft's purpose-built tool for exactly this case
[[1]](#references)[[2]](#references). This scenario builds that tool as code: create a search, review
and validate what it found, then purge it — soft-delete by default, hard-delete only as an explicit,
separately-flagged choice.

## 2. Design goals

1. **Script the current mechanism, not the retired one.** Microsoft retired all classic eDiscovery
   experiences — including the classic Content Search tool and the dedicated "Data spillage
   scenario: Search and purge" walkthrough this item's own follow-up note pointed at — on
   2025-08-31; both pages now carry a caution banner restricting their guidance to organizations
   hosted by 21Vianet (China) [[3]](#references)[[4]](#references). This scenario is built entirely
   on the **current, non-retired mechanism**: the `New-ComplianceSearch`/`New-ComplianceSearchAction`
   family's underlying capability, re-exposed for the new (case-based) eDiscovery experience through
   **Microsoft Graph's `ediscoverySearch` resource and its `purgeData` action**
   [[5]](#references)[[6]](#references)[[7]](#references) — the same object model this repo's
   `premium-legal-hold-and-export` sibling already uses for holds and exports.
2. **Follow this repo's own automation-surface guidance.** `docs/automation-surface.md` §3 already
   states, from building the `premium-legal-hold-and-export` sibling, that app-only authentication
   for eDiscovery cmdlets in Security & Compliance PowerShell is explicitly unsupported by Microsoft,
   and that Graph is the intended, fully-supported app-only path for eDiscovery automation. This
   scenario follows that guidance rather than reopening the S&C PowerShell
   `New-ComplianceSearchAction -Purge` path Microsoft's own current documentation still describes —
   that path remains valid for an **interactive, delegated** admin session (and is cited here for
   context, since it's what most of Microsoft's own current prose examples show), but this repo never
   builds unattended automation on it.
3. **Split discovery from destruction into two scripts.** `New-DataSpillageSearch.ps1` (find search,
   review, validate — safe to run repeatedly) is separate from `Invoke-DataSpillagePurge.ps1`
   (irreversible for `PermanentlyDelete`, meaningfully consequential even for the default
   `Recoverable` mode). No single command path can go from "define a query" to "content is gone"
   without a human reading the estimate in between — the same two-stage discipline
   `priority-cleanup-exchange-data-spillage` already uses (simulate, then a separate,
   deliberately-invoked enforcement step).
4. **Default to the reversible purge type.** `-PurgeType Recoverable` (Graph's soft-delete-equivalent
   [[6]](#references)) is the default; `PermanentlyDelete` requires an explicit switch and a second,
   named confirmation parameter (`-ConfirmPermanentDelete`) — mirroring Microsoft's own documentation,
   which flags hard-delete with a Warning banner that soft-delete doesn't carry
   [[8]](#references).
5. **Be honest about what this scenario cannot do: override a hold.** Search-and-purge is explicitly
   **not** a hold-overriding control — Microsoft's own FAQ states that on a mailbox with a litigation
   hold, purge "isn't supported... only 10 items are removed from view of the user. These 10 items
   aren't permanently deleted" [[2]](#references), and separately recommends **Priority Cleanup** as
   the tool for removing held content [[2]](#references). This scenario's README states that limit
   plainly and hands off to the already-built `priority-cleanup-exchange-data-spillage` sibling for
   held mailboxes, rather than silently reimplementing or ignoring it.

## 3. Why Graph, and what that implies about licensing

Microsoft's current guidance distinguishes two purge paths by how the underlying eDiscovery case was
configured, not by which API the operator personally prefers [[2]](#references):

| | Case not configured for eDiscovery Premium | Case configured for eDiscovery Premium |
|---|---|---|
| Purge via | PowerShell only | PowerShell **or** Graph |
| Max items purged per mailbox per run | 10 | 100 |
| Minimum licensing | eDiscovery (Standard) — included in **E3** | eDiscovery (Premium) — **E5**, Suite, or the E5 eDiscovery & Audit add-on |

A case created through the Graph `ediscoveryCase`/`ediscoverySearch` resources (this scenario's
mechanism, and the only Graph-based case type Microsoft documents) is a **Premium-configured** case
— so this scenario inherits the 100-item-per-mailbox-per-run ceiling, not the 10-item Standard
ceiling, and requires **eDiscovery (Premium)** licensing (`docs/licensing-matrix.md` §2), the same
tier `premium-legal-hold-and-export` already documents. Re-run `Invoke-DataSpillagePurge.ps1` (safe —
see §5) if a mailbox has more than 100 matching items.

## 4. Architecture

```mermaid
sequenceDiagram
    participant Op as Operator
    participant Search as New-DataSpillageSearch.ps1
    participant Purge as Invoke-DataSpillagePurge.ps1
    participant Graph as Microsoft Graph (ediscoveryCase)
    participant Mbx as Exchange mailboxes

    Op->>Search: -DefinitionPath (case + search: contentQuery, dataSourceScopes)
    Search->>Graph: POST /ediscoveryCases (find-or-create)
    Search->>Graph: POST .../searches (find-or-create)
    Search->>Graph: POST .../searches/{id}/estimateStatistics
    Graph-->>Search: indexedItemCount, mailboxCount (poll operation)
    Search-->>Op: Report - review before purging (no mutation of mailbox content)

    Op->>Purge: -CaseId -SearchId -PurgeType Recoverable|PermanentlyDelete
    Purge->>Graph: POST .../searches/{id}/purgeData {purgeType, purgeAreas: mailboxes}
    Graph->>Mbx: Remove matching items (<=100/mailbox/run; skips items under litigation hold)
    Graph-->>Purge: 202 Accepted + Location (ediscoveryPurgeDataOperation) - poll to completion

    Note over Mbx: Held mailboxes: items only hidden from view, NOT deleted.<br/>Chain to priority-cleanup-exchange-data-spillage for those.
```

## 5. Idempotency and safety posture

- **Search creation** is create-or-report by `displayName` within the case, identical to the
  `premium-legal-hold-and-export` sibling's pattern — re-running `New-DataSpillageSearch.ps1` never
  duplicates a search or case.
- **`estimateStatistics`** is safe to re-run any number of times — it only reads.
- **`purgeData` is deliberately NOT idempotent-by-skip.** Unlike this repo's `addToReviewSet`/export
  idempotency checks (which skip a repeat call once one has already succeeded), a second purge run
  against the same search is a legitimate, Microsoft-documented pattern — items beyond the
  100-per-mailbox ceiling, or new items matched after the search re-runs against updated content, are
  only removed by repeating the purge [[2]](#references). `Invoke-DataSpillagePurge.ps1` therefore
  lists prior purge operations against the search (for audit-trail awareness) but never auto-skips —
  every invocation is a deliberate, individually-confirmed action, gated behind `-WhatIf` and (for
  `PermanentlyDelete`) the extra `-ConfirmPermanentDelete` switch.
- **No default-on path.** Both scripts require an explicit `-PurgeType`; there is no parameterless
  "just purge everything the search finds" invocation.

## 6. The litigation-hold gap and the priority-cleanup hand-off

Microsoft's own tip, published directly on the `priority-cleanup-exchange` page this repo's sibling
scenario is grounded in, describes exactly the workflow this scenario completes:

> "If you prefer end users to not see the retention message, you can achieve this by first using
> eDiscovery search and purge that soft-deletes items. When that completes, then apply the priority
> cleanup policy to permanently delete the soft deleted items." [[1]](#references)

That is: for a mailbox **not** on hold, this scenario's `-PurgeType Recoverable` run is often
sufficient on its own — the item moves out of the visible mailbox immediately. For a mailbox **on**
hold or under a retention policy, `Recoverable` only hides the item from the user (per §2 goal 5);
finishing the job requires the already-built `priority-cleanup-exchange-data-spillage` sibling,
pointed at the same content via its own `ContentMatchQuery` (KeyQL — the same search index this
scenario's `contentQuery` (KQL) targets, per Microsoft's own cross-reference between the two features
[[9]](#references)). This scenario's README §5 documents that two-step sequence explicitly rather
than leaving it as an implied follow-up, closing the gap `priority-cleanup-exchange-data-spillage
design.md` §7 originally flagged as blocked on "no eDiscovery search-and-purge scenario exists yet in
this repo."

## 7. Key decisions

| Decision | Choice | Rationale |
|---|---|---|
| API surface | Microsoft Graph (`ediscoveryCase`/`ediscoverySearch`/`purgeData`), not S&C PowerShell | `docs/automation-surface.md` §3: app-only auth for eDiscovery S&C PowerShell cmdlets is unsupported by Microsoft |
| Script split | Search+estimate vs. purge, two separate scripts | No single command path can purge without a human reviewing the estimate first |
| Default purge type | `Recoverable` (soft-delete-equivalent) | Matches Microsoft's own Warning-banner treatment of hard-delete; conservative default per this repo's precedent |
| Hard-delete gate | `-PurgeType PermanentlyDelete` **and** `-ConfirmPermanentDelete` both required | Two independent, deliberate flags for the one truly irreversible path |
| Idempotency (purge) | Never auto-skip a repeat purge | Re-running is the documented way to clear >100 items/mailbox or newly matched content |
| Scope | `purgeAreas: mailboxes` only; Teams messages explicitly out of scope | A materially different, separately-scoped capability documented on its own page [[10]](#references) — built as [`ediscovery/search-and-purge-teams-messages`](/scenarios/ediscovery/search-and-purge-teams-messages/). **Correction:** this row previously justified the scoping decision by describing Teams purge as "compliance-copy-only"; that sibling scenario's own re-grounding found the opposite is true for the Graph action — Teams purge is *more* consequential (immediate, unconditional deletion of the user-visible message), not less. The scoping decision (a separate scenario) still stands; the reason has been corrected |
| Held-mailbox handling | Document the gap; hand off to `priority-cleanup-exchange-data-spillage` | Search-and-purge cannot override a hold by design; re-implementing that override here would duplicate a control this repo already built and reviewed |
| Licensing | eDiscovery (Premium), not Standard | A Graph-created case is a Premium-configured case; 100-item/mailbox ceiling, not 10 |

## 8. Non-goals

- **Microsoft Teams message purge** (`purgeAreas: teamsMessages`) — a materially different capability
  documented on its own page [[10]](#references), now built as `scenarios/ediscovery/
  search-and-purge-teams-messages/`; not folded in here to avoid the false impression that this
  scenario's default `Recoverable` purge behaves the same way for Teams content that it does for
  mail. **Correction:** this non-goal's original rationale described Teams purge as "compliance-copy-
  only deletion, no true hide-from-user soft-delete equivalent" — i.e. safer than this scenario's own
  mailbox purge. The sibling scenario's own grounding pass found current Microsoft Learn states the
  opposite: for the Graph `purgeData` action, either `purgeType` value permanently deletes the Teams
  user-visible message immediately, with no reversible mode at all — *more* consequential than this
  scenario's `Recoverable` default, not less. The compliance-copy-only behavior applies only to the
  legacy, cmdlet-based purge path, which Microsoft's own current guidance says to avoid for Teams.
- **Overriding litigation holds or retention policies** — by design, not a gap; see §6.
- **SharePoint/OneDrive content** — `purgeData`'s documented scope is Exchange mailboxes and Teams
  messages only; SharePoint/OneDrive spillage needs a different remediation path (file deletion/
  versioning), out of scope here.
- **Custodian-based, litigation-style collection** — this scenario uses `dataSourceScopes:
  allTenantMailboxes` or a named mailbox list for a fast incident-response sweep, not
  `premium-legal-hold-and-export`'s custodian/hold model, which is a different lifecycle stage
  (litigation preservation, not spillage remediation).

## References

See `README.md` §12 for the full, numbered source list shared with this file.
