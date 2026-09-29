---
part: "runbook"
parent: "insider-risk/data-leaks"
---
## Implementation steps

### Step 1 - Assign permissions

Confirm the operator is a member of **Insider Risk Management** or **Insider Risk Management
Admins** (Purview role group), and has at least read access to the DLP policies to be used as a
trigger ([RBAC model, section 4](/docs/rbac-model/#4-purview-role-groups-by-module-representative-not-exhaustive)). No HR/Communication Compliance/Defender-for-Endpoint role is
needed anywhere in this scenario.

### Step 2 - Check candidate DLP policies for trigger readiness (scripted, read-only, new)

```powershell
Connect-IPPSSession -AppId $AppId -Certificate $Cert -Organization $TenantDomain

# Dry run - shows the query plan, calls nothing
./deploy/Test-DlpPolicyIrmTriggerReadiness.ps1 -DlpPolicyName 'PII DLP - Exchange External Send Control' -WhatIf

# Check one or more existing policies
./deploy/Test-DlpPolicyIrmTriggerReadiness.ps1 -DlpPolicyName 'PII DLP - Exchange External Send Control', 'SharePoint PII Guardrail'
```

For each policy, this reports whether it's scoped to a supported workload (Exchange/SharePoint/
OneDrive), whether it has at least one High-severity rule, whether its `Mode` is `Enable` rather
than a Test mode, and reminds the operator to cross-check the policy's own scope against the IRM
policy's future "Users and groups" scope (the configuration reference's double-scoping requirement - there is no automated
way to compare the two). Fix any `[FAIL]` in the source DLP policy (or choose a different one)
before continuing - this script never modifies the policy itself. A `[WARN]` on `Mode` is not a
hard blocker, but confirm the policy is not left indefinitely in `TestWithNotifications`/
`TestWithoutNotifications` mode if you need this trigger to actually fire - whether Test mode
still generates the alerts this indicator consumes is unconfirmed.

### Step 3 - Resolve and size the policy-scope candidate list (scripted, read-only, reused)

```powershell
Connect-MgGraph -ClientId $AppId -TenantId $TenantId -CertificateThumbprint $Thumbprint

# Dry run
../security-policy-violations/deploy/Get-SecurityPolicyViolationsScopeCandidates.ps1 `
    -GroupId $ScopeGroupId -MaxUsers 15000 -WhatIf

# Resolve, dedupe, filter to enabled accounts, check against the confirmed cap
../security-policy-violations/deploy/Get-SecurityPolicyViolationsScopeCandidates.ps1 `
    -GroupId $ScopeGroupId -MaxUsers 15000 -OutputPath ./data-leaks-scope-candidates.csv
```

**`-MaxUsers` is 15,000 for this template** - Microsoft's own "Limits in Insider Risk
Management" table gives the base `Data leaks` template its own row at 15,000, confirmed via a
direct Microsoft Learn fetch (the configuration reference and the references ref 6, the design notes goal 7). This cap is cumulative
**tenant-wide across every policy built from this exact template** - pass a lower value if
another `Data leaks`-template policy already consumes part of it. Do not reuse the
*Security Policy Violations (base template)* (1,000) or risky/priority-users family (7,500) numbers, which are
documented for different templates.

### Step 4 - Create the Insider Risk Management policy (portal, not scriptable)

Purview portal → **Insider Risk Management** → **Policies** → **Create policy**:

1. Template: **Data leaks**. Confirm this is the base template and not `Data leaks by risky
   users` or `Data leaks by priority users` - all three share overlapping naming in the template
   picker.
2. Name: `Data Leaks`. The template and name can't be changed after policy creation - confirm
   before continuing.
3. **Users and groups**: assign the scope resolved in Step 3.
4. **Triggers for this policy**: select **User matches a data loss prevention (DLP) policy**, then
   add the DLP policy/policies checked for readiness in Step 2 (up to 20). If no qualifying DLP
   policy exists yet, select **User performs an exfiltration activity** instead, choose one or
   more built-in indicators, and choose default or custom thresholds - a fully valid, documented
   alternative this scenario does not further worked-example beyond this configuration reference.
5. **Policy indicators**: select **Office indicators** (SharePoint Online downloads/syncing,
   sharing internal files/folders externally, printing files, copying data to personal cloud
   storage/messaging services) - this template's primary, built-in scoring category. Optionally
   add Communication Compliance content indicators, generative AI app indicators, and/or cloud
   storage/cloud service indicators (Box, Dropbox, Google Drive, Amazon S3, Azure - requires those
   apps connected in Microsoft Defender for Cloud Apps and pay-as-you-go billing).
