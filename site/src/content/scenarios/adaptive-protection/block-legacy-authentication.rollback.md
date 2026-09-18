---
part: "rollback"
parent: "adaptive-protection/block-legacy-authentication"
---
This scenario's own deployed artifact is a single **custom** Conditional Access policy
(`Block Legacy Authentication (Custom)`). Roll back in stages rather than deleting outright — a
live block policy affects real users' ability to sign in the moment it's disabled or re-enabled,
the same reasoning this library's other Conditional-Access-based scenarios' rollback docs apply.

**This procedure never touches a Microsoft-managed "Block legacy authentication" policy**, if your
tenant also has one — see "What rollback does not undo" below.

## Recommended sequence

### Stage 1 — Disable the policy (reversible, seconds)

```powershell
Connect-MgGraph -ClientId $AppId -TenantId $TenantId -CertificateThumbprint $Thumbprint
./deploy/Remove-BlockLegacyAuthenticationPolicy.ps1
```

This PATCHes the custom policy's `state` to `disabled` [[1]](#references). The policy object
remains defined (visible in **Entra admin center** → **Conditional Access** → **Policies**) but
stops evaluating sign-ins — no user is blocked or reported on by this policy while disabled.
Re-enable instantly by re-running `deploy/New-BlockLegacyAuthenticationPolicy.ps1 -Mode Enabled
-Force -SkipManagedPolicyCheck` (or `-Mode ReportOnly -Force -SkipManagedPolicyCheck` to go back to
reporting only) — `-SkipManagedPolicyCheck` is needed here because this is a re-deploy of an
already-decided custom policy, not a fresh first-time check.

Use this stage for: a legitimate legacy-auth-dependent device/client discovered only after
enforcement, a change freeze, or suspicion that this policy is disrupting access while you
investigate.

### Stage 2 — Step back to Report-only (partial rollback, keeps visibility)

If a full disable is too blunt (you still want to know who *would* be blocked):

```powershell
./deploy/Remove-BlockLegacyAuthenticationPolicy.ps1 -ReportOnly
```

Nothing is blocked; the policy still evaluates sign-ins and logs matches to **Conditional Access
Insights and reporting**. This is the same state the deploy script defaults to on first run.

### Stage 3 — Permanent removal (not reversible)

```powershell
./deploy/Remove-BlockLegacyAuthenticationPolicy.ps1 -Purge
```

This calls `Remove-MgIdentityConditionalAccessPolicy`, which deletes the policy object entirely
[[2]](#references). There is no "undo" — re-establishing the control means re-running
`deploy/New-BlockLegacyAuthenticationPolicy.ps1` from scratch. Only do this when the control is
being permanently retired (e.g. because a Microsoft-managed equivalent has since appeared and
fully supersedes it — confirm with `validate/Test-BlockLegacyAuthenticationPolicy.ps1` first).

## What rollback does **not** undo

- **A Microsoft-managed "Block legacy authentication" policy, if the tenant has one.** This
  scenario's scripts never create, modify, disable, or delete a Microsoft-managed policy —
  Microsoft's own documentation states organizations can't rename or delete one at all. If your
  tenant relies on the Microsoft-managed policy rather than (or in addition to) this scenario's
  custom policy, manage it directly in the **Microsoft Entra admin center**: exclude accounts, or
  change its state to **Off**. Rolling back this scenario's own custom policy has zero effect on
  it.
- **Legacy authentication protocol behavior at the workload level** (e.g. Exchange Online's own
  authentication-policy mechanism, if separately configured) — a different, workload-specific
  control surface this scenario doesn't touch (`design.md` §7).
- **Sign-in log history.** Sign-ins already blocked or reported on by this policy remain in Entra
  sign-in logs per their own retention window, regardless of this policy's current state.
- **A session already blocked.** A sign-in attempt denied while the policy was enforcing was not
  granted; disabling the policy afterward does not retroactively grant it. The client must retry.

## Verification after rollback

```powershell
Connect-MgGraph -ClientId $AppId -TenantId $TenantId -CertificateThumbprint $Thumbprint
Get-MgIdentityConditionalAccessPolicy -All | Where-Object { $_.DisplayName -eq 'Block Legacy Authentication (Custom)' } | Select-Object DisplayName, State
```

Confirm `State` reports `disabled` or `enabledForReportingButNotEnforced` (Stage 1/2 outcome as
expected), or that the command returns nothing (Stage 3 — policy deleted). Then run
`validate/Test-BlockLegacyAuthenticationPolicy.ps1` to confirm whether a Microsoft-managed policy
is still (or newly) covering this control after this scenario's custom policy is rolled back.

## References

1. Update conditionalAccessPolicy — <https://learn.microsoft.com/graph/api/conditionalaccesspolicy-update>
2. Remove-MgIdentityConditionalAccessPolicy — <https://learn.microsoft.com/powershell/module/microsoft.graph.identity.signins/remove-mgidentityconditionalaccesspolicy>
3. Microsoft-managed Conditional Access policies (organizations can't rename or delete a
   Microsoft-managed policy) — <https://learn.microsoft.com/entra/identity/conditional-access/managed-policies>
