---
part: "runbook"
parent: "dlp/defender-device-control-usb-allowlist-macos-bluetooth-allowlist"
---
## Implementation steps

### Portal path (for a first manual walkthrough / to validate intent before scripting)

1. Confirm both prerequisite fragments are already deployed - [Microsoft Intune admin
   center](https://intune.microsoft.com) → **Devices** → **macOS** → **Configuration profiles** →
   the parent policy → Custom configuration → view the current `.mobileconfig`, and confirm its
   `deviceControl.policy` JSON already contains an `AllBluetoothDevices` group and a
   `Deny-AllBluetoothDevices` rule.
2. Add one new sub-group to the same JSON's `groups[]` array **per approved device** - `$type:
   "and"`, clauses `[{"$type":"primaryId","value":"bluetooth_devices"},
   {"$type":"vendorId","value":"<4-digit hex>"}, {"$type":"productId","value":"<4-digit hex>"}]` -
   the exact per-device shape Microsoft's own `deny_all_bluetooth_devices_except_samsung.json` sample
   uses.
3. Add one new **parent** group - `$type: "or"`, clauses = one `{"$type":"groupId","value":"<sub-group
   id>"}` entry per device sub-group added in step 2. This one parent group represents "any of the
   approved devices."
4. Edit the existing `Deny-AllBluetoothDevices` rule to add `"excludeGroups": ["<parent group id>"]`
   - leave its `entries` untouched.
5. Add one new rule to `rules[]` - `includeGroups: ["<parent group id>"]`, two entries: `allow` and
   `auditAllow` (`send_event`), both `$type: "bluetoothDevice"`, `access: ["download_files_from_device",
   "send_files_to_device"]`.
6. Re-escape the edited JSON, re-embed it as the `<key>policy</key><string>...</string>` value, and
   re-upload the `.mobileconfig` - **replacing**, not creating a second profile.
7. **Review + save.** No new assignment step - this reuses the existing assignment.

### Script path (idempotent, parameterized, dry-run capable)

```powershell
# 1. Connect (certificate app-only - see Automation surface Section 3)
Connect-MgGraph -ClientId $AppId -TenantId $TenantId -CertificateThumbprint $Thumbprint

# 2. Edit deploy/config/mac-bluetooth-device-allowlist.sample.json (or copy it) with one or more
# approved devices' vendorId/productId. Leave approvedBluetoothDevices empty for pure default-deny.

# 3. Dry run - reports the planned PATCH, makes no changes
./deploy/Add-MacBluetoothDeviceAllowlist.ps1 `
    -ConfigPath ./deploy/config/mac-bluetooth-device-allowlist.sample.json `
    -WhatIf

# 4. Add the exception
./deploy/Add-MacBluetoothDeviceAllowlist.ps1 `
    -ConfigPath ./deploy/config/mac-bluetooth-device-allowlist.sample.json

# 5. Validate
./validate/Test-MacBluetoothDeviceAllowlist.ps1 `
    -ConfigPath ./deploy/config/mac-bluetooth-device-allowlist.sample.json
```

The deploy script refuses to run if the portable-device-coverage fragment's Bluetooth coverage
doesn't already exist. Like both fragments beneath it, it uses `Invoke-MgGraphRequest`
against the `macOSCustomConfiguration` resource (automation surface 3 per
[Automation surface, section 3](/docs/automation-surface/#3-authentication-patterns---interactive-vs-unattended)). It extracts the parent's current embedded policy JSON, merges in
this fragment's per-device sub-groups and parent group/rule, rebuilds the shared
`Deny-AllBluetoothDevices` rule with its original two entries reproduced unchanged plus the new
`excludeGroups`, and PATCHes the whole `.mobileconfig` payload back - every other plist key and
every group/rule this fragment doesn't own is left untouched - see the design notes. Each device's
sub-group id is derived deterministically (RFC 4122 v5 UUID) from its `vendorId:productId` pair, so
re-running the script never duplicates a sub-group for the same device, and removing a device from
`-ConfigPath` cleanly drops its sub-group on the next run.

## Configuration reference

| Setting | Location in `deviceControl.policy` JSON | Value |
|---|---|---|
| Sub-group: `BluetoothVendorProductMatch-<label>` (one per device) | `groups[]` | `query: {"$type":"and","clauses":[{"$type":"primaryId","value":"bluetooth_devices"},{"$type":"vendorId","value":"<config>"},{"$type":"productId","value":"<config>"}]}`; `id` deterministically derived (RFC 4122 v5) from `vendorId:productId` |
| Parent group: `ApprovedBluetoothDevices` (fixed id, unchanged since v1) | `groups[]` | `query: {"$type":"or","clauses":[{"$type":"groupId","value":"<sub-group id>"}, ... one per device]}` |
| Rule: `Deny-AllBluetoothDevices` (modified) | `rules[]` | Adds `"excludeGroups": ["<ApprovedBluetoothDevices parent group id>"]`; `entries` unchanged from the portable-device-coverage fragment (`deny` + `auditDeny(send_event, show_notification)`, `access=[download_files_from_device, send_files_to_device]`) |
| Rule: `Allow-ApprovedBluetoothDevice` (new) | `rules[]` | `includeGroups=[ApprovedBluetoothDevices parent group]`; entries `$type: bluetoothDevice`, `allow` + `auditAllow(send_event)`, `access=[download_files_from_device, send_files_to_device]` |

Every property name, clause `$type`, and access string above is confirmed directly against
Microsoft's official "Device Control for macOS" Query/Clause/Access-policy-rule/Access-Types
reference tables, and matches Microsoft's own published `deny_all_bluetooth_devices_except_samsung.json`
sample byte-for-byte for the exception group's `$type: "and"` shape and clause set - fetched
directly from the GitHub repository during this fragment's build.

**Why this fragment adds an explicit `allow` entry, unlike Microsoft's own sample.** Microsoft's
worked sample only pairs `excludeGroups` with an `auditAllow` entry (no plain `allow`), because that
sample's own `settings.global.defaultEnforcement` is `"allow"` (Microsoft's documented default) - a
device excluded from the one deny rule simply falls through to the permissive default. This
fragment's shared policy inherits `defaultEnforcement = "deny"` (fail-closed) from the parent
scenario (*Defender for Endpoint Device Control (macOS): USB Default-Deny Allowlist* (the validation steps)) and does not change it - under
a fail-closed default, a device excluded from the deny rule but matched by no `allow` entry still
falls through to deny. This fragment therefore adds an explicit `allow` + `auditAllow` entry pair for
the approved device, the same "both paths audited" pattern the parent and portable-device-coverage
fragments already use for their own approved-device rules - not a deviation from Microsoft's
documented behavior, but a deliberate adaptation to this shared policy's own already-established,
stricter default. See the design notes.

**`vendorId`/`productId` identify a device *model*, not a unique physical unit.** Unlike this
control's `serialNumber`-based allowlists (removable media, Apple, Portable), Bluetooth's exception
mechanism has no documented per-unit identifier - see the known limitations.

## Operations and tuning

This fragment shares the parent scenario's full operations model and the
portable-device-coverage fragment's own additions (operations and tuning there). Two additions specific to
this fragment:

- **Keep the approved-device list to exactly the devices with a documented business need.** Every
  device sharing the same `vendorId`+`productId` pair - not just the one physical unit an approver
  had in mind - is allowed once configured. Treat approval as "this model, for this business
  reason," not "this specific unit."
- **After any change to Apple/Portable coverage via the portable-device-coverage fragment's own
  `-Force` reconcile, re-run this fragment's deploy script and re-validate.** This is the documented
  ordering hazard - it is a routine operational step for this three-layer policy, not an
  incident, but it needs to be in the standard change-management runbook for this control, not
  discovered the hard way after a Bluetooth exception silently stops working.
- **Review `Allow-ApprovedBluetoothDevice` `auditAllow` event volume and distinct `DeviceName` count
  against the number of physically-issued approved units, on the same review cadence as the parent
  control's other KPIs.** Because `vendorId`+`productId` cannot distinguish the genuine approved
  unit from an impersonating one with a matching model identifier, this comparison - more
  distinct allowed devices than units actually issued, or a volume spike from one `DeviceName` that
  doesn't match known usage - is the practical detection signal available in this schema for the
  residual gap described in the known limitations, not a cryptographic guarantee.

## Rollback and decommission

See the rollback runbook. Quick reference: `./deploy/Remove-MacBluetoothDeviceAllowlist.ps1` strips this
fragment's group and allow rule, and removes `excludeGroups` from the shared
`Deny-AllBluetoothDevices` rule, reverting Bluetooth to the portable-device-coverage fragment's
original unconditional-deny state - not to unrestricted. To remove the entire device control policy
(all four families), use the parent scenario's own
`Remove-MacDeviceControlUsbAllowlistPolicy.ps1 -Purge`.

## References

1. Device Control for macOS (Query type 1 `$type`/`and`/`or` AND/OR semantics; Clause reference -
   `vendorId`/`productId` "Four digit hexadecimal string"; Access policy rule reference -
   `includeGroups` multiple-groups-is-AND, `excludeGroups` multiple-groups-is-OR; Enforcement
   reference - `allow`/`deny`/`auditAllow`/`auditDeny`; Access Types table for `bluetoothDevice`;
   `settings.global.defaultEnforcement` `"allow"` (default) or `"deny"`) -
   <https://learn.microsoft.com/defender-endpoint/mac-device-control-overview>
2. Sample macOS device control policy - `deny_all_bluetooth_devices_except_samsung.json` (the exact
   `vendorId`+`productId` AND-match exception-group and allow-rule shape this fragment reproduces;
   fetched directly from the raw file during this fragment's build) -
   <https://github.com/microsoft/mdatp-devicecontrol/blob/main/macOS/policy/samples/deny_all_bluetooth_devices_except_samsung.json>
3. *Defender for Endpoint Device Control (macOS): Apple/Portable/Bluetooth Device Coverage* - the
   prerequisite fragment this scenario extends; owns the `AllBluetoothDevices` group and
   `Deny-AllBluetoothDevices` rule this fragment adds an exception to. See that scenario's own
   references for every citation not repeated here.
4. *Defender for Endpoint Device Control (macOS): USB Default-Deny Allowlist* - the root parent scenario; see its
   own references for licensing, onboarding, Full Disk Access, and Graph resource schemas.

> Re-verify all links, and especially the `AdditionalFields` VendorId/ProductId VERIFY and the
> `payload` PATCH replace-vs-merge semantics inherited from the parent, against current Microsoft
> Learn and a pilot tenant before a customer-facing assessment or sale.