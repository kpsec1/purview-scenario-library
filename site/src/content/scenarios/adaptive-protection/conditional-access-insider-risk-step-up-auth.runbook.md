---
part: "runbook"
parent: "adaptive-protection/conditional-access-insider-risk-step-up-auth"
---
## Implementation steps

### Step 1 - Confirm (or deploy) a feeder Insider Risk Management policy

Same as both siblings - use *Departing Employee Data Theft*, or
Microsoft's built-in **Data leaks** template.

### Step 2 - Assign permissions

Same Purview role-group and **Conditional Access Administrator** assignment as the Elevated
sibling (the implementation steps Step 2 there).

### Step 3 - Confirm insider risk levels and Adaptive Protection are enabled (portal, not scriptable)

Identical to both siblings - configure once tenant-wide, not per scenario.

### Step 4 - Create the Terms of Use agreement (portal, or one-time delegated-auth - not this scenario's app-only script)

This is the one step this scenario's automation genuinely cannot perform end-to-end - create
it once, manually or via a separate interactive session:

1. Prepare a PDF document stating the security/privacy commitments you want Moderate-risk users to
   acknowledge.
2. **Entra admin center** → **Conditional Access** → **Terms of use** → **New terms**. Upload the
   PDF, set a display name and default language, and for **Enforce with Conditional Access policy
   templates**, select **Custom policy** so no policy is auto-created - this scenario's own script
   creates the policy in the next step.
3. Note the agreement's `Id` (find it later with
   `Get-MgIdentityGovernanceTermsOfUseAgreement | Select-Object DisplayName, Id` if needed).

### Step 5 - Identify and exclude break-glass/emergency-access accounts

Same as both siblings - note object ID(s)/group ID(s) for Step 6.

### Step 6 - Deploy both policies (scripted, dry-run capable)

```powershell
Connect-MgGraph -ClientId $AppId -TenantId $TenantId -CertificateThumbprint $Thumbprint

# Dry run - shows exactly what would be created, changes nothing
./deploy/New-InsiderRiskStepUpPolicies.ps1 -AgreementId $AgreementId -ExcludeGroupIds $EmergencyAccessGroupId -WhatIf

# Deploy both in their default posture: Moderate in Report-only, Minor permanently Report-only
./deploy/New-InsiderRiskStepUpPolicies.ps1 -AgreementId $AgreementId -ExcludeGroupIds $EmergencyAccessGroupId
```

No agreement created yet? Deploy only the Minor policy this run:

```powershell
./deploy/New-InsiderRiskStepUpPolicies.ps1 -SkipModeratePolicy -ExcludeGroupIds $EmergencyAccessGroupId
```

### Step 7 - Pilot, then promote the Moderate policy

Same baseline-cycle and pilot-review recommendation as both siblings. Review **Entra admin
center** → **Conditional Access** → **Insights and reporting** for both policies before promoting.
**The Minor policy is never promoted** - there is no `-Mode Enabled` option for it.
Once satisfied with the Moderate policy's Report-only results:

```powershell
./deploy/New-InsiderRiskStepUpPolicies.ps1 -AgreementId $AgreementId -ExcludeGroupIds $EmergencyAccessGroupId -ModerateMode Enabled -Force
```

### Step 8 - Validate

```powershell
./validate/Test-InsiderRiskStepUpPolicies.ps1 -ExpectedAgreementId $AgreementId -ExpectedModerateState enabled
```

## Configuration reference

