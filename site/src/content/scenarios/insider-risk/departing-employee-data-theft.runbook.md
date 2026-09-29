---
part: "runbook"
parent: "insider-risk/departing-employee-data-theft"
---
## Implementation steps

This scenario is **portal-first for policy authoring** (section 6 explains why) and **script-first for
the two pieces that have a real automation surface**: the HR data feed and alert export.

### Step 1 - Assign permissions

Purview portal → **Settings** → **Roles and groups** → **Role groups** → add the
administrators who will configure this policy to **Insider Risk Management** or **Insider Risk
Management Admins**. Confirm the Microsoft 365 audit log is enabled
(**Purview** → **Audit** → confirm status, or [RBAC model, section 6](/docs/rbac-model/#6-exchange-online-dependency-the-most-common-permissions-gap) for the underlying
`Search-UnifiedAuditLog` dependency).

### Step 2 - Register the Entra app for the HR connector (scripted, idempotent)

Microsoft's own HR-connector guide cites only the generic "Register an application" quickstart
for this step - no HR-connector-specific cmdlet exists, because none is needed: the requirement
is a plain, permission-free app registration.
`deploy/Register-HrConnectorApp.ps1` scripts that generic sequence (`New-MgApplication` →
`New-MgServicePrincipal` → `Add-MgApplicationPassword`) instead of leaving it a manual portal
task, and deliberately grants **no** Microsoft Graph API permission - see the callout below.

```powershell
Connect-MgGraph -Scopes 'Application.ReadWrite.All'

# Dry run - reports whether a new app would be created or an existing one reused, calls nothing
./deploy/Register-HrConnectorApp.ps1 -WhatIf

# Real run - creates the app, its service principal, and a 3-month client secret
$hrApp = ./deploy/Register-HrConnectorApp.ps1
```

Record `$hrApp.AppId` (the **Application (client) ID** for Step 3) and `$hrApp.TenantId`. Store
`$hrApp.ClientSecret` (a `SecureString`) in a vault immediately - it is passed to
`deploy/Send-HrTerminationRecord.ps1` as `-AppSecret`, never written to disk, and Microsoft
Entra ID never shows the plaintext value again after this run. Re-run with `-RotateSecret` at
the ~90-day rotation point rather than creating a second app registration.

Once the new secret from a `-RotateSecret` run is confirmed working in
`Send-HrTerminationRecord.ps1`'s scheduled task, remove the superseded secret it left behind -
`-RotateSecret` adds a secret, it never deletes one:

```powershell
# Dry run - lists which already-expired secrets would be deleted, calls nothing
./deploy/Remove-HrConnectorAppSecret.ps1 -RemoveExpired -WhatIf

# Delete every already-expired secret on the app
./deploy/Remove-HrConnectorAppSecret.ps1 -RemoveExpired
```

`validate/Test-HrConnectorAppRegistration.ps1` warns if an already-expired secret is still
present, as a recurring nudge to run this cleanup.

### Step 3 - Create the HR connector

Purview portal → **Settings** → **Data connectors** → **My connectors** → **Add connector** →
**HR (preview)**. Provide the Entra **Application ID** from Step 2, select the **Employee
resignation** HR scenario, and map the CSV columns (`UserPrincipalName`, `ResignationDate`,
`LastWorkingDate`). Record the **Job ID** shown on the confirmation page -
this is the `-JobId` parameter for Step 4.

### Step 4 - Upload resignation data (scripted, dry-run capable)

```powershell
$secret = Read-Host -AsSecureString -Prompt 'HR connector app secret'

# Dry run - validates the CSV schema and reports the upload plan, sends nothing
./deploy/Send-HrTerminationRecord.ps1 `
    -TenantId $TenantId -AppId $AppId -AppSecret $secret -JobId $JobId `
    -CsvPath './employee_resignations.csv' -WhatIf

# Real upload
./deploy/Send-HrTerminationRecord.ps1 `
    -TenantId $TenantId -AppId $AppId -AppSecret $secret -JobId $JobId `
    -CsvPath './employee_resignations.csv'
```

Schedule this to run daily against a freshly exported CSV (Task Scheduler, cron, or a CI
pipeline) - see operations and tuning for cadence guidance and the known limitations for the propagation-lag tradeoff of any less
frequent a schedule.

### Step 5 - Create the Insider Risk Management policy (portal, not scriptable)

Purview portal → **Insider Risk Management** → **Policies** → **Create policy**:

1. Template: **Data theft by departing users**.
2. Name: `Departing Employee Data Theft`. **The template and name can't be changed after policy
   creation** - confirm before continuing.
3. **Users and groups**: select **All users** (or a scoped subset per your organization's
   structure).
4. **Triggering events**: enable both the **HR connector** resignation signal (now fed by Step
   4) **and** the **User account deleted from Microsoft Entra ID** fallback
   - see the design notes for why both, not either.
5. **Content priorities** (optional but recommended): select the tenant's confidential/highly-confidential sensitivity labels so matching activity scores higher.
6. **Indicators**: accept the template's pre-selected exfiltration indicators (SharePoint/
   OneDrive downloads, printing, USB copy, personal-cloud uploads); enable the **cloud
   indicators** for Box/Dropbox/Google Drive/Amazon S3/Azure if the tenant has Defender for
   Cloud Apps connected.
