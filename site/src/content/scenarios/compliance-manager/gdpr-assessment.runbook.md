---
part: "runbook"
parent: "compliance-manager/gdpr-assessment"
---
## Implementation steps

### Portal path - creating the assessment (there is no script path for this part; see why this matters/the design notes)

1. Before starting, decide the group and role assignments - see `deploy/policy/gdpr-assessment-manifest.json`. **Both decisions are effectively permanent**: an assessment's group can't be
   changed after creation, and groups themselves can't be deleted.
2. **Check whether *Assess Against ISO/IEC 27001:2022*, *PCI DSS v4.0 Assessment*, *SOC 2 Assessment*, and/or `scenarios/
   compliance-manager/hipaa-hitech-assessment/` (or any other Compliance Manager assessment using
   the `Security & Compliance Assessments` group) are already deployed in this tenant.** If yes, plan
   to **add** this assessment to that group in step 6 below, not create a new one - see the design notes for exactly what that buys you (nontechnical improvement-action sharing, not the broader
   "everything syncs" read a quick skim might suggest).
3. **(Recommended order, not required)** Deploy this library's GDPR-relevant technical scenarios
   first if not already in place - see the manifest's `recommendedDeploymentOrder` and the design notes's control crosswalk. Compliance Manager's built-in automation detects signals from Data
   Lifecycle Management, Information Protection, DLP, and Insider Risk Management, and those signals sync to this assessment **regardless of which group it
   ends up in** - so deployment order matters, group choice doesn't, for this part.
