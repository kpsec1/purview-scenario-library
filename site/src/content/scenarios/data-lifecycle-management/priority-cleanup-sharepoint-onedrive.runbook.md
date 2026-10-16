---
part: "runbook"
parent: "data-lifecycle-management/priority-cleanup-sharepoint-onedrive"
---
## Implementation steps

### PowerShell path

```powershell
# Connect (certificate app-only preferred - Automation surface Section 3)
Connect-IPPSSession -AppId $AppId -Certificate $Cert -Organization 'contoso.onmicrosoft.com'

# 1. Dry run - prints the exact New-ComplianceTag / New-RetentionCompliancePolicy / -Rule cmdlets
./deploy/New-PriorityCleanupSharePointOneDrivePolicy.ps1 -ConfigPath ./deploy/config/priority-cleanup-sharepoint-onedrive.json -Simulate -DryRun

# 2. Deploy in SIMULATION mode - the ONLY supported creation path for this workload (mandatory, not
# merely recommended)
./deploy/New-PriorityCleanupSharePointOneDrivePolicy.ps1 -ConfigPath ./deploy/config/priority-cleanup-sharepoint-onedrive.json -Simulate

# 3. Review simulation sample results in the portal (Data Lifecycle Management > Priority cleanup >
# View simulation details) - a SECOND, DIFFERENT Priority Cleanup Admin must do this review.

# 4. That second admin turns the policy on:
./deploy/New-PriorityCleanupSharePointOneDrivePolicy.ps1 -ConfigPath ./deploy/config/priority-cleanup-sharepoint-onedrive.json -EnforceSimulation

# 5. Validate the deployed objects (not approvals - see Section 7)
./validate/Test-PriorityCleanupSharePointOneDrivePolicy.ps1 -ConfigPath ./deploy/config/priority-cleanup-sharepoint-onedrive.json
```

A simulation-mode policy can run for up to 7 days before it must be restarted.
Microsoft also states **"the last person to edit the policy can't also turn it on"** - the operator
running step 4 must be a different admin from whoever ran step 2 against this same policy; this
script cannot verify that itself (no documented API exposes "who last edited this policy").

### Portal reference

