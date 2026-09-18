---
part: "rollback"
parent: "compliance-manager/entra-privileged-role-monitoring"
---
This scenario has no portal object to roll back — it ships two standalone, read-only scripts.
Decommissioning both means undoing exactly three things. To decommission only the companion script
(`Export-RoleAssignableGroupMembershipAuditTrail.ps1`) while keeping
`Export-EntraPrivilegedRoleAuditTrail.ps1` running, do steps 1-2 for the companion's own schedule
and CSV only, and in step 3 remove only the two permissions the companion needed
(`Group.Read.All`, `RoleManagement.Read.Directory`) — leave `AuditLog.Read.All` in place since the
sibling script still needs it.

## 1. Stop the schedule(s)

If `deploy/Export-EntraPrivilegedRoleAuditTrail.ps1` and/or
`deploy/Export-RoleAssignableGroupMembershipAuditTrail.ps1` were wired into a scheduled
task/pipeline (`README.md` §8, recommended daily), disable or delete that schedule. Neither script
has any persistent server-side state to disable — there is nothing in the tenant either one created
or modified.

## 2. Decide the fate of the CSV file(s)

Each rolling audit-trail CSV is itself a compliance-relevant artifact — the first records who
changed Global Administrator/Compliance Administrator/Compliance Data Administrator/Security
Administrator role assignments directly, and when; the second records the same for role-assignable
**group** membership changes. Treat both with the same retention discipline as any other audit
evidence rather than deleting them casually. If either must be deleted, do so deliberately and
document why, the same way you would for a native audit log export. If this scenario was deployed
alongside `assess-against-iso27001` specifically to support an ISO 27001 audit cycle, retain all
three CSVs together — they're evidence for the same audit period.

## 3. Revoke the automation identity's Graph permission(s)

Remove the Microsoft Graph application permission grant(s) from the app registration used to run
these scripts (Entra admin center → **App registrations** → the app → **API permissions** →
remove, then re-confirm admin consent is also revoked):
- **`AuditLog.Read.All`** — used by both scripts; remove only if decommissioning both.
- **`Group.Read.All`** and **`RoleManagement.Read.Directory`** — used only by
  `Export-RoleAssignableGroupMembershipAuditTrail.ps1`'s Phase 1 discovery; safe to remove even if
  keeping the sibling script running.

If the app registration was created solely for this scenario and isn't used elsewhere, consider
deleting the app registration and its certificate entirely — check `docs/automation-surface.md` §3
first in case the same app registration is shared with another scenario's script.

## What rollback does **not** undo

- **Audit log records already generated.** `Add member to role`/`Remove member from role` events
  (and, for the companion script, `Add member to group`/`Remove member from group` events) already
  logged by Microsoft Entra ID are retained per the tenant's own Entra audit-log retention (7 days
  Free / 30 days P1-P2, or up to 1 year if the tenant separately holds Purview Audit (Premium) —
  `README.md` §11) regardless of whether either export script keeps running.
- **The role assignments/removals or group membership changes themselves.** Neither script in this
  scenario ever modifies Entra role membership or group membership — both only read and report on
  changes others make. Rolling back this scenario does not restore or revert any role assignment or
  group membership.
- **`assess-against-iso27001`'s own audit trail and assessment.** That scenario's rollback
  (`scenarios/compliance-manager/assess-against-iso27001/rollback.md`) is entirely independent —
  removing this scenario does not affect it, and re-introduces the blind spot
  `Export-EntraPrivilegedRoleAuditTrail.ps1` closed (`design.md` §1) if that sibling scenario stays
  deployed without this one.
- **If decommissioning only the companion script:** `Export-EntraPrivilegedRoleAuditTrail.ps1`
  keeps running and covering direct role assignments as before, but the role-assignable-group gap
  it cannot see (`design.md` §4b) re-opens — confirm this is an accepted, deliberate trade-off
  before decommissioning the companion alone.

## Verification after rollback

```powershell
# Confirm the audit-trail CSV(s) stopped growing (no new rows after the schedule(s) were disabled):
Import-Csv './out/entra-privileged-role-audit-trail.csv' | Sort-Object ActivityDateTime -Descending | Select-Object -First 1
Import-Csv './out/role-assignable-group-membership-audit-trail.csv' | Sort-Object ActivityDateTime -Descending | Select-Object -First 1

# Confirm the app registration no longer holds the removed grant(s) (run as a Global Administrator
# or Privileged Role Administrator, via the Microsoft Graph PowerShell SDK):
Get-MgServicePrincipalAppRoleAssignment -ServicePrincipalId (Get-MgServicePrincipal -Filter "appId eq '$AppId'").Id |
    Where-Object { $_.AppRoleId -ne $null } |
    Select-Object AppRoleId, ResourceDisplayName
# Confirm no remaining entry corresponds to the permission(s) you intended to revoke
# (AuditLog.Read.All, Group.Read.All, RoleManagement.Read.Directory) on the Microsoft Graph resource.
```
