# Four-Lens Review — Auto-Label EU/UK Personal Data in SharePoint & OneDrive

Reviewed after the initial draft of `README.md`, `design.md`, `deploy/`, and `validate/`. One round
of findings below; all **Fix** items were applied to the scenario before this file was finalized
(see "Resolution" under each). No **Fail** items were raised. Several inherited findings from the
sibling scenario's own review (`auto-label-confidential-sharepoint/reviews.md`) are noted as
already-addressed-by-inheritance rather than re-litigated.

---

## 🔴 Red Team

**Verdict: Fix (resolved)**

1. **Checksum-strength variance across the EU national ID bundle creates an inconsistent
   detection floor.** The original draft presented the three default SITs as a uniform "EU/UK
   personal data" condition set without flagging that they don't carry equal detection
   confidence — this build's own grounding confirmed EU debit card number is fully checksummed,
   while several countries inside the EU national ID bundle (e.g. France National ID Card/CNI) are
   pattern-only with no checksum. A red-teamer targeting the weakest-covered country's format
   specifically (or, inversely, ordinary business content that happens to match a weak
   unchecksummed pattern) gets a materially less reliable detection outcome than the bundle name
   implies as a whole.
   - **Resolution:** Added an explicit "EU checksums vary by country" item to `README.md` §11 and
     an Operations §8 KPI recommending per-country match-distribution monitoring in Activity
     Explorer as the concrete mechanism for spotting this in practice, with a pointer to the
     per-country localization path (§6) as the mitigation.
2. **The starter-set/non-exhaustive framing needed to be explicit for this scenario too, not
   assumed inherited from the sibling.** Because this scenario's whole premise is "more
   jurisdiction-appropriate than the sibling," an early draft risked implying by omission that it
   *is* GDPR-complete coverage, repeating the sibling's own original mistake in a new form.
   - **Resolution:** `README.md` §2 explicitly states the three-SIT default is a representative
     starter set (identity + financial pair), not exhaustive GDPR personal-data coverage, with a
     direct pointer to `design.md` §8's non-goals (names, addresses, health data, biometric data
     all out of scope).
