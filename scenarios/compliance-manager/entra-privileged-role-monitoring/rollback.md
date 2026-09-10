# Rollback — Compliance Manager: Entra Privileged Role Monitoring

This scenario has no portal object to roll back — it is a single, standalone, read-only script.
Decommissioning it means undoing exactly three things.

## 1. Stop the schedule

If `deploy/Export-EntraPrivilegedRoleAuditTrail.ps1` was wired into a scheduled task/pipeline
(`README.md` §8, recommended daily), disable or delete that schedule. The script itself has no
persistent server-side state to disable — there is nothing in the tenant it created or modified.

## 2. Decide the fate of the CSV file

The rolling audit-trail CSV is itself a compliance-relevant artifact (it records who changed
Global Administrator/Compliance Administrator/Compliance Data Administrator/Security Administrator
role assignments, and when) — treat it with the same retention discipline as any other audit
evidence rather than deleting it casually. If it must be deleted, do so deliberately and document
why, the same way you would for a native audit log export. If this scenario was deployed alongside
`assess-against-iso27001` specifically to support an ISO 27001 audit cycle, retain both CSVs
together — they're evidence for the same audit period.

## 3. Revoke the automation identity's Graph permission

Remove the **`AuditLog.Read.All`** Microsoft Graph application permission grant from the app
registration used to run this script (Entra admin center → **App registrations** → the app →
**API permissions** → remove, then re-confirm admin consent is also revoked). If the app
registration was created solely for this scenario and isn't used elsewhere, consider deleting the
app registration and its certificate entirely — check `docs/automation-surface.md` §3 first in case
the same app registration is shared with another scenario's script.

## What rollback does **not** undo

- **Audit log records already generated.** `Add member to role`/`Remove member from role` events
  already logged by Microsoft Entra ID are retained per the tenant's own Entra audit-log retention
  (7 days Free / 30 days P1-P2, or up to 1 year if the tenant separately holds Purview Audit
  (Premium) — `README.md` §11) regardless of whether this scenario's export script keeps running.
- **The role assignments/removals themselves.** This scenario never modifies Entra role membership
  — it only reads and reports on changes others make. Rolling back this scenario does not restore
  or revert any role assignment.
- **`assess-against-iso27001`'s own audit trail and assessment.** That scenario's rollback
  (`scenarios/compliance-manager/assess-against-iso27001/rollback.md`) is entirely independent —
  removing this scenario does not affect it, and re-introduces the blind spot this scenario closed
  (`design.md` §1) if that sibling scenario stays deployed without this one.

## Verification after rollback

```powershell
# Confirm the audit-trail CSV stopped growing (no new rows after the schedule was disabled):
Import-Csv './out/entra-privileged-role-audit-trail.csv' | Sort-Object ActivityDateTime -Descending | Select-Object -First 1

# Confirm the app registration no longer holds the AuditLog.Read.All grant (run as a Global
# Administrator or Privileged Role Administrator, via the Microsoft Graph PowerShell SDK):
Get-MgServicePrincipalAppRoleAssignment -ServicePrincipalId (Get-MgServicePrincipal -Filter "appId eq '$AppId'").Id |
    Where-Object { $_.AppRoleId -ne $null } |
    Select-Object AppRoleId, ResourceDisplayName
# Confirm no remaining entry corresponds to AuditLog.Read.All on the Microsoft Graph resource.
```
