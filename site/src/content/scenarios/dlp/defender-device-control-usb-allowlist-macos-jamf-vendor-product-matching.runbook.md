---
part: "runbook"
parent: "dlp/defender-device-control-usb-allowlist-macos-jamf-vendor-product-matching"
---
## Implementation steps

### Step 0 - Prerequisites (one-time, not scripted by this fragment)

Confirm the base scenario's own Step 0 (onboarding + Full Disk Access) and Steps 2 (schema update,
`DC_in_dlp`) and 3 (adding the Device Control property) are already complete -
*Defender for Endpoint Device Control (macOS, JAMF-managed): USB Default-Deny Allowlist* (the implementation steps). This fragment only replaces **what
gets pasted** into the already-added Device Control Policy property; it does not add that property.

### Step 1 - Build the combined config (one-time or on every allowlist change)

Copy `deploy/config/mac-jamf-vendor-product-device-allowlist.sample.json`. Populate `approvedDevices`
with any serial-numbered drives (carry these over from the base scenario's own config if you're
upgrading from a serialNumber-only deployment) and `vendorProductDevices` with any devices identified
only by `vendorId`/`productId`. At least one entry across both lists is required.

### Step 2 - Generate and validate the policy JSON (scripted)

```powershell
# Dry run - reports what would be written, writes nothing
./deploy/New-JamfVendorProductDeviceAllowlistPolicyJson.ps1 `
    -ConfigPath ./deploy/config/mac-jamf-vendor-product-device-allowlist.sample.json `
    -WhatIf

# Generate the artifact (pass -Force if the base scenario's own output already exists at this path)
./deploy/New-JamfVendorProductDeviceAllowlistPolicyJson.ps1 `
    -ConfigPath ./deploy/config/mac-jamf-vendor-product-device-allowlist.sample.json `
    -Force

# (Optional, run ON an already-onboarded Mac's Terminal) - also locally schema-validate:
./deploy/New-JamfVendorProductDeviceAllowlistPolicyJson.ps1 `
    -ConfigPath ./deploy/config/mac-jamf-vendor-product-device-allowlist.sample.json `
    -Force -ValidateWithMdatp

# Structural re-check at any time
./validate/Test-JamfVendorProductDeviceAllowlistPolicyJson.ps1 `
    -ConfigPath ./deploy/config/mac-jamf-vendor-product-device-allowlist.sample.json
