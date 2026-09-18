---
part: "rollback"
parent: "dlp/defender-device-control-usb-allowlist-macos-jamf-vendor-product-matching"
---
## Why this rollback procedure is identical in shape to the base JAMF scenario's

This fragment adds no new JAMF Pro profile, property, or feature toggle — it only changes **what
JSON gets pasted** into the Device Control Policy property the base scenario's own `README.md` §5
already establishes. Every stage below is therefore, like the base scenario's own rollback, a **JAMF
Pro console action**, not a script action against a live object this repo's tooling can delete.

## Recommended sequence

A device control policy change affects live removable-storage access on every assigned Mac, so roll
back in stages rather than deleting outright — identical staging discipline to every scenario in this
family.

### Stage 1 — Unscope (reversible, minutes)

Identical to the base scenario's `rollback.md` Stage 1: in the JAMF Pro console, remove the pilot
Computer Group from the profile's **Scope** tab (or clear the scope entirely). Use this for an
immediate-relief situation that doesn't warrant touching the pasted JSON itself.

### Stage 2 — Revert to the base scenario's serialNumber-only output (targeted rollback)

If the vendor/product-matching capability itself is the problem (e.g. an incident traced to a
device-model-level false match, §11), you do not need to clear the Device Control Policy property
entirely. Instead:

```powershell
./defender-device-control-usb-allowlist-macos-jamf/deploy/New-JamfDeviceControlPolicyJson.ps1 `
    -ConfigPath ./defender-device-control-usb-allowlist-macos-jamf/deploy/config/mac-device-control-usb-allowlist-jamf.sample.json `
    -Force
```

Paste the resulting artifact into the same **Device Control Policy** text box, overwriting this
fragment's combined output. This removes every `VendorProductMatch-` sub-group and its `groupId`
clause from `ApprovedBackupDrives` while leaving every `serialNumber`-based approval, both rules, and
the catch-all group untouched — a narrower rollback than clearing the property entirely.

### Stage 3 — Clear the Device Control Policy JSON (broader rollback, still reversible)

Identical to the base scenario's `rollback.md` Stage 2: clear the **Device Control Policy** text box
and **Save**. Removes all device-control policy content (both matching mechanisms) while leaving the
rest of the "MDE Preferences" profile untouched.

Re-establish by re-pasting `deploy/output/jamf-device-control-policy.json` (regenerate first with
this fragment's own deploy script if the config has changed) and saving.

### Stage 4 — Disable the Device Control engine (broadest, still reversible)

Identical to the base scenario's `rollback.md` Stage 3: set `DC_in_dlp`'s **State** back to
`disabled`. Do this only if no other device-control policy on these Macs should remain active either.

### Stage 5 — Remove the local artifact (not reversible without re-running the deploy script)

```powershell
Remove-Item ./deploy/output/jamf-device-control-policy.json
```

Deletes the locally generated JSON file only — no effect on anything already configured in JAMF Pro.

## What rollback does **not** undo

Identical list to the base JAMF scenario's `rollback.md`:

- **Advanced Hunting / `DeviceEvents` history.** Retained per its own retention window regardless of
  policy state.
- **Access already denied or allowed.** Not retroactively completed by a later rollback.
- **Device onboarding, or the Full Disk Access (PPPC) profile.** This scenario does not create or
  manage either.
- **The JAMF Pro Computer Group membership, or the physical approved drives.** Not created or managed
  by this scenario.
- **Any other setting in the shared "MDE Preferences" `com.microsoft.wdav` profile.** Stages 1–4 above
  are scoped to the Device Control property and the `DC_in_dlp` feature flag only.

## Verification after rollback

1. In the JAMF Pro console, confirm the profile's **Scope**, **Device Control Policy** text box
   content, and `DC_in_dlp` **State** reflect the intended post-rollback state.
2. If you performed Stage 2 (revert to serialNumber-only), run
   `defender-device-control-usb-allowlist-macos-jamf/validate/Test-JamfDeviceControlPolicyJson.ps1`
   against the reverted artifact to confirm it matches the base scenario's expected shape.
3. On a pilot Mac, after its next check-in: `mdatp health --details device_control` — confirm
   `v2_state` reflects the change.
4. Functional test: plug in a device previously approved only by `vendorId`/`productId` and confirm
   it is now denied (if Stage 2, 3, or 4 was performed) while any `serialNumber`-approved device
   (Stage 2 only) remains allowed.
