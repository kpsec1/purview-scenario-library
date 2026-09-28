---
part: "runbook"
parent: "compliance-manager/soc2-assessment"
---
## Implementation steps

### Portal path - creating the assessment (there is no script path for this part; see why this matters/the design notes)

1. Before starting, decide the group and role assignments - see
   `deploy/policy/soc2-assessment-manifest.json`. **Both decisions are effectively permanent**: an
   assessment's group can't be changed after creation, and groups themselves can't be deleted.
2. **Check whether *Assess Against ISO/IEC 27001:2022* and/or `scenarios/
   compliance-manager/pci-dss-assessment/` (or any other Compliance Manager assessment using the
   `Security & Compliance Assessments` group) are already deployed in this tenant.** If yes, plan to
   **add** this assessment to that group in step 6 below, not create a new one - see the design notes
   for exactly what that buys you (nontechnical improvement-action sharing, not the broader
   "everything syncs" read a quick skim might suggest).
3. **(Recommended order, not required)** Deploy this library's SOC 2-relevant technical scenarios
   first if not already in place - see the manifest's `recommendedDeploymentOrder` and the design notes's control crosswalk. Compliance Manager's built-in automation detects signals from Data
   Lifecycle Management, Information Protection, DLP, Communication Compliance, and Insider Risk
   Management, and those signals sync to this assessment **regardless of which
   group it ends up in** - so deployment order matters, group choice doesn't, for
   this part.
4. Sign in to the [Microsoft Purview portal](https://purview.microsoft.com) → **Compliance
   Manager** → **Assessments** → **Add assessment**.
5. On **Base your assessment on a regulation** → **Select regulation** → search for **SOC** → **you
   will see two results: "System and Organization Controls (SOC) 1" and "System and Organization
   Controls (SOC) 2."** Select **SOC 2** - SOC 1 covers a different Trust Services scope (a service
   organization's effect on a customer's **financial reporting** controls, per SSAE 18) and is the
   wrong template for a general security/confidentiality/privacy readiness assessment - →
   **Save** → confirm → **Next**.
