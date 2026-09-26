# Four-Lens Review - Compliance Manager: PCI DSS v4.0 Assessment

Reviewed after the initial draft of `README.md`, `design.md`, `deploy/`, and `validate/`. One round
of findings below; all **Fix** items were applied to the scenario before this file was finalized
(see "Resolution" under each). No **Fail** items were raised.

---

## 🔴 Red Team

**Verdict: Fix (resolved)**

1. **A freshly-created PCI DSS assessment inherits the tenant's existing shared-technical-action
   state on day one, invisibly.** `design.md` §6 correctly documents that **technical** improvement
   actions sync "across all groups" tenant-wide - but the original draft didn't follow that fact to
   its conclusion: it means this brand-new assessment's very first compliance score is not computed
   fresh. It's computed against whatever automation-trust settings, prior manual overrides, and
   "Out of scope" markings already exist on shared technical actions from **any** other Compliance
   Manager assessment already in the tenant - including one nobody remembers creating, or one whose
   automated testing was quietly narrowed months ago for unrelated reasons. A red-teamer (or a
   careless admin) who previously weakened a shared technical action's testing scope in an
   unrelated, forgotten assessment gets that weakening "for free" here, with no warning.
   - **Resolution:** Added an explicit step to `README.md` §5 (step 3) framing deployment order as
     mattering "regardless of which group [the assessment] ends up in," and added a KPI-adjacent
     caution to `README.md` §8 clarifying that a day-one score is not a from-scratch baseline. Not
     fixable by this scenario's tooling alone - no read API exists to enumerate every other
     assessment's shared technical actions and their current automation-trust state (`design.md`
     §2) - so the mitigation is documentation plus the existing `ComplianceManagerAutomationChange`
     monitoring in the reused audit-trail script, which would have caught the hypothetical prior
     weakening event if it happened after this scenario's audit window began.
2. **A red-teamer (or a well-meaning but overzealous salesperson) could present this assessment's
   score as PCI DSS "compliance" or "certification" to a customer or acquirer.** This is the single
   highest-consequence misuse this scenario could enable, given PCI DSS's contractual (not just
   regulatory) stakes.
   - **Resolution:** Confirmed already correctly and prominently scoped in the original draft -
     `README.md` §2 states the SAQ/RoC distinction in its second paragraph (not buried in §11), and
     `design.md` §8 lists it as a non-goal "in the strongest possible sense." No further change
     needed; flagging here because this finding's *absence* of a needed fix is itself worth
     recording; a weaker initial framing would have been a Fail, not a Fix.
3. **Accidentally activating both "PCI DSS v3.2.1" and "PCI DSS v4.0"** consumes two premium-template
   slots for what looks, at a glance in the regulation picker, like the same regulation - an easy
   mistake under time pressure, not really a red-team scenario but a genuine misconfiguration risk
   with real license cost.
   - **Resolution:** Confirmed already addressed: `README.md` §5 step 5 calls this out explicitly at
     the exact moment (the regulation picker) it would happen, and §10/§11 cover the cost and
     compliance-catalog-accuracy angles respectively. No further change.

No remaining Fix/Fail after resolution.

---

## 🔵 Blue Team

**Verdict: Fix (resolved)**

