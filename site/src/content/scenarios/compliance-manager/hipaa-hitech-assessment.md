---
title: "HIPAA/HITECH Assessment"
fullTitle: "Compliance Manager — HIPAA/HITECH Assessment"
category: "Compliance Manager"
categorySlug: "compliance-manager"
slug: "hipaa-hitech-assessment"
repoPath: "scenarios/compliance-manager/hipaa-hitech-assessment"
parts: ["design","deploy","validate","rollback"]
deployCount: 2
validateCount: 1
---
## 1. Scenario summary

Stands up a dedicated **Microsoft Purview Compliance Manager** assessment against the
**HIPAA/HITECH** premium regulatory template, places it correctly relative to this library's other
Compliance Manager assessments, and cross-references it against the HIPAA/HITECH-relevant technical
controls this library already ships (Information Protection labeling, DLP exfiltration blocking,
Adaptive Protection access control, Insider Risk Management, Audit). Like `scenarios/compliance-
manager/assess-against-iso27001/`, `scenarios/compliance-manager/pci-dss-assessment/`, and
`scenarios/compliance-manager/soc2-assessment/`, Compliance Manager itself has no write API, so most
of this scenario is a precise, repeatable **portal runbook** — see §2 and `design.md` §2.

**Who it's for:** a HIPAA **covered entity** (a health care provider, health plan, or health care
clearinghouse) or a **business associate** — a health-tech ISV, MSP, or any Microsoft 365-based
service provider that creates, receives, maintains, or transmits protected health information (PHI)
on a covered entity's behalf — that needs an internal, evidenced readiness view of how its Microsoft
365 estate maps to HIPAA's Privacy Rule, Security Rule, and Breach Notification Rule. Critically,
this is also for a team that already understands (or needs this scenario to make explicit) that
**no HHS-approved HIPAA certification exists at all** — for anyone, covered entity or business
associate — and this assessment does not create one (§11).

## 2. Business/regulatory driver

