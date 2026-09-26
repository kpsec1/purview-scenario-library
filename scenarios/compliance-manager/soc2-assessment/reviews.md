# Four-Lens Review - Compliance Manager: SOC 2 Assessment

Reviewed after the initial draft of `README.md`, `design.md`, `deploy/`, and `validate/`. One round
of findings below; all **Fix** items were applied to the scenario before this file was finalized
(see "Resolution" under each). No **Fail** items were raised.

---

## 🔴 Red Team

**Verdict: Fix (resolved)**

1. **A freshly-created SOC 2 assessment inherits the tenant's existing shared-technical-action state
   on day one, invisibly.** Identical mechanism to the finding `pci-dss-assessment/reviews.md` §🔴
   finding 1 already raised and `assess-against-iso27001/reviews.md` documents: `design.md` §6
   correctly states that **technical** improvement actions sync "across all groups" tenant-wide, but
   that means this brand-new assessment's very first compliance score is computed against whatever
   automation-trust settings and prior manual overrides already exist tenant-wide - not from
   scratch. With three Compliance Manager assessments now potentially coexisting in this tenant (ISO
   27001, PCI DSS, SOC 2), the surface area for a forgotten weakening event to have occurred in
   *any* of the other two is larger than either sibling scenario faced alone.
   - **Resolution:** `README.md` §5 step 3 states deployment order matters "regardless of which
     group [the assessment] ends up in," and §8 carries the same day-one-score caution. Not
     independently fixable by this scenario's tooling - no read API exists to enumerate every other
     assessment's shared technical actions (`design.md` §2) - so the mitigation is documentation
     plus the existing `ComplianceManagerAutomationChange` monitoring in the reused audit-trail
     script, unchanged from the accepted mitigation in both sibling scenarios' own reviews.
2. **A salesperson under deal-closing pressure forwards this assessment's Excel export to a
   prospect's procurement team in place of the actual SOC 2 report**, because the export looks
   sufficiently official (Compliance Manager branding, a compliance score, a controls list) to an
   unsophisticated reader on the receiving end. This is a sharper version of the generic
   misrepresentation risk `pci-dss-assessment/reviews.md` §🔴 finding 2 raised for SAQ/RoC, because
   SOC 2 reports are specifically **requested and evaluated by name** in routine B2B vendor-security
   workflows - the exact moment this scenario's tooling output is most likely to get grabbed and
   sent externally under time pressure.
   - **Resolution:** `README.md` §2 states the "not a substitute for an actual SOC 2 report"
     distinction in its second paragraph, not buried in §11, and adds a dedicated portal-runbook
     step (§5 step 15) instructing that an engaged CPA firm gets **Reader** portal access or a
     scoped export, not a rebranding of this assessment's own score as deliverable evidence.
     `design.md` §8 lists producing/substituting for a SOC 2 report as a non-goal "in the strongest
     possible sense," matching the PCI DSS scenario's own strongest-non-goal framing for its
     equivalent risk.
3. **Selecting the wrong sibling template ("System and Organization Controls (SOC) 1") at the
   regulation picker** - a materially different Trust Services scope (financial-reporting internal
   controls, not security/confidentiality/privacy) - burns a premium-template slot and produces an
   assessment mapped to the wrong control set entirely. Structurally the same class of picker-level
   mistake `pci-dss-assessment/reviews.md` §🔴 finding 3 flagged for the PCI DSS v3.2.1/v4.0 pair,
   but here the two templates aren't even different versions of the same standard - they're
   different standards that happen to share the "SOC" name and catalog section.
   - **Resolution:** Confirmed already addressed: `README.md` §5 step 5 calls this out explicitly at
     the exact moment (the regulation picker) it would happen, explaining *why* SOC 1 is wrong (not
     just that it is), and §10/§11 cover the cost and catalog-accuracy angles respectively. No
     further change.

No remaining Fix/Fail after resolution.

---

## 🔵 Blue Team

**Verdict: Fix (resolved)**

1. **The new crosswalk-manifest structural check in `validate/
   Test-ComplianceManagerAuditTrail.ps1` could be misread as proof the referenced controls are
   actually deployed in the tenant.** Identical scope-boundary risk to `pci-dss-assessment/
   reviews.md` §🔵 finding 1.
   - **Resolution:** Left as-is after review, for the identical reason that scenario's review
     accepted: the script's `.DESCRIPTION` already states the check only confirms repo-local paths
     exist, and the manual checklist's own tenant-state spot-check item is the actual proof point.
     No code change; confirming the separation of concerns is correct, not adding a redundant
     disclaimer.
