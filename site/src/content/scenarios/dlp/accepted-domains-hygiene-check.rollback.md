---
part: "rollback"
parent: "dlp/accepted-domains-hygiene-check"
---
## What there is to roll back

Same archetype as `scenarios/data-estate-insights/classification-coverage-report`: this scenario
creates **no object inside Exchange Online or Microsoft Purview at all** — no accepted domain, no DLP
policy, no rule. Every call `deploy/Export-AcceptedDomainsHygieneReport.ps1` and
`validate/Test-AcceptedDomainsHygieneReport.ps1` make is read-only (`Get-AcceptedDomain`,
optionally `Search-UnifiedAuditLog`). "Rollback" here means three things, none of which touch the
tenant's Exchange or Purview configuration:

1. Stop the scheduled execution of `deploy/Export-AcceptedDomainsHygieneReport.ps1`.
2. Remove the automation identity's Exchange Online role assignment.
3. Decide what to do with the already-produced baseline, drift-log, and findings files.

## 1. Stop the schedule

This scenario ships no scheduler-specific code (`README.md` §5) — remove or disable whatever
recurring-execution mechanism was wired up (an Azure Automation runbook, a scheduled Azure Function,
a cron entry, or a Windows Task Scheduler task) using that platform's own removal procedure. There is
nothing Exchange- or Purview-side to undo as part of this step.

## 2. Remove the automation identity's role assignment

Remove whatever Exchange Online role/role group (`README.md` §3 — Organization Management or a
narrower custom role group, per `docs/rbac-model.md` §6/§14) was assigned to the service principal or
account running this scenario's scripts. Standard Exchange Online role-group membership removal
(`Remove-RoleGroupMember`, or the Exchange admin center equivalent) — no scenario-specific step. If
`-IncludeAuditAttribution` was used, also confirm the identity has no residual audit-log-search role
it doesn't need elsewhere.

If the app registration itself is no longer needed for any other purpose in this repo, also revoke
or delete its client secret/certificate — standard Entra app-registration hygiene, not specific to
this scenario.

## 3. Decide the fate of already-produced report files

- **Baseline JSON, drift-log CSV, and per-run findings JSON files** (wherever `-BaselinePath`/
  `-DriftLogPath` pointed, and the same directory for findings files) are ordinary files this
  scenario wrote outside of Exchange/Purview — delete them, archive them, or leave them in place per
  the buyer's own data-retention policy. There is no Exchange- or Purview-side artifact tied to them
  that would become orphaned or inconsistent if they're kept after the automation identity's role is
  removed.
- If the drift log or baseline was committed to a source-control repository (the recommended pattern
  for preserving history — `README.md` §4/§8), treat its removal like removing any other tracked
  file: a deliberate commit, not an ad hoc delete, so the historical drift record isn't silently lost
  without a decision to do so.
- **The known-domains config** (`deploy/KnownDomains.json`, edited from the sample) is buyer-owned
  policy content, not a generated artifact — keep it regardless of whether the rest of this scenario
  is decommissioned; it has value as a documented record of which domains were reviewed and approved,
  independent of whether the automated check keeps running.

## What rollback does **not** undo

- **Any Exchange or Purview object.** There isn't one — see "What there is to roll back," above.
  Removing this scenario's automation has zero effect on the tenant's actual accepted-domains
  configuration, DLP policies, or any rule that consumes `FromScope`/`ExceptIfFromScope`.
- **Findings already surfaced.** If a prior run reported a `MissingExpectedDomain` or
  `UnexpectedTrustedDomain` finding, that underlying condition (a domain the buyer's DLP rules are
  currently mistreating) is unaffected by removing this scenario's monitoring — rollback stops future
  detection, it doesn't retroactively fix what was already found. Confirm any open finding has been
  addressed (or consciously accepted) before decommissioning the check that surfaces it.

## Re-enabling later

Re-running `deploy/Export-AcceptedDomainsHygieneReport.ps1` after a rollback is safe at any time:
re-assign the Exchange Online role (step 2, reversed), point `-BaselinePath`/`-DriftLogPath` at
either fresh files or the previously-archived ones, and resume scheduling. If the baseline file was
kept, the very next run resumes normal Added/Removed/Changed drift detection immediately; if it was
deleted, the next run is treated as a first run (`design.md` §4) — no findings are reported as drift
until a new baseline has been recorded, so a re-enablement after a long gap should be followed by a
second run soon after (e.g. the next day) to re-establish real drift detection rather than relying on
a single first-run snapshot.
