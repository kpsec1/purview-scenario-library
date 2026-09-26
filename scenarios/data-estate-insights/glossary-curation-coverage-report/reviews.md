# Four-Lens Review - Glossary Curation Coverage Report

Reviewed after the initial draft of `README.md`, `design.md`, `deploy/`, and `validate/`. One round
of findings below; all **Fix** items were applied to the scenario before this file was finalized
(see "Resolution" under each). No **Fail** items were raised.

---

## 🔴 Red Team

**Verdict: Fix (resolved)**

1. **The default (non-`-PublishedOnly`) mode requires Data Steward - a materially more privileged,
   write-capable role - for what is conceptually a read-only reporting task, and the original draft
   didn't flag the resulting blast-radius increase clearly enough.** Unlike `classification-
   coverage-report`'s Data-Reader-only design, a compromised credential for this report's default
   mode can also create/update/delete terms and policies in every domain it's scoped to (Data
   Steward's actual documented permission set), not just read them.
   - **Resolution:** `README.md` §3's role table and `design.md` §2 goal 2 both state plainly that
     this is *more* privileged than the sibling `classification-coverage-report` scenario, not
     parity - and `README.md` §6 recommends `-PublishedOnly` explicitly as the lower-privilege
     alternative wherever Draft-term visibility isn't a hard requirement. This is now a disclosed,
     named trade-off rather than an implicit privilege escalation a reader might not notice.
2. **`IncompleteTermNames` and `UnlinkedPublishedNames` in the breakdown JSON are themselves a
   business-vocabulary reconnaissance artifact** - a list of exactly which glossary terms are
   unowned or unattached tells an attacker (or a careless recipient) precisely which parts of the
   organization's data-governance program are weakest, with no access control once the file leaves
   the script's memory.
   - **Resolution:** `README.md` §11 now states this report is a "sensitivity-adjacent artifact" and
     recommends access-controlled storage for its output, consistent with (though explicitly scoped
     lower-sensitivity than) `classification-coverage-report/README.md` §11's treatment of its own
     more sensitive trend-log content.
3. **A `-PublishedOnly` run and a Data-Steward run against the same domain will report different
   `TotalTerms` without any obvious visual flag in the trend-log CSV row itself unless a consumer
   reads the `PublishedOnly` column** - someone diffing two trend-log rows across a schedule change
   (e.g. the automation identity's role was accidentally downgraded) could misread a legitimate
   Draft-term undercount as a real drop in glossary size.
   - **Resolution:** `validate/Test-GlossaryCurationCoverageReport.ps1` explicitly reads the
     `PublishedOnly` column per row and skips the status-sum arithmetic check accordingly rather than
     silently passing or failing on a Draft/Expired value that was never `0` for a real reason;
     `README.md` §11 states plainly that `-PublishedOnly` mode changes `TotalTerms`' own meaning
     (published-only, not tenant-truth), so a role change between runs is visible in the trend log's
     own `PublishedOnly` column, not just inferable from a count change.

No remaining Fix/Fail after resolution.

---

## 🔵 Blue Team

**Verdict: Fix (resolved)**

1. **A role-permission gap (automation identity holds Catalog Reader but the script wasn't run with
   `-PublishedOnly`) would silently under-report Draft-term counts as a real zero rather than
   surfacing as an error**, since `Terms - List` simply won't return terms the caller's role can't
   see - there's no distinguishable "0 because there are none" vs. "0 because I can't see them"
   signal from the API itself.
   - **Resolution:** `README.md` §8's incident-response runbook now names this exact failure mode
     explicitly under item 3 ("A `Write-Warning` for a role-permission mismatch..."), directing an
     operator to check the role assignment before trusting a sudden Draft-count drop to zero as real
     glossary curation progress rather than a permission regression.
2. **No guidance on distinguishing the live-reconciliation `[WARN]` from a file-integrity `[FAIL]`
   in an unattended pipeline's alerting**, the same class of gap `classification-coverage-report`
   originally had.
   - **Resolution:** `README.md` §8's incident-response runbook opens by naming which check category
     (file-integrity vs. live-reconciliation) each severity maps to, matching the resolved pattern
     already established in `classification-coverage-report/README.md` §8.
3. **No SIEM/Sentinel-specific detection rule suggested** for "asset-attachment rate dropped sharply
   between two runs" or "a term has been in Draft for N days" - correctly out of scope for this
   scenario to build (a consuming SIEM's own alerting rule, not this script's job), but worth
   confirming as a deliberate non-goal rather than an oversight.
   - **Resolution:** No change needed; confirmed as correctly scoped - the trend log and per-run
     breakdown JSON (which carries `systemData.createdAt`, per `README.md` §8) are what make such a
     rule buildable by the deploying organization's own SIEM, consistent with `design.md` §8's stated non-goal.

No remaining Fail. The two Fixes bring this scenario's operational guidance to the standard this
repo's `classification-coverage-report` sibling already sets.

---

## 🎩 CISO

**Verdict: Pass**

1. **Honest about its own privilege cost.** Unlike a scenario that claims a uniformly low-privilege
   story, this one states clearly that full status coverage costs more privilege (Data Steward) than
   its sibling report, and gives a named lower-privilege alternative (`-PublishedOnly`) rather than
   forcing an all-or-nothing choice - the right level of nuance for a funding decision that has to
   weigh coverage completeness against blast radius.
2. **Cost is negligible and the one real cost driver (per-term relationship calls at scale) is
   called out with a concrete opt-out (`-SkipAssetLinkCheck`)**, not hidden behind a vague
   "may not scale" caveat.
3. **The scope-boundary disclosure (classic glossary model vs. Unified Catalog Terms model,
   `README.md` §11) is the single most important thing this scenario had to get right before being
   handed to a board or GRC tool** - an organization that hasn't migrated to Unified Catalog terms would
   otherwise be shown a false "your glossary is empty" signal instead of "you're on a different
   glossary model this report doesn't cover." Stating this plainly, rather than letting a reader
   discover it by getting zero results, is exactly the kind of transparency a CISO needs before
   trusting the numbers.
4. **Change-management impact: none.** No M365 control, DLP policy, or user-facing behavior is
   touched - a pure read/report layer, same as its sibling. Rollback is correspondingly simple.
5. **Would I fund this?** Yes. "We can show glossary curation completeness and asset-attachment
   rate trending over time, against the same term model our glossary-as-code pipeline actually
   writes to" is a specific, defensible narrative that closes a real, named gap in the native
   report's coverage of this repo's own architecture.

No Fix/Fail raised.

---

## 🟦 Microsoft Product Owner

**Verdict: Fix (resolved)**

1. **The single most important correctness issue in the initial draft was conflating the classic
   glossary report's object model with the Unified Catalog Terms model** - an early pass of this
   scenario assumed the classic report's `Approved`/`Alert` status vocabulary could be reproduced
   directly against the new `Term.status` enum. A direct fetch of the Terms - List/Get REST
   reference confirmed the new enum has only three values (`DRAFT`/`PUBLISHED`/`EXPIRED`), with no
   `Alert` field anywhere on the `Term` object.
   - **Resolution:** `design.md` §1 (point 4) and §4 now state the model mismatch explicitly, with a
     mapping table showing exactly which classic concepts have a documented analog (`Approved` ≈
     `PUBLISHED`, `Draft`/`Expired` unchanged) and which don't (`Alert` - dropped, not invented).
     `README.md` §11 repeats this as the scenario's single most important disclosed limitation.
2. **Strong, primarily-sourced grounding for every REST operation used** - `Terms - List`,
   `Terms - List Related Entities`, and the `Term`/`ContactsMap`/`CatalogModelStatus` schemas were
   all confirmed via direct fetch of the current (`2026-03-20-preview`) REST reference pages, the
   same version this repo's `curate-business-glossary` and `docs/automation-surface.md` §4 already
   pin - no version drift introduced.
3. **The role-privilege claims (Data Steward for Draft visibility; Global/Local Catalog Reader for
   published-only) are grounded in a direct fetch of the canonical `data-governance-roles-
   permissions` page**, not inferred from a general RBAC article or copied from a sibling scenario
   without re-verifying it still applies to this specific read operation.
4. **This scenario correctly declines to invent a facets-based fast path.** `Terms - Get Facets`'
   `facets[].name` values are not enumerated in Microsoft's reference (only a worked `owner` example
   exists) - rather than guessing that `status` or a `hasAssets`-style name would work, this
   scenario uses the documented, confirmed client-side tally instead, the same discipline
   `classification-coverage-report/design.md` §2 goal 3 already establishes as this repo's standard.
5. **Reinventing-a-native-capability check:** this scenario does not attempt to rebuild the classic
   glossary report's UI, drill-down browsing, or portal experience - and, more specifically for this
   scenario, does not claim to be a replacement for that report on a tenant still using the classic
   glossary model it doesn't cover (§11). This is the correct scope for a companion automation built
   against a different, newer object model, not a competing reproduction of the old one.
6. **No deprecated cmdlets/endpoints used.** No PowerShell module exists for Unified Catalog term
   reads, consistent with `curate-business-glossary/README.md` §5's own statement - both scripts use
   `Invoke-RestMethod` directly against the pinned preview API version, with the version's preview
   status disclosed rather than presented as GA-stable.

No remaining Fail after resolution.

---

## Summary

| Lens | Initial verdict | Findings | Resolution |
|---|---|---|---|
| 🔴 Red Team | Fix | 3 (all closed via README/design/validate additions) | Closed |
| 🔵 Blue Team | Fix | 3 (2 closed via README additions, 1 confirmed correctly scoped) | Closed |
| 🎩 CISO | Pass | - | - |
| 🟦 Microsoft Product Owner | Fix | 1 major (model-mismatch) closed via design.md/README.md; 5 confirmed correct | Closed |

All Fix items from this round are resolved in the current state of `README.md`, `design.md`,
`deploy/`, and `validate/`. No Fail items were raised. This fragment meets the definition of done in
`AGENTS.md` §9.
