---
part: "runbook"
parent: "data-lifecycle-management/adaptive-protection-deleted-content-preservation"
---
## Implementation steps

### Enable the control (portal-only - no script exists for this step)

1. Confirm Adaptive Protection is already on for the tenant (*Dynamic Risk-Based DLP Enforcement* (the implementation steps)). If it was turned on **before** this Data Lifecycle
   Management integration existed in your tenant, the auto-labeling policy is **not** created
   automatically - you must opt in explicitly, which is exactly what the next step does either
   way.
2. Sign in to the [Microsoft Purview portal](https://purview.microsoft.com/) → **Solutions** →
   **Settings** → **Solution settings** → **Data lifecycle management** → **Adaptive protection**.
3. Turn **"Adaptive protection in Data Lifecycle Management"** **on**, and select **Save**. You will not be able to turn this on unless Adaptive Protection is already
   on for the tenant.
4. Confirm: the **Adaptive Protection** dashboard's summary tab shows the message *"Your
   organization is also being dynamically protected from users who might potentially delete
   critical data"* - the only in-portal confirmation surface; there is no
   dedicated metrics widget for this control.
5. Allow up to **36 hours** before expecting the control to actually apply to activity.

### PowerShell path (evidence and verification, not enablement)

```powershell
# Connect (certificate app-only preferred - Automation surface Section 3)
Connect-ExchangeOnline -AppId $AppId -Certificate $Cert -Organization 'contoso.onmicrosoft.com'

# Prove the control has fired (health check - never asserts a definitive on/off status; see Section 7)
./validate/Test-AdaptiveProtectionDlmPreservation.ps1 -LookbackDays 30

# Build/maintain the rolling audit-evidence trail (dry run first)
./deploy/Export-AdaptiveProtectionPreservationEvidence.ps1 -OutputCsvPath ./out/ap-dlm-preservation.csv -WhatIf
./deploy/Export-AdaptiveProtectionPreservationEvidence.ps1 -OutputCsvPath ./out/ap-dlm-preservation.csv
```

## Configuration reference

| Setting | Value | Notes |
|---|---|---|
| Preservation duration | **120 days**, fixed | Cannot be changed, cannot vary by risk level or location |
| Scope | Tenant-wide, single policy | Not a per-user or per-location object; can't be narrowed |
| Locations covered | SharePoint, OneDrive, Exchange Online | Not Teams chat, not other workloads |
| Trigger | User currently assigned **Elevated** insider risk level by Adaptive Protection, deletes content | Moderate/Minor risk levels do **not** trigger this control |
| Enable/disable cmdlet | **None** | Portal-only - section 5 |
| Audit Operations | `SharePointDataProactivelyPreserved` ("Retained file proactively"), `ExchangeDataProactivelyPreserved` ("Retained email item proactively") | `Search-UnifiedAuditLog -Operations <these>`, no `-RecordType` value documented specifically for them |
| Restore path | **Contact Microsoft Support** | No self-service restore cmdlet/API; the evidence CSV this scenario produces is the artifact for that request |
| Disable consequence | Releases **all currently-preserved items**, tenant-wide, immediately | Not a pause - see the rollback runbook |

Exact cmdlet syntax and Learn sources are cited in each script's `.NOTES`.

## Operations and tuning

**KPIs / signals:** count of preservation events per rolling window (`deploy/
Export-AdaptiveProtectionPreservationEvidence.ps1`'s row count over time) - a sudden spike
correlates with a spike in Elevated-risk-user deletions and should route to the same insider risk
triage process as the feeder IRM policy's own alerts, not be treated as a separate signal.

**Recommended cadence:** run `validate/Test-AdaptiveProtectionDlmPreservation.ps1` and `deploy/
Export-AdaptiveProtectionPreservationEvidence.ps1` **daily** - the daily-scheduled pattern this
scenario's sibling scripts elsewhere in this library already use for rolling audit trails.
Standard Audit's 180-day retention means a daily/weekly cadence keeps the rolling CSV as the
durable record well past the audit log's own retention window (`deploy/
Export-AdaptiveProtectionPreservationEvidence.ps1`'s own `.NOTES`).

**Change management:** because turning the control off releases everything currently preserved, treat any change to this toggle - on or off - as a reviewed, deliberate
action, not routine tuning. There is nothing to "tune" in the control itself (the configuration reference, fixed 120 days,
fixed scope). Keep **Insider Risk Management**/**Insider Risk Management Admins** role-group
membership minimal - that membership is also who can disable this control.

**Alerting:** forward the two audit Operations to your SIEM for near-real-time notification
rather than relying solely on the daily export/validate cadence above for time-sensitive
investigations. Once a specific user becomes the subject of an actual investigation, escalate to a
real eDiscovery hold - don't rely on this control alone past that point.

## Rollback and decommission

See the rollback runbook. Quick reference: this scenario's own code has nothing to roll back (read-only).
Disabling the underlying control is a portal action that **immediately releases all currently-preserved content** - not a pause. Capture a final evidence export and secure anything still
relevant (independent hold or a Microsoft Support restore request) **before** disabling.

## References

1. Help dynamically mitigate risks with Adaptive Protection (120-day mechanic, Elevated-risk
   trigger, toggle path, disable consequence, 36-hour timing, dashboard banner, permissions link,
   no self-service restore) - <https://learn.microsoft.com/purview/insider-risk-management-adaptive-protection>
2. Learn about retention policies and retention labels - "Dynamically mitigate the risk of
   accidental or malicious deletes" (preview status, opt-in requirement, exact turn-on/off portal
   steps, "not visible in the Microsoft Purview portal", eDiscovery-searchable, and - re-fetched
   again 2026-09-27 to close the role-group VERIFY - the "required permissions" link on the toggle
   itself) - <https://learn.microsoft.com/purview/retention#dynamically-mitigate-the-risk-of-accidental-or-malicious-deletes>
   - directly re-fetched (not search-snippet-only) during this build and re-verified 2026-09-27.
3. Insider Risk Management permissions (role groups) - <https://learn.microsoft.com/purview/insider-risk-management-permissions>
4. Audit log activities - Retention policy and retention label activities (Operation names) - <https://learn.microsoft.com/purview/audit-log-activities#retention-policy-and-retention-label-activities>
5. Search-UnifiedAuditLog reference - <https://learn.microsoft.com/powershell/module/exchangepowershell/search-unifiedauditlog>
6. [Licensing matrix, section 2](/docs/licensing-matrix/#2-master-capability--license-matrix) (Adaptive Protection licensing row)
7. [RBAC model, section 4](/docs/rbac-model/#4-purview-role-groups-by-module-representative-not-exhaustive) (Insider Risk Management/Adaptive Protection role groups), the configuration reference (Exchange
   Online audit-search role dependency)

> Re-verify all links and the preview status against current Microsoft Learn before a
> customer-facing deployment. The role-group question is resolved against documentation
> but, like any permissions claim in this library, is worth a pilot-tenant spot check before relying
> on it operationally.