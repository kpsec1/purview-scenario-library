# Four-Lens Review - Manage OKRs (Objectives and Key Results) in Unified Catalog

Reviewed after the initial draft of `README.md`, `design.md`, `deploy/`, and `validate/`. One
round of findings below; all **Fix** items were applied to the scenario before this file was
finalized (see "Resolution" under each). No **Fail** items were raised.

---

## 🔴 Red Team

**Verdict: Fix (resolved)**

1. **This object type has no server-side duplicate guard at all, and this scenario's id-based
   design means the only defense against catalog pollution is process discipline outside the
   tool.** Because Microsoft explicitly permits duplicate-named OKRs, there is no lookup this
   script (or any script) could run to detect "did someone already create this objective under a
   different id?" A careless re-run of `New-Okr.ps1` against a definition file where `objective.id`
   was accidentally regenerated (instead of reusing the pinned value from the first run) creates a
   genuine, silent duplicate - no warning, no error, no exit code signal, since from the API's
   perspective it's just another valid Create. This is a materially different risk profile from
   every other Unified Catalog scenario in this repo, where a name-based lookup at least catches
   the common case.
   - **Resolution:** Not fixable at the API layer (design.md §3 explains why a name-based
     mitigation would be worse, not better, for this object type - Microsoft's own docs deny
     name uniqueness). Instead, `README.md` §11 now states this risk explicitly as a named
     limitation, and the recommended operational practice (stated in §11, not left implicit) is
     to commit the definition file's pinned ids to source control and treat any diff to an
     *existing* objective/key-result `id` field in a pull request as a reviewable, suspicious
     change - the same "make the risk visible where a human will actually see it" pattern this
     repo already uses for undocumented API behavior it cannot close by code alone.
2. **The `assetId`-omission VERIFY (design.md §4/§6) could, if wrong, produce a relationship call
   that silently fails or half-succeeds, giving false assurance that the business-narrative link
   landed when it didn't.**
   - **Resolution:** Confirmed already covered, not a gap: `validate/Test-Okr.ps1`'s data-product
     check reads the link back from the data product's own `List Relationships` response - server
     ground truth, not the deploy script's own success/failure assumption - so a silently-broken
     `Create Relationship` call would surface as a validate `[WARN]` (entityId absent from the
     list), not a false `[PASS]`. `README.md` §8's "run validate after every deploy" discipline
     (already established by the sibling CDE scenario) applies here without modification.
3. **The Data Steward/Data Product Owner role pair is domain-scoped, not OKR-scoped** - identical
   in shape to the domain-scoped-role finding `curate-business-glossary/reviews.md`,
   `manage-data-products/reviews.md`, and `manage-critical-data-elements/reviews.md` already
   recorded for their own roles.
   - **Resolution:** `README.md` §3 states this explicitly and cross-references the sibling
     READMEs' existing compensating-controls note (scope the role assignment to only the domains
     this automation curates) rather than treating it as a new, unaddressed gap.

No remaining Fix/Fail after resolution.

---

## 🔵 Blue Team

**Verdict: Fix (resolved)**

1. **No structured, machine-parseable signal distinguishes "data-product link skipped because
   the product name wasn't found" from "already linked, nothing to do"** in the deploy script's
   console output - the same class of finding `manage-critical-data-elements/reviews.md`'s Blue
   Team recorded for its own column-mapping skip path.
   - **Resolution:** Confirmed this is exactly what `validate/Test-Okr.ps1` exists to provide,
     matching every other scenario in this repo's deploy-then-validate pattern. `README.md` §8's
     "run validate after every deploy" note already covers this; no new code needed.
