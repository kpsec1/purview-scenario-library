---
part: "rollback"
parent: "insider-risk/departing-employee-data-theft"
---
Unlike the DLP scenarios in this library, most of what this scenario configures lives in the
Purview portal, not in an object a script created, so most rollback steps here are portal
steps, not script invocations. This document is still staged (least-disruptive first) for the
same reason the DLP rollback docs are: don't reach for permanent deletion when a pause will do.

## Recommended sequence

### Stage 1, Pause the policy (reversible, seconds)

1. Purview portal → **Insider Risk Management** → **Policies** → select `Departing Employee
   Data Theft` → **Edit policy** → turn scoring off, or remove all users/groups from scope
   (leaving the policy shell in place).
2. Alternatively, stop the HR data feed without touching the policy: stop scheduling
   `deploy/Send-HrTerminationRecord.ps1` and disable the "User account deleted from Microsoft
   Entra ID" triggering event in the policy. With no triggering event configured, the policy
   stops evaluating new users (existing in-scope users already in their activation window
   continue being scored until that window ends).

Use this stage for: a false-positive-heavy pilot phase that needs to pause without losing
configuration, or a temporary change freeze.

### Stage 2, Disable the HR data feed only (partial rollback)

If the policy and its indicators should keep running against the `User account deleted from
Microsoft Entra ID` fallback trigger, but the HR connector feed should stop (e.g., the source
HR system is being migrated):

1. Stop the scheduled task/pipeline running `deploy/Send-HrTerminationRecord.ps1`.
2. Purview portal → **Settings** → **Data connectors** → select the HR connector → **Pause**
   (or delete, if permanent, see Stage 3).

The policy keeps running on whatever triggering events remain enabled; departing-user coverage
narrows to the Entra-account-deletion fallback only (see design.md §6 for why that alone is a
materially weaker signal, the risk window is not fully closed by this stage).

### Stage 3, Full removal (not reversible without redoing setup)

1. Purview portal → **Insider Risk Management** → **Policies** → select `Departing Employee
   Data Theft` → **Delete policy**.
2. Purview portal → **Settings** → **Data connectors** → select the HR connector → **Delete**.
3. Revoke the HR connector's app registration credential: Microsoft Entra admin center →
   **App registrations** → the app used by `deploy/Send-HrTerminationRecord.ps1` → **Certificates
   & secrets** → delete the client secret (or delete the app registration entirely if it serves
   no other purpose). Do this even if you only completed Stage 1/2 above but are retiring the
   integration, a live, unused secret is a standing credential-leak risk regardless of whether
   the policy/connector that used it still exists.

   To revoke just the secret and keep the app registration (e.g. pausing the integration rather
   than retiring it), use `deploy/Remove-HrConnectorAppSecret.ps1 -KeyId <guid> -Force` (`-Force`
   is required because this deliberately removes a still-valid secret, not merely an expired one
, see that script's own `.PARAMETER Force`). To remove the app registration entirely, same
   `Application.ReadWrite.All` delegated session `deploy/Register-HrConnectorApp.ps1` uses:
   ```powershell
   $app = Get-MgApplication -Filter "displayName eq 'Purview HR Connector - Insider Risk Management (single-purpose)'"
   Remove-MgServicePrincipal -ServicePrincipalId (Get-MgServicePrincipal -Filter "appId eq '$($app.AppId)'").Id
   Remove-MgApplication -ApplicationId $app.Id
   ```
   Deleted applications land in a 30-day recoverable container, not permanent deletion
   immediately, see the Microsoft Graph `Remove-MgApplication` reference.
4. If a priority user group was created for this scenario (README.md §8) and is not reused by
   another policy: Purview portal → **Settings** → **Insider Risk Management** → **Priority
   user groups** → delete it.

There is no "undo" for policy deletion, re-establishing the control means re-running the
portal steps in README.md §5 from scratch, referencing `deploy/policy/
departing-employee-policy-manifest.json` again as the configuration source of truth.

## What rollback does **not** undo

- **Alert and case history.** Alerts and cases already generated remain in the Purview portal
  and Microsoft Defender portal per their own retention policy, regardless of whether the
  policy that generated them still exists. Deleting the policy does not delete past alerts.
- **Risk scores already calculated.** A user's risk score for an activation window that already
  completed is historical record, not live state, pausing or deleting the policy does not
  retroactively un-score it.
- **HR data already ingested.** Resignation records already uploaded via
  `deploy/Send-HrTerminationRecord.ps1` and ingested by the HR connector are not deleted by
  pausing or removing the connector. There is no documented delete/purge API for already-
  ingested HR connector records as of this writing, VERIFY with Microsoft support if a
  compliance obligation requires purging previously uploaded resignation data.
- **Audit log entries.** Every action in this scenario (policy edits, connector changes, alert
  activity) is itself an audited event in the Microsoft 365 unified audit log per its own
  retention window, rollback of the *control* does not roll back the *record that it existed*.

## Verification after rollback

Re-run the manual checklist section of `validate/Test-DepartingEmployeeIrmSetup.ps1` and
confirm the Purview portal state matches the stage you intended (policy paused/removed,
connector paused/removed, app secret revoked). There is no automated way to confirm policy
deletion via script, see design.md §6 for why.
