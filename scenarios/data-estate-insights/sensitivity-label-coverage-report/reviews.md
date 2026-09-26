# Four-Lens Review - Sensitivity-Label Coverage Report

Reviewed after the initial draft of `README.md`, `design.md`, `deploy/`, and `validate/`. One round of
findings below; all **Fix** items were applied to the scenario before this file was finalized (see
"Resolution" under each). No **Fail** items were raised.

---

## 🔴 Red Team

**Verdict: Fix (resolved)**

1. **A `0% labeled` reading is ambiguous between "genuinely unprotected data" and "this source type
   doesn't support Data Map sensitivity labeling at all," and the original draft didn't say so.**
   Microsoft's supported-source list for the Data Map label extension is a specific, named set (Azure
   Blob Storage, ADLS Gen1/Gen2, SQL Server, Azure SQL Database, Azure SQL Managed Instance, Amazon
   S3, Amazon RDS (preview), Power BI). A collection scoped to an unsupported source type - or, more
   subtly, a Microsoft 365 workload like Teams/SharePoint/Exchange, which uses an entirely different,
   native labeling mechanism, not this Data Map extension - will always read `0%` regardless of actual
   sensitivity, which an attacker doing reconnaissance on a target's published governance metrics
   could exploit as noise to hide a genuinely unlabeled, in-scope collection inside.
   - **Resolution:** `README.md` §11 now states this ambiguity explicitly as its own bullet, §8's KPI
     guidance tells an operator to confirm source-type support before treating a low
     `PercentLabeled` as a governance gap, and `design.md` §7 records the specific follow-up (a
     source-type-support check in the deploy/validate scripts) this build declined to build without
     independently re-verifying Microsoft's supported-source list is complete and current enough to
     hard-code as a validation rule.
2. **The trend-log CSV and breakdown JSON files are a curated map of an organization's *already-known-
   sensitive* data - arguably a higher-value reconnaissance target than the sibling
   `classification-coverage-report` scenario's own equivalent files**, since a label (e.g.
   "Highly Confidential") is a human-assigned sensitivity judgment, not just a pattern match.
   - **Resolution:** `README.md` §11 states this explicitly, cross-referencing the sibling scenario's
     own already-reviewed sensitivity-of-the-report-itself finding rather than treating it as new
     - same access-controlled-storage guidance applies, stated in this scenario's own terms.
3. **A compromised or over-broadly-scoped Data Reader credential could still read every label value in
   every collection it has access to** - correctly a Data Reader-level exposure inherited from the
   underlying role, not something this scenario makes worse, identical in kind to the sibling
   scenario's own Red Team finding.
   - **Resolution:** No new mitigation needed beyond what's already stated in §3's Data Reader row and
     §11 - confirmed as the same, already-accepted trade-off the sibling scenario documents, not a new
     gap this scenario introduces.

No remaining Fix/Fail after resolution.

---

## 🔵 Blue Team

**Verdict: Fix (resolved)**

1. **The source-type-support ambiguity (Red Team finding 1) is also an operability problem, not just a
   reconnaissance one: an on-call operator reacting to a coverage-drop alert has no fast way to tell
   "real regression" from "someone just onboarded a new, unsupported collection" without manually
   cross-checking Microsoft's supported-source list by hand.**
   - **Resolution:** `README.md` §8's KPI guidance now tells an operator to break `PercentLabeled` out
     by `-ObjectTypes`/`-CollectionId` and read the per-run breakdown JSON before escalating a blended
     estate-wide drop as a single incident - the same operability standard this repo's other
     reporting/validation scripts already meet.
2. **No guidance distinguished this scenario's alert-routing/incident-response posture from the
   sibling `classification-coverage-report` scenario's own, already-reviewed posture** - a reader of
   just this scenario shouldn't have to open the sibling's `reviews.md` to know the two severities
   (file-integrity `[FAIL]` vs. live-reconciliation `[WARN]`) work the same way here.
   - **Resolution:** `README.md` §8 reproduces the sibling scenario's incident-response runbook
     structure in full (not just by reference) so this scenario's own documentation is self-contained,
     consistent with this repo's per-scenario self-containment convention.
3. **Running both sibling scripts (`classification-coverage-report` and this scenario) against the
   same scheduler/storage location without an explicit collision check could, in principle, produce
   confusing output if an organization's own automation reused one variable name for both `-TrendLogPath`
   values.**
   - **Resolution:** `README.md` §5's scheduling guidance and `design.md` §5's naming-decision row now
     state explicitly that this scenario's file names (`sensitivity-label-coverage-trend.csv`,
     `<RunId>-<ObjectType>-labels.json`) are distinct from the sibling scenario's own, so an organization
     wiring up both scripts in the same pipeline doesn't need to invent disambiguating names
     themselves.

No remaining Fail. The Fixes bring this scenario's operational guidance to the same standard the
sibling `classification-coverage-report` scenario's own review already set, plus the two new
sensitivity-label-specific considerations above.

---

## 🎩 CISO

**Verdict: Fix (resolved)**

