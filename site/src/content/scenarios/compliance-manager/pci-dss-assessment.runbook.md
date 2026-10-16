---
part: "runbook"
parent: "compliance-manager/pci-dss-assessment"
---
## Implementation steps

### Portal path - creating the assessment (there is no script path for this part; see why this matters/the design notes)

1. Before starting, decide the group and role assignments - see
   `deploy/policy/pci-dss-assessment-manifest.json`. **Both decisions are effectively permanent**:
   an assessment's group can't be changed after creation, and groups themselves can't be deleted.
2. **Check whether *Assess Against ISO/IEC 27001:2022* (or any other
   Compliance Manager assessment using the `Security & Compliance Assessments` group) is already
   deployed in this tenant.** If yes, plan to **add** this assessment to that group in step 5
   below, not create a new one - see the design notes for exactly what that buys you (nontechnical
   improvement-action sharing, not the broader "everything syncs" read a quick skim might suggest).
3. **(Recommended order, not required)** Deploy this library's PCI-relevant technical scenarios
   first if not already in place - see the manifest's `recommendedDeploymentOrder` and
   the design notes's control crosswalk. Compliance Manager's built-in automation detects signals from
   Data Lifecycle Management, Information Protection, DLP, Communication Compliance, and Insider
   Risk Management, and those signals sync to this assessment **regardless of
   which group it ends up in** - so deployment order matters, group choice doesn't,
   for this part.
4. Sign in to the [Microsoft Purview portal](https://purview.microsoft.com) → **Compliance
   Manager** → **Assessments** → **Add assessment**.
5. On **Base your assessment on a regulation** → **Select regulation** → search for **PCI DSS** →
   **you will see two results: "PCI DSS v3.2.1" and "PCI DSS v4.0."** Select **PCI DSS v4.0** -
   v3.2.1 is a retired PCI Security Standards Council revision still listed in the catalog
   - → **Save** → confirm → **Next**.
6. On **Add name and group**: enter a unique assessment name (this scenario's default:
   `PCI DSS v4.0 - Microsoft 365 Estate`). If step 2 found an existing `Security & Compliance
   Assessments` group, choose it under **Add to existing group**. Otherwise choose **Create new
   group** with that same name (so a future assessment finds it) → **Next**.
7. On **Select services**: select **Microsoft 365** only, per this scenario's scope (the design notes - multicloud scoping via Defender for Cloud is a documented but explicitly out-of-scope
   extension) → **Next**.
8. **Review and finish**: confirm the regulation (PCI DSS v4.0), name, group, and services →
   **Create assessment** → **Done**.
9. From the new assessment's details page → **Manage user access**: assign
   Contributor/Assessor/Reader roles per the manifest's `roleAssignments`.
10. **Do not** rely on the tenant's default **Data Protection Baseline** assessment as a substitute
    for steps 4-8 - see the design notes (identical reasoning to
    *Assess Against ISO/IEC 27001:2022* (the implementation steps)).

### Ongoing portal work - testing and evidencing controls (also has no script path)

11. **Improvement actions** tab: for actions with **Automatic** testing type, confirm they've
    picked up a status from the built-in automation signals described in step 3 before doing any
    manual work on them.
12. For actions requiring manual work: assign an owner, complete implementation, upload evidence,
    submit for testing - a **Compliance Manager Assessor** validates and sets Pass/Fail.
13. For bulk updates: use **Export actions** → edit the **Action Update** tab per its embedded
    instructions → **Update actions** to re-upload - Microsoft's own documented mechanism, with no
    faster scripted path as of this writing (the design notes Non-goals).
14. **If this assessment shares its group with *Assess Against ISO/IEC 27001:2022***: when you complete a
    **nontechnical** improvement action common to both regulations (e.g. a documented information
    security policy, a personnel background-check policy), verify the update is reflected in the
    other assessment too - this is the concrete payoff of the group-placement decision from step 6, and is worth spot-checking once so the team trusts it's actually working.

### Script path - the audit-trail export (reused, not duplicated - see the design notes)

