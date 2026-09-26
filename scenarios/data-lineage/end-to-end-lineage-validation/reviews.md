# Four-Lens Review - End-to-End Customer Data Lineage

Reviewed after the initial draft of `README.md`, `design.md`, `deploy/`, and `validate/`. One
round of findings below; all **Fix** items were applied to the scenario before this file was
finalized (see "Resolution" under each). No **Fail** items were raised.

---

## 🔴 Red Team

**Verdict: Fix (resolved)**

1. **Data Curator is a collection-wide role, not an asset-scoped one.** The original draft's
   prerequisites table listed the role without noting its actual blast radius: a service principal
   holding Data Curator on the collection containing `customerdb.dbo.Customers` and
   `analyticsdb.dbo.CustomerRiskSummary` can create, edit, or delete entities and relationships on
   **any** asset in that entire collection, not just the two this scenario targets. No narrower,
   asset-scoped or relationship-scoped role is documented for this action.
   - **Resolution:** `README.md` §3 now states this explicitly against the Data Curator row, with
     guidance to review collection role membership periodically - the same "document the trust
     boundary rather than pretend it's fixable" treatment this repo already gave the Data Quality
     Steward role in `scenarios/data-quality/rules-and-scorecards/reviews.md`.
2. **Custom lineage is a trust claim, not a verified fact, and the original draft didn't say so
   anywhere a reader evaluating this as compliance evidence would see it.** Purview does not check
   a `direct_lineage_dataset_dataset` relationship against what the referenced systems actually do
   - it accepts whatever the caller asserts. A compromised or careless automation identity (or
   engineer) with Data Curator could assert a false lineage claim (hiding a real flow by never
   creating it, or fabricating a flow that doesn't exist) with nothing in Purview to catch it. This
   is a materially different integrity posture than natively-captured lineage (which Purview
   observes ADF/Synapse/Power BI actually doing), and this repo's own §2 business driver leans on
   lineage as audit/compliance evidence - a reader could reasonably use this scenario's output to
   overstate the strength of that evidence.
   - **Resolution:** `README.md` §11 now opens with an explicit "Custom lineage is asserted, not
     verified" bullet, instructing that any audit/compliance narrative built on this graph must
     distinguish natively-captured edges from custom-asserted ones rather than presenting both with
     equal evidentiary weight.
3. **The columnMapping attribute is unvalidated free text** - Purview does not check that the
   column names referenced actually exist on either table, so a typo or stale mapping would be
   silently accepted. Correctly scoped as a non-goal already (`design.md` §7's schema-drift note)
   rather than a gap this scenario claims to close; confirmed adequate on review, no change needed.

No remaining Fix/Fail after resolution.

---

## 🔵 Blue Team

**Verdict: Fix (resolved)**

1. **The "not present at all" validation failure had an ambiguous cause the original guidance
   didn't fully name.** The script's hint for a missing downstream asset mentioned a deleted link
   or a stale qualifiedName, but not that `-MaxDepth` being too shallow produces the exact same
   symptom - an operator could spend time investigating a "broken lineage" incident that's actually
   just a depth parameter set too low for a longer real-world chain than the shipped one-hop
   example.
   - **Resolution:** Both `validate/Test-EndToEndLineage.ps1`'s inline hint and `README.md` §8's
     incident-response runbook now name `-MaxDepth` explicitly as a possible cause for this specific
     failure mode, and note (correctly) that the *other* check - "present but not connected" - is
     unambiguous and cannot be explained by depth, since presence in the graph already required
     being within the requested depth.
2. **No mandatory-alerting caveat was as prominent as this repo's precedent sets.** Lineage has no
   native alert mechanism (correctly documented), but the original draft's phrasing buried this as
   a passing remark rather than stating plainly that the recurring validate run **is** the entire
   detection mechanism - matching the bar `scenarios/data-quality/rules-and-scorecards/README.md`
   §8 set for its own no-native-alert case.
   - **Resolution:** `README.md` §8's Alert routing paragraph was already written to this bar in
     the initial draft (confirmed on review, no change needed) - re-verified against the Data
     Quality scenario's phrasing side-by-side and found equivalent in prominence and clarity.
3. **No SIEM/Sentinel integration mentioned.** Correctly out of scope - lineage has no event stream
   to route, consistent with this repo's established pattern for surfaces without one.
   - **Resolution:** No change needed; confirmed as correctly scoped rather than a gap.
4. **The column-mapping check ("Check 2") silently assumes every custom link's upstream is the
   origin asset.** Correct for the shipped single-hop example, but the script's own inline
   documentation didn't say so - a reader adapting this scenario to a longer, multi-hop chain
   could add a `customLineageLinks` entry whose upstream isn't the origin and get a silently wrong
   (always-`[FAIL]`) result for that link, without any indication the check itself doesn't
   generalize yet.
   - **Resolution:** `validate/Test-EndToEndLineage.ps1` now carries an explicit scope-note comment
     immediately above Check 2, and `design.md` §7 records the same limitation as a tracked
     follow-up rather than a silent gap.

No remaining Fail. The two substantive Fixes (the ambiguous-failure-mode guidance) brings this
scenario's troubleshooting guidance to the same standard already set by this repo's Data Quality
and Data Map scenarios for their own validate scripts.

---

## 🎩 CISO

**Verdict: Pass**

1. **Risk-reduction narrative is specific and honest**, especially after the Red Team fix above:
   "we can prove this specific data flow is connected end-to-end, and we distinguish what Purview
   observed from what we asserted" is a defensible, auditable claim - materially more useful to a
   risk committee than an unqualified "our lineage is complete."
2. **Cost is negligible and the funding decision is simple**: this is a thin REST layer over
   already-governed assets (no scanning, no new PAYG meter beyond what Data Map scanning already
   costs as a prerequisite) - §10's framing that the real cost is engineering time to keep
   `expectedDownstreamChain` current, not Azure spend, is accurate and sets the right expectation.
3. **Change-management impact: minimal.** No M365 control, DLP policy, or user-facing behavior is
   touched - purely a metadata assertion inside Purview. The rollback path is a single, reversible
   script run.
4. **Would I fund this?** Yes, without conditions beyond what's already built in: the Red Team
   fix's evidentiary-honesty note is the only thing that needed to be explicit before this
   scenario's output could be safely cited in a compliance narrative, and it now is.

No Fix/Fail raised.

---

## 🟦 Microsoft Product Owner

**Verdict: Fix (resolved)**

1. **Citation mix could be misread as resting on a deprecated feature.** Several of this
   scenario's citations point at articles titled "classic Data Catalog" (where Microsoft documents
   lineage concepts most thoroughly), which sit near "customer support mode" retirement notices for
   *other*, unrelated classic-portal features (Data Sharing lineage, Workflow) in the same
   documentation set. A reader skimming the reference list could wrongly conclude this scenario is
   built on something being retired.
   - **Resolution:** `README.md` §11 now carries an explicit bullet distinguishing "classic Data
     Catalog" (cited for concepts) from the Data Map/Atlas REST API this scenario actually calls
     (current, non-deprecated, and the same surface Unified Catalog's own Lineage tab reads from).
2. **All four REST operations directly confirmed against canonical reference pages, not
   corroborated indirectly.** Unlike several earlier scenarios in this repo (Data Map's Data
   Sources/Triggers, Data Quality's Alerts), every operation this scenario depends on - Relationship
   - Create, Relationship - Delete, Lineage - Get, Lineage - Get By Unique Attribute - was fetched
   directly from its own canonical REST reference page during this build, at a consistent, current
   API version (`2023-09-01`). This is a stronger grounding bar than this repo's average scenario
   and should be preserved as the standard where achievable.
3. **Relationship type selection is correct and honestly scoped.** `direct_lineage_dataset_dataset`
   is the right, minimal shape for "close a gap without modeling a Process asset" - confirmed
   against Microsoft's own worked example rather than the richer DataSet-Process-DataSet shape,
   which this scenario correctly declines to use given the unconfirmed custom-Process-entity
   creation body (`design.md` §7, tracked as a follow-up rather than guessed).
4. **No deprecated cmdlets/endpoints used**, and the dual-endpoint (`api.purview-service.microsoft.com`
   / `<account>.purview.azure.com`) parameterization is grounded more strongly than this repo's
   earlier precedent for the same pattern (an explicit Microsoft statement of both valid values for
   this exact path family, not an inference).
5. **Reinventing-a-native-capability check:** this scenario doesn't build a parallel lineage
   tracker - it's a direct, idiomatic use of the exact REST mechanism Microsoft documents for
   closing lineage gaps, plus a validation layer Microsoft doesn't provide out of the box but that
   doesn't compete with or duplicate any native Purview feature.

No remaining Fail after resolution.

---

## Summary

| Lens | Initial verdict | Findings | Resolution |
|---|---|---|---|
| 🔴 Red Team | Fix | 3 (2 closed via README additions, 1 confirmed already correctly scoped) | Closed |
| 🔵 Blue Team | Fix | 4 (2 closed via validate-script/README/design.md guidance, 2 confirmed already adequate/correctly scoped) | Closed |
| 🎩 CISO | Pass | - | - |
| 🟦 Microsoft Product Owner | Fix | 1 closed (citation clarity); 4 confirmed correct | Closed |

All Fix items from this round are resolved in the current state of `README.md`, `design.md`,
`deploy/New-CustomLineageRelationship.ps1`, `deploy/Remove-CustomLineageRelationship.ps1`, and
`validate/Test-EndToEndLineage.ps1`. No Fail items were raised. This fragment meets the definition
of done in `AGENTS.md` §9.

---

## Correction addendum (follow-up fragment)

**Blue Team finding 4 closed, not just disclosed.** The original round's Resolution for this
finding added a scope-note comment disclosing that Check 2 only worked for the shipped
single-hop example (upstream == origin asset); it did not generalize the check itself, and the
gap was tracked as a `PROGRESS.md` follow-up instead. This follow-up fragment closes it:
`validate/Test-EndToEndLineage.ps1`'s Check 2 now resolves each `customLineageLinks` entry's
relation edge against its own declared `upstreamQualifiedName` (via the same `guidEntityMap`
qualifiedName-matching pattern Check 1 already used, falling back to the already-known
`baseEntityGuid` only when the link's upstream genuinely is the origin asset), so a longer,
multi-hop definition file validates correctly without further script changes. No new REST
assumption was introduced - the fallback path keeps the shipped example's behavior identical to
before. `design.md` §7's non-goal bullet updated to record the generalization instead of the
now-resolved limitation.
