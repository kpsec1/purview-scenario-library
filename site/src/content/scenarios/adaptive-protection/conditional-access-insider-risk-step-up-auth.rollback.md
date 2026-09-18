---
part: "rollback"
parent: "adaptive-protection/conditional-access-insider-risk-step-up-auth"
---
This scenario's own deployed artifacts are two Conditional Access policies (Moderate/Terms of Use,
Minor/insights). Roll back in stages rather than deleting outright, for the same reasoning both
sibling scenarios' own `rollback.md` files apply, though the blast radius here is lower than the
Elevated sibling's block policy: neither policy this scenario deploys can lock a user out of
Microsoft 365 entirely.

## Recommended sequence

### Stage 1, Disable one or both policies (reversible, seconds)

```powershell
Connect-MgGraph -ClientId $AppId -TenantId $TenantId -CertificateThumbprint $Thumbprint

# Both policies (default)
./deploy/Remove-InsiderRiskStepUpPolicies.ps1

# Only the Moderate (Terms of Use) policy
./deploy/Remove-InsiderRiskStepUpPolicies.ps1 -Policy Moderate

# Only the Minor (insights) policy
./deploy/Remove-InsiderRiskStepUpPolicies.ps1 -Policy Minor
```

This PATCHes the selected policy/policies' `state` to `disabled` [[1]](#references). The policy
object(s) remain defined (visible in **Entra admin center** → **Conditional Access** →
**Policies**) but stop evaluating sign-ins. Re-enable instantly by re-running
`deploy/New-InsiderRiskStepUpPolicies.ps1` with the appropriate `-ModerateMode`/`-MinorMode` and
`-Force`.

Use this stage for: a Terms of Use prompt disrupting a real workflow unexpectedly, a change
freeze, or investigating whether either policy is affecting a specific user's legitimate access.

### Stage 2, Step back to Report-only (partial rollback, keeps visibility)

```powershell
./deploy/Remove-InsiderRiskStepUpPolicies.ps1 -ReportOnly
```

Nothing is prompted or blocked; both policies still evaluate sign-ins and log matches to
**Conditional Access Insights and reporting**. This is the Minor policy's permanent, only-ever
state, and the Moderate policy's default state on first deploy.

### Stage 3, Permanent removal (not reversible)

```powershell
./deploy/Remove-InsiderRiskStepUpPolicies.ps1 -Purge
```

This calls `Remove-MgIdentityConditionalAccessPolicy` for each selected policy, which deletes the
policy object entirely [[2]](#references). There is no "undo", re-establishing the control means
re-running `deploy/New-InsiderRiskStepUpPolicies.ps1` from scratch. **The Terms of Use agreement
object itself is not deleted by this stage**, it is a separate object this scenario's scripts
never created or own (see `README.md` §11); delete it separately in the portal if it's no longer
needed for any purpose.

## What rollback does **not** undo

- **Adaptive Protection itself, or insider risk level definitions.** Identical to both siblings.
- **The feeder Insider Risk Management policy.** Not created or managed by this scenario.
- **A user's current insider risk level.** Disabling or deleting either policy does not reset any
  user's Elevated/Moderate/Minor assignment.
- **The Terms of Use agreement object.** Never created, owned, or deleted by this scenario's
  scripts, a separate Microsoft Entra ID Governance object (§5 Step 4). Deleting it independently
  (outside this scenario) would also remove the Moderate policy's grant control reference; do not
  delete the agreement while the Moderate policy is still enabled without first rolling back the
  policy.
- **Terms of Use acceptance records.** A user's prior acceptance of the agreement (tracked as a
  Graph `agreementAcceptance` object) is unaffected by rolling back this scenario's policies.
- **Either sibling scenario's own policy or rules**, if also deployed. All three Conditional
  Access policies (Elevated block, Moderate Terms of Use, Minor insights) and the DLP sibling's
  rules are independent, rolling back one has no effect on the others.
- **Sign-in log history.** Retained per its own retention window regardless of policy state.

## Verification after rollback

```powershell
Connect-MgGraph -ClientId $AppId -TenantId $TenantId -CertificateThumbprint $Thumbprint
Get-MgIdentityConditionalAccessPolicy -All | Where-Object {
    $_.DisplayName -in @(
        'Adaptive Protection - Require Terms of Use for Moderate Insider Risk (Custom)',
        'Adaptive Protection - Insights for Minor Insider Risk (Custom)'
    )
} | Select-Object DisplayName, State
```

Confirm `State` reports `disabled` or `enabledForReportingButNotEnforced` (Stage 1/2 outcome as
expected), or that a purged policy's row is simply absent (Stage 3).

## References

1. Update conditionalAccessPolicy, <https://learn.microsoft.com/graph/api/conditionalaccesspolicy-update>
2. Remove-MgIdentityConditionalAccessPolicy, <https://learn.microsoft.com/powershell/module/microsoft.graph.identity.signins/remove-mgidentityconditionalaccesspolicy>
