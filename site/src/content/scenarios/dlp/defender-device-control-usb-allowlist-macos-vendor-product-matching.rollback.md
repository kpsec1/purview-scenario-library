---
part: "rollback"
parent: "dlp/defender-device-control-usb-allowlist-macos-vendor-product-matching"
---
## Recommended sequence

This fragment shares one `macOSCustomConfiguration` object with the parent scenario (and, if
deployed, the Apple/Portable/Bluetooth sibling fragments). Rolling back means removing **only** this
fragment's delta (the `VendorProductMatch-*` sub-groups and their `groupId` clauses on
`ApprovedBackupDrives`) — not the parent's `serialNumber` clauses, `AllRemovableStorage`, or either
of the parent's two rules.

### Stage 1 — Revoke one device (reversible, minutes)

```powershell
# Remove the device's entry from deploy/config/my-tenant.json, then:
Connect-MgGraph -ClientId $AppId -TenantId $TenantId -CertificateThumbprint $Thumbprint
./deploy/Add-MacVendorProductDeviceAllowlist.ps1 -ConfigPath ./deploy/config/my-tenant.json
```

The deploy script recomputes the desired sub-group set from the edited config file, detects the
removed device's now-orphaned sub-group and `groupId` clause, and removes both in the same reconcile
— no `-Force` flag and no separate "remove" step required for a single-device revocation.

**Important:** removing a device's config entry makes that device **denied again** (unless it is
also separately matched by a `serialNumber` clause), not left unrestricted. Confirm this is the
intended outcome (e.g. the device is lost, decommissioned, or its approval is being formally
reviewed) before treating this as routine cleanup.

Re-add it instantly by restoring its config entry and re-running the same command — the deterministic
id derivation (`design.md` §4) means the restored device gets the identical sub-group id it had
before, not a fresh one.

### Stage 2 — Remove every vendorId/productId device exception (full fragment rollback)

```powershell
Connect-MgGraph -ClientId $AppId -TenantId $TenantId -CertificateThumbprint $Thumbprint
./deploy/Remove-MacVendorProductDeviceAllowlist.ps1
```

This strips every `VendorProductMatch-*` group and every `groupId` clause from
`ApprovedBackupDrives`, reverting it to serialNumber-only matching — the parent scenario's original,
pre-this-fragment state. The parent's `AllRemovableStorage` group, both of the parent's rules, the
object's identity, and its assignment are all untouched.

### Stage 3 — Remove the entire device control policy (not this fragment's rollback)

This fragment has no "Stage 3" of its own — there is only one shared policy object. To remove device
control entirely (every family, every fragment's contributions), use the parent scenario's own
rollback:

```powershell
./scenarios/dlp/defender-device-control-usb-allowlist-macos/deploy/Remove-MacDeviceControlUsbAllowlistPolicy.ps1 -Purge
```

## What rollback does **not** undo

- **Advanced Hunting / `DeviceEvents` history** for events an approved vendorId/productId device
  already generated — retained per its own retention window regardless of policy state.
- **The parent's `serialNumber`-based approvals, or the Apple/Portable/Bluetooth sibling fragments'
  own coverage** — both stages of this rollback are scoped exclusively to this fragment's own
  vendorId/productId additions.
- **A device also matched by a still-present `serialNumber` clause** — Stage 1 and Stage 2 both only
  remove this fragment's `groupId`-referenced OR-branch; a device independently approved by serial
  number remains approved through that separate mechanism.

## Verification after rollback

```powershell
Connect-MgGraph -ClientId $AppId -TenantId $TenantId -CertificateThumbprint $Thumbprint
$policy = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/deviceManagement/deviceConfigurations?`$filter=displayName eq 'Device Control (macOS) - USB Removable Media Default-Deny Allowlist'"
$full = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/deviceManagement/deviceConfigurations/$($policy.value[0].id)"
$xml = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($full.payload))
$match = [regex]::Match($xml, '<key>policy</key>\s*<string>(.*?)</string>', [System.Text.RegularExpressions.RegexOptions]::Singleline)
$decoded = $match.Groups[1].Value -replace '&lt;', '<' -replace '&gt;', '>' -replace '&amp;', '&'
$json = $decoded | ConvertFrom-Json

# Stage 1: confirm the revoked device's group is gone and no dangling groupId clause references it
$json.groups.name
($json.groups | Where-Object { $_.id -eq '22222222-bbbb-4ccc-8ddd-222222222222' }).query.clauses

# Stage 2: confirm no VendorProductMatch-* group remains at all
$json.groups.name | Where-Object { $_ -like 'VendorProductMatch-*' }   # expect empty
```

## References

1. `scenarios/dlp/defender-device-control-usb-allowlist-macos/rollback.md` — full policy removal
   (Stage 3), and the parent scenario's own rollback for its `serialNumber`-based approvals.
2. `scenarios/dlp/defender-device-control-usb-allowlist-macos-bluetooth-allowlist/rollback.md` — the
   sibling fragment's equivalent single-device rollback, for the same "revocation, not
   unrestriction" caution.
