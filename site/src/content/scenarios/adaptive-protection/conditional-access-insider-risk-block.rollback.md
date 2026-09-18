---
part: "rollback"
parent: "adaptive-protection/conditional-access-insider-risk-block"
---
This scenario's own deployed artifact is a single Conditional Access policy. Roll back in
stages rather than deleting outright, a live block policy affects real users' ability to sign
in to Microsoft 365 the moment it's disabled or re-enabled, the same reasoning
`dynamic-risk-dlp-enforcement/rollback.md` applies to its DLP policy.

## Recommended sequence

### Stage 1, Disable the policy (reversible, seconds)

```powershell
Connect-MgGraph -ClientId $AppId -TenantId $TenantId -CertificateThumbprint $Thumbprint
./deploy/Remove-InsiderRiskConditionalAccessPolicy.ps1
```

This PATCHes the policy's `state` to `disabled` [[1]](#references). The policy object remains
defined (visible in **Entra admin center** → **Conditional Access** → **Policies**) but stops
evaluating sign-ins, no user is blocked or reported on by this policy while disabled.
Re-enable instantly by re-running `deploy/New-InsiderRiskConditionalAccessPolicy.ps1
-Mode Enabled -Force` (or `-Mode ReportOnly -Force` to go back to reporting only).

Use this stage for: a false-positive incident locking out a real employee, a change freeze, or
suspicion that this policy is disrupting a specific user's legitimate access while you
investigate.

### Stage 2, Step back to Report-only (partial rollback, keeps visibility)

If a full disable is too blunt (you still want to know who *would* be blocked):

```powershell
./deploy/Remove-InsiderRiskConditionalAccessPolicy.ps1 -ReportOnly
```

Nothing is blocked; the policy still evaluates sign-ins and logs matches to **Conditional Access
Insights and reporting**. This is the same state the deploy script defaults to on first run.

### Stage 3, Permanent removal (not reversible)

```powershell
./deploy/Remove-InsiderRiskConditionalAccessPolicy.ps1 -Purge
```

This calls `Remove-MgIdentityConditionalAccessPolicy`, which deletes the policy object entirely
[[2]](#references). There is no "undo", re-establishing the control means re-running
`deploy/New-InsiderRiskConditionalAccessPolicy.ps1` from scratch. Only do this when the control
is being permanently retired.

## What rollback does **not** undo

- **Adaptive Protection itself, or insider risk level definitions.** Identical to the DLP
  sibling's rollback, rolling back this policy has no effect on whether Adaptive Protection is
  turned on or how Elevated/Moderate/Minor are defined.
- **The feeder Insider Risk Management policy.** Not created or managed by this scenario.
- **A user's current insider risk level.** Disabling or deleting this policy does not reset any
  user's Elevated/Moderate/Minor assignment, computed and owned entirely by the Adaptive
  Protection/Insider Risk Management service.
- **This scenario's DLP sibling policy**, if also deployed. The two are independent, rolling
  back one has no effect on the other.
- **Sign-in log history.** Sign-ins already blocked or reported on by this policy remain in Entra
  sign-in logs per their own retention window, regardless of this policy's current state.
- **A session already blocked.** A sign-in attempt denied while the policy was enforcing was not
  granted; disabling the policy afterward does not retroactively grant it. The user must retry.

## Verification after rollback

```powershell
Connect-MgGraph -ClientId $AppId -TenantId $TenantId -CertificateThumbprint $Thumbprint
Get-MgIdentityConditionalAccessPolicy -All | Where-Object { $_.DisplayName -eq 'Adaptive Protection - Block Elevated Insider Risk (Custom)' } | Select-Object DisplayName, State
```

Confirm `State` reports `disabled` or `enabledForReportingButNotEnforced` (Stage 1/2 outcome as
expected), or that the command returns nothing (Stage 3, policy deleted).

## References

1. Update conditionalAccessPolicy, <https://learn.microsoft.com/graph/api/conditionalaccesspolicy-update>
2. Remove-MgIdentityConditionalAccessPolicy, <https://learn.microsoft.com/powershell/module/microsoft.graph.identity.signins/remove-mgidentityconditionalaccesspolicy>
