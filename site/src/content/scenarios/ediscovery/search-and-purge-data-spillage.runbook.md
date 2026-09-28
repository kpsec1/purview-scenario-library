---
part: "runbook"
parent: "ediscovery/search-and-purge-data-spillage"
---
## Implementation steps

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
[Microsoft Purview portal](https://purview.microsoft.com). The portal's own
**Search** page flyout (**More → Purge data**) drives the identical `purgeData` action this
scenario's script calls - both paths share the same object model, so a purge started in the portal
is visible to, and re-checkable by, `validate/Test-DataSpillageSearchAndPurge.ps1`.

## Configuration reference

| Setting | Value this scenario uses | Notes |
|---|---|---|
| Search cmdlet | `New-MgSecurityCaseEdiscoveryCaseSearch` | POST `.../ediscoveryCases/{id}/searches` |
| `contentQuery` | KQL (Keyword Query Language) | Same query language `New-ComplianceSearch -ContentMatchQuery` documents |
| `dataSourceScopes` | `allTenantMailboxes` (tenant-wide sweep) or a named custodian/source list | `allTenantMailboxes` matches the retired walkthrough's "unsure where the content resides" mode; narrow to named sources once recipients are known |
| Estimate cmdlet | `Invoke-MgEstimateSecurityCaseEdiscoveryCaseSearchStatistics` | POST `.../searches/{id}/estimateStatistics`; returns `indexedItemCount`/`mailboxCount` via the polled operation |
| Purge cmdlet | `Clear-MgSecurityCaseEdiscoveryCaseSearchData` | POST `.../searches/{id}/purgeData` |
| `purgeType` | `recoverable` (default) or `permanentlyDelete` | `recoverable` = soft-delete-equivalent; `permanentlyDelete` requires `-ConfirmPermanentDelete` too |
| `purgeAreas` | `mailboxes` | `teamsMessages` is out of scope here - see *Search-and-Purge for Microsoft Teams Messages*. **Correction:** an earlier version of this row described `teamsMessages` as "compliance-copy-only" (implying it's safer than a mailbox purge); current Microsoft Learn states the opposite for this Graph action - it permanently deletes the Teams user-visible message immediately, for either `purgeType` value. the design notes. |
| Items purged per mailbox per run | **≤ 100** | Premium-tier ceiling (a Graph-created case is Premium-configured); re-run to clear more |
| Operation polling | `Get-MgSecurityCaseEdiscoveryCaseOperation` | Same pattern as *Legal Hold, Collection, Review, and Export*'s `Wait-CaseOperation` helper |

## Operations and tuning

**KPIs / signals:** `indexedItemCount` trend per search (should trend to zero after a successful
purge cycle); `mailboxCount` (breadth of the spillage); purge operation `status`/`percentProgress`;
time from search creation to first purge (the incident-response SLA this scenario is built to keep
short). **Tuning:** the `contentQuery` is the single highest-leverage control, the same as
*Priority Cleanup for Exchange Data Spillage*'s `ContentMatchQuery` - start narrow (a distinctive
attachment name, subject phrase, or sender + tight date range) and widen only after confirming the
estimate's item/mailbox counts look right; a `dataSourceScopes: allTenantMailboxes` sweep with a
broad query risks false-positive purges. **Change management:** each incident should get its own
case (named per your incident-ticket convention) rather than reusing one long-lived "spillage" case,
so the audit trail stays scoped to one event. **SIEM integration:** forward `ediscoveryCase`
operation-completion events (via the audit log export pattern in the validation steps.3) to Sentinel/SIEM, the same as
this library's other high-severity eDiscovery/DLM controls. **Purge is not
the whole containment story:** removing an item from a mailbox says nothing about whether it was
already forwarded, downloaded, or synced to a PST before the purge ran - for a spillage incident with
external recipients or a wide internal blast radius, pair this scenario with **Message trace**
 (sender/date-range query, same as the retired walkthrough's own recommended
Step 5) to establish how far the content actually traveled before treating the incident as contained.

## Rollback and decommission

See the rollback runbook. Quick reference: a `Recoverable` purge can be undone by the **end user** via
Outlook's Recover Deleted Items until the mailbox's deleted-item retention period expires - this
scenario's scripts don't (and can't) restore it centrally. A `PermanentlyDelete` purge **cannot** be
undone by this scenario, the user, an admin, or Microsoft. Deleting the eDiscovery case removes the
search/operation records but never reverses a completed purge.

## References

1. eDiscovery solution series: Data spillage scenario - Search and purge (workflow concept; the priority-cleanup hand-off tip is cross-cited from source 9 below; retired 2025-08-31, 21Vianet-only) - <https://learn.microsoft.com/purview/ediscovery-data-spillage-search-and-purge>
2. Find and delete email messages in eDiscovery (current, non-retired guide: limits, litigation-hold FAQ, Standard-vs-Premium/PowerShell-vs-Graph item-count ceilings) - <https://learn.microsoft.com/purview/edisc-search-mailbox-data>
3. Overview of Content search (retirement caution banner, 2025-08-31) - <https://learn.microsoft.com/purview/ediscovery-content-search-overview>
4. eDiscovery solution series: Data spillage scenario - Search and purge (retirement caution banner) - <https://learn.microsoft.com/purview/ediscovery-data-spillage-search-and-purge>
5. New-ComplianceSearch (ContentMatchQuery/KQL reference; cited for query-language grounding, not as this scenario's execution path) - <https://learn.microsoft.com/powershell/module/exchangepowershell/new-compliancesearch>
6. ediscoverySearch: purgeData (Graph v1.0; `purgeType`/`purgeAreas`; Application permission `eDiscovery.ReadWrite.All`; Search And Purge role) - <https://learn.microsoft.com/graph/api/security-ediscoverysearch-purgedata>
7. Create ediscoverySearch (Graph v1.0; `displayName`/`contentQuery`/`dataSourceScopes`) - <https://learn.microsoft.com/graph/api/security-ediscoverycase-post-searches>
8. Find and delete email messages in eDiscovery - Step 3: Delete the message (soft-delete vs. hard-delete behavior and Warning banner) - <https://learn.microsoft.com/purview/edisc-search-mailbox-data#step-3-delete-the-message>
9. Expedite the permanent deletion of sensitive information from mailboxes (priority cleanup; the "first use eDiscovery search and purge... then apply the priority cleanup policy" tip) - <https://learn.microsoft.com/purview/priority-cleanup-exchange#the-end-user-experience-for-priority-cleanup>
10. Find and delete Microsoft Teams chat messages in eDiscovery (compliance-copy-vs-user-copy caveat for `purgeAreas: teamsMessages`) - <https://learn.microsoft.com/purview/edisc-search-teams-data>
11. ediscoveryEstimateOperation resource type (`indexedItemCount`, `mailboxCount` properties) - <https://learn.microsoft.com/graph/api/resources/security-ediscoveryestimateoperation>
12. ediscoverySearch: estimateStatistics (Graph v1.0 action reference) - <https://learn.microsoft.com/graph/api/security-ediscoverysearch-estimatestatistics>
13. ediscoveryPurgeDataOperation resource type (`status`, `purgeType`/`purgeAreas` value tables) - <https://learn.microsoft.com/graph/api/resources/security-ediscoverypurgedataoperation>
14. Message trace in the Security & Compliance Center (complementary "how far did the spillage travel" check, cited by the retired data-spillage walkthrough's own Step 5) - <https://learn.microsoft.com/microsoft-365/security/office-365-security/message-trace-scc>
15. reportFileMetadata resource type (`downloadUrl`/`fileName`/`size`; no expiry documented) - <https://learn.microsoft.com/graph/api/resources/security-ediscoveryreportfilemetadata>

> Re-verify all links, Graph SDK cmdlet names, and - especially - the litigation-hold VERIFY
> against current Microsoft Learn before a customer-facing deployment. This scenario deliberately
> defaults to the reversible purge type and never auto-repeats a purge, because a mailbox purge is a
> genuinely destructive operation even in its "recoverable" mode.