**HIPAA** (the Health Insurance Portability and Accountability Act of 1996) and the **HITECH Act**
(2009) together form a set of U.S. federal healthcare laws establishing requirements for the use,
disclosure, and safeguarding of protected health information (PHI) [[1]](#references). Unlike SOC 2
(a contractual/commercial driver), HIPAA is a **legal mandate**: it applies directly to covered
entities and, since HITECH extended its scope, directly to their business associates — including any
cloud service provider, such as Microsoft or a customer running Microsoft 365, that creates,
receives, maintains, or transmits PHI on a covered entity's behalf [[1]](#references)[[2]](#references).
Noncompliance carries real regulatory exposure: enforcement sits with the HHS Office for Civil Rights
(OCR), and the Breach Notification Rule imposes affirmative, time-bound obligations on both covered
entities and business associates when a breach of unsecured PHI occurs [[3]](#references).

HIPAA and HITECH together comprise three rules [[2]](#references):

1. **The Privacy Rule** — safeguards for the privacy of PHI and restrictions on its use/disclosure
   without patient authorization, plus patient rights to access and correct their own records.
2. **The Security Rule** — administrative, physical, and technical safeguards for the
   confidentiality, integrity, and availability of **electronic** PHI (ePHI).
3. **The Breach Notification Rule** — notification obligations when a breach of unsecured PHI occurs.

Compliance Manager's HIPAA/HITECH premium template exists to give an organization's Microsoft
365-based controls a scored, evidenced internal readiness view against this structure
[[4]](#references) — it does not itself demonstrate legal compliance or produce any form of
certification (§11), and this scenario does not present it as though it does. A Microsoft Business
Associate Agreement (BAA) is a separate, contractual prerequisite this scenario assumes is already
in place — it governs Microsoft's own obligations as a business associate, not the customer's
internal control posture, which is exactly what this assessment tracks [[5]](#references).

## 3. Prerequisites

Full licensing detail and citations: `docs/licensing-matrix.md`. Summary for this scenario
(identical role/licensing model to `assess-against-iso27001/README.md` §3, `pci-dss-assessment/
README.md` §3, and `soc2-assessment/README.md` §3 — Compliance Manager's RBAC and premium-template
licensing are tenant-wide, not per-regulation):

| Requirement | Minimum | Notes |
|---|---|---|
| Compliance Manager base access | **Office 365 / Microsoft 365** license (any tier) | Available at all subscription levels; only premium regulatory templates require more [[6]](#references) |
| HIPAA/HITECH premium template | **A5/E5/G5** (3 free premium templates of choice) **or** the purchased **Compliance Manager premium assessment add-on**, **or** a **90-day premium assessments trial** (25 templates) | Compliance Manager's catalog lists **HIPAA/HITECH** under its **US Government** category, alongside a separately-listed **HITRUST** template that is easy to confuse with it — select **HIPAA/HITECH**, not HITRUST, when the goal is a HIPAA-specific readiness view; see §11 [[7]](#references) |
| Role to create/administer the assessment | **Compliance Manager Administration** (or **Compliance Manager Assessor** to create; **Global Administrator** also works) | `docs/rbac-model.md` §4 for the Purview role-group mapping [[8]](#references) |
| Role to edit/test without creating | **Compliance Manager Contribution** (create + edit) or **Compliance Manager Assessor** (edit only, no create) | Assign the narrowest role per person — see `deploy/policy/hipaa-hitech-assessment-manifest.json` |
| Role for read-only visibility | **Compliance Manager Reader** | Extend to the organization's designated Privacy Officer/Security Officer (see below) if they are not already a Contributor |
| Organizational designation (not a Compliance Manager role) | A formally designated **HIPAA Privacy Officer** (45 CFR §164.530(a)(1)) and **Security Officer** (45 CFR §164.308(a)(2)) | Legally required designations under the Privacy Rule and Security Rule respectively — not satisfied by assigning anyone Compliance Manager Administration [[9]](#references)[[10]](#references) |
| Automation identity (audit-trail script only) | App registration or account holding the **View-Only Audit Logs** (or **Audit Logs**) Exchange Online role, plus `Exchange.ManageAsApp` | Same requirement as the three sibling scenarios — `docs/rbac-model.md` §6 and `docs/automation-surface.md` §3 |
| Prerequisite (not deployed by this scenario) | A **Business Associate Agreement (BAA)** with Microsoft already in place if PHI will be processed in this tenant | A contractual, not a technical, prerequisite — see §2. This scenario does not create or track the BAA itself [[5]](#references) |
| Dependency (not deployed by this scenario) | Nothing hard-required, but strongly recommended: `scenarios/information-protection/auto-label-confidential-sharepoint/` (+ Exchange sibling), `scenarios/dlp/exchange-pii-exfil-block/` (+ Part 2), `scenarios/dlp/endpoint-dlp-usb-block/`, `scenarios/adaptive-protection/block-legacy-authentication/` (+ Exchange sibling), `scenarios/insider-risk/departing-employee-data-theft/`, `scenarios/audit/premium-audit-investigation/`, `scenarios/audit/compromised-account-incident-response/` | Reduces the manual-testing backlog and maps directly to HIPAA's Security Rule safeguard categories and Breach Notification Rule — see the manifest's `controlCrosswalk` and `design.md` §7 |
| Recommended (not required) | `scenarios/compliance-manager/assess-against-iso27001/`, `scenarios/compliance-manager/pci-dss-assessment/`, and/or `scenarios/compliance-manager/soc2-assessment/` already deployed | Not a hard dependency, but if present, this scenario's group-placement decision (§5, `design.md` §6) gets meaningfully better — join, don't duplicate |

> Verify current entitlement names against `docs/licensing-matrix.md` and the Product Terms before
> a sales commitment — SKU names and the premium-template licensing model change over time.

## 4. Architecture

```mermaid
flowchart TD
    A[Compliance Manager Administrator/Assessor<br/>completes portal runbook - Section 5] --> B["HIPAA/HITECH assessment<br/>Group: Security & Compliance Assessments<br/>Scope: Microsoft 365"]
    C["Already-deployed HIPAA-relevant scenarios:<br/>Info Protection labeling / DLP exfil block /<br/>Endpoint DLP / Legacy-auth block / IRM /<br/>Audit / Compromised-account response"] -.built-in automation<br/>feeds technical-action signals<br/>tenant-wide, any group.-> B
    D[Contributors/Assessors] -->|manual work: evidence,<br/>notes, test status,<br/>Excel Action Update wizard| B
    E["ISO/IEC 27001:2022, PCI DSS v4.0,<br/>and/or SOC 2 assessments<br/>(if deployed, same group)"] <-.nontechnical improvement-action<br/>updates sync within the shared group only.-> B
    B --> F[Compliance score<br/>Controls tab<br/>native Reports page]
    G["Admin changes a Compliance Manager<br/>role or automation-trust setting"] --> H["Unified audit log:<br/>ComplianceManagerRolesChange /<br/>ComplianceManagerAutomationLevelChange /<br/>ComplianceManagerAutomationChange"]
    H --> I["REUSED: assess-against-iso27001/deploy/<br/>Export-ComplianceManagerAuditTrail.ps1"]
    I --> J[Rolling audit-trail CSV<br/>retained 6+ years per Sec 164.316(b)(2)(i)]
    J --> K[validate/Test-ComplianceManagerAuditTrail.ps1<br/>+ crosswalk-manifest check]
    B -.evidence + exported reports.-> L[Designated Privacy Officer / Security Officer<br/>and, if ever needed, HHS OCR]
```

## 5. Step-by-step implementation

### Portal path — creating the assessment (there is no script path for this part; see §2/`design.md` §2)

1. Before starting, decide the group and role assignments — see
   `deploy/policy/hipaa-hitech-assessment-manifest.json`. **Both decisions are effectively
   permanent**: an assessment's group can't be changed after creation, and groups themselves can't
   be deleted [[11]](#references).
2. **Check whether `scenarios/compliance-manager/assess-against-iso27001/`, `scenarios/compliance-
   manager/pci-dss-assessment/`, and/or `scenarios/compliance-manager/soc2-assessment/` (or any
   other Compliance Manager assessment using the `Security & Compliance Assessments` group) are
   already deployed in this tenant.** If yes, plan to **add** this assessment to that group in step
   6 below, not create a new one — see `design.md` §6 for exactly what that buys you (nontechnical
   improvement-action sharing, not the broader "everything syncs" read a quick skim might suggest).
3. **(Recommended order, not required)** Deploy this library's HIPAA-relevant technical scenarios
   first if not already in place — see the manifest's `recommendedDeploymentOrder` and `design.md`
   §7's control crosswalk. Compliance Manager's built-in automation detects signals from Data
   Lifecycle Management, Information Protection, DLP, Communication Compliance, and Insider Risk
   Management [[12]](#references), and those signals sync to this assessment **regardless of which
   group it ends up in** (`design.md` §6) — so deployment order matters, group choice doesn't, for
   this part.
4. Sign in to the [Microsoft Purview portal](https://purview.microsoft.com) → **Compliance
   Manager** → **Assessments** → **Add assessment**.
5. On **Base your assessment on a regulation** → **Select regulation** → search for **HIPAA** →
   **you will see results for both "HIPAA/HITECH" and "HITRUST" — these are not the same
   template.** Select **HIPAA/HITECH** — HITRUST is a separate, independently governed certifiable
   framework (the HITRUST CSF) that harmonizes many standards including HIPAA, but is not itself a
   HIPAA/HITECH assessment (§11) — → **Save** → confirm → **Next** [[7]](#references).
6. On **Add name and group**: enter a unique assessment name (this scenario's default:
   `HIPAA/HITECH - Microsoft 365 Estate`). If step 2 found an existing `Security & Compliance
   Assessments` group, choose it under **Add to existing group**. Otherwise choose **Create new
   group** with that same name (so a future assessment finds it) → **Next**.
7. On **Select services**: select **Microsoft 365** only, per this scenario's scope (`design.md`
   §8 — multicloud scoping via Defender for Cloud is a documented but explicitly out-of-scope
   extension) → **Next**.
8. **Review and finish**: confirm the regulation (HIPAA/HITECH), name, group, and services →
   **Create assessment** → **Done** [[11]](#references).
9. From the new assessment's details page → **Manage user access**: assign
   Contributor/Assessor/Reader roles per the manifest's `roleAssignments` [[8]](#references).
10. **Confirm the organization has separately, formally designated a HIPAA Privacy Officer and
    Security Officer** (§3) — these HIPAA-mandated designations are independent of, and not
    satisfied by, any Compliance Manager role assignment made in step 9.
11. **Do not** rely on the tenant's default **Data Protection Baseline** assessment as a substitute
    for steps 4–8 — see `design.md` §5 (identical reasoning to the three sibling scenarios', and
    notably the Baseline's own documented blend of NIST CSF/ISO/FedRAMP/GDPR elements does not even
    mention HIPAA).

### Ongoing portal work — testing and evidencing controls (also has no script path)

12. **Improvement actions** tab: for actions with **Automatic** testing type, confirm they've
    picked up a status from the built-in automation signals described in step 3 before doing any
    manual work on them [[12]](#references).
13. For actions requiring manual work: assign an owner, complete implementation, upload evidence,
    submit for testing — a **Compliance Manager Assessor** validates and sets Pass/Fail
    [[13]](#references). **For any action mapped to an "addressable" Security Rule implementation
    specification** (§6, §11): implement it as documented, OR document a reasonable alternative
    measure and the rationale for it, OR document why no safeguard is needed — never simply mark it
    N/A or skip it, which would misrepresent an addressable specification as optional.
14. For bulk updates: use **Export actions** → edit the **Action Update** tab per its embedded
    instructions → **Update actions** to re-upload — Microsoft's own documented mechanism, with no
    faster scripted path as of this writing (`design.md` §2, §8 Non-goals) [[14]](#references).
15. **If this assessment shares its group with `assess-against-iso27001`, `pci-dss-assessment`,
    and/or `soc2-assessment`**: when you complete a **nontechnical** improvement action common
    across them (e.g. a documented information security policy, a personnel background-check
    policy, an incident response plan), verify the update is reflected in the other assessment(s)
    too — this is the concrete payoff of the group-placement decision from step 6 (`design.md`
    §6), and is worth spot-checking once so the team trusts it's actually working.
16. **If HHS OCR ever opens an investigation, or a covered entity's own auditor requests evidence**
    (for a business associate answering a covered entity's due-diligence request): grant the
    relevant contacts **Compliance Manager Reader** access (or export the relevant reports for
    them, §7) rather than treating this assessment's score as something you hand over in place of
    the organization's own required Security Risk Analysis (§11) or direct evidence.

### Script path — the audit-trail export (reused, not duplicated — see `design.md` §2)

```powershell
# 1. Connect (certificate app-only — see docs/automation-surface.md §3). The connecting identity
#    needs Exchange.ManageAsApp PLUS the View-Only Audit Logs Exchange Online role (docs/rbac-model.md §6).
Connect-ExchangeOnline -AppId $AppId -Certificate $Cert -Organization $TenantDomain

# 2. If scenarios/compliance-manager/assess-against-iso27001/, .../pci-dss-assessment/, and/or
#    .../soc2-assessment/ are ALSO deployed in this tenant, run only ONE instance of
#    Export-ComplianceManagerAuditTrail.ps1 (any copy — they're identical; see design.md Section 2)
#    against a single shared CSV path. The commands below assume this is the only Compliance
#    Manager assessment in the tenant so far.

# 3. Dry run — queries the last 7 days, reports what would be merged, writes nothing
./deploy/Export-ComplianceManagerAuditTrail.ps1 -OutputCsvPath './out/compliance-manager-audit-trail.csv' -WhatIf

# 4. First real run — a one-time backfill covering the full default retention window
./deploy/Export-ComplianceManagerAuditTrail.ps1 `
    -StartDate (Get-Date).AddDays(-180) -EndDate (Get-Date) `
    -OutputCsvPath './out/compliance-manager-audit-trail.csv'

# 5. Recurring run (schedule daily or weekly — overlapping windows are safe, see design.md §4).
#    Keep this running indefinitely — HIPAA's own documentation retention requirement (§8, §11)
#    outlives any Audit retention configuration this script depends on.
./deploy/Export-ComplianceManagerAuditTrail.ps1 -OutputCsvPath './out/compliance-manager-audit-trail.csv'

# 6. Validate the audit trail AND this scenario's own control-crosswalk manifest
./validate/Test-ComplianceManagerAuditTrail.ps1 -AuditTrailCsvPath './out/compliance-manager-audit-trail.csv'
```

## 6. Configuration reference

| Setting | Value this scenario uses | Notes |
|---|---|---|
| Regulation/template | HIPAA/HITECH | Premium template, US Government category — do **not** select the separately-listed HITRUST template (§11) |
| Assessment name | `HIPAA/HITECH - Microsoft 365 Estate` | Effectively permanent once created |
| Group | `Security & Compliance Assessments` (join if present, else create new) | Buys nontechnical improvement-action sharing with `assess-against-iso27001`/`pci-dss-assessment`/`soc2-assessment` — `design.md` §6 |
| Services in scope | Microsoft 365 only | Multicloud is an explicit non-goal — `design.md` §8 |
| Recommended role split | Administration: 1–2 people (ideally the designated Security Officer or a delegate) · Contribution/Assessor: control owners across IT/Security/Compliance/Privacy · Reader: leadership and the designated Privacy Officer if not already a Contributor | See `deploy/policy/hipaa-hitech-assessment-manifest.json` |
| Control crosswalk | 5 categories mapped to HIPAA/HITECH's own published rule structure (Privacy Rule, Administrative/Physical/Technical Safeguards, Breach Notification Rule), correlated against this library's own scenarios | `deploy/policy/hipaa-hitech-assessment-manifest.json`'s `controlCrosswalk` — this library's own correlation, not Microsoft's mapping (`design.md` §7) |
| Addressable-specification flag | Administrative, Physical, and Technical Safeguards categories each carry `hasAddressableSpecifications: true` | "Addressable" implementation specifications are still required, or require a documented alternative — not optional (§11) |
| Audit-trail script | Reused from `assess-against-iso27001/deploy/`, not duplicated | Tenant-wide operations — `design.md` §2/§4 |
| Audit-trail script idempotency | Merge + de-duplicate by `(CreationDate, Operations, UserIds, hash(AuditData))` | Identical model to the three sibling scenarios — see that scenario's `design.md` §8 |
| Validate script additions | Crosswalk manifest structural check (5 categories + addressable-flag check) + stale-scenario-path check | New in this scenario — see `validate/Test-ComplianceManagerAuditTrail.ps1`'s `.DESCRIPTION` |

## 7. Validation / how to prove it works

1. **Automated file-integrity + manifest check** — `./validate/Test-ComplianceManagerAuditTrail.ps1
   -AuditTrailCsvPath './out/compliance-manager-audit-trail.csv'` confirms the audit-trail CSV's
   schema/de-duplication/sort order (identical checks to the three sibling scenarios) **and**
   structurally validates this scenario's own `controlCrosswalk` manifest (all 5 categories
   present, each Security Rule safeguard category flagged `hasAddressableSpecifications: true`,
   every referenced `scenarios/...` path actually exists in this repo); exits non-zero on any hard
   failure.
2. **Manual verification checklist** — the same script prints a checklist (assessment exists,
   correct regulation **and not the HITRUST lookalike**, group placement correct, role assignments
   match, Privacy/Security Officer designations confirmed, group-sharing actually works for a
   shared nontechnical action, at least one "addressable" specification evidenced correctly, and —
   critically — that this assessment isn't being mis-presented as "HIPAA certified") because none
   of these have a read API to check programmatically (`design.md` §2).
3. **Functional test (audit-trail script)** — identical procedure to the three sibling scenarios:
   change a test user's Compliance Manager role, wait ~60 minutes for audit-log ingestion, re-run
   with a `-StartDate` covering that window, expect a new row with `Operation =
   ComplianceManagerRolesChange`.
4. **Group-sharing functional test** — if `assess-against-iso27001`, `pci-dss-assessment`, and/or
   `soc2-assessment` are also deployed: pick one nontechnical improvement action common across
   them, update its implementation status and notes in this HIPAA/HITECH assessment, then confirm
   within a few minutes that the same update appears in the other assessment(s). This is the one
   behavior in this scenario that's easy to configure wrong (wrong group choice) without any error
   message telling you so.
5. **Evidence for HHS OCR (if ever needed) or a covered entity's own due-diligence review** — the
   assessment's own **Export actions** report (§5, step 14) is the primary evidence artifact; this
   scenario's audit-trail CSV is a secondary, complementary artifact. **Neither one is a HIPAA
   certification** (none exists) **nor a substitute for the organization's own required Security
   Risk Analysis** — see §11.

## 8. Operations & tuning

**Review cadence:** run the audit-trail export on a **recurring schedule** — daily is cheap and
safe, weekly is the practical minimum given Audit (Standard)'s 180-day retention (§11). This matters
even more here than for the ISO 27001/PCI DSS/SOC 2 siblings: HIPAA's own Security Rule requires
retaining required documentation for **six years** from creation or last-effective date (45 CFR
§164.316(b)(2)(i) [[15]](#references)) — far longer than even a SOC 2 Type II period of performance.
Start the recurring schedule immediately and archive the accumulated CSV outside the tenant's own
audit-log retention window (which will expire long before the six-year documentation-retention clock
does) if a longer native window isn't purchased via Audit Premium retention policies
(`docs/licensing-matrix.md`). Review the **Controls** tab and compliance-score trend at least
**monthly**. Review role-assignment and automation-trust events **immediately** on the audit-trail
script's own warning, not on the monthly cadence — identical operational posture to the three
sibling scenarios.

**KPIs to watch:** identical four KPIs to the sibling scenarios (compliance score trend,
automated-vs-manual improvement-action ratio, `ComplianceManagerRolesChange` volume, any
automation-trust-change event at all — near-zero tolerance), plus two new ones specific to this
scenario:

- **Group-sharing drift** — if a nontechnical improvement action common to this assessment and
  `assess-against-iso27001`/`pci-dss-assessment`/`soc2-assessment` is updated in one but the update
  doesn't appear in the other(s) within a reasonable time, treat it as a signal the assessments may
  no longer share a group, not as a Compliance Manager bug.
- **"Addressable" specifications marked complete without documented rationale** — periodically
  spot-check improvement actions mapped to addressable Security Rule specifications (§6, §11) for
  evidence that either implements the specification or documents a reasonable alternative. An
  addressable action marked "Passed" with no supporting note is a governance gap, not proof of
  compliance.

**Incident-response runbook (automation-trust change detected):** identical to
`assess-against-iso27001/README.md` §8 steps 1–5 — triage the `AuditData` JSON, classify
planned/unplanned, document or escalate accordingly. **If the automation-trust change coincides
with a suspected or confirmed breach of unsecured PHI**: separately trigger this library's
`scenarios/audit/compromised-account-incident-response/` runbook and the organization's own Breach
Notification Rule procedure (§11) — this scenario's audit trail is evidence for that response, not
a substitute for it.

## 9. Rollback / decommission

See `rollback.md` for the full procedure. Because this scenario may share a group with
`assess-against-iso27001`, `pci-dss-assessment`, and/or `soc2-assessment`, its rollback has one
extra consideration those scenarios' own rollback docs already describe: deleting this assessment
does not delete or affect the shared group or the other assessment(s) in it.

## 10. Cost & licensing notes

- **Premium-template licensing, not PAYG** — identical model to the three sibling scenarios: 1 of
  the tenant's 3 free A5/E5/G5 premium-template slots, a purchased add-on, or a time-boxed trial
  [[6]](#references)[[7]](#references).
- **Don't select the wrong lookalike template.** HIPAA/HITECH and HITRUST are billed as **separate**
  premium-template slots — accidentally activating HITRUST when only a HIPAA/HITECH readiness view
  is needed consumes a second of the tenant's 3 free slots for a materially different (and
  separately certifiable) framework (§11).
- **No additional cost for the audit-trail script** beyond the Exchange Online role assignment, and
  **zero incremental cost if `assess-against-iso27001`, `pci-dss-assessment`, and/or
  `soc2-assessment` already run it** — this scenario reuses that script rather than running an
  additional copy (`design.md` §2).
- **Sizing note:** identical to the sibling scenarios — the premium-template allotment is
  per-regulation, not per-assessment.
- **A Business Associate Agreement (BAA) with Microsoft has no separate Compliance Manager
  licensing cost** — it is a contractual instrument under the Microsoft Product Terms, not a
  purchasable SKU [[5]](#references). It is a prerequisite this scenario assumes, not something it
  configures.

## 11. Known limitations & gotchas

- **There is currently no HHS-approved certification standard for HIPAA/HITECH compliance, for
  anyone.** Microsoft states this explicitly for its own position as a business associate: "There's
  currently no certification standard that the Department of Health and Human Services approves to
  demonstrate compliance with HIPAA or the HITECH Act by a business associate" [[16]](#references).
  This is a stronger statement than SOC 2's "this assessment isn't the report" caution — for HIPAA,
  no equivalent third-party-issued certification exists at all for this scenario's tooling output to
  be confused with. Do not let a customer conversation, an internal deck, or this scenario's own
  tooling output imply "HIPAA certified" status.
- **This assessment does not substitute for the organization's own legally required Security Risk
  Analysis** (45 CFR §164.308(a)(1)(ii)(A) [[10]](#references)) — a periodic risk assessment every
  covered entity and business associate must perform themselves. A Compliance Manager score,
  however complete, is an internal readiness-tracking and evidence tool for that broader legal
  obligation, not a replacement for it.
- **Compliance Manager's regulation catalog lists a separately-selectable "HITRUST" premium
  template alongside "HIPAA/HITECH"** in different catalog areas — HITRUST (the HITRUST CSF) is an
  independently governed, separately certifiable framework maintained by the HITRUST Alliance that
  harmonizes many standards including HIPAA, but selecting it does not produce a HIPAA/HITECH-
  specific readiness view, and vice versa. Selecting the wrong one wastes a premium-template slot
  and produces an assessment mapped to a different (if related) control set — see §5 step 5 and
  §10 for the cost consequence [[7]](#references).
- **"Addressable" HIPAA Security Rule implementation specifications are not optional.** Microsoft's
  own HIPAA configuration guidance states this explicitly: "The 'addressable' designation denotes a
  specification is reasonable and appropriate. Addressable doesn't mean that an implementation
  specification is optional. Therefore, subparts that are defined as addressable are also required"
  [[17]](#references). An organization must implement each addressable specification as written, or
  document a reasonable equivalent alternative measure and the rationale, or document why no
  safeguard is needed — never simply skip it. This is, in this scenario's assessment, the single
  most commonly misunderstood fact about the HIPAA Security Rule, which is why `deploy/policy/
  hipaa-hitech-assessment-manifest.json` and `validate/Test-ComplianceManagerAuditTrail.ps1` both
  structurally enforce that this distinction stays documented rather than silently dropped.
- **This scenario cannot script assessment creation, control mapping, or improvement-action
  updates** — identical constraint and reasoning to the three sibling scenarios (`design.md` §2).
- **The audit-trail script here is the same file as the three sibling scenarios', not an
  independent implementation** — deliberate, not an oversight; see `design.md` §2. It inherits
  those scripts' own limitations verbatim: it does not track compliance score or improvement-action
  status changes (only the 3 documented role/automation-trust operations), and it cannot see
  Compliance Manager access granted implicitly via the Global Administrator, Compliance
  Administrator, Compliance Data Administrator, or Security Administrator Entra ID roles — see
  `assess-against-iso27001/README.md` §11 for the full statement of both limitations, which apply
  here without modification.
- **The `controlCrosswalk` in `deploy/policy/hipaa-hitech-assessment-manifest.json` is this
  library's own scenario-to-rule correlation, not Microsoft's published improvement-action
  mapping** — see `design.md` §7. The Privacy Rule and Physical Safeguards categories have little
  to no direct technical coverage from this Microsoft 365/Purview-only library — stated plainly in
  the manifest rather than glossed over, and a dedicated PHI-classification/DLP scenario using
  Purview's built-in "U.S. Health Insurance Act (HIPAA) Enhanced" DLP policy template
  [[18]](#references) is tracked as a follow-up in `PROGRESS.md` rather than fabricated here.
- **Audit (Standard) default retention is 180 days** (1 year for Entra ID/Exchange/OneDrive/
  SharePoint under an E5-tier license; up to 10 years with Audit Premium retention policies)
  [[19]](#references) — dramatically shorter than HIPAA's own 6-year documentation retention
  requirement (§8, [[15]](#references)). Start the recurring audit-trail schedule immediately and
  archive its output outside the tenant's own audit-log retention window rather than relying on
  Audit (Standard) to preserve the underlying events for years.
- **The Breach Notification Rule's own notification obligations are not scripted here.** This
  scenario's crosswalk maps this library's incident-response scenarios to the *evidence-gathering*
  side of a breach response (§6), but notifying affected individuals, HHS, and — for breaches
  affecting 500 or more residents of a state or jurisdiction — the media, are organizational/legal
  processes this library does not automate [[3]](#references).
- **The "Action Update" Excel bulk-import file's exact column schema is not scripted here** — same
  tracked follow-up as the three sibling scenarios (`PROGRESS.md`).
- **This scenario does not select or scope which HIPAA rule categories apply within the Compliance
  Manager wizard.** No worked example or documented control was found during this build showing a
  per-category (Privacy Rule / Administrative / Physical / Technical Safeguards / Breach
  Notification) selection step in the assessment-creation flow — the template appears to map the
  full published control set once selected, the same all-or-nothing pattern the PCI DSS and SOC 2
  sibling scenarios document for their own regulations. **VERIFY (pilot tenant):** whether
  Compliance Manager's Controls/Improvement actions views let you filter or tag improvement actions
  by rule category after creation — this would materially help a Contributor/Assessor scope their
  work, and would help confirm which specific improvement actions correspond to "addressable" vs.
  "required" implementation specifications, which this scenario's grounding pass could not confirm
  is exposed anywhere in the Compliance Manager UI itself (only in the underlying rule text).
- **A high compliance score is not proof of compliance, and is even less a proxy for the
  organization's own legal HIPAA obligations.** Microsoft's own FAQ states this explicitly for
  Compliance Manager generally [[20]](#references) — HHS OCR's enforcement posture depends on the
  organization's actual documented safeguards, risk analysis, and breach-response conduct, not on
  this assessment's score.

## 12. References

1. Health Insurance Portability and Accountability Act (HIPAA) & Health Information Technology for Economic and Clinical Health (HITECH) Act — overview, business-associate scope, "Use Microsoft Purview Compliance Manager to assess your risk" — <https://learn.microsoft.com/compliance/regulatory/offering-hipaa-hitech>
2. HIPAA (US) — Azure compliance offering (Privacy Rule / Security Rule / Breach Notification Rule three-rule structure, Business Associate Agreement) — <https://learn.microsoft.com/azure/compliance/offerings/offering-hipaa-us>
3. HHS.gov — Breach Notification Rule — <https://www.hhs.gov/hipaa/for-professionals/breach-notification/index.html>
4. Get started with Compliance Manager — assessment templates page — <https://learn.microsoft.com/purview/compliance-manager-setup>
5. (see reference 1) Business Associate Agreement section — Microsoft HIPAA Business Associate Agreement — <https://servicetrust.microsoft.com/DocumentPage/d60051b9-8b5a-4794-9844-033773faaeb0>
6. Microsoft Purview service description — Compliance Manager — <https://learn.microsoft.com/office365/servicedescriptions/microsoft-365-service-descriptions/microsoft-365-tenantlevel-services-licensing-guidance/microsoft-purview-service-description#microsoft-purview-compliance-manager>
7. Compliance Manager regulations list — US Government category lists "HIPAA/HITECH" and, separately, "HITRUST" as distinct premium templates; 3-free-templates allotment (direct fetch, 2026-09-16) — <https://learn.microsoft.com/purview/compliance-manager-regulations-list#premium-regulations>
8. Get started with Compliance Manager (role types table incl. Entra role mapping) — <https://learn.microsoft.com/purview/compliance-manager-setup>
9. HHS.gov — Privacy Rule, personnel designation requirement (45 CFR §164.530(a)(1)) — <https://www.hhs.gov/hipaa/for-professionals/privacy/index.html>
10. Configuring Microsoft Entra ID for HIPAA compliance — HIPAA Security Rule overview, 45 CFR Part 160/164 structure, Security Officer designation (§164.308(a)(2)), Security Risk Analysis (§164.308(a)(1)(ii)(A)) — <https://learn.microsoft.com/entra/standards/hipaa-configure-for-compliance>
11. Build and manage assessments in Compliance Manager (create-assessment wizard, Groups for assessments — technical-vs-nontechnical improvement-action sync scope, one-assessment-per-product-per-regulation-per-group rule, groups can't be deleted, Data Protection Baseline default, Export an assessment report, Delete an assessment) — <https://learn.microsoft.com/purview/compliance-manager-assessments>
12. Working with improvement actions in Compliance Manager (built-in automation from DLM/Information Protection/DLP/Communication Compliance/IRM; automated testing/monitoring) — <https://learn.microsoft.com/purview/compliance-manager-improvement-actions>
13. (see reference 12) "Assign improvement action to assessor for completion"
14. Update improvement actions and bring compliance data into Compliance Manager (Export actions / Action Update tab / Update actions wizard) — <https://learn.microsoft.com/purview/compliance-manager-update-actions>
15. eCFR — 45 CFR §164.316, Policies and procedures and documentation requirements (six-year retention of required Security Rule documentation, §164.316(b)(2)(i)) — <https://www.ecfr.gov/current/title-45/section-164.316>
16. (see reference 1) Frequently asked questions — "There's currently no certification standard that the Department of Health and Human Services approves to demonstrate compliance with HIPAA or the HITECH Act by a business associate"
17. Configuring Microsoft Entra ID for HIPAA compliance — "Addressable doesn't mean that an implementation specification is optional. Therefore, subparts that are defined as addressable are also required." — <https://learn.microsoft.com/entra/standards/hipaa-configure-for-compliance>
18. What the DLP policy templates include — "U.S. Health Insurance Act (HIPAA) Enhanced" built-in DLP policy template (SSN/DEA Number/US Physical Addresses/All Full Names SITs, ICD-9-CM/ICD-10-CM keyword terms, Healthcare and Health/Medical Forms trainable classifiers) — <https://learn.microsoft.com/purview/dlp-policy-templates-include#us-health-insurance-act-hipaa-enhanced>
19. Manage audit log retention policies (180-day Standard default, 1-year E5 default for Entra/Exchange/OneDrive/SharePoint, up to 10 years with Audit Premium retention policies) — <https://learn.microsoft.com/purview/audit-log-retention-policies>
20. Compliance Manager frequently asked questions (a high score is not proof of compliance) — <https://learn.microsoft.com/purview/compliance-manager-faq>
21. Audit log activities — Compliance Manager activities table (the 3 documented operations) — <https://learn.microsoft.com/purview/audit-log-activities#compliance-manager-activities>
22. Search-UnifiedAuditLog reference — <https://learn.microsoft.com/powershell/module/exchangepowershell/search-unifiedauditlog>
23. `scenarios/compliance-manager/assess-against-iso27001/README.md`, `scenarios/compliance-manager/pci-dss-assessment/README.md`, and `scenarios/compliance-manager/soc2-assessment/README.md` — this library's sibling Compliance Manager assessments, cross-referenced throughout this scenario for the shared group/audit-trail-script pattern.

> Re-verify all links, the HIPAA/HITECH-vs-HITRUST catalog-naming detail, and the premium-template
> licensing model against current Microsoft Learn before a customer-facing assessment or sale —
> Compliance Manager's regulation catalog and licensing rules have changed materially before and can
> change again.
