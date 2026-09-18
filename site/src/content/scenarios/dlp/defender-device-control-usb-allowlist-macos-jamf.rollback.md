---
part: "rollback"
parent: "dlp/defender-device-control-usb-allowlist-macos-jamf"
---
## Why this rollback procedure differs from both siblings

Both the Windows and Intune-managed-macOS siblings deploy through an API this repo's own scripts
can also un-deploy (`Remove-*.ps1` scripts calling Microsoft Graph). This scenario has no such
object to delete, the policy lives inside a JAMF Pro custom-schema property that was populated by
hand (`README.md` §5, Steps 3-4). Every stage below is therefore a **JAMF Pro console action**, not
a script.

## Recommended sequence

A device control policy change affects live removable-storage access on every assigned Mac, so
roll back in stages rather than deleting outright, identical staging discipline to both siblings.

### Stage 1, Unscope (reversible, minutes)

In the JAMF Pro console, open the "MDE Preferences" profile (`README.md` §5) → **Scope** tab →
remove the pilot Computer Group (or clear the scope entirely). This stops the policy from being
pushed to any new or re-checking-in Mac; Macs that already received the profile keep enforcing it
until their next check-in re-syncs the (now-unscoped) profile.

Use this stage for: a false-positive incident affecting a business-critical workflow that needs
immediate relief, a change freeze, or a temporary business exception that doesn't warrant clearing
the Device Control Policy JSON itself.

Re-scope instantly by re-adding the Computer Group and selecting **Save**.

### Stage 2, Clear the Device Control Policy JSON (broader rollback, still reversible)

In the same profile, clear the **Device Control Policy** text box (§5 Step 3) and select **Save**.
This removes the device-control policy content from the profile entirely while leaving the rest of
the "MDE Preferences" profile (onboarding, antivirus/EDR settings, etc.) untouched, device control
enforcement stops on next check-in, but nothing else about the Mac's Defender for Endpoint
configuration changes.

Re-establish it by re-pasting the contents of `deploy/output/jamf-device-control-policy.json`
(regenerate first with `deploy/New-JamfDeviceControlPolicyJson.ps1` if the config has changed since
it was last written) and saving.

### Stage 3, Disable the Device Control engine (broadest, still reversible)

Under **Data Loss Prevention (DLP)** → **Features**, set `DC_in_dlp`'s **State** back to `disabled`
(§5 Step 2). This disables the Device Control engine itself, not just this scenario's specific
policy, do this only if no other device-control policy on these Macs should remain active either.

### Stage 4, Remove the local artifact (not reversible without re-running the deploy script)

```powershell
Remove-Item ./deploy/output/jamf-device-control-policy.json
```

This deletes the locally generated JSON file only, it has **no effect** on anything already
configured in JAMF Pro (Stages 1-3 above are the only way to change what a Mac actually enforces).
Re-establishing the local artifact means re-running
`deploy/New-JamfDeviceControlPolicyJson.ps1` from the original config.

## What rollback does **not** undo

- **Advanced Hunting / `DeviceEvents` history.** Allow and deny audit events already generated are
  retained per their own retention window regardless of policy state.
- **Access already denied or allowed.** A copy that was denied while the policy was enforcing was
  not written to the removable device; a later rollback does not retroactively complete it.
- **Device onboarding, or the Full Disk Access (PPPC) profile for `com.microsoft.dlp.daemon`.**
  This scenario does not create or manage either, rollback here has no effect on them. In
  particular, clearing the Device Control Policy property does **not** revoke the Full Disk Access
  grant; that is a separate profile with its own lifecycle.
- **The JAMF Pro Computer Group membership, or the physical approved drives.** This scenario does
  not create or manage the pilot Computer Group or the approved-drive inventory.
- **Any other setting in the shared "MDE Preferences" `com.microsoft.wdav` profile** (onboarding,
  antivirus/EDR configuration, etc.), Stages 1-3 above are scoped to the Device Control property
  and the `DC_in_dlp` feature flag only.

## Verification after rollback

1. In the JAMF Pro console, confirm the profile's **Scope** (Stage 1), **Device Control Policy**
   text box (Stage 2), and `DC_in_dlp` **State** (Stage 3) reflect the intended post-rollback state.
2. On a pilot Mac, after its next check-in:
   ```sh
   mdatp health --details device_control
   ```
   Confirm `v2_state` reflects the change (e.g. no longer `"enabled"` after Stage 3, or the policy
   content changed after Stage 2).
3. Functional test: plug in a previously-denied drive and confirm the expected post-rollback
   behavior (e.g. no longer blocked, if the control was fully removed).
