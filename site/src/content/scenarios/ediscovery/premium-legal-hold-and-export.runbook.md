---
part: "runbook"
parent: "ediscovery/premium-legal-hold-and-export"
---
## Implementation steps

### Portal path (for a first manual walkthrough / to validate intent before scripting)

1. **Confirm Premium is available**: Purview portal → **Settings** → **eDiscovery** →
   **General** → confirm the **eDiscovery (Premium)** toggle is on for new cases.
2. **Create the case**: eDiscovery solution card → **Cases** → **Create case** → name and
   description → **Create**. On **Case settings**, confirm the **Premium features** toggle for
   this specific case is on.
3. **Add custodians**: in the case, **Data sources** (or the **Custodians** tab) → **Add
   custodian** → enter the SMTP address → confirm **mailbox** and **OneDrive** as included
   sources → **Place custodian on hold**.
4. **Create a search**: **Searches** tab → **New search** → scope to **All case custodians** →
   enter the KQL query agreed with counsel → **Run query**, then **View estimated statistics**
   before collecting.
5. **Add to a review set**: from the search, **Add to review set** → **new review set**, name
   it, choose **Add all search results** (or configure sampling).
6. **Register the download API app** (one-time, per tenant, before your first export
   download): register/confirm the **MicrosoftPurviewEDiscovery** first-party service principal
   exists (`New-MgServicePrincipal -BodyParameter @{ AppId = 'b26e684c-5068-4120-a679-64a5d2c909d9' }`
   if not already present), then on your automation app registration → **API permissions** →
   **Add a permission** → **APIs my organization uses** → **MicrosoftPurviewEDiscovery** →
   **Application permissions** → **`eDiscovery.Download.Read`** → **Grant admin consent**.
7. **Export**: in the review set, **Action** → **Export** → name the export, choose export
   options (original files, tags) and structure (PST) → **Export**. Track progress under
   **Process manager**; retrieve the download link from the export's **Copy support information**
   or via the Graph operation as in section 6 below.

### Script path (idempotent, parameterized, dry-run capable)

```powershell
# 1. Connect (app-only, certificate - see docs/automation-surface.md §3). All three deploy
#    scripts below share this connection if you Connect-MgGraph once first, or connect
#    per-invocation using the -AppId/-TenantId/-CertificateThumbprint parameters shown.

# 2. Dry run - reports every case/custodian/hold action this run would take, makes none.
./deploy/New-EdiscoveryPremiumLegalHold.ps1 `
    -DefinitionPath ./deploy/policy/ediscovery-case-definition.json `
    -AppId $AppId -TenantId $TenantId -CertificateThumbprint $Thumbprint -WhatIf

# 3. Create the case, add custodians, apply hold.
./deploy/New-EdiscoveryPremiumLegalHold.ps1 `
    -DefinitionPath ./deploy/policy/ediscovery-case-definition.json `
    -AppId $AppId -TenantId $TenantId -CertificateThumbprint $Thumbprint
# Note the case id printed at the end (or look it up via
# Get-MgSecurityCaseEdiscoveryCase | Where-Object DisplayName -eq '<name>').

# 4. Search, commit to review set, export. Stop short of export with -SkipExport to let a
#    reviewer tag/cull first.
./deploy/New-EdiscoverySearchReviewSetExport.ps1 `
    -DefinitionPath ./deploy/policy/ediscovery-case-definition.json `
    -CaseId $caseId `
    -AppId $AppId -TenantId $TenantId -CertificateThumbprint $Thumbprint

# 5. Download the export package (requires the eDiscovery.Download.Read permission from §5
#    step 6, above).
./deploy/Get-EdiscoveryExportPackage.ps1 `
    -CaseId $caseId -ExportOperationId $exportOpId `
    -OutputDirectory ./exports/CONTOSO-LIT-2026-014-export1 `
    -AppId $AppId -TenantId $TenantId -CertificateThumbprint $Thumbprint

# 6. Validate.
./validate/Test-EdiscoveryPremiumCaseSetup.ps1 `
    -DefinitionPath ./deploy/policy/ediscovery-case-definition.json `
    -CaseId $caseId -AppId $AppId -TenantId $TenantId -CertificateThumbprint $Thumbprint

# 7. Audit trail (independent of the Graph objects above; run on a recurring schedule per Section 8
#    "Audit visibility" - Exchange Online PowerShell, not Graph, so connect separately).
Connect-ExchangeOnline -AppId $AppId -Certificate $Cert -Organization $TenantDomain
./deploy/Export-EdiscoveryAuditTrail.ps1 `
    -CaseName 'CONTOSO-LIT-2026-014' -OutputCsvPath ./deploy/out/edisc-audit-trail.csv