The label, policy, and rule are visible under **Data Lifecycle Management → Priority cleanup** in
the [Microsoft Purview portal](https://purview.microsoft.com). **Approving
pending disposals happens only in the portal** - Data Lifecycle Management → Priority cleanup →
Pending cleanups - there is no PowerShell or Graph cmdlet for this step. `-WhatIf` is
non-functional in S&C PowerShell; the scripts ship `-DryRun` instead.

## Configuration reference

| Setting | Value this scenario uses | Notes |
|---|---|---|
| Label cmdlet | `New-ComplianceTag -PriorityCleanup` | Same mandatory parameter set as the Exchange sibling: `-RetentionAction`, `-RetentionDuration`, `-RetentionType`, `-MultiStageReviewProperty` |
| `RetentionAction` | `Delete` | Required value for priority cleanup |
| `RetentionDuration` / `RetentionType` | `0` / `TaggedAgeInDays` | Carried over from the Exchange sibling's best-effort mapping of "delete as soon as possible" - **VERIFY**, see the design notes |
| `MultiStageReviewProperty` | 1-stage JSON: `EDiscoveryAdmin` only | **Fewer stages than Exchange** - no separate retention-manager stage for this workload. Whether a `PriorityCleanupAdmin` stage entry is also needed for the pre-turn-on two-person check is this scenario's own open construction gap - **VERIFY**, see the design notes |
| Policy cmdlet | `New-RetentionCompliancePolicy -PriorityCleanup -IsSimulation` | Needs ≥1 of `-OneDriveLocation`/`-SharePointLocation`; no `-Enabled`-at-creation path (simulation mandatory) |
| Simulation | `-IsSimulation` at create; `Set-RetentionCompliancePolicy -StartSimulation $true` to run it; `-EnforceSimulationPolicy $true` to turn on | **Required**, not optional, for SharePoint/OneDrive |
| Rule cmdlet | `New-RetentionComplianceRule -PriorityCleanup -ApplyComplianceTag -ContentMatchQuery` | `ProgID:Media AND ProgID:Meeting` - Microsoft's own verbatim worked example for Teams recordings/transcripts |
| Classification check | `Get-ComplianceTag`/`Get-RetentionCompliancePolicy`/`Get-RetentionComplianceRule -PriorityCleanup` | Official filter switch; same pattern as the Exchange sibling |
| Redistribute a stuck policy | `Set-RetentionCompliancePolicy -RetryDistribution` | Same mechanism as ordinary retention policies |

Exact cmdlet syntax and Learn sources are cited in each script's `.NOTES`.

## Operations and tuning

**KPIs / signals:** count of `PriorityCleanupTagApplied`/`PriorityCleanupFileRecycled` audit events
per Cleanup ID; time-to-approval for the conditional eDiscovery-admin stage (email reminders fire
weekly); policy `DistributionStatus`. **Tuning - the "stale" query has no
built-in age filter:** `ProgID:Media AND ProgID:Meeting` matches **all** Teams recordings/
transcripts, not just old ones - no confirmed relative-date ("older than 90 days") operator exists
for this KeyQL surface. Running it as a standing, continual policy (as Microsoft's own guidance
recommends for this use case) means every matching recording is moved to the
Recycle Bin, relying on the Recycle Bin's own retention window as the real age buffer rather than
the query itself. If a harder age cutoff is required, review and narrow the query on a recurring
schedule instead - this scenario does not script that review. **Change management:** because
simulation is mandatory for **any** change other than the description, budget for a review cycle
(hours, per Microsoft) before every meaningful edit, not just at initial setup. **SIEM
integration:** forward `PriorityCleanupTagApplied`/`PriorityCleanupFileRecycled` audit events to
Sentinel/SIEM given the lack of friendly portal names - see the Blue Team review.

## Rollback and decommission

See the rollback runbook. Quick reference: `./deploy/Remove-PriorityCleanupSharePointOneDrivePolicy.ps1`
disables the policy (stops identifying *new* items); `-Delete` removes the policy + rule. **Neither
undoes an approval that has already completed** - Microsoft states items may still move to the
Recycle Bin even after the policy is deleted, if the approval process for them was already complete. Items already in the Recycle Bin can still be recovered from there within its
own retention window - this is a materially softer rollback story than the Exchange sibling's
irreversible permanent deletion. The label is not force-removed by default.

## References

1. Override holds to clean up files for Copilot and reclaim storage (SharePoint/OneDrive priority cleanup; typical use cases; mandatory simulation; create-a-policy walkthrough) - <https://learn.microsoft.com/purview/priority-cleanup-onedrive-sharepoint>
2. Override holds to clean up files for Copilot and reclaim storage - monitoring, audit operations (`PriorityCleanupTagApplied`/`PriorityCleanupFileRecycled`), Recycle Bin mechanism - <https://learn.microsoft.com/purview/priority-cleanup-onedrive-sharepoint#how-to-monitor-priority-cleanup>
3. Expedite the permanent deletion of sensitive information from mailboxes (Exchange vs. SharePoint/OneDrive comparison table - Preservation Lock override conditionality) - <https://learn.microsoft.com/purview/priority-cleanup-exchange#comparing-priority-cleanup-for-different-workloads>
4. Turn off priority cleanup for the tenant (shared toggle across Exchange and SharePoint/OneDrive) - <https://learn.microsoft.com/purview/priority-cleanup-onedrive-sharepoint#turn-off-priority-cleanup-for-the-tenant>
5. Override holds to clean up files for Copilot and reclaim storage - prerequisites, approver roles, approval process, limitations - <https://learn.microsoft.com/purview/priority-cleanup-onedrive-sharepoint#prerequisites-for-priority-cleanup>
6. New-RetentionCompliancePolicy (`-OneDriveLocation`, `-SharePointLocation`, `-PriorityCleanup`, `-IsSimulation`) - <https://learn.microsoft.com/powershell/module/exchangepowershell/new-retentioncompliancepolicy>
7. New-ComplianceTag (`-PriorityCleanup` parameter set; `-MultiStageReviewProperty` JSON shape) - <https://learn.microsoft.com/powershell/module/exchangepowershell/new-compliancetag>
8. New-RetentionComplianceRule (`-PriorityCleanup`, `-ApplyComplianceTag`, `-ContentMatchQuery`) - <https://learn.microsoft.com/powershell/module/exchangepowershell/new-retentioncompliancerule>
9. Get-ComplianceTag (`-PriorityCleanup` filter switch) - <https://learn.microsoft.com/powershell/module/exchangepowershell/get-compliancetag>
10. Get-RetentionCompliancePolicy / Get-RetentionComplianceRule (`-PriorityCleanup` filter switch) - <https://learn.microsoft.com/powershell/module/exchangepowershell/get-retentioncompliancepolicy>
11. Set-RetentionCompliancePolicy (`-StartSimulation`, `-EnforceSimulationPolicy`, `-RetryDistribution`) - <https://learn.microsoft.com/powershell/module/exchangepowershell/set-retentioncompliancepolicy>
12. Permanently delete files with Microsoft Purview Priority Cleanup (the separate permanent-deletion sub-feature, out of scope for this fragment and built as its own sibling scenario; public preview from 2026-08-24) - <https://learn.microsoft.com/purview/priority-cleanup-permanent-deletion>
13. Use the condition builder to create search queries in eDiscovery (`(c:c)`/`c:s` as condition-builder-generated KeyQL notation, not manual-entry operators; Sender/Author and Subject/Title as common properties spanning mail and documents) - <https://learn.microsoft.com/purview/edisc-condition-builder>

> Re-verify all links, cmdlet parameters, licensing, and - especially - the `-MultiStageReviewProperty`
> single-stage shape and preview status against current Microsoft Learn before a customer-facing
> deployment.