3. **"EU" bundle naming includes a non-EU country (UK), which is a real mislabeling risk in a
   buyer conversation, not just a technicality.** A CISO or compliance officer reading "EU national
   identification number" could reasonably assume EU-27 scope and be surprised, post-Brexit, that
   UK NINO detection is bundled in (or, conversely, assume UK isn't covered when it actually is).
   - **Resolution:** Added an explicit "EU as used by Microsoft's SIT naming does not track EU
     membership exactly" item to `README.md` §11, citing the UK entity's membership in the bundle
     directly from its own Microsoft Learn definition page.
4. **Inherited from the sibling scenario, not re-opened:** the manual-label-first bypass, the
   exclusion list as a permanent blind spot, and the scan-cadence lag as a detection gap
   (`auto-label-confidential-sharepoint/reviews.md`, Red Team findings 1–3) all apply identically
   here — this scenario shares the same override/exclusion/scan-cadence mechanism, unchanged. Not
   re-documented in this scenario's own `README.md` §11 beyond a summary cross-reference, to avoid
   two copies of the same residual-risk text drifting out of sync.

No remaining Fix/Fail after resolution.

---

## 🔵 Blue Team

**Verdict: Fix (resolved)**

1. **The validation script's per-SIT check assumed an unconfirmed property-casing shape.** The
   first draft of `validate/Test-EuPersonalDataAutoLabelPolicy.ps1` read
   `$Rule.ContentContainsSensitiveInformation | ForEach-Object { $_.name }` — reasonable given the
   documented *write* shape uses lowercase `name`, but this build could not confirm during
   grounding that `Get-AutoSensitivityLabelRule`'s *read-back* shape uses the same casing. If it
   doesn't, every per-SIT check would silently report `[FAIL]` regardless of actual policy
   correctness — a validation script that's wrong in the paranoid direction (false failure) is
   less dangerous than one that's wrong permissively, but it's still a real defect that would
   erode operator trust in the script on first use against a live tenant.
   - **Resolution:** `Test-SitCoverage` now checks for either `name` or `Name` via
     `PSObject.Properties` before reading the value, and the ambiguity itself is documented as a
     new VERIFY in `README.md` §11 rather than silently patched over.
2. **No KPI existed for detecting when the EU-wide bundle's breadth becomes a liability rather
   than a feature.** The original Operations section (§8) covered generic failure-count triage
   (inherited correctly from the sibling) but had nothing specific to this scenario's own design
   differentiator — the localization parameter.
   - **Resolution:** Added the "per-country match distribution" KPI to `README.md` §8, giving
     operators a concrete, Activity-Explorer-based signal for when to move from the default bundle
     to a narrower `-SensitiveInfoTypeName` list (§6), and a dedicated §7 test case (localization
     test) proving a narrowed list is actually enforced, not silently falling back to the full
     bundle.
3. **Alert routing and native observability are correctly inherited, not re-derived.** Confirmed
   this scenario has no DLP-style incident-report alerting, same as the sibling — the same
   Activity Explorer / Audit Search / Graph pull pattern applies unchanged. No new gap found here
   specific to the EU/UK SIT set.

No remaining Fail. The operational surface now includes an EU-scenario-specific KPI and test case,
not just an inherited copy of the sibling's own operations section.

---

## 🎩 CISO

**Verdict: Pass**

- **Risk reduction vs. cost:** this scenario directly closes a gap the CISO lens in the sibling
  scenario's own review implicitly relied on being closed eventually (`auto-label-confidential-
  sharepoint/reviews.md` CISO section already frames the sibling as "a starter configuration to
  extend against the org's actual data inventory and jurisdiction") — this is that extension,
  delivered as a real, deployable sibling scenario rather than a promise in a README.
- **Board-level narrative:** "for our EU/UK-regulated population, we classify personal data using
  Microsoft's own EU-region identifiers — not a U.S. substitute — and we can tune detection
  precision down to the specific member states we operate in" is a stronger, more specific
  narrative than the sibling's own U.S.-default framing, and it's now backed by a working
  `-SensitiveInfoTypeName` parameter, not just a README suggestion to "swap in the relevant
  regional SITs."
- **Change-management impact:** identical override/rollout model to the already-reviewed sibling
  scenario — no new change-management risk introduced by this scenario's SIT-set substitution.
- **Compliance mapping:** correctly framed against GDPR Article 32 as the primary driver (more
  directly defensible here than in the sibling, since the SITs genuinely match EU/UK identifier
  formats) and ISO/IEC 27001 Annex A.5.12/A.8.2 as the classification-discipline driver the default
  configuration satisfies as shipped — same honest two-tier framing the sibling scenario
  established, correctly not overclaimed here either (§2's explicit non-exhaustiveness note).
- **Would I fund this?** Yes — this is the direct, low-incremental-cost (§10: no additional
  licensing) completion of a gap this library's own prior review had already flagged and
  deliberately deferred rather than guessed at. Funding it now, grounded, is the right sequencing.

No Fix/Fail items from this lens.

---

## 🟦 Microsoft Product Owner

**Verdict: Fix (resolved)**

1. **The EU-wide bundle SIT names needed to be verified as real, selectable SIT objects — not
   just documentation groupings — before this scenario could ship.** The initial research pass
   found per-country entity definition pages and a page titled "EU national identification number"
   listing them, which is ambiguous on its own (is this a real selectable SIT, or just a doc
   index?). Shipping a scenario built on a condition that doesn't actually exist as a selectable
   SIT would be a significant grounding failure.
   - **Resolution:** Confirmed via an independent, authoritative source — Microsoft's own "these
     SITs can't be copied" exclusion list in the custom-SIT-authoring documentation, which names
     each EU-wide bundle SIT individually as an action target (you can't "copy" something that
     isn't a real, selectable SIT object). Cited directly in `design.md` §4 and `README.md` §12
     reference 6, rather than assumed from the grouping page alone.
2. **`Get-DlpSensitiveInformationType` is the correct, current cmdlet for name resolution — not
   fabricated.** Verified directly against its Microsoft Learn reference page, including a worked
   `-Identity "Credit Card Number"` example confirming exact-name lookup behavior, before building
   `Resolve-SensitiveInfoTypeNames` around it.
3. **Byte-exact SIT name capitalization could not be confirmed with the same confidence as the
   sibling scenario's SIT names, and this is disclosed rather than glossed over.** The sibling
   scenario's two SIT names both matched their citation exactly with no ambiguity; this scenario's
   EU names showed inconsistent casing across different Microsoft Learn pages during grounding.
   Rather than pick one casing and present it as authoritative, the deploy script defends against
   the uncertainty at runtime (name-resolution check against the live tenant catalog) and the
   uncertainty itself is flagged as an open VERIFY — the correct application of `AGENTS.md` §4 when
   grounding is incomplete, matching the standard the sibling scenario's own Product Owner review
   already held `RuleErrorAction` to.
4. **No deprecated cmdlets or invented parameters found.** `New-AutoSensitivityLabelPolicy`/
   `New-AutoSensitivityLabelRule`/`Set-AutoSensitivityLabelPolicy`/`Get-DlpSensitiveInformationType`
   are all current, and this scenario introduces no new parameter beyond what the sibling scenario
   already uses plus the SIT-name array (a standard `-ContentContainsSensitiveInformation`
   condition list, just sourced from a script parameter instead of a hard-coded literal).
5. **Licensing citation accuracy** — no change from the sibling scenario's entitlement
   requirement; confirmed no separate or additional licensing applies to EU-region SITs versus
   U.S.-region SITs (both are part of the same built-in SIT catalog under the same entitlement).

No remaining Fail after resolution.

---

## Summary

| Lens | Initial verdict | Findings | Resolution |
|---|---|---|---|
| 🔴 Red Team | Fix | 4 (3 closed with doc/design edits, 1 confirmed correctly inherited without re-opening) | Closed |
| 🔵 Blue Team | Fix | 3 (2 closed with a script fix + doc/KPI additions, 1 confirmed correctly inherited) | Closed |
| 🎩 CISO | Pass | 0 (benefited directly from this scenario closing the sibling review's own deferred gap) | — |
| 🟦 Microsoft Product Owner | Fix | 5 (3 closed by independent grounding/citation, 2 confirmed correct/deliberate) | Closed |

All Fix items from this round are resolved in the current state of `README.md`, `design.md`,
`deploy/New-EuPersonalDataAutoLabelPolicy.ps1`, and
`validate/Test-EuPersonalDataAutoLabelPolicy.ps1`. No Fail items were raised. This fragment meets
the definition of done in `AGENTS.md` §9.

---

## Review round 2 — 2026-09-09 — opt-in travel-document bundle (`-IncludeTravelDocumentSits`)

Scope: the `PROGRESS.md` follow-up asking for `EU passport number` and `EU driver's license
number` as an opt-in bundle (not a new default). Reviewed after adding the
`-IncludeTravelDocumentSits` switch to `deploy/New-EuPersonalDataAutoLabelPolicy.ps1` and
`validate/Test-EuPersonalDataAutoLabelPolicy.ps1`, and the supporting `README.md`/`design.md`
updates.

### 🔴 Red Team

**Verdict: Fix (resolved)**

1. **The "EU passport number" bundle's U.K. coverage is not what a buyer would assume from the
   name.** This round's grounding pass (fetching the bundle's own Microsoft Learn index page
   directly) found no standalone U.K. passport entity — U.K. coverage exists only inside a single
   combined "U.S./U.K. passport number" entity. A buyer who enables this switch specifically for
   U.K. travel-document coverage gets U.S. passport-number matching bundled in with no way to
   disable it independently — a real scope-creep and false-positive-surface risk that the original
   "just flip on the opt-in bundle" framing would have hidden.
   - **Resolution:** Documented prominently in the `.PARAMETER IncludeTravelDocumentSits` doc
     block (with a `Write-Host` runtime notice on every use), `design.md` §4, and `README.md` §6
     and §11 — not buried in a single footnote.
2. **The three EU-wide bundles this scenario can reference have inconsistent member-state
   coverage**, which could otherwise let an operator assume "EU-wide" means the same 26–28
   countries across all of them.
   - **Resolution:** Full per-bundle membership table added to `design.md` §4 (fetched directly
     from each bundle's own index page, not inferred), cross-referenced from `README.md` §11.

No remaining Fix/Fail after resolution.

### 🔵 Blue Team

**Verdict: Pass**

- The validate script's new `-IncludeTravelDocumentSits` switch mirrors the deploy script's
  parameter name and behavior exactly (append, don't replace), so an operator checking a
  bundle-enabled deployment doesn't have to reconstruct the expanded SIT list by hand — the same
  operability principle the base scenario's `-SensitiveInfoTypeName` validation already follows.
- Added README.md §7 test case 8 gives operators a concrete way to observe the U.S./U.K. merge
  behavior in practice (upload a test U.S. or U.K. passport number, confirm both match), rather
  than leaving it as a documentation-only claim.
- No new alerting/observability surface is introduced — labeling events from the new SITs surface
  through the same Overview/Labeled items/Activity Explorer path already reviewed in round 1.

No Fix/Fail items from this lens.

### 🎩 CISO

**Verdict: Pass**

- Small, well-bounded, no-incremental-licensing-cost extension (same built-in SIT catalog,
  same entitlement — `README.md` §10 unchanged) that closes a specific, previously-deferred
  backlog item without expanding this scenario's scope into a second condition-set default.
- The U.S./U.K. passport-merge disclosure is exactly the kind of specific, board-relevant caveat
  a CISO needs before approving this switch for a U.K.-regulated population — "enabling this also
  adds U.S. passport detection" is a one-sentence, concrete risk statement, not vague hedging.
- Would I fund this? Yes — it's a documentation- and parameter-level enhancement to an
  already-funded, already-reviewed control, not new infrastructure or licensing spend.

No Fix/Fail items from this lens.

### 🟦 Microsoft Product Owner

**Verdict: Pass**

- Both opt-in SIT names were re-confirmed as real, selectable bundle SITs by fetching their own
  Microsoft Learn bundle-index pages directly during this round (not re-asserted from the round-1
  citation alone), and their exact per-country membership lists were captured rather than assumed
  from the national-ID bundle's own composition.
- No new cmdlet introduced — `-IncludeTravelDocumentSits` is pure script-parameter logic (array
  append + dedupe) layered in front of the same, already-grounded `Get-DlpSensitiveInformationType`
  resolution path; no risk of an invented cmdlet or parameter shape.
- The byte-exact-casing VERIFY already open for this scenario's default SITs (`README.md` §11)
  now explicitly extends to `"EU driver's license number"` vs. the page-title spelling `"EU
  drivers license number"` (no apostrophe) — flagged as joining the existing VERIFY rather than
  treated as newly resolved, since this round could not reach a live tenant to confirm either way.
- Scope discipline: this round deliberately did not attempt a full per-country checksum table for
  either opt-in bundle (a ~50-page grounding effort for a non-default condition set) — correctly
  deferred as a `PROGRESS.md` follow-up rather than fabricated to look complete.

No Fix/Fail items from this lens.

### Summary — round 2

| Lens | Verdict | Findings | Resolution |
|---|---|---|---|
| 🔴 Red Team | Fix | 2 (both closed with doc/design/runtime-notice additions) | Closed |
| 🔵 Blue Team | Pass | 0 | — |
| 🎩 CISO | Pass | 0 | — |
| 🟦 Microsoft Product Owner | Pass | 0 (1 VERIFY extended, not newly opened) | — |

All Fix items from round 2 are resolved in the current state of `README.md`, `design.md`,
`deploy/New-EuPersonalDataAutoLabelPolicy.ps1`, and
`validate/Test-EuPersonalDataAutoLabelPolicy.ps1`. This fragment meets the definition of done in
`AGENTS.md` §9.

## Review round 3 — 2026-09-09 — per-country checksum/confidence table for both opt-in bundles

Scope: the `PROGRESS.md` follow-up asking for a full per-country checksum/confidence table for the
"EU passport number" and "EU driver's license number" opt-in bundles, matching the depth already
built for the default "EU national identification number" bundle in round 1. Reviewed after fetching
all 26 passport-bundle and all 28 driver's-license-bundle entity-definition pages directly from
Microsoft Learn and adding both tables to `design.md` §4, with `README.md` §8/§11 updated to cite
the results.

### 🔴 Red Team

**Verdict: Pass (no new Fix — this round closes a prior gap rather than opening one)**

- The headline finding this round surfaces is itself the Red Team-relevant one: both opt-in bundles
  are dramatically weaker on checksum validation than the default bundle a buyer already trusts (8%
  and 11% vs. 73%). That is now disclosed, not hidden — `README.md` §11 states it in the same
  concrete, numeric terms this repo's Red Team lens requires, not "some countries lack checksums."
- Verified the driver's-license bundle's confidence ceiling claim directly against every one of the
  28 fetched pages, not sampled: 25 of 28 entities have exactly one `<Pattern>` tier at
  `confidenceLevel="75"` with no higher tier defined at all — a materially different (weaker)
  structure than the passport bundle's uniform two-tier 85/75 definitions, and worth calling out
  explicitly rather than averaging the two bundles together as "opt-in SITs are weaker."
- No bypass/evasion angle beyond what's already disclosed: a pattern-only, no-checksum SIT (the
  overwhelming majority of both bundles) is inherently easier to evade by using a superficially
  similar but invalid number, but this is the same class of risk already reviewed and accepted for
  the default bundle's 7 pattern-only members in round 1 — not a new risk class introduced by this
  round's grounding work.

