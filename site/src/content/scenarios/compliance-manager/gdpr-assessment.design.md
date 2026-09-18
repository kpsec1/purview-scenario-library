---
part: "design"
parent: "compliance-manager/gdpr-assessment"
---
## 1. Problem statement

Any organization that offers goods or services to people in the EU, or that monitors the behavior
of EU residents, is subject to the EU General Data Protection Regulation (GDPR) regardless of where
the organization itself is located — an extraterritorial reach none of this library's four other
Compliance Manager scenarios' regulations share (HIPAA is US-specific, PCI DSS applies wherever card
data flows but is a card-network contractual scheme, SOC 2 is a US/AICPA attestation, ISO/IEC 27001
is voluntary and global but not a legal mandate). This library already ships technical controls
squarely aimed at GDPR-relevant data discovery, classification, protection, retention, and incident
response (`scenarios/data-map/*`, `scenarios/information-protection/*`, `scenarios/dlp/*`,
`scenarios/data-lifecycle-management/*`, `scenarios/audit/*`, `scenarios/unified-catalog/*`). This
scenario stands up the Microsoft Purview Compliance Manager **EU GDPR premium template** to give
those controls — and the rest of the Microsoft 365 estate — a scored, evidence-ready internal
readiness view, and correctly scopes what that view is (and is not) worth toward the organization's
actual legal GDPR obligations.

## 2. Why this scenario looks identical in shape to its four Compliance Manager siblings

Identical starting constraint to `scenarios/compliance-manager/assess-against-iso27001/`,
`scenarios/compliance-manager/pci-dss-assessment/`, `scenarios/compliance-manager/soc2-assessment/`,
and `scenarios/compliance-manager/hipaa-hitech-assessment/` (see any sibling's `design.md` §2 for the
full grounding): Compliance Manager has **no write API**. Assessment creation, control mapping, and
improvement-action status/evidence updates are portal- and Excel-wizard-driven only, re-confirmed
during this build against the current `compliance-manager-assessments`, `compliance-manager-
improvement-actions`, and `compliance-manager-setup` articles. `docs/automation-surface.md` §4 still
has no routing-table row for Compliance Manager. Fabricating a `New-ComplianceManagerAssessment`-style
cmdlet or a payload shape for the Excel "Action Update" bulk-import file would violate `AGENTS.md`
§4 for the same reason it would have for any sibling scenario.

**The same reason this folder does not ship a fifth, independent copy of the audit-trail script's
logic** (it ships a copy of the file, not a reimplementation): the three Compliance-Manager-specific
audit operations Microsoft documents (`ComplianceManagerRolesChange`,
`ComplianceManagerAutomationLevelChange`, `ComplianceManagerAutomationChange` — §4 below) are
**tenant-wide** events, not scoped to a single assessment. `scenarios/compliance-manager/
assess-against-iso27001/deploy/Export-ComplianceManagerAuditTrail.ps1` (already duplicated,
verbatim, into `pci-dss-assessment/deploy/`, `soc2-assessment/deploy/`, and `hipaa-hitech-
assessment/deploy/`) already queries and reports on all of them, for every Compliance Manager
assessment in the tenant, with no assessment-name parameter to narrow it. A fifth byte-for-byte-
identical script in this folder would be pure duplication with zero functional difference. This
scenario's `README.md` §5 documents reusing whichever copy is already deployed (and copying it
verbatim into this folder only if none of the four siblings is also purchased/deployed) rather than
maintaining five copies of security-relevant audit code that could silently drift apart.

**What this scenario ships that is genuinely new**, to still meet `AGENTS.md` §9's definition of
done in full:

1. A precise, repeatable **portal runbook** (`README.md` §5) backed by a structured, versioned,
   explicitly-non-executable reference manifest at `deploy/policy/gdpr-assessment-manifest.json` —
   same pattern as the four sibling scenarios, extended with a **GDPR-specific structure crosswalk**
   this library's own scenarios map against (manifest's `controlCrosswalk`, §7 below), an explicit
   group-placement decision that now accounts for a **five-way** group membership, and two
   GDPR-specific wrinkles none of the four siblings needed: a licensing-history caveat (§3 below) and
   a conditional (not blanket) accountability-officer requirement (§8, `README.md` §3).
