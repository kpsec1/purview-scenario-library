---
part: "design"
parent: "compliance-manager/hipaa-hitech-assessment"
---
## 1. Problem statement

A HIPAA covered entity, or a Microsoft 365-based business associate (health-tech ISV, MSP, or any
service provider that creates, receives, maintains, or transmits PHI on a covered entity's behalf),
needs an internal, evidenced readiness view of how its Microsoft 365 estate maps to HIPAA's Privacy
Rule, Security Rule, and Breach Notification Rule. This library already ships technical controls
squarely aimed at the kind of access-control, transmission-security, audit, and incident-response
controls the HIPAA Security Rule and Breach Notification Rule evaluate (`scenarios/information-
protection/*`, `scenarios/dlp/*`, `scenarios/adaptive-protection/*`, `scenarios/insider-risk/*`,
`scenarios/audit/*`). This scenario stands up the Microsoft Purview Compliance Manager **HIPAA/
HITECH premium template** to give those controls — and the rest of the Microsoft 365 estate — a
scored, evidence-ready internal readiness view, and correctly scopes what that view is (and, more
starkly than any sibling scenario, is **not**) worth toward actual legal HIPAA compliance.

## 2. Why this scenario looks identical in shape to its three Compliance Manager siblings

Identical starting constraint to `scenarios/compliance-manager/assess-against-iso27001/`,
`scenarios/compliance-manager/pci-dss-assessment/`, and `scenarios/compliance-manager/
soc2-assessment/` (see any sibling's `design.md` §2 for the full grounding): Compliance Manager has
**no write API**. Assessment creation, control mapping, and improvement-action status/evidence
updates are portal- and Excel-wizard-driven only, re-confirmed during this build against the current
`compliance-manager-assessments`, `compliance-manager-improvement-actions`, and `compliance-manager-
setup` articles. `docs/automation-surface.md` §4 still has no routing-table row for Compliance
Manager. Fabricating a `New-ComplianceManagerAssessment`-style cmdlet or a payload shape for the
Excel "Action Update" bulk-import file would violate `AGENTS.md` §4 for the same reason it would
have for any sibling scenario.

**The same reason this folder does not ship a fourth, independent copy of the audit-trail script's
logic** (it ships a copy of the file, not a reimplementation): the three Compliance-Manager-specific
audit operations Microsoft documents (`ComplianceManagerRolesChange`,
`ComplianceManagerAutomationLevelChange`, `ComplianceManagerAutomationChange` — §4 below) are
**tenant-wide** events, not scoped to a single assessment. `scenarios/compliance-manager/
assess-against-iso27001/deploy/Export-ComplianceManagerAuditTrail.ps1` (already duplicated,
verbatim, into `pci-dss-assessment/deploy/` and `soc2-assessment/deploy/`) already queries and
reports on all of them, for every Compliance Manager assessment in the tenant, with no
assessment-name parameter to narrow it. A fourth byte-for-byte-identical script in this folder would
be pure duplication with zero functional difference. This scenario's `README.md` §5 documents
reusing whichever copy is already deployed (and copying it verbatim into this folder only if none of
the three siblings is also purchased/deployed) rather than maintaining four copies of
security-relevant audit code that could silently drift apart.

**What this scenario ships that is genuinely new**, to still meet `AGENTS.md` §9's definition of
done in full:

1. A precise, repeatable **portal runbook** (`README.md` §5) backed by a structured, versioned,
   explicitly-non-executable reference manifest at `deploy/policy/hipaa-hitech-assessment-
   manifest.json` — same pattern as the three sibling scenarios, extended with a **HIPAA/HITECH
   rule-structure crosswalk** this library's own scenarios map against (manifest's
   `controlCrosswalk`, §7 below), an explicit group-placement decision that now accounts for a
   **four-way** group membership, and a HIPAA-specific structural distinction (the "addressable is
   not optional" flag) none of the three siblings' own crosswalks needed.
2. A validate script (`validate/Test-ComplianceManagerAuditTrail.ps1`, reused and extended with a
   `-CrosswalkManifestPath` check) that adds HIPAA-specific structural validation of this scenario's
   own manifest on top of the audit-trail file-integrity checks it already performs for the three
   sibling scenarios. Its manifest-shape check is structurally different from all three siblings'
   (5 named rule categories, three of which carry a `hasAddressableSpecifications` flag) because
   HIPAA/HITECH's own published structure — Privacy Rule, three Security Rule safeguard categories,
   Breach Notification Rule — is neither a numbered-goal shape (PCI DSS) nor a flat
   Trust-Services-Criteria shape (SOC 2, ISO 27001's Annex A domains).
3. An explicit **"no certification exists at all"** framing (`README.md` §2/§11) sharper than any
   sibling scenario's own non-goal: SOC 2 at least has a real, CPA-issued report this scenario is
   careful not to be confused with; ISO 27001 has a real third-party certification; HIPAA has
   **no HHS-approved certification standard for anyone**, covered entity or business associate
   [[16]](#references, `README.md`) — so there is no possible legitimate "certificate" this
   scenario's tooling could even be mistaken for, only the organization's own required Security Risk
   Analysis and the CPA/QSA-equivalent-free reality of HIPAA enforcement (HHS OCR investigation,
   not a scheduled third-party audit cycle).

## 3. Design goals

1. Stand up a **dedicated HIPAA/HITECH assessment** — not the tenant's default Data Protection
   Baseline (§5 below, identical reasoning to the three sibling scenarios, strengthened here because
   the Baseline's own documented composition (NIST CSF/ISO/FedRAMP/GDPR) does not even reference
   HIPAA), and explicitly **not** the separately-listed "HITRUST" template that Compliance Manager's
   regulation catalog also lists (§11) — with a deliberate group-placement decision and a minimal,
   correct services scope.
2. Make explicit which of this library's already-built scenarios contribute to which of HIPAA/
   HITECH's own rule categories, using this library's own crosswalk (§7) rather than fabricating
   Microsoft's internal mapping.
3. State plainly, up front, what this assessment is **not**: a HIPAA certification (none exists),
   a substitute for the organization's own Security Risk Analysis, or a substitute for a signed
   Business Associate Agreement. This is the single most important scoping statement in this
   scenario — see `README.md` §2/§11 and the CISO lens in `reviews.md`.
4. Correctly represent HIPAA's own "addressable is not optional" Security Rule distinction — a fact
   this build found directly grounded in Microsoft's own HIPAA configuration guidance, not inferred
   — as a structural property of the crosswalk manifest, not just prose.
5. Avoid duplicating the tenant-wide audit-trail script this scenario shares with its three
   siblings — reuse it explicitly rather than re-shipping it (§2 above).
6. Never fabricate what isn't documented — same standard as every other scenario in this library,
   including where the Compliance Manager wizard does **not** expose a documented rule-category
   selection step (§11's VERIFY item).

## 4. What Compliance Manager's audit log actually documents (identical grounding to all three sibling scenarios)

Re-confirmed during this build against the current `audit-log-activities` reference: exactly three
Compliance-Manager-specific operations exist in the unified audit log, and none of them are
scoped to a single assessment:

| Friendly name | Operation | What it means |
|---|---|---|
| Roles change | `ComplianceManagerRolesChange` | An admin changed a user's Compliance Manager role, tenant-wide or scoped to a specific assessment/regulation. |
| Tenant automation level change | `ComplianceManagerAutomationLevelChange` | An admin changed the org-wide automated-testing trust level across **all** improvement actions, in **every** assessment. |
| Testing source automation change | `ComplianceManagerAutomationChange` | An admin changed the automated-testing source setting for a specific improvement action — which may be shared across multiple assessments (§6). |

Because none of these three operations carry an assessment-scoping field a filter could target, one
running instance of the export script covers this HIPAA/HITECH assessment, the ISO 27001 assessment,
the PCI DSS assessment, the SOC 2 assessment, and any other Compliance Manager assessment the tenant
creates — see §2 above for why this scenario reuses rather than duplicates it.

## 5. Why a dedicated assessment instead of extending the Data Protection Baseline

Identical reasoning to the three sibling scenarios' own `design.md` §5: the tenant's default Data
Protection Baseline assessment blends NIST CSF/ISO/FedRAMP/GDPR elements and is not itself a
citable, audit-mappable HIPAA/HITECH control set. Notably, unlike the ISO 27001/PCI DSS/SOC 2 cases
(where the Baseline at least draws on a related framework), the Baseline's own documented
composition does not reference HIPAA at all — making the case for a dedicated assessment here even
more direct than for any sibling scenario. A dedicated, named HIPAA/HITECH assessment is Microsoft's
own documented intended use of the premium template, not a deviation from it.

## 6. Group placement — what it actually buys you, now across four assessments

Microsoft's `compliance-manager-assessments` reference ("Groups for assessments") documents a
distinction this scenario's design leans on directly, and which is easy to get wrong — the same
quote every sibling scenario's `design.md` §6 already cites:

> "Any updates in details or status that you make to a **technical** improvement action will be
> picked up by assessments **across all groups**. **Nontechnical** improvement action updates will
> be recognized by assessments **within the group** where you apply them."

This means, unchanged from the smaller-N case the sibling scenarios document:

- **Technical** improvement actions (e.g., a DLP policy is turned on, a sensitivity label is
  auto-applied, MFA is enforced) already sync to **every** assessment in the tenant, regardless of
  which group any of them belongs to. Placing this HIPAA/HITECH assessment in the same group as the
  ISO 27001, PCI DSS, and/or SOC 2 assessments buys **nothing** for these — they were already
  shared.
- **Nontechnical** improvement actions (documentation and operational actions — e.g., "a written
  information security policy exists," "a personnel background-check policy is documented," "an
  incident response plan is maintained") sync **only within a shared group**. HIPAA's Administrative
  Safeguards, SOC 2's Security Common Criteria, PCI DSS Requirement 12, and ISO/IEC 27001:2022's
  Annex A all require overlapping documentation of this kind. Placing all four assessments in the
  same group (`deploy/policy/hipaa-hitech-assessment-manifest.json`'s `group.strategy:
  joinExistingIfPresent`) is what lets completing that documentation work **once** credit all four
  — the genuine, narrower benefit group placement provides, correctly scoped rather than oversold.

The grounded rule governing whether a **fourth** assessment can join the same group as the other
three still holds exactly as documented: a group can contain multiple assessments for the same
**product** (Microsoft 365) only if each is for a **different regulation**. ISO/IEC 27001:2022 +
PCI DSS v4.0 + SOC 2 + HIPAA/HITECH in one group is four distinct regulations against the same
product — the same explicitly supported case the smaller-N scenarios already establish, not a new
edge case introduced by adding a fourth. Microsoft also documents that **groups can't be deleted**
once created, regardless of how many assessments remain in them — see `rollback.md` for what this
means for decommissioning.

## 7. The control crosswalk — HIPAA/HITECH's own rule structure, and why "addressable ≠ optional" matters

`deploy/policy/hipaa-hitech-assessment-manifest.json`'s `controlCrosswalk` maps HIPAA/HITECH's own
published rule structure — the **Privacy Rule**, the **Security Rule**'s three safeguard categories
(**Administrative**, **Physical**, **Technical** — 45 CFR §§164.308/164.310/164.312), and the
**Breach Notification Rule** — against **this library's own scenarios**. This is the same category
of claim every sibling scenario's `design.md` makes and bounds identically: Microsoft's proprietary
per-improvement-action-to-control mapping is rendered inside the Compliance Manager UI per action,
not published as a document this scenario can fetch and cite, so this crosswalk is offered as this
library's own correlation, not as a reproduction of Microsoft's internal automation logic.

Two structural properties distinguish this crosswalk from the three siblings', because HIPAA's own
published shape is genuinely different from SOC 2's Trust Services Criteria or PCI DSS's numbered
goals:

1. **The Privacy Rule and Physical Safeguards categories have little to no direct technical
   coverage** from this Microsoft 365/Purview-only library — the Privacy Rule's core obligations
   (minimum-necessary use/disclosure, patient right-of-access) are organizational/legal processes,
   and Physical Safeguards are largely a facility/workstation-physical-security concern outside
   Purview's reach entirely (an even sharper version of PCI DSS's Goal 1/3 network-and-vulnerability
   gap, or SOC 2's Availability/Processing Integrity gap). Stated plainly in the manifest rather
   than stretched to look like coverage that doesn't exist.
2. **HIPAA's Security Rule distinguishes "required" from "addressable" implementation
   specifications, and this distinction is a genuine, well-documented source of misconfiguration
   risk this crosswalk structurally guards against.** Microsoft's own HIPAA configuration guidance
   states directly: "Addressable doesn't mean that an implementation specification is optional.
   Therefore, subparts that are defined as addressable are also required" [[17]](#references,
   `README.md`). None of the three sibling regulations (ISO 27001's Annex A, PCI DSS's numbered
   requirements, SOC 2's Trust Services Criteria) have an equivalent named "this looks optional but
   isn't" trap built into their own control taxonomy — so this crosswalk's `hasAddressableSpecifications:
   true` flag on the three Security Rule categories, and the corresponding validate-script check
   that the flag can't silently disappear, is new to this scenario rather than copied from a
   sibling's pattern that happened to also apply here.

## 8. Non-goals

- **Generating the "Action Update" bulk-import Excel file.** Same constraint and same reasoning as
  every sibling scenario's `design.md`.
- **Reproducing Microsoft's per-control HIPAA/HITECH improvement-action mapping.** Out of reach for
  the reason in §7 above.
- **Multicloud (AWS/GCP/Azure via Defender for Cloud) service scoping.** Scoped to Microsoft 365
  only, matching this library's tenant-only scope (`AGENTS.md` §5) and all three sibling scenarios'
  identical non-goal.
- **Producing or substituting for any form of HIPAA certification.** No such HHS-approved
  certification exists for anyone (§2, §11) — this non-goal is even more absolute here than the
  equivalent non-goal in the SOC 2 or ISO 27001 scenarios, where a real third-party certification or
  report at least exists for this scenario to be careful not to be confused with.
- **Scripting or tracking the Breach Notification Rule's own notification obligations**
  (notifying affected individuals, HHS, and — for large breaches — the media). These are
  organizational/legal processes this library does not automate; this scenario's crosswalk maps
  only to the evidence-gathering side of a breach response (§7, `README.md` §11).
- **Re-implementing the audit-trail export as a fourth, independent script.** Deliberately reused
  from the three sibling scenarios instead — see §2 above.
- **Scripting rule-category selection within the assessment.** No documented wizard step or API for
  this was found during this build (§11's VERIFY item) — not fabricated.

## 9. Key decisions

| Decision | Choice | Rationale |
|---|---|---|
| Assessment creation method | Portal wizard, documented as a runbook, not a script | No write API exists — see §2. |
| Regulation template | HIPAA/HITECH, explicitly not HITRUST | HITRUST is a separate, independently governed certifiable framework, not a HIPAA/HITECH-specific readiness view — see `README.md` §11. |
| Audit-trail script | Reused from the three sibling scenarios' `deploy/`, not duplicated | The 3 monitored operations are tenant-wide, not assessment-scoped — see §2/§4. Copy it into this folder verbatim only if none of the three siblings is also deployed. |
| Group placement | Join the existing `Security & Compliance Assessments` group if present; create it if not | Buys shared credit specifically for **nontechnical** improvement actions across regulations — see §6. Not a claim of broader technical-control sharing, which already happens tenant-wide regardless of group. |
| Crosswalk format | This library's own scenario-to-rule-category correlation, with the three Security Rule categories flagged `hasAddressableSpecifications: true` | Microsoft's own per-action mapping isn't published in a fetchable form — see §7. The addressable-flag is HIPAA-specific and has no analog in the three sibling crosswalks. |
| Services scope | Microsoft 365 only | Matches this library's tenant-only, author-only scope (`AGENTS.md` §5). |
| Framing of the assessment's evidentiary weight | Explicitly not a certification (none exists) and not a substitute for the org's own Security Risk Analysis or BAA | Prevents this scenario's tooling from being read as a compliance shortcut it cannot be — see §8, `README.md` §2/§11. |
| "Addressable" specification treatment | Documented as required-with-a-documented-alternative-path, never as optional | Directly grounded in Microsoft's own HIPAA configuration guidance — see §7. |

## 10. Data flow / where each piece runs

```mermaid
flowchart TD
    A[Compliance Manager Administrator/Assessor<br/>completes portal runbook - README.md Section 5] --> B["HIPAA/HITECH assessment<br/>Group: Security & Compliance Assessments (joined or created)<br/>Scope: Microsoft 365"]
    C["Already-deployed HIPAA-relevant scenarios in this tenant:<br/>Info Protection labeling / DLP exfil block / Endpoint DLP /<br/>Legacy-auth block / IRM / Audit / Compromised-account response"] -.built-in automation<br/>feeds technical-action signals<br/>tenant-wide, any group.-> B
    D[Contributors/Assessors] -->|manual work: evidence,<br/>notes, test status,<br/>Excel Action Update wizard| B
    E["ISO/IEC 27001:2022, PCI DSS v4.0,<br/>and/or SOC 2 assessments<br/>(if deployed, same group)"] <-.nontechnical improvement-action<br/>updates sync within the shared group only.-> B
    B --> F[Compliance score<br/>Controls tab<br/>native Reports page]
    G["Admin changes a Compliance Manager<br/>role or automation-trust setting<br/>(tenant-wide, not assessment-scoped)"] --> H["Unified audit log:<br/>ComplianceManagerRolesChange /<br/>ComplianceManagerAutomationLevelChange /<br/>ComplianceManagerAutomationChange"]
    H --> I["REUSED: assess-against-iso27001/deploy/<br/>Export-ComplianceManagerAuditTrail.ps1"]
    I --> J[Rolling audit-trail CSV<br/>archived 6+ years per Sec 164.316(b)(2)(i)]
    J --> K[validate/Test-ComplianceManagerAuditTrail.ps1<br/>+ this scenario's rule-crosswalk-manifest check]
    B -.evidence + Export actions report.-> L[Designated Privacy Officer / Security Officer<br/>and, if ever needed, HHS OCR investigation]
```
