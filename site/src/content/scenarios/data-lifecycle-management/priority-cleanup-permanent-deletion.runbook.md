---
part: "runbook"
parent: "data-lifecycle-management/priority-cleanup-permanent-deletion"
---
## Implementation steps

### PowerShell path

```powershell
# Connect (certificate app-only preferred - docs/automation-surface.md Section 3)
Connect-IPPSSession -AppId $AppId -Certificate $Cert -Organization 'contoso.onmicrosoft.com'

# 1. Dry run - prints the exact New-ComplianceTag / New-RetentionCompliancePolicy / -Rule cmdlets
./deploy/New-PriorityCleanupPermanentDeletionPolicy.ps1 -ConfigPath ./deploy/config/priority-cleanup-permanent-deletion.json -Simulate -DryRun

# 2. Deploy the SHARED base objects in SIMULATION mode (mandatory for this workload)
./deploy/New-PriorityCleanupPermanentDeletionPolicy.ps1 -ConfigPath ./deploy/config/priority-cleanup-permanent-deletion.json -Simulate

# 3. MANDATORY MANUAL STEP - no CLI/Graph equivalent (see Section 3/4/11):
#    Purview portal > Data Lifecycle Management > Priority cleanup > open the policy >
#    "Choose what to do with the content" > select "Delete data permanently".
#    VERIFY (pilot tenant) this is even a valid action against a PowerShell-provisioned policy -
#    design.md Section 4 documents the two open readings.

# 4. Review simulation sample results in the portal - a SECOND, DIFFERENT Priority Cleanup Admin
#    must do this review.

# 5. That second admin turns the policy on:
./deploy/New-PriorityCleanupPermanentDeletionPolicy.ps1 -ConfigPath ./deploy/config/priority-cleanup-permanent-deletion.json -EnforceSimulation

# 6. Validate the deployed base objects (does NOT confirm permanent-deletion mode - see Section 7)
./validate/Test-PriorityCleanupPermanentDeletionPolicy.ps1 -ConfigPath ./deploy/config/priority-cleanup-permanent-deletion.json
```

### Portal reference

The full policy-creation wizard, including the content-disposition selection, is described end to
end by Microsoft as a portal flow: **Data Lifecycle Management → Priority cleanup → + Create a
priority cleanup**, through name/description, scope, query, **"Choose what to do with the content"
(select "Delete data permanently")**, approvers, and simulation mode. Approving
pending disposals happens only in the portal - **Pending cleanups → select items → Approve disposal**
- there is no PowerShell or Graph cmdlet for this step, same gap as the sibling scenario.

## Configuration reference

| Setting | Value this scenario uses | Notes |
|---|---|---|
| Label cmdlet | `New-ComplianceTag -PriorityCleanup` | Identical parameter shape to the sibling scenario - `-RetentionAction`, `-RetentionDuration`, `-RetentionType`, `-MultiStageReviewProperty` |
| `RetentionAction` | `Delete` | Only value that applies - confirmed the parameter accepts exactly `Delete`/`Keep`/`KeepAndDelete`, **no fourth "permanent" value exists** |
| Content-disposition mode | **Not scriptable** | "Delete data permanently" vs. default Recycle-Bin outcome - portal-wizard-only, see the implementation steps and the known limitations |
| Policy cmdlet | `New-RetentionCompliancePolicy -PriorityCleanup -IsSimulation` | Same as sibling; needs ≥1 of `-OneDriveLocation`/`-SharePointLocation` |
| Scope | Deliberately **narrow, static, incident-specific** (named sites/accounts) | Unlike the sibling's broad/continual scope - see the design notes |
| Rule cmdlet | `New-RetentionComplianceRule -PriorityCleanup -ApplyComplianceTag -ContentMatchQuery` | Query is **incident-specific**, not a generic worked example like the sibling's `ProgID:Media AND ProgID:Meeting` - construct per §config `_ruleNote` |
| Audit operation (disposal) | **`PriorityCleanupFileDeleted`** | Distinct from the sibling's `PriorityCleanupFileRecycled` - the only scriptable confirmation that permanent deletion occurred |
| Classification check | `Get-ComplianceTag`/`Get-RetentionCompliancePolicy`/`Get-RetentionComplianceRule -PriorityCleanup` | Same filter switch as the sibling; **cannot** distinguish permanent-deletion mode |

Exact cmdlet syntax and Learn sources are cited in each script's `.NOTES`.

## Operations and tuning

