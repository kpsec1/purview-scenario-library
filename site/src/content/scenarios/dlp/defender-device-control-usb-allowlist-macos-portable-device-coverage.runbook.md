---
part: "runbook"
parent: "dlp/defender-device-control-usb-allowlist-macos-portable-device-coverage"
---
## Implementation steps

### Portal path (for a first manual walkthrough / to validate intent before scripting)

1. Confirm the parent policy (`Device Control (macOS) - USB Removable Media Default-Deny
   Allowlist`) already exists and is assigned to at least a pilot group - [Microsoft Intune admin
   center](https://intune.microsoft.com) → **Devices** → **macOS** → **Configuration profiles**.
2. Open the policy → its Custom configuration → download/view the current `.mobileconfig`.
3. Enable the three new families: unlike the top-level `dlp.features` engine switch
   (`DC_in_dlp`, already enabled by the parent), per-family enablement lives **inside** the
   `deviceControl.policy` JSON string itself. Edit that embedded JSON to add
   `"appleDevice": {"disable": false}`, `"portableDevice": {"disable": false}`,
   `"bluetoothDevice": {"disable": false}` under `settings.features`, alongside the parent's
   existing `removableMedia` entry.
4. Add the three catch-all groups and up to five rules from the design notes's table to the same
   JSON's `groups`/`rules` arrays.
5. Re-escape the edited JSON, re-embed it as the `<key>policy</key><string>...</string>` value, and
   re-upload the `.mobileconfig` to the same Custom configuration profile - **replacing**, not
   creating a second profile.
6. **Review + save.** No new assignment step - this reuses the parent policy's existing assignment.

### Script path (idempotent, parameterized, dry-run capable)

```powershell
# 1. Connect (certificate app-only - see docs/automation-surface.md Section 3)
Connect-MgGraph -ClientId $AppId -TenantId $TenantId -CertificateThumbprint $Thumbprint

# 2. Edit deploy/config/mac-portable-device-coverage.sample.json (or copy it). Leave
#    approvedAppleDevices/approvedPortableDevices empty for pure default-deny, or add entries to
#    allowlist specific IT-issued devices by serial number.

# 3. Dry run - reports the planned PATCH, makes no changes
./deploy/Add-MacPortableDeviceCoverage.ps1 `
    -ConfigPath ./deploy/config/mac-portable-device-coverage.sample.json `
    -WhatIf

# 4. Add coverage to the parent policy
./deploy/Add-MacPortableDeviceCoverage.ps1 `
    -ConfigPath ./deploy/config/mac-portable-device-coverage.sample.json

# 5. Validate
./validate/Test-MacPortableDeviceCoverage.ps1 `
    -ConfigPath ./deploy/config/mac-portable-device-coverage.sample.json
```

The deploy script refuses to run if the parent policy doesn't already exist - it never
creates a standalone policy. Like the parent, it uses `Invoke-MgGraphRequest` against the
`macOSCustomConfiguration` resource (automation surface 3 per [Automation surface, section 1](/docs/automation-surface/#1-five-automation-surfaces-not-one-read-this-first)). It
extracts the parent's current embedded policy JSON, merges in this fragment's additions, and
PATCHes the whole `.mobileconfig` payload back - every other plist key (`PayloadUUID`,
`PayloadIdentifier`, `PayloadDisplayName`, etc.) and every group/rule this fragment doesn't own is
left untouched - see the design notes.

## Configuration reference

| Setting | Location in `deviceControl.policy` JSON | Value |
|---|---|---|
| Enable Apple device enforcement | `settings.features.appleDevice.disable` | `false` (new) |
| Enable Portable device enforcement | `settings.features.portableDevice.disable` | `false` (new) |
| Enable Bluetooth device enforcement | `settings.features.bluetoothDevice.disable` | `false` (new) |
| Group: `AllAppleDevices` (catch-all) | `groups[]` | `query: {"$type":"all","clauses":[{"$type":"primaryId","value":"apple_devices"}]}` |
| Group: `ApprovedAppleDevices` (optional) | `groups[]` | `query: {"$type":"or","clauses":[{"$type":"serialNumber","value":"<serial>"}, ...]}` from `-ConfigPath`'s `approvedAppleDevices` |
| Group: `AllPortableDevices` (catch-all) | `groups[]` | `query: {"$type":"all","clauses":[{"$type":"primaryId","value":"portable_devices"}]}` |
| Group: `ApprovedPortableDevices` (optional) | `groups[]` | Same `serialNumber`/`or` shape, from `approvedPortableDevices` |
| Group: `AllBluetoothDevices` (catch-all) | `groups[]` | `query: {"$type":"all","clauses":[{"$type":"primaryId","value":"bluetooth_devices"}]}` - **no approved-devices sibling group in this fragment** |
| Rule: `Allow-ApprovedAppleDevices` (if configured) | `rules[]` | `includeGroups=[ApprovedAppleDevices]`; entries `$type: appleDevice`, `allow` + `auditAllow(send_event)`, `access=[download_files_from_device, sync_content_to_device, backup_device, update_device, download_photos_from_device]` |
| Rule: `Deny-All(Other)AppleDevices` | `rules[]` | `includeGroups=[AllAppleDevices]`, `excludeGroups=[ApprovedAppleDevices]` if configured; entries `$type: appleDevice`, `deny` + `auditDeny(send_event, show_notification)`, same access list |
| Rule: `Allow-ApprovedPortableDevices` (if configured) | `rules[]` | `includeGroups=[ApprovedPortableDevices]`; entries `$type: portableDevice`, `allow` + `auditAllow`, `access=[download_files_from_device, send_files_to_device, download_photos_from_device, debug]` |
| Rule: `Deny-All(Other)PortableDevices` | `rules[]` | `includeGroups=[AllPortableDevices]`, `excludeGroups=[ApprovedPortableDevices]` if configured; same entry shape, deny+auditDeny |
| Rule: `Deny-AllBluetoothDevices` | `rules[]` | `includeGroups=[AllBluetoothDevices]`, no `excludeGroups`; entries `$type: bluetoothDevice`, `deny` + `auditDeny`, `access=[download_files_from_device, send_files_to_device]` |

Every property name, clause `$type`, entry `$type`, and `access` string above is confirmed directly
against Microsoft's official "Device Control for macOS" Settings/Clause/Access-Types tables and
cross-checked against three of Microsoft's own published GitHub sample policies
(`audit_all_apple_devices.json`, `deny_mobile_devices.json`,
`deny_all_bluetooth_devices_except_samsung.json`) - see the references and the deploy script's `.NOTES`.
Notably, this closes a capitalization ambiguity the Windows WPD-coverage sibling's own grounding
pass had to flag as unresolved: the Learn page's entry-`$type` property table shows `PortableDevice`
(capital P) in one cell, inconsistent with every other row in the same table and with the page's
own Access Types table below it (`portableDevice`, lowercase) - three independently-published
worked samples all use the lowercase form, resolved here as a documentation table rendering
inconsistency, not a second valid casing.

All eight new GUIDs (five groups, five rules) are fixed constants defined in
`deploy/Add-MacPortableDeviceCoverage.ps1` (not freshly generated per run), matching the parent
scenario's own idempotency rationale (the design notes there).

**Matching a device to `serialNumber`:** Microsoft's clause reference states `serialNumber`
"[m]atches a device's serial number. Doesn't match if the device doesn't have a serial number."
 - confirmed directly for the `apple_devices` family via Microsoft's own worked
sample; not independently confirmed via a worked example for `portable_devices`
specifically (the known limitations VERIFY). There is no `serialNumber`-based allowlist option for `bluetooth_devices`
in this fragment - Microsoft's own worked sample for that family uses `vendorId`+`productId`
compound matching instead.

## Operations and tuning

This fragment shares the parent scenario's full operations model - deployment
sequence, KPI categories, alert routing, review cadence, and incident-response runbook all apply
unchanged, extended to the three new families. Two additions specific to this fragment:

- **A spike in Apple/Portable/Bluetooth deny events right after this fragment ships** is the
  expected signal of previously-invisible device usage becoming visible for the first time -
  investigate for legitimate business use (e.g. a team that routinely backs up iPads) before
  assuming misuse, the same caution the parent scenario documents for its own initial rollout and
  the Windows WPD-coverage sibling documents for phones/cameras.
- **Bluetooth deny events have no "was this an approved device" triage step** - every Bluetooth
  deny is, by this fragment's design, either a genuine policy hit or a legitimate use case that
  needs a scope decision (widen a future allowlist follow-up, or accept the block) rather than a
  simple "add it to the allowlist and move on" response available for the other two families.

## Rollback and decommission

See the rollback runbook. Quick reference: `./deploy/Remove-MacPortableDeviceCoverage.ps1` strips this
fragment's three feature flags, catch-all groups, optional approved-device groups, and five rules
back out of the parent's `.mobileconfig` payload, leaving the parent's original `removableMedia`
coverage, assignment, and object identity untouched. To remove the entire device control policy
(all four families), use the parent scenario's own `Remove-MacDeviceControlUsbAllowlistPolicy.ps1`.

## References

1. Device Control for macOS (Settings/Features table - `appleDevice`/`portableDevice`/
   `bluetoothDevice`/`removableMedia`, each disabled by default; Clause reference including
   `primaryId` values `apple_devices`/`portable_devices`/`bluetooth_devices`/
   `removable_media_devices`, `serialNumber`, `vendorId`, `productId`; Access Types table for
   `appleDevice`/`portableDevice`/`bluetoothDevice`/`removableMedia`/`generic`; best-practice
   guidance on generic access types; known Android-PTP-mode-only limitation) -
   <https://learn.microsoft.com/defender-endpoint/mac-device-control-overview>
2. Sample macOS device control policies (Microsoft-published GitHub worked examples independently
   confirming entry `$type` casing - `appleDevice`/`portableDevice`/`bluetoothDevice`, all
   lowercase-first-letter - access-string lists per family, the `serialNumber`/`or`/`excludeGroups`
   approved-device pattern for `apple_devices`, and the `vendorId`+`productId` compound-match
   pattern for `bluetooth_devices`) -
   <https://github.com/microsoft/mdatp-devicecontrol/tree/main/macOS/policy/samples>
   - `audit_all_apple_devices.json`, `audit_all_apple_devices_except_serial_numbers.json`,
     `deny_mobile_devices.json`, `deny_all_bluetooth_devices_except_samsung.json`
3. Device control policies in Microsoft Defender for Endpoint (shared Groups/Rules/Entries concepts
   across Windows and macOS) - <https://learn.microsoft.com/defender-endpoint/device-control-policies>
4. Device control in Microsoft Defender for Endpoint (Windows-side worked Advanced Hunting example
   confirming the `RemovableStoragePolicy`/`RemovableStorageAccess`/`RemovableStoragePolicyVerdict`
   `AdditionalFields` shape for `RemovableStoragePolicyTriggered` events, cited in the validation steps step 8 - used
   here on the strength of the parent macOS scenario's own established, cross-platform
   `DeviceEvents` schema assumption, not an independent macOS-side worked example) -
   <https://learn.microsoft.com/defender-endpoint/device-control-overview>
5. *Defender for Endpoint Device Control (macOS): USB Default-Deny Allowlist* - the parent scenario this fragment
   extends; see that scenario's own references for every citation not repeated here (licensing,
   onboarding, Full Disk Access, Graph resource schemas, Advanced Hunting/Sentinel alert routing).
6. *Defender for Endpoint Device Control: Windows Portable Device (WPD) Coverage* - the Windows sibling
   fragment this scenario is the direct macOS analog of.

> Re-verify all links, and especially the `portable_devices`-`serialNumber` VERIFY and the
> `payload` PATCH replace-vs-merge semantics inherited from the parent, against current Microsoft
> Learn and a pilot tenant before a customer-facing assessment or sale.