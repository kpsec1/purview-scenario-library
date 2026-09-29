---
part: "runbook"
parent: "insider-risk/security-policy-violations"
---
## Implementation steps

### Step 1 - Assign permissions

Confirm the operator is a member of **Insider Risk Management** or **Insider Risk Management
Admins** (Purview role group), and has a Defender for Endpoint role capable of changing advanced
features (Step 2 below) - typically **Security Administrator**, or the granular permission
[RBAC model, section 12](/docs/rbac-model/#12-microsoft-defender-for-endpoint-portal-rbac---an-eighth-system-for-scenarios-that-configure-defender-for-endpoint-tenant-wide-settings) documents.

### Step 2 - Enable the Defender for Endpoint → Purview alert-sharing feature (manual, one-time)

Identical to the sibling scenario's step 2 of the implementation steps - **skip this step entirely if
*Security Policy Violations by Departing Users* is already deployed in this tenant**, since the
toggle is tenant-wide, not per-policy (the rollback runbook Stage 2 flags the same coupling here).

1. Sign in to the [Microsoft Defender portal](https://security.microsoft.com).
2. **Settings** → **Endpoints** → **Advanced features**.
3. Locate **Share endpoint alerts with Microsoft Compliance Center** and toggle it **On**.
4. Select **Save preferences**.

### Step 3 - Resolve and size the policy's user population (scripted, read-only)

Because this template has no built-in population mechanism (no HR feed, no priority-user-group
requirement) and Microsoft caps it at **1,000** actively-scored users tenant-wide, deliberately
choose a bounded population **before** creating the policy rather than defaulting to "all users" -
see the design notes for why an all-users scope would silently exceed the cap in any but a very small
tenant.

```powershell
Connect-MgGraph -ClientId $AppId -TenantId $TenantId -CertificateThumbprint $Thumbprint

# Dry run - shows the query plan, calls nothing
./deploy/Get-SecurityPolicyViolationsScopeCandidates.ps1 -GroupId $PrivilegedUsersGroupId -WhatIf

# Resolve one or more Entra security groups' transitive user membership, dedupe across groups,
# filter to enabled accounts, and check the combined count against the 1,000-user cap
./deploy/Get-SecurityPolicyViolationsScopeCandidates.ps1 -GroupId $PrivilegedUsersGroupId, $ContractorsGroupId -OutputPath ./scope-candidates.csv
```

This script is **read-only** - it never touches the IRM policy or the Entra group itself, only
reads and reports (the design notes goal 2). It cannot account for users already in scope of *other*
policies built from this same template elsewhere in the tenant - Microsoft's own cumulative,
per-template-type limit has no documented Graph/REST query API to read current usage against,
the same class of gap already established for the IRM alert audit log
(`docs/the project backlog's "Follow-ups discovered while building the IRM case-escalation-to-eDiscovery
scenario"). Flagged in the known limitations and the script's own `.NOTES`, not silently assumed away.

### Step 4 - Create the Insider Risk Management policy (portal, not scriptable)

Purview portal → **Insider Risk Management** → **Policies** → **Create policy**:

1. Template: **Security policy violations**. Confirm this is the base template and not one of its
   three siblings (by departing users / by priority users / by risky users) - all four share the
   same "Security policy violations…" naming prefix in the template picker.
2. Name: `Security Policy Violations`. The template and name can't be changed after policy creation
   - confirm before continuing.
3. **Users and groups**: select **Include specific users and groups**, then add the candidate
   population resolved in Step 3 - either the source Entra group(s) directly (Microsoft documents
   Microsoft 365 groups, distribution groups, and both mail-enabled and non-mail-enabled security
   groups as supported scope types), or the individual users from
   `scope-candidates.csv` if a tighter, hand-curated subset is preferred. **Do not select "Include
   all users and groups"** unless the tenant's total user count is confidently under the 1,000-user
   template cap - see the design notes. **VERIFY (pilot tenant):** whether adding the group
   itself keeps the policy's in-scope population in sync with future group-membership changes, or
   captures membership as a snapshot at the moment the group is added - Microsoft's own
   documentation doesn't state this either way, and this scenario's operations and tuning and the known limitations operational guidance
   (periodic re-review) applies regardless of which behavior turns out to be true.
4. **Triggering events**: none to configure - this template's only trigger is the Defender for
   Endpoint security-violation signal itself, already enabled by Step 2. Unlike
   the departing-users sibling, there is no HR-connector or Entra-account-deletion toggle on this
   template's workflow.
5. **Indicators**: select the **Microsoft Defender for Endpoint indicators (preview)** category.
   As with the departing-users sibling, Microsoft's documentation does not enumerate the individual
   indicator names under this category - **VERIFY against the live policy-creation workflow at
   deploy time** which specific indicator toggles appear, and whether any other indicator
   categories are also selectable for this specific template; not confirmed by Microsoft Learn
   during this build.
6. **Review and submit.**

Use `deploy/policy/security-policy-violations-policy-manifest.json` as the checklist/reference
while completing this workflow - it is not consumed by any API (see the file's own `_comment`
field and the design notes).

### Step 5 - Export correlated alerts for SIEM/ticketing integration (scripted, read-only, reused)

This scenario does not ship a second copy of the sibling scenario's alert-export script - Microsoft
Graph's `alerts_v2` query this scenario would need is identical (both `detectionSource` values,
joined client-side by `incidentId`), and the sibling's script already applies no policy-specific
filter, so it works unmodified against this policy's own alerts (the design notes goal 3):

```powershell
Connect-MgGraph -ClientId $AppId -TenantId $TenantId -CertificateThumbprint $Thumbprint

../security-policy-violations-by-departing-users/deploy/Export-SecurityViolationInsiderRiskAlerts.ps1 `
    -SinceDateTime (Get-Date).AddDays(-1) -OutputPath ./security-violation-alerts.json
```

**Caveat carried over unchanged from the sibling scenario:** if both this policy and the
departing-users (or any other "Security policy violations…" family) policy are deployed in the same
tenant, this export cannot tell which policy produced a given alert - `alertPolicyId` is exported as
raw, unmapped data (the sibling scenario's known limitations; not repeated in full here).

### Step 6 - Validate

```powershell
./validate/Test-SecurityPolicyViolationsIrmSetup.ps1
```

## Configuration reference

| Setting | Value this scenario uses | Notes |
|---|---|---|
| Policy template | `Security policy violations` **(preview)** - the base template | Cannot be changed after creation |
| Triggering event | Defense evasion of security controls or unwanted software, detected by Microsoft Defender for Endpoint | Not optional/configurable - this **is** the template's only trigger; no HR/Entra-deletion toggle exists on this template |
| Indicator category | **Microsoft Defender for Endpoint indicators (preview)** | Individual indicator names not enumerated by Microsoft as of this writing - VERIFY at deploy time |
| Maximum users in scope | **1,000** (Microsoft-fixed limit for this template, tenant-wide across all policies built from it) | - identical to the priority-users sibling's own cap despite requiring no priority-group object; smaller than the departing-users (15,000) and risky-users (7,500) siblings - do not conflate the four |
| Population mechanism | Operator-selected Entra security group(s) or individual users, resolved by `deploy/Get-SecurityPolicyViolationsScopeCandidates.ps1` | No HR connector, no formal priority-user-group requirement - a plain Entra group is sufficient |
| Defender for Endpoint alert-sharing dependency | "Share endpoint alerts with Microsoft Compliance Center" advanced feature (tenant-wide) | Same portal-only mechanism as the departing-users sibling - step 2 of the implementation steps |
| User-identity privacy | Pseudonymized (Microsoft default) | Not disabled by this scenario |
| Alert export mechanism | Reused: `../security-policy-violations-by-departing-users/deploy/Export-SecurityViolationInsiderRiskAlerts.ps1`, unmodified | No policy-specific filter exists in that script or in the underlying Graph API - works against any "Security policy violations…" family policy's alerts |
| Cross-policy-template disambiguation | Not attempted - same disclosed gap as the sibling scenario | `alertPolicyId` is exported as raw, unmapped data - the sibling scenario's known limitations |

## Operations and tuning

- **Re-scope on group membership change, not only on a calendar cadence.** Because it isn't
  documented whether the policy's in-scope population tracks the source group's live membership, treat a **newly added member of the source privileged group as unmonitored
  until an operator manually re-applies scope in the portal** - the higher-severity risk direction,
  since the population this template targets (privileged/IT/elevated-access users) is exactly the
  group where a coverage gap matters most. Tie re-running
  `Get-SecurityPolicyViolationsScopeCandidates.ps1` and re-applying the portal scope to the same
  process that adds someone to the source group (e.g., a step in the privileged-access-onboarding
  checklist), not only to a periodic calendar review. A quarterly review remains a reasonable
  **backstop** for catching drift missed by the event-driven process, not the primary control.
- **Defender for Endpoint alert-sharing health.** Same standing item as the sibling scenario's
  page operations and tuning - if the "Your organization doesn't have a Microsoft Defender for Endpoint
  subscription" or "Microsoft Defender for Endpoint alerts aren't being shared with the Microsoft
  Purview portal" policy-health notifications appear, this policy silently
  stops scoring new activity even though it looks correctly configured in the portal.
- **Incident-response runbook (alert triage)** - identical to the departing-users sibling's runbook
  (*Security Policy Violations by Departing Users* (operations and tuning)), reusing the same exported
  `RelatedDefenderAlerts` field from Step 5's export script.
- **Preview status is a rollout-pacing decision, not just a documentation footnote.** Same
  recommendation as the sibling scenario: pilot against a narrow population for at least one full
  activation-window cycle before treating this as a permanent, tenant-wide control in a
  customer-facing commitment.
- **Population-selection accountability.** Because this template does not have Microsoft's own
  built-in "priority user group" governance model (a named, auditable object with its own settings
  page) or an HR-driven trigger, the population choice is entirely the deploying operator's - a
  weaker built-in accountability trail than either sibling. Document the population-selection
  rationale (which group(s), why) outside this scenario's own artifacts - e.g., in the change
  ticket that authorized deployment - since Insider Risk Management itself doesn't capture "why
  was this group chosen" anywhere queryable.

## Rollback and decommission

See the rollback runbook. Quick reference: pausing the policy or removing groups from scope is reversible
in seconds; deleting the policy, or revoking the scope-resolution app registration's certificate, is
not.

## References

1. Learn about Insider Risk Management - Scenarios ("Intentional or unintentional security policy violations (preview)") - <https://learn.microsoft.com/purview/insider-risk-management#scenarios>
2. Learn about Insider Risk Management policy templates - Security policy violations (description, prerequisites/triggering-events table) - <https://learn.microsoft.com/purview/insider-risk-management-policy-templates#security-policy-violations>
3. Create and manage Insider Risk Management policies - policy health (HR connector shared across the departing-user templates; base "Security policy violations" is not part of that HR-connector group) - <https://learn.microsoft.com/purview/insider-risk-management-policies#policy-health>
4. Configure advanced features in Defender for Endpoint - "Share endpoint alerts with Microsoft Compliance Center" (portal steps, no API) - <https://learn.microsoft.com/defender-endpoint/advanced-features#share-endpoint-alerts-with-microsoft-compliance-center>
5. Create and manage Insider Risk Management policies (template/name immutable after creation) - <https://learn.microsoft.com/purview/insider-risk-management-policies>
6. Limits in Insider Risk Management - maximum users in scope per policy template (1,000 for "Security policy violations", identical to "…by priority users"; 15,000 for "…by departing users"; 7,500 for "…by risky users") - <https://learn.microsoft.com/purview/insider-risk-management-limits#maximum-number-of-users-in-scope-for-a-policy-template>
7. Learn about Insider Risk Management policy templates - Security policy violations (Defender for Endpoint subscription + integration prerequisite) - <https://learn.microsoft.com/purview/insider-risk-management-policy-templates#policy-template-prerequisites-and-triggering-events>
8. List group transitive members - OData cast (`/transitiveMembers/microsoft.graph.user`), required `ConsistencyLevel: eventual` header, permissions (`GroupMember.Read.All` among the higher-privileged options) - <https://learn.microsoft.com/graph/api/group-list-transitivemembers?view=graph-rest-1.0>
9. Get-MgGroupTransitiveMemberAsUser (PowerShell cmdlet reference, `Microsoft.Graph.Groups` module, output type `IMicrosoftGraphUser`) - <https://learn.microsoft.com/powershell/module/microsoft.graph.groups/get-mggrouptransitivememberasuser>
10. Get started with Insider Risk Management - Step 6, Users and groups page (supported scope group types: Microsoft 365 groups, distribution groups, mail-enabled and non-mail-enabled security groups) - <https://learn.microsoft.com/purview/insider-risk-management-configure#step-6-required-create-an-insider-risk-management-policy>
11. alert resource type - `alertPolicyId`, `incidentId`, `detectionSource` properties - <https://learn.microsoft.com/graph/api/resources/security-alert>
12. Microsoft Graph permissions reference (`GroupMember.Read.All`, `SecurityAlert.Read.All`) - <https://learn.microsoft.com/graph/permissions-reference>

> Re-verify all links, cmdlet/API behavior, and licensing terms against current Microsoft Learn
> before a customer-facing assessment or sale - this template family is explicitly Microsoft-
> labeled preview and could change materially before reaching general availability.