1. **The single most important finding of this review, from a funding/board-narrative standpoint: a
   high `PercentLabeled` number must never be presented as "this data is protected."** Microsoft's own
   FAQ for the Data Map label extension states plainly that these labels are metadata-only - "don't
   modify your files and databases in any way" - with no encryption, no content marking, and no DLP
   enforcement available through Data Map. A CISO who funds this scenario expecting it to demonstrate
   *protection* posture, rather than *awareness* posture, would be building a compliance narrative on a
   false premise. This is a materially different risk than anything the sibling
   `classification-coverage-report` scenario's own review needed to flag, because "classified" doesn't
   carry the same "therefore protected" connotation that "labeled" does in ordinary usage.
   - **Resolution:** `README.md` §2 now opens with an explicit callout stating this distinction before
     any KPI is described, and §11 restates it as a limitation with a pointer to this repo's DLP/
     Information Protection scenarios for anyone who actually needs enforced-protection evidence.
     `design.md` §1 records the same distinction as a fifth design consideration.
2. **The licensing story is a genuine, easy-to-miss gate this scenario's §10 correctly surfaces**: the
   upstream "extend sensitivity labels to Data Map" capability requires its own Microsoft 365 E5-tier
   (or equivalent) license, separate from whatever license justifies Data Map scanning itself - an organization
   evaluating this as a "just add it to the classification report" upsell needs to know this isn't
   free to add.
3. **Privilege story remains a genuine improvement over the native path**, identical reasoning to the
   sibling scenario: Data Reader-only vs. the native report's Data-Curator-only (or Data-health-reader-
   gated view/Data-Curator-gated export) requirement.
4. **Change-management impact: none.** No M365 control, DLP policy, sensitivity label, or user-facing
   behavior is touched - a pure read/report layer, identical to the sibling scenario.
5. **Would I fund this, after the Fix above?** Yes, conditional on the metadata-vs-protection
   distinction actually reaching whoever consumes the report's output (board, GRC tool, auditor) - the
   fix makes that distinction explicit in the artifact itself rather than leaving it to be discovered
   the hard way during an audit.

No remaining Fail after resolution.

---

## 🟦 Microsoft Product Owner

**Verdict: Fix (resolved)**

1. **Strong, primarily-sourced grounding for the central design claim, mirroring the sibling
   scenario's own citation discipline.** The "no documented has-any-label filter" claim is grounded in
   a direct fetch of the Discovery - Query REST reference for this build, which confirms the
   operation's only worked exact-value filter example (`Discovery_Query_Classification`) is for
   `classification`, with no `label` equivalent - the right citation hierarchy (primary source, not
   inferred from the sibling scenario's own already-established claim about `classification`).
2. **The `label` field/facet claims are independently confirmed, not assumed from the `classification`
   field's own confirmed shape.** The REST reference's `Definitions` section explicitly documents
   `label` as `string[]` ("The labels of the asset") and lists `label` as one of exactly four
   documented facets (`assetType`, `classification`, `contactId`, `label`) - this scenario does not
   merely assume symmetry with `classification`, it confirms it.
3. **One citation-precision gap in the initial draft:** the native report's name was initially
   paraphrased loosely from `PROGRESS.md`'s own follow-up note ("Labeling insights") rather than
   Microsoft's actual current report name.
   - **Resolution:** Every reference to the native report throughout `README.md`/`design.md` now uses
     Microsoft's confirmed current name, **Classic sensitivity labels** report, sourced directly from
     the `unified-catalog-reports-classic-sensitivity-labels` page fetched for this build (reference
     1) - not the looser paraphrase.
4. **Preview-status prominence correctly elevated**, consistent with this repo's established pattern
   (the Data Quality `rules-and-scorecards` scenario's own Product Owner fix for exactly this issue):
   the Public Preview callout sits at the top of `README.md`, before §1, not buried in §11.
5. **No deprecated cmdlets/endpoints used**, and the dual-endpoint parameterization reuses the
   already-established precedent from the sibling scenario rather than re-deriving it independently.
6. **Reinventing-a-native-capability check:** this scenario does not attempt to rebuild the native
   Insights application's UI or drill-down browsing - it fills the same named export/schedule/history/
   least-privilege gap the sibling scenario already fills for classifications, applied to labels,
   which is the correct scope for a companion automation.

No remaining Fail after resolution.

---

## Summary

| Lens | Initial verdict | Findings | Resolution |
|---|---|---|---|
| 🔴 Red Team | Fix | 3 (1 new source-type-ambiguity finding closed via README/design additions; 2 confirmed as already-accepted, sibling-scenario-equivalent trade-offs, stated in this scenario's own terms) | Closed |
| 🔵 Blue Team | Fix | 3 (all closed via README additions - operability guidance, self-contained runbook, file-naming clarity) | Closed |
| 🎩 CISO | Fix | 1 major finding (metadata-vs-protection distinction) closed via README/design additions; 4 confirmed correct | Closed |
| 🟦 Microsoft Product Owner | Fix | 1 closed (native report name precision); 5 confirmed correct | Closed |

All Fix items from this round are resolved in the current state of `README.md`, `design.md`, and
`rollback.md`. No Fail items were raised. This fragment meets the definition of done in `AGENTS.md`
§9.
