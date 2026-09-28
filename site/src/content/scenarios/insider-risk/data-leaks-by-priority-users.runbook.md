---
part: "runbook"
parent: "insider-risk/data-leaks-by-priority-users"
---
## Implementation steps

### Step 1 - Assign permissions

Confirm the operator is an **unrestricted administrator** member of **Insider Risk Management** or
**Insider Risk Management Admins** (Purview role group) - a restricted/scoped administrator cannot
create a policy from this template at all, because priority-user-group-based policies don't support
admin-unit scoping. If using the DLP-policy trigger, also confirm at least
read access to the candidate DLP policy/policies ([RBAC model, section 4](/docs/rbac-model/#4-purview-role-groups-by-module-representative-not-exhaustive)).

### Step 2 - Check candidate DLP policies for trigger readiness (scripted, read-only, reused - optional)

Skip this step entirely if using the exfiltration-activity trigger instead.

```powershell
Connect-IPPSSession -AppId $AppId -Certificate $Cert -Organization $TenantDomain

# Dry run - shows the query plan, calls nothing
../data-leaks/deploy/Test-DlpPolicyIrmTriggerReadiness.ps1 -DlpPolicyName 'PII DLP - Exchange External Send Control' -WhatIf

# Check one or more existing policies
../data-leaks/deploy/Test-DlpPolicyIrmTriggerReadiness.ps1 -DlpPolicyName 'PII DLP - Exchange External Send Control', 'SharePoint PII Guardrail'
```

This is the base `Data leaks` scenario's own script, reused unmodified - it has no
template-specific logic beyond workload/severity/Mode/20-policy-ceiling checks that apply
identically here (the design notes goal 1). Fix any `[FAIL]` before continuing.

### Step 3 - Resolve and size the priority-group candidate list (scripted, read-only, reused)

```powershell
Connect-MgGraph -ClientId $AppId -TenantId $TenantId -CertificateThumbprint $Thumbprint

# Dry run - shows the query plan, calls nothing
../security-policy-violations-by-priority-users/deploy/Get-PriorityUserGroupScopeCandidates.ps1 `
    -GroupId $PriorityPopulationGroupId -MaxActivelyScored 1000 -MaxGroupMembers 10000 -WhatIf

# Resolve, dedupe, filter to enabled accounts, check against BOTH documented caps, write a
# bulk-upload-ready CSV
../security-policy-violations-by-priority-users/deploy/Get-PriorityUserGroupScopeCandidates.ps1 `
    -GroupId $PriorityPopulationGroupId -MaxActivelyScored 1000 -MaxGroupMembers 10000 `
    -OutputPath ./data-leaks-priority-users-candidates.csv
```

`-MaxActivelyScored 1000` and `-MaxGroupMembers 10000` are this script's own defaults - passed
explicitly here rather than left implicit, because this scenario's own grounding pass independently
confirmed **this exact template's** 1,000-user cap from Microsoft's Limits table, rather than assuming it matches the sibling template's numerically identical
cap by analogy (the design notes goal 2). This script is **read-only**; it never touches the IRM
policy, the priority user group, or the Entra group itself.

### Step 4 - Create the priority user group (portal, not scriptable)

Identical workflow to the *Security Policy Violations by Priority Users* sibling's own Step 4
(`../security-policy-violations-by-priority-users/the implementation steps Step 4) - **skip this step and
reuse the existing priority user group if one already exists for this population**, since a
priority user group is a standalone, template-agnostic object, not owned by any one policy.
**Before reusing an existing group, confirm reviewer-permission scoping is a property of the group
itself, not of any one policy**: if this scenario's policy references the same priority
user group as an existing `Security policy violations by priority users` policy, both policies'
alerts for that population become visible to the identical set of reviewers - there is no way to
give the two templates different reviewer scopes for the same underlying population without
creating a second, separate priority user group.

1. Purview portal → **Settings** → **Insider Risk Management** → **Priority user groups** →
   **Create priority user group**.
2. **Name and describe**, then **Next**.
3. **Choose members**: search/select, or upload the CSV from Step 3.
4. **Assign review permissions**: select which role groups or individual users can review this
   priority group's data - do this deliberately for a sensitive population.
5. **Review and finish.**

### Step 5 - Create the Insider Risk Management policy (portal, not scriptable)

Purview portal → **Insider Risk Management** → **Policies** → **Create policy**:

1. Template: **Data leaks by priority users**. Confirm this is the priority-users member of the
   **Data leaks…** family and not `Data leaks`/`…by risky users`, and not either
   `Security policy violations…` template - all four "priority/risky users" templates across the
   two families share overlapping naming in the template picker.
2. Name: `Data Leaks by Priority Users`. The template and name can't be changed after policy
   creation - confirm before continuing.
3. **Users and groups**: select **Add or edit priority user groups** - an option Microsoft's own
   configuration guide states appears **only** for this template - and assign
   the priority user group created in Step 4. This is a distinct UI path from the base template's
   plain "Include specific users and groups" option; do not confuse the two.
4. **Triggers for this policy**: select **User matches a data loss prevention (DLP) policy** (add
   the policy/policies checked in Step 2, up to 20) **or** **User performs an exfiltration
   activity** (choose one or more built-in indicators and default or custom thresholds) - the
   identical two-option choice the base `Data leaks` template offers. This
   scenario does not further worked-example the exfiltration-activity path beyond this
   configuration reference, matching the base template scenario's own scope (`../data-leaks/
   the design notes).
