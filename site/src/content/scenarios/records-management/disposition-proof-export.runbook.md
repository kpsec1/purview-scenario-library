---
part: "runbook"
parent: "records-management/disposition-proof-export"
---
## Implementation steps

### Portal path (the Microsoft-documented "proof of disposition" mechanism)

1. **Purview portal** → **Records Management** → **Disposition**.
2. Select a retention label. If applicable, open its **Pending disposition** tab (time range by
   expiration date) or **Disposed items** tab (time range by deletion date).
3. Use **Filter** to narrow the view, then **Export** - produces a `.csv` you can sort and manage in
   Excel. Items disposed with no review stage show `Type = Records Disposed`.
4. This export is **manual and one-off per label** - there is no documented PowerShell or Graph
   equivalent (the known limitations; the design notes item 4). Repeat it whenever a fresh, portal-sourced export is
   needed.

### Script path (this scenario's automation)

```powershell
# Connect (certificate app-only preferred - docs/automation-surface.md §3)
Connect-ExchangeOnline -AppId $AppId -Certificate $Cert -Organization 'contoso.onmicrosoft.com'

# 1. Dry run - queries the last 7 days tenant-wide, writes nothing
./deploy/Export-DispositionProofEvidence.ps1 -OutputCsvPath ./out/disposition-proof.csv -WhatIf

# 2. Build/merge the rolling evidence trail
./deploy/Export-DispositionProofEvidence.ps1 -OutputCsvPath ./out/disposition-proof.csv

# 3. Validate - live audit-log check + CSV structural integrity
./validate/Test-DispositionProofExport.ps1 -CsvPath ./out/disposition-proof.csv

# 4. Targeted pull for one records schedule (e.g. an examiner request)
./deploy/Export-DispositionProofEvidence.ps1 -StartDate (Get-Date).AddDays(-180) -EndDate (Get-Date) `
    -RetentionLabelName 'Contract Expiration - 7yr' -OutputCsvPath ./out/contract-expiration-audit.csv