```powershell
# 1. Connect (certificate app-only - see Automation surface, section 3). The connecting identity
# needs Exchange.ManageAsApp PLUS the View-Only Audit Logs Exchange Online role (RBAC model, section 6).
Connect-ExchangeOnline -AppId $AppId -Certificate $Cert -Organization $TenantDomain

# 2. If Assess Against ISO/IEC 27001:2022 is ALSO deployed in this tenant, run
# only ONE instance of Export-ComplianceManagerAuditTrail.ps1 (either copy - they're identical;
# see the design notes Section 2) against a single shared CSV path. The commands below assume this is
# the only Compliance Manager assessment in the tenant so far.

# 3. Dry run - queries the last 7 days, reports what would be merged, writes nothing
./deploy/Export-ComplianceManagerAuditTrail.ps1 -OutputCsvPath './out/compliance-manager-audit-trail.csv' -WhatIf

# 4. First real run - a one-time backfill covering the full default retention window
./deploy/Export-ComplianceManagerAuditTrail.ps1 `
    -StartDate (Get-Date).AddDays(-180) -EndDate (Get-Date) `
    -OutputCsvPath './out/compliance-manager-audit-trail.csv'

# 5. Recurring run (schedule daily or weekly - overlapping windows are safe, see the design notes)
./deploy/Export-ComplianceManagerAuditTrail.ps1 -OutputCsvPath './out/compliance-manager-audit-trail.csv'

# 6. Validate the audit trail AND this scenario's own control-crosswalk manifest
./validate/Test-ComplianceManagerAuditTrail.ps1 -AuditTrailCsvPath './out/compliance-manager-audit-trail.csv'
```

## Configuration reference

| Setting | Value this scenario uses | Notes |
|---|---|---|
| Regulation/template | PCI DSS v4.0 | Premium template - do **not** select the separately-listed, retired PCI DSS v3.2.1 |
| Assessment name | `PCI DSS v4.0 - Microsoft 365 Estate` | Effectively permanent once created |
| Group | `Security & Compliance Assessments` (join if present, else create new) | Buys nontechnical improvement-action sharing with *Assess Against ISO/IEC 27001:2022* - the design notes |
| Services in scope | Microsoft 365 only | Multicloud is an explicit non-goal - the design notes |
| Recommended role split | Administration: 1-2 people · Contribution/Assessor: control owners across IT/Security/Legal/Finance · Reader: auditors/QSA/leadership | See `deploy/policy/pci-dss-assessment-manifest.json` |
| Control crosswalk | 6 PCI DSS goals mapped to this library's scenarios | `deploy/policy/pci-dss-assessment-manifest.json`'s `controlCrosswalk` - this library's own correlation, not Microsoft's mapping |
| Audit-trail script | Reused from `assess-against-iso27001/deploy/`, not duplicated | Tenant-wide operations - the design notes |
| Audit-trail script idempotency | Merge + de-duplicate by `(CreationDate, Operations, UserIds, hash(AuditData))` | Identical model to *Assess Against ISO/IEC 27001:2022* - see that scenario's the design notes |
| Validate script additions | Crosswalk manifest structural check + stale-scenario-path check | New in this scenario - see `validate/Test-ComplianceManagerAuditTrail.ps1`'s `.DESCRIPTION` |

## Operations and tuning

**Review cadence:** run the audit-trail export on a **recurring schedule** - daily is cheap and
safe, weekly is the practical minimum given Audit (Standard)'s 180-day retention. Review the
**Controls** tab and compliance-score trend at least **monthly**. Review role-assignment and
automation-trust events **immediately** on the audit-trail script's own warning, not on the monthly
cadence - identical operational posture to *Assess Against ISO/IEC 27001:2022* (operations and tuning). PCI DSS's own
Requirement 12 domain (Maintain an Information Security Policy) explicitly expects a formally
managed, ongoing compliance program - **VERIFY** the exact review-frequency obligation your
organization's merchant/service-provider level and QSA/ISA require against the current PCI DSS v4.0
standard; this scenario deliberately does not hard-code an assumed cadence
(e.g. "quarterly") into its tooling, since that obligation depends on facts (merchant level,
service-provider status) outside this scenario's scope to assume.

**KPIs to watch:** identical four KPIs to *Assess Against ISO/IEC 27001:2022* (compliance score
trend, automated-vs-manual improvement-action ratio, `ComplianceManagerRolesChange` volume,
any automation-trust-change event at all - near-zero tolerance), plus one new one specific to this
scenario:

- **Group-sharing drift** - if a nontechnical improvement action common to both this assessment and
  *Assess Against ISO/IEC 27001:2022* is updated in one but the update doesn't appear in the other within a
  reasonable time, treat it as a signal the two assessments may no longer share a group (perhaps
  because one was deleted and recreated - the rollback runbook), not as a Compliance Manager bug.

