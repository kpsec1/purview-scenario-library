---
part: "rollback"
parent: "data-map/verify-purview-entra-graph-prerequisites"
---
This scenario has no portal object, Purview resource, or Entra directory state to roll back, it
ships one standalone, read-only script (`deploy/Confirm-DirectoryReadersMembership.ps1`) that never
creates, modifies, or deletes anything in the tenant. Decommissioning it means undoing exactly three
things.

## 1. Stop the schedule

If the deploy script was wired into a scheduled task/pipeline (`README.md` §8, recommended
daily/weekly), disable or delete that schedule. The script itself has no persistent server-side
state to disable.

## 2. Decide the fate of the JSON report file(s)

Each `-ReportPath` output is a point-in-time compliance-relevant artifact, a record of which
Managed-Instance-backed Purview sources had their Entra prerequisite intact (and which didn't) on
the date it was generated. It is also, by design, a full membership list of a tenant-wide,
security-sensitive Entra role (`README.md` §11), treat retained report files with the same access
restriction and retention discipline you'd apply to any other privileged-role membership export, not
just generic audit evidence. If this scenario was run to support the sibling scenario's own audit
trail, retain both together, in the same access-restricted location.

## 3. Revoke the automation identity's Graph permission

Remove the `RoleManagement.Read.Directory` Microsoft Graph application permission grant from the app
registration used to run this script (Entra admin center → **App registrations** → the app → **API
permissions** → remove, then re-confirm admin consent is also revoked). If the app registration also
holds `User.Read.All`/`Group.Read.All` solely for this scenario's best-effort drift-name resolution
(`README.md` §3), remove those too. If the app registration was created solely for this scenario and
isn't used elsewhere, consider deleting the app registration and its certificate/secret entirely, 
check `docs/automation-surface.md` §3 first in case the same app registration is shared with another
scenario's script (e.g. the sibling `scan-azure-sql-managed-instance-and-classify` scenario's own
automation identity, which is a *different* app registration with *Purview* roles, not Graph
permissions, the two are never the same identity in this scenario's default design).

## What rollback does **not** undo

- **Any Directory Readers grant or revocation this scenario's findings led a human to make.** This
  scenario never performs the grant/revoke itself (`design.md` §10), only reports on current state.
  Removing this scenario does not touch Directory Readers membership in any way.
- **The sibling scenario's own deployment.** `scan-azure-sql-managed-instance-and-classify`'s
  rollback is entirely independent (its own `rollback.md`), removing this scenario only removes the
  *monitoring* of its Entra prerequisite, not the scan/data-source objects themselves, and re-opens
  the blind spot this scenario's `design.md` §1 describes if that sibling scenario stays deployed
  without this one.
- **Report files already generated.** Same as any other point-in-time evidence, deleting this
  scenario's schedule does not retroactively delete or invalidate reports already written to disk.

## Verification after rollback

```powershell
# Confirm the report file(s) stopped growing (no new file after the schedule was disabled):
Get-Item './out/directory-readers-membership-report.json' | Select-Object LastWriteTimeUtc

# Confirm the app registration no longer holds the removed Graph permission (run as a Global
# Administrator or Privileged Role Administrator, via the Microsoft Graph PowerShell SDK):
Get-MgServicePrincipalAppRoleAssignment -ServicePrincipalId (Get-MgServicePrincipal -Filter "appId eq '$AppId'").Id |
    Where-Object { $_.AppRoleId -ne $null } |
    Select-Object AppRoleId, ResourceDisplayName
# Confirm no remaining entry corresponds to RoleManagement.Read.Directory (or User.Read.All/
# Group.Read.All, if granted) on the Microsoft Graph resource.
```
