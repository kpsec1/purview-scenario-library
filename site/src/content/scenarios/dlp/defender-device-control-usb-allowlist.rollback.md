---
part: "rollback"
parent: "dlp/defender-device-control-usb-allowlist"
---
## Recommended sequence

A device control policy change affects live removable-storage access on every assigned device, so
roll back in stages rather than deleting outright.

### Stage 1, Unassign (reversible, minutes)

```powershell
Connect-MgGraph -ClientId $AppId -TenantId $TenantId -CertificateThumbprint $Thumbprint
./deploy/Remove-DeviceControlUsbAllowlistPolicy.ps1
```

This deletes every assignment on the device configuration object (both the pilot group and, if
present, "All devices"). The object and its seven `omaSettings` entries remain fully defined and
visible in the Intune admin center, nothing needs to be re-authored. Re-assign instantly:

```powershell
./deploy/New-DeviceControlUsbAllowlistPolicy.ps1 -ConfigPath ./deploy/config/my-tenant.json
```

Use this stage for: a false-positive incident affecting a business-critical workflow that needs
immediate relief, a change freeze, or a temporary business exception that doesn't warrant deleting
the control's definition.

### Stage 2, Narrow the assignment (partial rollback)

If a full unassign is too blunt (you still want the control enforcing for most devices, just not
the ones affected by an incident), remove only the affected devices from the pilot Entra ID group
referenced by `assignment.groupId` rather than deleting the assignment entirely, this scenario's
scripts do not manage that group's membership directly (it is a dependency, not a deployed
artifact, `design.md` §8), so this is a directory-side change, not a script re-run.

### Stage 3, Permanent removal (not reversible)

```powershell
./deploy/Remove-DeviceControlUsbAllowlistPolicy.ps1 -Purge
```

This deletes every assignment, then permanently deletes the device configuration object itself
(`DELETE /deviceManagement/deviceConfigurations/{id}`). There is no "undo", re-establishing the
control means re-running `deploy/New-DeviceControlUsbAllowlistPolicy.ps1` from scratch, including
re-supplying the approved-devices list. Only do this when the control is being permanently retired
or replaced by a successor policy with a different name.

## What rollback does **not** undo

- **Advanced Hunting / `DeviceEvents` history.** Allow and deny audit events already generated are
 retained per their own retention window regardless of policy state (`README.md` §8).
- **Access already denied or allowed.** A copy that was denied while the policy was enforcing was
 not written to the removable device; unassigning or deleting the policy afterward does not
 retroactively complete it. A copy to an approved drive that already completed is unaffected by a
 later rollback.
- **Device onboarding/Intune enrollment.** This scenario does not onboard devices to Defender for
 Endpoint or enroll them in Intune, rollback here has no effect on either.
- **The pilot/target Entra ID group, or the physical approved drives.** This scenario does not
 create or manage the assignment group or the approved-drive inventory, they are dependencies,
 not deployed artifacts. Removing this policy has no effect on either.
- **Group Policy-based device control, if one also exists on the same devices.** Microsoft's own
 guidance is that Group Policy takes precedence over Intune when both target the same machine
 (`README.md` §11, reference 8), removing this scenario's Intune-based policy does not touch any
 separate GPO-based device control configuration.

## Verification after rollback

```powershell
Connect-MgGraph -ClientId $AppId -TenantId $TenantId -CertificateThumbprint $Thumbprint
$policy = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/deviceManagement/deviceConfigurations?`$filter=displayName eq 'Device Control - USB Removable Media Default-Deny Allowlist'"
$policy.value | Select-Object id, displayName

# Stage 1: confirm zero assignments remain
Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/deviceManagement/deviceConfigurations/$($policy.value[0].id)/assignments"

# Stage 3: confirm the GET above for the policy itself returns an empty .value array
```
