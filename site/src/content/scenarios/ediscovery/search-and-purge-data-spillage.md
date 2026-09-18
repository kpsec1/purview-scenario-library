---
title: "Search-and-Purge for Data Spillage"
fullTitle: "eDiscovery — Search-and-Purge for Data Spillage"
category: "eDiscovery"
categorySlug: "ediscovery"
slug: "search-and-purge-data-spillage"
repoPath: "scenarios/ediscovery/search-and-purge-data-spillage"
parts: ["design","deploy","validate","rollback"]
related: ["data-lifecycle-management/priority-cleanup-exchange-data-spillage","ediscovery/search-and-purge-teams-messages"]
deployCount: 3
validateCount: 1
---
## 1. Scenario summary

Scripts Microsoft Purview eDiscovery's **search-and-purge** capability — create a search, validate
what it found, then remove matching items from Exchange mailboxes — as code, via Microsoft Graph's
`ediscoveryCase`/`ediscoverySearch` resources. Soft-delete (`Recoverable`) by default; hard-delete
(`PermanentlyDelete`) only as an explicit, separately-confirmed choice.

**Who it's for:** a security/compliance responder who needs a confidential message out of
recipients' visible mailboxes **right now** — the common, fast-turnaround data-spillage case — with
a full audit trail of what was searched, estimated, and removed.

## 2. Business/regulatory driver

Data spillage — sensitive content emailed to the wrong recipients — is the exact use case Microsoft
documents this capability for: "quickly assess the size and locations of the spillage... and then
permanently purge the spilled data from the system" [[1]](#references). Most spillage incidents don't
involve a litigation hold or a multi-year retention policy; they need immediate containment with an
auditable record, not this repo's `priority-cleanup-exchange-data-spillage` sibling's slower,
three-approver, hold-overriding permanent deletion. This scenario is that faster, narrower tool —
and it explicitly hands off to the priority-cleanup sibling for the minority of cases where a hold
*is* in the way (§5, §11).

