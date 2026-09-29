---
part: "runbook"
parent: "compliance-manager/hipaa-hitech-assessment"
---
## Implementation steps

### Portal path - creating the assessment (there is no script path for this part; see why this matters/the design notes)

1. Before starting, decide the group and role assignments - see
   `deploy/policy/hipaa-hitech-assessment-manifest.json`. **Both decisions are effectively
   permanent**: an assessment's group can't be changed after creation, and groups themselves can't
   be deleted.
2. **Check whether *Assess Against ISO/IEC 27001:2022*, *PCI DSS v4.0 Assessment*, and/or *SOC 2 Assessment* (or any
   other Compliance Manager assessment using the `Security & Compliance Assessments` group) are
   already deployed in this tenant.** If yes, plan to **add** this assessment to that group in step
   6 below, not create a new one - see the design notes for exactly what that buys you (nontechnical
   improvement-action sharing, not the broader "everything syncs" read a quick skim might suggest).
3. **(Recommended order, not required)** Deploy this library's HIPAA-relevant technical scenarios
   first if not already in place - see the manifest's `recommendedDeploymentOrder` and the design notes's control crosswalk. Compliance Manager's built-in automation detects signals from Data
   Lifecycle Management, Information Protection, DLP, Communication Compliance, and Insider Risk
   Management, and those signals sync to this assessment **regardless of which
   group it ends up in** - so deployment order matters, group choice doesn't, for
   this part.
4. Sign in to the [Microsoft Purview portal](https://purview.microsoft.com) → **Compliance
   Manager** → **Assessments** → **Add assessment**.
5. On **Base your assessment on a regulation** → **Select regulation** → search for **HIPAA** →
   **you will see results for both "HIPAA/HITECH" and "HITRUST" - these are not the same
   template.** Select **HIPAA/HITECH** - HITRUST is a separate, independently governed certifiable
   framework (the HITRUST CSF) that harmonizes many standards including HIPAA, but is not itself a
   HIPAA/HITECH assessment - → **Save** → confirm → **Next**.
6. On **Add name and group**: enter a unique assessment name (this scenario's default:
   `HIPAA/HITECH - Microsoft 365 Estate`). If step 2 found an existing `Security & Compliance
   Assessments` group, choose it under **Add to existing group**. Otherwise choose **Create new
   group** with that same name (so a future assessment finds it) → **Next**.
7. On **Select services**: select **Microsoft 365** only, per this scenario's scope (the design notes - multicloud scoping via Defender for Cloud is a documented but explicitly out-of-scope
   extension) → **Next**.
8. **Review and finish**: confirm the regulation (HIPAA/HITECH), name, group, and services →
   **Create assessment** → **Done**.
9. From the new assessment's details page → **Manage user access**: assign
   Contributor/Assessor/Reader roles per the manifest's `roleAssignments`.
10. **Confirm the organization has separately, formally designated a HIPAA Privacy Officer and
    Security Officer** - these HIPAA-mandated designations are independent of, and not
    satisfied by, any Compliance Manager role assignment made in step 9.
11. **Do not** rely on the tenant's default **Data Protection Baseline** assessment as a substitute
    for steps 4-8 - see the design notes (identical reasoning to the three sibling scenarios', and
    notably the Baseline's own documented blend of NIST CSF/ISO/FedRAMP/GDPR elements does not even
    mention HIPAA).

### Ongoing portal work - testing and evidencing controls (also has no script path)

12. **Improvement actions** tab: for actions with **Automatic** testing type, confirm they've
    picked up a status from the built-in automation signals described in step 3 before doing any
    manual work on them.
13. For actions requiring manual work: assign an owner, complete implementation, upload evidence,
    submit for testing - a **Compliance Manager Assessor** validates and sets Pass/Fail. **For any action mapped to an "addressable" Security Rule implementation
    specification**: implement it as documented, OR document a reasonable alternative
    measure and the rationale for it, OR document why no safeguard is needed - never simply mark it
    N/A or skip it, which would misrepresent an addressable specification as optional.
14. For bulk updates: use **Export actions** → edit the **Action Update** tab per its embedded
    instructions → **Update actions** to re-upload - Microsoft's own documented mechanism, with no
    faster scripted path as of this writing (the design notes Non-goals).