| Setting | Moderate policy | Minor policy |
|---|---|---|
| Policy name | `Adaptive Protection - Require Terms of Use for Moderate Insider Risk (Custom)` | `Adaptive Protection - Insights for Minor Insider Risk (Custom)` |
| Target resources | `includeApplications = ['MicrosoftAdminPortals']` - matches Microsoft's own worked example exactly | `includeApplications = ['All']` - broad visibility, matching the intent of Microsoft's referenced Insights and reporting workbook |
| Users | `includeUsers = ['All']` minus `-ExcludeUserIds`/`-ExcludeGroupIds` | Same |
| Insider Risk condition | `insiderRiskLevels = ['moderate']` (default; configurable via `-ModerateRiskLevels`) | `insiderRiskLevels = ['minor']` (default; configurable via `-MinorRiskLevels`) |
| Grant control | `grantControls.termsOfUse = [<AgreementId>]`, `operator = 'OR'` - matches Microsoft's documented "select the terms of use" grant choice | `grantControls.builtInControls = ['mfa']`, `operator = 'OR'` - **a disclosed payload-shape choice, not a Microsoft recommendation**; Microsoft names no control for Minor risk. Deliberately `mfa`, not the Elevated sibling's `block`, for its fail-safe profile if this policy's state is ever changed outside this scenario's scripts. Never evaluated in an enforcing state - see next row. |
| Initial / achievable policy states | `-ModerateMode`: `ReportOnly` (default), `Enabled`, or `Disabled` | `-MinorMode`: `ReportOnly` (default) or `Disabled` **only** - `Enabled` is not a valid value; there is no enforcement path for this policy by design |
| Break-glass exclusion | Not enabled by default - supply via `-ExcludeUserIds`/`-ExcludeGroupIds` | Same, shared across both policies |
| Agreement creation | **Out of scope for this script** - pass an existing agreement's `-AgreementId` | N/A |

## Operations and tuning

**KPIs to watch (first 90 days):** the same Adaptive Protection dashboard KPIs the Elevated
the sibling scenario's operations and tuning documents apply here too - review all three Conditional Access policies'
(Elevated block, Moderate Terms of Use, Minor insights) outcomes together, since they share the
same upstream risk signal. Additionally for this scenario:

- **Terms of Use acceptance rate and time-to-accept** for the Moderate policy - a consistently low
  acceptance rate or long delay may indicate the prompt is being ignored/dismissed without being
  read, or that the population in scope is broader than intended.
- **Minor-risk sign-in volume trend** from the Minor policy's Report-only evaluation data - a
  leading indicator worth reviewing alongside (not instead of) the feeder IRM policy's own alert
  trend.

**Tuning:** as with both siblings, tune the *insider risk level conditions* in Adaptive Protection
settings if too many/few users receive a level - not these policies, which should stay matched to
Microsoft's own documented reference configuration unless there's a specific, documented reason to
diverge (the design notes documents how to substitute a different Moderate grant control if an organization
prefers one).

**Incident-response runbook (Moderate Terms of Use prompt event):**
1. **Triage** - the prompted user sees the Terms of Use dialog on next admin-portal sign-in; the
   sign-in appears in **Entra sign-in logs**, flagged with this policy's name. No separate
   Purview-side alert exists for this specific event - cross-reference by user and timestamp
   against the feeder IRM policy's own alert, same manual-correlation caveat both siblings
   document.
2. **Classify and resolve** - identical logic to both siblings: if the underlying IRM alert is a
   false positive, resolving/dismissing it resets the user's risk level, which stops this policy
   matching them on the next sign-in evaluation - no manual Conditional Access exception needed.
3. **A user who reports being unable to complete admin-portal sign-in** - check whether they
   declined the Terms of Use prompt rather than accepting it; a decline is not satisfied and
   sign-in does not complete, the same as any other unmet Conditional Access grant control. Re-attempting sign-in and accepting resolves it; this is expected behavior, not an outage.

**Minor policy requires no runbook** - it never prompts or blocks anyone; its only output is
Insights/reporting trend data, reviewed on the same quarterly cadence as everything else in this
scenario family.

**Review cadence:** quarterly, alongside both siblings and the feeder IRM policy, using the same
KPIs plus the two additions above.

## Rollback and decommission