5. **Policy indicators**: select **Office indicators** (SharePoint sites, Microsoft Teams, and
   email messaging, per Microsoft's current description) and **Cumulative
   exfiltration detection** (enabled by default for this template - confirm actually selected).
   Under **Risk score boosters**, explicitly select **User is a member of a priority user group**
   - a **separate checkbox** from every other setting on this page; without it, priority-group
   members receive no likelihood/severity boost over the general population despite the group
   assignment in Step 3 (the design notes goal 4, section 5). Optionally add Communication Compliance
   content indicators and/or generative AI app indicators, both documented as selectable for this
   template. **VERIFY against the live workflow** whether cloud storage/cloud
   service indicators (Box, Dropbox, Google Drive, Amazon S3, Azure) are also offered - Microsoft's
   per-template description text does not name them explicitly for this template, the same open
   question the *Data Leaks by Risky Users* sibling already carries for itself.
6. **Review and submit.**

Use `deploy/policy/data-leaks-priority-users-policy-manifest.json` as the checklist/reference while
completing this workflow - it is not consumed by any API.

### Step 6 - Add the DLP policy/policies to the global DLP-alerts indicator setting (portal, not scriptable - if using the DLP trigger)

Purview portal → **Insider Risk Management** → **Settings** → **Policy indicators** → **Built-in
Indicators** → **Data loss prevention (DLP) indicators** → **Add DLP policies**, and select each
policy checked in Step 2. This is a **global, tenant-wide** setting shared with every other
Data-leaks-family policy in the tenant - confirm this addition doesn't unintentionally widen
another policy's trigger surface, identical caveat to the base template scenario's own step 5 of the implementation steps.

### Step 7 - Export correlated alerts for SIEM/ticketing integration (scripted, read-only, reused)

```powershell
Connect-MgGraph -ClientId $AppId -TenantId $TenantId -CertificateThumbprint $Thumbprint

../departing-employee-data-theft/deploy/Export-InsiderRiskAlerts.ps1 `
    -SinceDateTime (Get-Date).AddDays(-1) -OutputPath ./data-leaks-priority-users-alerts.json
```

No Defender for Endpoint signal exists for this template, so this scenario reuses the plain export
script, not the *Security Policy Violations (base template)* family's Defender-for-Endpoint-joining variant.

**Caveat carried over from every IRM scenario in this library:** if more than one Insider Risk
Management policy is deployed in the tenant, this export cannot tell which policy produced a given
alert - `AlertPolicyId` has no documented policy-name mapping.

### Step 8 - Validate

```powershell
./validate/Test-DataLeaksPriorityUsersIrmSetup.ps1 -GroupId $PriorityPopulationGroupId -DlpTriggerConfigured
```

## Configuration reference

| Setting | Value this scenario uses | Notes |
|---|---|---|
| Policy template | `Data leaks by priority users` | Not found labeled preview in this build's grounding - re-verify at deploy time. Cannot be changed after creation |
| Triggering event | **User matches a DLP policy** (up to 20 policies, optional) **or** **User performs an exfiltration activity** - the identical choice the base `Data leaks` template offers | - a materially different shape from the fixed, single-trigger `Security policy violations by priority users` sibling |
| Population mechanism | **Priority user group** - required, not optional, via the **"Add or edit priority user groups"** option on the Users and groups page | - a distinct UI path confirmed by name, not the base template's plain-group "Include specific users and groups" option |
| Maximum members in a priority user group | **10,000** (Microsoft-fixed, tenant-wide, not per-template) | |
| Maximum actively-scored users for this template | **1,000** - its own, independently-documented cap, cumulative **only** across policies built from this exact template | - numerically identical to `Security policy violations by priority users` but a **separate** cap; do not conflate the two, and do not assume it is shared with either same-family sibling (15,000 / 7,500) |
| Priority-group scoring boost | A **separate, explicitly-selectable** "Risk score booster" - **"User is a member of a priority user group"** - not an automatic consequence of population assignment | - the design notes goal 4 |
| Reviewer-permission scoping | Optional, per-priority-group restriction of who can review that group's data | |
| Primary scoring indicator category | **Office indicators** - SharePoint sites, Microsoft Teams, and email messaging (current Microsoft description) | |
| Cumulative exfiltration detection | **Enabled by default** for this template | - confirm selected at policy creation, not assumed |
| Optional scoring indicators | Communication Compliance content indicators; generative AI app indicators (Prompt Shields, Protected material detection) | Both explicitly confirmed selectable for this template |
| Optional cloud indicators | Cloud storage (Box, Dropbox, Google Drive) / cloud service (Amazon S3, Azure) | **Not confirmed applicable to this specific template** - open VERIFY, same as *Data Leaks by Risky Users* |
| DLP-policy trigger workload support | Exchange Online, SharePoint Online, OneDrive for Business only | Endpoint DLP, Microsoft Teams, **Microsoft 365 Copilot**, on-premises repositories, and Power BI are explicitly **not** supported for this indicator - a fuller list than this library's own base `Data leaks` scenario carries |
| Admin unit scoping | **Not supported** for this template; only an unrestricted administrator can create this policy | |
| Defender for Endpoint dependency | **None** | |
| User-identity privacy | Pseudonymized (Microsoft default) | Not disabled by this scenario |
| Alert export mechanism | Reused: `../departing-employee-data-theft/deploy/Export-InsiderRiskAlerts.ps1`, unmodified | The plain, non-MDE-joining variant |
| Cross-policy disambiguation | Not attempted - same disclosed gap as every IRM scenario in this library | `AlertPolicyId` has no documented policy-name mapping |

## Operations and tuning

- **Confirm the risk score booster is actually selected, not just the population assignment.**
  This scenario's single most operationally significant, newly-surfaced finding (the design notes
  goal 4): a policy can have a correctly-populated priority user group and still score that
  population identically to a plain-group population if **"User is a member of a priority user
  group"** was never selected under Risk score boosters. Check this explicitly at every deployment
  sign-off and after any policy edit - there is no automated way to detect this misconfiguration.
- **Re-scope on priority-group-membership change, not only on a calendar cadence** - identical
  reasoning to *Security Policy Violations by Priority Users* (operations and tuning), not repeated here in
  full.
- **If using the DLP-policy trigger, confirm the double-scoping overlap on every scope change** -
  identical reasoning to the base template scenario's own operations and tuning: a user in the priority user group but
  not in the parent DLP policy's own scope (or vice versa) never has an alert processed.
- **The DLP-alerts indicator is a global, tenant-wide setting** - coordinate before adding or
  removing a DLP policy from it if other Data-leaks-family or Data-theft policies in the tenant
  also use it.
- **Confirm what the live portal actually does as the priority user group approaches 1,000
  members** - the same open dual-cap-interaction question *Security Policy Violations by Priority Users* (the prerequisites) carries for itself, now independently confirmed to be a **per-exact-template**
  cap for this scenario rather than a family-wide pool - `validate/
  Test-DataLeaksPriorityUsersIrmSetup.ps1`'s manual checklist includes this explicitly.
- **Use the reviewer-permission scoping deliberately, not by default** - identical guidance to the
  *Security Policy Violations by Priority Users* sibling's own section 8.
- **Reviewer-permission scoping is a property of the priority user group, not of the policy.**
  If this scenario's policy and a `Security policy violations by priority users` policy both
  reference the same priority user group, both templates' alerts for that population are visible
  to the identical reviewer set - there is no per-policy override. Confirm this is the intended
  outcome before reusing an existing group across templates; create a second, dedicated priority
  user group instead if the two templates' alerts need different reviewers.
- **Pair with the base `Data leaks` template for general-population coverage** - this template's
  1,000-user cap and priority-group requirement make it unsuitable as the tenant's only
  DLP-triggered exfiltration control; run it alongside (not instead of) `../data-leaks/` for the
  broader population.

## Rollback and decommission

See the rollback runbook. Quick reference: removing the priority user group from policy scope, removing a
DLP policy from the global indicator list, or deselecting the risk score booster is reversible in
seconds; deleting the policy or the priority user group itself, or revoking either app
registration's certificate, is not.

## References

1. Get started with Insider Risk Management - Step 4, "Configure priority user groups": "A priority user group is required when using the following policy templates: Security policy violations by priority users, Data leaks by priority users" - <https://learn.microsoft.com/purview/insider-risk-management-configure#step-4-recommended-configure-prerequisites-for-policies>
2. Learn about Insider Risk Management policy templates - Data leaks by priority users (description: "you need to assign priority user groups created in Insider Risk Management > Settings > Priority user groups to the policy") - <https://learn.microsoft.com/purview/insider-risk-management-policy-templates#data-leaks-by-priority-users>
3. Learn about Insider Risk Management policy templates - Policy template prerequisites and triggering events table: "Data leaks by priority users - Triggering events: Data leak policy activity that creates a High severity alert or built-in exfiltration event triggers. Prerequisites: DLP policy configured for High severity alerts (Exchange Online, SharePoint Online, or OneDrive for Business workloads only) OR Customized triggering indicators; Priority user groups configured in insider risk settings" - <https://learn.microsoft.com/purview/insider-risk-management-policy-templates#policy-template-prerequisites-and-triggering-events>
4. Get started with Insider Risk Management - Step 6, "Users and groups" page: "Add or edit priority user groups. This option appears only if you choose the Data leaks by priority users template," and the admin-unit restriction note: "Priority user groups aren't currently supported for admin units. If you're creating a policy based on the Data leaks by priority users template or the Security policy violations by priority users template, you can't select admin units for scoping the policy. Unrestricted administrators can select priority user groups without selecting admin units, but restricted or scoped administrators can't create these policies at all." - <https://learn.microsoft.com/purview/insider-risk-management-configure#step-6-required-create-an-insider-risk-management-policy>
5. Configure policy indicators in Insider Risk Management - Office indicators ("SharePoint sites, Microsoft Teams, and email messaging") and Risk score boosters ("User is a member of a priority user group: Scores are boosted if the user is a member of a priority user group") - <https://learn.microsoft.com/purview/insider-risk-management-settings-policy-indicators#built-in-indicators-vs-custom-indicators>
6. Limits in Insider Risk Management - maximum users in scope per policy template: Data leaks by priority users = 1,000; Data leaks by risky users = 7,500; Data leaks = 15,000; Security policy violations by priority users = 1,000 (separate row/cap) - <https://learn.microsoft.com/purview/insider-risk-management-limits#maximum-number-of-users-in-scope-for-a-policy-template>
7. Learn about Insider Risk Management policy templates - Policy template limits: "The limit for each policy calculates the total number of unique users receiving risk scores per policy template type... These maximum limits apply to users across all policies using a given policy template" - <https://learn.microsoft.com/purview/insider-risk-management-policy-templates#policy-template-limits>
8. Prioritize user groups for Insider Risk Management policies - priority user group creation workflow, 10,000-member cap, reviewer-permission scoping, likelihood/severity scoring effect - <https://learn.microsoft.com/purview/insider-risk-management-settings-priority-user-groups>
9. Configure policy indicators in Insider Risk Management - Data loss prevention alerts indicators, supported workloads (Exchange Online, SharePoint Online, OneDrive for Business) and explicitly unsupported workloads (Endpoint DLP, Microsoft Teams, Microsoft 365 Copilot, on-premises repositories, Power BI) - <https://learn.microsoft.com/purview/insider-risk-management-settings-policy-indicators#supported-dlp-workloads>
10. Create and manage Insider Risk Management policies - Cumulative exfiltration detection, enabled by default for "Data leaks / Data leaks by priority users / Data leaks by risky users / Data theft by departing users" - <https://learn.microsoft.com/purview/insider-risk-management-policies#cumulative-exfiltration-detection>
11. Create and manage Communication Compliance policies - Communication Compliance content indicators and generative AI app indicators (Prompt Shields, Protected material detection) explicitly listed as selectable for the "Data leaks, Data leaks by risky users, Data leaks by priority users" templates - <https://learn.microsoft.com/purview/communication-compliance-policies#integrate-communication-compliance-with-microsoft-purview-insider-risk-management>
12. `../data-leaks/this page and the design notes, `../security-policy-violations-by-priority-users/this page and the design notes - this scenario's two direct ancestors, whose already-built scripts (`Test-DlpPolicyIrmTriggerReadiness.ps1`, `Get-PriorityUserGroupScopeCandidates.ps1`) and `../departing-employee-data-theft/deploy/Export-InsiderRiskAlerts.ps1` are reused unmodified rather than re-verified independently.
13. alert resource type - `AlertPolicyId`, `DetectionSource` properties - <https://learn.microsoft.com/graph/api/resources/security-alert>
14. List group transitive members / Get-MgGroupTransitiveMemberAsUser / `GroupMember.Read.All` and `SecurityAlert.Read.All` permissions - reused unmodified from the scripts cited in reference 12; see those scripts' own `.NOTES` for the underlying Graph API citations.

> Re-verify all links, cmdlet/API behavior, and licensing terms against current Microsoft Learn
> before a customer-facing assessment or sale. This build's citations were grounded via direct
> Microsoft Learn MCP fetch/search of the URLs above, not WebSearch snippets alone - where this
> build's own findings differ from or add detail beyond an already-built sibling scenario's own
> (older) grounding pass, the known limitations states this explicitly rather than silently overriding the sibling.