# Four-Lens Review — Bulk-Grant Azure Synapse Serverless SQL Database Access

Reviewed after the initial draft of `README.md`, `design.md`, `deploy/`, and `validate/`. One round of
findings below; all **Fix** items were applied to the scenario before this file was finalized (see
"Resolution" under each). No **Fail** items were raised.

---

## 🔴 Red Team

**Verdict: Fix (resolved)**

1. **Bulk automation removes the friction that made the manual process self-limiting.** Microsoft's own
   documented walkthrough grants access one database at a time, from inside that database's own Synapse
   Studio SQL-script context - a human necessarily looks at each database before granting it. A single
   run of this scenario's script against the wrong `-ServerlessSqlEndpoint`, or without
   `-ExcludeDatabase` for databases that should stay out of scope, can grant read access across every
   database in a workspace in one shot. The original draft documented `-ExcludeDatabase` and `-Database`
   as available options but didn't call out that the full-workspace default is the riskier choice for a
   workspace mixing sensitivity levels across databases.
   - **Resolution:** `README.md` §5 now carries an explicit callout to always preview with `-WhatIf`
     first and to prefer an explicit `-Database` allow-list over the full-workspace default for a
     first production run on a mixed-sensitivity workspace.
2. **Idempotency checks match by name only, not by a stable identifier.** A pre-existing, unrelated
   principal sharing the same display name as `-PrincipalName` would cause the login/user-existence
   checks to report "already granted" and silently skip the intended grant. Azure Synapse's
   external-provider login model doesn't document an object-ID-pinning mechanism at creation time. The
   original draft didn't disclose this.
   - **Resolution:** `README.md` §11 now states this explicitly as a known limitation, with an honest
     assessment of real-world likelihood (low, but not zero).
