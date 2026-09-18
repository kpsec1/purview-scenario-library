---
part: "rollback"
parent: "data-estate-insights/classification-coverage-report"
---
## What there is to roll back

Unlike this repo's policy-deploying scenarios, this scenario creates **no object inside Microsoft
Purview at all** — no DLP policy, no label, no lineage relationship, no scan. Every call it makes is
a read-only `POST search/query`. "Rollback" here means three things, none of which touch the Purview
account itself:

1. Stop the scheduled execution of `deploy/Export-ClassificationCoverageReport.ps1`.
2. Remove the reporting service principal's **Data Reader** role assignment.
3. Decide what to do with the already-produced trend-log CSV and breakdown JSON files.

## 1. Stop the schedule

This scenario ships no scheduler-specific code (README.md §5) — remove or disable whatever
recurring-execution mechanism was wired up (an Azure Automation runbook, a scheduled Azure Function,
a cron entry, or a Windows Task Scheduler task) using that platform's own removal procedure. There is
nothing Purview-side to undo as part of this step.

## 2. Remove the automation identity's role assignment

In the Purview portal: **Data Map** → **Collections** → select the collection(s) the reporting
service principal was granted **Data Reader** on → **Role assignments** → remove the service
principal from the **Data readers** list (README.md reference 6). This requires the **Collection
Admin** role, the same prerequisite that was needed to grant it (README.md §3).

If the app registration itself is no longer needed for any other purpose in this repo, also revoke
or delete its client secret/certificate — standard Entra app-registration hygiene, not specific to
this scenario.

## 3. Decide the fate of already-produced report files

- **Trend-log CSV and per-run breakdown JSON files** (wherever `-TrendLogPath` /
  `-BreakdownOutputDirectory` pointed) are ordinary files this scenario wrote outside of Purview —
  delete them, archive them, or leave them in place per the buyer's own data-retention policy. There
  is no Purview-side artifact tied to them that would become orphaned or inconsistent if they're kept
  after the automation identity's role is removed.
- If the trend log was committed to a source-control repository (the recommended pattern for
  preserving history — README.md §4/§8), treat its removal like removing any other tracked file:
  a deliberate commit, not an ad hoc delete, so the historical record itself isn't silently lost
  without a decision to do so.

## What rollback does **not** undo

- **Any Purview object.** There isn't one — see "What there is to roll back," above. Removing this
  scenario's automation has zero effect on the assets, classifications, scans, or collections it
  read from.
- **The scans or classifications themselves** — entirely owned by `scenarios/data-map/
  scan-azure-sql-and-classify/` (or whichever scan populated the collection(s) this scenario
  reported on), not by this scenario.

## Re-enabling later

Re-running `deploy/Export-ClassificationCoverageReport.ps1` after a rollback is safe at any time:
re-assign the Data Reader role (step 2, reversed), point `-TrendLogPath` at either a fresh file or
the previously-archived one, and resume scheduling. Because this scenario's idempotency model
replaces rows by `-RunId` rather than depending on any created Purview object's existence, there is
no "was it fully torn down" ambiguity to resolve before resuming — unlike a policy-deploying
scenario's redeploy-after-rollback case.