See the rollback runbook for the full staged procedure. Quick reference:
`./deploy/Remove-InsiderRiskStepUpPolicies.ps1` disables both policies by default (reversible in
seconds); `-Policy Moderate` / `-Policy Minor` targets one; `-ReportOnly` steps back to reporting
only; `-Purge` permanently deletes. None of these actions delete the Terms of Use agreement object,
disable Adaptive Protection, the feeder IRM policy, or reset any user's current insider risk
level.

## References

1. Adaptive Protection configuration guide (the Elevated/Moderate/Minor Conditional Access pairing
   this scenario automates for Moderate and Minor) - <https://learn.microsoft.com/purview/insider-risk-management-adaptive-protection-guide>
2. Block access for users with insider risk (the Elevated sibling's own procedure, referenced for
   contrast) - <https://learn.microsoft.com/entra/identity/conditional-access/policy-risk-based-insider-block>
3. Require terms of use to be accepted before accessing Microsoft Admin Portals (the exact
   portal procedure this scenario's Moderate policy automates, including the P1 license
   prerequisite and agreement-creation steps) - <https://learn.microsoft.com/entra/identity/conditional-access/require-tou>
4. Set up Microsoft Entra terms of use with Conditional Access (general Terms of Use feature
   reference, P1 licensing, PDF-document prerequisite, 40-terms-per-tenant service limit) - <https://learn.microsoft.com/entra/identity/conditional-access/terms-of-use>
5. conditionalAccessConditionSet resource type (`insiderRiskLevels` property, Graph v1.0) - <https://learn.microsoft.com/graph/api/resources/conditionalaccessconditionset>
6. conditionalAccessGrantControls resource type (`termsOfUse`, `builtInControls`, `operator`
   properties) - <https://learn.microsoft.com/graph/api/resources/conditionalaccessgrantcontrols>
7. Help dynamically mitigate risks with Adaptive Protection (36-hour propagation delay) - <https://learn.microsoft.com/purview/insider-risk-management-adaptive-protection>
8. conditionalAccessApplications resource type (`MicrosoftAdminPortals`/`All` special
   includeApplications values) - <https://learn.microsoft.com/graph/api/resources/conditionalaccessapplications>
9. Create agreement (delegated-permission-only - "Application: Not supported" - the grounding for
   this scenario's central automation-gap disclosure) - <https://learn.microsoft.com/graph/api/termsofusecontainer-post-agreements>
10. agreement / agreementAcceptance resource types (Microsoft Entra ID Governance Terms of Use) - <https://learn.microsoft.com/graph/api/resources/agreement>
11. Create / Update conditionalAccessPolicy (least-privileged permission
    `Policy.ReadWrite.ConditionalAccess` + `Policy.Read.All`) - <https://learn.microsoft.com/graph/api/conditionalaccessroot-post-policies>, <https://learn.microsoft.com/graph/api/conditionalaccesspolicy-update>
12. Conditional Access Target resources: Microsoft Admin Portals (the four app IDs the grouping
    expands to) - <https://learn.microsoft.com/entra/identity/conditional-access/concept-conditional-access-cloud-apps#microsoft-admin-portals>
13. [Licensing matrix, section 8](/docs/licensing-matrix/#8-adjacent-product-family-microsoft-entra-id-p2-conditional-access-risk-based-conditions) - Entra ID P2 (Conditional Access risk-based conditions),
    updated in this build to reference both Conditional Access scenarios.
14. [RBAC model, section 10](/docs/rbac-model/#10-microsoft-entra-conditional-access---a-sixth-system-for-identity-layer-scenarios) - Microsoft Entra Conditional Access.
15. *Conditional Access Insider Risk Block* - the Elevated sibling
    scenario this fragment complements.
16. *Dynamic Risk-Based DLP Enforcement* - the DLP sibling scenario; see
    the design notes for how its own Moderate/Minor audit treatment differs from this scenario's.

> Re-verify all links, API behavior, and licensing terms against current Microsoft Learn before a
> customer-facing assessment or sale - Adaptive Protection and its Conditional Access integration
> are comparatively new capabilities that change faster than most in the Purview portfolio.