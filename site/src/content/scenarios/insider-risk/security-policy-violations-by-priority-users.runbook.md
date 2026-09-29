---
part: "runbook"
parent: "insider-risk/security-policy-violations-by-priority-users"
---
## Implementation steps

### Step 1 - Assign permissions

Confirm the operator is a member of **Insider Risk Management** or **Insider Risk Management
Admins** (Purview role group), and has a Defender for Endpoint role capable of changing advanced
features (Step 2 below) - typically **Security Administrator**, or the granular permission
[RBAC model, section 12](/docs/rbac-model/#12-microsoft-defender-for-endpoint-portal-rbac---an-eighth-system-for-scenarios-that-configure-defender-for-endpoint-tenant-wide-settings) documents.

### Step 2 - Enable the Defender for Endpoint → Purview alert-sharing feature (manual, one-time)

Identical to the base and departing-users siblings' own Step 2 - **skip this step entirely if
either sibling is already deployed in this tenant**, since the toggle is tenant-wide, not
per-policy (the rollback runbook Stage 2 flags the same coupling here).

1. Sign in to the [Microsoft Defender portal](https://security.microsoft.com).
2. **Settings** → **Endpoints** → **Advanced features**.
3. Locate **Share endpoint alerts with Microsoft Compliance Center** and toggle it **On**.
4. Select **Save preferences**.

### Step 3 - Resolve and size the priority-group candidate list (scripted, read-only)

Choose the Entra security group (or groups) whose membership should become the priority user
group's population, then resolve and size it against **both** documented caps before creating the
priority user group - see the design notes for why neither cap alone tells the full story.

```powershell
Connect-MgGraph -ClientId $AppId -TenantId $TenantId -CertificateThumbprint $Thumbprint

# Dry run - shows the query plan, calls nothing
./deploy/Get-PriorityUserGroupScopeCandidates.ps1 -GroupId $PrivilegedUsersGroupId -WhatIf

# Resolve one or more Entra security groups' transitive user membership, dedupe across groups,
# filter to enabled accounts, check against the 10,000-member group cap AND the 1,000-actively-
# scored template cap, and write a CSV ready for the portal's bulk-upload dialog
./deploy/Get-PriorityUserGroupScopeCandidates.ps1 -GroupId $ExecutivesGroupId -OutputPath ./priority-user-group-candidates.csv
```

This script is **read-only** - it never touches the IRM policy, the priority user group, or the
Entra group itself, only reads and reports (the design notes goal 2). It cannot account for users
already actively scored under **other** policies built from this same template elsewhere in the
tenant, and it cannot confirm what actually happens if the resulting priority user group exceeds
1,000 members once assigned to a policy - both are disclosed gaps, not silently assumed away; see
the known limitations and the script's own `.NOTES`.

### Step 4 - Create the priority user group (portal, not scriptable)

Purview portal → **Settings** → **Insider Risk Management** → **Priority user groups** →
**Create priority user group**:

1. **Name and describe the priority user group**: enter a name and description, then **Next**.
2. **Choose members**: search and select users individually, **or** upload the CSV produced by
   Step 3 (a `user principal name`-headed file - confirm the exact expected column header and
   accepted file format against the live upload dialog at deploy time; **VERIFY**). Members must be
   resolvable, mail-enabled users in the directory - `Get-PriorityUserGroupScopeCandidates.ps1`
   flags candidates with no `mail` attribute as a `[WARN]`, an approximation for "mail-enabled,"
   not a guarantee.
3. **Assign review permissions**: select which of the **Insider Risk Management**, **Insider Risk
   Management Analysts**, **Insider Risk Management Investigators** role groups - or which
   individual users - can review this priority group's users, alerts, cases, and reports. Do this deliberately for a sensitive population rather than accepting
   whatever default reviewer scope applies - operations and tuning.
4. **Review and finish.**

### Step 5 - Create the Insider Risk Management policy (portal, not scriptable)

Purview portal → **Insider Risk Management** → **Policies** → **Create policy**:

1. Template: **Security policy violations by priority users**. Confirm this is the priority-users
   member of the family and not one of its three siblings (base / by departing users / by risky
   users) - all four share the same "Security policy violations…" naming prefix in the template
   picker.
2. Name: `Security Policy Violations by Priority Users`. The template and name can't be changed
   after policy creation - confirm before continuing.
3. **Users and groups**: assign the priority user group created in Step 4 as this policy's
   population. **VERIFY at deploy time** whether the "Users and groups" step for this specific
   template accepts *only* a priority user group, or additionally allows a plain Entra group or
   individual users alongside it (e.g., a broader base population plus a priority-boosted subset)
   - Microsoft's own policy-templates prerequisite table states that a priority user group must be
   assigned to this template, but this build found no worked example or portal
   screenshot confirming whether that requirement is exclusive or additive. Do not assume either
   way; confirm against the live policy-creation workflow before finalizing scope. **Note on the UI
   control's exact name:** Microsoft's own "Get started" workflow guide names a distinct **"Add or
   edit priority user groups"** option on this page, but states in the same sentence that it
   "appears only if you choose the *Data leaks by priority users* template" -
   the sibling template that also requires a priority user group. That guide does not name an
   equivalent option for *this* template. Do not assume the "Add or edit priority user groups"
   label is what appears here; confirm the actual control name shown for this specific template at
   deploy time rather than reusing the sibling's confirmed UI text.
4. **Triggering events**: none to configure - identical to the base template, this template's only
   trigger is the Defender for Endpoint security-violation signal itself, already enabled by
   Step 2. There is no HR-connector or Entra-account-deletion toggle on this template's workflow.
5. **Indicators**: select the **Microsoft Defender for Endpoint indicators (preview)** category.
   As with every sibling in this family, Microsoft's documentation does not enumerate the
   individual indicator names under this category - **VERIFY against the live policy-creation
   workflow at deploy time** which specific indicator toggles appear, and whether any other
   indicator categories are also selectable for this specific template; not confirmed by Microsoft
   Learn during this build. **Separately, VERIFY whether "Risk score boosters" - specifically
   "User is a member of a priority user group," a booster Microsoft's Configure policy indicators
   reference documents generically, not scoped to any one template - is
   actually offered for a policy built from this template.** Microsoft's own "Get started" workflow
   guide ties Risk score booster availability to selecting "at least one Office or Device
   indicator", and this template's only selectable indicator category is
   **Microsoft Defender for Endpoint indicators (preview)** - a third, separately-documented
   category, distinct from both "Office" and "Device" indicators. No worked example was found
   either confirming or excluding booster availability for a Defender-for-Endpoint-only indicator
   selection; do not assume the priority-group scoring boost described in the configuration reference is automatically
   applied without confirming this checkbox is actually visible and selected at deploy time.
6. **Review and submit.**

Use `deploy/policy/security-policy-violations-priority-users-policy-manifest.json` as the
checklist/reference while completing this workflow - it is not consumed by any API.

### Step 6 - Export correlated alerts for SIEM/ticketing integration (scripted, read-only, reused)

This scenario does not ship a third copy of the family's alert-export script - the base template
scenario already established that Microsoft Graph's `alerts_v2` query it needs applies no
policy-specific filter, so it works unmodified against this policy's own alerts too
(the design notes goal 4):

```powershell
Connect-MgGraph -ClientId $AppId -TenantId $TenantId -CertificateThumbprint $Thumbprint

../security-policy-violations-by-departing-users/deploy/Export-SecurityViolationInsiderRiskAlerts.ps1 `
    -SinceDateTime (Get-Date).AddDays(-1) -OutputPath ./security-violation-alerts.json
```

**Caveat carried over unchanged from every sibling in this family:** if more than one "Security
policy violations…" template is deployed in the same tenant, this export cannot tell which policy
produced a given alert - `alertPolicyId` is exported as raw, unmapped data (base template
the known limitations; not repeated in full here).

### Step 7 - Validate

```powershell
./validate/Test-PriorityUserGroupIrmSetup.ps1
```

## Configuration reference

| Setting | Value this scenario uses | Notes |
|---|---|---|
| Policy template | `Security policy violations by priority users` **(preview)** | Cannot be changed after creation |
| Triggering event | Defense evasion of security controls or unwanted software, detected by Microsoft Defender for Endpoint | Not optional/configurable - identical to the base template; no HR/Entra-deletion toggle exists on this template either |
| Indicator category | **Microsoft Defender for Endpoint indicators (preview)** | Individual indicator names not enumerated by Microsoft as of this writing - VERIFY at deploy time |
| Population mechanism | A **priority user group** (Settings → Priority user groups) is required for this template | Distinguishing prerequisite versus the base template - the design notes goal 1. Whether it can be combined with additional plain-group/individual scope on the same policy is unconfirmed - step 5 of the implementation steps. The exact **UI control name** used to assign it on this template's "Users and groups" page is also unconfirmed - Microsoft names "Add or edit priority user groups" only for the *Data leaks by priority users* sibling - step 3 of the implementation steps |
| Maximum members in a priority user group | **10,000** (Microsoft-fixed limit per group) | |
| Maximum actively-scored users for this template | **1,000**, cumulative tenant-wide across all policies built from this exact template - **its own, independently-tracked pool, not shared with the base "Security policy violations" template** | - Microsoft's Policy template limits reference states the cap applies "across all policies using a given policy template" and lists each template as its own row; the base template happens to document the identical number (1,000), which is a coincidence of the two caps' size, not evidence of a shared pool - smaller than the departing-users (15,000) and risky-users (7,500) siblings' own, separately-tracked caps - do not conflate any of the four |
| Interaction between the two caps above | **Undocumented - VERIFY (pilot tenant)** | the design notes; treated as an open question, not assumed either way. This is a *different* open question from the (now-confirmed) fact that the 1,000-user cap itself is not shared with the base template - see the row above |
| Priority-group effect on scoring | Increases both **likelihood** and **severity** of resulting alerts for the same underlying activity, versus a non-priority user | - the functional reason to choose this template over the base one, beyond population mechanism. Whether the separate "Risk score boosters" → "User is a member of a priority user group" checkbox is additionally required, and whether it's even offered for this template's Defender-for-Endpoint-only indicator category, is a separate, unresolved **VERIFY** - do not conflate the two |
| Reviewer-permission scoping | Optional, per-priority-group restriction of who can review that group's alerts/cases/reports to specific role groups or individuals | - a capability the base template's plain-group mechanism does not offer; operations and tuning |
| Defender for Endpoint alert-sharing dependency | "Share endpoint alerts with Microsoft Compliance Center" advanced feature (tenant-wide) | Same portal-only mechanism as every sibling - step 2 of the implementation steps |
| User-identity privacy | Pseudonymized (Microsoft default) | Not disabled by this scenario |
| Alert export mechanism | Reused: `../security-policy-violations-by-departing-users/deploy/Export-SecurityViolationInsiderRiskAlerts.ps1`, unmodified | No policy-specific filter exists in that script or in the underlying Graph API |
| Cross-policy-template disambiguation | Not attempted - same disclosed gap as every sibling | `alertPolicyId` is exported as raw, unmapped data |

## Operations and tuning

**This scenario's incident-response runbook, Defender for Endpoint alert-sharing health check, and
preview-status rollout-pacing recommendation mirror the base and departing-users siblings' own
page operations and tuning guidance exactly** - re-read those sections; they are not repeated here to avoid drift
between three copies of the same guidance. Items specific to this scenario:

- **Re-scope on priority-group-membership change, not only on a calendar cadence.** Same
  Red-Team/Blue-Team-driven reasoning the base template scenario's own operations and tuning already applies to its
  plain-group population: because Microsoft doesn't document whether the priority user group's
  membership can drift out of step with the source Entra group used to build it (this scenario's
  candidate CSV is a point-in-time snapshot, not a live sync - the known limitations), treat adding someone to the
  source privileged/executive group as incomplete until the priority user group's own membership is
  updated to match, on the same process trigger, not a periodic review alone. A quarterly review of
  the priority user group's actual membership remains a reasonable **backstop**, not the primary
  mechanism.
- **Confirm what the live portal actually does as the priority user group approaches 1,000
  members** - the open cap-interaction question. Run this check the first time
  this template is deployed and again any time the priority user group's membership grows
  materially, not only once at initial rollout - `validate/Test-PriorityUserGroupIrmSetup.ps1`'s
  manual checklist includes this explicitly.
- **Use the reviewer-permission scoping deliberately, not by default.** For a genuinely sensitive
  priority population (executives, subjects of an active investigation), restrict review to a named
  subset of the IRM team at Step 4 rather than leaving the group reviewable by every Insider Risk
  Management Analyst/Investigator in the tenant - the least-privilege benefit this template offers
  over the base template only materializes if this step is actually used, not left at whatever the
  broader tenant-wide role-group membership would otherwise allow.
- **Defender for Endpoint alert-sharing health.** Same standing item as every sibling - if the
  "Your organization doesn't have a Microsoft Defender for Endpoint subscription" or "Microsoft
  Defender for Endpoint alerts aren't being shared with the Microsoft Purview portal" policy-health
  notifications appear, this policy silently stops scoring new activity even though it looks
  correctly configured in the portal.
- **Incident-response runbook (alert triage)** - identical to the base and departing-users
  siblings' runbook, reusing the same exported `RelatedDefenderAlerts` field. Because membership in
  this template's population signals an organizationally-designated elevated-risk user, treat a
  confirmed finding here with correspondingly higher urgency in triage prioritization than an
  equivalent base-template alert - consistent with Microsoft's own likelihood/severity boost for
  this population.
- **Preview status is a rollout-pacing decision, not just a documentation footnote.** Same
  recommendation as every sibling: pilot against a narrow priority population for at least one full
  activation-window cycle before treating this as a permanent, tenant-wide control in a
  customer-facing commitment.

## Rollback and decommission

See the rollback runbook. Quick reference: removing the priority user group from policy scope is
reversible in seconds; deleting the policy or the priority user group itself, or revoking the
candidate-resolution app registration's certificate, is not.

## References

1. Learn about Insider Risk Management policy templates - Security policy violations by priority users (description, prerequisites table, priority-user-group requirement, Defender for Endpoint requirement) - <https://learn.microsoft.com/purview/insider-risk-management-policy-templates#security-policy-violations-by-priority-users>
2. Prioritize user groups for Insider Risk Management policies - priority user group creation workflow (Name and describe → Choose members → review-permission assignment), 10,000-member cap, `user principal name` CSV bulk-upload column, likelihood/severity scoring boost for priority-group members, reviewer-permission scoping to specific role groups/individuals - <https://learn.microsoft.com/purview/insider-risk-management-settings-priority-user-groups>
3. Configure advanced features in Defender for Endpoint - "Share endpoint alerts with Microsoft Compliance Center" (portal steps, no API) - <https://learn.microsoft.com/defender-endpoint/advanced-features#share-endpoint-alerts-with-microsoft-compliance-center>
4. Create and manage Insider Risk Management policies (template/name immutable after creation) - <https://learn.microsoft.com/purview/insider-risk-management-policies>
5. Assign permissions in Insider Risk Management - built-in role groups (Insider Risk Management, Insider Risk Management Analysts, Insider Risk Management Investigators, Insider Risk Management Admins) - <https://learn.microsoft.com/purview/insider-risk-management-permissions>
6. Limits in Insider Risk Management - maximum users in scope per policy template (1,000 for "Security policy violations", identical to "…by priority users"; 15,000 for "…by departing users"; 7,500 for "…by risky users") - <https://learn.microsoft.com/purview/insider-risk-management-limits#maximum-number-of-users-in-scope-for-a-policy-template>
7. Learn about Insider Risk Management - Scenarios ("Intentional or unintentional security policy violations (preview)") and Configure policy indicators - Microsoft Defender for Endpoint indicators (preview) - <https://learn.microsoft.com/purview/insider-risk-management#scenarios>, <https://learn.microsoft.com/purview/insider-risk-management-settings-policy-indicators#built-in-indicators-vs-custom-indicators>
8. List group transitive members - OData cast (`/transitiveMembers/microsoft.graph.user`), required `ConsistencyLevel: eventual` header, permissions (`GroupMember.Read.All` among the higher-privileged options) - <https://learn.microsoft.com/graph/api/group-list-transitivemembers?view=graph-rest-1.0>
9. Get-MgGroupTransitiveMemberAsUser (PowerShell cmdlet reference, `Microsoft.Graph.Groups` module, output type `IMicrosoftGraphUser`) - <https://learn.microsoft.com/powershell/module/microsoft.graph.groups/get-mggrouptransitivememberasuser>
10. alert resource type - `alertPolicyId`, `incidentId`, `detectionSource` properties - <https://learn.microsoft.com/graph/api/resources/security-alert>
11. Microsoft Graph permissions reference (`GroupMember.Read.All`, `SecurityAlert.Read.All`) - <https://learn.microsoft.com/graph/permissions-reference>
12. *Security Policy Violations (base template)* and *Security Policy Violations by Departing Users* - this template family's base and departing-users siblings, whose already-grounded facts (1,000-user cap citation, alert-export script, Defender for Endpoint advanced-feature toggle) this scenario reuses and cross-references rather than re-verifying independently.
13. Get started with Insider Risk Management - Step 4 ("A priority user group is required when using the following policy templates: Security policy violations by priority users, Data leaks by priority users") and Step 6 ("**Add or edit priority user groups**. This option appears only if you choose the *Data leaks by priority users* template"; Risk score boosters instruction tied to selecting "at least one Office or Device indicator") - <https://learn.microsoft.com/purview/insider-risk-management-configure#step-4-recommended-configure-prerequisites-for-policies>, <https://learn.microsoft.com/purview/insider-risk-management-configure#step-6-required-create-an-insider-risk-management-policy>
14. Learn about Insider Risk Management policy templates - Policy template limits ("These maximum limits apply to users across all policies using a given policy template") and Configure policy indicators - Risk score boosters ("User is a member of a priority user group: Scores are boosted if the user is a member of a priority user group," documented generically, not scoped to one template) - <https://learn.microsoft.com/purview/insider-risk-management-policy-templates#policy-template-limits>, <https://learn.microsoft.com/purview/insider-risk-management-settings-policy-indicators#built-in-indicators-vs-custom-indicators>

> Re-verify all links, cmdlet/API behavior, and licensing terms against current Microsoft Learn
> before a customer-facing assessment or sale - this template family is explicitly Microsoft-
> labeled preview and could change materially before reaching general availability. This build's
> original grounding pass could not directly fetch learn.microsoft.com pages (proxy-blocked);
> those citations were grounded via web search of the same official Microsoft Learn URLs and,
> where noted inline, corroborated by independent secondary sources rather than a verbatim
> primary-source fetch. A later re-verification fragment ( "DONE") *did* have
> direct Microsoft Learn fetch access and used it to add references 13-14 above, which corrected
> this file's earlier, inaccurate claim that the 1,000-actively-scored cap is shared with the base
> template (it is not - the configuration reference and the cost and licensing notes) and sharpened two open VERIFY items with
> verbatim-quoted Microsoft text rather than resolving them by assumption. Re-verify directly
> against the live pages before a customer-facing commitment regardless of citation source.