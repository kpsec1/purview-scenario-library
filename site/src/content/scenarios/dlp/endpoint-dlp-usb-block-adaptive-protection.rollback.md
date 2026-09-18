---
part: "rollback"
parent: "dlp/endpoint-dlp-usb-block-adaptive-protection"
---
This scenario's own deployed artifact is a single Endpoint DLP policy — independent of the
Exchange/Teams sibling scenario's own policy and rollback procedure. Roll back in stages rather
than deleting outright, since a live block rule affects real users and devices the moment it's
disabled or re-enabled.

## Recommended sequence

### Stage 1 — Disable the DLP policy (reversible, seconds)

```powershell
Connect-IPPSSession -AppId $AppId -Certificate $Cert -Organization $TenantDomain
./deploy/Remove-AdaptiveProtectionDevicesDlpPolicy.ps1
```

This runs `Set-DlpCompliancePolicy -Identity "Adaptive Protection - Devices Endpoint DLP
(Custom)" -Mode Disable`. The policy and its two rules remain defined (visible in the Purview
portal under **Data loss prevention** → **Policies**) but stop evaluating device activity — no
user is blocked or audited by this scenario's rules while disabled. Re-enable instantly:

```powershell
Set-DlpCompliancePolicy -Identity "Adaptive Protection - Devices Endpoint DLP (Custom)" -Mode Enable
```

Use this stage for: a false-positive incident that needs immediate relief, a change freeze, or
suspicion that the Elevated-block rule is disrupting a specific user's legitimate device work
while you investigate.

### Stage 2 — Step back to simulation (partial rollback, keeps visibility)

If a full disable is too blunt (you still want to know what *would* have been blocked or
audited), step back to simulation instead:

```powershell
Set-DlpCompliancePolicy -Identity "Adaptive Protection - Devices Endpoint DLP (Custom)" -Mode TestWithNotifications
```

Nothing is blocked; audit entries still generate. This is the same mode the deploy script
defaults to on first run.

### Stage 3 — Permanent removal (not reversible)

```powershell
./deploy/Remove-AdaptiveProtectionDevicesDlpPolicy.ps1 -Purge
```

This runs `Remove-DlpCompliancePolicy`, which deletes the policy **and its two rules** in one
call [[1]](#references). There is no "undo" — re-establishing the control means re-running
`deploy/New-AdaptiveProtectionDevicesDlpPolicy.ps1` from scratch. Only do this when the control
is being permanently retired.

## What rollback does **not** undo

- **Adaptive Protection itself, insider risk level definitions, or the feeder IRM policy.**
  Identical to the Exchange/Teams sibling scenario's own rollback — see that scenario's
  `rollback.md` for the full portal-based procedure to fully disable Adaptive Protection, not
  repeated here.
- **The Exchange/Teams sibling scenario's own DLP policy.** Rolling back this scenario has no
  effect on [`adaptive-protection/dynamic-risk-dlp-enforcement`](/scenarios/adaptive-protection/dynamic-risk-dlp-enforcement/)'s policy — each rolls
  back independently via its own script.
- **[`dlp/endpoint-dlp-usb-block`](/scenarios/dlp/endpoint-dlp-usb-block/)'s own DLP policy**, if also deployed. A separate,
  always-on Devices policy with its own lifecycle.
- **Device onboarding or Advanced classification scanning and protection.** Both remain as
  configured after this scenario's policy is disabled or removed — they are shared,
  Devices-location-wide settings this scenario consumes but does not own.
- **A user's current insider risk level.** Computed entirely by the Adaptive
  Protection/Insider Risk Management service, independent of this policy's state.
- **Alert and incident-report history**, or content already blocked before rollback.

## Verification after rollback

```powershell
Get-DlpCompliancePolicy -Identity "Adaptive Protection - Devices Endpoint DLP (Custom)" | Select-Object Name, Mode
```

Confirm `Mode` reports `Disable` (Stage 1/2 outcome) or that the command returns nothing (Stage 3
— policy deleted).

## References

1. Remove-DlpCompliancePolicy reference — <https://learn.microsoft.com/powershell/module/exchangepowershell/remove-dlpcompliancepolicy>
2. `scenarios/adaptive-protection/dynamic-risk-dlp-enforcement/rollback.md` — the Exchange/Teams
   sibling's own rollback procedure, including the full Adaptive Protection portal-disable steps
   this document doesn't repeat.
