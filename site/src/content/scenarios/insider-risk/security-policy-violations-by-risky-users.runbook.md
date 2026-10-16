---
part: "runbook"
parent: "insider-risk/security-policy-violations-by-risky-users"
---
## Implementation steps

### Step 1 - Assign permissions

Confirm the operator is a member of **Insider Risk Management** or **Insider Risk Management
Admins** (Purview role group), has **Data Connector Admin** for the HR connector step, and has a
Defender for Endpoint role capable of changing advanced features - typically **Security
Administrator**, or the granular permission [RBAC model, section 12](/docs/rbac-model/#12-microsoft-defender-for-endpoint-portal-rbac---an-eighth-system-for-scenarios-that-configure-defender-for-endpoint-tenant-wide-settings) documents.

### Step 2 - Register a dedicated HR-connector app and create the connector (manual, reused pattern)

This scenario deliberately does **not** reuse the departing-employee-data-theft sibling's HR
connector - that connector is scoped to Resignation data only, and Microsoft's documented Edit
action for an existing connector changes "the Azure App ID or the column header names," not the set
of HR scenarios it was created for. VERIFY at deploy time whether the live
portal actually allows adding new scenarios to an existing connector via Edit before assuming a
second connector is required - this scenario's scripts assume it is, as the documented, unambiguous
path.

1. Register the app: reuse
   `../security-policy-violations-by-departing-users/../departing-employee-data-theft/deploy/Register-HrConnectorApp.ps1`
   unmodified with a different `-DisplayName` (e.g. `"HR Connector - IRM Risky Users"`). Same
   single-purpose, no-Graph-permission hygiene as the sibling's own use of this script.
2. Purview portal → **Settings** → **Data connectors** → **My connectors** → **Add connector** →
   **HR (preview)**. Provide the new app's Application ID, select **Job level change**,
   **Performance review**, and **Performance improvement plan** as the HR scenarios to import
   (select all three, or only the ones your HR system provides), and map columns - either upload a
   sample CSV shaped per the configuration reference below, or map manually using the **HRScenario** column pattern.
3. Record the generated **Job ID** - needed for Step 4.

### Step 3 - Enable the Defender for Endpoint → Purview alert-sharing feature (manual, one-time)

Identical to every sibling's own Step - **skip entirely if any sibling scenario is already deployed
in this tenant**, since the toggle is tenant-wide, not per-policy (the rollback runbook Stage 2 flags the
same coupling here).

1. Sign in to the [Microsoft Defender portal](https://security.microsoft.com).
2. **Settings** → **Endpoints** → **Advanced features**.
3. Locate **Share endpoint alerts with Microsoft Compliance Center** and toggle it **On**.
4. Select **Save preferences**.

### Step 4 - Resolve and size the policy-scope candidate list (scripted, read-only, reused)

This template has no priority-user-group requirement - population is a plain Entra group, resolved
and sized exactly like the base template, just against this template's larger **7,500**-user cap:

```powershell
Connect-MgGraph -ClientId $AppId -TenantId $TenantId -CertificateThumbprint $Thumbprint

# Dry run - shows the query plan, calls nothing
../security-policy-violations/deploy/Get-SecurityPolicyViolationsScopeCandidates.ps1 `
    -GroupId $SecurityRelevantUsersGroupId -MaxUsers 7500 -WhatIf

# Resolve, dedupe, filter to enabled accounts, check against the 7,500-user cap
../security-policy-violations/deploy/Get-SecurityPolicyViolationsScopeCandidates.ps1 `
    -GroupId $SecurityRelevantUsersGroupId -MaxUsers 7500 -OutputPath ./risky-users-scope-candidates.csv
```

No new script was written for this step - the base template's own scope script has no
template-specific logic beyond the `-MaxUsers` cap it already accepts as a parameter, so a third
copy would be pure duplication (the design notes goal 2).

### Step 5 - Prepare and upload the HR risk-indicator CSV (scripted, mutating)

```powershell
Connect-MgGraph -ClientId $AppId -TenantId $TenantId -CertificateThumbprint $Thumbprint  # unrelated session, HR upload below uses its own auth

$hrSecret = Read-Host -AsSecureString -Prompt 'HR connector app secret'

# Dry run - validates the CSV, reports per-scenario row counts, sends nothing
./deploy/Send-HrRiskIndicatorRecord.ps1 -TenantId $TenantId -AppId $HrConnectorAppId `
    -AppSecret $hrSecret -JobId $HrConnectorJobId -CsvPath ./risk_indicators.csv -WhatIf

# Upload - chunked at 500 rows per call
./deploy/Send-HrRiskIndicatorRecord.ps1 -TenantId $TenantId -AppId $HrConnectorAppId `
    -AppSecret $hrSecret -JobId $HrConnectorJobId -CsvPath ./risk_indicators.csv
```

At least one of this step or Step 6 (Communication Compliance) must be completed before the policy
in Step 7 can start scoring - either alone satisfies Microsoft's documented AND/OR prerequisite. Schedule this script to run on the same recurring cadence as the HR system's own
export, identical operational pattern to the departing-employee-data-theft sibling's resignation
uploader.

### Step 6 - Enable Communication Compliance risk-signal integration (portal-only, optional but recommended)

During policy creation in Step 7, select the option to integrate Communication Compliance risk
signals. This automatically creates a dedicated policy using the Threat, Harassment, and
Discrimination trainable classifiers, scoped to all organization users, with every **Insider Risk
Management Investigators** role-group member auto-assigned as a reviewer. Users
sending 5 or more messages classified as potentially risky within 24 hours are brought in-scope for
this IRM policy, with up to 48 hours of latency from message to in-scope status. **Manually add**
IRM investigators to the **Communication Compliance Investigators** role group if they need to
review the underlying flagged message directly on the Communication Compliance alerts page.

There is no PowerShell or Graph surface for creating or managing Communication Compliance
policies - Microsoft states this explicitly; this step is portal-only in this
scenario, not a fabricated cmdlet gap.

### Step 7 - Create the Insider Risk Management policy (portal, not scriptable)

Purview portal → **Insider Risk Management** → **Policies** → **Create policy**:

1. Template: **Security policy violations by risky users**. Confirm this is the risky-users member
   of the family and not one of its three siblings - all four share the same "Security policy
   violations…" naming prefix in the template picker.
2. Name: `Security Policy Violations by Risky Users`. The template and name can't be changed after
   policy creation - confirm before continuing.
3. **Users and groups**: assign the scope resolved in Step 4.
4. **Triggering events**: enable the HR connector risk-indicator signal (Step 5) and/or the
   Communication Compliance integration (Step 6) - at least one is required. Enabling both is
   supported and gives broader coverage than either alone.
5. **Indicators**: select the **Microsoft Defender for Endpoint indicators (preview)** category, as
   with every sibling. Communication Compliance content indicators are **not** documented as
   selectable scoring indicators for this specific template - unlike the sibling `Data leaks by
   risky users` template, which does list them - so do not conflate the two "risky users" templates
   when scoping this step. **VERIFY against the live policy-creation workflow at deploy time** which
   specific Defender for Endpoint indicator toggles appear; not enumerated by Microsoft Learn during
   this build.
6. **Review and submit.**

Use `deploy/policy/security-policy-violations-risky-users-policy-manifest.json` as the
checklist/reference while completing this workflow - it is not consumed by any API.

### Step 8 - Export correlated alerts for SIEM/ticketing integration (scripted, read-only, reused)

Identical reasoning to the priority-users sibling - the alert-export script applies no
policy-specific filter, so it works unmodified against this policy's own alerts too:

```powershell
Connect-MgGraph -ClientId $AppId -TenantId $TenantId -CertificateThumbprint $Thumbprint

../security-policy-violations-by-departing-users/deploy/Export-SecurityViolationInsiderRiskAlerts.ps1 `
    -SinceDateTime (Get-Date).AddDays(-1) -OutputPath ./security-violation-alerts.json
```

**Caveat carried over unchanged from every sibling:** if more than one "Security policy
violations…" template is deployed in the same tenant, this export cannot tell which policy produced
a given alert - `alertPolicyId` is exported as raw, unmapped data.

### Step 9 - Validate

```powershell
./validate/Test-RiskyUsersIrmSetup.ps1
```

## Configuration reference

| Setting | Value this scenario uses | Notes |
|---|---|---|
| Policy template | `Security policy violations by risky users` **(preview)** | Cannot be changed after creation |
| Triggering events | HR risk-indicator signal (Job level change / Performance review / Performance improvement plan) **AND/OR** Communication Compliance risky-message integration | At least one required; both is supported and recommended |
| Indicator category | **Microsoft Defender for Endpoint indicators (preview)** | Not enumerated by Microsoft as of this writing - VERIFY at deploy time. Communication Compliance content indicators are NOT selectable for this template |
| Population mechanism | A plain Entra group (or groups), resolved via the reused base-template scope script | No priority-user-group requirement, unlike the …by priority users sibling |
| Maximum actively-scored users for this template | **7,500**, cumulative tenant-wide across all policies built from this exact template | - larger than the base/priority-users siblings' 1,000, smaller than the departing-users sibling's 15,000. Do not conflate the four |
| HR data types accepted | Job level change, Performance review, Performance improvement plan | Any one, or a combination, satisfies the HR-connector half of the trigger requirement |
| HR CSV required columns (this scenario's script) | `UserPrincipalName`, `EffectiveDate`, `HRScenario` (name configurable) | Every other documented per-scenario column (`OldLevel`/`NewLevel`, `Remarks`/`Rating`, the improvement-plan columns) is optional and passed through unvalidated - the known limitations documents a Microsoft-side documentation inconsistency in the improvement-plan column names |
| Communication Compliance classifiers | Threat, Harassment, Discrimination (Microsoft-provided trainable classifiers) | Auto-created dedicated policy; not editable via any scripted surface |
| Communication Compliance in-scope threshold | 5+ risky messages within 24 hours; up to 48h latency to in-scope status | |
| Defender for Endpoint alert-sharing dependency | "Share endpoint alerts with Microsoft Compliance Center" advanced feature (tenant-wide) | Same portal-only mechanism as every sibling |
| User-identity privacy | Pseudonymized (Microsoft default) | Not disabled by this scenario |
| Alert export mechanism | Reused: `../security-policy-violations-by-departing-users/deploy/Export-SecurityViolationInsiderRiskAlerts.ps1`, unmodified | No policy-specific filter exists in that script or in the underlying Graph API |
| Cross-policy-template disambiguation | Not attempted - same disclosed gap as every sibling | `alertPolicyId` is exported as raw, unmapped data |

## Operations and tuning

**This scenario's incident-response runbook, Defender for Endpoint alert-sharing health check, and
preview-status rollout-pacing recommendation mirror the other three siblings' own page operations and tuning
guidance exactly** - re-read those sections; they are not repeated here to avoid drift between four
copies of the same guidance. Items specific to this scenario:

- **Confirm HR/Legal sign-off on the HR-connector trigger path before go-live, and keep it on
  record.** Per why this matters's governance note, this is the only scenario in this library whose trigger draws
  on performance-management data. Treat HR/Legal review as a standing prerequisite to check at
  initial deployment sign-off and at any subsequent review of who is in scope - not a one-time box
  checked before the first policy was ever created.
- **Two independent trigger paths means two independent health checks, not one.** Confirm the HR
  connector's import log (Settings → Data connectors → this connector → Download log,
  `RecordsSaved` field) **and** - if Communication Compliance integration is enabled - that the
  auto-created dedicated policy is still active and hasn't been accidentally disabled or reassigned,
  on the same recurring cadence. A silent failure of either path alone reduces coverage without
  producing an error; nothing in the portal actively surfaces "one of your two trigger paths for
  this policy went quiet."
- **Confirm at least one trigger is actually enabled at initial deployment sign-off.** Because
  Microsoft's own prerequisite table states this template's two trigger paths as AND/OR rather than
  naming either as the mandatory primary, a policy can technically be created with neither actually
  producing signal (e.g., the HR connector exists but has never received an upload, and
  Communication Compliance integration wasn't selected) - a silently non-functional configuration
  with no error at creation time, the same class of risk the departing-users sibling's page operations and tuning
  already documents for its own optional-trigger shape.
- **Re-scope on group-membership change, same reasoning as the base template.** This template's
  plain-group population mechanism inherits the base template's own re-scoping guidance
  (*Security Policy Violations (base template)* (operations and tuning)) - this scenario does not repeat it in full.
- **Treat a correlated alert (HR/CC signal + Defender for Endpoint violation on the same user) as
  higher-priority triage than a base-template alert alone** - the same reasoning the priority-users
  sibling documents for its own population, applied here to a behaviorally-flagged rather than a
  formally-designated population.
- **Defender for Endpoint alert-sharing health.** Same standing item as every sibling - if the
  "Your organization doesn't have a Microsoft Defender for Endpoint subscription" or "Microsoft
  Defender for Endpoint alerts aren't being shared with the Microsoft Purview portal" policy-health
  notifications appear, this policy silently stops scoring new activity even though it looks
  correctly configured in the portal.
- **Preview status is a rollout-pacing decision, not just a documentation footnote.** Same
  recommendation as every sibling: pilot against a narrow population for at least one full
  activation-window cycle before treating this as a permanent, tenant-wide control in a
  customer-facing commitment.

## Rollback and decommission

See the rollback runbook. Quick reference: narrowing policy scope or disabling one trigger path is
reversible in seconds; deleting the policy, the dedicated HR connector, the auto-created
Communication Compliance policy, or revoking either app registration's certificate, is not.

## References

1. Learn about Insider Risk Management - Scenarios (employment-stressor precursor framing: performance improvement plan, poor performance review, position demotion) - <https://learn.microsoft.com/purview/insider-risk-management#scenarios>
2. Learn about Insider Risk Management policy templates - Security policy violations by risky users (description, prerequisites table: HR connector risk indicators AND/OR Communication Compliance integration AND active Defender for Endpoint subscription, no Plan qualifier) - <https://learn.microsoft.com/purview/insider-risk-management-policy-templates#security-policy-violations-by-risky-users>
3. Create and manage Communication Compliance policies - Integrate Communication Compliance with Microsoft Purview Insider Risk Management (dedicated "Detect inappropriate text" policy creation, Threat/Harassment/Discrimination classifiers, 5+ messages/24h in-scope threshold, up to 48h latency, auto-assigned IRM Investigators reviewers, "PowerShell isn't supported for creating and managing Communication Compliance policies") - <https://learn.microsoft.com/microsoft-365/compliance/communication-compliance-policies#integrate-communication-compliance-with-microsoft-purview-insider-risk-management>
4. Configure advanced features in Defender for Endpoint - "Share endpoint alerts with Microsoft Compliance Center" (portal steps, no API) - <https://learn.microsoft.com/defender-endpoint/advanced-features#share-endpoint-alerts-with-microsoft-compliance-center>
5. Create and manage Insider Risk Management policies (template/name immutable after creation) - <https://learn.microsoft.com/purview/insider-risk-management-policies>
6. Limits in Insider Risk Management - maximum users in scope per policy template (7,500 for "Security policy violations by risky users"; 1,000 for the base/priority-users siblings; 15,000 for the departing-users sibling) - <https://learn.microsoft.com/purview/insider-risk-management-limits#maximum-number-of-users-in-scope-for-a-policy-template>
7. Set up a connector to import HR data - HR scenario/data-type table (this template requires Job level change, Performance review, and/or Performance improvement plan data), per-scenario CSV column reference, the HRScenario multi-scenario CSV pattern, Data Connector Admin role requirement, Step 4 upload script pattern - <https://learn.microsoft.com/purview/import-hr-data>
8. Get started with Insider Risk Management - Configure Microsoft 365 HR connector (templates requiring the HR connector, including this one) - <https://learn.microsoft.com/purview/insider-risk-management-configure#step-4-recommended-configure-prerequisites-for-policies>
9. Learn about Insider Risk Management - Scenarios ("Intentional or unintentional security policy violations (preview)") and Configure policy indicators - Microsoft Defender for Endpoint indicators (preview) - <https://learn.microsoft.com/purview/insider-risk-management#scenarios>, <https://learn.microsoft.com/purview/insider-risk-management-settings-policy-indicators#built-in-indicators-vs-custom-indicators>
10. alert resource type - `alertPolicyId`, `incidentId`, `detectionSource` properties - <https://learn.microsoft.com/graph/api/resources/security-alert>
11. List group transitive members (OData cast, required `ConsistencyLevel: eventual` header, `GroupMember.Read.All` among the higher-privileged application permissions) - <https://learn.microsoft.com/graph/api/group-list-transitivemembers?view=graph-rest-1.0>
12. Microsoft Graph permissions reference (`GroupMember.Read.All`, `SecurityAlert.Read.All`) - <https://learn.microsoft.com/graph/permissions-reference>
13. *Security Policy Violations (base template)*, *Security Policy Violations by Departing Users*, and *Security Policy Violations by Priority Users* - this template family's base, departing-users, and priority-users siblings, whose already-grounded facts (scope-candidate script, alert-export script, Defender for Endpoint advanced-feature toggle, HR-connector app-registration bootstrap) this scenario reuses and cross-references rather than re-verifying independently.

> Re-verify all links, cmdlet/API behavior, and licensing terms against current Microsoft Learn
> before a customer-facing assessment or sale - this template family is explicitly Microsoft-
> labeled preview and could change materially before reaching general availability. This build's
> citations were grounded via direct Microsoft Learn MCP fetch/search of the URLs above.