> ⚠️ **Purge does not override a hold.** On a mailbox with an active litigation hold, purge removes
> matching items from the user's *view* only — they are **not** permanently deleted
> [[2]](#references). If that's the outcome you need, see §5's hand-off to
> [`data-lifecycle-management/priority-cleanup-exchange-data-spillage`](/scenarios/data-lifecycle-management/priority-cleanup-exchange-data-spillage/). Hard-delete
> (`-PurgeType PermanentlyDelete`) is irreversible on a mailbox **without** a hold — validate the
> search estimate carefully before purging (§5, §7).

## 3. Prerequisites

Full licensing detail: `docs/licensing-matrix.md` §2 (eDiscovery (Premium) row — a Graph-created case
is Premium-configured; see `design.md` §3). RBAC: `docs/rbac-model.md` §4. Automation surface:
`docs/automation-surface.md` §3 (Microsoft Graph — the supported app-only path for eDiscovery
automation) and §7. Summary:

| Requirement | Minimum | Notes |
|---|---|---|
| Licensing | **eDiscovery (Premium)**: M365/Office 365 **E5**, **Microsoft Purview Suite**, or **E5 eDiscovery & Audit** add-on | `docs/licensing-matrix.md` §2; `design.md` §3 explains why a Graph-based case is Premium-tier |
| Role to create/run a search | **eDiscovery Manager** (own cases) or **eDiscovery Administrator** (all cases) — includes the **Compliance Search** role | `docs/rbac-model.md` §4 |
| Role to purge | **Search And Purge** — "the least privileged option for purging data," available by default only to **Organization Management** members | Grant the automation's service principal a **custom role group** with just Compliance Search + Search And Purge (+ Case Management, to create the case/search) rather than full Organization Management — least privilege |
| Graph permission | Application **`eDiscovery.ReadWrite.All`** | `docs/automation-surface.md` §3; confirmed against the `purgeData`/`searches` Graph reference pages [[6]](#references)[[7]](#references) |
| Auth | Certificate-based app-only via `Connect-MgGraph` | `docs/automation-surface.md` §3 |
| PowerShell module | `Microsoft.Graph.Security` ≥ 2.25.0 | Same module/version floor as `premium-legal-hold-and-export` |

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

Full rationale, including why this is built on Graph rather than the S&C PowerShell
`New-ComplianceSearchAction -Purge` path Microsoft's own current docs still show for interactive use:
`design.md` §2/§3.

## 5. Step-by-step implementation

### PowerShell path

```powershell
# 1. Create (or find) the case and search, then estimate - no mailbox content is touched yet.
./deploy/New-DataSpillageSearch.ps1 -DefinitionPath ./deploy/policy/data-spillage-search-definition.sample.json `
    -AppId $AppId -TenantId $TenantId -CertificateThumbprint $Thumbprint -WhatIf

./deploy/New-DataSpillageSearch.ps1 -DefinitionPath ./deploy/policy/data-spillage-search-definition.sample.json `
    -AppId $AppId -TenantId $TenantId -CertificateThumbprint $Thumbprint

# Output includes indexedItemCount / mailboxCount - review these before purging. If the count is
# larger than expected, refine the definition file's search.contentQuery and re-run (idempotent).

# 2. Purge - soft-delete (default, reversible by the user until retention expires)
./deploy/Invoke-DataSpillagePurge.ps1 -CaseId $caseId -SearchId $searchId -PurgeType Recoverable `
    -AppId $AppId -TenantId $TenantId -CertificateThumbprint $Thumbprint -WhatIf

./deploy/Invoke-DataSpillagePurge.ps1 -CaseId $caseId -SearchId $searchId -PurgeType Recoverable `
    -AppId $AppId -TenantId $TenantId -CertificateThumbprint $Thumbprint

# 3. Validate
./validate/Test-DataSpillageSearchAndPurge.ps1 -DefinitionPath ./deploy/policy/data-spillage-search-definition.sample.json `
    -CaseId $caseId -AppId $AppId -TenantId $TenantId -CertificateThumbprint $Thumbprint

# 4. Only if a mailbox is on hold and step 2's estimate/validation still shows the item present:
#    hand off to the priority-cleanup sibling, pointed at the same content (its own
#    ContentMatchQuery, written in KeyQL, targeting the same content this scenario's KQL
#    search.contentQuery matches).
../../data-lifecycle-management/priority-cleanup-exchange-data-spillage/deploy/New-PriorityCleanupExchangePolicy.ps1 `
    -ConfigPath <a config whose ContentMatchQuery matches this scenario's search.contentQuery> -Simulate

# 5. (Rare) irreversible hard-delete, on a mailbox confirmed NOT on hold, after reviewing the estimate:
./deploy/Invoke-DataSpillagePurge.ps1 -CaseId $caseId -SearchId $searchId -PurgeType PermanentlyDelete `
    -ConfirmPermanentDelete -AppId $AppId -TenantId $TenantId -CertificateThumbprint $Thumbprint
```

### Portal reference

The case and search are visible under **eDiscovery** in the
[Microsoft Purview portal](https://purview.microsoft.com) [[9]](#references). The portal's own
**Search** page flyout (**More → Purge data**) drives the identical `purgeData` action this
scenario's script calls — both paths share the same object model, so a purge started in the portal
is visible to, and re-checkable by, `validate/Test-DataSpillageSearchAndPurge.ps1`.

## 6. Configuration reference

| Setting | Value this scenario uses | Notes |
|---|---|---|
| Search cmdlet | `New-MgSecurityCaseEdiscoveryCaseSearch` | POST `.../ediscoveryCases/{id}/searches` [[7]](#references) |
| `contentQuery` | KQL (Keyword Query Language) | Same query language `New-ComplianceSearch -ContentMatchQuery` documents [[5]](#references) |
| `dataSourceScopes` | `allTenantMailboxes` (tenant-wide sweep) or a named custodian/source list | `allTenantMailboxes` matches the retired walkthrough's "unsure where the content resides" mode [[1]](#references); narrow to named sources once recipients are known |
| Estimate cmdlet | `Invoke-MgEstimateSecurityCaseEdiscoveryCaseSearchStatistics` | POST `.../searches/{id}/estimateStatistics`; returns `indexedItemCount`/`mailboxCount` via the polled operation [[11]](#references) |
| Purge cmdlet | `Clear-MgSecurityCaseEdiscoveryCaseSearchData` | POST `.../searches/{id}/purgeData` [[6]](#references) |
| `purgeType` | `recoverable` (default) or `permanentlyDelete` | `recoverable` = soft-delete-equivalent; `permanentlyDelete` requires `-ConfirmPermanentDelete` too |
| `purgeAreas` | `mailboxes` | `teamsMessages` is out of scope here — see [`ediscovery/search-and-purge-teams-messages`](/scenarios/ediscovery/search-and-purge-teams-messages/). **Correction:** an earlier version of this row described `teamsMessages` as "compliance-copy-only" (implying it's safer than a mailbox purge); current Microsoft Learn states the opposite for this Graph action — it permanently deletes the Teams user-visible message immediately, for either `purgeType` value. `design.md` §8. |
| Items purged per mailbox per run | **≤ 100** | Premium-tier ceiling (a Graph-created case is Premium-configured); re-run to clear more [[2]](#references) |
| Operation polling | `Get-MgSecurityCaseEdiscoveryCaseOperation` | Same pattern as `premium-legal-hold-and-export`'s `Wait-CaseOperation` helper |

## 7. Validation / how to prove it works

1. **Automated (object-level)** — `./validate/Test-DataSpillageSearchAndPurge.ps1` confirms the case
   and search exist, reports the latest `estimateStatistics` result, lists every `purgeData`
   operation against the search with its status, and warns if the most recent purge operation is
   still `running`/`notStarted`. Exits non-zero on a `failed`/`submissionFailed` purge operation.
2. **Re-run the search's estimate** — a falling `indexedItemCount` across successive
   `New-DataSpillageSearch.ps1` runs after a purge is the direct evidence content was actually
   removed (mirrors the retired walkthrough's own Step 8 verification pattern of re-running the same
   query and confirming no results [[1]](#references)).
3. **Audit** — search the unified audit log for the eDiscovery search/purge activity; see
   `docs/rbac-model.md` §4 and `premium-legal-hold-and-export`'s own
   `Export-EdiscoveryAuditTrail.ps1` for the audit-log query pattern this repo already uses for
   eDiscovery case-lifecycle events (RecordType `Discovery`).
4. **Idempotency proof** — re-run `New-DataSpillageSearch.ps1`; the case/search report `exists`, not
   `created`.

## 8. Operations & tuning

**KPIs / signals:** `indexedItemCount` trend per search (should trend to zero after a successful
purge cycle); `mailboxCount` (breadth of the spillage); purge operation `status`/`percentProgress`;
time from search creation to first purge (the incident-response SLA this scenario is built to keep
short). **Tuning:** the `contentQuery` is the single highest-leverage control, the same as
`priority-cleanup-exchange-data-spillage`'s `ContentMatchQuery` — start narrow (a distinctive
attachment name, subject phrase, or sender + tight date range) and widen only after confirming the
estimate's item/mailbox counts look right; a `dataSourceScopes: allTenantMailboxes` sweep with a
broad query risks false-positive purges. **Change management:** each incident should get its own
case (named per your incident-ticket convention) rather than reusing one long-lived "spillage" case,
so the audit trail stays scoped to one event. **SIEM integration:** forward `ediscoveryCase`
operation-completion events (via the audit log export pattern in §7.3) to Sentinel/SIEM, the same as
this repo's other high-severity eDiscovery/DLM controls (see `reviews.md`, Blue Team). **Purge is not
the whole containment story:** removing an item from a mailbox says nothing about whether it was
already forwarded, downloaded, or synced to a PST before the purge ran — for a spillage incident with
external recipients or a wide internal blast radius, pair this scenario with **Message trace**
[[14]](#references) (sender/date-range query, same as the retired walkthrough's own recommended
Step 5) to establish how far the content actually traveled before treating the incident as contained.

## 9. Rollback / decommission

See `rollback.md`. Quick reference: a `Recoverable` purge can be undone by the **end user** via
Outlook's Recover Deleted Items until the mailbox's deleted-item retention period expires — this
scenario's scripts don't (and can't) restore it centrally. A `PermanentlyDelete` purge **cannot** be
undone by this scenario, the user, an admin, or Microsoft. Deleting the eDiscovery case removes the
search/operation records but never reverses a completed purge.

## 10. Cost & licensing notes

- **eDiscovery (Premium)** entitlement (E5/Suite/add-on) — no separate per-search or per-purge meter.
- **The real cost is process, not the meter**: a documented incident record (one case per spillage
  event), a reviewed estimate before every purge, and — for `PermanentlyDelete` — a second,
  deliberate confirmation.
- Compare against `priority-cleanup-exchange-data-spillage` before choosing a tool: this scenario is
  faster and narrower (no multi-approver workflow) but **cannot** override a hold; that sibling is
  slower (up to 7 days to match, multi-stage approval) but can.

## 11. Known limitations & gotchas

- **Does not override litigation holds or retention policies.** See §2's warning and `design.md` §6.
  Chain to `priority-cleanup-exchange-data-spillage` for held content.
- **100 items per mailbox per run.** Repeat the purge to clear more; this is a documented Microsoft
  limit, not a bug in this scenario's scripts [[2]](#references).
- **Doesn't purge Microsoft Teams messages**, even though `purgeAreas: teamsMessages` exists on the
  same Graph action — deliberately out of scope; see `scenarios/ediscovery/
  search-and-purge-teams-messages/` for that sibling scenario. **Correction (superseding this
  scenario's own earlier text):** Teams purge is not "compliance-copy-only" as previously stated
  here — Microsoft's `purgeData` reference states that either `purgeType` value permanently deletes
  the Teams user-visible message immediately when `purgeAreas` is `teamsMessages`, a *more*
  consequential guarantee than this scenario's own `Recoverable` mailbox purge, not a lesser one.
  See that sibling's `design.md` §2 for the full re-grounding.
- **`PermanentlyDelete` is irreversible** for a mailbox not on hold. Always review the
  `estimateStatistics` output first; there is no "undo."
- **VERIFY (pilot tenant):** whether a mailbox on litigation hold behaves identically for the Graph
  `purgeData` action as Microsoft's FAQ documents for the PowerShell `New-ComplianceSearchAction
  -Purge` path (items only hidden from view, not deleted, regardless of `purgeType`) — both paths
  share the same underlying eDiscovery search/purge engine, but no Microsoft Learn page independently
  confirms the hold behavior specifically for the Graph `purgeData` action. `design.md` §2 goal 5 and
  `deploy/Invoke-DataSpillagePurge.ps1`'s `.NOTES` flag this rather than assuming it by analogy.
- **The `contentQuery` itself can carry the spilled data** (a distinctive phrase, attachment name, or
  keyword drawn from the leaked content) and persists on the search object for the life of the case —
  a second, smaller exposure surface visible to anyone with read access to the case. `rollback.md`
  Stage 2 (delete the search once the incident is closed) and the sample config's own `_comment` flag
  this; treat the definition file and the live search object as sensitive for the incident's duration.
- **`purgeData`'s prior-operations listing is case-wide, not search-specific.** Neither
  `Invoke-DataSpillagePurge.ps1 -ListOnly` nor `validate/Test-DataSpillageSearchAndPurge.ps1` can
  confirm which search a given `purgeData` operation targeted — `caseOperation` doesn't expose that
  link without a further, undocumented expand. In a case with more than one active search, cross-check
  timing/context manually before assuming a listed purge operation belongs to the search you're
  reviewing.
- **VERIFY:** how long a purge job report's `reportFileMetadata.downloadUrl`
  (`Invoke-DataSpillagePurge.ps1`'s printed proof-of-purge link) remains valid before expiring — not
  stated on the `ediscoveryPurgeDataOperation` reference page. Download and archive the report
  promptly with the case record rather than relying on it staying reachable indefinitely.
- **The classic "Data spillage scenario: Search and purge" walkthrough is retired** (2025-08-31,
  21Vianet-only now) [[3]](#references) — this scenario's workflow shape (search → validate → purge →
  verify) is re-derived from it for concept only; every cmdlet/API call is grounded in current,
  non-retired references (§12).
- **Illustrative values.** The case name, query, and mailbox scope in the sample config are
  placeholders — replace with the real, confirmed spillage details before use.

## 12. References

1. eDiscovery solution series: Data spillage scenario - Search and purge (workflow concept; the priority-cleanup hand-off tip is cross-cited from source 9 below; retired 2025-08-31, 21Vianet-only) — <https://learn.microsoft.com/purview/ediscovery-data-spillage-search-and-purge>
2. Find and delete email messages in eDiscovery (current, non-retired guide: limits, litigation-hold FAQ, Standard-vs-Premium/PowerShell-vs-Graph item-count ceilings) — <https://learn.microsoft.com/purview/edisc-search-mailbox-data>
3. Overview of Content search (retirement caution banner, 2025-08-31) — <https://learn.microsoft.com/purview/ediscovery-content-search-overview>
4. eDiscovery solution series: Data spillage scenario - Search and purge (retirement caution banner) — <https://learn.microsoft.com/purview/ediscovery-data-spillage-search-and-purge>
5. New-ComplianceSearch (ContentMatchQuery/KQL reference; cited for query-language grounding, not as this scenario's execution path) — <https://learn.microsoft.com/powershell/module/exchangepowershell/new-compliancesearch>
6. ediscoverySearch: purgeData (Graph v1.0; `purgeType`/`purgeAreas`; Application permission `eDiscovery.ReadWrite.All`; Search And Purge role) — <https://learn.microsoft.com/graph/api/security-ediscoverysearch-purgedata>
7. Create ediscoverySearch (Graph v1.0; `displayName`/`contentQuery`/`dataSourceScopes`) — <https://learn.microsoft.com/graph/api/security-ediscoverycase-post-searches>
8. Find and delete email messages in eDiscovery — Step 3: Delete the message (soft-delete vs. hard-delete behavior and Warning banner) — <https://learn.microsoft.com/purview/edisc-search-mailbox-data#step-3-delete-the-message>
9. Expedite the permanent deletion of sensitive information from mailboxes (priority cleanup; the "first use eDiscovery search and purge... then apply the priority cleanup policy" tip) — <https://learn.microsoft.com/purview/priority-cleanup-exchange#the-end-user-experience-for-priority-cleanup>
10. Find and delete Microsoft Teams chat messages in eDiscovery (compliance-copy-vs-user-copy caveat for `purgeAreas: teamsMessages`) — <https://learn.microsoft.com/purview/edisc-search-teams-data>
11. ediscoveryEstimateOperation resource type (`indexedItemCount`, `mailboxCount` properties) — <https://learn.microsoft.com/graph/api/resources/security-ediscoveryestimateoperation>
12. ediscoverySearch: estimateStatistics (Graph v1.0 action reference) — <https://learn.microsoft.com/graph/api/security-ediscoverysearch-estimatestatistics>
13. ediscoveryPurgeDataOperation resource type (`status`, `purgeType`/`purgeAreas` value tables) — <https://learn.microsoft.com/graph/api/resources/security-ediscoverypurgedataoperation>
14. Message trace in the Security & Compliance Center (complementary "how far did the spillage travel" check, cited by the retired data-spillage walkthrough's own Step 5) — <https://learn.microsoft.com/microsoft-365/security/office-365-security/message-trace-scc>

> Re-verify all links, Graph SDK cmdlet names, and — especially — the litigation-hold VERIFY (§11)
> against current Microsoft Learn before a customer-facing deployment. This scenario deliberately
> defaults to the reversible purge type and never auto-repeats a purge, because a mailbox purge is a
> genuinely destructive operation even in its "recoverable" mode.