No Fix/Fail items from this lens.

### 🔵 Blue Team

**Verdict: Pass**

- `README.md` §8's new KPI bullet gives operators a concrete, numeric expectation (8%/11% vs. 73%
  checksum coverage) to calibrate false-positive triage effort *before* enabling
  `-IncludeTravelDocumentSits`, rather than discovering the weaker signal quality only after
  fielding a wave of override requests.
- No new alerting/observability surface introduced — this round is documentation-only (design.md
  tables + README cross-references); the underlying policy mechanics, deploy script, and validate
  script are unchanged from round 2.

No Fix/Fail items from this lens.

### 🎩 CISO

**Verdict: Pass**

- Zero cost, zero risk change — pure grounding/documentation completeness work that closes a
  disclosed gap from round 2 rather than changing behavior. No new licensing, no new
  infrastructure, no new admin action required.
- The 8%/11%-vs-73% checksum-coverage numbers are exactly the kind of concrete, decision-usable
  metric a CISO needs to size the operational cost (override/relabel volume) of enabling the two
  opt-in bundles before approving that expansion for a specific regulated population.
- Would I fund this? Yes — closing a previously-disclosed, explicitly-tracked gap with real,
  individually-fetched data (not estimated or extrapolated) is exactly the standard this library
  holds itself to elsewhere.

