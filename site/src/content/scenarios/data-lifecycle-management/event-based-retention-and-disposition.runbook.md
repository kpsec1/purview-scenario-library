---
part: "runbook"
parent: "data-lifecycle-management/event-based-retention-and-disposition"
---
## Implementation steps

### PowerShell path

```powershell
# Connect (certificate app-only preferred - docs/automation-surface.md §3)
Connect-IPPSSession -AppId $AppId -Certificate $Cert -Organization 'contoso.onmicrosoft.com'

# 1. One-time: dry run then deploy the event type, label, and publish policy/rule
./deploy/New-EventBasedRetentionAndDisposition.ps1 -ConfigPath ./deploy/config/employee-departure-retention.json -DryRun
./deploy/New-EventBasedRetentionAndDisposition.ps1 -ConfigPath ./deploy/config/employee-departure-retention.json

# 2. Validate the policy deployment
./validate/Test-EventBasedRetentionAndDisposition.ps1 -ConfigPath ./deploy/config/employee-departure-retention.json

# 3. Ongoing: HR/records manager applies the published label to the departed employee's
#    records (portal), sets that content's ComplianceAssetID to the employee ID, then:
./deploy/New-RetentionTriggerEvent.ps1 -EventName 'Employee Departure - 123456' -EmployeeId '123456' -EventDate '2026-09-01' -DryRun
./deploy/New-RetentionTriggerEvent.ps1 -EventName 'Employee Departure - 123456' -EmployeeId '123456' -EventDate '2026-09-01'
```

### Portal reference