7. **Detection options**: enable **sequence detection** and **cumulative exfiltration
   detection**; apply Microsoft-provided default thresholds on first deployment.
8. **Review and submit.**

Use `deploy/policy/departing-employee-policy-manifest.json` as the checklist/reference while
completing this workflow - it is not consumed by any API (see the file's own `_comment` field
and the design notes).

### Step 6 - Export alerts for SIEM/ticketing integration (scripted, read-only)

```powershell
Connect-MgGraph -ClientId $AppId -TenantId $TenantId -CertificateThumbprint $Thumbprint

# Dry run - shows the query plan, calls nothing
./deploy/Export-InsiderRiskAlerts.ps1 -WhatIf

# Pull the last 24 hours of Insider-Risk-Management-sourced alerts to a file a SIEM polls
./deploy/Export-InsiderRiskAlerts.ps1 -SinceDateTime (Get-Date).AddDays(-1) -OutputPath ./irm-alerts.json
```

### Step 7 - Validate

```powershell
Connect-MgGraph -Scopes 'Application.Read.All'
./validate/Test-HrConnectorAppRegistration.ps1

Connect-MgGraph -ClientId $AppId -TenantId $TenantId -CertificateThumbprint $Thumbprint
./validate/Test-DepartingEmployeeIrmSetup.ps1 -CsvPath './employee_resignations.csv'
```

## Configuration reference

| Setting | Value this scenario uses | Notes |
|---|---|---|
| Policy template | `Data theft by departing users` | Cannot be changed after creation |
| Primary triggering event | HR connector - Employee resignation (`ResignationDate`, `LastWorkingDate`) | Fed by `deploy/Send-HrTerminationRecord.ps1` |
| Fallback triggering event | `User account deleted from Microsoft Entra ID` | Enabled explicitly, not relied on alone - the design notes |
| Activation window | 30 days (Microsoft default) | Configurable in Insider Risk Management global settings; not overridden by this scenario |
| Retrospective lookback | Up to 90 days from the triggering event (10 days for Exchange Online signals) | Microsoft-fixed limit, not configurable per policy |
| Priority user group | None by default | See operations and tuning for when to add one; limit is 10,000 users per group |
| Indicator categories enabled | Office (SharePoint/OneDrive download/sync/share), Device (USB copy, browser upload, print, network-share transfer), Cloud (Box/Dropbox/Google Drive/Amazon S3/Azure) | Device indicators require device onboarding; cloud indicators require Defender for Cloud Apps and bill as PAYG |
| Detection options | Sequence detection + cumulative exfiltration detection, Microsoft-default thresholds | the design notes; do not hand-tune before one full activation-window cycle of baseline data |
| User-identity privacy | Pseudonymized (Microsoft default) | Not disabled by this scenario - see the CISO review |
| Alert export mechanism | Microsoft Graph `GET /security/alerts_v2`, filtered client-side on `detectionSource eq 'microsoftInsiderRiskManagement'` | Server-side `$filter` does **not** support `detectionSource` - see section 11 |
| HR CSV schema | `UserPrincipalName`, `ResignationDate`, `LastWorkingDate` (ISO 8601) | Minimal Employee resignation schema - this scenario does not use the Employee profile connector's additional PII fields |
| HR upload chunk size | ≤500 data rows per file (documented ingestion limit) | `deploy/Send-HrTerminationRecord.ps1 -ChunkSize` (default 500) |

