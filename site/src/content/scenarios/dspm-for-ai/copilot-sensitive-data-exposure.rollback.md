---
part: "rollback"
parent: "dspm-for-ai/copilot-sensitive-data-exposure"
---
## Recommended sequence

This scenario's DLP policy affects live Copilot traffic, so roll back in stages rather than
deleting outright. The DSPM for AI oversharing data risk assessment (README.md §5, §8) is not
deployed by this scenario (it is automatic and portal-only) and has nothing to roll back.

### Stage 1, Disable (reversible, seconds)

```powershell
Connect-IPPSSession -AppId $AppId -Certificate $Cert -Organization $TenantDomain
./deploy/Remove-CopilotSensitiveDataProtectionPolicy.ps1
```

This runs `Set-DlpCompliancePolicy -Identity "Copilot DLP - Sensitive Data Exposure Protection" -Mode Disable`.
The policy and its two rules remain defined (visible in the Purview portal under **Data loss
prevention > Policies**) but stop evaluating Copilot traffic. Re-enable instantly:

```powershell
Set-DlpCompliancePolicy -Identity "Copilot DLP - Sensitive Data Exposure Protection" -Mode Enable
```

Use this stage for: a false-positive incident needing immediate relief while tuning, a change
freeze, or a temporary business exception.

### Stage 2, Simulation (partial rollback, keeps visibility)

```powershell
Set-DlpCompliancePolicy -Identity "Copilot DLP - Sensitive Data Exposure Protection" -Mode TestWithNotifications
```

Nothing is blocked; alerts still fire. This is the same mode the deploy script defaults to on
first run.

### Stage 3, Permanent removal (not reversible)

```powershell
./deploy/Remove-CopilotSensitiveDataProtectionPolicy.ps1 -Purge
```

This runs `Remove-DlpCompliancePolicy`, which deletes the policy **and its two rules** in one call.
There is no undo, re-establishing the control means re-running
`deploy/New-CopilotSensitiveDataProtectionPolicy.ps1` from scratch. Only do this when the control
is being permanently retired (e.g., replaced by a successor policy, or by activating DSPM for AI's
one-click equivalent instead, see `design.md` §3a for why this scenario avoided that path in the
first place before choosing to switch to it).

## What rollback does **not** undo

- **Audit log / alert history.** Alerts already generated are retained per their own retention
  windows regardless of policy state.
- **Responses already blocked from web grounding or content processing.** A Copilot response that
  was already restricted while the policy was enforcing is not retroactively regenerated;
  disabling or removing the policy afterward only affects future prompts.
- **Sensitivity labels.** This scenario does not create or manage the `Confidential`/`Highly
  Confidential` labels it references, they are a dependency (see
  `scenarios/information-protection/auto-label-confidential-sharepoint/`), not a deployed artifact.
  Removing this policy has no effect on the labels or their own auto-labeling policies.
- **DSPM for AI oversharing assessment.** It is not created or scoped by this scenario at all; it
  keeps running automatically regardless of this policy's state.

## Verification after rollback

```powershell
Get-DlpCompliancePolicy -Identity "Copilot DLP - Sensitive Data Exposure Protection" | Select-Object Name, Mode
```

Confirm `Mode` reports `Disable` (Stage 1) or that the command returns nothing (Stage 3).
