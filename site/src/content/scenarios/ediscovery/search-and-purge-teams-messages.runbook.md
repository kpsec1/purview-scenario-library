---
part: "runbook"
parent: "ediscovery/search-and-purge-teams-messages"
---
## Implementation steps

### PowerShell path

```powershell
# 1. Resolve target mailboxes first (not this scenario's job):
#    - Standard/shared channel -> parent team mailbox via
#      ../teams-group-hold-resolution/deploy/Resolve-TeamsGroupHoldLocations.ps1
#    - 1:1 / group chat -> the participants' own known mailbox addresses
#    - Private channel -> see README Section 11's VERIFY before relying on a single "dedicated mailbox"

# 2. Create (or find) the case and search, bind target mailboxes, then estimate.
./deploy/New-TeamsMessagePurgeSearch.ps1 -DefinitionPath ./deploy/policy/teams-message-purge-search-definition.sample.json `
    -AppId $AppId -TenantId $TenantId -CertificateThumbprint $Thumbprint -WhatIf

./deploy/New-TeamsMessagePurgeSearch.ps1 -DefinitionPath ./deploy/policy/teams-message-purge-search-definition.sample.json `
    -AppId $AppId -TenantId $TenantId -CertificateThumbprint $Thumbprint

# Review indexedItemCount / mailboxCount. If larger than expected, narrow the definition file's
# search.contentQuery (add a date range or distinctive keyword) and re-run (idempotent).

# 3. MANUAL, not scripted: identify and remove any hold or retention policy on every target
#    mailbox the estimate's Top Locations reported -- an active hold BLOCKS this purge entirely
#    (it does not just hide the item, unlike the mailbox sibling). Record which holds you removed
#    so you can reapply them in step 6.

# 4. Purge -- ALWAYS requires -ConfirmPermanentDelete, for EITHER -PurgeType value (README Section 2).
./deploy/Invoke-TeamsMessagePurge.ps1 -CaseId $caseId -SearchId $searchId -PurgeType Recoverable `
    -ConfirmPermanentDelete -AppId $AppId -TenantId $TenantId -CertificateThumbprint $Thumbprint -WhatIf

./deploy/Invoke-TeamsMessagePurge.ps1 -CaseId $caseId -SearchId $searchId -PurgeType Recoverable `
    -ConfirmPermanentDelete -AppId $AppId -TenantId $TenantId -CertificateThumbprint $Thumbprint

# 5. Validate.
./validate/Test-TeamsMessagePurgeSearchAndPurge.ps1 -DefinitionPath ./deploy/policy/teams-message-purge-search-definition.sample.json `
    -CaseId $caseId -AppId $AppId -TenantId $TenantId -CertificateThumbprint $Thumbprint