## Operations and tuning

**HR data feed cadence:** run `deploy/Send-HrTerminationRecord.ps1` **daily** at minimum,
matching Microsoft's own recommended pattern for this connector. A less
frequent schedule directly widens the gap between an employee's resignation being recorded by
HR and the policy beginning to score their activity - see the known limitations.

**KPIs to watch (first 90 days):**
- **Alert volume vs. departing-employee headcount** - trend alerts generated against the
  count of resignation records ingested in the same period. A near-zero rate across a
  meaningful sample size after 90 days is itself a signal - either the indicators/thresholds
  need tuning, or genuine departing-employee exfiltration risk in this tenant is lower than
  typical (worth confirming, not assuming).
- **Alert-to-case conversion rate** - how many alerts investigators escalate to a formal case.
  A very low rate alongside high alert volume suggests threshold tuning is needed before
  analyst fatigue sets in.
- **HR connector import success rate** - check the connector's log on the same cadence as
  the upload schedule; a silent upload failure (bad CSV, expired app secret, blocked firewall
  rule for `webhook.ingestion.office.com`) means the policy is *not* scoring new departures
  even though it looks configured correctly in the portal.
- **Time-to-alert from resignation date** - for a true positive, how long between the
  resignation record's ingestion and the first alert. This is the metric that most directly
  measures whether this scenario is closing the notice-period risk window it exists for.

**This control is only as good as HR's data discipline - and that failure mode is invisible by
default.** A technically healthy HR connector (green import log, no script errors) still
produces zero coverage for any departure HR simply never puts in the export - there is no
"expected N departures this month, saw M" negative-space check this scenario can compute on its
own, because it has no independent source of truth for who is actually leaving. Treat "confirm
the departing-employee export ran" as a line item in the org's HR/IT offboarding SOP, not solely
a technical monitoring problem - see the CISO review.

**When to add a priority user group:** if alert triage volume makes it hard to prioritize,
identify roles with elevated data access (finance, engineering with source-code access,
executives) and create a priority user group (the configuration reference, `insider-risk-management-settings-priority-user-groups`) - this sharpens alert severity for departing users in those
roles without a second policy.

**Incident-response runbook (alert triage):**
1. **Triage** - open the alert in Insider Risk Management → Alerts (or the Defender portal
   unified incident queue, if integrated per the references). Review the **Activity explorer** tab for the
   specific indicator events and their volume.