3. **`db_datareader` is still a broad read grant relative to "let Purview classify some columns."** Same
   inherent tension the parent scenario's own Red Team review already raised (`scan-azure-synapse-and-
   classify/reviews.md`) - not a new issue this scenario introduces, and not re-litigated here for the
   same reason the parent scenario didn't change its own design over it: the mitigation is process (who
   can run this script, and against which databases), not a scripting change.
   - **Resolution:** Not changed - noted here for visibility, consistent with the parent scenario's own
     disposition of the same finding.

No remaining Fix/Fail after resolution.

---

## 🔵 Blue Team

**Verdict: Fix (resolved)**

1. **No durable audit trail of which run granted which database.** The script's own output is
   console-only (`Write-Host`); nothing is persisted by default. The original draft didn't point to
   Azure SQL/Synapse's own auditing capability as the actual detective control, reading as an oversight
   rather than a disclosed, deliberate scope boundary.
   - **Resolution:** `README.md` §8 now recommends transcript capture for a lightweight run-level
     record and names Azure SQL/Synapse workspace **Auditing** (diagnostic logs) as the authoritative
     detective control this scenario does not configure or verify - a candidate for a future
     cross-cutting Data Map auditing scenario, not built here.
2. **This scenario checks one named principal, not a full inventory of who has access.** Unlike
   `scenarios/data-map/scan-credential-inventory-report/`'s estate-wide drift model for Data Map
   credentials, this scenario's `validate/` script only confirms `-PrincipalName`'s own access - it
   would not surface an unexpected, unrelated login or role membership someone else added directly via
   Synapse Studio.
   - **Resolution:** Not built in this fragment (a materially different, estate-wide reporting shape,
     the same class of scope decision the parent scenario's own credential-inventory follow-up already
     made) - recorded as a follow-up in `PROGRESS.md` rather than silently left unautomated.
3. **No alerting on a failed bulk-grant run.** Same disposition as the parent scenario and every other
   Data Map scenario in this repo: Data Map/Synapse SQL operations have no native `GenerateAlert`-style
   alert stream to route into, so a non-zero exit code plus the operator's own pipeline/scheduler
   failure handling is the correct mechanism, not a gap.
   - **Resolution:** No change needed; confirmed not a gap, consistent with the parent scenario's own
     Blue Team disposition of the same question.

No remaining Fail.

---

## 🎩 CISO

**Verdict: Fix (resolved)**

1. **Change-management impact of one run touching many databases at once.** A change-approval process
   built around reviewing individual grants may not anticipate a single script execution changing
   permissions across an entire workspace's worth of databases. The original draft didn't suggest how to
   fit this into an existing change-management process.
   - **Resolution:** `README.md` §8 now recommends treating a `-WhatIf` preview's printed target list as
     the artifact a change-approval process reviews, rather than approving "run the bulk-grant script"
     as an undifferentiated one-line request.
2. **Risk reduction vs. cost:** high leverage, low cost. This scenario spends automation-engineering
   effort once to remove a cost (manual per-database SQL scripting) that otherwise recurs, and scales
   worse, every time the parent scenario's target workspace gains a database.
3. **Board-level narrative:** "our Synapse classification coverage isn't gated by how much manual SQL
   scripting an operator was willing to do" is a stronger, more durable claim than the parent scenario
   alone supports for a workspace with many serverless databases.
4. **Licensing spend:** none - this scenario uses only Azure Synapse's own RBAC/T-SQL surface, no
   incremental Purview or Microsoft 365 entitlement (`README.md` §10).
5. **Would I fund this?** Yes - the finding above (change-management fit) is a process adjustment, not a
   reason to withhold the automation; the parent scenario's own CISO review already flagged the manual
   cost as a real, scaling problem worth solving.

No remaining Fix/Fail after resolution.

---

## 🟦 Microsoft Product Owner

**Verdict: Fix (resolved)**

1. **Is this reinventing a native Microsoft capability?** Checked directly during this build's grounding
   pass: Microsoft's own documentation for both the enumeration login and the per-database grant steps
   consistently directs operators to "run SQL scripts" against each database, with no ARM template,
   `Az.Synapse` cmdlet, or portal bulk-action found that performs this specific operation across
   multiple databases in one call. `Az.Synapse`'s `New-AzSynapseRoleAssignment` manages Synapse
   **workspace RBAC roles** (e.g. Synapse Administrator) - a different, adjacent system from the
   database-level `db_datareader` grant this scenario automates, not a substitute for it. Confirmed: no
   native capability is being duplicated.
   - **Resolution:** `design.md` §3 now notes this distinction explicitly rather than leaving it
     unstated.
2. **`db_datareader` via `ALTER ROLE ... ADD MEMBER` (not `sp_addrolemember`) is the current, correct
   mechanism for serverless SQL pool databases** - confirmed directly against Microsoft's own
   `register-scan-synapse-workspace` worked example, which uses `ALTER ROLE` for serverless and reserves
   `sp_addrolemember` for the dedicated-pool branch. This scenario's script matches that split exactly,
   not by assumption.
3. **The server-scoped-vs-per-database correction (design.md §4) is itself a Product Owner-relevant
   finding**, since it corrects a documented, already-shipped sibling scenario's framing. Independently
   confirmed against two separate, directly-fetched Microsoft Learn pages rather than a single source -
   see `design.md` §4 for both citations.
4. **No deprecated cmdlets/endpoints used.** `CREATE LOGIN`/`CREATE USER`/`ALTER ROLE` are current,
   non-deprecated T-SQL; `Invoke-Sqlcmd -AccessToken` is Microsoft's own currently-documented pattern
   for app-only Azure SQL/Synapse connections.
5. **Licensing citation accuracy** - confirmed: no incremental licensing, consistent with `README.md`
   §10.

No remaining Fail after resolution.

---

## Summary

| Lens | Initial verdict | Findings | Resolution |
|---|---|---|---|
| 🔴 Red Team | Fix | 3 (2 closed via documentation additions, 1 confirmed as an inherent trust-model note carried from the parent scenario) | Closed |
| 🔵 Blue Team | Fix | 3 (1 closed via documentation addition, 1 follow-up recorded, 1 confirmed correctly scoped) | Closed |
| 🎩 CISO | Fix | 1 closed (change-management guidance added); Pass on all other dimensions | Closed |
| 🟦 Microsoft Product Owner | Fix | 1 closed (native-capability distinction made explicit); 4 confirmed correct | Closed |

All Fix items from this round are resolved in the current state of `README.md`, `design.md`,
`deploy/Grant-SynapseServerlessDatabaseAccess.ps1`, and
`validate/Test-SynapseServerlessDatabaseAccess.ps1`. No Fail items were raised. This fragment meets the
definition of done in `AGENTS.md` §9.
