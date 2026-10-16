---
part: "runbook"
parent: "dlp/defender-device-control-usb-allowlist-macos-apple-portable-vendor-product-matching"
---
## Implementation steps

### Portal path (for a first manual walkthrough / to validate intent before scripting)

1. Confirm the prerequisites are already deployed: Intune admin center → **Devices** → **macOS** →
   **Configuration profiles** → confirm `Device Control (macOS) - USB Removable Media Default-Deny
   Allowlist` exists, and that its embedded policy JSON already has an `ApprovedAppleDevices` and/or
   `ApprovedPortableDevices` group (from the portable-device-coverage fragment) with at least one
   `serialNumber` clause for the family you want to extend.
2. Obtain the vendor ID and product ID for each device to approve.
3. Edit the profile's `.mobileconfig`: add one `groups[]` entry per device (shape: the design notes
   row 1) and one `groupId` clause per device to the relevant family's existing Approved group's
   `query.clauses` array (shape: the design notes row 2), preserving every existing `serialNumber`
   clause unchanged.
4. Re-upload the modified `.mobileconfig` as the profile's configuration file, replacing the
   existing one.
5. **Save**. No assignment change is needed.

### Script path (idempotent, parameterized, dry-run capable)

```powershell
# 1. Connect (certificate app-only - see Automation surface Section 3)
Connect-MgGraph -ClientId $AppId -TenantId $TenantId -CertificateThumbprint $Thumbprint

# 2. Edit deploy/config/mac-apple-portable-vendor-product-device-allowlist.sample.json (or copy it)
# with your approved devices' vendorId/productId pairs, per family. Leave either family's array
# empty (or omitted) if you don't need it.

# 3. Dry run - reports every change, makes none
./deploy/Add-MacApplePortableVendorProductDeviceAllowlist.ps1 `
    -ConfigPath ./deploy/config/mac-apple-portable-vendor-product-device-allowlist.sample.json `
    -WhatIf

# 4. Deploy
./deploy/Add-MacApplePortableVendorProductDeviceAllowlist.ps1 `
    -ConfigPath ./deploy/config/mac-apple-portable-vendor-product-device-allowlist.sample.json

# 5. Validate
./validate/Test-MacApplePortableVendorProductDeviceAllowlist.ps1 `
    -ConfigPath ./deploy/config/mac-apple-portable-vendor-product-device-allowlist.sample.json

# 6. To revoke a device: remove its entry from the config file and re-run step 4 - the deploy
# script detects and removes the now-orphaned sub-group automatically, no -Force required.
```

