---
part: "runbook"
parent: "data-lifecycle-management/retention-labels-financial-records"
---
## Implementation steps

### PowerShell path

```powershell
# Connect (certificate app-only preferred - docs/automation-surface.md §3)
Connect-IPPSSession -AppId $AppId -Certificate $Cert -Organization 'contoso.onmicrosoft.com'

# 1. Dry run - prints the exact New-ComplianceTag / New-RetentionCompliancePolicy / -Rule cmdlets
./deploy/New-FinancialRecordsRetention.ps1 -ConfigPath ./deploy/config/financial-records-retention.json -DryRun

# 2. Deploy the label + auto-apply policy + rule (after lab test + Records/Legal sign-off)
./deploy/New-FinancialRecordsRetention.ps1 -ConfigPath ./deploy/config/financial-records-retention.json

# 3. Validate
./validate/Test-FinancialRecordsRetention.ps1 -ConfigPath ./deploy/config/financial-records-retention.json
```

### Portal reference

The label, policy, and rule are visible in the [Microsoft Purview portal](https://purview.microsoft.com)
under **Records Management** (or **Data Lifecycle Management**) → **File plan / Labels** and →
**Label policies**. The **regulatory record** option is hidden in
the portal by default, which is why *label creation* is PowerShell-first - though,
per the correction in section 2, *distributing* a regulatory record label is never done by this scenario's
own policy/rule at all; see the sibling scenario. `-WhatIf` is non-functional in S&C PowerShell, so
the deploy/remove scripts ship a `-DryRun` instead.

## Configuration reference

| Setting | Value this scenario uses | Notes |
|---|---|---|
| Label cmdlet | `New-ComplianceTag` | Retention label |
| `RetentionAction` | `Keep` | `Keep` / `Delete` / `KeepAndDelete` |
| `RetentionDuration` | `2555` (≈7 years) | Days, or `Unlimited` |
| `RetentionType` | `CreationAgeInDays` | When the clock starts: `CreationAgeInDays` / `ModificationAgeInDays` / `TaggedAgeInDays` / `EventAgeInDays` |
| `Regulatory` | `$false` (default) | Set `$true` only if you intend to hand off to the publish sibling - auto-apply is skipped when true |
| `IsRecordLabel` | `$true` (default) | A plain **record** label - lockable, and the only one of the two auto-apply supports |
| Policy cmdlet | `New-RetentionCompliancePolicy` | Auto-apply label policy; needs ≥1 location; **only created when `Regulatory` is false** |
| Locations | `SharePointLocation` (finance site) | Also `ExchangeLocation`, `OneDriveLocation`, etc. |
| Rule cmdlet | `New-RetentionComplianceRule -ApplyComplianceTag` | One rule per policy; `-ContentMatchQuery` (KQL) or `-ContentContainsSensitiveInformation`; **no `-Name`** - documented mutually exclusive with `-ApplyComplianceTag` |
| Retry stuck distribution | `Set-RetentionCompliancePolicy -RetryDistribution` | If the policy status shows Off (Error) |

Exact cmdlet syntax and Learn sources are cited in each script's `.NOTES`.

## Operations and tuning

**KPIs / signals:** policy **DistributionStatus** (should reach a healthy state; Off (Error) → retry);
count of items labeled over time (via content search / Data Lifecycle reports); disposition backlog
(if using KeepAndDelete). **Tuning:** keep the auto-apply **match query narrow** - precision matters
far more than recall when the label locks content as a record; start with a tightly-scoped location +
query, validate, then widen. Auto-apply latency is up to 7 days; don't expect instant labeling.

**Change management:** treat any change to the label or its scope as a controlled, Records/Legal-reviewed change - a record label needs a records manager to walk back, and a regulatory record can
never be walked back at all. Keep the config file under version control as the record of what was
deployed and why.

## Rollback and decommission

See the rollback runbook. Quick reference: `./deploy/Remove-FinancialRecordsRetention.ps1` **disables** the
auto-apply policy (stops labeling *new* content, and only exists at all for a record label - see section 2);
`-Delete` removes the policy + rule. The **label is not force-removed**: a record label that's been
applied can only be unlocked/removed by a records manager, and a regulatory record label that's been
applied **cannot** be removed by anyone and its retention **cannot** be shortened. Removing the policy
never releases content already labeled.

## References

1. Learn about records management / regulatory records (immutability: can't remove/relabel/unlock/shorten; PowerShell-only creation) - <https://learn.microsoft.com/purview/records-management>
2. Declare records by using retention labels ("...for labels that mark items as records (but not regulatory records), auto-apply those labels...") - <https://learn.microsoft.com/purview/declare-records>
3. Automatically apply a retention label to retain or delete content (auto-apply policy, up to 7-day latency, RetryDistribution, classifier limits; "isn't supported for regulatory records... require a published retention label policy") - <https://learn.microsoft.com/purview/apply-retention-labels-automatically>
4. New-ComplianceTag (retention label; RetentionAction/Duration/Type, IsRecordLabel, Regulatory) - <https://learn.microsoft.com/powershell/module/exchangepowershell/new-compliancetag>
5. New-RetentionCompliancePolicy (retention label policy; locations) - <https://learn.microsoft.com/powershell/module/exchangepowershell/new-retentioncompliancepolicy>
6. Microsoft Purview service description - Records Management / Data Lifecycle Management licensing - <https://learn.microsoft.com/office365/servicedescriptions/microsoft-365-service-descriptions/microsoft-365-tenantlevel-services-licensing-guidance/microsoft-purview-service-description>
7. New-RetentionComplianceRule (-ApplyComplianceTag / -PublishComplianceTag, -ContentMatchQuery, -ContentContainsSensitiveInformation) - <https://learn.microsoft.com/powershell/module/exchangepowershell/new-retentioncompliancerule>
8. PowerShell cmdlets for retention policies and retention labels - <https://learn.microsoft.com/purview/retention-cmdlets>
9. Bulk create and publish retention labels by using PowerShell - <https://learn.microsoft.com/purview/bulk-create-publish-labels-using-powershell>

> Re-verify all links, cmdlet parameters, licensing, and the regulatory-record behavior against
> current Microsoft Learn before a customer-facing deployment. Regulatory records are irreversible -
> the scenario is deliberately conservative (dry-run, create-or-report, no force-remove of records).