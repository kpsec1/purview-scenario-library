---
part: "rollback"
parent: "insider-risk/data-leaks-custom-indicator-trigger"
---
As with every Insider Risk Management scenario in this library, most of what this scenario configures
lives in the Purview portal, not in an object a script created — most rollback steps here are portal
steps. Staged least-disruptive-first, same reasoning as `security-policy-violations/rollback.md`. This
scenario additionally has an **upload pipeline** (a scheduled script + an Entra app registration) that
neither sibling Data-leaks-template scenario in this library has to unwind, since both are portal-only
trigger mechanisms with no external data feed.

## Recommended sequence

### Stage 1 — Pause the upload pipeline, narrow scope, raise a threshold, or turn off scoring (reversible, seconds to minutes)

1. **Stop the scheduled task** running `deploy/Send-InsiderRiskIndicatorRecord.ps1` (Windows Task
   Scheduler, or whatever scheduler was used) — the fastest, fully reversible way to stop new data from
   flowing in without touching any portal configuration. Existing already-ingested data and any alerts
   already generated are unaffected.
2. Purview portal → **Insider Risk Management** → **Policies** → select the policy → **Edit policy** →
   narrow/empty the "Users and groups" scope, raise a custom indicator's trigger or scoring threshold
   (reduces alert volume without disabling the policy), or deselect a custom indicator from the
   **Indicators** page while leaving it as a trigger (or vice versa).
3. Deselecting **Cumulative exfiltration detection** or **Office indicators** takes effect immediately
   and is trivially reversible by reselecting it.
4. Changing a custom threshold's value is reversible at any time — update `deploy/policy/
   data-leaks-custom-indicator-trigger-policy-manifest.json` to keep the recorded values in sync with
   whatever the portal actually reflects afterward. Remember the **24-hour sync wait** (§5 Step 8/§8)
   applies to this change too before resuming uploads.

### Stage 2 — Full removal (not reversible without redoing setup)

1. **Stop the scheduled upload task** first, if not already done in Stage 1 — avoids a race where new
   data arrives mid-teardown.
2. Purview portal → **Insider Risk Management** → **Policies** → select the policy → **Delete policy**.
3. Purview portal → **Insider Risk Management** → **Settings** → **Policy indicators** → **Custom
   Indicators** tab → delete each custom indicator this scenario created, **only if** no other Insider
   Risk Management policy in the tenant still uses it.
4. Purview portal → **Settings** → **Data connectors** → **My connectors** → select the Insider Risk
   Indicators connector this scenario created → delete it, **only if** no other custom indicator still
   references it.
5. If the Entra app registration (`Register-HrConnectorApp.ps1`'s output) is not shared with the
   HR-connector sibling scenario or any other scenario in this library, revoke its client secret or
   delete the app registration. **Do not** revoke it while the HR-connector sibling scenario (or any
   other scenario using the same app) still depends on it — confirm first, since this repo's convention
   is to reuse this script's output by `-DisplayName`, and two scenarios sharing an app registration by
   mistake is a real, easy error to make if `-DisplayName` wasn't kept distinct between them.
6. If the scope-resolution app registration (`GroupMember.Read.All`) or the alert-export app
   registration (`SecurityAlert.Read.All`) are shared with other scenarios in this library, don't revoke
   either while those scenarios still use them.
7. **Do not delete the source Entra security group(s)** used for scoping — that group is owned by
   whatever process governs the tenant's role-based groups, not by this scenario.

There is no "undo" for policy, custom-indicator, or connector deletion — re-establishing the control
means re-running the portal and script steps in `README.md` §5 from scratch, referencing `deploy/policy/
data-leaks-custom-indicator-trigger-policy-manifest.json` again as the configuration source of truth.

## What rollback does **not** undo

- **Alert and case history.** Alerts and cases already generated remain in the Purview portal per their
  own retention policy, regardless of whether the policy, indicator, or connector that generated them
  still exists.
- **Risk scores already calculated.** Historical record, not live state.
- **Data already ingested by the connector** before it was deleted — historical record, not
  retroactively purged from wherever Insider Risk Management stored it.
- **Whatever the third-party CASB/DLP/SIEM tool itself has recorded** — entirely outside this scenario's
  or Microsoft's control; that tool's own data-retention policy governs it.
- **Audit log entries.** Every action in this scenario (connector creation/deletion, indicator changes,
  policy edits, alert activity) is itself an audited event in the Microsoft 365 unified audit log per its
  own retention window.

## Verification after rollback

Re-run the manual checklist section of `validate/Test-DataLeaksCustomIndicatorTriggerSetup.ps1` and
confirm the Purview portal state matches the stage you intended. Confirm the scheduled upload task's
last-run status separately (it has no portal-visible state of its own once the connector it targeted is
deleted — a run against a deleted connector will fail, which is expected, not a bug, during Stage 2
teardown). There is no automated way to confirm policy, indicator, or connector deletion via script.
