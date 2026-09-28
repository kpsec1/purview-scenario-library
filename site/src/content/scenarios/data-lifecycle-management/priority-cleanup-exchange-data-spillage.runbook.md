---
part: "runbook"
parent: "data-lifecycle-management/priority-cleanup-exchange-data-spillage"
---
## Implementation steps

### PowerShell path

```powershell
# Connect (certificate app-only preferred - Automation surface Section 3)
Connect-IPPSSession -AppId $AppId -Certificate $Cert -Organization 'contoso.onmicrosoft.com'

# 1. Dry run - prints the exact New-ComplianceTag / New-RetentionCompliancePolicy / -Rule cmdlets
./deploy/New-PriorityCleanupExchangePolicy.ps1 -ConfigPath ./deploy/config/priority-cleanup-exchange.json -Simulate -DryRun

# 2. Deploy in SIMULATION mode (recommended default - not required for Exchange, but Microsoft's
# own guidance, and this scenario's default posture for a hold-overriding control)
./deploy/New-PriorityCleanupExchangePolicy.ps1 -ConfigPath ./deploy/config/priority-cleanup-exchange.json -Simulate

# 3. Review simulation sample results in the portal (Data Lifecycle Management > Priority cleanup >
# View simulation details) - a SECOND priority cleanup admin must do this review.

# 4. That second admin enforces the reviewed simulation, turning the policy live:
./deploy/New-PriorityCleanupExchangePolicy.ps1 -ConfigPath ./deploy/config/priority-cleanup-exchange.json -EnforceSimulation

# 5. Validate the deployed objects (not approvals - see Section 7)
./validate/Test-PriorityCleanupExchangePolicy.ps1 -ConfigPath ./deploy/config/priority-cleanup-exchange.json
```

Skipping simulation (`-Enabled` instead of `-Simulate`) is supported - Microsoft states simulation is
*"No (but recommended)"* for Exchange, unlike SharePoint/OneDrive where it's mandatory
 - but this scenario's scripts still refuse to deploy with **no** explicit choice at
all (`-Simulate`, `-Enabled`, or `-DryRun`); see the design notes. The SharePoint/OneDrive sibling
(*Priority Cleanup for SharePoint & OneDrive*) has no `-Enabled` path
at all, for exactly this reason.

### Portal reference

