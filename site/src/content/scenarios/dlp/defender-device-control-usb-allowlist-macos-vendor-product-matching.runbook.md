---
part: "runbook"
parent: "dlp/defender-device-control-usb-allowlist-macos-vendor-product-matching"
---
## Implementation steps

### Portal path (for a first manual walkthrough / to validate intent before scripting)

1. Confirm the parent scenario is already deployed: Intune admin center → **Devices** → **macOS** →
   **Configuration profiles** → confirm `Device Control (macOS) - USB Removable Media Default-Deny
   Allowlist` exists.
2. Obtain the vendor ID and product ID for each device to approve - on a Mac with the device
   connected: **Apple menu → About This Mac → More Info → System Report → USB**, or
   `system_profiler SPUSBDataType` in Terminal; note the `Vendor ID` and `Product ID` hex values.
3. Edit the profile's `.mobileconfig`: add one `groups[]` entry per device (shape: the design notes
   row 1) and one `groupId` clause per device to `ApprovedBackupDrives`' existing `query.clauses`
   array (shape: the design notes row 2), preserving every existing `serialNumber` clause unchanged.
4. Re-upload the modified `.mobileconfig` as the profile's configuration file, replacing the
   existing one.
5. **Save**. No assignment change is needed - the profile's existing assignment already governs
   which endpoints receive this update.

### Script path (idempotent, parameterized, dry-run capable)

```powershell
# 1. Connect (certificate app-only - see docs/automation-surface.md Section 3)
Connect-MgGraph -ClientId $AppId -TenantId $TenantId -CertificateThumbprint $Thumbprint

# 2. Edit deploy/config/mac-vendor-product-device-allowlist.sample.json (or copy it) with your
#    approved devices' vendorId/productId pairs.

# 3. Dry run - reports every change, makes none
./deploy/Add-MacVendorProductDeviceAllowlist.ps1 `
    -ConfigPath ./deploy/config/mac-vendor-product-device-allowlist.sample.json `
    -WhatIf

# 4. Deploy
./deploy/Add-MacVendorProductDeviceAllowlist.ps1 `
    -ConfigPath ./deploy/config/mac-vendor-product-device-allowlist.sample.json

# 5. Validate
./validate/Test-MacVendorProductDeviceAllowlist.ps1 `
    -ConfigPath ./deploy/config/mac-vendor-product-device-allowlist.sample.json

# 6. To revoke a device: remove its entry from the config file and re-run step 4 - the deploy
#    script detects and removes the now-orphaned sub-group automatically, no -Force required.
```

