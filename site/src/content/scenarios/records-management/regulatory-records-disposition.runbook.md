---
part: "runbook"
parent: "records-management/regulatory-records-disposition"
---
## Implementation steps

```powershell
# Connect (certificate app-only preferred - docs/automation-surface.md §3)
Connect-IPPSSession -AppId $AppId -Certificate $Cert -Organization 'contoso.onmicrosoft.com'

# 1. Dry run - prints the exact cmdlets, starts nothing
./deploy/New-RecordsDisposition.ps1 -ConfigPath ./deploy/config/records-disposition.json -DryRun

# 2. Build event type + label + publish policy/rule (NO clock started)
./deploy/New-RecordsDisposition.ps1 -ConfigPath ./deploy/config/records-disposition.json

# 3. Validate
./validate/Test-RecordsDisposition.ps1 -ConfigPath ./deploy/config/records-disposition.json

# 4. LATER, for a real dated event only (irreversible) - requires event.create=true in config:
./deploy/New-RecordsDisposition.ps1 -ConfigPath ./deploy/config/records-disposition.json -TriggerEvent
```

### Portal reference

Event types and events live in the [Microsoft Purview portal](https://purview.microsoft.com) under
**Records Management → Events** (**Manage event types** / **+ Create** event); labels
and label policies under **Records Management → File plan / Label policies**; pending disposals under
**Records Management → Disposition**. Events can also be automated via the Microsoft
Graph records-management APIs (the older REST event API is deprecated). `-WhatIf` is
non-functional in S&C PowerShell, so the scripts ship a `-DryRun`.

## Configuration reference

| Setting | Value this scenario uses | Notes |
|---|---|---|
| Event-type cmdlet | `New-ComplianceRetentionEventType` | Creates the event type |
| Label cmdlet | `New-ComplianceTag` | Record label |
| `RetentionAction` | `KeepAndDelete` | Retain, then dispose (review-gated) |
| `RetentionType` | `EventAgeInDays` | Clock starts on the event, not content age |
| `EventType` | the event-type name | Binds the label to the event type; **can't be changed after save** |
| `RetentionDuration` | `2555` (≈7 years) | Days after the event |
| `IsRecordLabel` | `$true` | Declares content a record (lockable) |
| `ReviewerEmail` | records-manager address(es) | Enables **disposition review**; users or mail-enabled security groups |
| `AutoApprovalPeriod` | optional | Auto-approve if no reviewer acts within N days (7-365) |
| Publish cmdlets | `New-RetentionCompliancePolicy` + `New-RetentionComplianceRule -PublishComplianceTag` | Publish (not auto-apply) |
| Event cmdlet | `New-ComplianceRetentionEvent` | `-EventDateTime`, `-SharePointAssetIdQuery`/`-ExchangeAssetIdQuery` to scope |

Exact cmdlet syntax and Learn sources are cited in each script's `.NOTES`.

## Operations and tuning

**KPIs / signals:** publish policy **DistributionStatus** (should reach a healthy state); **disposition
backlog** (pending items awaiting review - the key records-management SLA); count of events triggered
vs. expected; count of items disposed with proof. **Tuning:** scope each event **narrowly** with an
asset-ID query - an event with no asset ID starts retention for **all** content carrying that
event-type label, which is almost never intended. Use `AutoApprovalPeriod` to stop a
disposition backlog stalling disposal when reviewers are slow, but only where auto-approval is
defensible for that record class. Multi-stage reviews (up to 5 stages, 10 reviewers each) model
sign-off chains where one approver isn't enough.

**Change management:** the config file is the versioned records schedule - treat any change to the label,
event type, or reviewers as a controlled, Records/Legal-reviewed change. The event type **cannot be
changed** once a label is saved with it, so name and scope it deliberately.

## Rollback and decommission

See the rollback runbook. Quick reference: `./deploy/Remove-RecordsDisposition.ps1` **disables** the publish
policy (stops the label being newly applied); `-Delete` removes the policy + rule and **attempts** to
remove the label and event type. Rollback **cannot** delete a record label already applied, shorten
retention, or **cancel a triggered event** - those are irreversible by design, and the script reports
rather than forces them.

## References

1. Start retention when an event occurs (event-based retention: event types, events, asset-ID scoping, can't-cancel, PowerShell + Graph automation) - <https://learn.microsoft.com/purview/event-driven-retention>
2. Disposition of content / disposition reviews (Disposition Management role, reviewers, stages, 15-day post-approval delete, proof of disposition) - <https://learn.microsoft.com/purview/disposition>
3. Automatically apply / publish a retention label (publish vs. auto-apply, latency, RetryDistribution) - <https://learn.microsoft.com/purview/create-apply-retention-labels>
4. New-ComplianceTag (retention label; RetentionAction/Type, EventType, ReviewerEmail, IsRecordLabel, AutoApprovalPeriod) - <https://learn.microsoft.com/powershell/module/exchangepowershell/new-compliancetag>
5. New-ComplianceRetentionEventType - <https://learn.microsoft.com/powershell/module/exchangepowershell/new-complianceretentioneventtype>
6. Use the Microsoft Graph records management APIs (event automation; REST event API deprecated) - <https://learn.microsoft.com/graph/api/resources/security-recordsmanagement-overview>
7. Microsoft Purview service description - Records Management licensing - <https://learn.microsoft.com/office365/servicedescriptions/microsoft-365-service-descriptions/microsoft-365-tenantlevel-services-licensing-guidance/microsoft-purview-service-description>
8. New-ComplianceRetentionEvent (-EventDateTime, -SharePointAssetIdQuery / -ExchangeAssetIdQuery, -EventType) - <https://learn.microsoft.com/powershell/module/exchangepowershell/new-complianceretentionevent>
9. Learn about records management - <https://learn.microsoft.com/purview/records-management>
10. New-RetentionComplianceRule (-PublishComplianceTag) - <https://learn.microsoft.com/powershell/module/exchangepowershell/new-retentioncompliancerule>

> Re-verify all links, cmdlet parameters, licensing, disposition RBAC, and the irreversibility behaviors
> against current Microsoft Learn before a customer-facing deployment. Triggered events and applied
> record labels are irreversible - the scenario is deliberately conservative (dry-run, gated event,
> create-or-report, no force-removal of records).