**Incident-response runbook (automation-trust change detected):** identical to
*Assess Against ISO/IEC 27001:2022* (operations and tuning) steps 1-5 - triage the `AuditData` JSON, classify
planned/unplanned, document or escalate accordingly.

## Rollback and decommission

See the rollback runbook for the full procedure. Because this scenario may share a group with
*Assess Against ISO/IEC 27001:2022*, its rollback has one extra consideration that scenario's rollback
doesn't: deleting this assessment does not delete or affect the shared group or the other
assessment in it.

## References

1. Payment Card Industry (PCI) Data Security Standard (DSS) - Office 365/Microsoft 365 applicability, in-scope services, customer responsibility for their own PCI DSS compliance - <https://learn.microsoft.com/compliance/regulatory/offering-pci-dss>
2. PCI Security Standards Council - official PCI DSS v4.0.1 standard and Quick Reference Guide (SAQ/RoC/QSA terminology, the 6 control goals/12 requirements structure) - <https://docs-prv.pcisecuritystandards.org/PCI%20DSS/Standard/PCI-DSS-v4_0_1.pdf> and <https://docs-prv.pcisecuritystandards.org/PCI%20DSS/Supporting%20Document/PCI-DSS-v4_x-QRG.pdf>
3. (see reference 1) "Use Microsoft Purview Compliance Manager to assess your risk" section
4. Get started with Compliance Manager (role types table incl. Entra role mapping) - <https://learn.microsoft.com/purview/compliance-manager-setup>
5. Build and manage assessments in Compliance Manager (create-assessment wizard, Groups for assessments - technical-vs-nontechnical improvement-action sync scope, one-assessment-per-product-per-regulation-per-group rule, groups can't be deleted, Data Protection Baseline default, Export an assessment report, Delete an assessment) - <https://learn.microsoft.com/purview/compliance-manager-assessments>
6. Payment Card Industry (PCI) Data Security Standard (DSS) - Microsoft and PCI DSS (Azure/OneDrive/SharePoint/Azure Communication Service certified under PCI DSS v4.0.1) - <https://learn.microsoft.com/compliance/regulatory/offering-pci-dss#microsoft-and-pci-dss>
7. (see reference 1) "It's important to understand that PCI DSS compliance status... doesn't automatically translate to PCI DSS certification for the services that customers build or host on these platforms" (Frequently asked questions)
8. Microsoft Purview service description - Compliance Manager - <https://learn.microsoft.com/office365/servicedescriptions/microsoft-365-service-descriptions/microsoft-365-tenantlevel-services-licensing-guidance/microsoft-purview-service-description#microsoft-purview-compliance-manager>
9. Compliance Manager regulations list (premium regulations, including both "PCI DSS v3.2.1" and "PCI DSS v4.0" as separate catalog entries; December 2022 licensing change; 3-free-templates allotment) - <https://learn.microsoft.com/purview/compliance-manager-regulations-list>
10. Working with improvement actions in Compliance Manager (built-in automation from DLM/Information Protection/DLP/Communication Compliance/IRM; automated testing/monitoring) - <https://learn.microsoft.com/purview/compliance-manager-improvement-actions>
11. (see reference 10) "Assign improvement action to assessor for completion"
12. Update improvement actions and bring compliance data into Compliance Manager (Export actions / Action Update tab / Update actions wizard) - <https://learn.microsoft.com/purview/compliance-manager-update-actions>
13. Manage audit log retention policies (180-day Standard default, 1-year E5 default for Entra/Exchange/OneDrive/SharePoint, up to 10 years with Audit Premium retention policies) - <https://learn.microsoft.com/purview/audit-log-retention-policies>
14. Compliance Manager frequently asked questions (a high score is not proof of compliance) - <https://learn.microsoft.com/purview/compliance-manager-faq>
15. Audit log activities - Compliance Manager activities table (the 3 documented operations) - <https://learn.microsoft.com/purview/audit-log-activities#compliance-manager-activities>
16. Search-UnifiedAuditLog reference - <https://learn.microsoft.com/powershell/module/exchangepowershell/search-unifiedauditlog>
17. *PCI Teams Card-Data Exfiltration Block* - this library's primary PCI DSS Requirement 4 technical control, cross-referenced throughout this scenario.

> Re-verify all links, the two-PCI-DSS-templates catalog detail, and the premium-template licensing
> model against current Microsoft Learn before a customer-facing assessment or sale - Compliance
> Manager's regulation catalog and licensing rules have changed materially before and can change
> again.