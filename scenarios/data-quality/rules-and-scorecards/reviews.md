# Four-Lens Review - Data Quality Rules and Scorecards for a Governed Data Asset

Reviewed after the initial draft of `README.md`, `design.md`, `deploy/`, and `validate/`. One round
of findings below; all **Fix** items were applied to the scenario before this file was finalized
(see "Resolution" under each). No **Fail** items were raised.

---

## 🔴 Red Team

**Verdict: Fix (resolved)**

1. **Data Quality Steward is a governance-domain-wide role, not an asset-scoped one.** The original
   draft's prerequisites table listed the role without noting its actual blast radius: a service
   principal holding **Data Quality Steward** on "Customer Experience" can create, edit, or delete
   Data Quality rules on **any** asset in **any** data product inside that entire domain, not just
   the single "Customer" asset this scenario targets. No narrower, asset-scoped role is documented
   for this action by Microsoft.
   - **Resolution:** `README.md` §3 now states this explicitly against the Data Quality Steward row,
     with a pointer to `docs/rbac-model.md` §9 for periodic role-membership review - the same
     "document the trust boundary rather than pretend it's fixable" treatment this repo already gave
     the SAMI `db_datareader` grant in `scenarios/data-map/scan-azure-sql-and-classify/`.
2. **"Quality theater" risk: rules can be silently left in `Draft` status indefinitely.** The script
   deliberately supports `-RuleStatus Draft` for a review-before-activation workflow (a legitimate,
   intentional feature), but the original draft had no guidance on catching a rule that was *meant*
   to be temporarily Draft and never got flipped back to Active - which looks, at a glance in the
   portal, like a fully configured control that in fact contributes nothing to the score.
   - **Resolution:** `README.md` §8 now explicitly instructs wiring
     `validate/Test-DataQualityRulesAndScorecard.ps1 -ExpectedRuleStatus Active` into a recurring
     pipeline check as a go-live requirement, not an optional nicety (this also resolves a related
     Blue Team finding below).
3. **The example custom email-format rule is weak and could be mistaken for a compliance-grade
   validator.** The regex is a basic shape check, not RFC 5322-complete, and was only flagged inline
   in the JSON definition file's own `description` field - easy to miss for a reader who goes
   straight to the README's configuration reference.
   - **Resolution:** `README.md` §11 now carries an explicit Known Limitations bullet stating this
     directly, including that passing this scenario's validation proves the rule *infrastructure*
     works, not that the rule *content* is production-ready.
4. **Rollback's `-RemoveRules` doesn't purge score history**, so a stale historical score could in
   principle be referenced by a report or dashboard after the rules that produced it are gone.
   - **Resolution:** Not changed - already correctly documented in `rollback.md`'s "What rollback
     does **not** undo" section, with a pointer to the portal's explicit **Delete data quality data**
     action for anyone who needs that separately. Confirmed this is adequate; no silent gap.

No remaining Fix/Fail after resolution.

---

## 🔵 Blue Team

**Verdict: Fix (resolved)**

1. **No mandatory-alerting guidance.** The original draft documented alert configuration as a portal
   step and moved on, without stating that skipping it leaves score regressions with **zero**
   automatic detection - a materially different risk posture from this repo's DLP/IRM scenarios,
   which all have a native alert/incident mechanism the automation itself can verify is wired up.
   - **Resolution:** `README.md` §8 now states plainly that this scenario should not be considered
     "monitored" until at least one portal alert is configured, and additionally recommends a
     periodic `validate/` pipeline run as a second detection layer independent of the alert channel
     - this also closes the Red Team's Draft-status-drift finding above.
2. **Validate script's asset-score check had an ambiguous failure mode.** The score-lookup REST call
   is unconfirmed/preview surface; if it failed for a reason unrelated to "no scan has run yet" (most
   plausibly, a wrong or stale `businessDomainId`/`dataProductId`/`dataAssetId` in the definition
   file), the original catch block's generic warning read identically to the benign "just hasn't run
   yet" case - masking a real configuration error behind a message that sounds like "everything's
   fine, just early."
   - **Resolution:** `validate/Test-DataQualityRulesAndScorecard.ps1`'s catch block now explicitly
     names the "wrong/stale IDs" possibility and tells the operator to double-check those three GUIDs
     against the portal, rather than defaulting to the more comfortable "not run yet" explanation.
3. **No SIEM/Sentinel integration mentioned.** Correctly out of scope, consistent with this repo's
   established pattern (Data Map, Adaptive Protection) of not overclaiming an alert-stream
   integration a given Purview surface doesn't natively provide - Data Quality has no comparable
   event stream to route.
   - **Resolution:** No change needed; confirmed as correctly scoped rather than a gap.

No remaining Fail. The two Fix items bring this scenario's operability guidance to the same bar as
this repo's other poll-based (not alert-native) scenarios, adapted to Data Quality's specific
"scan succeeded but score dropped" failure mode, which is functionally distinct from "scan failed
outright" and needed its own runbook branch (already present in the original draft's §8 Incident-
response runbook, confirmed correct on review).

---

## 🎩 CISO

**Verdict: Fix (resolved)**