The event type, label, and policy are visible in the
[Microsoft Purview portal](https://purview.microsoft.com) under **Records Management** →
**File plan** (labels) and **Label policies**, and events under **Records Management** → **Events**. Applying the published label to content, and setting each item's Asset ID, is
normally a manual, portal-driven records-manager action - this scenario doesn't
script that step (it's per-item, human judgment about which records belong to which employee).
`-WhatIf` is non-functional in S&C PowerShell, so the deploy/remove/trigger scripts ship a `-DryRun`
instead.

> **Apply the label at hire, not at departure.** Applying the label (and setting `ComplianceAssetID`)
> to an employee's personnel folder as part of onboarding - not as a rushed step during
> offboarding - means the only action needed at departure is firing the event. It also closes the
> gap where an as-yet-unlabeled record isn't a locked record yet and could be edited or deleted
> before anyone gets to it.

## Configuration reference

| Setting | Value this scenario uses | Notes |
|---|---|---|
| Event type cmdlet | `New-ComplianceRetentionEventType` | Creates the named event type a label listens for |
| Label cmdlet | `New-ComplianceTag -EventType <type>` | Binds the label to the event type; **can't be changed after the label is saved** |
| `RetentionAction` | `KeepAndDelete` | Required (with `Delete`) to use `-ReviewerEmail`/`-MultiStageReviewProperty` |
| `RetentionType` | `EventAgeInDays` | Clock starts from the fired event's date, not creation/modification |
| `RetentionDuration` | `3650` (~10 years, illustrative) | Set to your actual obligation - see why this matters and the known limitations |
| `IsRecordLabel` | `$true` | Locks labeled content as a record; mirrors Microsoft's own worked event-based example. Not a *regulatory* record - see *Retention Labels for Financial Records* for that stronger control |
| `MultiStageReviewProperty` | 2-stage JSON: HR Records Review → Legal Review | `'{"MultiStageReviewSettings":[{"StageName":"...","Reviewers":[...]},...]}'` |
| `AutoApprovalPeriod` | disabled (`null`) by default | If set: 7-365 days, default 14, per the disposition-review article - VERIFY the exact cmdlet-parameter mapping, see the known limitations |
| Policy cmdlet | `New-RetentionCompliancePolicy` | Publish policy; needs ≥1 location |
| Rule cmdlet | `New-RetentionComplianceRule -PublishComplianceTag` | **Publish**, not auto-apply - event-based labels are normally hand-applied per employee with an Asset ID |
| Event cmdlet | `New-ComplianceRetentionEvent -EventType -SharePointAssetIdQuery -EventDateTime` | Fired per employee by `deploy/New-RetentionTriggerEvent.ps1`; **cannot be canceled once created** |
| Asset scope | `ComplianceAssetID:<employeeId>` (SharePoint/OneDrive document property) | Omitting it retains **all** content of that event type tenant-wide - the trigger script requires `-EmployeeId` or an explicit `-Force` |

Exact cmdlet syntax and Learn sources are cited in each script's `.NOTES`.

## Operations and tuning

**KPIs / signals:** publish policy **DistributionStatus**; count of retention events fired vs. count
of departed employees (an HR feed reconciliation, not scripted here - see the known limitations); disposition-review
backlog (pending Stage 1 / Stage 2 items, and how close any are to the optional auto-approval
timeout); events fired with no matching Asset ID content (a records-hygiene signal that Asset IDs
weren't set before the event fired). **Tuning:** treat `-EventName` as a durable, greppable key (this
scenario's convention: `<event type> - <employee ID>`) so a Records/HR audit can trace which event
covers which employee; keep the reviewer distribution list current in both the label's multi-stage
JSON and in your HR/Legal team rosters (Purview doesn't validate the mailboxes exist).

**Change management:** the event type **cannot be changed on a label after it's saved**
- retiring or renaming an event type means creating a new label bound to the new type, not editing
the old one. Treat the reviewer list and retention duration as controlled, HR/Legal-reviewed changes.

## Rollback and decommission

See the rollback runbook. Quick reference: `./deploy/Remove-EventBasedRetentionAndDisposition.ps1`
**disables** the publish policy (records managers can no longer apply the label to new content);
`-Delete` removes the policy + rule. The label, event type, and any already-fired events are **not**
force-removed - a fired event's retention clock keeps running regardless of what happens to the
policy, and a record-labeled item stays locked until disposition, by design.

## References

1. Start retention when an event occurs (event types, asset IDs, can't be changed/canceled once set/fired, unscoped-event behavior, 10-year employee-departure example) - <https://learn.microsoft.com/purview/event-driven-retention>
2. Learn about records management (labeling, file plan, event-based retention, disposition review overview) - <https://learn.microsoft.com/purview/records-management>
3. Disposition of content (disposition review workflow, timelines, auto-approval 7-365/default 14, reviewer permissions not auto-granted, stage/reviewer limits) - <https://learn.microsoft.com/purview/disposition>; limits detail - <https://learn.microsoft.com/purview/retention-limits#maximum-numbers-for-disposition-review>
4. New-ComplianceRetentionEventType - <https://learn.microsoft.com/powershell/module/exchangepowershell/new-complianceretentioneventtype>
5. New-ComplianceTag (-EventType/-RetentionAction/-RetentionDuration/-RetentionType/-IsRecordLabel/-MultiStageReviewProperty/-ReviewerEmail/-AutoApprovalPeriod) - <https://learn.microsoft.com/powershell/module/exchangepowershell/new-compliancetag>
6. New-RetentionCompliancePolicy / New-RetentionComplianceRule (-PublishComplianceTag) - <https://learn.microsoft.com/powershell/module/exchangepowershell/new-retentioncompliancepolicy> / <https://learn.microsoft.com/powershell/module/exchangepowershell/new-retentioncompliancerule>
7. New-ComplianceRetentionEvent (-EventType/-AssetId/-SharePointAssetIdQuery/-ExchangeAssetIdQuery/-EventDateTime; disposition review stage limits) - <https://learn.microsoft.com/powershell/module/exchangepowershell/new-complianceretentionevent>
8. Microsoft Purview service description - Records Management / Data Lifecycle Management licensing - <https://learn.microsoft.com/office365/servicedescriptions/microsoft-365-service-descriptions/microsoft-365-tenantlevel-services-licensing-guidance/microsoft-purview-service-description>
9. Use retention labels to manage the lifecycle of documents stored in SharePoint (worked event-based example marking content as a record) - <https://learn.microsoft.com/purview/auto-apply-retention-labels-scenario>
10. Use the Microsoft Graph records management APIs (event-based retention object model; alternative automation surface not used by this scenario) - <https://learn.microsoft.com/graph/api/resources/security-recordsmanagement-overview>

> Re-verify all links, cmdlet parameters, licensing, and the disposition-review behavior against
> current Microsoft Learn before a customer-facing deployment. Retention events can't be canceled
> once fired - the trigger script is deliberately conservative (asset-scope required, no re-fire on
> a repeated name).