```

This produces `deploy/output/jamf-device-control-policy.json` - the **same default path** the base
scenario's own script writes to, since this artifact supersedes it. Automation surface: local
file generation only, no Graph or JAMF Pro API call.

### Step 3 - Paste the JSON into JAMF Pro (manual, JAMF Pro console)

Follow *Defender for Endpoint Device Control (macOS, JAMF-managed): USB Default-Deny Allowlist* (the implementation steps), Step 3: open the existing
**Device Control Policy** text box on the `com.microsoft.wdav` custom-schema profile, replace its
contents with `deploy/output/jamf-device-control-policy.json`, and **Save**. This is a full
replacement of the prior content, not an append - expected, since this fragment's artifact already
contains everything the prior artifact did (the prerequisites, the design notes, backward-compatible-output row).

### Step 4 - Confirm scope (manual, JAMF Pro console)

Confirm the profile's **Scope** tab still targets the intended pilot Computer Group (unchanged by
this fragment) - see the base scenario's the implementation steps, Step 4.

## Configuration reference

| Setting | Location in the generated JSON | Value |
|---|---|---|
| Enable Device Control engine | JAMF Pro GUI property, **not** in this JSON | `{"name": "DC_in_dlp", "state": "enabled"}` - unchanged from the base scenario, not re-set by this fragment. |
| Group: `AllRemovableStorage` (catch-all) | `groups[0]` | Unchanged from the base scenario. |
| Group: `VendorProductMatch-<label>` (one per `vendorProductDevices` entry) | `groups[]`, inserted before `ApprovedBackupDrives` | `query: {"$type":"and","clauses":[{"$type":"primaryId","value":"removable_media_devices"},{"$type":"vendorId","value":"<hex>"},{"$type":"productId","value":"<hex>"}]}`; `id` is a deterministic UUIDv5 of `vendorId:productId`. |
| Group: `ApprovedBackupDrives` | `groups[]` | `query: {"$type":"any","clauses":[...serialNumber clauses from approvedDevices..., ...groupId clauses referencing each VendorProductMatch- sub-group...]}` |
| Rule: `Allow-ApprovedBackupDrives` | `rules[0]` | Unchanged from the base scenario - `includeGroups=[ApprovedBackupDrives]`; `allow` + `auditAllow(send_event)`, `access=[read,write,execute]`. |
| Rule: `Deny-AllOtherRemovableStorage` | `rules[1]` | Unchanged from the base scenario. |

All fixed group/rule `id` values are byte-identical to the base JAMF scenario's and the Intune
sibling's own constants; per-device sub-group ids are deterministic and byte-identical across
Intune and JAMF for the same `vendorId`+`productId` pair. Full cmdlet/schema
grounding: the deploy script's `.NOTES` block and the references below.

## Operations and tuning

**Deployment sequence:** identical staged-rollout discipline to the base scenario's operations and tuning - Computer
Group scope is the only rollout lever, set entirely by hand in the JAMF Pro console.

**Change management is manual, identical to the base scenario's operations and tuning** - an allowlist change (adding or
removing either a `serialNumber` or a `vendorId`/`productId` entry) means: update `-ConfigPath`,
re-run `deploy/New-JamfVendorProductDeviceAllowlistPolicyJson.ps1 -Force`, then re-paste the full
artifact into the JAMF Pro console. Track allowlist changes in whatever
change-management/ticketing process governs JAMF Pro profile edits generally.

**KPIs to watch (first 30 days):** identical framing to every sibling - deny-path volume/distribution
after widening, allow-path volume per approved drive (broken out by matching mechanism -
`serialNumber` vs. `vendorId`/`productId` - to see which mechanism a given business unit actually
relies on), and `auditDeny` events immediately followed by a new onboarding/exception request.

**Alert routing:** identical to every sibling - Advanced Hunting/`DeviceEvents`, Microsoft Defender
Streaming API, or the Microsoft Defender XDR connector for Microsoft Sentinel.

**Review cadence:** quarterly at minimum; re-run `validate/
Test-JamfVendorProductDeviceAllowlistPolicyJson.ps1` as part of that review, and separately confirm
in the JAMF Pro console that no one has hand-edited the pasted JSON out of band. Review the
vendorId/productId-matched entries with extra scrutiny relative to `serialNumber` entries - a device
model match is a weaker guarantee than a unique physical unit.

**Incident-response runbook:** identical structure to the base scenario's operations and tuning, with one addition: if
an incident involves a device approved only by `vendorId`/`productId`, treat "is this the actual
physical unit, or just a device of the same model" as an open question the policy itself cannot
answer - corroborate with independent evidence (asset tag, custody log) before concluding the
connection was authorized.

## Rollback and decommission

See the rollback runbook for the full staged procedure. Identical mechanics to the base JAMF scenario's own
rollback (entirely JAMF Pro console actions - there is no API object to delete), with one addition:
reverting to the base scenario's own output (dropping vendor/product matching entirely) is itself a
valid, simpler rollback step - see the rollback runbook.

## References

1. Device Control for macOS (Clause reference table - `groupId` "Match if a device is a member of
   another group. The value represents the UUID of the group to match against. The group must be
   defined within the policy before the clause."; `vendorId`/`productId` "Four digit hexadecimal
   string"; query `any`/`or` OR semantics; Prepare your endpoints - Full Disk Access, `DC_in_dlp`,
   minimum client version `101.91.92`) - <https://learn.microsoft.com/defender-endpoint/mac-device-control-overview>
2. Sample macOS device control policies (`deny_all_bluetooth_devices_except_samsung.json` - the
   `vendorId`+`productId` AND-clause exception-group shape this fragment generalizes to N devices and
   to the `removable_media_devices` family) - <https://github.com/microsoft/mdatp-devicecontrol/blob/main/macOS/policy/samples/deny_all_bluetooth_devices_except_samsung.json>
3. Deploy and manage Device Control using JAMF (Steps 1-4: author JSON, validate with `mdatp`, update
   the Defender for Endpoint preferences schema, add the Device Control Policy property; states the
   Microsoft 365 E3 / Defender for Endpoint Plan 1 licensing minimum; frames JAMF as a third-party
   tool with no Microsoft-provided API guidance) - <https://learn.microsoft.com/defender-endpoint/mac-device-control-jamf>
4. Device control policies in Microsoft Defender for Endpoint ("The rules and policies are combined
   into a single JSON and configured by using JAMF as the device control policy"; shared
   groups/rules/entries concepts across Windows and macOS) - <https://learn.microsoft.com/defender-endpoint/device-control-policies>
5. RFC 4122, Section 4.3 (name-based UUID, algorithm for creating a version-5 UUID) - <https://www.rfc-editor.org/rfc/rfc4122#section-4.3>
6. *Defender for Endpoint Device Control (macOS, JAMF-managed): USB Default-Deny Allowlist* - the base JAMF scenario this
   fragment extends; see that scenario's own references for the onboarding, Full Disk Access, and
   JAMF-console-procedure citations.
7. *Defender for Endpoint Device Control (macOS): vendorId/productId Compound-Matched Device Allowlist* - the Intune
   sibling this fragment's group-generation logic and deterministic-UUID scheme are ported from
   verbatim; see that scenario's own references for the Intune/Graph-side citations.

> Re-verify all links, and especially the known limitations's open VERIFYs, against current Microsoft Learn, JAMF's own
> developer documentation, and a pilot tenant before a customer-facing assessment or sale.