2. A validate script (`validate/Test-ComplianceManagerAuditTrail.ps1`, reused and extended with a
   `-CrosswalkManifestPath` check) that adds GDPR-specific structural validation of this scenario's
   own manifest on top of the audit-trail file-integrity checks it already performs for the four
   sibling scenarios. Its manifest-shape check is structurally different from all four siblings'
   (6 named categories, none carrying a shared flag the way HIPAA's `hasAddressableSpecifications`
   does) because GDPR's own published structure — Data Subject Requests, Breach Notification, and
   Data Protection Impact Assessment per Microsoft's own `gdpr` overview, plus the Article 5
   processing principles, Article 46 cross-border-transfer safeguards, and Article 30/37
   accountability obligations that sit around them — is neither a numbered-goal shape (PCI DSS), a
   flat Trust-Services-Criteria shape (SOC 2), Annex A domains (ISO 27001), nor a rule-with-
   safeguard-categories shape (HIPAA/HITECH).
3. An explicit framing of GDPR's **own actual certification mechanism** (Article 42/43) that is
   neither "no certification exists at all" (HIPAA's sharper non-goal) nor "a real, mature
   third-party certification/attestation exists and this isn't it" (SOC 2/ISO 27001's framing) —
   GDPR genuinely describes a certification path in its own text, but current practice is fragmented
   across national supervisory authorities and accredited certification bodies rather than a single
   unified EU-wide seal (`README.md` §2/§11). This is a third, distinct shape of "what this
   assessment is not" that none of the four siblings' own non-goals directly cover.

## 3. Design goals

1. Stand up a **dedicated EU GDPR assessment** — not the tenant's default Data Protection Baseline
   (§5 below). Unlike every sibling scenario's Baseline analysis, the Baseline's own documented
   composition draws **directly and explicitly** on GDPR as one of its four source frameworks
   (alongside NIST CSF, ISO, and FedRAMP) — a materially different starting point that gets its own
   dedicated design section rather than a one-line restatement of the sibling scenarios' reasoning.
2. Make explicit which of this library's already-built scenarios contribute to which of GDPR's own
   structural components, using this library's own crosswalk (§7) rather than fabricating
   Microsoft's internal mapping.
3. State plainly, up front, what this assessment is **not**: a GDPR certification (a real but
   fragmented mechanism exists — §2 item 3, §11 — and this assessment is not it, nor a path toward
   it), a substitute for the organization's own Article 30 Records of Processing Activities, Article
   35 Data Protection Impact Assessments, or Article 28 processor-agreement review with Microsoft.
4. Correctly represent GDPR's **conditional** (not automatic) Article 37 Data Protection Officer
   designation requirement — a genuine contrast with HIPAA's blanket Privacy/Security Officer
   designation, not a restatement of it.
5. Correctly represent the December 2022 Compliance Manager licensing change's specific effect on
   GDPR (along with NIST 800-53 and ISO 27001): a template that used to be included by default now
   draws from the same 3-free-premium-template allotment as this library's other four Compliance
   Manager scenarios — a fact worth stating precisely rather than assuming GDPR's licensing model is
   identical to a sibling's from day one.
6. Avoid duplicating the tenant-wide audit-trail script this scenario shares with its four siblings
   — reuse it explicitly rather than re-shipping it (§2 above).
7. Never fabricate what isn't documented — same standard as every other scenario in this library,
   including where Microsoft's DSR/DPIA/breach-notification guidance describes organizational
   processes this library's Microsoft 365/Purview-only tooling cannot fully automate (§7's honest
   coverage gaps).

## 4. What Compliance Manager's audit log actually documents (identical grounding to all four sibling scenarios)

Re-confirmed during this build against the current `audit-log-activities` reference: exactly three
Compliance-Manager-specific operations exist in the unified audit log, and none of them are scoped
to a single assessment:

| Friendly name | Operation | What it means |
|---|---|---|
| Roles change | `ComplianceManagerRolesChange` | An admin changed a user's Compliance Manager role, tenant-wide or scoped to a specific assessment/regulation. |
| Tenant automation level change | `ComplianceManagerAutomationLevelChange` | An admin changed the org-wide automated-testing trust level across **all** improvement actions, in **every** assessment. |
| Testing source automation change | `ComplianceManagerAutomationChange` | An admin changed the automated-testing source setting for a specific improvement action — which may be shared across multiple assessments (§6). |

