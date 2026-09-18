---
part: "rollback"
parent: "compliance-manager/hipaa-hitech-assessment"
---
This scenario has two independent things to roll back: the **assessment itself** (portal-only, no
script touches it) and the **audit-trail export**, which is a **reused** script shared with
`scenarios/compliance-manager/assess-against-iso27001/`, `scenarios/compliance-manager/
pci-dss-assessment/`, and `scenarios/compliance-manager/soc2-assessment/` (`design.md` §2). Handle
them separately, and read the group-sharing note in Stage 3 before deleting anything if this
assessment shares a group with any of the three siblings.

## Rolling back the assessment (portal-only, no script)

There is no `Remove-*` script for this scenario's `deploy/` folder, because there is no script that
creates the assessment in the first place (`design.md` §2).

### Stage 1, Remove services from scope (partial rollback, reversible)

From the assessment's details page → **Edit assessment** → **Select services** → remove a service →
**Next** → **Modify assessment**. Improvement actions specific to the removed service stop
contributing to this assessment's score; the assessment itself remains.

### Stage 2, Revoke user access (reversible)

From the assessment's details page → **Manage user access** → remove Reader/Assessor/Contributor
role assignments per user. Does not affect the assessment's data, the group, or other assessments
in it. This does **not** affect the organization's separately-designated HIPAA Privacy Officer or
Security Officer roles (`README.md` §3), which are organizational designations independent of
Compliance Manager RBAC.

### Stage 3, Delete the assessment (not reversible)

From the assessment's details page → **Delete assessment**. Microsoft's own guidance, and
considerations specific to this scenario:

- **This is permanent, you cannot get it back.** Re-creating means running the full portal
 runbook in `README.md` §5 again from scratch.
- Improvement actions that don't appear in any other assessment are deleted along with it.
 Improvement actions **shared with the ISO/IEC 27001:2022, PCI DSS v4.0, and/or SOC 2 assessments
 in the same group are unaffected**, deleting this HIPAA/HITECH assessment does not touch any
 sibling scenario or the nontechnical improvement-action data it shares with them (`design.md`
 §6).
- **Export a report first** (`README.md` §7, "Export an assessment report"), the exported Excel
 file is the only durable record of this assessment's state once it's deleted. Given HIPAA's own
 six-year documentation-retention requirement (45 CFR §164.316(b)(2)(i), `README.md` §11),
 archive this export (and the audit-trail CSV) for at least that long, independent of Compliance
 Manager's own retention or this scenario's continued deployment.
- **The group itself is never deleted**, regardless of how many assessments remain in it, groups
 can't be deleted at all (`design.md` §6). If any of `assess-against-iso27001`, `pci-dss-
 assessment`, and/or `soc2-assessment` are also in the `Security & Compliance Assessments` group,
 those assessments and the group both continue to exist normally after this assessment is deleted
, there is no cascading effect in either direction.

## Rolling back the audit-trail export (reused, not owned by this scenario)

`deploy/Export-ComplianceManagerAuditTrail.ps1` in this folder is the **same script** as the copies
in `scenarios/compliance-manager/assess-against-iso27001/deploy/`, `scenarios/compliance-manager/
pci-dss-assessment/deploy/`, and `scenarios/compliance-manager/soc2-assessment/deploy/` (`design.md`
§2). Decommissioning it depends on whether any sibling scenario is also deployed:

1. **If any of `assess-against-iso27001`, `pci-dss-assessment`, or `soc2-assessment` are also
 deployed and their audit-trail script is still needed**: do nothing to the script itself, it
 monitors tenant-wide Compliance Manager operations, not this assessment specifically, so
 removing this HIPAA/HITECH assessment doesn't reduce what it needs to watch. Only stop the
 schedule if every Compliance Manager assessment in the tenant is *also* being decommissioned.
2. **If this is the only Compliance Manager assessment left in the tenant after this rollback**:
 stop the schedule, decide the fate of the accumulated CSV (treat it with the same retention
 discipline as any other HIPAA compliance evidence, don't delete it casually, and remember the
 six-year retention requirement above applies to this evidence too, not only to the exported
 assessment report), and revoke the automation identity's **View-Only Audit Logs** (or **Audit
 Logs**) Exchange Online role if it was dedicated to this purpose, identical procedure to the
 three sibling scenarios' own `rollback.md`.

## What rollback does **not** undo

- **Audit log records already generated.** Retained per the tenant's audit retention policy
 (`README.md` §11) regardless of whether any sibling scenario's export script keeps running, 
 note this is almost always shorter than HIPAA's own six-year documentation-retention requirement,
 which is exactly why this scenario recommends archiving the CSV independently rather than relying
 on the underlying audit log to still have the events later.
- **Signals already fed into Compliance Manager's built-in automation** from this library's
 Information Protection/DLP/Adaptive Protection/Insider Risk/Audit scenarios. Those scenarios' own
 rollback procedures govern their controls independently.
- **A compliance score history already reported** via Compliance Manager's native Reports page, 
 Microsoft's own product data, independent of this scenario's CSV export.
- **The ISO/IEC 27001:2022, PCI DSS v4.0, or SOC 2 assessments, or their shared group**, as stated
 in Stage 3 above.
- **The organization's obligations under HIPAA itself**, its Business Associate Agreement, its
 Security Risk Analysis obligation, its designated Privacy Officer/Security Officer roles, and its
 Breach Notification Rule obligations all continue to exist independent of whether this Compliance
 Manager assessment is deployed at all. This scenario is a readiness-tracking convenience layered
 on top of those obligations, never their source.

## Verification after rollback

```powershell
# Confirm the audit-trail CSV stopped growing (only if it was actually stopped per the guidance above):
Import-Csv './out/compliance-manager-audit-trail.csv' | Sort-Object CreationDate -Descending | Select-Object -First 1

# Confirm the automation identity no longer holds the audit-search role, if it was revoked:
Get-RoleGroupMember -Identity 'View-Only Organization Management' | Where-Object { $_.Name -eq '<service principal display name>' }
```

For the assessment itself, the only verification is in the portal: confirm it no longer appears on
the **Assessments** page (Stage 3), and, if any of `assess-against-iso27001`, `pci-dss-assessment`,
or `soc2-assessment` remain, confirm those assessments and their shared group are both still
present and unaffected.