2. **Alert routing for the automation-trust-change warning** - same, already-accepted scope
   boundary as `assess-against-iso27001/reviews.md` finding 2 and `pci-dss-assessment/reviews.md`
   finding 2. No change.
3. **Group-sharing drift across three assessments has no automated detection**, and with a third
   assessment now potentially in the shared group, there are more possible pairwise drift scenarios
   (ISO↔PCI, ISO↔SOC2, PCI↔SOC2) than either two-assessment sibling scenario had to consider.
   - **Resolution:** Carried forward the same mitigation `pci-dss-assessment/reviews.md` §🔵
     finding 3 accepted: `README.md` §7 item 4 (group-sharing functional test) and §8 (group-sharing
     drift KPI), both now phrased to cover "the other assessment(s)" plural rather than assuming
     exactly one sibling. Not automatable - Compliance Manager has no read API to query an
     improvement action's synchronized status across assessments (`design.md` §2).
4. **A silently-failed scheduled audit-trail export could create an unrecoverable evidence gap
   during a live SOC 2 Type II period of performance.** This is a genuinely new risk relative to
   both sibling scenarios: ISO 27001 and PCI DSS assessments don't have a standing multi-month
   evidence-collection window baked into their own attestation model the way a Type II report does.
   If the scheduled run fails quietly for long enough that Audit (Standard)'s 180-day retention
   expires the underlying events before anyone notices, that portion of the audit trail cannot be
   backfilled at all - not even by re-running the script.
   - **Resolution:** Added the "Evidence-window continuity" KPI to `README.md` §8 and a dedicated
     manual-checklist item to `validate/Test-ComplianceManagerAuditTrail.ps1` instructing an
     operator to confirm the CSV's collection window actually covers the full period of performance
     when one is underway. Not automatable as a hard pass/fail from inside the script itself - it
     has no way to know whether a Type II engagement is currently active or what its start date was
     (that's a fact about the organization's audit engagement, not about Compliance Manager) - so a
     documented, explicit manual check is the correct-for-this-gap mitigation, consistent with this
     scenario's other manual checklist items for facts with no read API.

No remaining Fail after resolution.

---

## 🎩 CISO

**Verdict: Pass**

- **Risk reduction vs. cost:** correctly scoped as a governance/evidence control, not a technical
  one (`README.md` §2) - same honest framing as both sibling scenarios. The driver here is
  **commercial**, not regulatory - a missing or unconvincing SOC 2 story can stall or lose an
  enterprise deal outright - which makes the "this is not the report itself" non-goal (§8) just as
  load-bearing as PCI DSS's SAQ/RoC caution, for a different reason: oversell it internally and a
  salesperson's premature claim to a prospect becomes the CISO's problem to walk back.
- **Board-level narrative:** "we track our SOC 2 readiness in the same governance platform as our
  other frameworks, we know exactly what does and doesn't share between them, and our sales and
  customer-success teams are trained on the difference between this internal tracker and our actual
  signed SOC 2 report" is a defensible, audit-committee-ready and sales-enablement-ready narrative.
- **Compliance mapping:** the control crosswalk (`design.md` §7) gives a CISO a one-page answer to
  "which of our Microsoft 365 investments count toward SOC 2," including the honest admission that
  2 of 5 TSC categories (Availability, Processing Integrity) aren't covered by this library at all -
  useful precisely because it doesn't inflate coverage a customer's security questionnaire might
  later probe.
- **Change-management impact:** the recommended deployment order (technical controls first, then
  the assessment) is the same sequencing call both sibling scenarios' CISO lenses already endorsed,
  for the same reason.
- **Would I fund this?** Yes - the premium-template license is a near-certain cost regardless
  (SOC 2 readiness is table stakes for most enterprise SaaS sales motions), and this scenario's
  incremental cost is negligible (largely zero, given the reused audit-trail script) against the
  value of correctly scoping what the resulting readiness view does and doesn't prove to a customer
  or an engaged CPA firm.

No Fix/Fail items from this lens.

---

## 🟦 Microsoft Product Owner

**Verdict: Fix (resolved)**

1. **Is reusing (not duplicating) the audit-trail script a legitimate engineering decision for a
   third consumer, or does three-way reuse start to look like this scenario's `deploy/` folder is
   incomplete relative to `AGENTS.md` §9's checklist?**
   - **Resolution:** `design.md` §2 states the reasoning directly, extending the same argument
     `pci-dss-assessment/design.md` §2 already made for the second copy: the 3 monitored operations
     are tenant-wide, not assessment-scoped, so a third byte-for-byte copy would still be pure
     duplication. The working, idempotent, parameterized, dry-run-capable code required by
     `AGENTS.md` §9 exists and is shipped in this folder - reused rather than reinvented, correct at
     any number of sibling consumers, not just two.