2. **There is no staleness-detection mechanism for a key result's `progress` value, and no
   Microsoft-documented event/webhook API this scenario's grounding pass found that would notify
   an operator when an OKR has gone unrefreshed.** A key result frozen at "on track" for months
   after the underlying metric has actually regressed is a false-assurance risk with no
   built-in alarm - a real operational gap, not a code defect.
   - **Resolution:** Confirmed no REST/Graph notification surface exists for this today (same "no
     documented event-driven trigger for this class of business-object change" pattern this
     repo's IRM- and eDiscovery-adjacent follow-ups have already recorded for different objects).
     `README.md` §8 now states plainly that progress tracking is manual and that a stale,
     un-refreshed OKR is worse than no OKR for the board-narrative goal in §2 - naming the
     operational discipline required (a scheduled `validate` run, diffed against its own prior
     output, is the only unattended workaround available today) rather than leaving the risk
     unstated.

No remaining Fail. Both findings resolved by pointing to the existing deploy-then-validate
pattern and stating the operational implications explicitly, not by adding unconfirmed monitoring
code.

---

## 🎩 CISO

**Verdict: Fix (resolved)**

- **The board-narrative pitch (README.md §2) is genuinely strong, but its evidentiary weight is
  capped by preview status - a CISO citing a "Customer Response"-style OKR in a funding
  conversation should know the underlying feature, and its API, could change materially before
  GA.**
  - **Resolution:** `README.md` §3 and §11 both state the preview status explicitly, and §8 adds
    the specific caution that OKR progress is a business-narrative tool, not a compliance system
    of record - distinguishing this from `manage-critical-data-elements`'s similar caution, which
    is about audit *evidence* rather than business narrative, so the two don't get conflated.
- **Cost story is clean and should be highlighted, not buried.** This scenario adds zero
  governed-asset billing event of its own (§10) - a genuinely good-news line, reasoned directly
  from the billing FAQ's own enumeration of what counts as a governed asset (which conspicuously
  never names OKRs), stated as an inference rather than an asserted fact.
  - **Resolution:** Confirmed `README.md` §10 already states this precisely, with the inference
    flagged as such rather than overstated - no further change needed; recorded here to confirm
    the review specifically checked for an overclaim and didn't find one.
- **Role-scoping residual risk (Red Team finding 3) is exactly the kind of finding a CISO needs
  visible before funding, not discovered later.**
  - **Resolution:** Stated in `README.md` §3 as a named prerequisite-section note, not only in
    this file.

No remaining Fail. Funding recommendation: **yes**, with the preview-status caveat and the
`additionalProperties`-shape VERIFY (Microsoft Product Owner lens, below) tracked as a follow-up
to close before this scenario's data is presented in a formal external-facing deck without a
"preview feature" footnote.

---

## 🟦 Microsoft Product Owner

**Verdict: Fix (resolved)**

1. **Correctly diagnosed a real, confirmed API asymmetry instead of either fabricating a
   relationship call on the Okr surface or declaring the objective-to-data-product link entirely
   out of scope.** A direct fetch of all thirteen Okr operations confirmed none of them is a
   relationship operation, and a direct fetch of the Data Products - Create/List/Delete
   Relationship pages' shared `EntityCategory` enum confirmed `OBJECTIVE` and `KEYRESULT` are
   real, documented values there - meaning the link genuinely is scriptable, just not from the
   side a reader might first assume. This is the same "verify before declaring a gap" discipline
   `manage-critical-data-elements/design.md` §5 used when it *did* find a genuine, unscriptable
   gap (the CDE-to-data-product rollup) - this build applied the identical rigor and reached a
   different, correct conclusion for a superficially similar situation.
