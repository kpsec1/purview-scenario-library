---
part: "rollback"
parent: "dlp/defender-device-control-usb-allowlist-wpd-coverage"
---
## Recommended sequence

This fragment shares one Intune device configuration object with its parent scenario
([`dlp/defender-device-control-usb-allowlist`](/scenarios/dlp/defender-device-control-usb-allowlist/)). Rolling back means removing **only** the
WPD-specific delta, not the parent's own `RemovableMediaDevices` coverage.

### Stage 1 — Remove WPD coverage only (reversible, minutes)

```powershell
Connect-MgGraph -ClientId $AppId -TenantId $TenantId -CertificateThumbprint $Thumbprint
./deploy/Remove-WpdDeviceControlCoverage.ps1
```

This reverts `SecuredDevicesConfiguration` from `RemovableMediaDevices|WpdDevices` back to
`RemovableMediaDevices` alone, and removes the four WPD-specific `omaSettings` entries
(`ApprovedWpdDevices` group, `AllWpdDevices` catch-all group, `Allow-ApprovedWpdDevices` rule,
`Deny-AllOtherWpd` rule). The parent policy's object identity, assignment, and its own seven
`RemovableMediaDevices`-scoped settings are untouched — devices continue to be governed by the
parent's USB allowlist exactly as before this fragment was ever deployed.

**Important:** removing WPD coverage this way makes WPD devices **unrestricted again, not denied**
— per Microsoft's documented behavior, "when device types are configured, device control in
Defender for Endpoint ignores requests to other device families." A WPD device is invisible to the
policy after rollback, the same as it was before this fragment was ever deployed. Do not use this
as an emergency "block everything" containment step; if the goal is emergency containment, widen
the approved-WPD-devices allowlist restrictively or use the parent scenario's own tenant-wide
posture instead.

Re-add coverage instantly:

```powershell
./deploy/Add-WpdDeviceControlCoverage.ps1 -ConfigPath ./deploy/config/my-tenant.json
```

### Stage 2 — Narrow the approved-WPD-devices list (partial rollback)

If a specific approved WPD device needs to be removed from the allowlist but WPD coverage should
otherwise remain in force, edit the `approvedWpdDevices` list in the config file and re-run
`deploy/Add-WpdDeviceControlCoverage.ps1 -Force` — this reconciles the `ApprovedWpdDevices` group
to the new list without touching `SecuredDevicesConfiguration` or the catch-all/deny rule.

### Stage 3 — Remove the entire device control policy (not this fragment's rollback)

This fragment has no "Stage 3" of its own — there is only one shared policy object. To remove
device control entirely (both `RemovableMediaDevices` and `WpdDevices` coverage), use the parent
scenario's own rollback:

```powershell
./scenarios/dlp/defender-device-control-usb-allowlist/deploy/Remove-DeviceControlUsbAllowlistPolicy.ps1 -Purge
```

This permanently deletes the shared object, including this fragment's WPD entries — there is no
scenario where the parent is purged but WPD coverage survives.

## What rollback does **not** undo

- **Advanced Hunting / `DeviceEvents` history** for WPD-triggered events already generated —
  retained per its own retention window regardless of policy state, same as the parent scenario.
- **The parent policy's `RemovableMediaDevices` coverage, assignment, or object identity** — Stage
  1 of this rollback is scoped exclusively to the WPD delta.
- **Device onboarding/Intune enrollment, or the approved-WPD-devices' physical inventory** — this
  scenario does not manage either; they are dependencies, not deployed artifacts.

## Verification after rollback

```powershell
Connect-MgGraph -ClientId $AppId -TenantId $TenantId -CertificateThumbprint $Thumbprint
$policy = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/deviceManagement/deviceConfigurations?`$filter=displayName eq 'Device Control - USB Removable Media Default-Deny Allowlist'"
$full = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/deviceManagement/deviceConfigurations/$($policy.value[0].id)"

# Stage 1: confirm SecuredDevicesConfiguration no longer mentions WpdDevices, and exactly 7
# omaSettings entries remain
($full.omaSettings | Where-Object { $_.omaUri -like '*SecuredDevicesConfiguration*' }).value
$full.omaSettings.Count
```