**KPIs / signals:** count of `PriorityCleanupFileDeleted` events per Cleanup ID (the true measure of
this scenario's effect - `PriorityCleanupTagApplied`/`PriorityCleanupFileRecycled` indicate the
weaker sibling outcome instead); time-to-approval for the conditional eDiscovery-admin stage.
**Change management:** because this is an incident-driven, narrow-scope control rather than a
standing policy, do not leave a permanent-deletion-configured policy running indefinitely after the
triggering incident is resolved - disable it (the rollback runbook Stage 1) once the confirmed-exposed set is
fully disposed of, and re-provision fresh per incident rather than widening an existing one. **SIEM
integration:** forward `PriorityCleanupFileDeleted` events to Sentinel/SIEM as the authoritative,
high-severity signal that irreversible deletion occurred - treat every such event as requiring an
audit trail entry in the incident record, not routine telemetry. **Query discipline:** because there
is no generic worked-example query for this use case (unlike the sibling's Teams-recording pattern),
every deployment's `contentMatchQuery` is bespoke - require a second reviewer on the query itself,
not just on the simulation results, before ever proceeding past simulation.

## Rollback and decommission

See the rollback runbook. Quick reference: `./deploy/Remove-PriorityCleanupPermanentDeletionPolicy.ps1`
disables the policy (stops identifying *new* items); `-Delete` removes the policy + rule. **Nothing
in this scenario undoes an item that has already been permanently deleted** - unlike the
*Priority Cleanup for SharePoint & OneDrive* sibling's Recycle Bin recourse, there is **no recovery path**
once `PriorityCleanupFileDeleted` has fired for an item. Rollback here only stops *further* items
from being identified and disposed of.

## References

1. Permanently delete files with Microsoft Purview Priority Cleanup (feature overview; prerequisites; public preview rollout date; portal configuration steps; PriorityCleanupFileDeleted audit operation; review-set exception) - <https://learn.microsoft.com/purview/priority-cleanup-permanent-deletion>
2. Override holds to clean up files for Copilot and reclaim storage - records/regulatory-record exception; shared base prerequisites and approver model - <https://learn.microsoft.com/purview/priority-cleanup-onedrive-sharepoint>
3. New-ComplianceTag (`-PriorityCleanup` parameter set; `-RetentionAction` accepts only Delete/Keep/KeepAndDelete - confirmed directly against this reference during this build) - <https://learn.microsoft.com/powershell/module/exchangepowershell/new-compliancetag>
4. New-RetentionCompliancePolicy (`-OneDriveLocation`, `-SharePointLocation`, `-PriorityCleanup`, `-IsSimulation`) - <https://learn.microsoft.com/powershell/module/exchangepowershell/new-retentioncompliancepolicy>
5. Permanently delete files with Microsoft Purview Priority Cleanup - monitoring section (`PriorityCleanupFileDeleted` operation, distinct from the sibling's `PriorityCleanupFileRecycled`) - <https://learn.microsoft.com/purview/priority-cleanup-permanent-deletion#monitor-permanent-deletion>
6. Turn off priority cleanup for the tenant (shared toggle and licensing across all priority cleanup workloads) - <https://learn.microsoft.com/purview/priority-cleanup-onedrive-sharepoint#turn-off-priority-cleanup-for-the-tenant>
7. New-RetentionComplianceRule (`-PriorityCleanup`, `-ApplyComplianceTag`, `-ContentMatchQuery`) - <https://learn.microsoft.com/powershell/module/exchangepowershell/new-retentioncompliancerule>
8. Set-RetentionCompliancePolicy (`-StartSimulation`, `-EnforceSimulationPolicy`) - <https://learn.microsoft.com/powershell/module/exchangepowershell/set-retentioncompliancepolicy>
9. Get-ComplianceTag / Get-RetentionCompliancePolicy / Get-RetentionComplianceRule (`-PriorityCleanup` filter switch) - <https://learn.microsoft.com/powershell/module/exchangepowershell/get-compliancetag>
10. Plan for Microsoft Purview compliance and risk management solutions - GCC High deployments (Step 4 capability-difference table; re-fetched 2026-09-28 to check for a Priority Cleanup row - none exists, for the base feature or permanent deletion specifically) - <https://learn.microsoft.com/office365/servicedescriptions/microsoft-365-service-descriptions/microsoft-365-tenantlevel-services-licensing-guidance/plan-for-microsoft-purview-gcc-high-deployments>
11. Microsoft Purview service description - Data Lifecycle & Records Management licensing table (lists Microsoft 365 E5/A5/G5, Microsoft Purview Suite/EDU/**GOV**/FLW, and Office 365 E5/A5/G5 as valid Priority Cleanup license paths, with no cloud-environment carve-out stated) - <https://learn.microsoft.com/office365/servicedescriptions/microsoft-365-service-descriptions/microsoft-365-tenantlevel-services-licensing-guidance/microsoft-purview-service-description#microsoft-purview-data-lifecycle-&-records-management>

> Re-verify all links, cmdlet parameters, licensing, tenant-availability timing, and - especially -
> whether a confirmed CLI/Graph path for "Delete data permanently" has since been published, before
> a customer-facing deployment.