./validate/Test-EdiscoveryAuditTrail.ps1 -AuditTrailCsvPath ./deploy/out/edisc-audit-trail.csv
```

All three deploy scripts use Microsoft Graph (`Microsoft.Graph.Security` module,
`microsoft.graph.security` namespace) - automation surface 3 per [Automation surface, section 1](/docs/automation-surface/#1-five-automation-surfaces-not-one-read-this-first),
because app-only authentication for eDiscovery cmdlets in Security & Compliance PowerShell is
explicitly unsupported. The download script additionally uses a separate,
non-Graph Purview eDiscovery API authenticated via `MSAL.PS`, per Microsoft's documented two-API
design.

## Configuration reference

| Object | Cmdlet | Key fields (from `deploy/policy/ediscovery-case-definition.json`) |
|---|---|---|
| Case | `New-MgSecurityCaseEdiscoveryCase` | `displayName`, `description`, `externalId` |
| Custodian | `New-MgSecurityCaseEdiscoveryCaseCustodian` | `email` |
| Custodian userSource | `New-MgSecurityCaseEdiscoveryCaseCustodianUserSource` | `email`, `includedSources = 'mailbox, site'` |
| Hold | `Add-MgSecurityCaseEdiscoveryCaseCustodianHold` | (no body - targets one custodian per call) |
| Search | `New-MgSecurityCaseEdiscoveryCaseSearch` | `displayName`, `contentQuery` (KQL), `dataSourceScopes = 'allCaseCustodians'` |
| Review set | `New-MgSecurityCaseEdiscoveryCaseReviewSet` | `displayName` |
| Add to review set | `Add-MgSecurityCaseEdiscoveryCaseReviewSetToReviewSet` | `search.id`, `itemsToInclude = 'searchHits'`, `additionalDataOptions = 'linkedFiles'` |
| Export | `Export-MgSecurityCaseEdiscoveryCaseReviewSet` | `outputName`, `exportOptions = 'originalFiles,tags'`, `exportStructure = 'pst'` |
| Release hold | `Invoke-MgGraphRequest POST .../custodians/{id}/release` | - |
| Close/delete case | `Update-MgSecurityCaseEdiscoveryCase -Status closed`, `Remove-MgSecurityCaseEdiscoveryCase` | - |
| Audit trail (read-only) | `Search-UnifiedAuditLog -RecordType Discovery -Operations ...` | `CaseAdded`/`CaseUpdated`/`CaseClosed`/`CaseReopened`/`CaseRemoved`; `HoldCreated`/`HoldUpdated`/`HoldRemoved`/`HoldRetryDistributionSync` - see operations and tuning and `deploy/Export-EdiscoveryAuditTrail.ps1` |

`caseOperationStatus` values used by the poll loops in both `New-Ediscovery*.ps1` scripts:
`notStarted`, `submissionFailed`, `running`, `succeeded`, `partiallySucceeded`, `failed`,
`unknownFutureValue` - the exact v1.0 enum, not carried over from beta.

Full parameter grounding: each script's `.NOTES` block cites the exact Microsoft Learn REST/
PowerShell reference page for every cmdlet it calls.

## Operations and tuning

**KPIs to watch:**
- **Custodian `HoldStatus`** - track for every custodian in every open matter; a status that
  regresses from `success` to anything else after the initial propagation window is a signal
  something (a mailbox move, a license change, a manual portal edit) disrupted the hold - treat
  it as an incident, not routine drift, given the spoliation exposure in why this matters.
- **Export age vs. the 30-day download window** - `validate/Test-EdiscoveryPremiumCaseSetup.ps1`
  flags an export older than 30 days as `WARN` (content is very likely no longer downloadable by
  then). Download every export you intend to keep well before that window
  closes; there is no automatic renewal.
- **Case/hold-policy counts against tenant limits** - 20,000 hold policies tenant-wide, 200 per
  Premium case, 2,000 mailboxes and 2,000 sites per case hold. A high-volume
  MSSP/legal-ops practice running many concurrent matters should watch these, not just per-case
  health.
- **PAYG export storage cost** (if the tenant has activated Purview's pay-as-you-go billing) -
  Export API usage is billed by exported data volume; case/search/hold operations themselves are
  not billed. See the cost and licensing notes.

**Review cadence:** re-run `validate/Test-EdiscoveryPremiumCaseSetup.ps1` on every case with an
active hold at least weekly for the life of the matter - a released hold that should still be
active is a preservation failure, not a cosmetic drift.

**Audit visibility for hold-apply/hold-release/case-close/case-delete actions:** none of this
scenario's own objects retain a full history of *who* released a hold or closed/deleted a case
beyond the single `lastModifiedBy`/`closedBy` snapshot on the case itself - an actor with
eDiscovery Administrator access who quietly releases a custodian's hold and later re-applies it
leaves no trace in the objects this scenario's scripts read. `deploy/Export-EdiscoveryAuditTrail.ps1`
routes around this by pulling case-lifecycle events (`CaseAdded`/`CaseUpdated`/`CaseClosed`/
`CaseReopened`/`CaseRemoved`) and hold-policy-lifecycle events (`HoldCreated`/`HoldUpdated`/
`HoldRemoved`/`HoldRetryDistributionSync`) from the Microsoft 365 unified audit log
(`Search-UnifiedAuditLog`, automation surface 1, `RecordType Discovery`) into a rolling,
de-duplicated CSV - the same pattern this library's other no-independent-audit-trail scenarios use
(*Assess Against ISO/IEC 27001:2022*,
*Workplace Harassment & Code of Conduct*), both `Operation` sets
confirmed verbatim against Microsoft's own "Audit log activities" eDiscovery reference rather than
guessed by analogy. **One real gap remains, disclosed rather than papered
over:** those four hold-policy `Operation` values are documented against the case-level
`ediscoveryHoldPolicy` object (the "Hold policies" tab, and this library's sibling
*Location-Scoped Legal Hold (Regulatory Sweep / Shared Mailbox)* scenario) - whether they also fire for *this*
scenario's own custodian-scoped `ediscoveryCustodian: applyHold`/`release` calls is not confirmed
for the current, non-legacy eDiscovery experience; the one Microsoft Learn page describing
per-custodian audit search carries a caution banner limiting it to organizations hosted by
21Vianet (China) after the classic experience's August 2025 retirement everywhere else. See the script's own `.DESCRIPTION`/`.NOTES` for the full
reasoning and the pilot-tenant VERIFY step tracked in the project backlog. Until that VERIFY closes,
treat a `HoldPolicyLifecycle` row in this scenario's audit trail as strong evidence *some*
eDiscovery hold changed, and cross-check its `CaseName`/`ObjectName` columns against this case
before assuming it's this scenario's own custodian hold rather than an unrelated
`ediscoveryHoldPolicy` action in a different matter. Run it weekly alongside
`validate/Test-EdiscoveryPremiumCaseSetup.ps1` per this section's Review cadence, and pair it with
the case's own `Get-MgSecurityCaseEdiscoveryCase`/`Get-MgSecurityCaseEdiscoveryCaseCustodian`
snapshots for the point-in-time status those scripts already report.

**Operational dependency this scenario does not close:** whether the *right* custodians were
identified for a given matter is a legal-judgment call this scenario's automation cannot make -
it only guarantees that whichever custodians are listed in `deploy/policy/
ediscovery-case-definition.json` are reliably placed on hold. Getting the custodian list right is
outside code's ability to verify.

## Rollback and decommission

See the rollback runbook for the full staged procedure (release hold → close case → delete case). Quick
reference: `./deploy/Remove-EdiscoveryPremiumLegalHold.ps1 -CaseId $caseId` releases every
custodian currently on hold; add `-CloseCase` or `-DeleteCase` for the progressively more
destructive stages, each requiring an explicit switch.

## References

1. Create holds in eDiscovery (preserve independent of retention policies, up to 24-hour propagation) - <https://learn.microsoft.com/purview/edisc-hold-create>
2. eDiscovery subscription comparison (Standard vs. Premium capability table) - <https://learn.microsoft.com/purview/ediscovery#comparison-of-key-capabilities>
3. Learn about case settings in eDiscovery (per-case Premium features toggle) - <https://learn.microsoft.com/purview/edisc-settings-cases>
4. Configure general settings in eDiscovery (tenant-level Premium default toggle) - <https://learn.microsoft.com/purview/edisc-settings-general>
5. Assign permissions in eDiscovery (eDiscovery Manager/Administrator, Custodian role) - <https://learn.microsoft.com/purview/edisc-permissions>
6. Assign permissions in eDiscovery - app-only auth for S&C PowerShell eDiscovery cmdlets is unsupported - <https://learn.microsoft.com/purview/edisc-permissions#configure-app-only-authentication-for-ediscovery-powershell>
7. Set up app-only access for Microsoft Purview eDiscovery (Graph app-only setup, step by step) - <https://learn.microsoft.com/graph/security-ediscovery-appauthsetup>
8. Use Microsoft Purview APIs for eDiscovery (two-API design, MicrosoftPurviewEDiscovery app registration, `eDiscovery.Download.Read`, MSAL.PS download scripts) - <https://learn.microsoft.com/purview/edisc-ref-api-guide>
9. Create holds in eDiscovery (licensing requirement on every held user, Frontline exclusion) - <https://learn.microsoft.com/purview/edisc-hold-create>
10. Create holds in eDiscovery (custodian mailbox/OneDrive/Teams/Groups hold scope, 24-hour propagation) - <https://learn.microsoft.com/purview/edisc-hold-create>
11. Add search results to a review set in eDiscovery - <https://learn.microsoft.com/purview/edisc-search-add-to-review-set>
12. Export items from a review set in eDiscovery (portal export flow, Process manager) - <https://learn.microsoft.com/purview/edisc-review-set-export>
13. Microsoft Purview service description - eDiscovery licensing, shared-mailbox hold licensing parity with Exchange - <https://learn.microsoft.com/office365/servicedescriptions/microsoft-365-service-descriptions/microsoft-365-tenantlevel-services-licensing-guidance/microsoft-purview-service-description#microsoft-purview-ediscovery>
14. caseOperation resource type (v1.0 `caseOperationStatus` enum) - <https://learn.microsoft.com/graph/api/resources/security-caseoperation?view=graph-rest-1.0>
15. Use the hold report (preview) in eDiscovery - <https://learn.microsoft.com/purview/edisc-hold-report>
16. Export items from a review set in eDiscovery (summary/load file always included) - <https://learn.microsoft.com/purview/edisc-review-set-export>
17. Export items from a review set in eDiscovery (30-day download window, life-of-case retention of the operation record) - <https://learn.microsoft.com/purview/edisc-review-set-export>
18. Limits in eDiscovery (hold policy and per-case mailbox/site limits) - <https://learn.microsoft.com/purview/edisc-ref-limits>
19. Billing in eDiscovery (Graph API usage billing - only Export API is metered) - <https://learn.microsoft.com/purview/edisc-billing>
20. Create and manage cases in eDiscovery (closing/deleting a case turns off all its holds) - <https://learn.microsoft.com/purview/edisc-cases-manage>
21. ediscoveryCase resource type (v1.0 `caseStatus` enum: active/closing/closed/closedWithError) - <https://learn.microsoft.com/graph/api/resources/security-ediscoverycase?view=graph-rest-1.0>
22. ediscoveryCustodian resource type (Apply hold / Release / Activate methods) - <https://learn.microsoft.com/graph/api/resources/security-ediscoverycustodian?view=graph-rest-1.0>
23. Create custodian userSource (v1.0 REST reference, `includedSources` values) - <https://learn.microsoft.com/graph/api/security-ediscoverycustodian-post-usersources?view=graph-rest-1.0>
24. Use the Microsoft Purview eDiscovery API (v1.0 object/cmdlet overview) - <https://learn.microsoft.com/graph/api/resources/security-ediscovery-apioverview?view=graph-rest-1.0>
25. Audit log activities - eDiscovery activity reference (the exact `Operation` names/descriptions `deploy/Export-EdiscoveryAuditTrail.ps1`'s two query categories are built from verbatim) - <https://learn.microsoft.com/purview/audit-log-activities#ediscovery-activities>
26. Manage holds in eDiscovery (Premium) - the "custodian hold policy" claim; carries Microsoft's classic-eDiscovery-experience/21Vianet-China-only caution banner - <https://learn.microsoft.com/purview/ediscovery-managing-holds>
27. View custodian audit activity - the one per-custodian audit UI Microsoft documents; also carries the classic-experience/21Vianet-China-only caution banner - <https://learn.microsoft.com/purview/ediscovery-view-custodian-activity>
28. Manage hold notifications (current, non-legacy page - the `Important` callout stating legal hold custodian communications were permanently retired August 31, 2025 and aren't available in the new eDiscovery experience) - <https://learn.microsoft.com/purview/ediscovery-manage-hold-notifications>

> Re-verify all links against current Microsoft Learn before a customer-facing deployment -
> Purview's Graph eDiscovery surface has moved from the `microsoft.graph.ediscovery` namespace to
> `microsoft.graph.security` within the product's own history, and beta-to-v1.0 promotions can
> change property/enum shapes without notice.