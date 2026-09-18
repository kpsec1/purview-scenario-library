---
part: "design"
parent: "unified-catalog/manage-okrs"
---
## 1. Problem statement

[`unified-catalog/manage-data-products`](/scenarios/unified-catalog/manage-data-products/) groups a scanned asset into a discoverable
"Customer Master Data" data product. [`unified-catalog/manage-critical-data-elements`](/scenarios/unified-catalog/manage-critical-data-elements/)
names the columns that make it trustworthy. Neither answers the question a business sponsor
actually asks a data governance team: *why does any of this matter to the business?* Objectives
and key results (OKRs) are Microsoft's answer — a governance-domain-scoped business objective
("increase trust in customer master data") with measurable key results, linked directly to the
data product(s) that drive or measure it [[1]](README.md#12-references)
[[5]](README.md#12-references). This scenario scripts creating an objective, creating its key
results, and linking it to `manage-data-products`' own "Customer Master Data" product — closing
the `PROGRESS.md` follow-up this repo recorded against its Unified Catalog coverage
("script the Okr/Key Result operation groups and link them to data products").

## 2. Design goals

1. Create/update an objective and its key results from a declarative JSON file.
2. Link the objective to one or more already-existing data products.
3. Ship Draft by default; `-Publish` is a separate, explicit flag — matching this repo's other
   Unified Catalog scenarios' review-before-publish discipline.
4. Everything idempotent and re-runnable per `AGENTS.md` §4, with a `-WhatIf` dry-run path.
5. Do not guess an API shape that doesn't exist. Section 4 below found a real, confirmed gap in
   the Okr operation group (no relationship operation of its own) and a real, confirmed fix for it
   elsewhere in the same API (the Data Products operation group's own relationship operations
   accept `entityType=OBJECTIVE`/`KEYRESULT`) — this design routes around the gap using a
   Microsoft-documented mechanism, rather than either fabricating an Okr-side relationship call or
   declaring the whole link out of scope the way `manage-critical-data-elements/design.md` §5 had
   to for the (genuinely uncreatable) CDE-to-data-product rollup.

## 3. Idempotency design — a deliberate departure from this repo's name-based pattern

Every other Unified Catalog scenario in this repo (`curate-business-glossary`,
`manage-data-products`, `manage-critical-data-elements`) establishes idempotency by querying for
an existing object with an exact (case-insensitive) name match, then creating with a
freshly-minted `id` only if nothing matched. That pattern depends on an assumption Microsoft states
directly for those object types but explicitly **denies** for OKRs: "If you use a name that
already exists, you'll see a warning during the creation process... you won't be blocked from
using a duplicate name" [[2]](README.md#12-references). A name-based existence check is therefore
ambiguous by design for this object type — a second run against a definition file with an
unchanged `definition` text could, in principle, either update the original objective or create a
sibling duplicate, depending on undocumented match/tie-breaking behavior neither this build's
grounding pass nor Microsoft's own docs resolve.

This scenario avoids the ambiguity entirely rather than layering another client-side
exact-match mitigation onto an object type Microsoft has already said doesn't behave that way:
the definition file carries a caller-generated `id` for the objective and for each key result
(the same caller-generated-`id` requirement Create already imposes for every Unified Catalog
object in this repo — Section 42 of the Okr - Create reference marks `id` `Required: True`), and
this scenario's scripts treat that `id` as the sole identity check: **Get** by id first (`GET
.../objectives/{id}`), **Create** on a 404, **Update** (full-body `PUT`) on a 200. The Okr -
Create REST reference marks `id` as a required, caller-supplied UUID field in its request body
(not server-assigned) — the same caller-generated-identity model `manage-data-products` and
`manage-critical-data-elements` already establish for their own object types. The operator
generates the GUID once (e.g. `[guid]::NewGuid()` in a PowerShell session) and pins it in the
definition file before the first run — `deploy/New-Okr.ps1` refuses to run against the placeholder
nil GUID, the same guard `manage-data-products`'/`manage-critical-data-elements`'s Data Map asset
GUID placeholders already use for the identical "replace before running" pattern.

## 4. The relationship gap — and where the real fix lives

A direct fetch of the **Okr** operation group's full operation list (`Count`, `Create`, `Create
Key Result`, `Delete`, `Delete Key Result`, `Get`, `Get Facets`, `Get Key Result`, `List`, `List
Key Results`, `Query`, `Update`, `Update Key Result`) confirms it has **no** `Create
Relationship`/`List Relationships`/`Delete Relationship` operation at all — unlike Data Products,
Critical Data Elements, and Terms, each of which has all three. Neither the `Objective` nor the
`ObjectiveWithAdditionalProperties` response schema carries any data-product-reference field
either (confirmed by direct comparison of the Create/Get/Update/Query REST reference pages'
request/response definitions) [[8]](README.md#12-references). The portal's own **+ Link data
product** button on an OKR's details page [[2]](README.md#12-references) therefore cannot be
calling anything on the Okr surface — Microsoft's own API is asymmetric here by design, not by
omission this build failed to find.

The fix is on the *other* side of the relationship. The **Data Products** operation group's
`Create Relationship`/`List Relationships`/`Delete Relationship` operations all share one
`EntityCategory` enum, and that enum — fetched directly from the **Create Relationship** REST
reference — lists `OBJECTIVE` and `KEYRESULT` as valid values alongside `DATAASSET`, `TERM`,
`CRITICALDATAELEMENT`, `DATACOLUMN`, and others
[[9]](README.md#12-references). This means the documented way to link an objective to a data
product is to call the **data product's own** `Create Relationship` operation with
`entityType=OBJECTIVE` and `entityId=<objective id>` — exactly the same operation
`manage-data-products/deploy/New-DataProduct.ps1`'s `Add-DataProductRelationship` already calls
for `DATAASSET`/`TERM`, extended here with a third entity type. This scenario's
`Add-ObjectiveToDataProduct` function is that extension, duplicated rather than shared per this
repo's self-contained-script convention (Section 2), reusing `manage-data-products`' own
`Find-DataProductByName` query pattern to resolve the target product without assuming it was
created by this scenario.

**Correcting a prior doc claim.** `docs/automation-surface.md` §4's Data Products routing-table
row previously described this as "links a data product to assets/terms/**OKRs**" — an
informal paraphrase written before this scenario's dedicated grounding pass confirmed the actual
enum values are `OBJECTIVE` and `KEYRESULT`, not a literal `OKR` value. This build corrects that
row in place (a small, doc-only fix bundled with this fragment, matching the precedent
`curate-business-glossary`'s and `manage-data-products`' own automation-surface.md follow-ups
already set of tracking doc corrections alongside the scenario that discovers them) — see
`docs/automation-surface.md` §4 and `PROGRESS.md`.

**Only `OBJECTIVE` is scripted, not `KEYRESULT`.** The portal's own "Link data product" action
lives exclusively on an OKR's *objective* details page, with no equivalent action anywhere on an
individual key result's page [[3]](README.md#12-references). `KEYRESULT` being a documented
`EntityCategory` enum value with no discoverable portal caller is treated as a real but
not-yet-exposed capability — not scripted here, to avoid inventing a use for a value this build
cannot observe any product surface actually driving (non-goal, Section 7).

## 5. Key result identity and the `domainId` redundancy

A key result is created as a sub-resource of its parent objective
(`POST .../objectives/{objectiveId}/keyResults`), yet its own request body separately requires a
`domainId` field — redundant with the parent objective's own `domain`, since the portal exposes no
way to give a key result a different domain from its objective [[4]](README.md#12-references).
This scenario always sends the parent objective's own domain id for every key result it creates,
the only configuration the portal itself permits; whether the API independently validates or
silently ignores a mismatched `domainId` is not documented and not exercised by this scenario's
scripts (`README.md` §11).

Key results follow the identical Section 3 id-based idempotency pattern as their parent objective:
each entry in the definition file's `keyResults` array carries its own caller-generated `id`,
checked via `GET .../objectives/{objectiveId}/keyResults/{keyResultId}` before deciding create vs.
update.

## 6. `additionalProperties` is never sent

The `Okr - Create` and `Okr - Get` REST references both document an `additionalProperties` object
carrying `keyResultsCount`, `overallProgress`, `overallGoal`, `overallMax`, and `overallStatus` —
values that read as platform-computed roll-ups derived from the objective's own key results, not
data a caller should assert. The `Okr - Update` reference, by contrast, documents
`additionalProperties` on that same resource as type `OkrSharedEntityStatus` (an enum: `Draft`/
`Published`/`Closed`) — a different, apparently-inconsistent shape for the same field name on the
same object, fetched directly from Microsoft's own reference pages, not a build artifact of this
scenario's own drafting. This scenario's scripts never send `additionalProperties` on either
Create or Update, reasoning that a computed roll-up has no well-typed client-supplied value to
send regardless of which of the two documented shapes is the real one — flagged in `README.md`
§11 as a genuine Microsoft Learn reference inconsistency, not resolved by guessing.

## 7. Non-goals

- **Scripting `KEYRESULT` as a Data Products relationship `entityType`.** See Section 4 — a
  documented enum value with no discoverable portal caller.
- **Custom attributes.** Microsoft's portal supports governance-domain-scoped custom attribute
  groups on OKRs, the same mechanism `manage-critical-data-elements/design.md` §7 declines to
  model for critical data elements; this scenario's definition file doesn't model them either.
- **`Okr - Get Facets` and `Okr - Count`.** Neither was needed for create/link/observe; the same
  scoping choice `manage-critical-data-elements/design.md` §7 makes for its own Get Facets/Count
  operations.
- **Managed-attribute filtering on `Okr - Query`.** This scenario's scripts never call `Query` at
  all (Section 3) — Query's own `managedAttributes` filter parameter is unexercised.

## 8. Progress-trend companion (`PROGRESS.md` follow-up)

`PROGRESS.md`'s own follow-up asked for "a small scheduled companion script that re-runs
`validate/Test-Okr.ps1` on a cadence and diffs its output against a prior run" — the only
unattended staleness-detection workaround Section 6/`README.md` §8 name for a key result's
`progress` value going stale (frozen at "on track" while the real metric moves). This section
records why the shipped implementation (`deploy/Export-OkrProgressTrend.ps1` +
`validate/Test-OkrProgressTrend.ps1`) departs from the follow-up's literal wording in two ways, and
why each departure is an improvement rather than scope creep:

1. **It re-derives structured data instead of literally invoking `Test-Okr.ps1` and diffing its
   console text.** Two independent problems with the literal reading, either of which alone would
   have been disqualifying: (a) `Test-Okr.ps1` calls `exit 1` on a hard failure, and PowerShell's
   `exit` inside a script invoked via the call operator (`&`) terminates the **entire host
   process**, not just that script's own scope — a wrapper that ran `& ./Test-Okr.ps1 @params`
   in-process would never reach its own staleness-diff logic on any run where Test-Okr.ps1 found a
   problem, which is exactly the run an operator most needs the diff for. (b) Running it instead as
   an isolated child process (`pwsh -File ...`) to sidestep that would require passing the
   `-ClientSecret` `SecureString` across a process boundary, which means serializing it to
   plaintext on a command line — a real secret-handling regression this repo does not accept
   anywhere else. Diffing **structured, named fields** (`definition`/`progress`/`goal`/`max`/
   `status`, fetched directly by this script's own minimal GET calls) run-over-run avoids both
   problems and is a stronger, machine-comparable signal than text-diffing colorized console
   output would have been regardless — the same "structured over textual" preference
   `scan-credential-inventory-report`'s own per-kind fingerprint extraction already established for
   a different drift-detection problem in this repo.
2. **It diffs against this entity's own most recent PRIOR run, not a checked-in expected-state
   file.** `scan-credential-inventory-report`'s drift model (the closest existing precedent in this
   repo) compares live state to a human-authored, checked-in "what SHOULD this be" file — the right
   model for a credential inventory, where drift from an approved baseline is itself the risk. An
   OKR's `progress` value is expected to change over its lifetime (that's the point of tracking it)
   — there is no "correct" checked-in progress number to drift-check against, only the question of
   *whether anyone has updated it lately*. Run-over-run comparison is the correct model for that
   different question.

**Why the Export script needs no Graph token, unlike `New-Okr.ps1`.** It never resolves an owner
identity — it only re-fetches the objective/key-result objects already created, so `AppId` needs
only the same read-only Data Steward / Governance Domain Reader bar `validate/Test-Okr.ps1` already
requires, not the `User.Read.All` Graph application permission `New-Okr.ps1` needs. A narrower
credential for a script that runs unattended on a schedule (and is therefore a higher-value target
for a compromised-credential scenario than a human-triggered deploy) is a deliberate, disclosed
least-privilege choice, not an oversight.

**A uniform CSV schema across both entity types (Objective and KeyResult), by design, not by
accident.** `Export-Csv` derives its column headers from the *first* object in the pipeline only —
an Objective row (which has no `progress`/`goal`/`max`) and a KeyResult row (which has all three)
would, if given their natural narrower/wider shapes, silently truncate `progress`/`goal`/`max`
from every row in the file, including KeyResult rows, whichever type happened to sort first. Both
row types are built with the identical field set (`Definition`/`Progress`/`Goal`/`Max`/`Status`,
blank for the three Objective doesn't have) specifically to avoid this — a correctness fix applied
at design time, not discovered as a review finding (though the four-lens review below did
independently re-derive and confirm the same reasoning — see the Blue Team section).

**No audit/change-history surface exists for this object type, re-checked, not just carried
forward.** Rather than repeat reviews.md Round 1's Blue Team finding 2 unexamined, this build
independently re-checked the "Audit log activities" reference's own "Microsoft Purview governance
activities" category and found it lists `EntityCreated`/`EntityUpdated`/`EntityDeleted`,
`Classification*`, `GlossaryTerm*`, and `SensitivityLabelChanged` — the classic Atlas-model entity
event set — with **no** Objective/KeyResult/OKR-specific operation. This corroborates, but does not
conclusively prove, the original finding: that audit category describes a distinct, older data
model from the Unified Catalog OKR REST API this scenario actually calls, so an OKR change routed
through some other, unrecognized mechanism is not fully ruled out. `README.md` §11 and this
script's own `.NOTES` state the finding with that precision rather than upgrading it to a flat
"confirmed no audit trail" claim now that a citation exists for it.
