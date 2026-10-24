---
part: "runbook"
parent: "insider-risk/security-policy-violations-by-departing-users"
---
## Implementation steps

### Step 1 - Assign permissions

Same as the sibling scenario's page step 1 of the implementation steps (Purview role groups, audit log confirmation).
Additionally confirm the operator has a Defender for Endpoint role capable of changing advanced
features (Step 2 below) - typically **Security Administrator**, or the granular permission
[RBAC model, section 12](/docs/rbac-model/#12-microsoft-defender-for-endpoint-portal-rbac---an-eighth-system-for-scenarios-that-configure-defender-for-endpoint-tenant-wide-settings) documents.

### Step 2 - Enable the Defender for Endpoint → Purview alert-sharing feature (manual, one-time)

1. Sign in to the [Microsoft Defender portal](https://security.microsoft.com).
2. **Settings** → **Endpoints** → **Advanced features**.
3. Locate **Share endpoint alerts with Microsoft Compliance Center** and toggle it **On**.
4. Select **Save preferences**.

This sends endpoint security alerts and their triage status to the Purview portal for
consumption by Insider Risk Management policies - it does not, by itself, create any policy or
send any alert data anywhere outside the tenant's own Microsoft 365/Defender data location. No Graph/PowerShell equivalent for this toggle was found during this build -
see the design notes goal 3.

### Step 3 - Configure which Defender for Endpoint alert triage statuses to import (recommended)

Purview portal → **Settings** → **Insider Risk Management** → **Intelligent detections** →
select one or more of **Unknown / New / In progress / Resolved**. Alerts import **daily**; the
same underlying Defender alert can generate multiple Insider Risk Management activity records as
its triage status changes if more than one status is selected - see the known limitations.

### Step 4 - Confirm or configure the HR data feed (reused from the sibling scenario)

If *Departing Employee Data Theft* is already deployed in this tenant,
its HR connector already satisfies this template's optional trigger - **skip to Step 5**.
Otherwise, follow that scenario's the implementation steps Steps 2-4 to register the connector app, create
the HR connector, and run `../departing-employee-data-theft/deploy/Send-HrTerminationRecord.ps1`
on a recurring schedule. This scenario does not ship a second copy of that script (the design notes goal 1).

### Step 5 - Create the Insider Risk Management policy (portal, not scriptable)

Purview portal → **Insider Risk Management** → **Policies** → **Create policy**:

1. Template: **Security policy violations by departing users**.
2. Name: `Security Policy Violations by Departing Users`. The template and name can't be changed
   after policy creation - confirm before continuing.
3. **Users and groups**: select the same population as the sibling scenario's policy, or a
   subset - up to **15,000** users can be actively scored under this template.
4. **Triggering events**: enable the HR connector resignation signal (Step 4) **and/or** **User
   account deleted from Microsoft Entra ID** - both are optional per Microsoft's own prerequisite
   table for this template (unlike the sibling's Data theft template, which lists the HR
   connector as its documented, if optional, primary trigger).
5. **Indicators**: select the **Microsoft Defender for Endpoint indicators (preview)** category.
   Microsoft's documentation does not enumerate the individual indicator names under this
   category (unlike, e.g., the Office/Device indicator lists the sibling scenario's manifest
   documents verbatim) - **VERIFY against the live policy-creation workflow at deploy time** which
   specific indicator toggles appear, and whether any other indicator categories (Office, Device,
   Cumulative exfiltration) are also selectable for this specific template; not confirmed by
   Microsoft Learn during this build.
6. **Review and submit.**

Use `deploy/policy/security-policy-violations-departing-users-policy-manifest.json` as the
checklist/reference while completing this workflow - it is not consumed by any API (see the
file's own `_comment` field and the design notes).

### Step 6 - Export correlated alerts for SIEM/ticketing integration (scripted, read-only)

```powershell
Connect-MgGraph -ClientId $AppId -TenantId $TenantId -CertificateThumbprint $Thumbprint

# Dry run - shows the query plan, calls nothing
./deploy/Export-SecurityViolationInsiderRiskAlerts.ps1 -WhatIf

# Pull the last 24 hours of security-violation IRM alerts, joined to their Defender
# for Endpoint alert detail where a correlated incidentId is found
./deploy/Export-SecurityViolationInsiderRiskAlerts.ps1 -SinceDateTime (Get-Date).AddDays(-1) -OutputPath ./security-violation-alerts.json
```

### Step 7 - Validate

```powershell
./validate/Test-SecurityViolationIrmSetup.ps1
```

## Configuration reference

| Setting | Value this scenario uses | Notes |
|---|---|---|
| Policy template | `Security policy violations by departing users` **(preview)** | Cannot be changed after creation |
| Triggering events | HR connector resignation/termination date **and/or** `User account deleted from Microsoft Entra ID` | Both optional per Microsoft's prerequisite table for this template - unlike the sibling scenario, neither is documented as the required primary |
| Indicator category | **Microsoft Defender for Endpoint indicators (preview)** | Individual indicator names not enumerated by Microsoft as of this writing - VERIFY at deploy time |
| Maximum users in scope | 15,000 (Microsoft-fixed limit for this template) | - separate from, and larger than, the sibling Data theft template's 20,000 (not the same number; don't conflate the two limits) |
| Defender for Endpoint alert import cadence | Daily | Not configurable to a shorter interval |
| Defender alert triage statuses imported | Operator-selected in Intelligent detections (Unknown/New/In progress/Resolved) | Selecting more than one status can produce multiple IRM activity records per underlying Defender alert - the known limitations |
| User-identity privacy | Pseudonymized (Microsoft default) | Not disabled by this scenario |
| Alert export mechanism | Microsoft Graph `GET /security/alerts_v2`, pulling both `microsoftInsiderRiskManagement`- and `microsoftDefenderForEndpoint`-sourced alerts, joined client-side by `incidentId` | Server-side `$filter` does not support `detectionSource` or `incidentId` - see the known limitations |
| Cross-policy-template disambiguation | Not attempted | `alertPolicyId` is populated on exported alerts but Microsoft doesn't document a way to map it back to a named Purview policy via any API - the known limitations |

## Operations and tuning

**This scenario's KPIs, HR-process-discipline dependency, and review cadence mirror the sibling
scenario's page operations and tuning exactly** - re-read that section; it is not repeated here to avoid drift
between two copies of the same guidance. Two items are specific to this scenario:

- **Defender for Endpoint alert-sharing health.** If the "Your organization doesn't have a
  Microsoft Defender for Endpoint subscription" or "Microsoft Defender for Endpoint alerts aren't
  being shared with the Microsoft Purview portal" policy-health notifications appear, this policy silently stops scoring new security-violation activity even
  though it looks correctly configured in the portal - treat checking policy health as a
  standing item in the same cadence as the HR connector import check (sibling page operations and tuning).
- **Incident-response runbook (alert triage)** - identical to the sibling scenario's runbook
  (page operations and tuning, numbered list) with one substitution at step 1 (Triage): review the exported
  record's `RelatedDefenderAlerts` field (populated when `Export-SecurityViolationInsiderRiskAlerts.ps1`
  found a correlated Defender for Endpoint alert in the same incident) for the specific security
  violation before deciding whether the pattern is normal end-of-employment device cleanup or
  genuine tampering.
- **Confirm at least one triggering event is actually enabled - this template makes both
  optional, unlike the sibling.** Because Microsoft's own prerequisite table lists the HR
  connector *and* the Entra-deletion signal as equally optional for this specific template, a policy can be created with **neither** enabled - a silently non-functional
  configuration that produces no error at creation time. The only signal is Microsoft's own
  "Policy isn't assigning risk scores to activity" health message, which requires someone to
  notice it. `validate/Test-SecurityViolationIrmSetup.ps1`'s manual checklist includes this check
  explicitly - run it as part of initial deployment sign-off, not only ad hoc.
- **Preview status is a rollout-pacing decision, not just a documentation footnote.** Recommend
  piloting this scenario against a narrow user scope for at least one full activation-window
  cycle (30 days, the same default the sibling scenario uses) before recommending it as a
  permanent, tenant-wide control in a customer-facing commitment - a Microsoft-labeled preview
  capability can change behavior with less notice than a GA one, and an organization's compliance/board
  narrative should account for that risk explicitly rather than treating this as
  production-equivalent to the GA sibling scenario.

## Rollback and decommission

See the rollback runbook. Quick reference: pausing the policy or turning off the Defender-alert-sharing
feature is reversible in seconds; deleting the policy, or revoking the export app registration's
certificate, is not.

## References

1. Learn about Insider Risk Management policy templates - Security policy violations by departing users (description, prerequisites table, Defender for Endpoint requirement) - <https://learn.microsoft.com/purview/insider-risk-management-policy-templates#security-policy-violations-by-departing-users>
2. Create and manage Insider Risk Management policies - policy health (HR connector shared across Data theft by departing user / Security policy violations by departing user / Data leaks by risky users / Security policy violations by risky users) - <https://learn.microsoft.com/purview/insider-risk-management-policies#policy-health>
3. Microsoft Defender for Endpoint overview - Licensing (Microsoft 365 E5 and Microsoft 365 E5 Security include Defender for Endpoint Plan 2) - <https://learn.microsoft.com/defender-endpoint/microsoft-defender-endpoint#licensing>
4. Configure advanced features in Defender for Endpoint - "Share endpoint alerts with Microsoft Compliance Center" (portal steps, no API) - <https://learn.microsoft.com/defender-endpoint/advanced-features#share-endpoint-alerts-with-microsoft-compliance-center>
5. Create and manage Insider Risk Management policies - policy health ("HR connector isn't configured or working as expected," confirming the connector is a shared, reusable object across templates) - <https://learn.microsoft.com/purview/insider-risk-management-policies#policy-health>
6. Configure intelligent detections in Insider Risk Management - Microsoft Defender for Endpoint alert statuses (daily import cadence, multiple activity records per triage-status transition) - <https://learn.microsoft.com/purview/insider-risk-management-settings-intelligent-detections#microsoft-defender-for-endpoint-alert-statuses>
7. Create and manage Insider Risk Management policies (template/name immutable after creation) - <https://learn.microsoft.com/purview/insider-risk-management-policies>
8. Limits in Insider Risk Management - maximum users in scope per policy template (15,000 for this template) - <https://learn.microsoft.com/purview/insider-risk-management-limits#maximum-number-of-users-in-scope-for-a-policy-template>
9. Learn about Insider Risk Management - Scenarios ("Intentional or unintentional security policy violations (preview)") and Configure policy indicators - Microsoft Defender for Endpoint indicators (preview) - <https://learn.microsoft.com/purview/insider-risk-management#scenarios>, <https://learn.microsoft.com/purview/insider-risk-management-settings-policy-indicators#built-in-indicators-vs-custom-indicators>
10. alert resource type - `alertPolicyId`, `incidentId`, `detectionSource` properties - <https://learn.microsoft.com/graph/api/resources/security-alert>
11. detectionSource enum values (`microsoftInsiderRiskManagement`, `microsoftDefenderForEndpoint` members) - <https://learn.microsoft.com/graph/api/resources/security-detectionsource>
12. List alerts_v2 (supported `$filter` properties - `incidentId` and `detectionSource` are not among them) - <https://learn.microsoft.com/graph/api/security-list-alerts_v2>
13. Microsoft Graph permissions reference (`SecurityAlert.Read.All`) - <https://learn.microsoft.com/graph/permissions-reference>
14. Integrate insider risk management data with Microsoft Graph security API (Incidents/Alerts/Advanced hunting, alerts aggregated by attack technique/attacker into a shared incident) - <https://learn.microsoft.com/defender-xdr/irm-investigate-alerts-defender>
15. Overview of Microsoft Defender for Endpoint Plan 1 - Next-generation protection, attack surface reduction, and manual response actions are Plan 1 capabilities; Plan 1/Plan 2 feature-comparison table (Next-generation protection ✅ both plans, Attack surface reduction ✅ both plans, Endpoint detection and response ❌ Plan 1 / ✅ Plan 2 only) - <https://learn.microsoft.com/defender-endpoint/defender-endpoint-plan-1>, <https://learn.microsoft.com/microsoft-365/education/guide/3-standard/security/standard-security-threat-protection#microsoft-defender-for-endpoint-plan-1-and-plan-2>
16. Tamper protection overview - tampering attempts (including disabling antivirus/security features) generate alerts on the Defender portal's Alerts page as part of anti-tampering capabilities built on attack surface reduction, not EDR - <https://learn.microsoft.com/defender-endpoint/tamper-protection-overview>
15. Plan for Insider Risk Management - policy template requirements (Security policy violation template: enable Defender for Endpoint integration) - <https://learn.microsoft.com/purview/insider-risk-management-plan#understand-requirements-and-dependencies>

> Re-verify all links, cmdlet/API behavior, and licensing terms against current Microsoft Learn
> before a customer-facing assessment or sale - this template family is explicitly Microsoft-
> labeled preview and could change materially before reaching general availability.