2. **Classify** - is the pattern consistent with normal end-of-employment activity (returning
   personal files, closing out projects) or does volume/destination suggest exfiltration
   (bulk download immediately followed by a personal-cloud upload, printing far above the
   user's baseline)? Content preview (where supported - the known limitations) can help without opening a full
   case.
3. **Escalate if warranted** - assign the alert/case to an Investigator; Insider Risk
   Management cases can escalate directly to eDiscovery (Premium) for legal hold and further
   investigation if the pattern indicates genuine misappropriation. See
   *Case Escalation to eDiscovery (Premium)* for the scripted follow-through
   (provenance linkage + custodian/hold reconciliation) once that portal escalation step is done.
4. **Coordinate with HR/Legal/IT offboarding** - this policy is a detection control, not an
   offboarding-automation control; a true-positive finding should trigger the org's standard
   incident and (if the person hasn't yet departed) accelerated access-revocation process.
5. **Document** - case outcomes are retained per the tenant's audit-log/case retention
   settings; do not delete case records as part of closing them out.

**Review cadence:** review indicator/threshold configuration quarterly, using the KPIs above;
review HR connector health (import success) on the same cadence as the upload schedule itself
(daily automated check via `validate/Test-DepartingEmployeeIrmSetup.ps1`'s manual-checklist
prompts, or wire the connector's log into the same SIEM `Export-InsiderRiskAlerts.ps1` feeds).

## Rollback and decommission

See the rollback runbook for the full staged procedure (pause → disable feed → permanent removal).
Quick reference: pausing the policy or the HR connector in the portal is reversible in seconds;
deleting the policy, connector, or the HR-connector app registration's client secret is not.

## References

1. Learn about Insider Risk Management policy templates (Data theft by departing users, cloud indicators, PAYG) - <https://learn.microsoft.com/purview/insider-risk-management-policy-templates>
2. Assign permissions in Insider Risk Management (role groups, Data Connector Admin inclusion) - <https://learn.microsoft.com/purview/insider-risk-management-permissions>
3. Set up a connector to import HR data (CSV schema, app registration, webhook, 500-row limit, sample script) - <https://learn.microsoft.com/purview/import-hr-data>
4. Get started with Insider Risk Management (Step 1 permissions, Step 2 audit log) - <https://learn.microsoft.com/purview/insider-risk-management-configure>
5. Register an application with the Microsoft identity platform - <https://learn.microsoft.com/azure/active-directory/develop/quickstart-register-app>
6. Microsoft Graph permissions reference (`SecurityAlert.Read.All`) - <https://learn.microsoft.com/graph/permissions-reference>
7. Create and manage Insider Risk Management policies (template/name immutable after creation) - <https://learn.microsoft.com/purview/insider-risk-management-policies>
8. Prioritize user groups for Insider Risk Management policies (10,000-user limit) - <https://learn.microsoft.com/purview/insider-risk-management-settings-priority-user-groups>
9. Configure policy indicators in Insider Risk Management - <https://learn.microsoft.com/purview/insider-risk-management-settings-policy-indicators>
10. Investigate Microsoft Purview Insider Risk Management activities (sequence detection, spotlight, content preview) - <https://learn.microsoft.com/purview/insider-risk-management-activities>
11. Limits in Insider Risk Management (lookback periods, trigger volume limits) - <https://learn.microsoft.com/purview/insider-risk-management-limits>
12. Investigate Microsoft Purview Insider Risk Management activities - content preview supported/unsupported activities - <https://learn.microsoft.com/purview/insider-risk-management-activities#standard-alert-dashboard>
13. List alerts_v2 (supported `$filter` properties) - <https://learn.microsoft.com/graph/api/security-list-alerts_v2>
14. alert resource type and detectionSource enum (`microsoftInsiderRiskManagement` member) - <https://learn.microsoft.com/graph/api/resources/security-alert>, <https://learn.microsoft.com/graph/api/resources/security-detectionsource>
15. Data risk graph in Insider Risk Management (retirement date November 24, 2026) - <https://learn.microsoft.com/purview/insider-risk-management-data-risk-graph>
16. Investigate insider risk threats in the Microsoft Defender portal (Graph Security API integration path, Incidents/Alerts/Advanced hunting) - <https://learn.microsoft.com/defender-xdr/irm-investigate-alerts-defender>
17. Microsoft Purview service description - Insider Risk Management licensing table - <https://learn.microsoft.com/office365/servicedescriptions/microsoft-365-service-descriptions/microsoft-365-tenantlevel-services-licensing-guidance/microsoft-purview-service-description>
18. Plan for Insider Risk Management (per-template prerequisites) - <https://learn.microsoft.com/purview/insider-risk-management-plan>
19. New-MgApplication, Get-MgApplication, New-MgServicePrincipal, Add-MgApplicationPassword, Remove-MgApplication, Remove-MgServicePrincipal (Microsoft.Graph.Applications PowerShell reference) - <https://learn.microsoft.com/powershell/module/microsoft.graph.applications/new-mgapplication>, <https://learn.microsoft.com/powershell/module/microsoft.graph.applications/new-mgserviceprincipal>, <https://learn.microsoft.com/powershell/module/microsoft.graph.applications/add-mgapplicationpassword>
20. Add and manage application credentials in Microsoft Entra ID (multiple concurrent client secrets are supported; a secret's plaintext value is shown only once) - <https://learn.microsoft.com/entra/identity-platform/how-to-add-credentials>
21. Delegate app registration permissions in Microsoft Entra ID (default "Users can register applications" behavior; Application Developer / Application Administrator / Cloud Application Administrator roles) - <https://learn.microsoft.com/entra/identity/role-based-access-control/delegate-app-roles>
22. Remove-MgApplicationPassword (Microsoft.Graph.Applications, v1.0; `-ApplicationId` aliased `ObjectId`) and the underlying `application: removePassword` Graph REST action - <https://learn.microsoft.com/powershell/module/microsoft.graph.applications/remove-mgapplicationpassword>, <https://learn.microsoft.com/graph/api/application-removepassword>

> Re-verify all links, cmdlet/API behavior, and licensing terms against current Microsoft Learn
> before a customer-facing assessment or sale - this module changes faster than most in the
> Purview portfolio (several referenced features are marked preview or scheduled for retirement).