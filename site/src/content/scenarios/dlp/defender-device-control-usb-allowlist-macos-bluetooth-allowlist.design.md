---
part: "design"
parent: "dlp/defender-device-control-usb-allowlist-macos-bluetooth-allowlist"
---
## 1. Problem statement

`scenarios/dlp/defender-device-control-usb-allowlist-macos-portable-device-coverage/` closes the
Apple/Portable/Bluetooth invisibility gap left by the parent removable-media-only policy, but ships
Bluetooth as default-deny-only, no exceptions, a deliberate, disclosed scope decision (that
fragment's `design.md` §5) made because Microsoft's own worked exception sample for the
`bluetooth_devices` family uses a structurally different matching model (`vendorId`+`productId`
AND'd in one group) than the OR'd `serialNumber` pattern used for Apple/Portable devices. This
fragment closes that follow-up, tracked in `PROGRESS.md`, by adding exactly the exception mechanism
Microsoft's own sample demonstrates, no more, no less.

## 2. Design goals

1. **Reproduce Microsoft's own worked sample shape exactly, not a generalized approximation.** The
   `deny_all_bluetooth_devices_except_samsung.json` sample (fetched directly from GitHub during this
   fragment's build, §3) is the only confirmed reference for a Bluetooth exception; this fragment's
   group/rule shapes match it clause-for-clause and entry-for-entry, adapted only where this shared
   policy's own already-established `defaultEnforcement` setting requires a difference (§4).
2. **Extend the existing shared rule, don't create a competing one.** Per this repository's own
   established precedent (design goal 1 of the portable-device-coverage fragment this one extends),
   modifying the existing `Deny-AllBluetoothDevices` rule's `excludeGroups` in place is the only
   conflict-free way to add an exception, a second, independent Bluetooth rule targeting an
   overlapping device set has no documented precedence semantics against the first.
3. **Preserve every existing group/rule exactly**, including the very entries of the rule this
   fragment modifies. The deploy script reproduces `Deny-AllBluetoothDevices`'s two entries
   byte-for-byte from the live object (not re-derived from a hardcoded literal), see §4.
4. **Cap scope at exactly one approved device in v1**, matching the PROGRESS.md follow-up's own
   framing and Microsoft's sample (one device, "Samsung Galaxy S21"). Explicitly refuse, not
   silently mishandle, more than one configured device, per `AGENTS.md` §4's grounding discipline
   (§6, §8).
5. **State the model-not-unit identifier weakness and the cross-fragment ordering hazard honestly**,
   both disclosed in `README.md` §11 rather than left implicit.

## 3. Grounding: the confirmed worked sample

This fragment's entire group/rule shape is grounded against the raw content of
`deny_all_bluetooth_devices_except_samsung.json`, fetched directly during this build:

```json
{
  "groups": [
    { "$type": "device", "id": "...", "name": "All Bluetooth Devices",
      "query": { "$type": "or", "clauses": [{ "$type": "primaryId", "value": "bluetooth_devices" }] } },
    { "$type": "device", "id": "...", "name": "Samsung Galaxy S21",
      "query": { "$type": "and", "clauses": [
        { "$type": "primaryId", "value": "bluetooth_devices" },
        { "$type": "vendorId", "value": "0075" },
        { "$type": "productId", "value": "0100" }
      ] } }
  ],
  "rules": [
    { "id": "...", "name": "Deny all Bluetooth Devices",
      "includeGroups": ["<AllBluetoothDevices>"], "excludeGroups": ["<Samsung Galaxy S21>"],
      "entries": [ { "$type": "bluetoothDevice", "enforcement": { "$type": "deny" }, "access": [...] },
                   { "$type": "bluetoothDevice", "enforcement": { "$type": "auditDeny", "options": ["send_event","show_notification"] }, "access": [...] } ] },
    { "id": "...", "name": "Audit S21", "includeGroups": ["<Samsung Galaxy S21>"],
      "entries": [ { "$type": "bluetoothDevice", "enforcement": { "$type": "auditAllow", "options": ["send_event"] }, "access": [...] } ] }
  ],
  "settings": { "features": { "bluetoothDevice": { "disable": false } },
                "global": { "defaultEnforcement": "allow" },
                "ux": { "navigationTarget": "http://www.microsoft.com" } }
}
```

Two structural facts this fragment carries forward exactly: the exception group's `$type: "and"`
combining `primaryId`+`vendorId`+`productId` in one query, and the deny rule's `excludeGroups`
referencing that group by id. One fact this fragment deliberately does **not** carry forward: the
sample's own `"Audit S21"` rule has only an `auditAllow` entry, no plain `allow` entry, see §4 for
why.

Also confirmed directly from Microsoft's own "Access policy rule" reference table during this
build (not merely inferred): `includeGroups` combines multiple groups with **AND** semantics;
`excludeGroups` combines multiple groups with **OR** semantics. This is the specific fact that rules
out simply listing two device-exception groups in one allow rule's `includeGroups` to support more
than one approved device (§6, §8).

## 4. Why this fragment adds an explicit `allow` entry (a deliberate divergence from the sample)

The sample's `settings.global.defaultEnforcement` is `"allow"`, Microsoft's own documented default.
Under that default, a device excluded from the one deny rule needs no further rule to be granted
access; the sample's `"Audit S21"` rule exists purely to generate a **logged** allow event, not to
grant access that already exists by default.

This fragment's shared policy is different: the parent scenario explicitly sets
`defaultEnforcement = "deny"` (fail-closed defense in depth, `defender-device-control-usb-allowlist-
macos/design.md` §7) and no fragment in this chain changes it. Under a fail-closed default, a device
excluded from `Deny-AllBluetoothDevices` but matched by no other rule falls through to **deny**, not
allow, excluding it from the deny rule alone would not actually grant the approved device access.
This fragment therefore adds an explicit `Allow-ApprovedBluetoothDevice` rule with **both** an
`allow` entry and an `auditAllow` entry, reproducing the same "both paths audited" pattern the
parent scenario and the portable-device-coverage fragment already use for their own approved-device
rules (Apple `Allow-ApprovedAppleDevices`, Portable `Allow-ApprovedPortableDevices`), internal
consistency with this repository's own established pattern, not merely a literal reading of the one
external sample, which was authored against a different default.

## 5. Why exactly one approved device in v1

Two devices cannot both be referenced in one allow rule's `includeGroups` (AND semantics, §3)
without requiring a single connecting device to match both vendor+product pairs simultaneously,
which is impossible. Two independent workarounds exist, both deliberately deferred:

- **A separate allow rule + exception group per device.** Mechanically straightforward, but scales
  the shared policy's rule/group count linearly with approved-device count and needs a config-driven
  loop generating deterministic fixed GUIDs per array index, a heavier idempotency surface than
  this fragment's current fixed-four-GUID design, better scoped as its own follow-up once there's a
  concrete multi-device requirement to design against.
- **A combining group using `groupId` clauses** (Microsoft's Clause reference documents `groupId`:
  "Match if a device is a member of another group") to OR together multiple per-device sub-groups
  under one combining group, referenced once in `includeGroups`/`excludeGroups`. This is the same
  per-device sub-group + dynamic-`groupId`-clause-nesting technique this repository's sibling
  scenarios (`defender-device-control-usb-allowlist-macos-vendor-product-matching/`,
  `defender-device-control-usb-allowlist-macos-portable-device-coverage/design.md` §5) already defer
  as unverified complexity requiring a stable, deterministic GUID-per-device scheme not yet
  independently confirmed against a pilot tenant.

Rather than build either without a concrete second-device requirement to validate the design
against, this fragment ships exactly Microsoft's own demonstrated shape, one approved device, and
throws a clear, actionable error if `-ConfigPath` supplies more than one, rather than silently
picking one or mishandling the rest. Tracked as a follow-up in `PROGRESS.md`.

## 6. Why `vendorId`+`productId`, not `serialNumber`, and what that costs

No Microsoft-published sample pairs `serialNumber` with a `bluetooth_devices`-scoped group, the
only confirmed Bluetooth exception mechanism is `vendorId`+`productId`. This is a materially weaker
identifier than `serialNumber`, not merely a variant of the same risk: a `serialNumber` allowlist at
least requires acquiring or firmware-spoofing one specific approved physical unit's identity;
`vendorId`+`productId` are identical across every unit of a given model by design, so no forgery is
needed to get a second unit of the same approved model through, and deliberate impersonation is
plausible without physical access at all, since Bluetooth HCI/GAP vendor and product identifiers are
commonly software-configurable on inexpensive BLE development boards and some commodity dongles.
This is disclosed prominently in `README.md` §11 (with the operational triage recommendation in
§8), not treated as equivalent to the `serialNumber`-based allowlists elsewhere in this control
family. There is no stronger, Microsoft-documented per-unit Bluetooth identifier to fall back to in
this fragment.

## 7. Key decisions

| Decision | Choice | Rationale |
|---|---|---|
| Deploy surface | Same as both fragments beneath it, Microsoft Graph (`Connect-MgGraph`, app-only certificate), `Invoke-MgGraphRequest` against `v1.0` | Consistency; this fragment PATCHes the same shared object a third time. |
| Target object | The parent's existing `macOSCustomConfiguration`, located by `parentPolicyDisplayName` | Same one-payload-per-Mac architecture reasoning as the portable-device-coverage fragment's own `design.md` §3. |
| Extraction/write mechanism | Regex over the known, fixed `<key>policy</key><string>...</string>` shape | Same accepted trade-off both fragments beneath this one already document and use. |
| Prerequisite check | Refuse to run unless `AllBluetoothDevices` group and `Deny-AllBluetoothDevices` rule (fixed GUIDs) are both present | This fragment only adds an exception to existing Bluetooth coverage, it must never create Bluetooth coverage on its own, which would bypass the portable-device-coverage fragment's own deliberate design. |
| Deny-rule modification strategy | Rebuild the rule with `entries` reproduced verbatim from the live object, add `excludeGroups` | Preserves goal 3 (§2) exactly, no risk of silently drifting the entries this fragment doesn't own. |
| Approved-device matching | `vendorId`+`productId`, AND'd, exactly one device | §5, §6 above. |
| Allow-rule shape | Explicit `allow` + `auditAllow` entries (not sample-literal `auditAllow`-only) | §4 above, required by this shared policy's own fail-closed default. |
| GUIDs | Two new fixed, source-controlled GUIDs (one group, one rule) in the same `3333-...` (Bluetooth-family) namespace the portable-device-coverage fragment established, distinct from its two existing Bluetooth GUIDs | Same idempotent-reconcile rationale as every sibling fragment; namespace continuity documents the family relationship directly in the GUID values themselves. |
| Multi-device support | Deferred (§5) | Needs a concrete second-device requirement and, likely, a pilot-tenant-verified `groupId`-nesting design, not guessed here. |
| Ordering hazard | Disclosed, not engineered around by modifying the prerequisite fragment's own script | See §8 below. |

## 8. Why the ordering hazard is disclosed, not silently fixed by editing the prior fragment

`Add-MacPortableDeviceCoverage.ps1` (the portable-device-coverage fragment's own deploy script)
unconditionally rebuilds `Deny-AllBluetoothDevices` with `ExcludeGroupId = $null` on every run, 
that script has no knowledge this fragment exists, and was already reviewed and finalized before
this fragment's PROGRESS.md follow-up was written. Two options were considered:

1. **Modify the earlier, already-reviewed script to be aware of this fragment's exclusion.** Rejected
   for this v1: it reopens a finished, four-lens-reviewed fragment to add cross-fragment coupling in
   the opposite direction (a foundational script depending on knowledge of an optional extension
   three layers up), which is a larger and riskier change than this fragment's own stated scope, and
   isn't the kind of small, targeted backport this repository otherwise reserves for genuine
   corrections (compare the doc-only prerequisite backport tracked elsewhere in `PROGRESS.md`, not a
   behavioral change to a shared script).
2. **Disclose the hazard explicitly and detect it at validation time.** Adopted. This fragment's
   `deploy/Add-MacBluetoothDeviceAllowlist.ps1` always rebuilds `Deny-AllBluetoothDevices` itself on
   every run (so running this fragment last always produces the correct state), and
   `validate/Test-MacBluetoothDeviceAllowlist.ps1` distinguishes "never configured" from "drifted
   because the prerequisite fragment's `-Force` ran afterward" as two different check outcomes, with
   the exact remediation named in the failure message. This is the same "state genuinely open gaps
   honestly rather than resolve them by guessing or by an out-of-scope fix" discipline `AGENTS.md`
   §4 establishes, applied to an operational/sequencing gap rather than a product-fact gap.

## 9. Non-goals

- This scenario does not support more than one approved Bluetooth device (§5).
- This scenario does not resolve the `vendorId`/`productId`-identifies-a-model-not-a-unit limitation
, no stronger mechanism is Microsoft-documented for this device family (§6).
- This scenario does not modify `defender-device-control-usb-allowlist-macos-portable-device-
  coverage/deploy/Add-MacPortableDeviceCoverage.ps1` to make it aware of this fragment (§8), the
  ordering hazard is disclosed and detected, not engineered away by coupling the two scripts.
- This scenario does not deploy via JAMF as a separate build. Because the underlying
  `deviceControl.policy` JSON schema is identical across the Intune and JAMF deployment paths (the
  same reasoning the portable-device-coverage fragment's own `design.md` §8 already establishes for
  its own scope), the group/rule shape this fragment grounds applies equally to
  `scenarios/dlp/defender-device-control-usb-allowlist-macos-jamf/`'s JAMF-managed sibling, a JAMF
  admin can apply the identical JSON delta through that scenario's own manual-console workflow.
- This scenario does not address `serialNumber`, `mediaSerialNumber`/`mediaProductName`/
  `mediaApplicationId`, or `encryption: apfs` clauses for Bluetooth, out of scope, matching every
  sibling fragment's own non-goals.

## References

See `README.md` §12 for the full citation list. The exception-group and rule shapes in this document
are grounded against a direct fetch of Microsoft's own published sample policy JSON and the official
"Device Control for macOS" reference tables, both retrieved during this fragment's own build.