The deploy script uses the Microsoft Graph PowerShell SDK (`Invoke-MgGraphRequest` against the same
`macOSCustomConfiguration` resource) - automation surface 3 per [Automation surface, section 1](/docs/automation-surface/#1-five-automation-surfaces-not-one-read-this-first). It
never creates the prerequisite groups/rules and never changes the parent policy's assignment.

## Configuration reference

| Setting | Location in `.mobileconfig` | Value |
|---|---|---|
| Per-device sub-group (Apple) | `deviceControl.policy.groups[]` (inserted immediately before `ApprovedAppleDevices`) | `{"$type":"device","id":"<UUIDv5(namespace, apple/vendorId:productId)>","name":"AppleVendorProductMatch-<label>","query":{"$type":"and","clauses":[{"$type":"primaryId","value":"apple_devices"},{"$type":"vendorId","value":"<hex>"},{"$type":"productId","value":"<hex>"}]}}` |
| Per-device sub-group (Portable) | `deviceControl.policy.groups[]` (inserted immediately before `ApprovedPortableDevices`) | Same shape, `primaryId` value `portable_devices`, name prefix `PortableVendorProductMatch-` |
| `ApprovedAppleDevices`/`ApprovedPortableDevices` clause edit | `deviceControl.policy.groups[].query.clauses[]` | One `{"$type":"groupId","value":"<sub-group id>"}` appended per configured device, alongside the family's pre-existing `serialNumber` clauses (`query.$type` read from the live object and preserved unchanged - see the design notes) |
| Sub-group id derivation | N/A - computed, not stored as a separate object | RFC 4122 the architecture.3 version-5 UUID: `SHA1(namespace_bytes ++ UTF8("mac-apple-portable-vendor-product-match/v1/<family>/<vendorId>:<productId>"))`, version/variant bits patched. Namespace: `c7e21a4f-9d3b-4e6a-8c1f-2b3d4e5f6071` (fixed, this fragment's own constant, distinct from every other fragment's namespace). See the design notes. |
| Rules | *(unchanged)* - `Allow-ApprovedAppleDevices`/`Allow-ApprovedPortableDevices`, `Deny-AllOtherAppleDevices`/`Deny-AllOtherPortableDevices` | Not modified by this fragment; all already key off their family's Approved group's id. |

All group ids this fragment creates are **deterministic**, not fixed literals - the same
family+vendorId+productId always produces the same id, on any machine, with no state file. Full
cmdlet/REST/schema grounding: the deploy script's `.NOTES` block and the references below.

## Operations and tuning

**Deployment sequence:** this fragment ships directly into the prerequisite fragment's existing
assignment scope - there is no separate rollout stage of its own. Add a vendorId/productId device
only after the prerequisite fragment is already assigned to the intended endpoints and has at least
one `serialNumber` device configured for that family.

**KPIs to watch (first 30 days):** identical framing to the parent scenario's operations and tuning, with the same
addition the removable-media vendor-product-matching sibling already documents - track
`Allow-Approved{Family}Devices` `auditAllow` event volume **per configured vendorId+productId pair**
against the number of physically-issued units of that model, since this mechanism approves a
*model*, not a unit.

**Alert routing:** unchanged - same Advanced Hunting/`DeviceEvents` and Microsoft Defender Streaming
API/Sentinel connector paths as the parent scenario's operations and tuning.

**Review cadence:** quarterly at minimum. Re-run `validate/
Test-MacApplePortableVendorProductDeviceAllowlist.ps1` as part of that review, and cross-check each
family's `vendorProduct*Devices` config list against the current physical inventory of approved
units.

**Incident-response runbook:** identical structure to the parent scenario's operations and tuning runbook, with the
same addition the removable-media sibling documents: if Advanced Hunting shows more distinct
`DeviceName` values presenting an approved vendorId+productId pair than the count of
physically-issued units, treat this as a suspected impersonation - remove the device entry from the
config and re-run the deploy script immediately, then investigate before re-approving.

**Operational reminder specific to this fragment:** if
*Defender for Endpoint Device Control (macOS): Apple/Portable/Bluetooth Device Coverage*'s own
`Add-MacPortableDeviceCoverage.ps1 -Force` is ever re-run for a family after this fragment, re-run
this fragment's own deploy script immediately afterward to restore the vendorId/productId
exceptions - `validate/Test-MacApplePortableVendorProductDeviceAllowlist.ps1` flags the drift
distinctly if this step is missed.

## Rollback and decommission

See the rollback runbook for the full staged procedure. Quick reference: to revoke one device, remove its
entry from the relevant family's array in the config file and re-run
`deploy/Add-MacApplePortableVendorProductDeviceAllowlist.ps1` (orphan cleanup is automatic, no
`-Force` needed); to remove every Apple/Portable vendorId/productId device exception at once, run
`./deploy/Remove-MacApplePortableVendorProductDeviceAllowlist.ps1`.

## References

1. Device Control for macOS (Settings/Clause/Query reference tables - `groupId` "Match if a device
   is a member of another group... The group must be defined within the policy before the clause.";
   `vendorId`/`productId` "Four digit hexadecimal string"; `primaryId` values `apple_devices`/
   `portable_devices`; Query `any`/`or` synonymy; `includeGroups` AND / `excludeGroups` OR
   semantics), re-fetched directly during this fragment's own build -
   <https://learn.microsoft.com/defender-endpoint/mac-device-control-overview>
2. Sample macOS device control policy - `deny_all_bluetooth_devices_except_samsung.json` (the
   `primaryId`+`vendorId`+`productId` AND-clause exception-group shape this fragment generalizes a
   second time, to `apple_devices`/`portable_devices`) -
   <https://github.com/microsoft/mdatp-devicecontrol/blob/main/macOS/policy/samples/deny_all_bluetooth_devices_except_samsung.json>
3. Sample macOS device control policy - `audit_all_apple_devices_except_serial_numbers.json`
   (re-fetched directly during this fragment's build; confirmed `serialNumber`/`or`/`excludeGroups`
   matching only - no `vendorId`/`productId` usage for `apple_devices`) -
   <https://github.com/microsoft/mdatp-devicecontrol/blob/main/macOS/policy/samples/audit_all_apple_devices_except_serial_numbers.json>
4. Sample macOS device control policy - `deny_mobile_devices.json` (re-fetched directly during this
   fragment's build; confirmed `primaryId`-only catch-all matching for both `apple_devices` and
   `portable_devices` - no `vendorId`/`productId` usage) -
   <https://github.com/microsoft/mdatp-devicecontrol/blob/main/macOS/policy/samples/deny_mobile_devices.json>
5. RFC 4122, Section 4.3 - Algorithm for Creating a Name-Based UUID (version 5, SHA-1) -
   <https://www.rfc-editor.org/rfc/rfc4122#section-4.3>
6. *Defender for Endpoint Device Control (macOS): Apple/Portable/Bluetooth Device Coverage* - the
   prerequisite fragment whose `ApprovedAppleDevices`/`ApprovedPortableDevices` groups and Allow
   rules this fragment extends; see that scenario's own references for the shared macOS
   device-control citations not repeated here.
7. *Defender for Endpoint Device Control (macOS): vendorId/productId Compound-Matched Device Allowlist* - the direct
   precedent this fragment generalizes from `removable_media_devices` to `apple_devices`/
   `portable_devices`; same deterministic-GUID technique, same "extend the group, not the rule"
   reasoning.
8. *Defender for Endpoint Device Control (macOS): Bluetooth Approved-Device Allowlist* - the sibling
   fragment whose own disclosed-and-detected cross-fragment ordering hazard (the design notes there)
   this fragment's own, more severe variant follows the same resolution pattern for.

> Re-verify all links, and especially the vendorId/productId-for-Apple/Portable VERIFY and the
> `payload` PATCH replace-vs-merge semantics, against current Microsoft Learn and a pilot tenant
> before a customer-facing assessment or sale.