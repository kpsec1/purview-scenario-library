---
part: "rollback"
parent: "insider-risk/security-policy-violations-by-departing-users"
---
As with the sibling scenario, most of what this scenario configures lives in the Purview or
Microsoft Defender portal, not in an object a script created, most rollback steps here are
portal steps. Staged least-disruptive-first, same reasoning as `departing-employee-data-theft/
rollback.md`.

## Recommended sequence

### Stage 1, Pause the policy (reversible, seconds)

1. Purview portal → **Insider Risk Management** → **Policies** → select `Security Policy
 Violations by Departing Users` → **Edit policy** → turn scoring off, or remove all
 users/groups from scope (leaving the policy shell in place).
2. Alternatively, leave the policy in place but turn off both triggering events, with no
 triggering event configured, the policy stops evaluating new users (existing in-scope users
 already in their activation window continue being scored until it ends).

### Stage 2, Disable the Defender for Endpoint alert-sharing feature only (partial rollback)

If this policy and the sibling Data theft policy should keep running, but Defender for Endpoint
alert sharing into Purview should stop (e.g., as part of a Defender for Endpoint tenant
migration):

1. Microsoft Defender portal → **Settings** → **Endpoints** → **Advanced features** → toggle
 **Share endpoint alerts with Microsoft Compliance Center** to **Off** → **Save preferences**.

This stops **all** Insider Risk Management security-violation-family policies in the tenant from
receiving new Defender for Endpoint alerts, not just this scenario's policy, since the toggle
is tenant-wide, not per-policy. Confirm no other "Security policy violations…" policy depends on
it before disabling.

### Stage 3, Full removal (not reversible without redoing setup)

1. Purview portal → **Insider Risk Management** → **Policies** → select `Security Policy
 Violations by Departing Users` → **Delete policy**.
2. **Do not** delete the HR connector or its app registration as part of removing *this*
 scenario alone if `departing-employee-data-theft`'s policy still depends on it, that
 connector is shared (`design.md` §2 goal 1). Only follow that scenario's own `rollback.md`
 Stage 3 connector-removal steps once **both** policies that consume it are being retired.
3. If the "Share endpoint alerts with Microsoft Compliance Center" feature was enabled solely for
 this scenario and no other security-violation-family policy in the tenant needs it, disable it
 per Stage 2 as well.
4. Revoke the alert-export app registration's certificate if it serves no other purpose, 
 Microsoft Entra admin center → **App registrations** → the app used by
 `deploy/Export-SecurityViolationInsiderRiskAlerts.ps1` → **Certificates & secrets**. If this
 app registration is shared with the sibling scenario's `Export-InsiderRiskAlerts.ps1` (the
 same `SecurityAlert.Read.All` permission serves both), don't revoke it while that scenario
 still uses it.

There is no "undo" for policy deletion, re-establishing the control means re-running the portal
steps in README.md §5 from scratch, referencing `deploy/policy/
security-policy-violations-departing-users-policy-manifest.json` again as the configuration
source of truth.

## What rollback does **not** undo

- **Alert and case history.** Alerts and cases already generated remain in the Purview portal and
 Microsoft Defender portal per their own retention policy, regardless of whether the policy that
 generated them still exists.
- **Risk scores already calculated.** Historical record, not live state.
- **Defender for Endpoint alerts already shared with Purview** before the feature was disabled, 
 those records are not retroactively purged.
- **Audit log entries.** Every action in this scenario (policy edits, advanced-feature toggle
 changes, alert activity) is itself an audited event in the Microsoft 365 unified audit log per
 its own retention window.

## Verification after rollback

Re-run the manual checklist section of `validate/Test-SecurityViolationIrmSetup.ps1` and confirm
the Purview and Microsoft Defender portal state matches the stage you intended. There is no
automated way to confirm policy deletion or advanced-feature state via script, see `design.md`
§4 for why.
