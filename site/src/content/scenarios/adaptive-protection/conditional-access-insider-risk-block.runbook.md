---
part: "runbook"
parent: "adaptive-protection/conditional-access-insider-risk-block"
---
## Implementation steps

This scenario is **portal-first for Adaptive Protection enablement** (identical to the DLP
sibling - not repeated in code here) and **script-first for the Conditional Access policy
itself**, the one piece with a genuinely scriptable, independently-grounded Graph API surface.

### Step 1 - Confirm (or deploy) a feeder Insider Risk Management policy

Same as *Dynamic Risk-Based DLP Enforcement* (the implementation steps) Step 1 - use this library's own
*Departing Employee Data Theft*, or Microsoft's built-in **Data leaks**
template. Not created by this scenario.

### Step 2 - Assign permissions

Purview portal → **Settings** → **Roles and groups** → **Role groups** → add administrators who
will configure Adaptive Protection to **Insider Risk Management** or **Insider Risk Management
Admins**. Separately, in the **Microsoft Entra admin center**, assign administrators who will
create/manage this scenario's Conditional Access policy the **Conditional Access Administrator**
role - a distinct admin surface from every Purview role group above
([RBAC model, section 10](/docs/rbac-model/#10-microsoft-entra-conditional-access---a-sixth-system-for-identity-layer-scenarios)).

### Step 3 - Configure insider risk levels (portal, not scriptable)

Identical to *Dynamic Risk-Based DLP Enforcement* (the implementation steps) Step 3. Both scenarios read the same
tenant-wide insider risk level definitions - configure them once, not per scenario.

### Step 4 - Turn on Adaptive Protection (portal, not scriptable)

Identical to *Dynamic Risk-Based DLP Enforcement* (the implementation steps) Step 5. Allow up to **36 hours**
 before expecting risk levels to be assigned and this scenario's Conditional
Access policy to actually match a user - see the known limitations.

### Step 5 - Identify and exclude break-glass/emergency-access accounts

Before deploying, identify (or create, per Microsoft's documented pattern) a
dedicated **emergency-access** security group, or list the individual break-glass account object
IDs. Note their object ID(s)/group ID(s) - needed for Step 6.

### Step 6 - Deploy the Conditional Access policy (scripted, dry-run capable)

```powershell
Connect-MgGraph -ClientId $AppId -TenantId $TenantId -CertificateThumbprint $Thumbprint

# Dry run - shows exactly what would be created, changes nothing
./deploy/New-InsiderRiskConditionalAccessPolicy.ps1 -ExcludeGroupIds $EmergencyAccessGroupId -WhatIf

# Deploy in Report-only mode (Microsoft's own documented default posture)
./deploy/New-InsiderRiskConditionalAccessPolicy.ps1 -ExcludeGroupIds $EmergencyAccessGroupId
```

This creates one Conditional Access policy scoped to all applications, all users except the
excluded break-glass group, with the `insiderRiskLevels = ['elevated']` condition and a `block`
grant control (the configuration reference for the exact configuration) - in Report-only state.

### Step 7 - Pilot, then enforce

**Before enabling enforcement, confirm the feeder IRM policy has already completed at least one
full baseline/tuning cycle** - the same recommendation *Dynamic Risk-Based DLP Enforcement* (the implementation steps) Step 6 makes, and for the identical reason: compounding an untuned detector with an automated
*block-everything* response multiplies business-impact risk. Review the policy's Report-only
results in **Entra admin center** → **Conditional Access** → **Insights and reporting** for at
least the propagation window in section 11 before promoting. Once satisfied:

```powershell
./deploy/New-InsiderRiskConditionalAccessPolicy.ps1 -ExcludeGroupIds $EmergencyAccessGroupId -Mode Enabled -Force
```

### Step 8 - Validate

```powershell
./validate/Test-InsiderRiskConditionalAccessPolicy.ps1 -ExpectedState enabled
```

## Configuration reference

| Setting | Value this scenario uses | Notes |
|---|---|---|
| Policy name | `Adaptive Protection - Block Elevated Insider Risk (Custom)` | Deliberately distinct from Microsoft's Quick-Setup-generated name - see the known limitations |
| Target resources | `includeApplications = ['All']` | Matches Microsoft's own documented "All resources" step |
| Users | `includeUsers = ['All']` minus `-ExcludeUserIds`/`-ExcludeGroupIds`/`-ExcludeGuestOrExternalUserTypes` | Excludes break-glass accounts/group **and**, by default, `b2bDirectConnectUser`/`serviceProvider`/`otherExternalUser` guest/external categories - Microsoft's own documented Users-step exclusion, now scripted (`conditions.users.excludeGuestsOrExternalUsers.guestOrExternalUserTypes`) - see the known limitations for the wire-format grounding |
| Insider Risk condition | `insiderRiskLevels = ['elevated']` (default) | Configurable via `-RiskLevels`; adding `moderate`/`minor` applies the **same** block control to those levels too - see section 6 note in the design notes |
| Grant control | `builtInControls = ['block']`, `operator = 'OR'` | Matches Microsoft's documented "Block access" choice |
| Initial policy state | `enabledForReportingButNotEnforced` (Report-only) | Matches Microsoft's own documented Step 7 |
| Break-glass exclusion | Not enabled by default - must be supplied via `-ExcludeUserIds`/`-ExcludeGroupIds` | The deploy script **warns** (does not refuse) if both are empty while `-Mode Enabled` - see the known limitations |

## Operations and tuning

**KPIs to watch (first 90 days):** the same Adaptive Protection dashboard KPIs
*Dynamic Risk-Based DLP Enforcement* (operations and tuning) documents apply identically here (risk-level
assignment counts, false-positive rate, detection-to-enforcement latency, risk-level reset rate)
- review both scenarios' enforcement outcomes together, since they share the same upstream risk
signal.

**Tuning:** as with the DLP sibling, tune the *insider risk level conditions* in Adaptive
Protection settings if too many/few users are receiving a level - not this scenario's Conditional
Access policy, which should stay matched to Microsoft's own documented reference configuration
unless there's a specific, documented reason to diverge.

**Incident-response runbook (block event):**
1. **Triage** - the blocked user sees Entra's standard access-denied page; the sign-in appears in
   **Entra sign-in logs**, flagged with this policy's name under **Conditional Access**. There is
   no separate Purview-side alert for this specific block - cross-reference via the sign-in log,
   not the DLP Alerts dashboard.
2. **Cross-reference the feeder IRM policy's alert** - same manual-correlation caveat the DLP
   sibling's runbook documents: no shared correlation ID links a Conditional Access sign-in block
   to the specific IRM alert that produced the triggering risk level. Match by user and
   timestamp.
3. **Classify and resolve** - identical logic to the DLP sibling's runbook: if the underlying IRM
   alert is a false positive, resolving/dismissing it resets the user's risk level, which lifts
   the Conditional Access block automatically on the next sign-in evaluation - no manual
   Conditional Access exception needed.

**Review cadence:** quarterly, alongside the DLP sibling and the feeder IRM policy, using the
same KPIs.

**A blocked sign-in is a bigger business-continuity event than a blocked share.** Coordinate with
HR/Legal *and* IT service desk before broad enforcement-mode rollout - a user who cannot sign in
at all will call the help desk immediately, unlike a DLP-blocked share that may go unnoticed for
longer. Treat enabling `-Mode Enabled` org-wide as a change requiring service-desk runbook
readiness (the validation steps lists what they'll see), not only an HR/Legal-notified change. This is a residual
consideration for CISO sign-off - see the CISO review.

## Rollback and decommission

See the rollback runbook for the full staged procedure (disable → Report-only → permanent removal).
Quick reference: `./deploy/Remove-InsiderRiskConditionalAccessPolicy.ps1` disables the policy
(reversible in seconds); `-ReportOnly` steps back to reporting-only; `-Purge` permanently deletes
it. None of these actions disable Adaptive Protection itself, the feeder IRM policy, or reset any
user's current insider risk level.

## References

1. Block access for users with elevated insider risk (the exact portal procedure - Users/Target
   resources/Insider Risk condition/Grant/Report-only sequence - this scenario's deploy script
   automates) - <https://learn.microsoft.com/entra/identity/conditional-access/policy-risk-based-insider-block>
2. Protect your tenant with Insider Risk in Conditional Access (Microsoft Entra ID P2 licensing
   requirement; Insider Risk Management/Insider Risk Management Admins + Conditional Access
   Administrator role prerequisites) - <https://learn.microsoft.com/entra/identity/monitoring-health/recommendation-insider-risk-condition>
3. conditionalAccessConditionSet resource type (`insiderRiskLevels` property, Graph v1.0, values
   minor/moderate/elevated/unknownFutureValue) - <https://learn.microsoft.com/graph/api/resources/conditionalaccessconditionset>
4. conditionalAccessPolicy resource type (`state` property: enabled/disabled/
   enabledForReportingButNotEnforced) - <https://learn.microsoft.com/graph/api/resources/conditionalaccesspolicy>
5. Create / Update conditionalAccessPolicy (least-privileged permission
   `Policy.ReadWrite.ConditionalAccess` + `Policy.Read.All`) - <https://learn.microsoft.com/graph/api/conditionalaccessroot-post-policies>, <https://learn.microsoft.com/graph/api/conditionalaccesspolicy-update>
6. Help dynamically mitigate risks with Adaptive Protection (36-hour propagation delay,
   insider risk levels) - <https://learn.microsoft.com/purview/insider-risk-management-adaptive-protection>
7. Manage emergency access (break-glass) accounts - <https://learn.microsoft.com/entra/identity/role-based-access-control/security-emergency-access>
8. New- / Update- / Get- / Remove-MgIdentityConditionalAccessPolicy (Microsoft.Graph.Identity.SignIns
   module) - <https://learn.microsoft.com/powershell/module/microsoft.graph.identity.signins/new-mgidentityconditionalaccesspolicy>, <https://learn.microsoft.com/powershell/module/microsoft.graph.identity.signins/update-mgidentityconditionalaccesspolicy>, <https://learn.microsoft.com/powershell/module/microsoft.graph.identity.signins/get-mgidentityconditionalaccesspolicy>, <https://learn.microsoft.com/powershell/module/microsoft.graph.identity.signins/remove-mgidentityconditionalaccesspolicy>
9. [Licensing matrix, section 8](/docs/licensing-matrix/#8-adjacent-product-family-microsoft-entra-id-p2-conditional-access-risk-based-conditions) - Entra ID P2 (Conditional Access risk-based conditions), new in
   this build.
10. [RBAC model, section 10](/docs/rbac-model/#10-microsoft-entra-conditional-access---a-sixth-system-for-identity-layer-scenarios) - Microsoft Entra Conditional Access (a sixth RBAC system), new in
    this build.
11. *Dynamic Risk-Based DLP Enforcement* - the DLP sibling scenario this
    fragment complements; see the design notes for how the two differ.
12. conditionalAccessUsers / conditionalAccessGuestsOrExternalUsers resource types
    (`excludeGuestsOrExternalUsers.guestOrExternalUserTypes`/`externalTenants` properties this
    build's `-ExcludeGuestOrExternalUserTypes` parameter scripts) - <https://learn.microsoft.com/graph/api/resources/conditionalaccessusers>, <https://learn.microsoft.com/graph/api/resources/conditionalaccessguestsorexternalusers>
13. conditionalAccessGuestOrExternalUserTypes enum reference (the seven real, client-settable
    values: `internalGuest`/`b2bCollaborationGuest`/`b2bCollaborationMember`/
    `b2bDirectConnectUser`/`otherExternalUser`/`serviceProvider`, plus the server-only
    `unknownFutureValue`) - <https://learn.microsoft.com/graph/api/resources/enums#conditionalaccessguestorexternalusertypes-values>
14. cloudLicensing subscription / service resource types and conditionalAccessEnumeratedExternalTenants
    resource type (grounding for the `guestOrExternalUserTypes` multi-value separator VERIFY closed
    2026-09-27 - see the known limitations) - <https://learn.microsoft.com/graph/api/resources/cloudlicensing-subscription>, <https://learn.microsoft.com/graph/api/resources/cloudlicensing-service>, <https://learn.microsoft.com/graph/api/resources/conditionalaccessenumeratedexternaltenants>

> Re-verify all links, API behavior, and licensing terms against current Microsoft Learn before a
> customer-facing assessment or sale - Adaptive Protection and its Conditional Access integration
> are comparatively new capabilities that change faster than most in the Purview portfolio.