The label, policy, and rule are visible under **Data Lifecycle Management → Priority cleanup** in the
[Microsoft Purview portal](https://purview.microsoft.com). **Approving pending
deletions happens only in the portal** - Data Lifecycle Management → Priority cleanup → Pending
cleanups - there is no PowerShell or Graph cmdlet for this step. `-WhatIf` is non-functional in
S&C PowerShell; the scripts ship `-DryRun` instead.

## Configuration reference

| Setting | Value this scenario uses | Notes |
|---|---|---|
| Label cmdlet | `New-ComplianceTag -PriorityCleanup` | Mandatory in this parameter set: `-RetentionAction`, `-RetentionDuration`, `-RetentionType`, `-MultiStageReviewProperty` |
| `RetentionAction` | `Delete` | Required value for priority cleanup |
| `RetentionDuration` / `RetentionType` | `0` / `TaggedAgeInDays` | This scenario's best-effort mapping of "delete as soon as possible" - **VERIFY**, see the design notes |
| `MultiStageReviewProperty` | 3-stage JSON: `PriorityCleanupAdmin` → `RetentionManager` → `EDiscoveryAdmin` | This scenario's construction from the documented parameter shape - **VERIFY** stage naming/order, see the design notes |
| Policy cmdlet | `New-RetentionCompliancePolicy -PriorityCleanup -SkipPriorityCleanupConfirmation` | Needs ≥1 `-ExchangeLocation` |
| Simulation | `-IsSimulation` at create; `Set-RetentionCompliancePolicy -StartSimulation $true` to run it; `-EnforceSimulationPolicy $true` to go live | Recommended, not required, for Exchange |
| Rule cmdlet | `New-RetentionComplianceRule -PriorityCleanup -ApplyComplianceTag -ContentMatchQuery` | KeyQL; excludes `SenderAuthor`, `SubjectTitle`, `(c:c)`, `(c:s)` - **not** supported for priority cleanup even though eDiscovery search otherwise allows them |
| Classification check | `Get-ComplianceTag`/`Get-RetentionCompliancePolicy`/`Get-RetentionComplianceRule -PriorityCleanup` | Official filter switch; used instead of guessing an unconfirmed boolean property name |
| Redistribute a stuck policy | `Set-RetentionCompliancePolicy -RetryDistribution` | Same mechanism as ordinary retention policies |

Exact cmdlet syntax and Learn sources are cited in each script's `.NOTES`.

## Operations and tuning

**KPIs / signals:** count of `PriorityCleanupTagApplied`/`PriorityCleanupDelete` audit events per
Cleanup ID; time-to-approval per stage (email reminders fire weekly, so a stalled
approval is visible within a week); policy `DistributionStatus`. **Tuning:** the `ContentMatchQuery`
is the single highest-leverage control - an over-broad query destroys content permanently and without
recourse, so start as narrow as the confirmed spillage evidence allows (specific attachment name +
date range, as in this scenario's sample config) and widen only with sign-off. **Change management:**
every deployment of this control should be a one-off, individually justified incident response, not a
standing policy - disable or delete it once the specific incident is closed, rather than leaving
it live "just in case." **SIEM integration:** forward `PriorityCleanupTagApplied`/`PriorityCleanupDelete`
audit events to Sentinel/SIEM given their severity and the lack of friendly portal names - see
the Blue Team review.

## Rollback and decommission

See the rollback runbook. Quick reference: `./deploy/Remove-PriorityCleanupExchangePolicy.ps1` disables the
policy (stops identifying *new* items); `-Delete` removes the policy + rule. **Neither undoes an
approval that has already completed** - Microsoft states items may still be permanently deleted even
after the policy is deleted, if the approval process for them was already complete.
The label is not force-removed by default.

## References

1. Expedite the permanent deletion of sensitive information from mailboxes (priority cleanup for Exchange; preview note; data-spillage use case; Preservation Lock guidance; records/review-set exceptions) - <https://learn.microsoft.com/purview/priority-cleanup-exchange>
2. Override holds to clean up files for Copilot and reclaim storage (SharePoint/OneDrive comparison table) - <https://learn.microsoft.com/purview/priority-cleanup-onedrive-sharepoint>
3. Permanently delete files with Microsoft Purview Priority Cleanup (SharePoint/OneDrive permanent-deletion sub-feature; public preview from 2026-08-24) - <https://learn.microsoft.com/purview/priority-cleanup-permanent-deletion>
4. New-ComplianceTag (`-PriorityCleanup` parameter set; `-MultiStageReviewProperty` JSON shape) - <https://learn.microsoft.com/powershell/module/exchangepowershell/new-compliancetag>
5. Expedite the permanent deletion of sensitive information from mailboxes - prerequisites, approver roles, approval process, limitations - <https://learn.microsoft.com/purview/priority-cleanup-exchange#prerequisites-for-priority-cleanup>
6. Microsoft Purview service description - Priority cleanup licensing (same tier as Data Lifecycle & Records Management) - <https://learn.microsoft.com/office365/servicedescriptions/microsoft-365-service-descriptions/microsoft-365-tenantlevel-services-licensing-guidance/microsoft-purview-service-description>
7. New-ComplianceTag full parameter reference - <https://learn.microsoft.com/powershell/module/exchangepowershell/new-compliancetag>
8. New-RetentionCompliancePolicy (`-PriorityCleanup`, `-SkipPriorityCleanupConfirmation`, `-IsSimulation`) - <https://learn.microsoft.com/powershell/module/exchangepowershell/new-retentioncompliancepolicy>
9. Get-ComplianceTag (`-PriorityCleanup` filter switch) - <https://learn.microsoft.com/powershell/module/exchangepowershell/get-compliancetag>
10. Get-RetentionCompliancePolicy / Get-RetentionComplianceRule (`-PriorityCleanup` filter switch) - <https://learn.microsoft.com/powershell/module/exchangepowershell/get-retentioncompliancepolicy>
11. Set-RetentionCompliancePolicy (`-StartSimulation`, `-EnforceSimulationPolicy`, `-RetryDistribution`) - <https://learn.microsoft.com/powershell/module/exchangepowershell/set-retentioncompliancepolicy>
12. New-RetentionComplianceRule (`-PriorityCleanup`, `-ApplyComplianceTag`, `-ContentMatchQuery`) - <https://learn.microsoft.com/powershell/module/exchangepowershell/new-retentioncompliancerule>

> Re-verify all links, cmdlet parameters, licensing, and - especially - the `-MultiStageReviewProperty`
> stage shape and preview status against current Microsoft Learn before a customer-facing deployment.
> This scenario is deliberately conservative (no default-on path, create-or-report, explicit
> "cannot recall a completed approval" rollback warning) because priority cleanup is irreversible by
> design.