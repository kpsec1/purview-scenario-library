# Four-Lens Review — File Plan Bulk Import (Multi-Class Record Schedule)

Reviewed after the initial draft of `README.md`, `design.md`, `deploy/`, and `validate/`. All scripts
were also parse-checked and the validator was exercised end-to-end (a clean 10-row sample, and a
deliberately malformed CSV exercising every hard-error path) with PowerShell 7.4.6 before this
review — findings below are informed by that run, not just static reading. One round of findings;
all **Fix** items were applied before this file was finalized. No **Fail** items were raised.

---

## 🔴 Red Team

**Verdict: Fix (resolved)**

1. **CSV/formula injection.** The documented workflow (README §5) has a human open the generated
   file in a spreadsheet app before uploading it to the portal. A free-text column (`Comment`,
   `Notes`, `CitationName`, etc.) starting with `=`, `+`, `-`, or `@` — or containing a raw
   tab/CR/LF — is the classic OWASP CSV-injection vector: a malicious schedule contributor could
   plant a formula that executes when a records manager opens the file to review it before
   uploading.
   - **Resolution:** `FilePlanRow.Validate.ps1` now hard-fails any free-text column with a leading
     `=`/`+`/`-`/`@` or an embedded control character. Verified live: a test row with
     `Comment == "=cmd|'/c calc'!A1"` was correctly rejected (`[FAIL] Comment starts with '='...`).
     `README.md` §11 and `design.md` §6 document the control.
2. **A bulk run creates dozens of *immutable* labels in one shot.** Because `LabelName` and core
   retention settings can't be changed after save, a bad bulk run is a bigger, permanent mistake than
   a single-scenario one.
   - **Resolution:** Both deploy paths validate every row against the full documented rule set
     before creating/uploading anything (verified live: a malformed file produced 15 errors and
     wrote/created nothing); `README.md` §2/§5 leads with `-DryRun`/offline validation as step one,
     and §10 states the blast-radius risk explicitly.
3. **Silent auto-delete masquerading as reviewed disposition.** A `KeepAndDelete` row with no
   `ReviewerEmail` deletes with no review.
   - **Resolution:** Every script that touches a row emits a `[WARN]` for this combination — same
     pattern as the sibling `regulatory-records-disposition` scenario.
4. **Casual bulk teardown.** Removing dozens of labels at once via `Remove-FilePlanBulkLabels.ps1`.
   - **Resolution:** `Remove-ComplianceTag` itself refuses a label that's applied, published,
     event-based, or regulatory; the script reports these as kept, never forces removal; descriptor
     objects are never touched by rollback at all (shared across labels). `rollback.md` opens with
     the irreversibility/no-bulk-delete warning.

No remaining Fix/Fail after resolution.

---

## 🔵 Blue Team

**Verdict: Fix (resolved)**

1. **Partial-failure visibility in a CI-style run.** If a scheduled pipeline runs
   `New-FilePlanBulkLabels.ps1` against a growing schedule, a silently-swallowed per-row failure
   would let bad rows accumulate unnoticed.
   - **Resolution:** The script tallies `Created`/`Skipped`/`Failed validation` and exits non-zero if
     any row failed — verified the exit-code path via the parser/logic review; `Test-FilePlanBulkImport.ps1`
     likewise exits non-zero on any hard check failure, safe for a CI gate.
