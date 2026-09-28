---
part: "runbook"
parent: "dlp/defender-device-control-usb-allowlist-macos-jamf"
---
## Implementation steps

### Step 0 - Confirm onboarding and Full Disk Access first (one-time, not scripted)

Target Macs must already be onboarded to Microsoft Defender for Endpoint via JAMF and have a PPPC
profile granting **Full Disk Access** to `com.microsoft.dlp.daemon` -
[Microsoft Defender portal](https://security.microsoft.com) → **Assets** → **Devices** to confirm
onboarding; deploy/update `fulldisk.mobileconfig` via the JAMF Pro console if not already present,
following `mac-jamfpro-policies` Step 6, also referenced directly from the
Purview-specific JAMF onboarding guide.

### Step 1 - Generate and validate the policy JSON (scripted)

```powershell
# 1. Edit deploy/config/mac-device-control-usb-allowlist-jamf.sample.json (or copy it) with your
#    approved-device serial numbers.

# 2. Dry run - reports what would be written, writes nothing
./deploy/New-JamfDeviceControlPolicyJson.ps1 `
    -ConfigPath ./deploy/config/mac-device-control-usb-allowlist-jamf.sample.json `
    -WhatIf

# 3. Generate the artifact
./deploy/New-JamfDeviceControlPolicyJson.ps1 `
    -ConfigPath ./deploy/config/mac-device-control-usb-allowlist-jamf.sample.json

# 4. (Optional, run ON an already-onboarded Mac's Terminal) - also locally schema-validate:
./deploy/New-JamfDeviceControlPolicyJson.ps1 `
    -ConfigPath ./deploy/config/mac-device-control-usb-allowlist-jamf.sample.json `
    -ValidateWithMdatp

# 5. Structural re-check at any time
./validate/Test-JamfDeviceControlPolicyJson.ps1 `
    -ConfigPath ./deploy/config/mac-device-control-usb-allowlist-jamf.sample.json
```

This produces `deploy/output/jamf-device-control-policy.json` - plain JSON, ready to paste into the
JAMF Pro console in Step 4 below. Automation surface: local file generation only, no Graph or JAMF
Pro API call.

### Step 2 - Update the Defender for Endpoint preferences schema (manual, JAMF Pro console)

1. Download the latest `schema.json` from Microsoft's GitHub repository.
2. In JAMF Pro, open the existing **Application & Custom Settings** profile whose Preference Domain
   is `com.microsoft.wdav` and select **Edit schema** to re-upload the downloaded file.
3. Under **Preference Domain Properties**, enable **Data Loss Prevention (DLP)** →
   **Features** → set **Feature Name** to `DC_in_dlp`, **State** to `enabled`. This is a separate, easy-to-miss toggle from the Device Control policy
   itself - without it, the policy in Step 4 is inert.

### Step 3 - Add the Device Control property and paste the JSON (manual, JAMF Pro console)

1. Still on the same profile, select **Add/Remove properties**, select **Device Control**, and
   then select **Apply**.
2. Scroll to the **Device Control** property, select **Add/Remove properties** again, select
   **Device Control Policy**, and select **Apply**.
3. Open `deploy/output/jamf-device-control-policy.json` (Step 1) and paste its full contents into
   the **Device Control Policy** text box.
4. **Save** your changes.

### Step 4 - Scope to a pilot Computer Group (manual, JAMF Pro console)

Select the **Scope** tab and target a **pilot Computer Group** - never "All Computers" on a first
rollout, the same staged-rollout discipline as every scenario in this library. Select
**Save**.

## Configuration reference

| Setting | Location in the generated JSON | Value |
|---|---|---|
| Enable Device Control engine | JAMF Pro GUI property, **not** in this JSON | Data Loss Prevention (DLP) → Features → `{"name": "DC_in_dlp", "state": "enabled"}` - a separate schema property set in step 2 of the implementation steps, not part of `deploy/output/jamf-device-control-policy.json`. |
| Enable removable-media enforcement | `settings.features.removableMedia.disable` | `false` |
| Fail-closed default | `settings.global.defaultEnforcement` | `"deny"` |
| Group: `AllRemovableStorage` (catch-all) | `groups[0]` | `query: {"$type":"all","clauses":[{"$type":"primaryId","value":"removable_media_devices"}]}` |
| Group: `ApprovedBackupDrives` | `groups[1]` | `query: {"$type":"any","clauses":[{"$type":"serialNumber","value":"<serial>"}, ...]}` from config |
| Rule: `Allow-ApprovedBackupDrives` | `rules[0]` | `includeGroups=[ApprovedBackupDrives]`; `allow` + `auditAllow(send_event)`, `access=[read,write,execute]` |
| Rule: `Deny-AllOtherRemovableStorage` | `rules[1]` | `includeGroups=[AllRemovableStorage]`, `excludeGroups=[ApprovedBackupDrives]`; `deny` + `auditDeny(send_event, show_notification)`, `access=[read,write,execute]` |

All group/rule `id` values are fixed constants defined in
`deploy/New-JamfDeviceControlPolicyJson.ps1` - the same values as the Intune sibling's script
(the design notes goal 5, section 6), so a hybrid Intune+JAMF fleet enforces one identical policy identity.
Full cmdlet/CLI/schema grounding: the deploy script's `.NOTES` block and the references below.

## Operations and tuning

**Deployment sequence:** Off (not assigned) → assigned to a pilot JAMF Computer Group → tuned →
widened to a broader Computer Group. There is no service-side simulation mode - Computer Group
scope **is** the staged-rollout lever, identical in spirit to both siblings, but set entirely by
hand in the JAMF Pro console.

**Change management is manual for this deployment path.** Unlike the Intune sibling's Graph-based
create-or-reconcile script, an allowlist change here means: re-run
`deploy/New-JamfDeviceControlPolicyJson.ps1` with the updated config, then repeat the implementation steps Steps 3-4 by
hand in the JAMF Pro console. Track this in whatever change-management/ticketing process governs
JAMF Pro profile edits generally - this scenario does not provide its own audit trail beyond JAMF
Pro's own configuration-profile history.

**KPIs to watch (first 30 days):** identical framing to both siblings - deny-path volume/
distribution after widening, allow-path volume per approved drive as a usage baseline, and
`auditDeny` events immediately followed by a new onboarding/PPPC-exception request.

**Alert routing:** Advanced Hunting/`DeviceEvents` is queryable directly in the Microsoft Defender
portal; for SIEM integration, route through the **Microsoft Defender Streaming API** or the
**Microsoft Defender XDR connector for Microsoft Sentinel**'s "Connect events" option - see the
Windows the sibling scenario's operations and tuning for the same citations, which apply identically here since
`DeviceEvents` is a single, OS- and MDM-agnostic Advanced Hunting table.

**Review cadence:** quarterly at minimum; re-run `validate/Test-JamfDeviceControlPolicyJson.ps1` as
part of that review, and separately confirm in the JAMF Pro console that no one has hand-edited the
pasted JSON out of band. Review the approved-device allowlist itself on the same cadence as any
other privileged-access list.

**Incident-response runbook:** identical structure to both siblings' (triage via Advanced Hunting →
classify legitimate-need-vs-unapproved-attempt → remove a lost/decommissioned drive's entry and
re-run Steps 1-4 → document). The one JAMF-specific addition: because Steps 3-4 are manual, confirm
the change was actually applied in the JAMF Pro console (the validation steps check 3) before assuming a revoked
drive's access has actually been cut off - a re-generated local JSON file with no corresponding
JAMF-console update changes nothing on any Mac.