2. **Correctly identified and fixed a pre-existing inaccuracy in `docs/automation-surface.md` §4**
   (the Data Products routing-table row previously said relationships link to "assets/terms/OKRs,"
   an informal paraphrase that doesn't match the actual `OBJECTIVE`/`KEYRESULT` enum values) -
   caught specifically because this build had to fetch that exact enum directly rather than trust
   the existing doc's own summary of it.
3. **Correctly declined to script `KEYRESULT` as a Data Products relationship `entityType`** -
   a documented enum value with no discoverable portal action driving it (design.md §4/§7). Not
   scripting an API surface just because it exists is the same discipline
   `manage-critical-data-elements/design.md` §7 applied to Get Facets/Count.
4. **The `additionalProperties` shape inconsistency between Okr - Create/Get and Okr - Update
   (design.md §6) is a genuine, reportable Microsoft Learn reference defect, not a grounding
   shortcut this build took** - fetched directly from both reference pages, not inferred.
   Confirmed the resolution (never send the field) is the only defensible choice regardless of
   which documented shape is correct, since both describe platform-computed data.

No remaining Fail after resolution.

---

## Summary

| Lens | Initial verdict | Findings | Resolution |
|---|---|---|---|
| 🔴 Red Team | Fix | 3 (no-server-side-duplicate-guard risk documented as a named limitation with a source-control-review mitigation; assetId-omission risk confirmed already covered by validate's server-truth check; domain-scoped-role risk inherited by reference from three sibling scenarios) | Closed |
| 🔵 Blue Team | Fix | 2 (unattended-pipeline signal confirmed to be validate's exit code; OKR-staleness detection gap confirmed unfixable in tooling today, documented as an operational discipline instead) | Closed |
| 🎩 CISO | Fix | 3 (preview-status + business-narrative-vs-compliance-evidence caveat added; zero-incremental-cost story confirmed and highlighted as an inference, not overstated; role-scoping risk promoted into the README's prerequisites section) | Closed |
| 🟦 Microsoft Product Owner | Fix | 4 (Okr-vs-Data-Products relationship asymmetry correctly diagnosed and routed around rather than guessed or abandoned; a pre-existing automation-surface.md inaccuracy caught and fixed; KEYRESULT-linking correctly left unscripted; additionalProperties shape inconsistency documented in full) | Closed |

All Fix items from this round are resolved in the current state of `README.md`, `design.md`,
`deploy/New-Okr.ps1`, `deploy/Remove-Okr.ps1`, and `validate/Test-Okr.ps1`. No Fail items were
raised. This fragment meets the definition of done in `AGENTS.md` §9.

---

## Round 2 - progress-trend companion (`PROGRESS.md` follow-up)

Round 1's Blue Team finding 2 named the lack of any staleness-detection mechanism for a key
result's `progress` value as a real, unfixed-in-tooling operational gap. This round closes the
`PROGRESS.md` follow-up that named the workaround: adds `deploy/Export-OkrProgressTrend.ps1` (a
read-only, local-trend-log-producing companion) and `validate/Test-OkrProgressTrend.ps1` (its
file-integrity/staleness-gate/live-reconciliation companion), plus `README.md` §5/§7/§8/§11/§12 and
`design.md` §8 updates (see design.md §8 for why this departs from the follow-up's literal wording
in two ways, and why each departure is an improvement).

### 🔴 Red Team - Verdict: Fix (resolved)

1. **The trend-log CSV is the sole historical record of a key result's progress over time - losing
   or resetting it silently un-flags every previously-stale entity as freshly "Baseline" on the
   next run, with no warning that history was lost.** An operator who deletes the file (accidentally,
   or during a workstation/CI-runner rebuild) gets no signal that staleness tracking has reset to
   zero, and a key result that was genuinely stale for months would start a fresh staleness clock
   with no trace of the gap.
   - **Resolution:** `rollback.md`'s new "progress-trend companion needs no rollback of its own"
     section states this explicitly (deleting the file is a real, disclosed reset, not silent data
     loss the operator wasn't told about), and `README.md` §11's new bullet on the missing
     Microsoft-side change history states the same consequence. Not fixable in tooling without a
     durable, tenant-side history this object type doesn't have (design.md §8's audit-log
     grounding pass) - documented as a named limitation rather than worked around with unfounded
     complexity (e.g. a second, redundant local backup file this script would then also need to
     keep in sync).
2. **A `-ClientSecret` compromise against this script's own service principal is a lower-value
   target than against `New-Okr.ps1`'s, precisely because design.md §8 deliberately scoped it to no
   Graph permission and the same read-only bar `Test-Okr.ps1` already has - but it still runs
   unattended on a schedule, which is a different threat model (a scheduled task's stored credential
   is a more persistent, more discoverable target than one a human types in interactively) from
   every other script in this scenario.**
   - **Resolution:** `README.md` §3's existing service-principal/role guidance and
     `docs/rbac-model.md` already cover credential-storage hygiene for unattended automation
     generally; this finding doesn't reveal a scenario-specific gap beyond what design.md §8
     already discloses (the least-privilege scoping is itself the mitigation, not a residual risk
     needing a new control). Confirmed as adequately covered, not a new Fix beyond the disclosure
     already made.

### 🔵 Blue Team - Verdict: Fix (resolved)

1. **Mixing Objective rows (no `progress`/`goal`/`max`) and KeyResult rows (all three) in one
   `Export-Csv` call would have silently truncated those three columns from every row in the file,
   not just Objective rows** - `Export-Csv` derives its column set from the first pipeline object
   only. This is exactly the kind of quiet data-loss bug that would have made the whole companion
   worthless (a trend log that can't actually show progress trending) without erroring or warning
   anywhere.
   - **Resolution:** Confirmed already fixed at design time, not left for review to catch: both
     entity types are built with the identical field set (`Definition`/`Progress`/`Goal`/`Max`/
     `Status`, blank for the three Objective doesn't have) in `Export-OkrProgressTrend.ps1`'s
     `New-TrendRow` construction - design.md §8 documents the reasoning. This review independently
     re-derived the same bug before finding it was already handled, and records that verification
     here rather than silently trusting the inline comment.
2. **A numeric value's string representation could theoretically differ between two API responses
   for the same underlying number** (e.g. `45` vs `45.0`), which the plain `[string]` comparison in
   `New-TrendRow` would misread as a change, muddying the staleness signal with false "Changed"
   rows.
   - **Resolution:** Not independently verified against a live tenant (no pilot tenant exists - see
     `PROGRESS.md`'s own backlog policy on VERIFY items). `README.md` §11 now states this as an
     explicit, named VERIFY rather than an implicit assumption the script's logic silently makes.
3. **`validate/Test-OkrProgressTrend.ps1`'s live-reconciliation check confirms the most recent
   run's rows cover every currently-live entity, but does not (and cannot, from file data alone)
   confirm the reverse - that a row claiming `ChangeState: Unchanged` genuinely matches what the
   live entity says right now**, since that would require re-running the full comparison logic
   `Export-OkrProgressTrend.ps1` already owns.
   - **Resolution:** Confirmed as intentional scope, not a gap: the live-reconciliation check's job
     is completeness (nothing missing from the report), not re-verifying the diff engine itself -
     re-running `Export-OkrProgressTrend.ps1` itself is how an operator gets a fresh, authoritative
     comparison. `validate/Test-OkrProgressTrend.ps1`'s own header comment already scopes check 3
     this way; no change needed.

### 🎩 CISO - Verdict: Pass

Zero incremental licensing cost - this companion calls only the same Okr - Get / Get Key Result
operations already in scope for `validate/Test-Okr.ps1`, and (design.md §8) needs a narrower
role than `New-Okr.ps1` already requires. Directly strengthens the board-narrative pitch README.md
§2 makes: an OKR frozen at "on track" for months while the underlying metric actually regressed is
a false-assurance risk to a board-level claim, and this companion is the first concrete, shippable
mitigation for exactly that risk in this scenario. Operational cost is one more scheduled job to
own (same class of ask as every other scheduled companion already in this repo - e.g.
`scan-credential-inventory-report`) - reasonable for the risk reduction. Would fund this addition.

### 🟦 Microsoft Product Owner - Verdict: Pass

Calls only already-grounded operations (`Okr - Get`/`Get Key Result`, cited in Round 1 and reused
here) - no new cmdlet, endpoint, or field shape invented. The new "no OKR-specific audit category"
finding is grounded directly against the "Audit log activities" reference's own "Microsoft Purview
governance activities" table (fetched this round, not inferred), and is stated with the correct
epistemic precision (corroborating, not conclusive - the category describes a different, older data
model) rather than overclaimed now that a citation exists for it. Correctly scoped to a companion
that extends an already-shipped scenario in place, per `AGENTS.md` §4's guidance for a companion
script to an existing scenario, rather than duplicating the scenario's boilerplate into a new
folder.

### Round 2 summary

| Lens | Verdict | Findings | Resolution |
|---|---|---|---|
| 🔴 Red Team | Fix | 2 (trend-log-loss silent-reset risk documented in rollback.md/README §11; unattended-credential threat model confirmed already covered by existing least-privilege scoping and RBAC guidance) | Closed |
| 🔵 Blue Team | Fix | 3 (mixed-schema CSV truncation bug confirmed already fixed at design time; numeric string-format comparison sensitivity flagged as a new VERIFY; live-reconciliation scope confirmed intentional) | Closed |
| 🎩 CISO | Pass | 0 | - |
| 🟦 Microsoft Product Owner | Pass | 0 (new audit-category grounding independently re-checked and stated with correct precision) | - |

No remaining Fix/Fail. This addition meets the definition of done in `AGENTS.md` §9.