6. On **Add name and group**: enter a unique assessment name (this scenario's default: `SOC 2 -
   Microsoft 365 Estate`). If step 2 found an existing `Security & Compliance Assessments` group,
   choose it under **Add to existing group**. Otherwise choose **Create new group** with that same
   name (so a future assessment finds it) → **Next**.
7. On **Select services**: select **Microsoft 365** only, per this scenario's scope (the design notes - multicloud scoping via Defender for Cloud is a documented but explicitly out-of-scope
   extension) → **Next**.
8. **Review and finish**: confirm the regulation (SOC 2), name, group, and services → **Create
   assessment** → **Done**.
9. From the new assessment's details page → **Manage user access**: assign
   Contributor/Assessor/Reader roles per the manifest's `roleAssignments`.
10. **Do not** rely on the tenant's default **Data Protection Baseline** assessment as a substitute
    for steps 4-8 - see the design notes (identical reasoning to *Assess Against ISO/IEC 27001:2022* (the implementation steps) and *PCI DSS v4.0 Assessment* (the implementation steps)).

### Ongoing portal work - testing and evidencing controls (also has no script path)

11. **Improvement actions** tab: for actions with **Automatic** testing type, confirm they've
    picked up a status from the built-in automation signals described in step 3 before doing any
    manual work on them.
12. For actions requiring manual work: assign an owner, complete implementation, upload evidence,
    submit for testing - a **Compliance Manager Assessor** validates and sets Pass/Fail.
13. For bulk updates: use **Export actions** → edit the **Action Update** tab per its embedded
    instructions → **Update actions** to re-upload - Microsoft's own documented mechanism, with no
    faster scripted path as of this writing (the design notes Non-goals).
14. **If this assessment shares its group with *Assess Against ISO/IEC 27001:2022* and/or
    *PCI DSS v4.0 Assessment***: when you complete a **nontechnical** improvement action common across
    them (e.g. a documented information security policy, a personnel background-check policy, an
    incident response plan), verify the update is reflected in the other assessment(s) too - this
    is the concrete payoff of the group-placement decision from step 6, and is
    worth spot-checking once so the team trusts it's actually working.
15. **When a CPA firm engagement begins**: grant the engaged firm's contacts **Compliance Manager
    Reader** access (or export the relevant reports for them, the validation steps) rather than treating this
    assessment's score as something you hand over in place of direct evidence review - the CPA firm
    still performs its own independent testing regardless of what this assessment shows.

### Script path - the audit-trail export (reused, not duplicated - see the design notes)

```powershell
# 1. Connect (certificate app-only - see Automation surface, section 3). The connecting identity
# needs Exchange.ManageAsApp PLUS the View-Only Audit Logs Exchange Online role (RBAC model, section 6).
Connect-ExchangeOnline -AppId $AppId -Certificate $Cert -Organization $TenantDomain

# 2. If Assess Against ISO/IEC 27001:2022 and/or .../pci-dss-assessment/ are
# ALSO deployed in this tenant, run only ONE instance of Export-ComplianceManagerAuditTrail.ps1
# (any copy - they're identical; see the design notes Section 2) against a single shared CSV path. The
# commands below assume this is the only Compliance Manager assessment in the tenant so far.

# 3. Dry run - queries the last 7 days, reports what would be merged, writes nothing
./deploy/Export-ComplianceManagerAuditTrail.ps1 -OutputCsvPath './out/compliance-manager-audit-trail.csv' -WhatIf

# 4. First real run - a one-time backfill covering the full default retention window
./deploy/Export-ComplianceManagerAuditTrail.ps1 `
    -StartDate (Get-Date).AddDays(-180) -EndDate (Get-Date) `
    -OutputCsvPath './out/compliance-manager-audit-trail.csv'

# 5. Recurring run (schedule daily or weekly - overlapping windows are safe, see the design notes).
# Keep this running for the full duration of any SOC 2 Type II period of performance.
./deploy/Export-ComplianceManagerAuditTrail.ps1 -OutputCsvPath './out/compliance-manager-audit-trail.csv'

# 6. Validate the audit trail AND this scenario's own control-crosswalk manifest
./validate/Test-ComplianceManagerAuditTrail.ps1 -AuditTrailCsvPath './out/compliance-manager-audit-trail.csv'
```

## Configuration reference

| Setting | Value this scenario uses | Notes |
|---|---|---|
| Regulation/template | System and Organization Controls (SOC) 2 | Premium template - do **not** select the separately-listed SOC 1 template |
| Assessment name | `SOC 2 - Microsoft 365 Estate` | Effectively permanent once created |
| Group | `Security & Compliance Assessments` (join if present, else create new) | Buys nontechnical improvement-action sharing with *Assess Against ISO/IEC 27001:2022*/*PCI DSS v4.0 Assessment* - the design notes |
| Services in scope | Microsoft 365 only | Multicloud is an explicit non-goal - the design notes |
| Recommended role split | Administration: 1-2 people · Contribution/Assessor: control owners across IT/Security/Engineering/HR · Reader: engaged CPA firm/leadership | See `deploy/policy/soc2-assessment-manifest.json` |
| Control crosswalk | 5 AICPA 2017 Trust Services Criteria categories mapped to this library's scenarios | `deploy/policy/soc2-assessment-manifest.json`'s `controlCrosswalk` - this library's own correlation, not Microsoft's mapping |
| Audit-trail script | Reused from `assess-against-iso27001/deploy/`, not duplicated | Tenant-wide operations - the design notes |
| Audit-trail script idempotency | Merge + de-duplicate by `(CreationDate, Operations, UserIds, hash(AuditData))` | Identical model to *Assess Against ISO/IEC 27001:2022*/*PCI DSS v4.0 Assessment* - see that scenario's the design notes |
| Validate script additions | Crosswalk manifest structural check (5 TSC categories) + stale-scenario-path check | New in this scenario - see `validate/Test-ComplianceManagerAuditTrail.ps1`'s `.DESCRIPTION` |

## Operations and tuning

**Review cadence:** run the audit-trail export on a **recurring schedule** - daily is cheap and
safe, weekly is the practical minimum given Audit (Standard)'s 180-day retention. This matters
more here than for the ISO 27001/PCI DSS siblings: **if this tenant is preparing for a SOC 2 Type II
report**, the audit trail needs to cover the **full period of performance** (typically 6-12 months
), which exceeds the 180-day Standard default - start the recurring schedule
before the period of performance begins, or run periodic backfills to bridge the gap, and consider
Audit Premium retention policies if a longer native retention window is preferable to relying on
this script's own accumulated CSV ([Licensing matrix](/docs/licensing-matrix/)). Review the **Controls** tab and
compliance-score trend at least **monthly**. Review role-assignment and automation-trust events
**immediately** on the audit-trail script's own warning, not on the monthly cadence - identical
operational posture to *Assess Against ISO/IEC 27001:2022* (operations and tuning) and *PCI DSS v4.0 Assessment* (operations and tuning).

**KPIs to watch:** identical four KPIs to *Assess Against ISO/IEC 27001:2022* (compliance score
trend, automated-vs-manual improvement-action ratio, `ComplianceManagerRolesChange` volume, any
automation-trust-change event at all - near-zero tolerance), plus one new one specific to this
scenario:

- **Group-sharing drift** - if a nontechnical improvement action common to this assessment and
  *Assess Against ISO/IEC 27001:2022*/*PCI DSS v4.0 Assessment* is updated in one but the update doesn't appear in
  the other(s) within a reasonable time, treat it as a signal the assessments may no longer share a
  group (perhaps because one was deleted and recreated - the rollback runbook), not as a Compliance Manager
  bug.
- **Evidence-window continuity** - if a SOC 2 Type II period of performance is underway, treat any
  gap in the audit-trail CSV's coverage (a missed scheduled run, a deleted output file) as a
  potential hole in the evidence a CPA firm may later ask about - closing it retroactively is not
  always possible once the audit-log retention window has expired.

**Incident-response runbook (automation-trust change detected):** identical to
*Assess Against ISO/IEC 27001:2022* (operations and tuning) steps 1-5 - triage the `AuditData` JSON, classify
planned/unplanned, document or escalate accordingly.

## Rollback and decommission

See the rollback runbook for the full procedure. Because this scenario may share a group with
*Assess Against ISO/IEC 27001:2022* and/or *PCI DSS v4.0 Assessment*, its rollback has one extra consideration
those scenarios' own rollback docs already describe: deleting this assessment does not delete or
affect the shared group or the other assessment(s) in it.

## References

1. System and Organization Controls (SOC) 2 Type 2 - AICPA Trust Services Criteria (Security, Availability, Processing Integrity, Confidentiality, Privacy), SSAE No. 18 basis, "Use Microsoft Purview Compliance Manager to assess your risk" - <https://learn.microsoft.com/compliance/regulatory/offering-soc-2>
2. (see reference 1) "How often are Office 365 SOC reports issued?" - Microsoft commissions a full SOC 1 Type 2 and SOC 2 Type 2 examination of Office 365 annually; SOC Type 2 audits examine a rolling 12-month period of performance (October 1 - September 30)
3. AICPA - SOC 2 Reporting on an Examination of Controls at a Service Organization (Type I vs. Type II distinction; Type II period of performance) - <https://future.aicpa.org/cpe-learning/publication/soc-2-reporting-on-an-examination-of-controls-at-a-service-organization-relevant-to-security-availability-processing-integrity-confidentiality-or-privacy-OPL> and SSAE No. 18 reference in
4. Get started with Compliance Manager - assessment templates page - <https://learn.microsoft.com/purview/compliance-manager-setup>
5. Microsoft Purview service description - Compliance Manager - <https://learn.microsoft.com/office365/servicedescriptions/microsoft-365-service-descriptions/microsoft-365-tenantlevel-services-licensing-guidance/microsoft-purview-service-description#microsoft-purview-compliance-manager>
6. Compliance Manager regulations list - Global premium regulations, including both "System and Organization Controls (SOC) 1" and "System and Organization Controls (SOC) 2" as separate catalog entries; 3-free-templates allotment - <https://learn.microsoft.com/purview/compliance-manager-regulations-list#premium-regulations>
7. Get started with Compliance Manager (role types table incl. Entra role mapping) - <https://learn.microsoft.com/purview/compliance-manager-setup>
8. Build and manage assessments in Compliance Manager (create-assessment wizard, Groups for assessments - technical-vs-nontechnical improvement-action sync scope, one-assessment-per-product-per-regulation-per-group rule, groups can't be deleted, Data Protection Baseline default, Export an assessment report, Delete an assessment) - <https://learn.microsoft.com/purview/compliance-manager-assessments>
9. Working with improvement actions in Compliance Manager (built-in automation from DLM/Information Protection/DLP/Communication Compliance/IRM; automated testing/monitoring) - <https://learn.microsoft.com/purview/compliance-manager-improvement-actions>
10. (see reference 9) "Assign improvement action to assessor for completion"
11. Update improvement actions and bring compliance data into Compliance Manager (Export actions / Action Update tab / Update actions wizard) - <https://learn.microsoft.com/purview/compliance-manager-update-actions>
12. Manage audit log retention policies (180-day Standard default, 1-year E5 default for Entra/Exchange/OneDrive/SharePoint, up to 10 years with Audit Premium retention policies) - <https://learn.microsoft.com/purview/audit-log-retention-policies>
13. Compliance Manager frequently asked questions (a high score is not proof of compliance) - <https://learn.microsoft.com/purview/compliance-manager-faq>
14. Audit log activities - Compliance Manager activities table (the 3 documented operations) - <https://learn.microsoft.com/purview/audit-log-activities#compliance-manager-activities>
15. Search-UnifiedAuditLog reference - <https://learn.microsoft.com/powershell/module/exchangepowershell/search-unifiedauditlog>
16. *PCI DSS v4.0 Assessment* and *Assess Against ISO/IEC 27001:2022* - this library's sibling Compliance Manager assessments, cross-referenced throughout this scenario for the shared group/audit-trail-script pattern.

> Re-verify all links, the SOC 1/SOC 2 catalog-naming detail, and the premium-template licensing
> model against current Microsoft Learn before a customer-facing assessment or sale - Compliance
> Manager's regulation catalog and licensing rules have changed materially before and can change
> again.