## Rollback and decommission

See the rollback runbook for the full staged procedure. Unlike both siblings, there is no API object this
scenario's scripts can delete - rollback here is entirely a JAMF Pro console action (remove/blank
the Device Control Policy property, or unscope the profile).

## References

1. Deploy and manage Device Control using JAMF (JSON policy authoring, `mdatp device-control policy
   validate`, updating the Defender preferences schema, adding the Device Control property; states
   the Microsoft 365 E3 / Defender for Endpoint Plan 1 licensing minimum) - <https://learn.microsoft.com/defender-endpoint/mac-device-control-jamf>
2. Device Control for macOS (policy model: settings/groups/query/clause/rules/entries/enforcement/
   access schema tables; "Prepare your endpoints" - Full Disk Access for `com.microsoft.dlp.daemon`,
   `DC_in_dlp` via Data Loss Prevention (DLP) > Features, minimum client version `101.91.92`,
   `mdatp health`/`mdatp version` status fields) - <https://learn.microsoft.com/defender-endpoint/mac-device-control-overview>
3. Set up the Microsoft Defender for Endpoint on macOS policies in Jamf Pro (Step 3b: Preference
   Domain must be exactly `com.microsoft.wdav`; Step 6: Full Disk Access PPPC profile / `fulldisk.
   mobileconfig` upload procedure; general JAMF-based MDE onboarding) - <https://learn.microsoft.com/defender-endpoint/mac-jamfpro-policies>
4. Deploy Microsoft Defender for Endpoint on macOS with Microsoft Intune (`fulldisk.mobileconfig`
   source location and Full Disk Access rationale, cross-referenced for the same file this
   scenario's JAMF path also uses) - <https://learn.microsoft.com/defender-endpoint/mac-install-with-intune>
5. Onboard and offboard macOS devices into Purview solutions using Jamf Pro for Microsoft Defender
   for Endpoint customers (`fulldisk.mobileconfig`/`schema.json` update procedure specifically
   through the JAMF Pro console, referenced for the Full Disk Access step) - <https://learn.microsoft.com/purview/device-onboarding-offboarding-macos-jamfpro-mde>
6. Microsoft Defender for Endpoint macOS preferences schema (`schema.json`, source of truth for the
   Defender for Endpoint preferences profile's available settings, including Device Control) - <https://github.com/microsoft/mdatp-xplat/tree/master/macos/schema>
7. Deploy and manage Device Control using JAMF - Steps 3-4 (Edit schema; Add/Remove properties →
   Device Control → Device Control Policy; paste JSON) - <https://learn.microsoft.com/defender-endpoint/mac-device-control-jamf>
8. Device control policies in Microsoft Defender for Endpoint (shared Groups/Rules/Entries concepts
   across Windows and macOS; the Mac JSON entry syntax and access-type table) - <https://learn.microsoft.com/defender-endpoint/device-control-policies>
9. Microsoft Defender for Endpoint on macOS (system requirements, Device Control capability
   summary) - <https://learn.microsoft.com/defender-endpoint/microsoft-defender-endpoint-mac>
10. *Defender for Endpoint Device Control (macOS): USB Default-Deny Allowlist* - the Intune-managed sibling
    scenario this control is functionally identical to; see that scenario's own references for the
    Intune/Graph-side citations (`macOSCustomConfiguration`, demo `.mobileconfig`, JSON policy
    schema).
11. *Defender for Endpoint Device Control: USB Default-Deny Allowlist* - the Windows sibling scenario (Intune
    OMA-URI/XML mechanism); see that scenario's own references for the Windows-side citations.

> Re-verify all links, and especially the known limitations's open VERIFY on the JAMF Pro API, against current
> Microsoft Learn, JAMF's own developer documentation, and a pilot tenant before a customer-facing
> assessment or sale.