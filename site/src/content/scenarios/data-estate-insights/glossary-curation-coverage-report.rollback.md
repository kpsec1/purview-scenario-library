---
part: "rollback"
parent: "data-estate-insights/glossary-curation-coverage-report"
---
## What there is to roll back

Like `classification-coverage-report`, this scenario creates **no object inside Microsoft Purview at
all** — no domain, no term, no relationship. Every call it makes is a read-only `GET`. "Rollback"
here means three things, none of which touch the Purview account itself:

1. Stop the scheduled execution of `deploy/Export-GlossaryCurationCoverageReport.ps1`.
2. Remove the reporting service principal's **Data Steward** (or **Global/Local Catalog Reader**,
   in `-PublishedOnly` mode) role assignment.
3. Decide what to do with the already-produced trend-log CSV and breakdown JSON files.

## 1. Stop the schedule

This scenario ships no scheduler-specific code (`README.md` §5) — remove or disable whatever
recurring-execution mechanism was wired up, using that platform's own removal procedure. There is
nothing Purview-side to undo as part of this step.

## 2. Remove the automation identity's role assignment

In the Purview portal: **Unified Catalog** → **Governance domains** → select the domain(s) the
reporting service principal was granted a role on → **Roles** tab → remove the service principal
from the **Data Stewards** (or **Local Catalog Readers**) list. This requires the **Governance
Domain Owner** role, the same prerequisite that was needed to grant it (`README.md` §3). For a
service principal granted **Global Catalog Reader** at the catalog level instead, remove it from
**Settings** → **Unified Catalog** → **Roles and permissions** → **Global Catalog Readers**.

If the app registration itself is no longer needed for any other purpose in this repo, also revoke
or delete its client secret/certificate — standard Entra app-registration hygiene, not specific to
this scenario.

## 3. Decide the fate of already-produced report files

- **Trend-log CSV and per-run breakdown JSON files** (wherever `-TrendLogPath` /
  `-BreakdownOutputDirectory` pointed) are ordinary files this scenario wrote outside of Purview —
  delete them, archive them, or leave them in place per the buyer's own data-retention policy. There
  is no Purview-side artifact tied to them that would become orphaned or inconsistent if they're
  kept after the automation identity's role is removed.
- If the trend log was committed to a source-control repository (the recommended pattern for
  preserving history — `README.md` §4/§8), treat its removal like removing any other tracked file:
  a deliberate commit, not an ad hoc delete.

## What rollback does **not** undo

- **Any Purview object.** There isn't one — see "What there is to roll back," above. Removing this
  scenario's automation has zero effect on the domains, terms, contacts, or asset relationships it
  read from.
- **The glossary terms themselves** — entirely owned by
  `scenarios/unified-catalog/curate-business-glossary/` (or whichever process authored the domain(s)
  this scenario reported on), not by this scenario.

## Re-enabling later

Re-running `deploy/Export-GlossaryCurationCoverageReport.ps1` after a rollback is safe at any time:
re-assign the Data Steward (or Catalog Reader) role (step 2, reversed), point `-TrendLogPath` at
either a fresh file or the previously-archived one, and resume scheduling. Because this scenario's
idempotency model replaces rows by `-RunId` rather than depending on any created Purview object's
existence, there is no "was it fully torn down" ambiguity to resolve before resuming.
