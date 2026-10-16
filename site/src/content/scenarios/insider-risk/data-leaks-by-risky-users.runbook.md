---
part: "runbook"
parent: "insider-risk/data-leaks-by-risky-users"
---
## Implementation steps

### Step 1 - Assign permissions

Confirm the operator is a member of **Insider Risk Management** or **Insider Risk Management
Admins** (Purview role group) and has **Data Connector Admin** for the HR connector step
([RBAC model, section 4](/docs/rbac-model/#4-purview-role-groups-by-module-representative-not-exhaustive)). No Defender for Endpoint role is needed anywhere in this scenario -
unlike the security-policy-violations-by-risky-users sibling.

### Step 2 - Register a dedicated HR-connector app and create the connector (manual, reused pattern)

This scenario provisions its **own third** dedicated HR connector - not the departing-employee-data-theft sibling's Resignation-scoped connector, and not the security-policy-violations-by-risky-users sibling's own dedicated risk-indicator connector - for the same documented reason both
those scenarios already give: Microsoft's Edit action for an existing connector changes "the Azure
App ID or the column header names," not the set of HR scenarios it was created for.
VERIFY at deploy time whether the live portal actually allows adding scenarios to an existing
connector via Edit before assuming a third connector is required.

1. Register the app: reuse
   `../security-policy-violations-by-departing-users/../departing-employee-data-theft/deploy/
   Register-HrConnectorApp.ps1` unmodified with a different `-DisplayName` (e.g.
   `"HR Connector - IRM Data Leaks Risky Users"`).
2. Purview portal → **Settings** → **Data connectors** → **My connectors** → **Add connector** →
   **HR (preview)**. Provide the new app's Application ID, select **Job level change**,
   **Performance review**, and **Performance improvement plan** as the HR scenarios to import, and
   map columns per the configuration reference's reference (identical schema to the sibling scenario).
3. Record the generated **Job ID** - needed for Step 4.

### Step 3 - Resolve and size the policy-scope candidate list (scripted, read-only, reused)

Identical mechanism and cap to the security-policy-violations-by-risky-users sibling - this
template shares the same documented **7,500**-actively-scored-user limit:

```powershell
Connect-MgGraph -ClientId $AppId -TenantId $TenantId -CertificateThumbprint $Thumbprint

# Dry run - shows the query plan, calls nothing
../security-policy-violations/deploy/Get-SecurityPolicyViolationsScopeCandidates.ps1 `
    -GroupId $RiskyUsersGroupId -MaxUsers 7500 -WhatIf

# Resolve, dedupe, filter to enabled accounts, check against the 7,500-user cap
../security-policy-violations/deploy/Get-SecurityPolicyViolationsScopeCandidates.ps1 `
    -GroupId $RiskyUsersGroupId -MaxUsers 7500 -OutputPath ./data-leaks-risky-users-scope-candidates.csv
```

No new script was written for this step - the base template's own scope script has no
template-specific logic beyond the `-MaxUsers` cap it already accepts as a parameter, the same
reuse rationale the security-policy-violations-by-risky-users sibling already established
(the design notes goal 2).

### Step 4 - Prepare and upload the HR risk-indicator CSV (scripted, mutating, reused unmodified)

`Send-HrRiskIndicatorRecord.ps1` was already generalized in the security-policy-violations-by-risky-users sibling for exactly this template's HR data shape - its own `.SYNOPSIS` names both
templates as consumers. No fork was needed:

```powershell
Connect-MgGraph -ClientId $AppId -TenantId $TenantId -CertificateThumbprint $Thumbprint  # unrelated session, HR upload below uses its own auth

$hrSecret = Read-Host -AsSecureString -Prompt 'HR connector app secret'

# Dry run - validates the CSV, reports per-scenario row counts, sends nothing
../security-policy-violations-by-risky-users/deploy/Send-HrRiskIndicatorRecord.ps1 `
    -TenantId $TenantId -AppId $HrConnectorAppId -AppSecret $hrSecret -JobId $HrConnectorJobId `
    -CsvPath ./risk_indicators.csv -WhatIf

# Upload - chunked at 500 rows per call
../security-policy-violations-by-risky-users/deploy/Send-HrRiskIndicatorRecord.ps1 `
    -TenantId $TenantId -AppId $HrConnectorAppId -AppSecret $hrSecret -JobId $HrConnectorJobId `
    -CsvPath ./risk_indicators.csv
```

Pass **this scenario's own** `-AppId`/`-JobId` (Step 2) - the script is generic across both
templates' HR data shape, but each scenario's connector object is its own, distinct from the
sibling's. At least one of this step or Step 5 (Communication Compliance) must be completed before
the policy in Step 6 can start scoring - either alone satisfies Microsoft's documented AND/OR
prerequisite. Schedule this script on the same recurring cadence as the HR
system's own export.

### Step 5 - Enable Communication Compliance risk-signal integration (portal-only, optional but recommended)

During policy creation in Step 6, select the option to integrate Communication Compliance risk
signals as a **trigger**. This automatically creates a dedicated policy using the Threat,
Harassment, and Discrimination trainable classifiers, scoped to all organization users, with every
**Insider Risk Management Investigators** role-group member auto-assigned as a reviewer. Users sending 5 or more messages classified as potentially risky within 24
hours are brought in-scope, with up to 48 hours of latency from message to in-scope status.
**Manually add** IRM investigators to the **Communication Compliance Investigators** role group if
they need to review the underlying flagged message directly on the Communication Compliance alerts
page.

There is no PowerShell or Graph surface for creating or managing Communication Compliance
policies - Microsoft states this explicitly; this step is portal-only, not a
fabricated cmdlet gap.

**Naming inconsistency, disclosed rather than resolved:** Microsoft's own documentation for this
exact integration uses two different names for the auto-created dedicated policy within the same
article - *"Insider risk trigger - (date created)"* in one paragraph, *"Risky user in messages -
(date created)"* in the next. Confirm the actual live name against the portal at
deploy time rather than assuming either is authoritative - same disclosed gap as the
security-policy-violations-by-risky-users sibling's own the known limitations.

### Step 6 - Create the Insider Risk Management policy (portal, not scriptable)

Purview portal → **Insider Risk Management** → **Policies** → **Create policy**:

1. Template: **Data leaks by risky users**. Confirm this is the risky-users member of the
   **Data leaks…** family and not its `Data leaks`/`…by priority users` siblings, and not the
   differently-scored `Security policy violations by risky users` cousin - all four "risky/priority
   users" templates across the two families share overlapping naming in the template picker.
2. Name: `Data Leaks by Risky Users`. The template and name can't be changed after policy creation
   - confirm before continuing.
3. **Users and groups**: assign the scope resolved in Step 3.
4. **Triggers for this policy**: enable the HR connector risk-indicator signal (Step 4) and/or the
   Communication Compliance integration (Step 5) - at least one is required; both is supported and
   recommended for broader coverage.
5. **Policy indicators**: select **Office indicators** (SharePoint Online downloads/syncing,
   sharing internal files/folders externally, copying data to personal cloud storage/messaging
   services) - this template's primary, built-in scoring category, requiring no additional
   connector. Optionally add:
   - **Communication Compliance indicators** (Sending financial regulatory text that might be
     risky / Sending inappropriate images / Sending inappropriate content / Sending messages that
     contain specific sensitive info types) - a **scoring** indicator category selectable for this
     template, Microsoft documents explicitly, distinct from the CC **trigger** integration in
     Step 5: the same Communication Compliance product plays two different, independently-optional
     roles in this one policy. Do not conflate the two.
   - **Generative AI app indicators** (Prompt Shields, Protected material detection) - also
     documented as selectable for this template.
   - **Cloud storage/cloud service indicators** (Box, Dropbox, Google Drive, Amazon S3, Azure) -
     requires those apps connected in Microsoft Defender for Cloud Apps first, and pay-as-you-go
     billing enabled. Microsoft's per-template description
     text explicitly names this "cloud indicators" capability for the `Data theft by departing
     users` and base `Data leaks` templates; **VERIFY against the live policy-creation workflow at
     deploy time** whether the cloud-indicator category is actually offered when this specific
     template (`Data leaks by risky users`) is selected - not explicitly stated either way in this
     template's own description text, unlike its two siblings just named.
6. Select **Cumulative exfiltration detection** (enabled by default for this template - confirm it
   is actually selected rather than assuming the default survived any earlier "Turn on indicators"
   step).
7. **Review and submit.**

Use `deploy/policy/data-leaks-risky-users-policy-manifest.json` as the checklist/reference while
completing this workflow - it is not consumed by any API.

### Step 7 - Export correlated alerts for SIEM/ticketing integration (scripted, read-only, reused)

This template has **no** Microsoft Defender for Endpoint signal to join against, so this scenario
reuses the plain departing-employee-data-theft export script - not the security-policy-violations
family's Defender-for-Endpoint-joining variant, which would do wasted, misleading work here:

```powershell
Connect-MgGraph -ClientId $AppId -TenantId $TenantId -CertificateThumbprint $Thumbprint

../departing-employee-data-theft/deploy/Export-InsiderRiskAlerts.ps1 `
    -SinceDateTime (Get-Date).AddDays(-1) -OutputPath ./data-leaks-risky-users-alerts.json
```

**Caveat carried over from every IRM scenario in this library:** if more than one Insider Risk
Management policy is deployed in the tenant, this export cannot tell which policy produced a given
alert - `AlertPolicyId` (present in the Graph alert resource, not selected by this particular
script's output columns) has no documented way to map back to a named Purview policy.

### Step 8 - Validate

```powershell
./validate/Test-DataLeaksRiskyUsersIrmSetup.ps1
```

## Configuration reference

| Setting | Value this scenario uses | Notes |
|---|---|---|
| Policy template | `Data leaks by risky users` | Not Microsoft-labeled preview as of this writing, unlike its `Security policy violations by risky users` cousin - re-verify at deploy time. Cannot be changed after creation |
| Triggering events | HR risk-indicator signal (Job level change / Performance review / Performance improvement plan) **AND/OR** Communication Compliance risky-message integration | At least one required; both is supported and recommended |
| Primary scoring indicator category | **Office indicators** (built-in) - SharePoint Online downloads/syncs, external file/folder sharing, copying to personal cloud storage/messaging services | No additional connector required |
| Cumulative exfiltration detection | **Enabled by default** for this template | Confirm selected at policy creation, not assumed |
| Optional scoring indicators | Communication Compliance content indicators (financial regulatory text, inappropriate images, inappropriate content, sensitive info types); generative AI app indicators (Prompt Shields, Protected material detection) | Both documented as selectable for this template specifically - distinct from the CC **trigger** integration, which is a different role for the same product |
| Optional cloud indicators | Cloud storage (Box, Dropbox, Google Drive) / cloud service (Amazon S3, Azure) indicators | Requires Defender for Cloud Apps app connections + pay-as-you-go billing; **VERIFY at deploy time whether this template's policy-creation workflow actually offers this category** - step 6 of the implementation steps |
| Population mechanism | A plain Entra group (or groups), resolved via the reused base-template scope script | No priority-user-group requirement |
| Maximum actively-scored users for this template | **7,500**, cumulative tenant-wide across all policies built from this exact template | - same numeric cap as the `Security policy violations by risky users` cousin; do not conflate the two templates despite the identical number |
| HR data types accepted | Job level change, Performance review, Performance improvement plan | Any one, or a combination, satisfies the HR-connector half of the trigger requirement - identical to the cousin template |
| HR CSV required columns (reused script) | `UserPrincipalName`, `EffectiveDate`, `HRScenario` (name configurable) | Every other per-scenario column is optional and passed through unvalidated - see the sibling scenario's own the known limitations for the documented Microsoft-side column-naming inconsistency this reused script's `.NOTES` already discloses |
| Communication Compliance trigger classifiers | Threat, Harassment, Discrimination (Microsoft-provided trainable classifiers) | Auto-created dedicated policy; not editable via any scripted surface |
| Communication Compliance trigger threshold | 5+ risky messages within 24 hours; up to 48h latency to in-scope status | |
| Defender for Endpoint dependency | **None** | The defining difference from the *Security Policy Violations by Risky Users* sibling |
| User-identity privacy | Pseudonymized (Microsoft default) | Not disabled by this scenario |
| Alert export mechanism | Reused: `../departing-employee-data-theft/deploy/Export-InsiderRiskAlerts.ps1`, unmodified | The plain, non-MDE-joining variant - correct choice given this template's indicator set |
| Cross-policy disambiguation | Not attempted - same disclosed gap as every IRM scenario in this library | `AlertPolicyId` has no documented policy-name mapping |

## Operations and tuning

- **Confirm HR/Legal sign-off on the HR-connector trigger path before go-live, and keep it on
  record** - identical standing item to the security-policy-violations-by-risky-users sibling's own
  operations and tuning guidance, restated here because this scenario uses the same HR-connector mechanism (why this matters's
  governance note).
- **Two independent trigger paths means two independent health checks, not one.** Confirm the HR
  connector's import log (Settings → Data connectors → this connector → Download log,
  `RecordsSaved` field) **and** - if Communication Compliance integration is enabled - that the
  auto-created dedicated policy is still active, on the same recurring cadence. A silent failure of
  either path alone reduces coverage without producing an error.
- **Confirm at least one trigger is actually enabled at initial deployment sign-off** - the same
  AND/OR configuration-error risk the sibling scenario documents: a policy can be created with
  neither path actually producing signal, a silently non-functional configuration indistinguishable
  from a correctly configured one at creation time.
- **Cumulative exfiltration detection depends on Microsoft Entra data sharing.** Enabling it shares
  organization hierarchy, job titles, and SharePoint-site-access patterns with the Purview portal
  for peer-group comparison. If the tenant doesn't maintain this data in Microsoft
  Entra ID, detection accuracy degrades - document this as a known-limitation conversation with the
  customer rather than a silent accuracy gap.
- **Re-scope on group-membership change**, same reasoning as every group-scoped IRM template in
  this library - *Security Policy Violations (base template)* (operations and tuning), not repeated here in full.
- **Before scheduling `Send-HrRiskIndicatorRecord.ps1` unattended, verify the `-JobId`/`-AppId`
  pair in the scheduled task matches this scenario's own connector, not a sibling's** - the known limitations
  discloses this as a real operator-error risk given three near-identical connectors now exist in
  this library using the same script/calling convention. A wrong JobId uploads silently, with no
  error, into the wrong policy's trigger path.
- **If cloud-app indicators are enabled, monitor Defender for Cloud Apps connector health
  independently** - a disconnected Box/Dropbox/Google Drive/S3/Azure connector silently stops
  contributing to this policy's scoring without necessarily surfacing as an IRM policy-health
  notification; check the Defender portal's own connector status directly.
- **Treat a correlated alert (HR/CC trigger signal + built-in exfiltration activity on the same
  user) as higher-priority triage** than the base `Data leaks` template's plain-group-scope alerts
  alone - same reasoning the priority-users family documents for its own populations, applied here
  to a behaviorally-flagged rather than a formally-designated population.
- **This control is invisible to exfiltration channels outside the selected indicator set** - e.g.,
  a personal device with no Purview extension/DLP coverage, or a cloud storage provider never
  connected to Defender for Cloud Apps. Pair with a DLP-triggered `Data leaks` (base template)
  policy for broader channel coverage if this gap matters for the target population.
- **Coordinate deployment explicitly if both this template and *Security Policy Violations by Risky Users* are deployed against overlapping populations.** The two templates share an
  identical trigger mechanism and a numerically identical (but separately tracked) 7,500-user cap;
  running both against the same group without a deliberate reason doubles the HR-connector/
  Communication-Compliance operational surface (two connectors, potentially two dedicated CC
  policies) for a population that could instead be covered by one template chosen for its actual
  indicator need. Document which template a given population is scoped to and why, rather than
  defaulting to "both" without a reason - a CISO evaluating cost/complexity will ask.

## Rollback and decommission

See the rollback runbook. Quick reference: narrowing policy scope, disabling one trigger path, or turning
off an optional indicator category is reversible in seconds; deleting the policy, the dedicated HR
connector, the auto-created Communication Compliance policy, or revoking either app registration's
certificate, is not.

## References

1. Learn about Insider Risk Management - Scenarios (employment-stressor precursor framing: performance improvement plan, poor performance review, position demotion) - <https://learn.microsoft.com/purview/insider-risk-management#scenarios>
2. Learn about Insider Risk Management policy templates - Data leaks by risky users (description, prerequisites table: HR connector disgruntlement/risk indicators AND/OR Communication Compliance integration and dedicated policy) - <https://learn.microsoft.com/purview/insider-risk-management-policy-templates#data-leaks-by-risky-users>
3. Create and manage Communication Compliance policies - Integrate Communication Compliance with Microsoft Purview Insider Risk Management (dedicated "Detect inappropriate text" policy creation as a trigger, Threat/Harassment/Discrimination classifiers, 5+ messages/24h in-scope threshold, up to 48h latency, auto-assigned IRM Investigators reviewers, the two-different-names documentation inconsistency, "PowerShell isn't supported for creating and managing Communication Compliance policies") - <https://learn.microsoft.com/microsoft-365/compliance/communication-compliance-policies#integrate-communication-compliance-with-microsoft-purview-insider-risk-management>
4. Create and manage Communication Compliance policies - "Select Insider Risk Management policy indicators for data-based policy templates" (CC content indicators - financial regulatory text, inappropriate images, inappropriate content, sensitive info types - selectable as SCORING indicators for Data theft, Data leaks, Data leaks by risky users, and Data leaks by priority users templates) and "Select generative AI policy indicators for policy templates" (Prompt Shields, Protected material detection, selectable for Data leaks, Data leaks by risky users, Data leaks by priority users, Risky AI usage) - <https://learn.microsoft.com/microsoft-365/compliance/communication-compliance-policies#integrate-communication-compliance-with-microsoft-purview-insider-risk-management>
5. Create and manage Insider Risk Management policies (template/name immutable after creation) - <https://learn.microsoft.com/purview/insider-risk-management-policies>
6. Create and manage Insider Risk Management policies - Cumulative exfiltration detection (enabled by default for Data leaks / Data leaks by priority users / Data leaks by risky users / Data theft by departing users; peer-group Microsoft Entra data-sharing requirement) and Limits in Insider Risk Management - maximum users in scope per policy template (7,500 for "Data leaks by risky users") - <https://learn.microsoft.com/purview/insider-risk-management-policies#cumulative-exfiltration-detection>, <https://learn.microsoft.com/purview/insider-risk-management-limits#maximum-number-of-users-in-scope-for-a-policy-template>
7. Set up a connector to import HR data - HR scenario/data-type table (this template requires Job level change, Performance review, and/or Performance improvement plan data, identical to its Security policy violations by risky users cousin), Data Connector Admin role requirement - <https://learn.microsoft.com/purview/import-hr-data>
8. Get started with Insider Risk Management - Step 4/Step 6 (HR connector required for this template; Communication Compliance/HR data connector trigger options in the policy-creation workflow) - <https://learn.microsoft.com/purview/insider-risk-management-configure#step-4-recommended-configure-prerequisites-for-policies>, <https://learn.microsoft.com/purview/insider-risk-management-configure#step-6-required-create-an-insider-risk-management-policy>
9. Learn about Insider Risk Management policy templates - Data leaks by risky users description (employment-stressor examples, exfiltration activity examples: downloading files from SharePoint Online, copying data to personal cloud messaging and storage services) - <https://learn.microsoft.com/purview/insider-risk-management-policy-templates#data-leaks-by-risky-users>
10. Configure policy indicators in Insider Risk Management - Cloud storage indicators (Google Drive, Box, Dropbox) and Cloud service indicators (Amazon S3, Azure) - pay-as-you-go billing requirement, Defender for Cloud Apps connection prerequisite - <https://learn.microsoft.com/purview/insider-risk-management-settings-policy-indicators#built-in-indicators-vs-custom-indicators>
11. Get started with Insider Risk Management - Connect to cloud apps in Microsoft Defender (cloud storage/cloud service indicator categories, Defender for Cloud Apps connection prerequisite) - <https://learn.microsoft.com/purview/insider-risk-management-configure#connect-to-cloud-apps-in-microsoft-defender>
12. *Security Policy Violations by Risky Users* and the design notes - this scenario's closest cousin in this library, whose already-grounded facts (HR-connector uploader script, app-registration bootstrap, HR/Legal governance framing, the CC-trigger naming inconsistency) this scenario reuses and cross-references rather than re-verifying independently. `departing-employee-data-theft/deploy/Export-InsiderRiskAlerts.ps1` and `Register-HrConnectorApp.ps1` - the plain (non-MDE-joining) alert-export script and the HR-connector app-registration bootstrap, both reused unmodified. `security-policy-violations/deploy/Get-SecurityPolicyViolationsScopeCandidates.ps1` - the scope-candidate script, reused unmodified with `-MaxUsers 7500`.
13. alert resource type - `AlertPolicyId`, `DetectionSource` properties - <https://learn.microsoft.com/graph/api/resources/security-alert>
14. List group transitive members (OData cast, required `ConsistencyLevel: eventual` header, `GroupMember.Read.All` among the higher-privileged application permissions) - <https://learn.microsoft.com/graph/api/group-list-transitivemembers?view=graph-rest-1.0>
15. Microsoft Graph permissions reference (`GroupMember.Read.All`, `SecurityAlert.Read.All`) - <https://learn.microsoft.com/graph/permissions-reference>

> Re-verify all links, cmdlet/API behavior, and licensing terms against current Microsoft Learn
> before a customer-facing assessment or sale. This build's citations were grounded via direct
> Microsoft Learn MCP fetch/search of the URLs above.