Because none of these three operations carry an assessment-scoping field a filter could target, one
running instance of the export script covers this EU GDPR assessment, the ISO 27001 assessment, the
PCI DSS assessment, the SOC 2 assessment, the HIPAA/HITECH assessment, and any other Compliance
Manager assessment the tenant creates — see §2 above for why this scenario reuses rather than
duplicates it.

## 5. Why a dedicated assessment instead of extending the Data Protection Baseline

This is the one design question where GDPR's answer needs its own argument rather than a restatement
of a sibling's. Microsoft's `compliance-manager-assessments` reference states the tenant's default
Data Protection Baseline assessment "draws elements primarily from NIST CSF … and ISO … as well as
from FedRAMP … and GDPR" — GDPR is not merely "a related framework" the way it is for the ISO
27001/PCI DSS/SOC 2 siblings' Baseline analyses; it is one of the four frameworks Microsoft names
**directly and explicitly** as a Baseline input. This makes the case for a dedicated assessment
*less* automatically obvious than for the HIPAA/HITECH sibling (whose Baseline doesn't mention HIPAA
at all) and worth stating precisely rather than glossing over: the Baseline **blends** GDPR elements
into a cross-framework composite score — it is not a citable, complete, GDPR-only control set an
organization could hand to a Data Protection Authority or use to demonstrate Article 5(2)
accountability on its own. A dedicated, named EU GDPR assessment, built from Compliance Manager's own
purpose-built EU GDPR premium template, is Microsoft's own documented intended use of that template
— not a deviation from it, and still the correct choice even though (unlike the HIPAA case) the
Baseline already partially "knows about" this regulation.

## 6. Group placement — what it actually buys you, now across five assessments

Microsoft's `compliance-manager-assessments` reference ("Groups for assessments") documents a
distinction this scenario's design leans on directly, and which is easy to get wrong — the same
quote every sibling scenario's `design.md` §6 already cites:

> "Any updates in details or status that you make to a **technical** improvement action will be
> picked up by assessments **across all groups**. **Nontechnical** improvement action updates will
> be recognized by assessments **within the group** where you apply them."

This means, unchanged from the smaller-N case the sibling scenarios document:

- **Technical** improvement actions (e.g., a DLP policy is turned on, a sensitivity label is
  auto-applied, MFA is enforced) already sync to **every** assessment in the tenant, regardless of
  which group any of them belongs to. Placing this EU GDPR assessment in the same group as the ISO
  27001, PCI DSS, SOC 2, and/or HIPAA/HITECH assessments buys **nothing** for these — they were
  already shared.
