---
part: "rollback"
parent: "dlp/defender-device-control-usb-allowlist-macos-portable-device-coverage"
---
## Recommended sequence

This fragment shares one `macOSCustomConfiguration` object with its parent scenario
(`scenarios/dlp/defender-device-control-usb-allowlist-macos/`). Rolling back means removing
**only** this fragment's delta (three feature flags, up to five groups, five rules), not the
parent's own `removableMedia` coverage.

### Stage 1, Remove Apple/Portable/Bluetooth coverage only (reversible, minutes)

```powershell
Connect-MgGraph -ClientId $AppId -TenantId $TenantId -CertificateThumbprint $Thumbprint
./deploy/Remove-MacPortableDeviceCoverage.ps1
```

This strips the `appleDevice`/`portableDevice`/`bluetoothDevice` feature-enable entries and this
fragment's groups/rules back out of the parent's embedded `deviceControl.policy` JSON, then
PATCHes the whole `.mobileconfig` payload. The parent policy's object identity, assignment, and
its own `removableMedia`-scoped coverage are untouched, devices continue to be governed by the
parent's USB allowlist exactly as before this fragment was ever deployed.

**Important:** removing this coverage makes Apple/Portable/Bluetooth devices **unrestricted again,
not denied**, per Microsoft's documented per-family enable model, a family whose `features.<name>
.disable` flag isn't set to `false` "doesn't apply" at all [[1]](#references). A previously-covered
device is invisible to the policy after rollback, the same as it was before this fragment was ever
deployed. Do not use this as an emergency "block everything" containment step; if the goal is
emergency containment, narrow the approved-device allowlists (or, for Bluetooth, there is nothing
to narrow, it is already unconditional deny) rather than rolling this fragment back.

Re-add coverage instantly:

```powershell
./deploy/Add-MacPortableDeviceCoverage.ps1 -ConfigPath ./deploy/config/my-tenant.json
```

### Stage 2, Narrow an approved-device list (partial rollback)

If a specific approved Apple or Portable device needs to be removed from its allowlist but
coverage for that family should otherwise remain in force, edit the `approvedAppleDevices`/
`approvedPortableDevices` list in the config file and re-run
`deploy/Add-MacPortableDeviceCoverage.ps1 -Force`, this reconciles the affected approved-device
group (and, if the list becomes empty, removes the allow rule entirely, reverting that family to
pure default-deny) without touching the other two families or the parent's own coverage. Bluetooth
has no allowlist to narrow (§11, `design.md` §5), it is already unconditional deny in this
fragment.

### Stage 3, Remove the entire device control policy (not this fragment's rollback)

This fragment has no "Stage 3" of its own, there is only one shared policy object. To remove
device control entirely (all four families), use the parent scenario's own rollback:

```powershell
./scenarios/dlp/defender-device-control-usb-allowlist-macos/deploy/Remove-MacDeviceControlUsbAllowlistPolicy.ps1 -Purge
```

This permanently deletes the shared object, including this fragment's entries, there is no
scenario where the parent is purged but Apple/Portable/Bluetooth coverage survives.

## What rollback does **not** undo

- **Advanced Hunting / `DeviceEvents` history** for events these families already generated, 
  retained per its own retention window regardless of policy state, same as the parent scenario.
- **The parent policy's `removableMedia` coverage, assignment, or object identity**, Stage 1 of
  this rollback is scoped exclusively to this fragment's own delta.
- **Device onboarding/Full Disk Access grant, or the approved-devices' physical inventory**, this
  scenario does not manage either; they are dependencies, not deployed artifacts.

## Verification after rollback

```powershell
Connect-MgGraph -ClientId $AppId -TenantId $TenantId -CertificateThumbprint $Thumbprint
$policy = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/deviceManagement/deviceConfigurations?`$filter=displayName eq 'Device Control (macOS) - USB Removable Media Default-Deny Allowlist'"
$full = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/deviceManagement/deviceConfigurations/$($policy.value[0].id)"
$xml = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($full.payload))
$match = [regex]::Match($xml, '<key>policy</key>\s*<string>(.*?)</string>', [System.Text.RegularExpressions.RegexOptions]::Singleline)
$decoded = $match.Groups[1].Value -replace '&lt;', '<' -replace '&gt;', '>' -replace '&amp;', '&'
$json = $decoded | ConvertFrom-Json

# Stage 1: confirm no appleDevice/portableDevice/bluetoothDevice feature flags remain, and only
# the parent's own removableMedia-scoped groups/rules are present
$json.settings.features.psobject.Properties.Name
$json.groups.name
$json.rules.name
```

## References

1. Device Control for macOS (per-family `settings.features.<name>.disable` enable model, "if you
   don't configure this value, it doesn't apply"), 
   <https://learn.microsoft.com/defender-endpoint/mac-device-control-overview>