```

Read-only against the tenant - the only side effect is the CSV file. `-WhatIf` still runs the
(read-only) audit-log query so the reported would-be-merged count is accurate.

## Configuration reference

| Setting | Value this scenario uses | Notes |
|---|---|---|
| Query cmdlet | `Search-UnifiedAuditLog` | Exchange Online PowerShell |
| Disposition-review Operations | `AddReviewer`, `ApproveDisposal`, `ExtendRetention`, `RelabelItem` | Verbatim from Microsoft's "Disposition review activities" table |
| Record-deletion Operation | `RecordDelete` | "Deleted file marked as a record" - File and page activities |
| Record-lock-status Operations | `LockRecord`, `UnlockRecord` | Context, not disposition itself - a record must be unlocked before it can be modified/deleted by a user; added per the Red Team review, finding 2 |
| `RecordType` filter | **None** | Confirmed correct, not just unconfirmed: `RecordsManagement`/`MultiStageDisposition` are Graph-only enum members, not valid `Search-UnifiedAuditLog -RecordType` input - the design notes item 3 |
| `ApproveDisposal` on an interim stage | Moves the item to the **next** disposition stage, not to deletion | Only the final (or only) stage's approval marks an item eligible for permanent delete, within **15 days** |
| `ApproveDisposal` via autoapproval | Same event as manual approval - "no new auditing event for autoapproval" | Distinguishing field not named by Microsoft - the known limitations VERIFY |
| Portal `Type = Records Disposed` | Item deleted with **no** disposition review (a plain regulatory-record delete) | Portal-only view; this scenario's `RecordDelete` query covers both reviewed and unreviewed cases |
| Disposition timelines | 15 days (post-approval delete) · 7-365 days, default 14 (autoapproval timeout) · up to 7 days (config propagation) | Cited from the parent scenarios' own operations and tuning; reproduced here for evidence-timing context |

Exact cmdlet syntax and Learn sources are cited in each script's `.NOTES`.

## Operations and tuning

**KPIs / signals:** count of `ApproveDisposal` events reaching a final stage vs. corresponding
`RecordDelete` events within 15 days (a reconciliation gap here is worth investigating); count of
`RecordDelete` events with `Type = Records Disposed` in the portal (unreviewed regulatory-record
deletes) vs. reviewed disposals; disposition backlog (pending items awaiting review - portal-only,
tracked as an open follow-up under *Multi-Stage Disposition Review Panel*).

**Out-of-process-deletion pattern (Blue Team):** an `UnlockRecord` event shortly followed by a
`RecordDelete` with **no** corresponding final-stage `ApproveDisposal` in between is worth an
analyst's attention - it's consistent with a record being unlocked and deleted outside the reviewed
disposition process entirely, rather than through it. This scenario's scripts surface the raw
`LockRecord`/`UnlockRecord`/`ApproveDisposal`/`RecordDelete` events so this reconciliation is
possible; they do not themselves compute or alert on the pattern - for continuous, alerting-grade
monitoring at scale, feed this scenario's `-Operations` list into
*Continuous Streaming to a SIEM (Sentinel Connector + Management Activity API)* rather than relying on a scheduled CSV
pull alone.

**Cadence:** schedule `deploy/Export-DispositionProofEvidence.ps1` **daily or weekly** - deliberate
overlap between runs is safe (composite-key de-duplication). Because most retention periods span
years, disposition activity itself is bursty and infrequent per label; a rolling, longer-history CSV
is more useful for an examiner request than any single scheduled window.

**Retention-tier alignment:** run the export on a cadence **shorter than the shortest audit-retention
tier in play** - default **Audit (Standard)** retains most events 180 days; E5-licensed users'
Exchange/SharePoint/OneDrive/Entra ID events default to **1 year**; **Audit (Premium)** with the
10-year add-on extends this further. A quarterly export cadence
is not safe on a Standard-only tenant; a monthly or more frequent cadence is.

**Change management:** treat the rolling CSV like any other compliance evidence artifact - if
committed to source control, its removal should be a deliberate, reviewed commit, not an ad hoc
delete (same discipline as *Exportable, Historical Sensitivity-Label Coverage Report*).

## Rollback and decommission

See the rollback runbook. Quick reference: this scenario creates **no object inside Microsoft Purview** -
no policy, no label, no rule. There is nothing to disable or delete in the tenant. Rollback is
limited to stopping the export script's schedule and deciding what to do with already-produced CSV
files (which are themselves sensitive evidentiary records - handle accordingly, not as disposable
scratch output).

## References

1. Disposition of content (portal Filter/Export, timelines, `Type = Records Disposed`, RBAC, audit-enablement prerequisite) - <https://learn.microsoft.com/purview/disposition>
2. Audit log activities - Disposition review activities (`AddReviewer`/`ApproveDisposal`/`ExtendRetention`/`RelabelItem`) - <https://learn.microsoft.com/purview/audit-log-activities#disposition-review-activities>
3. Audit log activities - File and page activities (`RecordDelete`, "documents and emails") - <https://learn.microsoft.com/purview/audit-log-activities#file-and-page-activities>
4. `auditLogRecordType` enum type - `RecordsManagement`/`MultiStageDisposition` members, Graph-only, not valid `Search-UnifiedAuditLog -RecordType` input (Microsoft Graph) - <https://learn.microsoft.com/graph/api/resources/security-auditlogrecordtype>
5. Search-UnifiedAuditLog (`-RecordType`, `-Operations`, paging via `-SessionCommand ReturnLargeSet`) - <https://learn.microsoft.com/powershell/module/exchangepowershell/search-unifiedauditlog>
6. `dispositionReviewStage` resource type (Microsoft Graph - label stage configuration, not a live item) - <https://learn.microsoft.com/graph/api/resources/security-dispositionreviewstage>
7. Microsoft Purview service description - Records Management licensing - <https://learn.microsoft.com/office365/servicedescriptions/microsoft-365-service-descriptions/microsoft-365-tenantlevel-services-licensing-guidance/microsoft-purview-service-description>
8. Manage audit log retention policies (180-day Standard default, 1-year E5 default, 10-year Premium add-on) - <https://learn.microsoft.com/purview/audit-log-retention-policies>
9. Learn about auditing solutions in Microsoft Purview (Standard vs. Premium comparison) - <https://learn.microsoft.com/purview/audit-solutions-overview>
10. Maximum numbers for disposition review (retention-limits reference) - <https://learn.microsoft.com/purview/retention-limits#maximum-numbers-for-disposition-review>
11. Office 365 Management Activity API schema - `AuditLogRecordType` enum table, the value source `Search-UnifiedAuditLog -RecordType` documents itself against - <https://learn.microsoft.com/office/office-365-management-api/office-365-management-activity-api-schema#auditlogrecordtype>

> Re-verify all links, cmdlet parameters, licensing, and the remaining `AuditData`-field open
> questions against current Microsoft Learn before a customer-facing deployment. This scenario is
> read-only against the tenant - the only irreversible-adjacent risk is relying on a stale audit
> window; see operations and tuning and the known limitations.