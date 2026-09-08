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
