---
part: "rollback"
parent: "dlp/defender-device-control-usb-allowlist-macos-bluetooth-allowlist"
---
## Recommended sequence

This fragment shares one `macOSCustomConfiguration` object with the parent scenario and the
portable-device-coverage fragment. Rolling back means removing **only** this fragment's delta (one
sub-group per approved device, one parent group, one rule, and the `excludeGroups` edit to one
existing rule) - not the shared Bluetooth catch-all group or `Deny-AllBluetoothDevices`'s own two
deny/auditDeny entries.

### Stage 1 - Remove ALL Bluetooth device exceptions (reversible, minutes)

```powershell
Connect-MgGraph -ClientId $AppId -TenantId $TenantId -CertificateThumbprint $Thumbprint
./deploy/Remove-MacBluetoothDeviceAllowlist.ps1
```

This removes the `ApprovedBluetoothDevices` parent group, every per-device sub-group (identified by
the `BluetoothVendorProductMatch-` name prefix, since sub-group ids are deterministically derived
from config the removal script doesn't read), and the `Allow-ApprovedBluetoothDevice` rule, and
strips `excludeGroups` from `Deny-AllBluetoothDevices`, then PATCHes the whole `.mobileconfig`
payload. This is an all-or-nothing removal of every configured device at once, not per-device - see
Stage 2 to revoke a single device while keeping others approved. The prerequisite fragment's
Bluetooth coverage (its catch-all group, the deny rule's own entries), the parent's
`removableMedia` coverage, the Apple/Portable coverage, and the object's identity/assignment are all
untouched.

**Important:** removing these exceptions makes every previously-approved Bluetooth device **denied
again**, not left unrestricted - Bluetooth reverts to the portable-device-coverage fragment's
original unconditional-deny state. This is the *opposite* direction from most of this control's
other rollbacks (which typically remove restriction, not add it back) - confirm this is the
intended outcome (e.g. all approved devices are being formally revoked at once) before running this
stage as routine cleanup rather than a deliberate access-revocation action.

Re-add the exceptions instantly:

```powershell
./deploy/Add-MacBluetoothDeviceAllowlist.ps1 -ConfigPath ./deploy/config/my-tenant.json
```

### Stage 2 - Revoke or swap one approved device, keeping the rest (partial rollback)

To revoke a single device while leaving others approved, or to replace one device with another,
edit `approvedBluetoothDevices[]` in the config file (remove that device's entry, or edit its
`vendorId`/`productId`) and re-run `deploy/Add-MacBluetoothDeviceAllowlist.ps1 -Force` - this
reconciles the parent group/sub-groups/rule in place, dropping only the removed device's sub-group
and leaving every other configured device's sub-group and the shared parent group/rule untouched,
without a separate remove-then-add step or affecting any other device.

### Stage 3 - Remove the entire device control policy (not this fragment's rollback)

This fragment has no "Stage 3" of its own - there is only one shared policy object. To remove
device control entirely (all four families, every fragment's contributions), use the parent
scenario's own rollback:

```powershell
./scenarios/dlp/defender-device-control-usb-allowlist-macos/deploy/Remove-MacDeviceControlUsbAllowlistPolicy.ps1 -Purge
```

## What rollback does **not** undo

- **Advanced Hunting / `DeviceEvents` history** for events this exception already generated -
 retained per its own retention window regardless of policy state.
- **The prerequisite fragment's Bluetooth catch-all coverage, or the parent's/Apple/Portable
 coverage** - Stage 1 of this rollback is scoped exclusively to this fragment's own delta.
- **The known ordering hazard** (`README.md` §11) - rolling back this fragment does not change the
 fact that re-running the portable-device-coverage fragment's own `-Force` reconcile at any point
 in the future would have no additional effect once this fragment's exception is already removed
 (there is nothing left for it to strip), but if this fragment is later re-deployed, the hazard
 applies again from that point forward.

## Verification after rollback

```powershell
Connect-MgGraph -ClientId $AppId -TenantId $TenantId -CertificateThumbprint $Thumbprint
$policy = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/deviceManagement/deviceConfigurations?`$filter=displayName eq 'Device Control (macOS) - USB Removable Media Default-Deny Allowlist'"
$full = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/deviceManagement/deviceConfigurations/$($policy.value[0].id)"
$xml = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($full.payload))
$match = [regex]::Match($xml, '<key>policy</key>\s*<string>(.*?)</string>', [System.Text.RegularExpressions.RegexOptions]::Singleline)
$decoded = $match.Groups[1].Value -replace '&lt;', '<' -replace '&gt;', '>' -replace '&amp;', '&'
$json = $decoded | ConvertFrom-Json

# Stage 1: confirm no ApprovedBluetoothDevices parent group, no BluetoothVendorProductMatch- sub-
# groups, and no Allow-ApprovedBluetoothDevice rule remain, and the Deny-AllBluetoothDevices rule
# has no excludeGroups
$json.groups.name
$json.rules | Where-Object { $_.name -like '*Bluetooth*' } | Select-Object name, excludeGroups
```

## References

1. `scenarios/dlp/defender-device-control-usb-allowlist-macos-portable-device-coverage/rollback.md`
 - the prerequisite fragment's own rollback, for removing the shared Bluetooth coverage entirely.
2. `scenarios/dlp/defender-device-control-usb-allowlist-macos/rollback.md` - full policy removal.