- **Nontechnical** improvement actions (documentation and operational actions — e.g., "a written
  information security policy exists," "a personnel background-check policy is documented," "an
  incident response plan is maintained") sync **only within a shared group**. GDPR's accountability
  and governance documentation overlaps meaningfully with HIPAA's Administrative Safeguards, SOC 2's
  Security Common Criteria, PCI DSS Requirement 12, and ISO/IEC 27001:2022's Annex A. Placing all
  five assessments in the same group (`deploy/policy/gdpr-assessment-manifest.json`'s `group.strategy:
  joinExistingIfPresent`) is what lets completing that documentation work **once** credit all five —
  the genuine, narrower benefit group placement provides, correctly scoped rather than oversold.

The grounded rule governing whether a **fifth** assessment can join the same group as the other four
still holds exactly as documented: a group can contain multiple assessments for the same **product**
(Microsoft 365) only if each is for a **different regulation**. ISO/IEC 27001:2022 + PCI DSS v4.0 +
SOC 2 + HIPAA/HITECH + EU GDPR in one group is five distinct regulations against the same product —
the same explicitly supported case the smaller-N scenarios already establish, not a new edge case
introduced by adding a fifth. Microsoft also documents that **groups can't be deleted** once created,
regardless of how many assessments remain in them — see `rollback.md` for what this means for
decommissioning.

## 7. The control crosswalk — GDPR's own structure, and its honest coverage gaps

`deploy/policy/gdpr-assessment-manifest.json`'s `controlCrosswalk` maps GDPR's own published
structure — Microsoft's `gdpr` overview groups the regulation's compliance work into **Data Subject
Requests**, **Breach Notification**, and **Data Protection Impact Assessment**, and this crosswalk
adds three more categories that sit alongside those three and are independently citable to GDPR's
own articles: the **Article 5 processing principles**, **Article 46 cross-border transfer
safeguards**, and **Article 30/37 accountability and governance** obligations — against **this
library's own scenarios**. This is the same category of claim every sibling scenario's `design.md`
makes and bounds identically: Microsoft's proprietary per-improvement-action-to-control mapping is
rendered inside the Compliance Manager UI per action, not published as a document this scenario can
fetch and cite, so this crosswalk is offered as this library's own correlation, not as a reproduction
of Microsoft's internal automation logic.

Three structural properties distinguish this crosswalk from the four siblings', because GDPR's own
published shape is genuinely different from SOC 2's Trust Services Criteria, PCI DSS's numbered
goals, ISO 27001's Annex A domains, or HIPAA's rule-with-safeguard-categories structure:

1. **Six categories, not five, and none share a common structural flag the way HIPAA's three
   Security Rule categories share `hasAddressableSpecifications`.** GDPR has no equivalent
   "required vs. addressable" trap in its own text — its own structural risk is different (item 3
   below).
2. **Data Subject Rights has a real, if still incomplete, technical building block in this
   library**: `scenarios/ediscovery/gdpr-dsr-fulfillment/`, which composes this library's
   `premium-legal-hold-and-export` and `search-and-purge-data-spillage` eDiscovery scenarios into a
   purpose-built DSR intake/SLA/fulfillment-hand-off workflow — a stronger starting position than
   HIPAA's Privacy Rule or GDPR's own Cross-Border Data Transfers category, both of which this
   library states plainly have little to no direct technical coverage. The honest caveat carries
   forward, narrower than before: that scenario still has no technical fulfillment for
   Rectification/Restriction/Objection, because (per its own `design.md` §6) no Purview-native
   control exists for any of the three — stated directly in the manifest rather than presented as
   complete DSR tooling.
3. **The structural risk this crosswalk guards against is different from HIPAA's "addressable ≠
   optional" trap.** Here it is: mistaking a high Compliance Manager score, or completion of the
   improvement actions Microsoft's built-in automation surfaces, for having a documented Article 6
   lawful basis for every processing activity and a complete Article 30 Record of Processing
   Activities — neither of which Compliance Manager (or this scenario) can verify from inside a
   Microsoft 365 tenant. This is stated directly in the manifest's `controlCrosswalk.principlesNote`
   and in `README.md` §11 rather than left implicit.

## 8. Non-goals

- **Generating the "Action Update" bulk-import Excel file.** Same constraint and same reasoning as
  every sibling scenario's `design.md`.
- **Reproducing Microsoft's per-control GDPR improvement-action mapping.** Out of reach for the
  reason in §7 above.
- **Multicloud (AWS/GCP/Azure via Defender for Cloud) service scoping**, even though Microsoft
  explicitly documents that a single EU GDPR assessment can span Microsoft 365, Azure, AWS, and GCP
  together (`compliance-manager-multicloud`) — a genuinely available option this scenario
  deliberately does not exercise, matching this library's tenant-only, Microsoft-365-only scope
  (`AGENTS.md` §5) and every sibling scenario's identical non-goal.
- **Producing or substituting for any form of GDPR certification.** GDPR's Article 42/43 mechanism
  is real but fragmented (§2 item 3, §11) — this scenario does not perform, simulate, or progress
  toward it.
- **Scripting or tracking Data Subject Requests, Breach Notification obligations, or Data Protection
  Impact Assessments themselves** as end-to-end organizational workflows. This scenario's crosswalk
  maps the *technical building blocks* that support each (§7), not the legal/organizational process
  itself — identical non-goal shape to the HIPAA/HITECH sibling's Breach Notification Rule treatment,
  extended here to all three of GDPR's own named compliance areas.
- **Determining Article 37 DPO applicability or making the designation itself.** An organizational/
  legal determination this library does not automate — see `README.md` §3.
- **Re-implementing the audit-trail export as a fifth, independent script.** Deliberately reused
  from the four sibling scenarios instead — see §2 above.
- **Scoping cross-border data transfer mechanisms (Standard Contractual Clauses, adequacy
  decisions).** Contractual/legal instruments between the organization and Microsoft (or another
  processor), not a Purview policy — see §7's Cross-Border Data Transfers category.

## 9. Key decisions

| Decision | Choice | Rationale |
|---|---|---|
| Assessment creation method | Portal wizard, documented as a runbook, not a script | No write API exists — see §2. |
| Regulation template | EU GDPR (General Data Protection Regulation), explicitly not the separately-listed UK Data Protection Act | A different jurisdiction/regulator (UK ICO, not an EU/EEA DPA) — see `README.md` §11. Not the same near-identical-name trap as HIPAA/HITECH-vs-HITRUST, but still worth stating precisely. |
| Audit-trail script | Reused from the four sibling scenarios' `deploy/`, not duplicated | The 3 monitored operations are tenant-wide, not assessment-scoped — see §2/§4. Copy it into this folder verbatim only if none of the four siblings is also deployed. |
| Group placement | Join the existing `Security & Compliance Assessments` group if present; create it if not | Buys shared credit specifically for **nontechnical** improvement actions across regulations — see §6. Not a claim of broader technical-control sharing, which already happens tenant-wide regardless of group. |
| Crosswalk format | This library's own scenario-to-article correlation, 6 categories matching GDPR's own published structure | Microsoft's own per-action mapping isn't published in a fetchable form — see §7. Genuinely different shape from all four sibling crosswalks, not a copy with relabeled categories. |
| Services scope | Microsoft 365 only | Matches this library's tenant-only, author-only scope (`AGENTS.md` §5), even though Microsoft documents a genuinely available multicloud option for this specific template (§8). |
| Framing of the assessment's evidentiary weight | Explicitly not a certification (a real but fragmented Article 42/43 mechanism exists — not the same as HIPAA's "none exists" or SOC 2/ISO 27001's "a mature one exists") and not a substitute for Article 30/Article 35/Article 28 obligations | Prevents this scenario's tooling from being read as a compliance shortcut it cannot be — see §2 item 3, §8, `README.md` §2/§11. |
| DPO designation treatment | Documented as conditional (Article 37 applicability criteria), never assumed required or not required | Directly grounded in GDPR's own Article 37 text — a genuine contrast with HIPAA's blanket officer-designation requirement, not a restatement of it. |
| Licensing-history caveat | Stated explicitly that GDPR (with NIST 800-53 and ISO 27001) moved from "included by default" to "counts against the 3-free-premium-template allotment" after December 2022 | Grounded directly in Compliance Manager's own FAQ — a fact specific to this regulation (and two others no sibling scenario covers) that none of the four existing sibling scenarios needed to state. |

## 10. Data flow / where each piece runs

```mermaid
flowchart TD
    A[Compliance Manager Administrator/Assessor<br/>completes portal runbook - README.md Section 5] --> B["EU GDPR assessment<br/>Group: Security & Compliance Assessments (joined or created)<br/>Scope: Microsoft 365"]
    C["Already-deployed GDPR-relevant scenarios in this tenant:<br/>Data Map classification / Data Estate Insights /<br/>Info Protection labeling / DLP exfil block /<br/>Retention-disposition / Unified Catalog / Audit"] -.built-in automation<br/>feeds technical-action signals<br/>tenant-wide, any group.-> B
    D[Contributors/Assessors] -->|manual work: evidence,<br/>notes, test status,<br/>Excel Action Update wizard| B
    E["ISO/IEC 27001:2022, PCI DSS v4.0,<br/>SOC 2, and/or HIPAA/HITECH assessments<br/>(if deployed, same group)"] <-.nontechnical improvement-action<br/>updates sync within the shared group only.-> B
    B --> F[Compliance score<br/>Controls tab<br/>native Reports page]
    G["Admin changes a Compliance Manager<br/>role or automation-trust setting<br/>(tenant-wide, not assessment-scoped)"] --> H["Unified audit log:<br/>ComplianceManagerRolesChange /<br/>ComplianceManagerAutomationLevelChange /<br/>ComplianceManagerAutomationChange"]
    H --> I["REUSED: assess-against-iso27001/deploy/<br/>Export-ComplianceManagerAuditTrail.ps1"]
    I --> J[Rolling audit-trail CSV<br/>retained per the organization's own<br/>Article 5(1)(e) retention schedule]
    J --> K[validate/Test-ComplianceManagerAuditTrail.ps1<br/>+ this scenario's own crosswalk-manifest check]
    B -.evidence + Export actions report.-> L[Data Protection Officer/privacy lead<br/>and, if ever needed, a Data Protection Authority]
```