6. Select **Cumulative exfiltration detection** (enabled by default for this template - confirm it
   is actually selected rather than assuming the default survived any earlier "Turn on
   indicators" step).
7. **Review and submit.**

Use `deploy/policy/data-leaks-policy-manifest.json` as the checklist/reference while completing
this workflow - it is not consumed by any API.

### Step 5 - Add the DLP policy/policies to the global DLP-alerts indicator setting (portal, not scriptable)

Purview portal → **Insider Risk Management** → **Settings** → **Policy indicators** → **Built-in
Indicators** → **Data loss prevention (DLP) indicators** → **Add DLP policies**, and select each
policy checked in Step 2. This is a **global, tenant-wide** setting, not scoped to one IRM
policy - if other Insider Risk Management policies in the tenant also use the DLP-alerts
indicator, confirm this addition doesn't unintentionally widen their own trigger surface too.

### Step 6 - Export correlated alerts for SIEM/ticketing integration (scripted, read-only, reused)

```powershell
Connect-MgGraph -ClientId $AppId -TenantId $TenantId -CertificateThumbprint $Thumbprint

../departing-employee-data-theft/deploy/Export-InsiderRiskAlerts.ps1 `
    -SinceDateTime (Get-Date).AddDays(-1) -OutputPath ./data-leaks-alerts.json
```

This template has no Microsoft Defender for Endpoint signal to join against, so this scenario
reuses the plain export script, not the *Security Policy Violations (base template)* family's Defender-for-
Endpoint-joining variant.

**Caveat carried over from every IRM scenario in this library:** if more than one Insider Risk
Management policy is deployed in the tenant, this export cannot tell which policy produced a
given alert - `AlertPolicyId` has no documented way to map back to a named Purview policy.

### Step 7 - Validate

```powershell
./validate/Test-DataLeaksIrmSetup.ps1 -GroupId $ScopeGroupId -DlpTriggerConfigured
```

Checks the resolved scope against the default 15,000-user cap; pass `-MaxUsers` to override if
another policy built from this exact template already consumes part of that shared cap.

## Configuration reference

| Setting | Value this scenario uses | Notes |
|---|---|---|
| Policy template | `Data leaks` | Not found labeled preview in this build's grounding - re-verify at deploy time. Cannot be changed after creation |
| Triggering event (primary, worked example) | **User matches a DLP policy** - one or more existing policies, Exchange/SharePoint/OneDrive, High severity | Up to 20 DLP policies per IRM policy; checked via `deploy/Test-DlpPolicyIrmTriggerReadiness.ps1` |
| Triggering event (documented alternative, not worked-example'd) | **User performs an exfiltration activity** - built-in indicators, default or custom thresholds | Use if no qualifying DLP policy exists; the design notes |
| Double-scoping requirement | A user's DLP-triggered alert requires membership in **both** the DLP policy's own scope **and** this IRM policy's "Users and groups" scope | Not automatically cross-checked by any tool - manual confirmation required |
| Primary scoring indicator category | **Office indicators** (built-in) - SharePoint Online downloads/syncs, external file/folder sharing, printing files, copying to personal cloud storage/messaging services | No additional connector required |
| Cumulative exfiltration detection | **Enabled by default** for this template | Confirm selected at policy creation, not assumed |
| Optional scoring indicators | Communication Compliance content indicators; generative AI app indicators (Prompt Shields, Protected material detection) | Both documented as selectable for this template |
| Optional cloud indicators | Cloud storage (Box, Dropbox, Google Drive) / cloud service (Amazon S3, Azure) indicators | Confirmed applicable to this specific template (unlike the open question *Data Leaks by Risky Users* carries for itself); requires Defender for Cloud Apps + pay-as-you-go billing |
| Population mechanism | A plain Entra group (or groups), resolved via the reused base-template scope script | No HR-connector, Communication-Compliance-trigger, or priority-user-group requirement |
| Maximum actively-scored users for this template | **15,000** - confirmed via a direct Microsoft Learn fetch, cumulative tenant-wide across every policy built from this exact template | Do not reuse the *Security Policy Violations (base template)* (1,000) or risky/priority-users family (7,500) numbers - different templates |
| DLP-policy trigger workload support | Exchange Online, SharePoint Online, OneDrive for Business only | Endpoint DLP, Microsoft Teams, **Microsoft 365 Copilot**, on-premises repositories, and Power BI are explicitly NOT supported for this indicator - confirmed via a direct Microsoft Learn fetch. A policy that mixes a supported and an unsupported workload still has its supported-workload rules' alerts processed correctly (Microsoft states this explicitly) |
| DLP-policy trigger severity requirement | At least one rule at **High** severity on the parent DLP policy | Lower-severity-only policies never fire this trigger |
| Defender for Endpoint dependency | **None** | |
| User-identity privacy | Pseudonymized (Microsoft default) | Not disabled by this scenario |
| Alert export mechanism | Reused: `../departing-employee-data-theft/deploy/Export-InsiderRiskAlerts.ps1`, unmodified | The plain, non-MDE-joining variant |
| Cross-policy disambiguation | Not attempted - same disclosed gap as every IRM scenario in this library | `AlertPolicyId` has no documented policy-name mapping |

## Operations and tuning

- **Confirm the double-scoping overlap on every scope change, not just at initial deployment.**
  Adding a user to the IRM policy's group without also confirming they're in the parent DLP
  policy's own scope (or vice versa) silently produces no alert for that user - no error, no
  warning from either product.
- **This is a global indicator setting - coordinate before adding or removing a DLP policy from
  it.** Adding a DLP policy to the DLP-alerts indicator affects every Insider Risk Management
  policy in the tenant that also uses that indicator, not just this one. Confirm with whoever owns
  any other DLP-alerts-indicator-triggered IRM policy before changing the tenant-wide list.
- **Re-check the DLP policy's own severity/rule configuration on every change to the parent DLP
  scenario.** If the parent DLP policy (e.g. *Exchange PII Exfiltration Block (Block or Encrypt)*) changes a rule's
  `ReportSeverityLevel` away from High, or removes the rule entirely, this template's trigger
  silently stops firing for that content - re-run `deploy/Test-DlpPolicyIrmTriggerReadiness.ps1`
  after any change to a policy feeding this trigger.
- **Re-scope on group-membership change**, same reasoning as every group-scoped IRM template in
  this library - *Security Policy Violations (base template)* (operations and tuning), not repeated here in full.
- **Cumulative exfiltration detection depends on Microsoft Entra data sharing** for peer-group
  accuracy - same disclosed dependency as *Data Leaks by Risky Users* (operations and tuning).
- **If cloud-app indicators are enabled, monitor Defender for Cloud Apps connector health
  independently** - a disconnected connector silently stops contributing to this policy's scoring.
- **Pair with the HR-connector-triggered siblings for defense in depth, not as a replacement.**
  This template closes the "no precursor signal" gap those siblings' own reviews disclosed, but it
  is bounded by its own indicator/workload set - running this template alongside, not
  instead of, *Data Leaks by Risky Users* gives broader coverage than either alone for a
  population where both matter.
- **Confirm at deployment sign-off which triggering event is actually configured** - the DLP-policy trigger and the exfiltration-activity trigger produce materially different alert
  populations; documenting which one (or both, if that combination is confirmed viable - the known limitations) a
  given deployment uses avoids ambiguity during later review.

## Rollback and decommission

See the rollback runbook. Quick reference: removing a DLP policy from the global indicator list,
narrowing policy scope, or turning off an optional indicator is reversible in seconds; deleting
the policy or revoking an app registration's certificate is not.

## References

1. Learn about Insider Risk Management - Scenarios and policy templates overview -
   <https://learn.microsoft.com/purview/insider-risk-management>
2. Learn about Insider Risk Management policy templates - Data leaks template (description,
   "configure at least one Microsoft Purview Data Loss Prevention (DLP) policy... to receive
   insider risk alerts for High Severity DLP policy alerts," up to 20 DLP policies assignable as a
   triggering event, and the dual-scope requirement: "Only users included in Insider Risk
   Management policies using the Data leaks template have high severity DLP policy alerts
   processed, and only users included in a rule for a high severity DLP alert are analyzed by the
   Insider Risk Management policy for consideration") -
   <https://learn.microsoft.com/purview/insider-risk-management-policy-templates>
3. Get started with Insider Risk Management - Step 6, "Triggers for this policy" (the "User
   matches a data loss prevention (DLP) policy" vs. "User performs an exfiltration activity"
   triggering-event choice; default vs. custom thresholds for the exfiltration-activity option) -
   <https://learn.microsoft.com/purview/insider-risk-management-configure>
4. Configure policy indicators in Insider Risk Management - "Supported DLP workloads": Exchange
   Online, SharePoint Online, OneDrive for Business are supported; Endpoint DLP, Microsoft Teams,
   Microsoft 365 Copilot, on-premises repositories, and Power BI are explicitly listed as NOT
   currently supported, and "if your DLP policy spans multiple workloads... only the alerts from
   the supported workloads... are processed" - confirmed via a direct Microsoft Learn fetch -
   <https://learn.microsoft.com/purview/insider-risk-management-settings-policy-indicators#supported-dlp-workloads>
5. Create and manage Insider Risk Management policies - Cumulative exfiltration detection
   (enabled by default for Data leaks / Data leaks by priority users / Data leaks by risky users /
   Data theft by departing users) and template/name immutability after creation -
   <https://learn.microsoft.com/purview/insider-risk-management-policies>
6. Limits in Insider Risk Management - "Maximum number of users in scope for a policy template":
   Data leaks = **15,000** (Data leaks by priority users = 1,000; Data leaks by risky users =
   7,500; Security policy violations by priority users = 1,000, a separate row/cap) - confirmed
   via a direct Microsoft Learn fetch -
   <https://learn.microsoft.com/purview/insider-risk-management-limits#maximum-number-of-users-in-scope-for-a-policy-template>
7. *Data Leaks by Risky Users* and the design notes - this scenario's closest cousin in this
   library, whose own Red Team finding names the base `Data leaks` template as the
   compensating control this fragment builds. *Exchange PII Exfiltration Block, Part 2: Split/Obfuscated PII Compensating Control* (the prerequisites and the configuration reference)a and *PCI Teams Exfiltration Block, Part 2: Split/Obfuscated PAN Compensating Control* (the configuration reference)a - the two existing narrow, single-purpose deployments of this same template this fragment
   generalizes from. `security-policy-violations/deploy/
   Get-SecurityPolicyViolationsScopeCandidates.ps1` and `departing-employee-data-theft/deploy/
   Export-InsiderRiskAlerts.ps1` - reused unmodified.
8. alert resource type - `AlertPolicyId`, `DetectionSource` properties -
   <https://learn.microsoft.com/graph/api/resources/security-alert>
9. New-DlpComplianceRule / Get-DlpComplianceRule / Get-DlpCompliancePolicy reference
   (`ReportSeverityLevel`, `ExchangeLocation`/`SharePointLocation`/`OneDriveLocation` location
   properties) -
   <https://learn.microsoft.com/powershell/module/exchangepowershell/get-dlpcompliancepolicy>,
   <https://learn.microsoft.com/powershell/module/exchangepowershell/get-dlpcompliancerule>
10. List group transitive members (OData cast, required `ConsistencyLevel: eventual` header,
    `GroupMember.Read.All` among the higher-privileged application permissions) -
    <https://learn.microsoft.com/graph/api/group-list-transitivemembers?view=graph-rest-1.0>
11. Microsoft Graph permissions reference (`GroupMember.Read.All`, `SecurityAlert.Read.All`) -
    <https://learn.microsoft.com/graph/permissions-reference>
12. New-DlpCompliancePolicy / Set-DlpCompliancePolicy reference (`-EnforcementPlanes`,
    `-Locations`) and "Learn about using Microsoft Purview Data Loss Prevention to protect
    interactions with Microsoft 365 Copilot and Copilot Chat" (the Copilot-scoping mechanism
    `deploy/Test-DlpPolicyIrmTriggerReadiness.ps1`'s Copilot check is grounded against) -
    <https://learn.microsoft.com/powershell/module/exchangepowershell/new-dlpcompliancepolicy>,
    <https://learn.microsoft.com/purview/dlp-microsoft365-copilot-location-learn-about>

> Re-verify all links, cmdlet/API behavior, and licensing terms against current Microsoft Learn
> before a customer-facing assessment or sale. This scenario's original build session's citations
> were grounded via WebSearch only, in a network environment that blocked every direct URL fetch
> attempted (`EGRESS_BLOCKED`); a later follow-up fragment re-confirmed refs 4, 6, and 12 above via
> a direct Microsoft Learn fetch from a session whose network environment did not block it - those
> facts are no longer open VERIFYs. Remaining facts that could not be corroborated with reasonable
> confidence are still explicitly flagged `VERIFY` above and in the design notes rather than asserted.