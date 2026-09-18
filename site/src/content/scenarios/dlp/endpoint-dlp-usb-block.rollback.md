---
part: "rollback"
parent: "dlp/endpoint-dlp-usb-block"
---
## Recommended sequence

Endpoint DLP policy changes affect live user activity on every onboarded device, so roll back in
stages rather than deleting outright.

### Stage 1 — Disable (reversible, seconds)

```powershell
Connect-IPPSSession -AppId $AppId -Certificate $Cert -Organization $TenantDomain
./deploy/Remove-EndpointDlpUsbBlockPolicy.ps1
```

This runs `Set-DlpCompliancePolicy -Identity "Endpoint DLP - Block USB Removable Media
Exfiltration" -Mode Disable`. The policy and its two rules remain defined (visible in the Purview
portal under **Data loss prevention > Policies**) but stop evaluating device activity. Re-enable
instantly:

```powershell
Set-DlpCompliancePolicy -Identity "Endpoint DLP - Block USB Removable Media Exfiltration" -Mode Enable
```

Use this stage for: a false-positive incident that needs immediate relief while you tune the
policy, a change freeze, or a temporary business exception that doesn't warrant deleting the
control.

### Stage 2 — Simulation (partial rollback, keeps visibility)

If a full disable is too blunt (you still want to know what *would* have been blocked), step back
to simulation instead of fully disabling:

```powershell
Set-DlpCompliancePolicy -Identity "Endpoint DLP - Block USB Removable Media Exfiltration" -Mode TestWithNotifications
```

Nothing is blocked; policy tips and alerts still fire. This is the same mode the deploy script
defaults to on first run.

### Stage 3 — Permanent removal (not reversible)

```powershell
./deploy/Remove-EndpointDlpUsbBlockPolicy.ps1 -Purge
```

This runs `Remove-DlpCompliancePolicy`, which deletes the policy **and its rules** in one call
(Microsoft Learn: `remove-dlpcompliancepolicy`). There is no "undo" — re-establishing the control
means re-running `deploy/New-EndpointDlpUsbBlockPolicy.ps1` from scratch. Only do this when the
control is being permanently retired or replaced by a successor policy with a different name.

## What rollback does **not** undo

- **Audit log / alert history.** Alerts already generated (DLP Alerts dashboard, Microsoft
  Defender portal incidents) are retained per their own retention windows regardless of policy
  state (`README.md` §8).
- **Files already copied or blocked.** A copy that was blocked while the policy was enforcing was
  not written to the removable drive; disabling or removing the policy afterward does not
  retroactively complete it. A copy that was audited (IT Data Custodians path) already completed —
  disabling the policy has no effect on data already on the device.
- **Device onboarding.** This scenario does not onboard or offboard devices — rollback here has no
  effect on whether a device remains onboarded to Endpoint DLP / Microsoft Defender for Endpoint.
- **IT Data Custodians group membership.** This scenario does not create or manage the
  `ITCustodiansGroupEmail` security group — it's a dependency, not a deployed artifact. Removing
  this policy has no effect on that group.

## Verification after rollback

Run the validation script and confirm it reports the policy `Mode` as `Disable` (Stage 1) or that
`Get-DlpCompliancePolicy -Identity "..."` returns nothing (Stage 3):

```powershell
Get-DlpCompliancePolicy -Identity "Endpoint DLP - Block USB Removable Media Exfiltration" | Select-Object Name, Mode
```
