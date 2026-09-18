---
part: "rollback"
parent: "data-map/scan-credential-inventory-report"
---
## What there is to roll back

Like [`data-estate-insights/classification-coverage-report`](/scenarios/data-estate-insights/classification-coverage-report/), this scenario creates **no
object inside Microsoft Purview at all** — no credential, no Key Vault connection, no scan. Every
call it makes is a read-only `GET /scan/credentials`. "Rollback" here means four things, none of
which touch the Purview account itself or any credential it reports on:

1. Stop the scheduled execution of `deploy/Export-CredentialInventoryReport.ps1`.
2. Remove the reporting service principal's **Data Reader** role assignment.
3. Decide what to do with the already-produced trend-log CSV and drift-report JSON files.
4. Decide what to do with the checked-in expected-state file.

## 1. Stop the schedule

This scenario ships no scheduler-specific code (`README.md` §5) — remove or disable whatever
recurring-execution mechanism was wired up, using that platform's own removal procedure. There is
nothing Purview-side to undo as part of this step.

## 2. Remove the automation identity's role assignment

In the Purview portal: **Data Map** → **Collections** → select the collection(s) the reporting
service principal was granted **Data Reader** on → **Role assignments** → remove the service
principal from the **Data readers** list. This requires the **Collection Admin** role, the same
prerequisite that was needed to grant it (`README.md` §3).

If the app registration itself is no longer needed for any other purpose in this repo, also revoke
or delete its client secret/certificate — standard Entra app-registration hygiene, not specific to
this scenario.

## 3. Decide the fate of already-produced report files

- **Trend-log CSV and per-run drift-report JSON files** (wherever `-TrendLogPath` /
  `-DriftReportDirectory` pointed) are ordinary files this scenario wrote outside of Purview —
  delete them, archive them, or leave them in place per the buyer's own data-retention policy. There
  is no Purview-side artifact tied to them that would become orphaned or inconsistent if they're
  kept after the automation identity's role is removed.
- **Treat these files with the same handling discipline `README.md` §11 describes** — they name Key
  Vault secret names and identity fields (never secret values) for every scan credential in scope,
  which is reconnaissance value even without a single password or key inside them. Don't move them
  to less-protected storage as part of "just archiving" them.
- If the trend log was committed to a source-control repository (the recommended pattern for
  preserving history — `README.md` §4/§8), treat its removal like removing any other tracked file: a
  deliberate commit, not an ad hoc delete.

## 4. Decide the fate of the checked-in expected-state file

The expected-state file (`deploy/policy/expected-credential-inventory.json` or your own copy) is a
source-controlled artifact independent of any live Purview state. If this scenario's automation is
being decommissioned but `scan-credential-key-vault-backed`'s credentials themselves are staying in
place, consider whether the expected-state file should be preserved anyway as a point-in-time record
of "what the credential inventory was supposed to be" at decommission time — useful evidence if a
later, unrelated investigation needs to reconstruct what was approved.

## What rollback does **not** undo

- **Any Purview object.** There isn't one — see "What there is to roll back," above. Removing this
  scenario's automation has zero effect on the credentials, Key Vault connections, or scans it read
  from.
- **The credentials themselves** — entirely owned by `scenarios/data-map/
  scan-credential-key-vault-backed/`, not by this scenario. Rolling back this reporting scenario does
  **not** remove the detective-control gap `README.md` §2 describes reopening — see the next section.

## A rollback of this scenario reopens a named risk

Because this scenario exists specifically to compensate for the "Purview records no audit event for
a credential create/replace/delete" gap (`README.md` §2, `scan-credential-key-vault-backed/README.md`
§11), decommissioning it without a replacement detective control means that gap is open again with
nothing watching it. If rollback is happening because the buyer is replacing this scenario with a
different detection mechanism (e.g. a confirmed `PurviewSecurityLogs` event once that VERIFY closes —
`scan-credential-key-vault-backed/README.md` §11), confirm the replacement is actually in place and
running *before* stopping this scenario's schedule, not after.

## Re-enabling later

Re-running `deploy/Export-CredentialInventoryReport.ps1` after a rollback is safe at any time:
re-assign the Data Reader role (step 2, reversed), point `-TrendLogPath`/`-DriftReportDirectory` at
either fresh files or the previously-archived ones, confirm the expected-state file still reflects
the current intended credential set (it may have fallen behind during the gap), and resume
scheduling. Because this scenario's idempotency model replaces rows by `-RunId` rather than depending
on any created Purview object's existence, there is no "was it fully torn down" ambiguity to resolve
before resuming.
