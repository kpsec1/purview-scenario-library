---
part: "rollback"
parent: "insider-risk/data-leaks-exfiltration-activity-trigger"
---
As with every Insider Risk Management scenario in this library, most of what this scenario
configures lives in the Purview portal, not in an object a script created — most rollback steps
here are portal steps. Staged least-disruptive-first, same reasoning as
`security-policy-violations/rollback.md`. This scenario has **no** DLP policy, HR connector,
Communication Compliance policy, or Microsoft Defender for Endpoint dependency to unwind — the
shortest dependency list of any Data-leaks-family scenario in this library.

## Recommended sequence

### Stage 1 — Narrow scope, raise a threshold, or turn off an optional scoring indicator (reversible, seconds to minutes)

1. Purview portal → **Insider Risk Management** → **Policies** → select `Data Leaks -
   Exfiltration Activity Trigger` → **Edit policy** → narrow/empty the "Users and groups" scope,
   raise a trigger or scoring indicator's threshold (reduces alert volume without disabling the
   policy), or deselect an optional scoring indicator (Communication Compliance content indicators,
   generative-AI indicators, or cloud indicators if enabled).
2. To stop a specific built-in indicator from being usable as a trigger or scoring indicator
   tenant-wide (affecting every policy that uses it, not just this one), turn it off in **Insider
   Risk Management** → **Settings** → **Policy indicators** → **Built-in Indicators** — confirm
   first that no other IRM policy in the tenant also depends on that same indicator remaining on.
3. Deselecting **Cumulative exfiltration detection** or an optional scoring indicator category
   takes effect immediately and is trivially reversible by reselecting it.
4. Switching between default and custom thresholds, or changing a custom threshold's value, is
   reversible at any time — update `deploy/policy/
   data-leaks-exfiltration-activity-trigger-policy-manifest.json` to keep the recorded values in
   sync with whatever the portal actually reflects afterward.

### Stage 2 — Full removal (not reversible without redoing setup)

1. Purview portal → **Insider Risk Management** → **Policies** → select `Data Leaks -
   Exfiltration Activity Trigger` → **Delete policy**.
2. If no other Insider Risk Management policy in the tenant depends on a built-in indicator this
   scenario turned on specifically for its own use, turn it off in **Settings** → **Policy
   indicators** → **Built-in Indicators**. **Do not** turn off an indicator another policy's
   trigger or scoring still depends on — including the DLP-trigger sibling scenario
   (`../data-leaks/`), if also deployed, since both scenarios draw from the same tenant-wide
   Office-indicator category.
3. If the scope-resolution app registration (`GroupMember.Read.All`) or the alert-export app
   registration (`SecurityAlert.Read.All`) are shared with other scenarios in this library, don't
   revoke either while those scenarios still use them.
4. If cloud indicators were enabled and no other Insider Risk Management policy or Defender for
   Cloud Apps use case in the tenant depends on the connection, disconnect it in the Defender
   portal — confirm first, since these connectors are commonly shared across multiple Defender/
   Purview capabilities.
5. **Do not delete the source Entra security group(s)** used for scoping — that group is owned by
   whatever process governs the tenant's role-based groups, not by this scenario.

There is no "undo" for policy deletion — re-establishing the control means re-running the portal
and script steps in `README.md` §5 from scratch, referencing `deploy/policy/
data-leaks-exfiltration-activity-trigger-policy-manifest.json` again as the configuration source
of truth.

## What rollback does **not** undo

- **Alert and case history.** Alerts and cases already generated remain in the Purview portal per
  their own retention policy, regardless of whether the policy that generated them still exists.
- **Risk scores already calculated.** Historical record, not live state.
- **Cloud-app activity already ingested by Defender for Cloud Apps** before a connector was
  disconnected — historical record, not retroactively purged.
- **Audit log entries.** Every action in this scenario (policy edits, indicator-list changes,
  alert activity) is itself an audited event in the Microsoft 365 unified audit log per its own
  retention window.

## Verification after rollback

Re-run the manual checklist section of `validate/
Test-DataLeaksExfiltrationActivityTriggerSetup.ps1` and confirm the Purview portal state matches
the stage you intended. There is no automated way to confirm policy deletion or a tenant-wide
indicator's current enabled/disabled state via script.
