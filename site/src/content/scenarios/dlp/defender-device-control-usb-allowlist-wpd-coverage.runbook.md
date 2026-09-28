---
part: "runbook"
parent: "dlp/defender-device-control-usb-allowlist-wpd-coverage"
---
## Implementation steps

### Portal path (for a first manual walkthrough / to validate intent before scripting)

1. Confirm the parent policy (`Device Control - USB Removable Media Default-Deny Allowlist`)
   already exists and is assigned to at least a pilot group - [Microsoft Intune admin
   center](https://intune.microsoft.com) → **Devices** → **Configuration profiles**.
2. Open the policy → edit its OMA-URI rows.
3. Change the `SecuredDevicesConfiguration` row's value from `RemovableMediaDevices` to
   `RemovableMediaDevices|WpdDevices` (single word, pipe-separated, no spaces - Microsoft
   explicitly warns a string that doesn't follow this syntax "will cause unexpected behavior"
  ).
4. Add four new OMA-URI rows - one per setting in the design notes's table (two Group XML rows, two
   Rule XML rows), each **Data type: String (XML file), Custom XML** - using the friendly names
   from Windows Device Manager for each approved WPD device.
5. **Review + save.** No new assignment step - this reuses the parent policy's existing
   assignment.

### Script path (idempotent, parameterized, dry-run capable)

```powershell
# 1. Connect (certificate app-only - see docs/automation-surface.md Section 3)
Connect-MgGraph -ClientId $AppId -TenantId $TenantId -CertificateThumbprint $Thumbprint

# 2. Edit deploy/config/wpd-device-control-coverage.sample.json (or copy it) with your approved
#    WPD devices' Device Manager friendly names (see Section 6, Section 11).

# 3. Dry run - reports the planned PATCH, makes no changes
./deploy/Add-WpdDeviceControlCoverage.ps1 `
    -ConfigPath ./deploy/config/wpd-device-control-coverage.sample.json `
    -WhatIf

# 4. Add WPD coverage to the parent policy
./deploy/Add-WpdDeviceControlCoverage.ps1 `
    -ConfigPath ./deploy/config/wpd-device-control-coverage.sample.json

# 5. Validate
./validate/Test-WpdDeviceControlCoverage.ps1 `
    -ConfigPath ./deploy/config/wpd-device-control-coverage.sample.json
```