4. Sign in to the [Microsoft Purview portal](https://purview.microsoft.com) → **Compliance
   Manager** → **Assessments** → **Add assessment**.
5. On **Base your assessment on a regulation** → **Select regulation** → search for **GDPR** →
   **confirm you select "EU GDPR (General Data Protection Regulation)"**, listed under the
   **Europe, Middle East, and Africa (EMEA)** category - the catalog separately lists a **"UK Data
   Protection Act"** template (the UK's own post-Brexit implementing statute, which itself
   incorporates "UK GDPR"); it is a different jurisdiction and regulator (the UK Information
   Commissioner's Office, not an EU/EEA DPA) and is **not** interchangeable with this template if
   the organization has UK-specific obligations too → **Save** → confirm → **Next**.
6. On **Add name and group**: enter a unique assessment name (this scenario's default: `EU GDPR -
   Microsoft 365 Estate`). If step 2 found an existing `Security & Compliance Assessments` group,
   choose it under **Add to existing group**. Otherwise choose **Create new group** with that same
   name (so a future assessment finds it) → **Next**.
7. On **Select services**: select **Microsoft 365** only, per this scenario's scope (the design notes
   - Microsoft documents that a single EU GDPR assessment can span Microsoft 365, Azure, AWS, and
   GCP together, but multicloud scoping is an explicit out-of-scope extension for this scenario) →
   **Next**.
8. **Review and finish**: confirm the regulation (EU GDPR), name, group, and services → **Create
   assessment** → **Done**.
9. From the new assessment's details page → **Manage user access**: assign Contributor/Assessor/
   Reader roles per the manifest's `roleAssignments`.
10. **Determine whether Article 37 requires this organization to designate a Data Protection
    Officer** - large-scale systematic monitoring, large-scale special-category data processing,
    or public-authority processing. Unlike the HIPAA/HITECH sibling scenario's blanket officer
    designation, this is **conditional**: document the determination either way rather than assuming
    a DPO is (or isn't) required.
11. **Do not** rely on the tenant's default **Data Protection Baseline** assessment as a substitute
    for steps 4-8. Unlike the reasoning in the four sibling scenarios' own design notes, the
    Baseline's own documented composition **does** explicitly draw on GDPR as one of its four source
    frameworks (alongside NIST CSF, ISO, and FedRAMP) - but it *blends* those elements into a
    cross-framework composite score, not a citable, complete, GDPR-only control set.

### Ongoing portal work - testing and evidencing controls (also has no script path)

12. **Improvement actions** tab: for actions with **Automatic** testing type, confirm they've picked
    up a status from the built-in automation signals described in step 3 before doing any manual
    work on them.
13. For actions requiring manual work: assign an owner, complete implementation, upload evidence,
    submit for testing - a **Compliance Manager Assessor** validates and sets Pass/Fail. For actions mapped to **Data Subject Rights**, confirm the evidence
    documents an actual, repeatable process (not just a one-time test) - Discovery, Access,
    Rectification, Restriction, Export, and Deletion are all six activities a real DSR intake process
    must handle.
14. For bulk updates: use **Export actions** → edit the **Action Update** tab per its embedded
    instructions → **Update actions** to re-upload - Microsoft's own documented mechanism, with no
    faster scripted path as of this writing (the design notes Non-goals).
15. **If this assessment shares its group with *Assess Against ISO/IEC 27001:2022*, *PCI DSS v4.0 Assessment*,
    *SOC 2 Assessment*, and/or *HIPAA/HITECH Assessment***: when you complete a **nontechnical**
    improvement action common across them (e.g. a documented information security policy, a
    personnel background-check policy, an incident response plan), verify the update is reflected in
    the other assessment(s) too - this is the concrete payoff of the group-placement decision from
    step 6, and is worth spot-checking once so the team trusts it's actually
    working.
16. **If a Data Protection Authority ever opens an inquiry, or a business partner requests
    due-diligence evidence**: grant the relevant contacts **Compliance Manager Reader** access (or
    export the relevant reports for them, the validation steps) rather than treating this assessment's score as
    something you hand over in place of the organization's own required Article 30 Records of
    Processing Activities or direct evidence of a lawful basis for processing.

### Script path - the audit-trail export (reused, not duplicated - see the design notes)

```powershell
# 1. Connect (certificate app-only - see docs/automation-surface.md §3). The connecting identity
#    needs Exchange.ManageAsApp PLUS the View-Only Audit Logs Exchange Online role (docs/rbac-model.md §6).
Connect-ExchangeOnline -AppId $AppId -Certificate $Cert -Organization $TenantDomain

# 2. If scenarios/compliance-manager/assess-against-iso27001/, .../pci-dss-assessment/,
#    .../soc2-assessment/, and/or .../hipaa-hitech-assessment/ are ALSO deployed in this tenant, run
#    only ONE instance of Export-ComplianceManagerAuditTrail.ps1 (any copy - they're identical; see
#    design.md Section 2) against a single shared CSV path. The commands below assume this is the
#    only Compliance Manager assessment in the tenant so far.

# 3. Dry run - queries the last 7 days, reports what would be merged, writes nothing
./deploy/Export-ComplianceManagerAuditTrail.ps1 -OutputCsvPath './out/compliance-manager-audit-trail.csv' -WhatIf

# 4. First real run - a one-time backfill covering the full default retention window
./deploy/Export-ComplianceManagerAuditTrail.ps1 `
    -StartDate (Get-Date).AddDays(-180) -EndDate (Get-Date) `
    -OutputCsvPath './out/compliance-manager-audit-trail.csv'

# 5. Recurring run (schedule daily or weekly - overlapping windows are safe, see design.md §4).
#    Retain the accumulated CSV per the organization's own Article 5(1)(e) storage-limitation
#    record-retention schedule (README.md Section 8) - GDPR does not prescribe a fixed number of
#    years the way HIPAA's 45 CFR Section 164.316(b)(2)(i) does.
./deploy/Export-ComplianceManagerAuditTrail.ps1 -OutputCsvPath './out/compliance-manager-audit-trail.csv'

# 6. Validate the audit trail AND this scenario's own control-crosswalk manifest
./validate/Test-ComplianceManagerAuditTrail.ps1 -AuditTrailCsvPath './out/compliance-manager-audit-trail.csv'
```

## Configuration reference

| Setting | Value this scenario uses | Notes |
|---|---|---|
| Regulation/template | EU GDPR (General Data Protection Regulation) | Premium template, EMEA category - do **not** select the separately-listed "UK Data Protection Act" template |
| Assessment name | `EU GDPR - Microsoft 365 Estate` | Effectively permanent once created |
| Group | `Security & Compliance Assessments` (join if present, else create new) | Buys nontechnical improvement-action sharing with *Assess Against ISO/IEC 27001:2022*/*PCI DSS v4.0 Assessment*/*SOC 2 Assessment*/*HIPAA/HITECH Assessment* - the design notes |
| Services in scope | Microsoft 365 only | Multicloud is documented as a genuinely available option for this template, but is an explicit non-goal here - the design notes |
| Recommended role split | Administration: 1-2 people (ideally the Data Protection Officer, if designated, or a delegate from Legal/Privacy) · Contribution/Assessor: control owners across IT/Security/Legal/Privacy · Reader: leadership and the Data Protection Officer if not already a Contributor | See `deploy/policy/gdpr-assessment-manifest.json` |
| Control crosswalk | 6 categories mapped to GDPR's own published structure (Data Subject Rights, Data Processing Principles, Breach Notification, Data Protection Impact Assessment, Cross-Border Data Transfers, Accountability & Governance), correlated against this library's own scenarios | `deploy/policy/gdpr-assessment-manifest.json`'s `controlCrosswalk` - this library's own correlation, not Microsoft's mapping |
| DPO designation | Documented as conditional (Article 37 applicability criteria), never assumed | Genuine contrast with HIPAA's blanket officer-designation requirement - the prerequisites and the known limitations |
| Audit-trail script | Reused from `assess-against-iso27001/deploy/`, not duplicated | Tenant-wide operations - the design notes |
| Audit-trail script idempotency | Merge + de-duplicate by `(CreationDate, Operations, UserIds, hash(AuditData))` | Identical model to the four sibling scenarios - see that scenario's the design notes |
| Validate script additions | Crosswalk manifest structural check (6 categories + articleCitation/coverage completeness) + stale-scenario-path check | New in this scenario - see `validate/Test-ComplianceManagerAuditTrail.ps1`'s `.DESCRIPTION` |

## Operations and tuning

**Review cadence:** run the audit-trail export on a **recurring schedule** - daily is cheap and safe,
weekly is the practical minimum given Audit (Standard)'s 180-day retention. Unlike the
HIPAA/HITECH sibling, GDPR does not prescribe a fixed retention period for accountability evidence
the way HIPAA's Security Rule prescribes six years - Article 5(2)'s accountability principle requires
being able to **demonstrate** compliance, and Article 5(1)(e)'s storage-limitation principle requires
the organization to have (and follow) its own documented retention schedule. Align the archived CSV's
retention with that schedule rather than assuming Audit (Standard)'s native window is sufficient, and
rather than inventing a specific number of years this scenario has no grounded basis to assert.
Review the **Controls** tab and compliance-score trend at least **monthly**. Review role-assignment
and automation-trust events **immediately** on the audit-trail script's own warning, not on the
monthly cadence - identical operational posture to the four sibling scenarios.

**KPIs to watch:** identical four KPIs to the sibling scenarios (compliance score trend,
automated-vs-manual improvement-action ratio, `ComplianceManagerRolesChange` volume, any
automation-trust-change event at all - near-zero tolerance), plus two new ones specific to this
scenario:

- **Group-sharing drift** - if a nontechnical improvement action common to this assessment and
  *Assess Against ISO/IEC 27001:2022*/*PCI DSS v4.0 Assessment*/*SOC 2 Assessment*/*HIPAA/HITECH Assessment* is
  updated in one but the update doesn't appear in the other(s) within a reasonable time, treat it as
  a signal the assessments may no longer share a group, not as a Compliance Manager bug.
- **Data Subject Request volume and SLA** - *GDPR Data Subject Request (DSR) Fulfillment* now
  provides the request-tracking/SLA layer this section originally flagged as missing (the known limitations,
  the design notes updated accordingly). If DSR volume grows past what that scenario's flat-file
  ledger can support (its own the cost and licensing notes and the known limitations name the point at which Microsoft Priva's
  purpose-built Subject Rights Requests workflow becomes the better answer), treat that as a signal
  this assessment's score will not surface on its own.

**Incident-response runbook (automation-trust change detected):** identical to
*Assess Against ISO/IEC 27001:2022* (operations and tuning) steps 1-5 - triage the `AuditData` JSON, classify
planned/unplanned, document or escalate accordingly. **If the automation-trust change coincides with
a suspected or confirmed personal data breach**: separately trigger this library's *Compromised Account Incident Response* runbook and the organization's own Article 33/34 breach-notification procedure (the 72-hour DPA notification clock starts when the organization becomes aware
of the breach, not when this assessment's audit trail happens to be reviewed) - this scenario's audit
trail is evidence for that response, not a substitute for it.

## Rollback and decommission

See the rollback runbook for the full procedure. Because this scenario may share a group with
*Assess Against ISO/IEC 27001:2022*, *PCI DSS v4.0 Assessment*, *SOC 2 Assessment*, and/or *HIPAA/HITECH Assessment*,
its rollback has one extra consideration those scenarios' own rollback docs already describe:
deleting this assessment does not delete or affect the shared group or the other assessment(s) in
it.

## References

1. General Data Protection Regulation - overview, terminology, six key principles, extraterritorial scope, fines, DSR/breach-notification/DPIA structure, Data Protection Officer (Article 37), cross-border transfer basis - <https://learn.microsoft.com/compliance/regulatory/gdpr>
2. GDPR Breach Notification - 72-hour Data Protection Authority notification requirement, individual notification without undue delay - <https://learn.microsoft.com/compliance/regulatory/gdpr-breach-notification>
3. Data Protection Impact Assessment for the GDPR - Article 35 DPIA requirement and required contents - <https://learn.microsoft.com/compliance/regulatory/gdpr-data-protection-impact-assessments>
4. Data Subject Requests and the GDPR and CCPA - the six DSR activities (Discovery, Access, Rectification, Restriction, Export, Deletion) - <https://learn.microsoft.com/compliance/regulatory/gdpr-data-subject-requests>
5. (see reference 1) "Use Microsoft Purview Compliance Manager to assess your risk" - prebuilt assessment for E5 customers
6. Microsoft Purview service description - Compliance Manager - <https://learn.microsoft.com/office365/servicedescriptions/microsoft-365-service-descriptions/microsoft-365-tenantlevel-services-licensing-guidance/microsoft-purview-service-description#microsoft-purview-compliance-manager>
7. Compliance Manager regulations list - EMEA category lists "EU GDPR (General Data Protection Regulation)" and, separately, "UK Data Protection Act" as distinct premium templates; 3-free-templates allotment (direct fetch, 2026-09-16) - <https://learn.microsoft.com/purview/compliance-manager-regulations-list#premium-regulations>
8. Compliance Manager frequently asked questions - "What changed with template licensing in December 2022?" (GDPR, NIST 800-53, and ISO 27001 moved from included-by-default to counting against the 3-free-premium-template allotment) - <https://learn.microsoft.com/purview/compliance-manager-faq#are-there-licensing-requirements-for-using-compliance-manager>
9. Get started with Compliance Manager (role types table incl. Entra role mapping) - <https://learn.microsoft.com/purview/compliance-manager-setup>
10. (see reference 1) GDPR FAQs - "Does my business need to appoint a Data Protection Officer (DPO)?" (Article 37 conditional criteria)
11. (see reference 1) GDPR FAQs - "Under what basis does Microsoft facilitate the transfer of personal data outside of the EU?" (Standard Contractual Clauses, EU-U.S. Data Privacy Framework)
12. Build and manage assessments in Compliance Manager (create-assessment wizard, Groups for assessments - technical-vs-nontechnical improvement-action sync scope, one-assessment-per-product-per-regulation-per-group rule, groups can't be deleted, Data Protection Baseline default composition explicitly naming GDPR, Export an assessment report, Delete an assessment) - <https://learn.microsoft.com/purview/compliance-manager-assessments>
13. Working with improvement actions in Compliance Manager (built-in automation from DLM/Information Protection/DLP/Insider Risk Management; automated testing/monitoring) - <https://learn.microsoft.com/purview/compliance-manager-improvement-actions>
14. (see reference 13) "Assign improvement action to assessor for completion"
15. (see reference 4) DSR FAQs - "What actions complete a DSR?" (six activities)
16. Update improvement actions and bring compliance data into Compliance Manager (Export actions / Action Update tab / Update actions wizard) - <https://learn.microsoft.com/purview/compliance-manager-update-actions>
17. Compliance Manager frequently asked questions - "If I have a high score, does it mean I'm fully compliant?" - <https://learn.microsoft.com/purview/compliance-manager-faq>
18. Manage audit log retention policies (180-day Standard default, 1-year E5 default for Entra/Exchange/OneDrive/SharePoint, up to 10 years with Audit Premium retention policies) - <https://learn.microsoft.com/purview/audit-log-retention-policies>
19. Audit log activities - Compliance Manager activities table (the 3 documented operations) - <https://learn.microsoft.com/purview/audit-log-activities#compliance-manager-activities>
20. Search-UnifiedAuditLog reference - <https://learn.microsoft.com/powershell/module/exchangepowershell/search-unifiedauditlog>
21. GDPR Article 37 (Designation of the data protection officer) - full text - <https://gdpr-info.eu/art-37-gdpr/>
22. GDPR Article 42 (Certification) - full text - <https://gdpr-info.eu/art-42-gdpr/>
23. *Assess Against ISO/IEC 27001:2022*, *PCI DSS v4.0 Assessment*, *SOC 2 Assessment*, and *HIPAA/HITECH Assessment* - this library's sibling Compliance Manager assessments, cross-referenced throughout this scenario for the shared group/audit-trail-script pattern.

> Re-verify all links, the EU-GDPR-vs-UK-Data-Protection-Act catalog-naming detail, and the
> premium-template licensing model against current Microsoft Learn before a customer-facing
> assessment or sale - Compliance Manager's regulation catalog and licensing rules have changed
> materially before (most recently for this exact template, in December 2022) and can change again.