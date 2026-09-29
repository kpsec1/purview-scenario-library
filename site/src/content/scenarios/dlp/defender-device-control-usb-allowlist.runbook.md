---
part: "runbook"
parent: "dlp/defender-device-control-usb-allowlist"
---
## Implementation steps

### Portal path (for a first manual walkthrough / to validate intent before scripting)

1. **Confirm onboarding first** (one-time, not part of this scenario's deploy script). Target
   devices must already be onboarded to Microsoft Defender for Endpoint and enrolled in Intune -
   [Microsoft Defender portal](https://security.microsoft.com) → **Assets** → **Devices**, confirm
   the pilot devices show as onboarded and reporting.
2. Sign in to the [Microsoft Intune admin center](https://intune.microsoft.com) →
   **Devices** → **Configuration profiles** → **+ Create** → **+ New policy**.
3. Platform: **Windows 10 and later**. Profile type: **Templates** → **Custom**.
4. Name: `Device Control - USB Removable Media Default-Deny Allowlist`.
5. Add one **OMA-URI** row per setting in the design notes's table - `DeviceControlEnabled` (Integer,
   `1`), `SecuredDevicesConfiguration` (String, `RemovableMediaDevices`), `DefaultEnforcement`
   (Integer, `2`), then the two group XML rows and two rule XML rows (Data type **String (XML
   file)**, Custom XML) - see for the exact OMA-URI path syntax and
   for the Group/Rule/Entry XML schema.
6. **Assignments**: select the pilot Entra ID group, **not** "All devices," for a first rollout.
7. **Review + create**.

### Script path (idempotent, parameterized, dry-run capable)

```powershell
# 1. Connect (certificate app-only - see Automation surface, section 3)
Connect-MgGraph -ClientId $AppId -TenantId $TenantId -CertificateThumbprint $Thumbprint

# 2. Edit deploy/config/device-control-usb-allowlist.sample.json (or copy it) with your
# approved-device serial numbers/VID_PIDs and pilot Entra group ID.

# 3. Dry run - reports every change, makes none
./deploy/New-DeviceControlUsbAllowlistPolicy.ps1 `
    -ConfigPath ./deploy/config/device-control-usb-allowlist.sample.json `
    -WhatIf

# 4. Deploy, scoped to the pilot group from the config file
./deploy/New-DeviceControlUsbAllowlistPolicy.ps1 `
    -ConfigPath ./deploy/config/device-control-usb-allowlist.sample.json

# 5. After a pilot tuning window, widen the assignment tenant-wide (deliberate, explicit)
./deploy/New-DeviceControlUsbAllowlistPolicy.ps1 `
    -ConfigPath ./deploy/config/device-control-usb-allowlist.sample.json `
    -AssignAllDevices -Force

# 6. Validate
./validate/Test-DeviceControlUsbAllowlistPolicy.ps1 `
    -ConfigPath ./deploy/config/device-control-usb-allowlist.sample.json
```

The deploy script uses the Microsoft Graph PowerShell SDK (`Invoke-MgGraphRequest` against the
`windows10CustomConfiguration` resource) - automation surface 3 per [Automation surface, section 1](/docs/automation-surface/#1-five-automation-surfaces-not-one-read-this-first). Device onboarding and Intune enrollment have no equivalent step in this script and must be
completed first, as in the implementation steps step 1 above.

## Configuration reference

| Setting | OMA-URI suffix | Type | Value |
|---|---|---|---|
| Enable device control | `DeviceControlEnabled` | `omaSettingInteger` | `1` |
| Scope to removable storage | `SecuredDevicesConfiguration` | `omaSettingString` | `RemovableMediaDevices` |
| Fail-closed default | `DefaultEnforcement` | `omaSettingInteger` | `2` (Deny) |
| Group: `ApprovedBackupDrives` | `DeviceControl/PolicyGroups/{GUID}/GroupData` | `omaSettingStringXml` | `MatchAny` over `SerialNumberId`/`VID_PID` entries from config |
| Group: `AllRemovableStorage` (catch-all) | `DeviceControl/PolicyGroups/{GUID}/GroupData` | `omaSettingStringXml` | `MatchAny` over `PrimaryId = RemovableMediaDevices` |
| Rule: `Allow-ApprovedBackupDrives` | `DeviceControl/PolicyRules/{GUID}/RuleData` | `omaSettingStringXml` | Included = approved group; `Allow`(AccessMask 63) + `AuditAllowed`(send event) |
| Rule: `Deny-AllOtherRemovableStorage` | `DeviceControl/PolicyRules/{GUID}/RuleData` | `omaSettingStringXml` | Included = catch-all, Excluded = approved group; `Deny`(AccessMask 63) + `AuditDenied`(notify + send event) |

All four GUIDs are fixed constants defined in `deploy/New-DeviceControlUsbAllowlistPolicy.ps1` (not
freshly generated per run) so that re-running the script updates the same four OMA-URI nodes -
see the design notes for why. Full cmdlet/REST grounding: the deploy script's `.NOTES` block and
the references below.

## Operations and tuning

**Deployment sequence:** Off (not assigned) → assigned to a small pilot Entra group → tuned →
assigned tenant-wide (`-AssignAllDevices -Force`). There is no service-side simulation mode for
device control - assignment scope **is** the staged-rollout lever.

**KPIs to watch (first 30 days):**
- **Deny-path volume and per-user distribution** - a spike right after widening assignment usually
  means a legitimate, previously-unknown workflow was using an unapproved drive, not a wave of
  exfiltration attempts. Investigate before assuming malice, the same caution *Endpoint DLP: Block USB Removable Media Exfiltration*
  documents for its own Rule 0.
- **Allow-path volume per approved drive** - this is the baseline of how often each IT-issued drive
  is actually used. A drive with unusually high volume, or used from a device/user pattern that
  doesn't match its known custodian, is the signal worth investigating first - the audited-allow
  design exists specifically so this baseline is visible.
- **`AuditDenied` events immediately followed by a new device onboarding/enrollment request** - can
  indicate a user working around the control by requesting an exception rather than reporting a
  genuine business need; route these to the same review as any DLP exception request.

**Alert routing:** Advanced Hunting/`DeviceEvents` is queryable directly in the Microsoft Defender
portal; for SIEM integration, route through the **Microsoft Defender Streaming API**
 or the **Microsoft Defender XDR connector for Microsoft Sentinel**'s "Connect
events" option, which ingests the `DeviceEvents` table (among others) into a Sentinel workspace
 - see [Automation surface, section 4](/docs/automation-surface/#4-routing-table---which-surface-for-which-purview-task) for this library's general alert-routing
guidance.

**Review cadence:** quarterly at minimum; re-run `validate/Test-DeviceControlUsbAllowlistPolicy.ps1`
as part of that review to catch configuration or assignment drift. Review the **approved-device
allowlist itself** on the same cadence as any other privileged-access list - a stale entry for
a decommissioned or lost drive is a live gap, not a paperwork issue.

**Incident-response runbook (an `AuditDenied` event that looks anomalous, or a report of a blocked
legitimate drive):**
1. **Triage** - Advanced Hunting query for the device/user/timestamp; confirm the
   `RemovableStoragePolicyVerdict` and whether the device's serial number/VID_PID is genuinely
   absent from the approved list (misconfiguration) or genuinely unapproved (policy working as
   intended).
2. **Classify** - legitimate business need for a new approved drive vs. a user attempting to use
   an unapproved device. The former routes to the standard change-request process for adding a new
   `approvedDevices` entry (with its serial number, not just its VID_PID, for a true single-drive
   allowlist - the known limitations); the latter routes to the org's standard security-awareness or HR process.
3. **If a lost or decommissioned approved drive is reported** - remove its entry from the config
   and re-run the deploy script (`-Force`) **immediately**; a lost drive still on the allowlist is
   an active gap, not a historical one.
4. **Document** - every allow-path audit event and every escalated deny-path event is retained as
   incident-response evidence; do not delete or edit Advanced Hunting data (subject to its own
   retention window).

## Rollback and decommission

See the rollback runbook for the full staged procedure (unassign → permanent purge). Quick reference:
`./deploy/Remove-DeviceControlUsbAllowlistPolicy.ps1` removes the group assignment (reversible,
the policy definition remains); add `-Purge` to permanently delete the device configuration object.

## References

1. Overview of Microsoft Defender for Endpoint Plan 1 (device control listed as a Plan 1 attack-surface-reduction capability) - <https://learn.microsoft.com/defender-endpoint/defender-endpoint-plan-1>
2. What is Microsoft Intune (licensing overview) - <https://learn.microsoft.com/intune/intune-service/fundamentals/what-is-intune>
3. Device control in Microsoft Defender for Endpoint (overview, prerequisites, Advanced Hunting query examples, `RemovableStoragePolicyTriggered`) - <https://learn.microsoft.com/defender-endpoint/device-control-overview>
4. Create a device configuration profile in Microsoft Intune (Policy and Profile manager role prerequisite) - <https://learn.microsoft.com/intune/device-configuration/create-device-profile>
5. How to use Microsoft Entra ID to access the Intune APIs in Microsoft Graph (`DeviceManagementConfiguration.ReadWrite.All` application permission scope) - <https://learn.microsoft.com/intune/developer/configure-graph-api-access>
6. Deploy and manage device control in Microsoft Defender for Endpoint with Microsoft Intune (OMA-URI paths and data types for `DeviceControlEnabled`/`SecuredDevicesConfiguration`/`DefaultEnforcement`/`PolicyGroups`/`PolicyRules`) - <https://learn.microsoft.com/defender-endpoint/device-control-deploy-manage-intune>
7. Device control policies in Microsoft Defender for Endpoint (Groups/Rules/Entries schema, `AccessMask`, `MatchType`, notification cadence) - <https://learn.microsoft.com/defender-endpoint/device-control-policies>
8. Microsoft Defender for Endpoint Device Control frequently asked questions (Group Policy vs. Intune precedence when both target the same device) - <https://learn.microsoft.com/defender-endpoint/device-control-faq>
9. windows10CustomConfiguration resource type (Microsoft Graph v1.0 - `omaSettings` property) - <https://learn.microsoft.com/graph/api/resources/intune-deviceconfig-windows10customconfiguration>
10. Create windows10CustomConfiguration (`POST /deviceManagement/deviceConfigurations`) - <https://learn.microsoft.com/graph/api/intune-deviceconfig-windows10customconfiguration-create>
11. omaSetting / omaSettingInteger / omaSettingString / omaSettingStringXml resource types (Microsoft Graph v1.0) - <https://learn.microsoft.com/graph/api/resources/intune-deviceconfig-omasetting>, <https://learn.microsoft.com/graph/api/resources/intune-deviceconfig-omasettinginteger>, <https://learn.microsoft.com/graph/api/resources/intune-deviceconfig-omasettingstring>, <https://learn.microsoft.com/graph/api/resources/intune-deviceconfig-omasettingstringxml>
12. groupAssignmentTarget / deviceConfigurationAssignment resource types (Microsoft Graph v1.0) - <https://learn.microsoft.com/graph/api/resources/intune-shared-groupassignmenttarget>, <https://learn.microsoft.com/graph/api/resources/intune-deviceconfig-deviceconfigurationassignment>
13. New-MgDeviceManagementDeviceConfiguration / Update-MgDeviceManagementDeviceConfiguration / Remove-MgDeviceManagementDeviceConfiguration (Microsoft.Graph.DeviceManagement PowerShell module, v1.0) - <https://learn.microsoft.com/powershell/module/microsoft.graph.devicemanagement/new-mgdevicemanagementdeviceconfiguration>
14. Device control in Microsoft Defender for Endpoint - control access to USB devices (device installation restrictions vs. device control vs. Endpoint DLP comparison) - <https://learn.microsoft.com/defender-endpoint/device-control-overview#control-access-to-usb-devices>
15. *Endpoint DLP: Block USB Removable Media Exfiltration* - the content-aware sibling scenario this control complements; see that scenario's own references for the Endpoint DLP-side citations.
16. Microsoft Defender Streaming API (raw event export for long-term retention / external SIEM ingestion) - <https://learn.microsoft.com/defender-xdr/streaming-api>
17. Microsoft Defender XDR integration with Microsoft Sentinel ("Connect events" - `DeviceEvents` and other advanced hunting tables streamed into a Sentinel workspace) - <https://learn.microsoft.com/azure/sentinel/microsoft-365-defender-sentinel-integration>

> Re-verify all links, and especially the OMA-URI PATCH replace-vs-merge semantics (the known limitations VERIFY),
> against current Microsoft Learn and a pilot tenant before a customer-facing assessment or sale.