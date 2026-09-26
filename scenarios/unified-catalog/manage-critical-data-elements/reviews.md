# Four-Lens Review — Manage a Critical Data Element in Unified Catalog

Reviewed after the initial draft of `README.md`, `design.md`, `deploy/`, and `validate/`. One
round of findings below; all **Fix** items were applied to the scenario before this file was
finalized (see "Resolution" under each). No **Fail** items were raised.

---

## 🔴 Red Team

**Verdict: Fix (resolved)**

1. **A silently-skipped column gives false confidence that a source is covered.**
   `Resolve-DataMapColumnId` in `deploy/New-CriticalDataElement.ps1` treats a column-name mismatch
   (wrong case, a typo, a column that hasn't finished scanning) as a `Write-Warning`-and-`continue`
   — the script still exits 0 and prints "Done." A team relying on a CDE as a regulated-data
   inventory (`README.md` §2) could reasonably believe every configured source is mapped when one
   silently isn't, and an attacker or a careless config edit that quietly drops a source out of a
   compliance-relevant CDE would produce no error anyone would notice from the deploy run alone.
   - **Resolution:** `validate/Test-CriticalDataElement.ps1` already hard-`[FAIL]`s an unresolved
     column (it does not inherit the deploy script's tolerance), but that safety net only works if
     someone actually runs it. `README.md` §8 now states explicitly, as its own named operational
     practice, that a deploy run is not considered complete until validate has been run against it
     — promoted from an implicit assumption to a stated discipline, the same treatment
     `manage-data-products/reviews.md` gave its own publish-gate warning finding.
2. **Case-sensitive column-name matching is an undocumented, easy-to-trip footgun.**
   `entity.relationshipAttributes.columns[].displayText -ceq $ColumnName` means `customerid`,
   `CustomerId`, and `CustomerID` are three different strings to this script, but a human skimming
   a config file has no reason to assume case sensitivity matters for what looks like a display
   label. Combined with finding 1's non-fatal skip, a copy-paste config error is a realistic,
   silent-failure path.
   - **Resolution:** Confirmed intentional, not fixable by loosening the match (a case-insensitive
     match risks matching the *wrong* column if a source ever has two columns differing only in
     case — an unlikely but real ambiguity a governance tool shouldn't paper over). Instead,
     `README.md` §11 states the case-sensitivity behavior as a named gotcha (not left implicit in
     code comments alone), and `Resolve-DataMapColumnId`'s `Write-Warning` already lists every
     available column name on a miss, so an operator debugging a skip sees the exact casing
     available rather than having to guess.
3. **The Data Steward + Data Product Owner role pair is domain-scoped, not
   element-scoped** — identical in shape to the domain-scoped-role finding
   `manage-data-products/reviews.md` and `curate-business-glossary/reviews.md` already recorded
   for their own roles.
   - **Resolution:** `README.md` §3 now states this explicitly and cross-references both sibling
     READMEs' existing compensating-controls note rather than treating it as a new, unaddressed
     gap — the mitigation (scope the role assignment to only the domains this automation curates)
     is identical in shape, so this scenario inherits it by reference.

No remaining Fix/Fail after resolution.

---

## 🔵 Blue Team

**Verdict: Fix (resolved)**

1. **No structured signal distinguishes "column skipped due to a resolution failure" from
   "column already mapped, nothing to do"** in the deploy script's console output — both are
   plain `Write-Warning`/`Write-Host` lines a human has to read, not a machine-parseable exit
   code or summary count an unattended pipeline could gate on.
   - **Resolution:** Confirmed this is exactly what `validate/Test-CriticalDataElement.ps1`
     exists to provide — its non-zero exit code on any hard failure (finding 1 above) is the
     CI-gateable signal this scenario offers, matching every other scenario in this repo's
     deploy-then-validate pattern rather than trying to make the deploy script itself do double
     duty as a validation gate. `README.md` §8's new "run validate after every deploy" note makes
     this the documented operational answer instead of leaving a reader to infer it.
2. **The DATAPRODUCT-relationship cross-check has no alerting story if it unexpectedly changes**
   (e.g. a data product is unlinked from the shared asset outside this scenario's control, and the
   rollup silently stops showing it). `validate/Test-CriticalDataElement.ps1` reports this as an
   informational `[WARN]`/`[INFO]` on each run, with no history or trend.
   - **Resolution:** Confirmed intentional scope, not a gap: this rollup is entirely
     Microsoft-computed (design.md §5) and this scenario has no REST-scriptable way to be
     notified of a change to it (the same "no documented Graph/REST query API for this class of
     event" gap `irm-case-escalation-to-ediscovery`'s and
     `adaptive-protection-deleted-content-preservation`'s own follow-ups already recorded for
     different IRM-adjacent audit surfaces). A scheduled re-run of validate, diffed against a
     prior run's output, is the only unattended detection mechanism available today — noted in
     `README.md` §8 rather than left unstated.

No remaining Fail. Both findings resolved by pointing to the existing deploy-then-validate pattern
and stating its operational implications explicitly, not by adding unconfirmed monitoring code.

---

## 🎩 CISO

**Verdict: Fix (resolved)**

- **Regulatory-inventory narrative is genuinely strong but needs an explicit preview caveat.**
  `README.md` §2 pitches this scenario as a way to express a regulated-data-location inventory
  (PCI/GDPR/HIPAA-relevant) as a first-class, API-managed Purview object — a real, board-legible
  story. But the underlying feature is Microsoft-labeled preview end to end (the concept page's
  own title is "Critical data elements (preview)"), which matters if this scenario is ever cited
  as evidence in a formal compliance audit response.
  - **Resolution:** `README.md` §8 now carries an explicit "Compliance-evidence caution" stating
    plainly not to cite this as a sole system of record in a formal audit response before GA — the
    same discipline this repo already applies to other preview-labeled capabilities (e.g.
    `dspm-for-ai`'s Copilot-prompt-block deferral), stated locally rather than assumed known.
- **Cost story is clean and should be highlighted, not buried.** Unlike a scenario that might
  quietly add governed-asset cost, this scenario's default configuration adds **zero** incremental
  cost (§10) because it maps a column belonging to an asset `manage-data-products` already
  governs — a genuinely good-news line for a CISO justifying incremental governance investment
  without a corresponding incremental Azure bill, as long as the deploying organization understands this only holds
  when the column belongs to an already-governed asset.
  - **Resolution:** Confirmed `README.md` §10 already states this contrast explicitly (deduplication
    quoted verbatim from Microsoft's own billing FAQ) and separately calls out the case where a
    *new* asset's first-ever column mapping does trigger the meter — no further change needed, this
    finding is recorded to confirm the review specifically checked for it (the same practice
    `manage-data-products/reviews.md`'s CISO section uses when a check passes cleanly).
- **Role-scoping residual risk (Red Team finding 3) is exactly the kind of finding a CISO needs
  visible before funding, not discovered later.**
  - **Resolution:** Now stated in `README.md` §3 as a named prerequisite-section note rather than
    only in `reviews.md` — a CISO reading only the README, not this file, still sees it.

No remaining Fail. Funding recommendation: **yes**, with the preview-status caveat and the
DATACOLUMN-vs-CRITICALDATACOLUMN VERIFY (Microsoft Product Owner lens, below) tracked as
follow-ups to close before this scenario is presented as fully hardened for a regulatory-evidence
use case specifically.

---

## 🟦 Microsoft Product Owner

**Verdict: Fix (resolved)**

1. **The `entityType=DATACOLUMN`-vs-`CRITICALDATACOLUMN` discrepancy is a real, reportable
   documentation defect, not a grounding shortcut this build took.** Every worked example this
   build fetched for the Critical Data Elements Create/List/Delete Relationship operations —
   three independent reference pages — uses `entityType=CRITICALDATACOLUMN` in its sample request,
   while the `EntityCategory` enum each of those same pages formally documents omits that value
   entirely and lists `DATACOLUMN` instead. An earlier draft risked picking whichever value
   "looked more official" without saying so.
   - **Resolution:** `design.md` §6 documents the discrepancy in full, including that it repeats
     identically across three separate pages (ruling out a one-off typo), and states the specific
     reasoning for choosing the formally-documented enum value (`DATACOLUMN`) over the
     example-only value. `README.md` §6 and §11 and the deploy/rollback scripts' own `.NOTES`
     blocks all name the fallback (`CRITICALDATACOLUMN`) explicitly rather than silently picking
     one and hiding the ambiguity — this is a genuinely open question this build could not resolve
     without a pilot tenant, stated as such.
2. **Correct choice to resolve column GUIDs via the Data Map/Atlas Entity API rather than
   guessing a Unified Catalog-native way to enumerate columns.** The Unified Catalog API's own
   Data Columns operation group has no "list columns for this table" operation — only `Ingest`
   (which requires already knowing the column GUID), `Query` (which filters *existing* Unified
   Catalog data columns, not raw Data Map columns), and `Get`. Reaching into the Data Map/Atlas
   Entity API for the raw column enumeration, grounded directly against Microsoft's own
   `azure_sql_table` type-definition tutorial rather than assumed generically from other Atlas
   entity types, is the only Microsoft-documented path found — not a reinvention of a capability
   Unified Catalog already exposes elsewhere.
3. **Correctly avoided the CSV bulk-import (preview) path**, confirmed specifically for critical
   data elements this time (not just inherited by analogy from the sibling scenarios' own
   glossary-term/data-product bulk-import checks) — Microsoft's own critical-data-elements page
   states plainly "The bulk import process can't be used to edit or update critical data
   elements," directly quoted rather than assumed to hold from the sibling features' behavior.
4. **`dataType` enum choice (`TEXT`) is correctly aligned with the portal's own four expected-data-
   type options** (`number`, `text`, `date/time`, `Boolean` per the bulk-import CSV instructions,
   matching `TEXT`/`NUMBER`/`DATETIME`/`BOOLEAN` in the REST enum one-to-one) — unlike
   `manage-data-products`' own data-product `type` field, there is no 14-vs-11 mismatch to flag
   here; confirmed by direct comparison of both sources rather than assumed consistent.

No remaining Fail after resolution.

---

## Summary

| Lens | Initial verdict | Findings | Resolution |
|---|---|---|---|
| 🔴 Red Team | Fix | 3 (silent-skip false-confidence risk resolved via a named "validate after every deploy" operational discipline; case-sensitivity footgun documented as a named gotcha, not silently loosened; domain-scoped-role risk inherited by reference from both sibling scenarios) | Closed |
| 🔵 Blue Team | Fix | 2 (unattended-pipeline signal confirmed to be validate's exit code, stated explicitly; DATAPRODUCT-rollup change-detection gap confirmed unfixable in tooling today, documented instead) | Closed |
| 🎩 CISO | Fix | 3 (preview-status compliance-evidence caution added; zero-incremental-cost story confirmed and highlighted; role-scoping risk promoted into the README's prerequisites section) | Closed |
| 🟦 Microsoft Product Owner | Fix | 4 (DATACOLUMN/CRITICALDATACOLUMN enum-vs-example discrepancy documented in full rather than silently resolved; Data Map/Atlas Entity API choice confirmed correct and non-duplicative; bulk-import avoidance independently confirmed for this feature specifically; dataType enum alignment confirmed clean) | Closed |

All Fix items from this round are resolved in the current state of `README.md`, `design.md`,
`deploy/New-CriticalDataElement.ps1`, `deploy/Remove-CriticalDataElement.ps1`, and
`validate/Test-CriticalDataElement.ps1`. No Fail items were raised. This fragment meets the
definition of done in `AGENTS.md` §9.