No Fix/Fail items from this lens.

### 🟦 Microsoft Product Owner

**Verdict: Pass**

- All 54 entity-definition pages (26 passport + 28 driver's-license) were fetched directly from
  their own Microsoft Learn URLs during this round — no value in either new table was inferred,
  extrapolated from a subset, or carried over from the national-ID bundle's own numbers.
- The Germany-passport engine-version caveat (checksum path requires DLP engine ≥ 15.20.4570.0,
  confirmed directly from that entity's own `<Version minEngineVersion="...">` XML block) is
  reproduced faithfully in `design.md` §4 rather than simplified away — the same standard of
  fidelity this repo already applies to the German national-ID entity's post-2010-only checksum
  caveat in round 1's table.
- No invented cmdlets, blade paths, or SIT names — this round's only artifact is descriptive data
  (format/checksum/confidence) tabled directly from Microsoft's own entity-definition XML, the same
  low-risk grounding pattern as round 1.

No Fix/Fail items from this lens.

### Summary — round 3

| Lens | Verdict | Findings | Resolution |
|---|---|---|---|
| 🔴 Red Team | Pass | 0 (closes a prior disclosed gap) | — |
| 🔵 Blue Team | Pass | 0 | — |
| 🎩 CISO | Pass | 0 | — |
| 🟦 Microsoft Product Owner | Pass | 0 | — |

No Fix/Fail items from round 3. This fragment (the `PROGRESS.md` follow-up requesting per-country
checksum/confidence tables for both opt-in bundles) meets the definition of done in `AGENTS.md` §9.