1. **The new crosswalk-manifest path-existence check in `validate/
   Test-ComplianceManagerAuditTrail.ps1` could be misread as proof the referenced controls are
   actually deployed in the tenant.** It only confirms the referenced `scenarios/...` paths exist in
   *this repository* - a repo-hygiene check, not a tenant-state check. A reviewer skimming a
   green validate-script run could over-trust the crosswalk's real-world accuracy.
   - **Resolution:** The script's own `.DESCRIPTION` already worded this precisely ("catching a
     stale cross-link before an organization follows it into a 404") but the check's console output header
     didn't repeat that scoping. Left as-is after review - the `.DESCRIPTION` is the authoritative
     scope statement per this library's existing precedent (e.g. `assess-against-iso27001`'s
     manual-checklist framing), and the manual checklist item in this scenario's own validate script
     ("spot-check that at least some actions show a 'Passed'... status sourced from built-in
     automation") is the actual tenant-state proof point - the automated check was never meant to
     replace it, and the checklist item already exists specifically for that purpose. No code
     change; confirming the separation of concerns is correct, not adding a redundant disclaimer.
2. **Alert routing for the automation-trust-change warning** - same, already-accepted scope
   boundary as `assess-against-iso27001/reviews.md` finding 2. No change.
3. **Group-sharing drift has no automated detection** - if the group-sharing behavior silently
   stops working (e.g. because a well-meaning admin recreates one assessment in a new group), there
   is no script that would notice.
   - **Resolution:** Added the "Group-sharing functional test" to `README.md` §7 (item 4) and the
     "Group-sharing drift" KPI to `README.md` §8, both instructing a periodic manual spot-check.
     Not automatable - Compliance Manager has no read API to query an improvement action's
     synchronized status across assessments (`design.md` §2) - so a documented manual check is the
     correct-for-this-product-surface mitigation, consistent with this scenario's other manual
     checklist items.

No remaining Fail after resolution.

---

## 🎩 CISO

**Verdict: Pass**

- **Risk reduction vs. cost:** correctly scoped as a governance/evidence control, not a technical
  one (`README.md` §2) - same honest framing as `assess-against-iso27001`. The stakes are higher
  here (PCI DSS carries direct financial consequences - fines, increased transaction fees, and in
  the worst case loss of card-processing privileges - that ISO 27001 non-conformance typically
  doesn't carry as directly), which makes the SAQ/RoC-substitute non-goal (§8) the single most
  important thing this scenario gets right, not a nice-to-have caveat.
- **Board-level narrative:** "we track our PCI DSS posture in the same governance platform as our
  other frameworks, we know exactly what does and doesn't share between them, and we are explicit
  with our QSA/ISA that this is an internal tracking tool, not our SAQ or RoC" is a defensible,
  audit-committee-ready narrative that doesn't overclaim.
- **Compliance mapping:** the control crosswalk (`design.md` §7) gives a CISO a one-page answer to
  "which of our Microsoft 365 investments count toward PCI DSS," including the honest admission that
  2 of 6 goals aren't covered by this library at all - useful precisely because it doesn't inflate
  coverage.
- **Change-management impact:** the recommended deployment order (technical controls first, then
  the assessment) is the same sequencing call `assess-against-iso27001/reviews.md`'s CISO lens
  already endorsed, for the same reason.
- **Would I fund this?** Yes - same reasoning as the ISO 27001 scenario's CISO lens: the
  premium-template license is a near-certain cost regardless, and this scenario's incremental cost
  (largely zero, given the reused audit-trail script) is negligible against the value of correctly
  scoping what the resulting score does and doesn't prove to an auditor or acquirer.

No Fix/Fail items from this lens.

---

## 🟦 Microsoft Product Owner

**Verdict: Fix (resolved)**

1. **Is reusing (not duplicating) `assess-against-iso27001`'s audit-trail script a legitimate
   engineering decision, or does it make this scenario's `deploy/` folder look incomplete/lazy
   relative to `AGENTS.md` §9's checklist?**
   - **Resolution:** `design.md` §2 states the reasoning directly: the 3 monitored operations are
     tenant-wide, not assessment-scoped, so a byte-for-byte second copy would be pure duplication.
     The working, idempotent, parameterized, dry-run-capable code required by `AGENTS.md` §9 exists
     and is shipped in this folder (the file is physically present, per this scenario's own
     independent-deployability requirement) - it's reused rather than reinvented, which is the
     correct call given the constraint, not a shortfall.
2. **Is "PCI DSS v4.0" (not "v4.0.1") the correct current template name to reference?**
   Microsoft's certifications for its own services (Azure, OneDrive, SharePoint) cite "v4.0.1"
   specifically, while Compliance Manager's regulation-catalog link text says "PCI DSS v4.0."
   - **Resolution:** Verified directly against the `compliance-manager-regulations-list` premium
     regulations catalog during this build - the catalog entry's own display name is "PCI DSS
     v4.0," distinct from "PCI DSS v3.2.1." This scenario references the template by its actual
     catalog name rather than substituting the .0.1 revision number Microsoft uses elsewhere for
     its own infrastructure certification. `README.md` §11 flags that Microsoft's own PCI DSS
     attestation for Azure/O365 cites v4.0.1 specifically, so a reader isn't confused by the two
     numbers appearing in different contexts within this same scenario's references.
3. **Is the control crosswalk correctly and honestly bounded, or does it risk reading as this
   scenario claiming to know Microsoft's real per-action PCI mapping?**
   - **Resolution:** `deploy/policy/pci-dss-assessment-manifest.json`'s `controlCrosswalk._comment`
     and `design.md` §7 both state explicitly, in the first sentence, that this is this library's
     own correlation and not a reproduction of Microsoft's internal mapping - matching the identical
     caution `assess-against-iso27001/design.md` §6 already established as this library's pattern
     for this exact class of claim.
4. **Licensing and role-name accuracy** - checked against `docs/licensing-matrix.md`'s existing
   Compliance Manager row and `assess-against-iso27001`'s already-reviewed role table; both are
   reused verbatim here since Compliance Manager's RBAC and premium-template licensing model are
   tenant-wide constructs, not regulation-specific ones. Confirmed consistent.
5. **Is building a dedicated assessment instead of extending the Data Protection Baseline correct
   here too, or does PCI DSS's narrower, more technical scope change that answer?**
   - **Resolution:** No - the baseline's multi-framework blending problem (`design.md` §5) applies
     identically regardless of which specific premium regulation is being pursued. Confirmed
     consistent with `assess-against-iso27001/design.md` §5's reasoning, not a copy-paste that
     happens to also be wrong here.

No remaining Fail after resolution.

---

## Summary

| Lens | Initial verdict | Findings | Resolution |
|---|---|---|---|
| 🔴 Red Team | Fix | 3 (day-one inherited shared-technical-action state, closed with documentation + existing audit-trail monitoring; SAQ/RoC misrepresentation risk, confirmed already correctly scoped; dual-template license waste, confirmed already addressed) | Closed |
| 🔵 Blue Team | Fix | 3 (crosswalk-check scope could be over-trusted, confirmed the manual checklist already covers the real tenant-state proof; alert-routing scope, confirmed consistent with existing repo precedent; group-sharing drift had no check, closed with a new manual spot-check + KPI) | Closed |
| 🎩 CISO | Pass | 0 | - |
| 🟦 Microsoft Product Owner | Fix | 5 (script-reuse-not-duplication decision, confirmed correct; v4.0 vs v4.0.1 naming, confirmed and clarified; crosswalk honesty, confirmed correctly bounded; licensing/role accuracy, confirmed; Data Protection Baseline reasoning, confirmed still applies) | Closed |

All Fix items from this round are resolved in the current state of `README.md`, `design.md`,
`deploy/`, and `validate/`. No Fail items were raised. This fragment meets the definition of done
in `AGENTS.md` §9.