15. **If this assessment shares its group with *Assess Against ISO/IEC 27001:2022*, *PCI DSS v4.0 Assessment*,
    and/or *SOC 2 Assessment***: when you complete a **nontechnical** improvement action common
    across them (e.g. a documented information security policy, a personnel background-check
    policy, an incident response plan), verify the update is reflected in the other assessment(s)
    too - this is the concrete payoff of the group-placement decision from step 6, and is worth spot-checking once so the team trusts it's actually working.
16. **If HHS OCR ever opens an investigation, or a covered entity's own auditor requests evidence**
    (for a business associate answering a covered entity's due-diligence request): grant the
    relevant contacts **Compliance Manager Reader** access (or export the relevant reports for
    them, the validation steps) rather than treating this assessment's score as something you hand over in place of
    the organization's own required Security Risk Analysis or direct evidence.

### Script path - the audit-trail export (reused, not duplicated - see the design notes)

```powershell
# 1. Connect (certificate app-only - see Automation surface, section 3). The connecting identity
# needs Exchange.ManageAsApp PLUS the View-Only Audit Logs Exchange Online role (RBAC model, section 6).
Connect-ExchangeOnline -AppId $AppId -Certificate $Cert -Organization $TenantDomain

# 2. If Assess Against ISO/IEC 27001:2022, .../pci-dss-assessment/, and/or
# .../soc2-assessment/ are ALSO deployed in this tenant, run only ONE instance of
# Export-ComplianceManagerAuditTrail.ps1 (any copy - they're identical; see the design notes Section 2)
# against a single shared CSV path. The commands below assume this is the only Compliance
# Manager assessment in the tenant so far.

# 3. Dry run - queries the last 7 days, reports what would be merged, writes nothing
./deploy/Export-ComplianceManagerAuditTrail.ps1 -OutputCsvPath './out/compliance-manager-audit-trail.csv' -WhatIf

# 4. First real run - a one-time backfill covering the full default retention window
./deploy/Export-ComplianceManagerAuditTrail.ps1 `
    -StartDate (Get-Date).AddDays(-180) -EndDate (Get-Date) `
    -OutputCsvPath './out/compliance-manager-audit-trail.csv'

# 5. Recurring run (schedule daily or weekly - overlapping windows are safe, see the design notes).
# Keep this running indefinitely - HIPAA's own documentation retention requirement
# outlives any Audit retention configuration this script depends on.
./deploy/Export-ComplianceManagerAuditTrail.ps1 -OutputCsvPath './out/compliance-manager-audit-trail.csv'

# 6. Validate the audit trail AND this scenario's own control-crosswalk manifest
./validate/Test-ComplianceManagerAuditTrail.ps1 -AuditTrailCsvPath './out/compliance-manager-audit-trail.csv'
```

## Configuration reference

| Setting | Value this scenario uses | Notes |
|---|---|---|
| Regulation/template | HIPAA/HITECH | Premium template, US Government category - do **not** select the separately-listed HITRUST template |
| Assessment name | `HIPAA/HITECH - Microsoft 365 Estate` | Effectively permanent once created |
| Group | `Security & Compliance Assessments` (join if present, else create new) | Buys nontechnical improvement-action sharing with *Assess Against ISO/IEC 27001:2022*/*PCI DSS v4.0 Assessment*/*SOC 2 Assessment* - the design notes |
| Services in scope | Microsoft 365 only | Multicloud is an explicit non-goal - the design notes |
| Recommended role split | Administration: 1-2 people (ideally the designated Security Officer or a delegate) · Contribution/Assessor: control owners across IT/Security/Compliance/Privacy · Reader: leadership and the designated Privacy Officer if not already a Contributor | See `deploy/policy/hipaa-hitech-assessment-manifest.json` |
| Control crosswalk | 5 categories mapped to HIPAA/HITECH's own published rule structure (Privacy Rule, Administrative/Physical/Technical Safeguards, Breach Notification Rule), correlated against this library's own scenarios | `deploy/policy/hipaa-hitech-assessment-manifest.json`'s `controlCrosswalk` - this library's own correlation, not Microsoft's mapping |
| Addressable-specification flag | Administrative, Physical, and Technical Safeguards categories each carry `hasAddressableSpecifications: true` | "Addressable" implementation specifications are still required, or require a documented alternative - not optional |
| Audit-trail script | Reused from `assess-against-iso27001/deploy/`, not duplicated | Tenant-wide operations - the design notes |
| Audit-trail script idempotency | Merge + de-duplicate by `(CreationDate, Operations, UserIds, hash(AuditData))` | Identical model to the three sibling scenarios - see that scenario's the design notes |
| Validate script additions | Crosswalk manifest structural check (5 categories + addressable-flag check) + stale-scenario-path check | New in this scenario - see `validate/Test-ComplianceManagerAuditTrail.ps1`'s `.DESCRIPTION` |

## Operations and tuning

**Review cadence:** run the audit-trail export on a **recurring schedule** - daily is cheap and
safe, weekly is the practical minimum given Audit (Standard)'s 180-day retention. This matters
even more here than for the ISO 27001/PCI DSS/SOC 2 siblings: HIPAA's own Security Rule requires
retaining required documentation for **six years** from creation or last-effective date (45 CFR
section 164.316(b)(2)(i)) - far longer than even a SOC 2 Type II period of performance.
Start the recurring schedule immediately and archive the accumulated CSV outside the tenant's own
audit-log retention window (which will expire long before the six-year documentation-retention clock
does) if a longer native window isn't purchased via Audit Premium retention policies
([Licensing matrix](/docs/licensing-matrix/)). Review the **Controls** tab and compliance-score trend at least
**monthly**. Review role-assignment and automation-trust events **immediately** on the audit-trail
script's own warning, not on the monthly cadence - identical operational posture to the three
sibling scenarios.

**KPIs to watch:** identical four KPIs to the sibling scenarios (compliance score trend,
automated-vs-manual improvement-action ratio, `ComplianceManagerRolesChange` volume, any
automation-trust-change event at all - near-zero tolerance), plus two new ones specific to this
scenario:

- **Group-sharing drift** - if a nontechnical improvement action common to this assessment and
  *Assess Against ISO/IEC 27001:2022*/*PCI DSS v4.0 Assessment*/*SOC 2 Assessment* is updated in one but the update
  doesn't appear in the other(s) within a reasonable time, treat it as a signal the assessments may
  no longer share a group, not as a Compliance Manager bug.
- **"Addressable" specifications marked complete without documented rationale** - periodically
  spot-check improvement actions mapped to addressable Security Rule specifications for
  evidence that either implements the specification or documents a reasonable alternative. An
  addressable action marked "Passed" with no supporting note is a governance gap, not proof of
  compliance.

**Incident-response runbook (automation-trust change detected):** identical to
*Assess Against ISO/IEC 27001:2022* (operations and tuning) steps 1-5 - triage the `AuditData` JSON, classify
planned/unplanned, document or escalate accordingly. **If the automation-trust change coincides
with a suspected or confirmed breach of unsecured PHI**: separately trigger this library's
*Compromised Account Incident Response* runbook and the organization's own Breach
Notification Rule procedure - this scenario's audit trail is evidence for that response, not
a substitute for it.

## Rollback and decommission

See the rollback runbook for the full procedure. Because this scenario may share a group with
*Assess Against ISO/IEC 27001:2022*, *PCI DSS v4.0 Assessment*, and/or *SOC 2 Assessment*, its rollback has one
extra consideration those scenarios' own rollback docs already describe: deleting this assessment
does not delete or affect the shared group or the other assessment(s) in it.

## References

1. Health Insurance Portability and Accountability Act (HIPAA) & Health Information Technology for Economic and Clinical Health (HITECH) Act - overview, business-associate scope, "Use Microsoft Purview Compliance Manager to assess your risk" - <https://learn.microsoft.com/compliance/regulatory/offering-hipaa-hitech>
2. HIPAA (US) - Azure compliance offering (Privacy Rule / Security Rule / Breach Notification Rule three-rule structure, Business Associate Agreement) - <https://learn.microsoft.com/azure/compliance/offerings/offering-hipaa-us>
3. HHS.gov - Breach Notification Rule - <https://www.hhs.gov/hipaa/for-professionals/breach-notification/index.html>
4. Get started with Compliance Manager - assessment templates page - <https://learn.microsoft.com/purview/compliance-manager-setup>
5. (see reference 1) Business Associate Agreement section - Microsoft HIPAA Business Associate Agreement - <https://servicetrust.microsoft.com/DocumentPage/d60051b9-8b5a-4794-9844-033773faaeb0>
6. Microsoft Purview service description - Compliance Manager - <https://learn.microsoft.com/office365/servicedescriptions/microsoft-365-service-descriptions/microsoft-365-tenantlevel-services-licensing-guidance/microsoft-purview-service-description#microsoft-purview-compliance-manager>
7. Compliance Manager regulations list - US Government category lists "HIPAA/HITECH" and, separately, "HITRUST" as distinct premium templates; 3-free-templates allotment (direct fetch, 2026-09-16) - <https://learn.microsoft.com/purview/compliance-manager-regulations-list#premium-regulations>
8. Get started with Compliance Manager (role types table incl. Entra role mapping) - <https://learn.microsoft.com/purview/compliance-manager-setup>
9. HHS.gov - Privacy Rule, personnel designation requirement (45 CFR 164.530(a)(1)) - <https://www.hhs.gov/hipaa/for-professionals/privacy/index.html>
10. Configuring Microsoft Entra ID for HIPAA compliance - HIPAA Security Rule overview, 45 CFR Part 160/164 structure, Security Officer designation (section 164.308(a)(2)), Security Risk Analysis (section 164.308(a)(1)(ii)(A)) - <https://learn.microsoft.com/entra/standards/hipaa-configure-for-compliance>
11. Build and manage assessments in Compliance Manager (create-assessment wizard, Groups for assessments - technical-vs-nontechnical improvement-action sync scope, one-assessment-per-product-per-regulation-per-group rule, groups can't be deleted, Data Protection Baseline default, Export an assessment report, Delete an assessment) - <https://learn.microsoft.com/purview/compliance-manager-assessments>
12. Working with improvement actions in Compliance Manager (built-in automation from DLM/Information Protection/DLP/Communication Compliance/IRM; automated testing/monitoring) - <https://learn.microsoft.com/purview/compliance-manager-improvement-actions>
13. (see reference 12) "Assign improvement action to assessor for completion"
14. Update improvement actions and bring compliance data into Compliance Manager (Export actions / Action Update tab / Update actions wizard) - <https://learn.microsoft.com/purview/compliance-manager-update-actions>
15. eCFR - 45 CFR 164.316, Policies and procedures and documentation requirements (six-year retention of required Security Rule documentation, section 164.316(b)(2)(i)) - <https://www.ecfr.gov/current/title-45/section-164.316>
16. (see reference 1) Frequently asked questions - "There's currently no certification standard that the Department of Health and Human Services approves to demonstrate compliance with HIPAA or the HITECH Act by a business associate"
17. Configuring Microsoft Entra ID for HIPAA compliance - "Addressable doesn't mean that an implementation specification is optional. Therefore, subparts that are defined as addressable are also required." - <https://learn.microsoft.com/entra/standards/hipaa-configure-for-compliance>
18. What the DLP policy templates include - "U.S. Health Insurance Act (HIPAA) Enhanced" built-in DLP policy template (SSN/DEA Number/US Physical Addresses/All Full Names SITs, ICD-9-CM/ICD-10-CM keyword terms, Healthcare and Health/Medical Forms trainable classifiers) - <https://learn.microsoft.com/purview/dlp-policy-templates-include#us-health-insurance-act-hipaa-enhanced>
19. Manage audit log retention policies (180-day Standard default, 1-year E5 default for Entra/Exchange/OneDrive/SharePoint, up to 10 years with Audit Premium retention policies) - <https://learn.microsoft.com/purview/audit-log-retention-policies>
20. Compliance Manager frequently asked questions (a high score is not proof of compliance) - <https://learn.microsoft.com/purview/compliance-manager-faq>
21. Audit log activities - Compliance Manager activities table (the 3 documented operations) - <https://learn.microsoft.com/purview/audit-log-activities#compliance-manager-activities>
22. Search-UnifiedAuditLog reference - <https://learn.microsoft.com/powershell/module/exchangepowershell/search-unifiedauditlog>
23. *Assess Against ISO/IEC 27001:2022*, *PCI DSS v4.0 Assessment*, and *SOC 2 Assessment* - this library's sibling Compliance Manager assessments, cross-referenced throughout this scenario for the shared group/audit-trail-script pattern.

> Re-verify all links, the HIPAA/HITECH-vs-HITRUST catalog-naming detail, and the premium-template
> licensing model against current Microsoft Learn before a customer-facing assessment or sale -
> Compliance Manager's regulation catalog and licensing rules have changed materially before and can
> change again.