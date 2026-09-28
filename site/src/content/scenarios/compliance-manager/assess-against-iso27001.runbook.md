---
part: "runbook"
parent: "compliance-manager/assess-against-iso27001"
---
## Implementation steps

### Portal path - creating the assessment (there is no script path for this part; see why this matters/the design notes)

1. Before starting, decide the group name and role assignments - see
   `deploy/policy/iso27001-assessment-manifest.json` for this scenario's recommended values.
   **Both decisions are effectively permanent**: an assessment's group can't be changed after
   creation, and groups themselves can't be deleted.
2. **(Recommended order, not required)** Deploy this library's DLP, Information Protection, and
   Insider Risk Management scenarios first if not already in place - see the manifest's
   `recommendedDeploymentOrder` and the design notes. Compliance Manager's built-in automation
   detects signals from Data Lifecycle Management, Information Protection, DLP, Communication
   Compliance, and Insider Risk Management, so controls already live in the
   tenant reduce the manual-testing backlog before a human opens the assessment.
3. Sign in to the [Microsoft Purview portal](https://purview.microsoft.com) → **Compliance
   Manager** → **Assessments** → **Add assessment**.
4. On **Base your assessment on a regulation** → **Select regulation** → search for and select
   **ISO/IEC 27001:2022** (not the separately listed **ISO/IEC 27001:2013** entry - sections 2 and 11 explain
   why :2022 is the correct choice for a new assessment as of this build) → **Save** → confirm →
   **Next**.
5. On **Add name and group**: enter a unique assessment name (this scenario's default:
   `ISO/IEC 27001:2022 - Microsoft 365 Estate` - assessment names must be unique tenant-wide and
   effectively can't be renamed without deleting and recreating). Choose **Create new group**
   with the name from the manifest (`Security & Compliance Assessments`) unless an existing group
   is the deliberate, planned target → **Next**.
6. On **Select services**: select **Microsoft 365** only, per this scenario's scope (the design notes - multicloud scoping via Defender for Cloud is a documented but explicitly out-of-scope
   extension) → **Next**.
7. **Review and finish**: confirm the regulation, name, group, and services → **Create
   assessment** → **Done**.
8. From the new assessment's details page → **Manage user access**: assign
   Contributor/Assessor/Reader roles per the manifest's `roleAssignments` - do not leave every
   stakeholder at Administration by default.
9. **Do not** rely on the tenant's default **Data Protection Baseline** assessment as a substitute
   for step 4-7 - it blends NIST CSF/ISO/FedRAMP/GDPR elements and is not itself a citable
   ISO/IEC 27001:2022 control set.

### Ongoing portal work - testing and evidencing controls (also has no script path)

10. **Improvement actions** tab of the assessment: for actions with **Automatic** testing type,
    confirm they've picked up a status from the built-in automation signals described in step 2
    before doing any manual work on them.
11. For actions requiring manual work: assign an owner, complete implementation, upload evidence,
    and submit for testing - a **Compliance Manager Assessor** validates and sets the test status
    to Pass/Fail.
12. For bulk updates (many actions' status/evidence/notes at once): use **Export actions** →
    edit the downloaded Excel file's **Action Update** tab per its own embedded instructions →
    **Update actions** to re-upload. This wizard-and-Excel round trip is Microsoft's own documented
    mechanism - there is no faster scripted path as of this writing (the design notes Non-goals).

### Script path - the audit-trail export (idempotent, parameterized, dry-run capable)

```powershell
# 1. Connect (certificate app-only - see docs/automation-surface.md §3). The connecting identity
#    needs Exchange.ManageAsApp PLUS the View-Only Audit Logs Exchange Online role (docs/rbac-model.md §6).
Connect-ExchangeOnline -AppId $AppId -Certificate $Cert -Organization $TenantDomain

# 2. Dry run - queries the last 7 days, reports what would be merged, writes nothing
./deploy/Export-ComplianceManagerAuditTrail.ps1 -OutputCsvPath './out/compliance-manager-audit-trail.csv' -WhatIf

# 3. First real run - a one-time backfill covering the full default retention window
./deploy/Export-ComplianceManagerAuditTrail.ps1 `
    -StartDate (Get-Date).AddDays(-180) -EndDate (Get-Date) `
    -OutputCsvPath './out/compliance-manager-audit-trail.csv'

# 4. Recurring run (schedule daily or weekly - overlapping windows are safe, see design.md §8)
./deploy/Export-ComplianceManagerAuditTrail.ps1 -OutputCsvPath './out/compliance-manager-audit-trail.csv'

# 5. Validate
./validate/Test-ComplianceManagerAuditTrail.ps1 -AuditTrailCsvPath './out/compliance-manager-audit-trail.csv'
```

The audit-trail script uses Exchange Online PowerShell's `Search-UnifiedAuditLog` - automation
surface 1 per [Automation surface, section 1](/docs/automation-surface/#1-five-automation-surfaces-not-one-read-this-first), because Compliance Manager has no surface of its
own for anything, including its own audit footprint.

## Configuration reference

| Setting | Value this scenario uses | Notes |
|---|---|---|
| Regulation/template | ISO/IEC 27001:2022 | Premium template - see the prerequisites licensing. Not :2013 - see why this matters and the known limitations |
| Assessment name | `ISO/IEC 27001:2022 - Microsoft 365 Estate` | Effectively permanent once created |
| Group | `Security & Compliance Assessments` (new) | Permanent - group membership can't be changed after assessment creation |
| Services in scope | Microsoft 365 only | Multicloud is an explicit non-goal - the design notes |
| Recommended role split | Administration: 1-2 people · Contribution/Assessor: control owners · Reader: auditors/leadership | See `deploy/policy/iso27001-assessment-manifest.json` |
| Audit-trail script operations filter | `ComplianceManagerRolesChange`, `ComplianceManagerAutomationLevelChange`, `ComplianceManagerAutomationChange` | The only 3 Compliance-Manager-specific operations Microsoft's audit-log-activities reference documents |
| Audit-trail script idempotency | Merge + de-duplicate by `(CreationDate, Operations, UserIds, hash(AuditData))` | Not a RunId-replace pattern - see the design notes for why. Does not assume an ungrounded flat `ObjectId` field; a best-effort `AuditDataObjectId` is still surfaced as a display-only column |
| Audit-trail script default window | Last 7 days (`-StartDate`/`-EndDate`) | Suitable for a daily/weekly scheduled run; overlap with the prior run is safe |

Full cmdlet parameter grounding: `deploy/Export-ComplianceManagerAuditTrail.ps1`'s inline comments
and its `.NOTES` block cite the exact Microsoft Learn reference pages.

## Operations and tuning

**Review cadence:** run the audit-trail export on a **recurring schedule** - daily is cheap and
safe (overlapping-window de-duplication makes over-frequent runs harmless), weekly is the
practical minimum given Audit (Standard)'s 180-day retention window. Review the **Controls**
tab and compliance-score trend at least **monthly**; review **role assignments**
(`ComplianceManagerRolesChange` events) and any `ComplianceManagerAutomationLevelChange`/
`ComplianceManagerAutomationChange` event **immediately** when the audit-trail script's built-in
warning fires (deploy script `.NOTES`), not on the monthly cadence - an automation-trust change is
a control-integrity event, not routine drift. **Daily**, also: run
*Entra Privileged Role Monitoring*
Export-EntraPrivilegedRoleAuditTrail.ps1` - that scenario now scripts the quarterly Entra
directory role-assignment cross-check this operations section used to describe as a manual task, closing this scenario's own Red Team finding 1 with a real, dailyable control instead of a
portal-only recommendation. **Quarterly**, also: run **Export actions** and retain
the output outside Compliance Manager as a durable evidence snapshot - the native Reports page's
own history only covers 6 months.

**KPIs to watch:**
- **Compliance score trend** (native Reports page, up to 6 months of history) - a flat or
  declining score after a security-awareness or tooling push is a signal the assessment isn't
  being actively worked, not that the estate got less compliant.
- **Ratio of automated vs. manual improvement-action status** - a low automated-status ratio
  months after deploying this library's DLP/Information Protection/IRM scenarios
  suggests either those controls aren't actually configured as expected, or the mapping between
  them and this template's actions is thinner than assumed - investigate rather than assume.
- **`ComplianceManagerRolesChange` event volume** - a spike outside a planned onboarding/offboarding
  event is worth investigating; Compliance Manager role membership is a meaningful privilege (up to
  and including Administration, which can edit any assessment).
- **Any `ComplianceManagerAutomationLevelChange`/`ComplianceManagerAutomationChange` event at all**
  - treat as a near-zero-tolerance signal. These operations exist specifically because someone can
  quietly downgrade what "Passed" means for this assessment's improvement actions; the audit-trail
  script's inline `Write-Warning` on match (deploy script) exists to make this impossible to miss
  in a scheduled-run log.

**Incident-response runbook (automation-trust change detected):**
1. **Triage** - pull the full `AuditData` JSON for the flagged row (the audit-trail CSV's
   `AuditData` column) to see exactly what was changed and by whom.
2. **Classify** - was this a planned, documented change (e.g. deliberately moving an action from
   automatic to manual testing because the automated signal proved unreliable) or unplanned?
3. **Planned:** document the change and its rationale alongside the assessment (evidence/notes on
   the affected improvement action) so a future auditor sees the reasoning, not just the change.
4. **Unplanned:** escalate to whoever owns Compliance Manager Administration; treat as a potential
   attempt to game the compliance score, and review recent `ComplianceManagerRolesChange` events
   for the same user to see if their access was also recently, unexpectedly broadened.
5. **Document** - every reviewed event, planned or not, is retained in the audit-trail CSV as
   Requirement-adjacent evidence; do not delete rows from it.

## Rollback and decommission

See the rollback runbook for the full procedure - the assessment (portal-only, staged: scope-down →
revoke access → delete) and the audit-trail script (schedule + role removal) are rolled back
independently.

## References

1. ISO/IEC 27001:2013 Information Security Management Standards - Use Compliance Manager to assess your risk - <https://learn.microsoft.com/compliance/regulatory/offering-iso-27001>
2. Build and manage assessments in Compliance Manager (create-assessment wizard, groups can't be deleted/reassigned, Data Protection Baseline default, Export an assessment report, Delete an assessment) - <https://learn.microsoft.com/purview/compliance-manager-assessments>
3. Get started with Compliance Manager (role types table incl. Entra role mapping, Compliance Manager Administration/Contribution/Assessor/Reader) - <https://learn.microsoft.com/purview/compliance-manager-setup>
4. (see reference 2) Data Protection Baseline default assessment section
5. Learn about regulations in Compliance Manager (premium licensing, 3-free-templates allotment, per-regulation not per-assessment) - <https://learn.microsoft.com/purview/compliance-manager-regulations>
6. Working with improvement actions in Compliance Manager (automated testing/monitoring - built-in automation from DLM/Information Protection/DLP/Communication Compliance/IRM/Priva, Secure Score automation, Defender for Cloud automation, connectors) - <https://learn.microsoft.com/purview/compliance-manager-improvement-actions>
7. (see reference 6) Assign improvement action to assessor for completion; Improvement action details page
8. Update improvement actions and bring compliance data into Compliance Manager (Export actions / Action Update tab / Update actions wizard - the bulk-update workflow) - <https://learn.microsoft.com/purview/compliance-manager-update-actions>
9. Microsoft Purview service description - Compliance Manager - <https://learn.microsoft.com/office365/servicedescriptions/microsoft-365-service-descriptions/microsoft-365-tenantlevel-services-licensing-guidance/microsoft-purview-service-description#microsoft-purview-compliance-manager>
10. Compliance Manager regulations list (December 2022 licensing change, included vs. premium templates, GCC/DoD) - <https://learn.microsoft.com/purview/compliance-manager-regulations-list>
11. Learn about auditing solutions in Microsoft Purview (Audit Standard vs. Premium, licensing) - <https://learn.microsoft.com/purview/audit-solutions-overview>
12. Manage audit log retention policies (180-day Standard default since Oct 17 2023, 1-year E5 default for Entra/Exchange/OneDrive/SharePoint, up to 10 years with Premium retention policies) - <https://learn.microsoft.com/purview/audit-log-retention-policies>
13. Compliance Manager frequently asked questions (a high score is not proof of compliance) - <https://learn.microsoft.com/purview/compliance-manager-faq>
14. Audit log activities - Compliance Manager activities table (the 3 documented operations) - <https://learn.microsoft.com/purview/audit-log-activities#compliance-manager-activities>
15. Search-UnifiedAuditLog reference - <https://learn.microsoft.com/powershell/module/exchangepowershell/search-unifiedauditlog>
16. Search the audit log for deleted mailbox items - permissions section (View-Only Audit Logs / Audit Logs Exchange Online role requirement) - <https://learn.microsoft.com/purview/audit-log-search-deleted-mailbox-items#verify-administrator-permissions>
17. Compliance Manager regulations list - Premium regulations / Global section, lists ISO/IEC 27001:2013 and ISO/IEC 27001:2022 as separate entries (direct fetch, 2026-09-10; same URL as reference 10) - <https://learn.microsoft.com/purview/compliance-manager-regulations-list#premium-regulations>
18. IAF MD 26:2023 - Transition Requirements for ISO/IEC 27001 (International Accreditation Forum mandatory document: initial/recertification audits to :2013 stopped after April 30, 2024; all :2013 certificates expire or are reissued against :2022 by October 31, 2025) - <https://iaf.nu/iaf_system/uploads/documents/IAF_MD26_Issue_2_15012023.pdf>
19. Microsoft 365 - ISO 27001:2022 Certificate (2024-2027) - Microsoft's own current Office 365/Microsoft 365 ISO/IEC 27001 certification cycle, linked from reference 1's FAQ - <https://servicetrust.microsoft.com/DocumentPage/6af50cea-280c-4859-acff-bd1ea8e2660a>

> Re-verify all links and the premium-template licensing model against current Microsoft Learn
> before a customer-facing assessment or sale - Compliance Manager's regulation catalog and
> licensing rules have changed materially before (the December 2022 change cited above) and can
> change again.