2. **No documented audit trail for bulk label *creation* events** (as distinct from label
   *application* events, which Microsoft does document — `Changed retention label for a file`
   [[8]](README.md#12-references)).
   - **Resolution:** Rather than guess a `RecordType`, this is flagged as an open VERIFY in
     `README.md` §11 with the exact distinction (creation vs. application) spelled out, so a future
     fragment grounds it deliberately instead of this one inventing a value.
3. **File-plan-descriptor read-back isn't asserted by validate.** `Get-ComplianceTag`'s exposed
   property names for descriptors weren't confirmed against Learn.
   - **Resolution:** `validate/Test-FilePlanBulkImport.ps1` reports descriptors informationally
     rather than asserting on unconfirmed property names, and says so in its own `.DESCRIPTION` and
     `README.md` §11 — an honest gap, not a silently-wrong check.
4. **Working dry-run.** `-WhatIf` doesn't function in S&C PowerShell.
   - **Resolution:** `New-FilePlanBulkLabels.ps1`/`Remove-FilePlanBulkLabels.ps1` implement `-DryRun`;
     `New-FilePlanImportCsv.ps1` is non-mutating by construction (only `Get-*` under `-TenantChecks`).

No remaining Fail.

---

## 🎩 CISO

**Verdict: Fix (resolved)**

1. **Schedule-as-code for the whole file plan, not one label.** The deliverable a records-management
   engagement is actually judged on is the schedule, not a single class — `README.md` §1/§2 frame
   this scenario as the breadth complement to the sibling deep-dive, matching how organizations evaluate
   the product.
2. **Risk vs. cost:** stated honestly in §10 — E5 entitlement (no meter); the real cost is the
   one-time schedule-design labor, and the real risk is a rushed, immutable bulk import at scale
   (§10 names this explicitly rather than softening it).
3. **Board/compliance narrative:** "the organization's entire retention schedule is a single,
   validated, version-controlled file — every record class, its owner, its citation, and its
   retention period are reviewable in one diff before anything is created" — concrete and
   examiner-friendly.
4. **Change management:** immutability of `LabelName`/core settings is called out repeatedly (§6,
   §8, §11) so a correction path (new row, not edit) is the expected, not surprising, behavior.
5. **Would I fund this?** Yes — it's the actual shape of a records-management rollout (a schedule),
   not a demo label, and it front-loads the risk-review step (validation) before the expensive
   mistake (an immutable bulk create) can happen.

No remaining Fix/Fail after resolution.

---

## 🟦 Microsoft Product Owner

**Verdict: Fix (resolved)**

1. **Correct, current cmdlets — independently verified, not just cited.** `New-ComplianceTag`'s full
   parameter set (`-FilePlanProperty`, `-Regulatory`, `-IsRecordUnlockedAsDefault`,
   `-ComplianceTagForNextStage`, `-ReviewerEmail`, `-EventType`) and all six
   `New-/Get-FilePlanProperty*` cmdlets (`Department`/`Category`/`SubCategory` with `-ParentId`/
   `Citation`/`ReferenceId`/`Authority`) were each fetched/confirmed against their own Microsoft
   Learn pages, not assumed from naming convention alone.
2. **The `-FilePlanProperty` JSON shape matches Microsoft's own worked example exactly**
   (`PSCustomObject{Settings=@(@{Key;Value})} | ConvertTo-Json`) — reproduced verbatim in
   `New-FilePlanBulkLabels.ps1`, not approximated.
3. **Correctly identifies what has no API.** The CSV-import upload step itself is portal-only —
   stated plainly (`README.md` §11, `design.md` §7) rather than inventing a REST/Graph call that
   doesn't exist. `design.md` §7 also explicitly declines to script `CitationUrl`/
   `CitationJurisdiction`, since `New-FilePlanPropertyCitation`'s documented syntax takes only
   `-Name`.
4. **Right pattern for the obligation.** Bulk file-plan creation is Microsoft's own documented
   mechanism for exactly this problem (CSV import) — this scenario automates its validation and
   ships the scriptable equivalent, rather than reinventing bulk creation with ad hoc looped portal
   clicks or an undocumented API.
5. **Accurately scoped exclusion.** Multi-stage disposition review is correctly identified as
   unsupported by the CSV import *and* left single-stage in the PowerShell path, matching
   Microsoft's own "not currently supported for import" callout — not silently dropped or
   over-claimed.
6. **Accurate licensing.** E5 / E5 Compliance / Purview Suite records management, matching the
   sibling scenario and the service description.

No remaining Fail after resolution.

---

## Summary

| Lens | Initial verdict | Findings | Resolution |
|---|---|---|---|
| 🔴 Red Team | Fix | 4 (CSV/formula-injection guard added + verified live; pre-validated bulk creation; reviewer-required disposition warning; governed, non-forced teardown) | Closed |
| 🔵 Blue Team | Fix | 4 (CI-safe exit codes verified; audit-trail-for-creation gap flagged as VERIFY rather than guessed; honest descriptor read-back gap; working `-DryRun`) | Closed |
| 🎩 CISO | Fix | 1 (frame as schedule-as-code, the actual deliverable); Pass on cost/narrative/change-mgmt | Closed |
| 🟦 Microsoft Product Owner | Fix | 1 (independently re-verify every cmdlet/parameter rather than trust naming convention); 5 confirmed correct | Closed |

All Fix items are resolved in the current state of `README.md`, `design.md`,
`deploy/FilePlanRow.Validate.ps1`, `deploy/New-FilePlanImportCsv.ps1`,
`deploy/New-FilePlanBulkLabels.ps1`, `deploy/Remove-FilePlanBulkLabels.ps1`,
`deploy/config/file-plan-schedule.sample.csv`, and `validate/Test-FilePlanBulkImport.ps1`. No Fail
items were raised. This fragment meets the definition of done in `AGENTS.md` §9; product facts are
grounded in Microsoft Learn (every cmdlet and parameter used was individually fetched/confirmed, not
assumed), all scripts were parse-checked and the validation logic was exercised live against both a
clean and a deliberately malformed schedule (PowerShell 7.4.6), and every documented capability gap
(no CSV-import API, no multi-stage review, no citation URL/jurisdiction via PowerShell) is stated
rather than glossed over.