1. **Funding conditionality wasn't explicit.** The original draft's cost/licensing section was sound
   (PAYG/DGPU metering, budget-alert recommendation, pilot-first framing) but the review surfaced that
   "would I fund this" implicitly depended on two things not yet true by default: alert configuration
   (Blue Team finding 1) and the portal-only DQ connection setup (§11 VERIFY) both being completed
   before wider rollout, not left as someday-items.
   - **Resolution:** Addressed structurally rather than by adding a new section - the Blue Team fix
     above reframes alert configuration as a go-live gate in `README.md` §8, and §5's step-by-step
     portal path already sequences the connection setup as step 3, before rules/scheduling. No
     separate CISO-only callout was needed once those two fixes landed; re-reviewed and confirmed the
     resulting document reads as "fundable, with these two gates cleared first," not "fundable,
     someday."
2. **Risk-reduction narrative:** clear and specific - a governance-domain data quality score tied to
   BCBS 239 / GDPR Art. 5(1)(d) / SOX data-integrity narratives is a materially stronger position than
   "we believe the customer data is fine," and the scenario is honest about what it does and doesn't
   prove (§7 validation's negative-test step is genuine evidence, not a demo trick).
3. **Board-level narrative:** "we can produce, on demand, a dated, rule-level data quality score for
   our customer master data, computed the same way every time" is defensible and auditable - a
   materially different claim from an annual manual data-quality audit.
4. **Change-management impact:** low - deploying rules and a one-time schedule doesn't touch live
   M365 controls or user-facing behavior, matching this repo's Data Map scenario's assessment. The
   staged rollback (schedule-only → schedule + rules) gives a proportionate off-ramp.
5. **Would I fund this?** Yes, conditioned on the two go-live gates above (alert configuration, DQ
   connection setup) being treated as required steps rather than optional - which the current
   document now makes explicit rather than implicit.

No remaining Fix/Fail after resolution.

---

## 🟦 Microsoft Product Owner

**Verdict: Fix (resolved)**

1. **Public Preview status wasn't prominent enough in the original draft.** The scenario correctly
   disclosed "Public Preview" in §3's footnote, §6, and §11, but a reader skimming only the §1
   scenario summary - the first thing anyone reads - would not learn this is a preview surface until
   several sections later. This repo's own precedent
   (`scenarios/unified-catalog/curate-business-glossary/reviews.md`, Product Owner Fix round)
   explicitly called for sharpening preview-surface prominence when this same gap appeared there.
   - **Resolution:** `README.md` §1 now opens with an explicit callout block stating the Public
     Preview status, its GA-only API coverage boundary, and a "pilot before compliance commitment"
     recommendation, before any other content.
2. **Rule type coverage matches Microsoft's own documented rule catalog correctly.** Verified the
   five deployed rule types (`NotNull`, `Unique`, `TypeMatch`, `Duplicate`, `CustomTruth`) and their
   dimension tags against Microsoft's own "Create data quality rules" article and the REST reference's
   worked examples - no invented type strings, and the deliberate omission of `Freshness` (unsupported
   for Azure SQL, this scenario's target source type) is correctly grounded and documented rather than
   silently dropped.
3. **No deprecated cmdlets/endpoints used.** The API version (`2026-01-12-preview`) was independently
   confirmed via direct fetch of Microsoft's own REST operation-group index at build time; this is
   Microsoft's current Public Preview surface for this feature, not a stale or superseded one.
4. **Licensing citation accuracy** - checked against `docs/licensing-matrix.md`: Data Quality is
   correctly described as PAYG-only, DGPU-metered, matching the cross-cutting matrix's existing
   "Data Quality / Health" row exactly (Basic/Standard/Advanced SKUs). No conflation with the
   per-user or Unified Catalog governed-assets/day meters.
5. **Reinventing-a-native-capability check:** this scenario doesn't build a parallel data-quality
   engine - it's a direct, idiomatic REST wrapper around the Data Quality API Microsoft ships
   specifically for this purpose, deliberately declining to guess at unconfirmed shapes (custom scan
   connection provisioning, recurring trigger types, alert endpoints) rather than reinventing them
   with fabricated request bodies.

No remaining Fail after resolution.

---

## Summary

| Lens | Initial verdict | Findings | Resolution |
|---|---|---|---|
| 🔴 Red Team | Fix | 4 (3 closed via documentation/guidance additions, 1 confirmed already adequately documented) | Closed |
| 🔵 Blue Team | Fix | 3 (2 closed via README/validate-script guidance, 1 confirmed correctly scoped) | Closed |
| 🎩 CISO | Fix | 1 closed (funding conditionality made explicit via the Blue Team fix); Pass on all other dimensions | Closed |
| 🟦 Microsoft Product Owner | Fix | 1 closed (Public Preview prominence sharpened); 4 confirmed correct | Closed |

All Fix items from this round are resolved in the current state of `README.md`, `design.md`,
`deploy/New-DataQualityRulesAndSchedule.ps1`, `deploy/Remove-DataQualityRulesAndSchedule.ps1`, and
`validate/Test-DataQualityRulesAndScorecard.ps1`. No Fail items were raised. This fragment meets the
definition of done in `AGENTS.md` §9.
