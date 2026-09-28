---
part: "runbook"
parent: "records-management/multi-stage-disposition-review"
---
## Implementation steps

```powershell
# Connect (certificate app-only preferred - Automation surface Section 3)
Connect-IPPSSession -AppId $AppId -Certificate $Cert -Organization 'contoso.onmicrosoft.com'

# 1. Dry run - prints the exact cmdlets AND the exact -MultiStageReviewProperty JSON, starts nothing
./deploy/New-MultiStageDispositionReview.ps1 -ConfigPath ./deploy/config/multi-stage-disposition-review.json -DryRun

# 2. Build event type + label (with reviewer chain) + publish policy/rule (NO clock started)
./deploy/New-MultiStageDispositionReview.ps1 -ConfigPath ./deploy/config/multi-stage-disposition-review.json

# 3. Validate
./validate/Test-MultiStageDispositionReview.ps1 -ConfigPath ./deploy/config/multi-stage-disposition-review.json

# 4. LATER, for one real separated employee only (irreversible) - requires event.create=true in config:
./deploy/New-MultiStageDispositionReview.ps1 -ConfigPath ./deploy/config/multi-stage-disposition-review.json -TriggerEvent
```

### Portal reference

Event types and events live in the [Microsoft Purview portal](https://purview.microsoft.com) under
**Records Management → Events**; the multi-stage reviewer chain is configured on the label's disposition
step (**Records Management → File plan → Create label → choose "Start disposition review" → add a
stage**); pending disposals - one queue per stage a reviewer belongs to - under
**Records Management → Disposition**. `-WhatIf` is non-functional in S&C PowerShell, so the scripts ship a
`-DryRun`.

## Configuration reference

| Setting | Value this scenario uses | Notes |
|---|---|---|
| Event-type cmdlet | `New-ComplianceRetentionEventType` | Same as parent scenario |
| Label cmdlet | `New-ComplianceTag` | |
| `RetentionAction` | `KeepAndDelete` | Retain, then dispose (review-gated) |
| `RetentionType` | `EventAgeInDays` | Clock starts on the separation event |
| `RetentionDuration` | `1095` (3 years), illustrative | Above the EEOC 1-year / FLSA 2-3-year floors - set to your real practice, the design notes |
| `MultiStageReviewProperty` | JSON, 3 stages (HR → Legal → Records Mgmt) | `'{"MultiStageReviewSettings":[{"StageName":"...","Reviewers":[...]},...]}'` - built with `ConvertTo-Json`, up to 5 stages / 10 reviewers-per-stage documented max |
| `AutoApprovalPeriod` | `30` days | Valid range 7-365, default 14 if set with no value; **silently advances/disposes a stage with no reviewer action** - see section 8 |
| `ComplianceTagForNextStage` | not set (`null`) by default | Names a replacement label applied at the end of the retention period (relabeling) - confirmed via the file plan manager's identically-named import property and the "Relabeling at the end of the retention period" reference; passed through only if explicitly configured - the known limitations |
| `IsRecordLabel` | `$true` | Declares content a record (lockable) |
| Publish cmdlets | `New-RetentionCompliancePolicy` + `New-RetentionComplianceRule -PublishComplianceTag` | Publish (not auto-apply), same as parent |
| Event cmdlet | `New-ComplianceRetentionEvent` | Scoped to one employee via `-SharePointAssetIdQuery`/`-ExchangeAssetIdQuery` |

Exact cmdlet syntax and Learn sources are cited in each script's `.NOTES`.

## Operations and tuning

**KPIs / signals:** publish policy **DistributionStatus**; **per-stage disposition backlog** (a chain adds
a new failure mode the parent scenario doesn't have - a backlog stuck at Stage 1 never reaches Legal or
Records Management, so track backlog **per stage**, not just in aggregate); count of items that reached
each stage vs. items that reached final disposal; count of `AutoApprovalPeriod` auto-advances (this should
be near-zero in a healthy chain - a nonzero, growing count means a stage's reviewers aren't engaging, and
the chain is functionally a silent-approval pipeline, not a review).

**Tuning:**
- Scope each event **narrowly** (one employee's asset-ID query) - an event with no asset-ID query starts
  retention for **all** content carrying the event-type label, i.e. every separated employee at once.
- Set `AutoApprovalPeriod` deliberately, and **do not treat it as a safe default for every stage**: a
  30-day window for an HR-staffing-level Stage 1 may be reasonable; the same window on the **final**
  Records Management stage means a record can be permanently destroyed with zero human review if that
  team is short-staffed for a month. Consider a **shorter** auto-approval window paired with an
  operational alert at Stage N-1 → Stage N transitions, rather than relying on a single global setting.
- Use **mail-enabled security group** reviewers (not individuals) at every stage so staff turnover doesn't
  silently orphan a stage with zero reachable reviewers.
- **Monitor who can change the chain, not just who reviews it.** Anyone holding the Records Management /
  Retention Management config role can call `Set-ComplianceTag` directly (outside this library's scripts) to
  shorten `AutoApprovalPeriod`, remove a stage, or repoint reviewers - none of which this scenario's
  scripts detect. Restrict that role tightly and alert on `New-ComplianceTag`/`Set-ComplianceTag` activity
  in `Search-UnifiedAuditLog` as a compensating control. This repo has not yet grounded the exact
  `RecordType`/`Operations` values for those specific cmdlets against Microsoft's audit-log reference -
  tracked as a follow-up in the project backlog rather than guessed here.

**Change management:** the config file (including the reviewer chain) is the versioned, auditable
sign-off policy. The event type is immutable once a label references it; this scenario's deploy does not
retrofit reviewer-chain changes onto an existing label - changing who approves a records-disposal decision
already relied upon is a deliberate, HR/Legal/Records-reviewed action.

## Rollback and decommission

See the rollback runbook. Quick reference: `./deploy/Remove-MultiStageDispositionReview.ps1` **disables** the
publish policy by default; `-Delete` removes the policy + rule and **attempts** to remove the label and
event type. Rollback **cannot** delete a record label already applied, edit or shorten a live reviewer
chain, cancel a triggered event, or reach into an in-flight disposition item at any stage - those are
irreversible or out of scope by design; manage in-flight reviews in the portal.

## References

1. Disposition of content (multi-stage disposition review: up to 5 stages, up to 10 reviewers/stage,
   sequential stages, reviewer actions Approve disposal/Relabel/Extend/Add reviewers, auto-approval
   behavior, Disposition Management role) - <https://learn.microsoft.com/purview/disposition>
2. New-ComplianceTag (-MultiStageReviewProperty JSON syntax, -AutoApprovalPeriod 7-365 days,
   -ComplianceTagForNextStage, -RetentionAction, -RetentionType, -EventType, -IsRecordLabel) - <https://learn.microsoft.com/powershell/module/exchangepowershell/new-compliancetag>
3. Set-ComplianceTag (-MultiStageReviewProperty, -ComplianceTagForNextStage also documented here with the
   same unfilled description) - <https://learn.microsoft.com/powershell/module/exchangepowershell/set-compliancetag>
4. New-ComplianceRetentionEventType - <https://learn.microsoft.com/powershell/module/exchangepowershell/new-complianceretentioneventtype>
5. New-ComplianceRetentionEvent (-EventDateTime, -SharePointAssetIdQuery / -ExchangeAssetIdQuery,
   -EventType) - <https://learn.microsoft.com/powershell/module/exchangepowershell/new-complianceretentionevent>
6. Start retention when an event occurs (event-based retention) - <https://learn.microsoft.com/purview/event-driven-retention>
7. New-RetentionComplianceRule (-PublishComplianceTag) - <https://learn.microsoft.com/powershell/module/exchangepowershell/new-retentioncompliancerule>
8. Microsoft Purview service description - Records Management licensing - <https://learn.microsoft.com/office365/servicedescriptions/microsoft-365-service-descriptions/microsoft-365-tenantlevel-services-licensing-guidance/microsoft-purview-service-description>
9. 29 CFR 1602.14 - Preservation of records made or kept (EEOC, 1-year floor; retained until final
   disposition if a charge is filed) - <https://www.ecfr.gov/current/title-29/subtitle-B/chapter-XIV/part-1602/subpart-C/section-1602.14>
10. 29 CFR 516.5 / 516.6 - Records to be preserved (FLSA payroll records 3 years; wage-computation
    records 2 years) - <https://www.ecfr.gov/current/title-29/subtitle-B/chapter-V/subchapter-A/part-516/subpart-A/section-516.5>
11. Common settings for retention policies and retention label policies - "Relabeling at the end of the
    retention period" (confirms `-ComplianceTagForNextStage`'s behavior: replacement label's own retention
    settings apply, chaining is unlimited, a regulatory record can't be relabeled, up to 7-day sync on
    change, can't delete a label selected as a replacement) - <https://learn.microsoft.com/purview/retention-settings#relabeling-at-the-end-of-the-retention-period>
12. Rescission of Executive Order 11246 Implementing Regulations (Federal Register; effective October 26,
    2026) - <https://www.federalregister.gov/documents/2025/07/01/2025-12276/rescission-of-executive-order-11246-implementing-regulations>
13. Get-ComplianceTag - <https://learn.microsoft.com/powershell/module/exchangepowershell/get-compliancetag>
14. Use file plan to create and manage retention labels - `ComplianceTagForNextStage` import property
    (identically named to the PowerShell parameter; "the name of a replacement label to be applied at the
    end of the retention period. Do not specify this property if Regulatory is TRUE") - <https://learn.microsoft.com/purview/file-plan-manager#import-retention-labels-into-your-file-plan>

> Re-verify all links, cmdlet parameters, licensing, the `MultiStageReviewerMetadata` read-back property,
> and the irreversibility behaviors against current Microsoft Learn before a customer-facing deployment.
> Triggered events and applied record labels are irreversible - this scenario is deliberately conservative
> (dry-run, gated event, create-or-report, no force-removal of records, no unconfirmed read-back treated as
> a hard failure).