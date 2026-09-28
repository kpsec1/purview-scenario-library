---
part: "runbook"
parent: "dlp/defender-device-control-usb-allowlist-macos"
---
## Implementation steps

### Portal path (for a first manual walkthrough / to validate intent before scripting)

1. **Confirm onboarding and Full Disk Access first** (one-time, not part of this scenario's deploy
   script). Target Macs must already be onboarded to Microsoft Defender for Endpoint, enrolled in
   Intune, and have a PPPC profile granting **Full Disk Access** to `com.microsoft.dlp.daemon` -
   [Microsoft Defender portal](https://security.microsoft.com) → **Assets** → **Devices** to
   confirm onboarding; deploy Microsoft's own `fulldisk.mobileconfig` (or your organization's
   equivalent PPPC profile) via Intune if not already present.
2. Sign in to the [Microsoft Intune admin center](https://intune.microsoft.com) →
   **Devices** → **macOS** → **Configuration profiles** → **+ Create profile**.
3. Platform: **macOS**. Profile type: **Templates** → **Custom**.
4. Name: `Device Control (macOS) - USB Removable Media Default-Deny Allowlist`.
5. Build the `.mobileconfig` file: start from Microsoft's own demo file, replace
   its `groups`/`rules`/`settings` with the values in the design notes's table, and validate it
   against Microsoft's published JSON schema before uploading.
6. Upload the `.mobileconfig` as the profile's configuration file.
7. **Assignments**: select the pilot Entra ID group, **not** "All devices," for a first rollout.
8. **Review + create**.

### Script path (idempotent, parameterized, dry-run capable)

```powershell
# 1. Connect (certificate app-only - see docs/automation-surface.md Section 3)
Connect-MgGraph -ClientId $AppId -TenantId $TenantId -CertificateThumbprint $Thumbprint

# 2. Edit deploy/config/mac-device-control-usb-allowlist.sample.json (or copy it) with your
#    approved-device serial numbers and pilot Entra group ID.

# 3. Dry run - reports every change, makes none
./deploy/New-MacDeviceControlUsbAllowlistPolicy.ps1 `
    -ConfigPath ./deploy/config/mac-device-control-usb-allowlist.sample.json `
    -WhatIf

# 4. Deploy, scoped to the pilot group from the config file
./deploy/New-MacDeviceControlUsbAllowlistPolicy.ps1 `
    -ConfigPath ./deploy/config/mac-device-control-usb-allowlist.sample.json

# 5. After a pilot tuning window, widen the assignment tenant-wide (deliberate, explicit)
./deploy/New-MacDeviceControlUsbAllowlistPolicy.ps1 `
    -ConfigPath ./deploy/config/mac-device-control-usb-allowlist.sample.json `
    -AssignAllDevices -Force

# 6. Validate
./validate/Test-MacDeviceControlUsbAllowlistPolicy.ps1 `
    -ConfigPath ./deploy/config/mac-device-control-usb-allowlist.sample.json
```

The deploy script uses the Microsoft Graph PowerShell SDK (`Invoke-MgGraphRequest` against the
`macOSCustomConfiguration` resource) - automation surface 3 per [Automation surface, section 1](/docs/automation-surface/#1-five-automation-surfaces-not-one-read-this-first).
Device onboarding, Intune enrollment, and the Full Disk Access PPPC profile have no equivalent step
in this script and must be completed first, as in the implementation steps step 1 above.

## Configuration reference

| Setting | Location in `.mobileconfig` | Value |
|---|---|---|
| Enable Device Control engine | `PayloadContent[0].dlp.features[0]` | `{"name": "DC_in_dlp", "state": "enabled"}` |
| Enable removable-media enforcement | `deviceControl.policy.settings.features.removableMedia.disable` | `false` |
| Fail-closed default | `deviceControl.policy.settings.global.defaultEnforcement` | `"deny"` |
| Group: `AllRemovableStorage` (catch-all) | `deviceControl.policy.groups[0]` | `query: {"$type":"all","clauses":[{"$type":"primaryId","value":"removable_media_devices"}]}` |
| Group: `ApprovedBackupDrives` | `deviceControl.policy.groups[1]` | `query: {"$type":"any","clauses":[{"$type":"serialNumber","value":"<serial>"}, ...]}` from config |
| Rule: `Allow-ApprovedBackupDrives` | `deviceControl.policy.rules[0]` | `includeGroups=[ApprovedBackupDrives]`; `allow` + `auditAllow(send_event)`, `access=[read,write,execute]` |
| Rule: `Deny-AllOtherRemovableStorage` | `deviceControl.policy.rules[1]` | `includeGroups=[AllRemovableStorage]`, `excludeGroups=[ApprovedBackupDrives]`; `deny` + `auditDeny(send_event, show_notification)`, `access=[read,write,execute]` |

All group/rule/`PayloadUUID` identifiers are fixed constants defined in
`deploy/New-MacDeviceControlUsbAllowlistPolicy.ps1` (not freshly generated per run), the same
"stable identifiers, not fresh-per-run" discipline as the Windows sibling - see the design notes for
why. Full cmdlet/REST/schema grounding: the deploy script's `.NOTES` block and the references below.

## Operations and tuning

**Deployment sequence:** Off (not assigned) → assigned to a small pilot Entra group → tuned →
assigned tenant-wide (`-AssignAllDevices -Force`). No service-side simulation mode exists
 - assignment scope **is** the staged-rollout lever, identical to the Windows
sibling.

**KPIs to watch (first 30 days):** identical framing to the Windows sibling's operations and tuning - deny-path
volume/distribution after widening, allow-path volume per approved drive as a usage baseline, and
`auditDeny` events immediately followed by a new onboarding/PPPC-exception request.

**Alert routing:** Advanced Hunting/`DeviceEvents` is queryable directly in the Microsoft Defender
portal for both platforms; for SIEM integration, route through the **Microsoft Defender Streaming
API** or the **Microsoft Defender XDR connector for Microsoft Sentinel**'s "Connect events" option
- see the Windows the sibling scenario's operations and tuning (references 16-17) for the same citations, which apply
identically here since `DeviceEvents` is a single, OS-agnostic Advanced Hunting table.

**Review cadence:** quarterly at minimum; re-run `validate/Test-MacDeviceControlUsbAllowlistPolicy.ps1`
as part of that review. Review the approved-device allowlist itself on the same cadence as any
other privileged-access list.

**Incident-response runbook:** identical structure to the Windows sibling's operations and tuning runbook (triage via
Advanced Hunting → classify legitimate-need-vs-unapproved-attempt → remove a lost/decommissioned
drive's entry and re-run the deploy script `-Force` immediately → document). The one macOS-specific
triage addition: if a pilot Mac shows unexpected allow/deny behavior, check
`mdatp health --details device_control`'s `v2_full_disk_access` value **before** assuming the
policy itself is misconfigured - a revoked or never-granted Full Disk Access grant is
indistinguishable from "not onboarded" without this check.

## Rollback and decommission

See the rollback runbook for the full staged procedure (unassign → permanent purge). Quick reference:
`./deploy/Remove-MacDeviceControlUsbAllowlistPolicy.ps1` removes the group assignment (reversible,
the policy definition remains); add `-Purge` to permanently delete the device configuration object.

## References

1. Deploy and manage Device Control using Intune (macOS) - licensing requirement (Microsoft 365 E3), mobileconfig build/deploy steps - <https://learn.microsoft.com/defender-endpoint/mac-device-control-intune>
2. macOSCustomConfiguration resource type / Create macOSCustomConfiguration (Microsoft Graph v1.0 - `payload`/`payloadFileName`/`payloadName`, `DeviceManagementConfiguration.ReadWrite.All`) - <https://learn.microsoft.com/graph/api/resources/intune-deviceconfig-macoscustomconfiguration>, <https://learn.microsoft.com/graph/api/intune-deviceconfig-macoscustomconfiguration-create>
3. Demo `.mobileconfig` (exact plist key path: `PayloadContent[0].dlp.features` / `PayloadContent[0].deviceControl.policy`, `PayloadType`/`PayloadIdentifier` = `com.microsoft.wdav`) - <https://github.com/microsoft/mdatp-devicecontrol/blob/main/macOS/mobileconfig/demo.mobileconfig>
4. Device Control for macOS (policy model: settings/groups/query/clause/rules/entries/enforcement/access schema tables, Full Disk Access + `DC_in_dlp` prerequisites, minimum client version `101.91.92`, `mdatp health` status fields, Advanced Hunting query, known issues) - <https://learn.microsoft.com/defender-endpoint/mac-device-control-overview>
5. Device control policies in Microsoft Defender for Endpoint (shared Groups/Rules/Entries concepts across Windows and macOS; Mac JSON entry syntax and access-type table) - <https://learn.microsoft.com/defender-endpoint/device-control-policies>
6. Deploy and manage Device Control using JAMF (macOS) - the alternative, non-Intune macOS deployment path this scenario does not cover - <https://learn.microsoft.com/defender-endpoint/mac-device-control-jamf>
7. Deploy and manage Device Control using Intune (macOS) - Devices > macOS > Create profile > Templates > Custom portal path - <https://learn.microsoft.com/defender-endpoint/mac-device-control-intune>
8. Microsoft Defender for Endpoint on macOS (system requirements, Device Control capability summary) - <https://learn.microsoft.com/defender-endpoint/microsoft-defender-endpoint-mac>
9. Create a device configuration profile in Microsoft Intune (Policy and Profile manager role prerequisite; not OS-specific) - <https://learn.microsoft.com/intune/device-configuration/create-device-profile>
10. Device control policy JSON schema for macOS - <https://github.com/microsoft/mdatp-devicecontrol/blob/main/macOS/policy/device_control_policy_schema.json>
11. *Defender for Endpoint Device Control: USB Default-Deny Allowlist* - the Windows sibling scenario this control complements; see that scenario's own references for the Windows-side citations (Graph `windows10CustomConfiguration`, `EndpointDlpRestrictions`, Intune RBAC).
12. Deploy and manage Device Control manually (macOS) - preproduction-only `mdatp config device-control policy set`/`reset` path, referenced for context only; not used by this scenario's Intune-based deployment - <https://learn.microsoft.com/defender-endpoint/mac-device-control-manual>

> Re-verify all links, and especially the `payload` PATCH replace-vs-merge semantics and the
> multi-profile-conflict question (the known limitations VERIFYs), against current Microsoft Learn and a pilot
> tenant before a customer-facing assessment or sale.