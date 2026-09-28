---
part: "runbook"
parent: "ediscovery/gdpr-dsr-fulfillment"
---
## Implementation steps

### PowerShell path

```powershell
# 1. Intake - creates the case/custodian/userSource/search, computes SLA dates, writes the ledger.
# -WhatIf first: reports every Graph action and the ledger write, mutates nothing.
./deploy/New-DsrRequest.ps1 -DefinitionPath ./deploy/policy/dsr-request-definition.sample.json `
    -AppId $AppId -TenantId $TenantId -CertificateThumbprint $Thumbprint -WhatIf

./deploy/New-DsrRequest.ps1 -DefinitionPath ./deploy/policy/dsr-request-definition.sample.json `
    -AppId $AppId -TenantId $TenantId -CertificateThumbprint $Thumbprint

# 1b. (Optional, Access/Portability where completeness matters) also search tenant-wide for
# messages ABOUT the data subject stored in other people's mailboxes -- content the primary
# custodian-scoped search cannot see (the Red Team review, finding 1):
./deploy/New-DsrRequest.ps1 -DefinitionPath ./deploy/policy/dsr-request-definition.sample.json `
    -AppId $AppId -TenantId $TenantId -CertificateThumbprint $Thumbprint -IncludeParticipantSearch

# 2. Review the search results (portal or Graph) before choosing a fulfillment path.

# 3a. Access or Portability - hand off to the review-set/export sibling, pointed at this case/search:
../premium-legal-hold-and-export/deploy/New-EdiscoverySearchReviewSetExport.ps1 `
    -CaseId $caseId -SearchId $searchId -AppId $AppId -TenantId $TenantId `
    -CertificateThumbprint $Thumbprint -WhatIf
../premium-legal-hold-and-export/deploy/Get-EdiscoveryExportPackage.ps1 `
    -CaseId $caseId -ExportOperationId $exportOpId -AppId $AppId -TenantId $TenantId `
    -CertificateThumbprint $Thumbprint

# 3b. Erasure - hand off to the search-and-purge sibling, pointed at this case/search:
../search-and-purge-data-spillage/deploy/Invoke-DataSpillagePurge.ps1 `
    -CaseId $caseId -SearchId $searchId -PurgeType Recoverable `
    -AppId $AppId -TenantId $TenantId -CertificateThumbprint $Thumbprint -WhatIf

# 3c. Rectification / Restriction / Objection - no script; correct the record in its system of
# record, or make the licensing/service decision the Discovery search's results inform.

# 4. Update the ledger's Status as the request progresses, and/or record an extension:
./deploy/New-DsrRequest.ps1 -DefinitionPath ./deploy/policy/dsr-request-definition.sample.json `
    -AppId $AppId -TenantId $TenantId -CertificateThumbprint $Thumbprint `
    -Status Fulfilled

./deploy/New-DsrRequest.ps1 -DefinitionPath ./deploy/policy/dsr-request-definition.sample.json `
    -AppId $AppId -TenantId $TenantId -CertificateThumbprint $Thumbprint `
    -ApplyExtension -ExtensionReason 'High request volume this quarter - Article 12(3)'

