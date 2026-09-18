---
part: "rollback"
parent: "compliance-manager/pci-dss-assessment"
---
This scenario has two independent things to roll back: the **assessment itself** (portal-only, no
script touches it) and the **audit-trail export**, which is a **reused** script shared with
`scenarios/compliance-manager/assess-against-iso27001/` (`design.md` §2). Handle them separately,
and read the group-sharing note in Stage 3 before deleting anything if this assessment shares a
group with the ISO 27001 assessment.

## Rolling back the assessment (portal-only — no script)

There is no `Remove-*` script for this scenario's `deploy/` folder, because there is no script that
creates the assessment in the first place (`design.md` §2).

### Stage 1 — Remove services from scope (partial rollback, reversible)

From the assessment's details page → **Edit assessment** → **Select services** → remove a service →
**Next** → **Modify assessment**. Improvement actions specific to the removed service stop
contributing to this assessment's score; the assessment itself remains.

### Stage 2 — Revoke user access (reversible)

From the assessment's details page → **Manage user access** → remove Reader/Assessor/Contributor
role assignments per user. Does not affect the assessment's data, the group, or other assessments
in it.

### Stage 3 — Delete the assessment (not reversible)

From the assessment's details page → **Delete assessment**. Microsoft's own guidance, and one
consideration specific to this scenario:

- **This is permanent — you cannot get it back.** Re-creating means running the full portal
  runbook in `README.md` §5 again from scratch.
- Improvement actions that don't appear in any other assessment are deleted along with it.
  Improvement actions **shared with the ISO/IEC 27001:2022 assessment in the same group are
  unaffected** — deleting this PCI DSS assessment does not touch `assess-against-iso27001` or the
  nontechnical improvement-action data it shares with it (`design.md` §6).
- **Export a report first** (`README.md` §7, "Export an assessment report") — the exported Excel
  file is the only durable record of this assessment's state once it's deleted.
- **The group itself is never deleted**, regardless of how many assessments remain in it — groups
  can't be deleted at all (`design.md` §6). If `assess-against-iso27001` is also in the
  `Security & Compliance Assessments` group, that assessment and the group both continue to exist
  normally after this assessment is deleted — there is no cascading effect in either direction.

## Rolling back the audit-trail export (reused, not owned by this scenario)

`deploy/Export-ComplianceManagerAuditTrail.ps1` in this folder is the **same script** as the one in
`scenarios/compliance-manager/assess-against-iso27001/deploy/` (`design.md` §2). Decommissioning it
depends on whether the ISO 27001 scenario is also deployed:

1. **If `assess-against-iso27001` is also deployed and its audit-trail script is still needed**:
   do nothing to the script itself — it monitors tenant-wide Compliance Manager operations, not
   this assessment specifically, so removing this PCI DSS assessment doesn't reduce what it needs
   to watch. Only stop the schedule if the ISO 27001 scenario is *also* being decommissioned.
2. **If this is the only Compliance Manager assessment left in the tenant after this rollback**:
   stop the schedule, decide the fate of the accumulated CSV (treat it with the same retention
   discipline as any other audit evidence — don't delete it casually), and revoke the automation
   identity's **View-Only Audit Logs** (or **Audit Logs**) Exchange Online role if it was dedicated
   to this purpose — identical procedure to `assess-against-iso27001/rollback.md`.

## What rollback does **not** undo

- **Audit log records already generated.** Retained per the tenant's audit retention policy
  (`README.md` §11) regardless of whether either scenario's export script keeps running.
- **Signals already fed into Compliance Manager's built-in automation** from this library's DLP/
  Information Protection/Endpoint DLP/Adaptive Protection/IRM/Audit scenarios. Those scenarios' own
  rollback procedures govern their controls independently.
- **A compliance score history already reported** via Compliance Manager's native Reports page —
  Microsoft's own product data, independent of this scenario's CSV export.
- **The ISO/IEC 27001:2022 assessment or its shared group**, as stated in Stage 3 above.

## Verification after rollback

```powershell
# Confirm the audit-trail CSV stopped growing (only if it was actually stopped per the guidance above):
Import-Csv './out/compliance-manager-audit-trail.csv' | Sort-Object CreationDate -Descending | Select-Object -First 1

# Confirm the automation identity no longer holds the audit-search role, if it was revoked:
Get-RoleGroupMember -Identity 'View-Only Organization Management' | Where-Object { $_.Name -eq '<service principal display name>' }
```

For the assessment itself, the only verification is in the portal: confirm it no longer appears on
the **Assessments** page (Stage 3), and — if `assess-against-iso27001` remains — confirm that
assessment and its group are both still present and unaffected.
