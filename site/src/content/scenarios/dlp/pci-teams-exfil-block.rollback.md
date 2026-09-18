---
part: "rollback"
parent: "dlp/pci-teams-exfil-block"
---
## Recommended sequence

DLP policy changes affect live user traffic, so roll back in stages rather than deleting outright.

### Stage 1, Disable (reversible, seconds)

```powershell
Connect-IPPSSession -AppId $AppId -Certificate $Cert -Organization $TenantDomain
./deploy/Remove-PciTeamsDlpPolicy.ps1
```

This runs `Set-DlpCompliancePolicy -Identity "PCI DSS - Teams Card Data Exfiltration Block" -Mode Disable`.
The policy and its three rules remain defined (visible in the Purview portal under **Data loss
prevention > Policies**) but stop evaluating traffic. Re-enable instantly:

```powershell
Set-DlpCompliancePolicy -Identity "PCI DSS - Teams Card Data Exfiltration Block" -Mode Enable
```

Use this stage for: a false-positive incident that needs immediate relief while you tune the
policy, a change freeze, or a temporary business exception that doesn't warrant deleting the
control.

### Stage 2, Simulation (partial rollback, keeps visibility)

If a full disable is too blunt (you still want to know what *would* have been blocked), step
back to simulation instead of fully disabling:

```powershell
Set-DlpCompliancePolicy -Identity "PCI DSS - Teams Card Data Exfiltration Block" -Mode TestWithNotifications
```

Nothing is blocked; policy tips and alerts still fire. This is the same mode the deploy script
defaults to on first run.

### Stage 3, Permanent removal (not reversible)

```powershell
./deploy/Remove-PciTeamsDlpPolicy.ps1 -Purge
```

This runs `Remove-DlpCompliancePolicy`, which deletes the policy **and its rules** in one call
(Microsoft Learn: `remove-dlpcompliancepolicy`). There is no "undo", re-establishing the control
means re-running `deploy/New-PciTeamsDlpPolicy.ps1` from scratch. Only do this when the control
is being permanently retired (e.g., the tenant is exiting PCI scope, or the control is being
replaced by a successor policy with a different name).

## What rollback does **not** undo

- **Audit log / alert history.** Alerts already generated (DLP Alerts dashboard, Microsoft
 Defender portal incidents) are retained per their own retention windows (30 days in the DLP
 Alerts dashboard, 6 months in Microsoft Defender portal, see `README.md` §8) regardless of
 policy state.
- **Messages already blocked.** A message a user tried to send while the policy was enforcing was
 not delivered; disabling or removing the policy afterward does not retroactively deliver it.
 The sender must resend.
- **Card Operations group membership.** This scenario does not create or manage the
 `CardOpsGroupEmail` security group, it's a dependency, not a deployed artifact. Removing this
 policy has no effect on that group.

## Verification after rollback

Run the validation script and confirm it reports the policy `Mode` as `Disable` (Stage 1) or that
`Get-DlpCompliancePolicy -Identity "..."` returns nothing (Stage 3):

```powershell
Get-DlpCompliancePolicy -Identity "PCI DSS - Teams Card Data Exfiltration Block" | Select-Object Name, Mode
```