# 6. MANUAL, not scripted: reapply every hold/retention policy removed in step 3.
```

### Portal reference

The case and search are visible under **eDiscovery** in the
[Microsoft Purview portal](https://purview.microsoft.com). The portal's own
**Search** page flyout (**More → Purge data**) drives the identical `purgeData` action this
scenario's script calls, so a purge started in the portal is visible to, and re-checkable by,
`validate/Test-TeamsMessagePurgeSearchAndPurge.ps1`.

## Configuration reference

| Setting | Value this scenario uses | Notes |
|---|---|---|
| Search cmdlet | `New-MgSecurityCaseEdiscoveryCaseSearch` (`-BodyParameter`, `noncustodialSources@odata.bind`) | POST `.../ediscoveryCases/{id}/searches` |
| `contentQuery` | `kind:microsoftteams` -led KQL | Message kind condition value for Teams content - not `kind:im` (Skype for Business; matches Teams too but needs an exclusion clause) |
| Data sources | Explicit `noncustodialDataSource` per target mailbox (`userSource`, `email`) | No Teams-appropriate `allTenantMailboxes`-style blanket scope exists; the design notes |
| `dataSourceScopes` | `none` | Sources supplied explicitly via `noncustodialSources@odata.bind` instead |
| Estimate cmdlet | `Invoke-MgEstimateSecurityCaseEdiscoveryCaseSearchStatistics` | Same as the mailbox sibling; returns `indexedItemCount`/`mailboxCount` via the polled operation |
| Purge cmdlet | `Clear-MgSecurityCaseEdiscoveryCaseSearchData` | POST `.../searches/{id}/purgeData` |
| `purgeType` | `recoverable` or `permanentlyDelete` - **both permanently delete the user copy for Teams** | `-ConfirmPermanentDelete` required for both - why this matters, the design notes |
| `purgeAreas` | `teamsMessages` (hardcoded - this script never purges mailboxes) | The mailbox sibling's own `purgeAreas: mailboxes` remains that scenario's scope |
| Items purged per mailbox/location per run | **≤ 100** | Same documented ceiling as the mailbox sibling |
| Compliance-copy retention after purge | Retained ≥ 24 hours, then background-deleted (typically 1-7 days) | `SubstrateHolds` folder; reapplying a hold within the 24-hour window can preserve the compliance copy - but never the already-deleted user copy |
| Operation polling | `Get-MgSecurityCaseEdiscoveryCaseOperation` | Same pattern as the mailbox sibling |

## Operations and tuning

**KPIs / signals:** `indexedItemCount` trend per search; count of bound target mailboxes vs. the
number your incident's roster actually names (a mismatch means a mailbox is missing from the
definition file); purge operation `status`/`percentProgress`; time from search creation to first
purge. **Tuning:** narrow `contentQuery` the same way as the mailbox sibling - a distinctive keyword
or date range - before widening the target-mailbox list. **The hold-removal step is the single
biggest operational risk in this workflow**: forgetting to remove a hold means the purge silently
retains the content (Microsoft's own documented behavior - why this matters), and forgetting to **reapply** a
removed hold afterward is a preservation-duty gap this scenario cannot detect on its own; track both
steps explicitly in your incident runbook, not just in the script output. **SIEM integration:**
forward `ediscoveryCase` operation-completion events to Sentinel/SIEM, the same pattern this library's
other high-severity eDiscovery/DLM controls already use. **Change management:** one case per
incident, named to the incident ticket, matching the mailbox sibling's own guidance.

## Rollback and decommission

See the rollback runbook. Quick reference: **there is no recovery stage for the purged message itself** -
unlike the mailbox sibling's `Recoverable`-purge Stage 1, Teams offers no end-user or admin recovery
path once a purge succeeds. What remains reversible is process state: the search definition, the
case, and the holds you removed and must reapply.

## References

1. Find and delete Microsoft Teams chat messages in eDiscovery (data sources table, hold-removal
   requirement, role assignment, tombstone behavior, compliance-copy retention timing, Teams Connect
   Chat/self-chat exclusions) - <https://learn.microsoft.com/purview/edisc-search-teams-data>
2. ediscoverySearch: purgeData (Graph v1.0; `purgeType`/`purgeAreas`; permanent-deletion note for
   `teamsMessages`) - <https://learn.microsoft.com/graph/api/security-ediscoverysearch-purgedata>
3. Finding content in Microsoft Teams in eDiscovery (Teams content storage table; private-channel
   member-mailbox description) - <https://learn.microsoft.com/purview/edisc-search-teams>
4. Use the condition builder to create search queries in eDiscovery (Message kind condition, value
   `microsoftteams`) - <https://learn.microsoft.com/purview/edisc-condition-builder>
5. Feature reference for Content search (`kind:microsoftteams` KQL; `kind:im` Skype-for-Business
   caveat) - <https://learn.microsoft.com/purview/ediscovery-content-search-reference>
6. Create searches (Graph v1.0; `dataSourceScopes`, `custodianSources@odata.bind`,
   `noncustodialSources@odata.bind` worked example) - <https://learn.microsoft.com/graph/api/security-ediscoverycase-post-searches>
7. Create nonCustodialDataSources (Graph v1.0; `userSource`/`siteSource` dataSource shape) - <https://learn.microsoft.com/graph/api/security-ediscoverycase-post-noncustodialdatasources>
8. Add noncustodialDataSources (Graph v1.0; `$ref` bind to a search) - <https://learn.microsoft.com/graph/api/security-ediscoverysearch-post-noncustodialsources>
9. Assign eDiscovery permissions - <https://learn.microsoft.com/purview/edisc-permissions>
10. *Search-and-Purge for Data Spillage* - the mailbox-purge sibling this scenario
    completes; shares its case/search/estimate helper patterns and `Get-OperationIdFromLocation`
    Location-header handling.
11. *Microsoft Teams / Microsoft 365 Group Hold-Location Resolution* - resolves a Team/Microsoft 365 Group's own
    mailbox address, reused here for standard/shared-channel targets.
12. IT Admins - Private channels in Microsoft Teams (compliance-copy migration to the group mailbox;
    `Get-TenantPrivateChannelMigrationStatus`) - <https://learn.microsoft.com/microsoftteams/private-channels#compliance-copies-of-private-channel-messages>
13. Learn about retention for Microsoft Teams (`RecipientTypeDetails` mailbox-type table; `GroupMailbox`
    post-migration vs. `UserMailbox` before it, for Teams private channels) - <https://learn.microsoft.com/purview/retention-policies-teams#how-retention-works-with-microsoft-teams-messages>
14. Microsoft.Graph.Security module reference (full `EdiscoveryCaseSearchNoncustodialSource` and
    `EdiscoveryCaseNoncustodialDataSource` cmdlet index, confirming no typed `New-`/`Add-` cmdlet
    binds an existing source onto a search via `$ref`) - <https://learn.microsoft.com/powershell/module/microsoft.graph.security/>

> Re-verify all links and Graph SDK cmdlet names against current Microsoft Learn before a
> customer-facing deployment, and confirm each target private channel's own migration status via
> `Get-TenantPrivateChannelMigrationStatus`. This scenario treats every Teams purge as
> irreversible for the user copy; there is no "safe default" to fall back on the way the mailbox
> sibling has.