2. **Is "System and Organization Controls (SOC) 2" (verbatim) the correct current catalog template
   name, and is it being correctly distinguished from Microsoft's separate SOC 2 Type 2 attestation
   documentation for its own services?**
   - **Resolution:** Verified directly against the current `compliance-manager-regulations-list`
     premium-regulations catalog during this build via a direct Microsoft Learn MCP fetch (this
     session's network environment did not block it) - the catalog's Global section lists the entry
     exactly as "System and Organization Controls (SOC) 2," alongside a separate "System and
     Organization Controls (SOC) 1" entry. This scenario references the template by its exact
     catalog name throughout. `README.md` §2 also correctly distinguishes Microsoft's own SOC 2
     Type 2 attestation for Office 365/Azure (a fact about Microsoft's services, cited as reference
     2, evidencing the commercial norm this scenario's driver rests on) from the customer's own
     Compliance Manager assessment (this scenario's actual subject) - these are not conflated.
3. **Is the control crosswalk correctly and honestly bounded, or does it risk reading as this
   scenario claiming to know Microsoft's real per-action SOC 2 mapping?**
   - **Resolution:** `deploy/policy/soc2-assessment-manifest.json`'s `controlCrosswalk._comment` and
     `design.md` §7 both state explicitly, in the first sentence, that this is this library's own
     correlation and not a reproduction of Microsoft's internal mapping - matching the identical
     caution both sibling scenarios' designs already establish as this library's pattern for this
     exact class of claim.
4. **Licensing and role-name accuracy** - checked against `docs/licensing-matrix.md`'s existing
   Compliance Manager row and both sibling scenarios' already-reviewed role tables; reused verbatim
   here since Compliance Manager's RBAC and premium-template licensing model are tenant-wide
   constructs, not regulation-specific ones. Confirmed consistent.
5. **Is building a dedicated assessment instead of extending the Data Protection Baseline still
   correct for a third, commercially-driven (rather than regulatory) regulation?**
   - **Resolution:** Yes - the baseline's multi-framework blending problem (`design.md` §5) applies
     identically regardless of what specifically motivates pursuing the regulation. Confirmed
     consistent with both sibling scenarios' `design.md` §5 reasoning, not a copy-paste that happens
     to also be wrong here.
6. **Was the Type I/Type II distinction handled correctly** - i.e., does Compliance Manager's
   catalog actually expose separate templates for each report type, or was that assumed?
   - **Resolution:** Not assumed - this build's grounding pass found no separate "SOC 2 Type I" or
     "SOC 2 Type II" catalog entry; only the single "System and Organization Controls (SOC) 2"
     template exists. `README.md` §11 states this explicitly rather than silently picking one report
     type's name for the template, and frames the Type I/Type II distinction correctly as being
     about the CPA firm's engagement, not about which Compliance Manager template to select
     (`design.md` §9).

No remaining Fail after resolution.

---

## Summary

| Lens | Initial verdict | Findings | Resolution |
|---|---|---|---|
| 🔴 Red Team | Fix | 3 (day-one inherited shared-technical-action state, closed with documentation + existing audit-trail monitoring; sales-forwarding misrepresentation risk, closed with an explicit CPA-access runbook step + strongest-non-goal framing; SOC 1/SOC 2 picker mistake, confirmed already addressed) | Closed |
| 🔵 Blue Team | Fix | 4 (crosswalk-check scope could be over-trusted, confirmed the manual checklist covers real tenant-state proof; alert-routing scope, confirmed consistent with repo precedent; three-way group-sharing drift had no check, closed with a plural-aware manual spot-check + KPI; Type II evidence-window gap, closed with a new KPI + manual checklist item) | Closed |
| 🎩 CISO | Pass | 0 | - |
| 🟦 Microsoft Product Owner | Fix | 6 (three-way script-reuse decision, confirmed correct; SOC 2 catalog-name accuracy and Microsoft's-own-attestation-vs-customer's-assessment distinction, confirmed and grounded via direct fetch; crosswalk honesty, confirmed correctly bounded; licensing/role accuracy, confirmed; Data Protection Baseline reasoning, confirmed still applies; Type I/Type II template handling, confirmed not fabricated) | Closed |

All Fix items from this round are resolved in the current state of `README.md`, `design.md`,
`deploy/`, and `validate/`. No Fail items were raised. This fragment meets the definition of done in
`AGENTS.md` §9.
