---
part: "rollback"
parent: "dlp/defender-device-control-usb-allowlist-macos"
---
## Recommended sequence

A device control policy change affects live removable-storage access on every assigned Mac, so
roll back in stages rather than deleting outright, identical staging discipline to the Windows
sibling scenario.

### Stage 1, Unassign (reversible, minutes)

```powershell
Connect-MgGraph -ClientId $AppId -TenantId $TenantId -CertificateThumbprint $Thumbprint
./deploy/Remove-MacDeviceControlUsbAllowlistPolicy.ps1
```

This deletes every assignment on the device configuration object (both the pilot group and, if
present, "All devices"). The object and its `.mobileconfig` payload remain fully defined and
visible in the Intune admin center, nothing needs to be re-authored. Re-assign instantly:

```powershell
./deploy/New-MacDeviceControlUsbAllowlistPolicy.ps1 -ConfigPath ./deploy/config/my-tenant.json
```

Use this stage for: a false-positive incident affecting a business-critical workflow that needs
immediate relief, a change freeze, or a temporary business exception that doesn't warrant deleting
the control's definition.

### Stage 2, Narrow the assignment (partial rollback)

If a full unassign is too blunt, remove only the affected Macs from the pilot Entra ID group
referenced by `assignment.groupId` rather than deleting the assignment entirely, this scenario's
scripts do not manage that group's membership directly (a dependency, not a deployed artifact, 
`design.md` §8), so this is a directory-side change, not a script re-run.

### Stage 3, Permanent removal (not reversible)

```powershell
./deploy/Remove-MacDeviceControlUsbAllowlistPolicy.ps1 -Purge
```

This deletes every assignment, then permanently deletes the `macOSCustomConfiguration` object
itself (`DELETE /deviceManagement/deviceConfigurations/{id}`). There is no "undo", re-establishing
the control means re-running `deploy/New-MacDeviceControlUsbAllowlistPolicy.ps1` from scratch,
including re-supplying the approved-devices list. Only do this when the control is being
permanently retired or replaced by a successor policy with a different name.

## What rollback does **not** undo

- **Advanced Hunting / `DeviceEvents` history.** Allow and deny audit events already generated are
 retained per their own retention window regardless of policy state.
- **Access already denied or allowed.** A copy that was denied while the policy was enforcing was
 not written to the removable device; a later rollback does not retroactively complete it.
- **Device onboarding, Intune enrollment, or the Full Disk Access (PPPC) profile for
 `com.microsoft.dlp.daemon`.** This scenario does not create or manage any of these, rollback
 here has no effect on any of them. In particular, removing this scenario's policy does **not**
 revoke the Full Disk Access grant; that is a separate profile with its own lifecycle.
- **The pilot/target Entra ID group, or the physical approved drives.** This scenario does not
 create or manage the assignment group or the approved-drive inventory.
- **A separate, independently-deployed `com.microsoft.wdav` preferences profile**, if one exists
 for other Defender for Endpoint on macOS settings, removing this scenario's profile has no
 effect on any other profile of that type (see README.md §11's open VERIFY on multi-profile
 conflict behavior, which cuts both ways: if two profiles were merging, removing one may change
 the merged result in a way not independently confirmed by this build).

## Verification after rollback

```powershell
Connect-MgGraph -ClientId $AppId -TenantId $TenantId -CertificateThumbprint $Thumbprint
$policy = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/deviceManagement/deviceConfigurations?`$filter=displayName eq 'Device Control (macOS) - USB Removable Media Default-Deny Allowlist'"
$policy.value | Select-Object id, displayName

# Stage 1: confirm zero assignments remain
Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/deviceManagement/deviceConfigurations/$($policy.value[0].id)/assignments"

# Stage 3: confirm the GET above for the policy itself returns an empty .value array
```