The deploy script refuses to run if the parent policy doesn't already exist - it never
creates a standalone WPD-only policy. Like the parent, it uses `Invoke-MgGraphRequest` against the
`windows10CustomConfiguration` resource (automation surface 3 per [Automation surface, section 1](/docs/automation-surface/#1-five-automation-surfaces-not-one-read-this-first)).

## Configuration reference

| Setting | OMA-URI suffix | Type | Value |
|---|---|---|---|
| Scope (widened) | `SecuredDevicesConfiguration` | `omaSettingString` | `RemovableMediaDevices|WpdDevices` (changed from the parent's original `RemovableMediaDevices`) |
| Group: `ApprovedWpdDevices` (new) | `DeviceControl/PolicyGroups/{GUID}/GroupData` | `omaSettingStringXml` | `MatchAny` over `FriendlyNameId` (confirmed) and, optionally, `SerialNumberId`/`VID_PID` (unconfirmed for WPD - the known limitations) entries from config |
| Group: `AllWpdDevices` (new, catch-all) | `DeviceControl/PolicyGroups/{GUID}/GroupData` | `omaSettingStringXml` | `MatchAny` over `PrimaryId = WpdDevices` |
| Rule: `Allow-ApprovedWpdDevices` (new) | `DeviceControl/PolicyRules/{GUID}/RuleData` | `omaSettingStringXml` | Included = approved WPD group; `Allow`(AccessMask 63) + `AuditAllowed`(send event) |
| Rule: `Deny-AllOtherWpd` (new) | `DeviceControl/PolicyRules/{GUID}/RuleData` | `omaSettingStringXml` | Included = catch-all WPD group, Excluded = approved WPD group; `Deny`(AccessMask 63) + `AuditDenied`(notify + send event) |

The parent's original seven settings (`DeviceControlEnabled`, `DefaultEnforcement`,
`ApprovedBackupDrives` group, `AllRemovableStorage` catch-all group, and the two
`RemovableMediaDevices` rules) are preserved byte-for-byte - this fragment's deploy script rebuilds
the full `omaSettings` array by keeping every non-scope, non-WPD setting from the live object and
only replacing the scope string and (re)adding the four WPD entries (`deploy/
Add-WpdDeviceControlCoverage.ps1`'s `.DESCRIPTION`).

**Matching a device to `FriendlyNameId`:** open **Device Manager** on a machine the device is
connected to → locate the device (usually under "Portable Devices" or "Cameras") → right-click →
**Properties** → **Details** tab → **Device description** shows the friendly name (the same value
Device Control matches against as `FriendlyNameId`). This is the one group
property Microsoft's Device-Manager-mapping guidance directly confirms is populated for
portable-device-class hardware; `SerialNumberId`/`VID_PID` are accepted by this scenario's config
schema too but are unconfirmed for the WPD family specifically - see the known limitations.

All four new GUIDs are fixed constants defined in `deploy/Add-WpdDeviceControlCoverage.ps1` (not
freshly generated per run), matching the parent scenario's same idempotency rationale
(the design notes there).

## Operations and tuning

This fragment shares the parent scenario's full operations model - deployment
sequence, KPI categories, alert routing, review cadence, and incident-response runbook all apply
unchanged, extended to WPD events. Two WPD-specific additions:

- **Reviewing the approved-WPD-device list** carries the same privileged-access review cadence as
  the parent's `approvedDevices` list (quarterly at minimum) - a friendly name is a weaker
  identifier than a serial number, so this list warrants closer scrutiny at each review, not
  looser.
- **A spike in WPD deny events right after this fragment ships** is the expected signal of
  previously-invisible phone/camera usage becoming visible for the first time - investigate for
  legitimate business use before assuming misuse, the same caution the parent scenario documents
  for its own initial rollout.

## Rollback and decommission

See the rollback runbook. Quick reference: `./deploy/Remove-WpdDeviceControlCoverage.ps1` reverts
`SecuredDevicesConfiguration` to `RemovableMediaDevices` only and removes the four WPD-specific
`omaSettings` entries, leaving the parent policy's original USB coverage, assignment, and object
identity untouched. To remove the entire device control policy (both families), use the parent
scenario's own `Remove-DeviceControlUsbAllowlistPolicy.ps1`.

## References

1. Device control in Microsoft Defender for Endpoint (WPD added in anti-malware client
   `4.18.2107`+; "grant access for all entries associated with the physical device"; disk-letter
   definition distinguishing removable media from WPD) - <https://learn.microsoft.com/defender-endpoint/device-control-overview>
2. Deploy and manage device control in Microsoft Defender for Endpoint with Microsoft Intune
   (`SecuredDevicesConfiguration` OMA-URI, pipe-separated multi-value syntax and "must be all one
   word with no spaces" warning) - <https://learn.microsoft.com/defender-endpoint/device-control-deploy-manage-intune>
3. Device control policies in Microsoft Defender for Endpoint (`PrimaryId` family list including
   `WpdDevices`, `DescriptorIdList` properties, AccessMask parity confirmed across
   `CdRomDevices`/`RemovableMediaDevices`/`WpdDevices`, Windows-Device-Manager-to-`FriendlyNameId`
   mapping, Intune reusable-settings-groups device-group types) - <https://learn.microsoft.com/defender-endpoint/device-control-policies>
4. Device control policies in Microsoft Defender for Endpoint - Groups section (general Windows-devices property-support table for `FriendlyNameId`/`VID_PID`/`SerialNumberId`, not broken down
   by `PrimaryId` family; Intune reusable-settings-groups device-group type table showing only
   Printer device / Removable storage, not WPD) - <https://learn.microsoft.com/defender-endpoint/device-control-policies#groups>
5. *Defender for Endpoint Device Control: USB Default-Deny Allowlist* - the parent scenario this fragment
   extends; see that scenario's own references for every citation not repeated here (licensing,
   onboarding, Graph resource schemas, PowerShell cmdlet references, Advanced Hunting/Sentinel
   alert routing).

> Re-verify all links, and especially the `SerialNumberId`/`VID_PID`-for-WPD VERIFY, against
> current Microsoft Learn and a pilot tenant before a customer-facing assessment or sale.