# 5. SLA check (run ad hoc or on a schedule) - reports every open request's days-remaining/overdue
# status; exits non-zero on any breach.
./validate/Test-DsrRequest.ps1 -AppId $AppId -TenantId $TenantId -CertificateThumbprint $Thumbprint
```

### Portal reference

The case, custodian, userSource, and search are all visible under **eDiscovery** in the
[Microsoft Purview portal](https://purview.microsoft.com), using the identical
object model `New-DsrRequest.ps1` drives via Graph - a request can be reconciled in either
direction. There is **no portal "DSR case" button** in the current experience (section 2 of the design notes
explains why); a DSR case looks like any other eDiscovery case with one custodian.

## Configuration reference

| Setting | Value this scenario uses | Notes |
|---|---|---|
| Custodian cmdlet | `New-MgSecurityCaseEdiscoveryCaseCustodian` | POST `.../custodians`, `email` |
| Custodian userSource | `New-MgSecurityCaseEdiscoveryCaseCustodianUserSource` | `includedSources = 'mailbox, site'` - same combined-string form *Legal Hold, Collection, Review, and Export* uses; its own open VERIFY on whether this exact form is accepted applies unchanged |
| Hold | **Never applied** | Deliberate - the design notes |
| Search cmdlet | `New-MgSecurityCaseEdiscoveryCaseSearch` | `dataSourceScopes = 'allCaseCustodians'`, `contentQuery` optional and empty by default |
| Participant search (optional, `-IncludeParticipantSearch`) | Same cmdlet, second search | `dataSourceScopes = 'allTenantMailboxes'`, `contentQuery = "participants:<email>"` - catches messages about the data subject in other people's mailboxes; off by default (blast-radius tradeoff, the Red Team review, finding 1) |
| Request types | `Access`, `Portability`, `Erasure`, `Rectification`, `Restriction`, `Objection` | This scenario's own enum, mapped to GDPR Articles 15/20/17/16/18/21 respectively - not a Microsoft-defined type |
| SLA due date | `receivedDate` + 1 calendar month | GDPR Article 12(3) baseline |
| SLA extended due date | `receivedDate` + 3 calendar months | If the two-further-months extension is invoked; the data subject must be notified, with reasons, **within the original month** - this scenario records that the extension was applied, it does not send the notice |
| Fulfillment (Access/Portability) | Hand off to `premium-legal-hold-and-export/deploy/New-EdiscoverySearchReviewSetExport.ps1` + `Get-EdiscoveryExportPackage.ps1` | the design notes |
| Fulfillment (Erasure) | Hand off to `search-and-purge-data-spillage/deploy/Invoke-DataSpillagePurge.ps1` | Inherits that sibling's litigation-hold gap and *Priority Cleanup for Exchange Data Spillage* hand-off unchanged |
| Fulfillment (Rectification/Restriction/Objection) | None - manual/process | the design notes |
| Ledger | `deploy/dsr-ledger.json` (JSON array, one record per `requestId`) | This scenario's own state, not a Microsoft object - the design notes |

## Operations and tuning

**KPIs / signals:** open-request count by SLA status (OnTrack/DueSoon/Overdue) from
`Test-DsrRequest.ps1`'s output; time-to-fulfillment per request type; extension-invocation rate
(a rising rate across many requests is itself a signal worth reporting to the DPO - Article 12(3)
frames the extension as conditional on "complexity and number of the requests," not a routine
buffer). **Tuning:** if DSR volume is high enough that manually invoking `Test-DsrRequest.ps1` isn't
enough, schedule it (a cron job / scheduled task / Azure Automation runbook calling it with
`-AppId`/`-TenantId`/`-CertificateThumbprint`) and route its non-zero exit code to your
ticketing/alerting system - the script's `[FAIL]`/`[WARN]` lines are already structured enough to
parse. **Identity verification is out of scope but load-bearing:** this scenario assumes the
operator has already verified the requester's identity before running `New-DsrRequest.ps1` - a
custodian-scoped search created for the wrong person is itself a data-minimization problem.
**Change management:** one request, one `requestId`, one case - do not reuse a case across multiple
data subjects' requests, even if they arrive close together, since `allCaseCustodians` scoping and
the ledger's per-request SLA tracking both assume a 1:1 case-to-request mapping.

## Rollback and decommission

See the rollback runbook. Quick reference: closing or deleting the eDiscovery case follows the same
options *Search-and-Purge for Data Spillage* and *Legal Hold, Collection, Review, and Export*
already document; the ledger entry should be retained per the organization's own DSR
record-keeping/accountability policy (Article 5(2)) even after the case itself is closed, since it
is the only record of when the request was received and answered.

## References

1. Art. 12 GDPR - Transparent information, communication and modalities for the exercise of the rights of the data subject (one-month/two-further-months response timeline) - <https://gdpr-info.eu/art-12-gdpr/>
2. Art. 20 GDPR - Right to data portability (structured, commonly used, machine-readable format requirement) - <https://gdpr-info.eu/art-20-gdpr/>
3. Data Subject Requests for the GDPR and CCPA (the six DSR activities: Discovery, Access, Rectification, Restriction, Export, Deletion) - <https://learn.microsoft.com/en-us/compliance/regulatory/gdpr-data-subject-requests>
4. Office 365 Data Subject Requests Under the GDPR and CCPA (Exchange mailboxes/public folders, SharePoint, OneDrive as the searchable locations) - <https://learn.microsoft.com/en-us/compliance/regulatory/gdpr-dsr-office365>
5. Search for content in an eDiscovery (Standard) case (current, non-retired mechanism; its URL carries the redirect slug from the retired classic "User Data Search"/DSR-case-tool article, confirming the August 30, 2023 merge) - <https://learn.microsoft.com/en-us/purview/ediscovery-search-for-content>
6. Create custodians (Graph v1.0) - <https://learn.microsoft.com/en-us/graph/api/security-ediscoverycase-post-custodians?view=graph-rest-1.0>
7. Create custodian userSource (Graph v1.0; `includedSources` values) - <https://learn.microsoft.com/en-us/graph/api/security-ediscoverycustodian-post-usersources?view=graph-rest-1.0>
8. Create searches (Graph v1.0; `contentQuery` optional, `dataSourceScopes` enum) - <https://learn.microsoft.com/en-us/graph/api/security-ediscoverycase-post-searches?view=graph-rest-1.0>
9. ediscoverySearch resource type (`dataSourceScopes`: none/allTenantMailboxes/allTenantSites/allCaseCustodians/allCaseNoncustodialDataSources) - <https://learn.microsoft.com/en-us/graph/api/resources/security-ediscoverysearch?view=graph-rest-1.0>
10. Export items from a review set in eDiscovery (PST/individual-message and native-file export formats) - <https://learn.microsoft.com/purview/edisc-review-set-export>
11. Legacy eDiscovery tools retired (classic Content Search/eDiscovery, August 31, 2025) - <https://learn.microsoft.com/en-us/purview/ediscovery-legacy-retirement>
12. Assign permissions in eDiscovery (eDiscovery Manager/Administrator, Custodian role) - <https://learn.microsoft.com/purview/edisc-permissions>
13. Message properties and search operators for In-Place eDiscovery (the `participants:` recipient property; expands to an Entra ID identity lookup across From/To/Cc/Bcc/Participants/Recipients) - <https://learn.microsoft.com/en-us/exchange/policy-and-compliance/ediscovery/message-properties-and-search-operators>
14. Export documents in a review set to an Azure Storage account - "More information" (the `Export_load_file.csv` detail export report, "a column for each metadata property for a document," included with every export job) - <https://learn.microsoft.com/purview/ediscovery-download-export-jobs#more-information>

> Re-verify all links and Graph SDK cmdlet names against current Microsoft Learn before a
> customer-facing deployment - this scenario's grounding pass used web search rather than a direct
> Microsoft Learn fetch (environment constraint, not a shortcut taken by choice); the request-type
> routing and the "no technical control exists" claims in the configuration reference and the known limitations are the parts most worth
> re-confirming first, since they're the easiest to get wrong by omission.