The deploy script uses the Microsoft Graph PowerShell SDK (`Invoke-MgGraphRequest` against the same
`macOSCustomConfiguration` resource the parent scenario created) - automation surface 3 per
[Automation surface, section 1](/docs/automation-surface/#1-five-automation-surfaces-not-one-read-this-first). It never creates the parent policy and never changes its assignment.

## Configuration reference

| Setting | Location in `.mobileconfig` | Value |
|---|---|---|
| Per-device sub-group | `deviceControl.policy.groups[]` (inserted immediately before `ApprovedBackupDrives`) | `{"$type":"device","id":"<UUIDv5(namespace, vendorId:productId)>","name":"VendorProductMatch-<label>","query":{"$type":"and","clauses":[{"$type":"primaryId","value":"removable_media_devices"},{"$type":"vendorId","value":"<hex>"},{"$type":"productId","value":"<hex>"}]}}` |
| `ApprovedBackupDrives` group edit | `deviceControl.policy.groups[].query.clauses[]` (existing `ApprovedBackupDrives` entry) | One `{"$type":"groupId","value":"<sub-group id>"}` appended per configured device, alongside the parent's pre-existing `serialNumber` clauses (`query.$type` stays `"any"`) |
| Sub-group id derivation | N/A - computed, not stored as a separate object | RFC 4122 the architecture.3 version-5 UUID: `SHA1(namespace_bytes ++ UTF8("mac-vendor-product-match/v1/<vendorId>:<productId>"))`, version/variant bits patched. Namespace: `8f3a2b10-8f2e-4c4a-9b8b-2f1a6c9d7e10` (fixed, this fragment's own constant). See the design notes. |
| Rules | *(unchanged)* - `Allow-ApprovedBackupDrives` and `Deny-AllOtherRemovableStorage` | Not modified by this fragment; both already key off `ApprovedBackupDrives`' group id. |

All group ids this fragment creates are **deterministic**, not fixed literals - the same
`vendorId`+`productId` pair always produces the same id, on any machine, with no state file. Full
cmdlet/REST/schema grounding: the deploy script's `.NOTES` block and the references below.

## Operations and tuning

**Deployment sequence:** this fragment ships directly into the parent policy's existing assignment
scope - there is no separate rollout stage of its own. Add a vendorId/productId device only after the
parent policy is already assigned to the intended endpoints.

**KPIs to watch (first 30 days):** identical framing to the parent scenario's operations and tuning, with one addition -
track `Allow-ApprovedBackupDrives` `auditAllow` event volume **per configured vendorId+productId
pair** against the number of physically-issued units of that model. Because this mechanism approves a
*model*, not a unit, a materially higher distinct-device count than issued units for one pair is
the practical detection signal for an unauthorized unit of the same model, the same operational
pattern already established for the Bluetooth sibling fragment's own model-level exception.

**Alert routing:** unchanged - same Advanced Hunting/`DeviceEvents` and Microsoft Defender Streaming
API/Sentinel connector paths as the parent scenario's operations and tuning.

**Review cadence:** quarterly at minimum, same as the parent scenario; re-run
`validate/Test-MacVendorProductDeviceAllowlist.ps1` as part of that review, and cross-check the
`vendorProductDevices` config list against the current physical inventory of approved units - a
device model approved here but decommissioned needs its config entry removed, not merely
forgotten.

**Incident-response runbook:** identical structure to the parent scenario's operations and tuning runbook, with one
addition specific to this mechanism's weaker guarantee: if Advanced Hunting shows more distinct
`DeviceName` values presenting an approved vendorId+productId pair than the count of physically-issued
units, treat this as a suspected impersonation, not a false positive - remove the device entry from
the config and re-run the deploy script immediately, then investigate before re-approving.

## Rollback and decommission

See the rollback runbook for the full staged procedure. Quick reference: to revoke one device, remove its
entry from the config file and re-run `deploy/Add-MacVendorProductDeviceAllowlist.ps1` (orphan
cleanup is automatic, no `-Force` needed); to remove every vendorId/productId device exception at
once, run `./deploy/Remove-MacVendorProductDeviceAllowlist.ps1`.

## References

1. Device Control for macOS (Clause reference table - `groupId` "Match if a device is a member of
   another group... The group must be defined within the policy before the clause."; `vendorId`/
   `productId` "Four digit hexadecimal string"; Query `all`/`any`/`not` types; Access policy rule
   `includeGroups` AND / `excludeGroups` OR semantics) - <https://learn.microsoft.com/defender-endpoint/mac-device-control-overview>
2. Sample macOS device control policy - `deny_all_bluetooth_devices_except_samsung.json` (the
   `primaryId`+`vendorId`+`productId` AND-clause exception-group shape this fragment generalizes to
   the `removable_media_devices` family and to N devices; confirmed by direct fetch of the raw file
   during this fragment's build) - <https://github.com/microsoft/mdatp-devicecontrol/blob/main/macOS/policy/samples/deny_all_bluetooth_devices_except_samsung.json>
3. Sample macOS device control policy - `deny_removable_media_except_kingston.json` (single-`vendorId`
   exception group scoped to `removable_media_devices`, confirmed by direct fetch of the raw file
   during this fragment's build) - <https://github.com/microsoft/mdatp-devicecontrol/blob/main/macOS/policy/samples/deny_removable_media_except_kingston.json>
4. RFC 4122, Section 4.3 - Algorithm for Creating a Name-Based UUID (version 5, SHA-1) - <https://www.rfc-editor.org/rfc/rfc4122#section-4.3>
5. *Defender for Endpoint Device Control (macOS): USB Default-Deny Allowlist* - the parent scenario this fragment
   extends; see that scenario's own references for the shared macOS device-control citations
   (`macOSCustomConfiguration` Graph resource, Full Disk Access/`DC_in_dlp` prerequisites, Advanced
   Hunting query, licensing).
6. *Defender for Endpoint Device Control (macOS): Bluetooth Approved-Device Allowlist* - the sibling
   fragment whose single-device vendorId+productId exception this fragment's own AND-clause shape
   directly follows, and whose "model, not unit" disclosure this fragment's the known limitations mirrors.

> Re-verify all links, and especially the multi-sub-group `groupId` composition VERIFY, against
> current Microsoft Learn and a pilot tenant before a customer-facing assessment or sale.