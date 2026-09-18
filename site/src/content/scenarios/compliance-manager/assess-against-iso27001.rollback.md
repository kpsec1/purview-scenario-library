---
part: "rollback"
parent: "compliance-manager/assess-against-iso27001"
---
This scenario has two independent things to roll back: the **assessment itself** (portal-only, no
script touches it) and the **audit-trail export** (this scenario's one scripted artifact). Handle
them separately.

## Rolling back the assessment (portal-only — no script)

There is no `Remove-*` script for this scenario's `deploy/` folder, because there is no script
that creates the assessment in the first place (design.md §2). Deleting or scoping down the
assessment is a portal action:

### Stage 1 — Remove services from scope (partial rollback, reversible)

From the assessment's details page → **Edit assessment** → **Select services** → remove a service
and select **Next** → **Modify assessment**. Improvement actions specific to the removed service
stop contributing to this assessment's score; the assessment itself remains.

### Stage 2 — Revoke user access (reversible)

From the assessment's details page → **Manage user access** → remove Reader/Assessor/Contributor
role assignments per user. Does not affect the assessment's data or other users' access.

### Stage 3 — Delete the assessment (not reversible)

From the assessment's details page → **Delete assessment**. Microsoft's own guidance:

- **This is permanent — you cannot get it back.** Re-creating means running the full portal
  runbook in `README.md` §5 again from scratch, including re-selecting the ISO/IEC 27001:2022
  regulation and re-scoping services.
- Improvement actions that don't appear in any other assessment are deleted along with it.
  Improvement actions shared with another assessment in the same group (or another group) are
  unaffected.
- **Export a report first** (`README.md` §7, "Export an assessment report") — the exported Excel
  file is the only durable record of this assessment's state once it's deleted.
- The **group** this assessment belonged to is **not** deleted — groups can't be deleted at all
  (`design.md` §8). An empty group with no assessments left in it is expected and harmless.

## Rolling back the audit-trail export (scripted)

`deploy/Export-ComplianceManagerAuditTrail.ps1` has no "undo" in the usual sense — it only reads
from the unified audit log and writes to a local CSV file. Decommissioning this piece means:

1. **Stop the schedule.** If `Export-ComplianceManagerAuditTrail.ps1` was wired into a scheduled
   task/pipeline (`README.md` §8), disable or delete that schedule. The script itself has no
   persistent server-side state to disable — there is nothing in the tenant to turn off.
2. **Decide the fate of the CSV file.** The rolling audit-trail CSV is itself a compliance-relevant
   artifact (it records who changed Compliance Manager roles/automation trust, and when) — treat
   it with the same retention discipline as any other audit evidence rather than deleting it
   casually. If it must be deleted, do so deliberately and document why, the same way you would for
   a native audit log export.
3. **Revoke the automation identity's role**, if one was dedicated to this script. The script needs
   only the **View-Only Audit Logs** (or **Audit Logs**) Exchange Online role (`README.md` §3) —
   remove that role assignment from the app registration's service principal or the interactive
   account used to run it.

## What rollback does **not** undo

- **Audit log records already generated.** `ComplianceManagerRolesChange`/
  `ComplianceManagerAutomationLevelChange`/`ComplianceManagerAutomationChange` events already
  logged by Microsoft 365 are retained per the tenant's audit retention policy (`README.md` §11)
  regardless of whether this scenario's export script keeps running.
- **Signals already fed into Compliance Manager's built-in automation** from other scenarios in
  this library (DLP, Information Protection, IRM). Those scenarios' own rollback procedures govern
  their controls independently — deleting this Compliance Manager assessment does not disable or
  affect them.
- **A compliance score history already reported** via Compliance Manager's native Reports page.
  That history is Microsoft's own product data, retained per Microsoft's documented behavior
  (`README.md` §7, "Reports page"), independent of this scenario's CSV export.

## Verification after rollback

```powershell
# Confirm the audit-trail CSV stopped growing (no new rows after the schedule was disabled):
Import-Csv './out/compliance-manager-audit-trail.csv' | Sort-Object CreationDate -Descending | Select-Object -First 1

# Confirm the automation identity no longer holds the audit-search role (run as a Global/Compliance
# Administrator, from Exchange Online PowerShell):
Get-RoleGroupMember -Identity 'View-Only Organization Management' | Where-Object { $_.Name -eq '<service principal display name>' }
```

For the assessment itself, the only verification is in the portal: confirm it no longer appears on
the **Assessments** page (Stage 3) or that its **Services**/**Manage user access** panes reflect
the reduced scope (Stages 1–2).
