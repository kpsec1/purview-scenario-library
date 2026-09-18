---
part: "rollback"
parent: "insider-risk/data-leaks"
---
As with every Insider Risk Management scenario in this library, most of what this scenario
configures lives in the Purview portal, not in an object a script created, most rollback steps
here are portal steps. Staged least-disruptive-first, same reasoning as
`security-policy-violations/rollback.md`. This scenario has **no** HR connector, Communication
Compliance policy, or Microsoft Defender for Endpoint dependency to unwind, fewer moving parts
than its `data-leaks-by-risky-users` sibling.

## Recommended sequence

### Stage 1, Narrow scope, remove a DLP policy from the trigger, or turn off an optional indicator (reversible, seconds to minutes)

1. Purview portal → **Insider Risk Management** → **Policies** → select `Data Leaks` → **Edit
   policy** → narrow/empty the "Users and groups" scope, remove one or more DLP policies from the
   triggering-event list, or deselect an optional indicator (Communication Compliance content
   indicators, generative-AI indicators, or cloud indicators if enabled), leaving the policy
   shell and the core Office-indicator scoring in place.
2. To pause the DLP-policy trigger without editing this policy at all, remove the specific DLP
   policy from **Insider Risk Management** → **Settings** → **Policy indicators** → **DLP alerts
   indicators**, but confirm first that no *other* IRM policy in the tenant also relies on that
   same DLP policy being in the global list (§8's coordination note in `README.md`).
3. Deselecting **Cumulative exfiltration detection** or an optional indicator category takes
   effect immediately and is trivially reversible by reselecting it.

### Stage 2, Full removal (not reversible without redoing setup)

1. Purview portal → **Insider Risk Management** → **Policies** → select `Data Leaks` → **Delete
   policy**.
2. If no other IRM policy in the tenant uses the DLP-alerts indicator, remove every DLP policy
   this scenario added from **Settings** → **Policy indicators** → **DLP alerts indicators**.
   **Do not** remove a DLP policy that another IRM policy's trigger still depends on.
3. **Do not delete or modify the parent DLP policy/policies themselves** as part of removing this
   scenario, they are independently owned, pre-existing objects this scenario only ever read
   (`design.md` §7). Removing them would affect whatever DLP protection they provide on their own,
   unrelated to this scenario's trigger wiring.
4. If the DLP-policy readiness check's automation identity, the scope-resolution app registration
   (`GroupMember.Read.All`), or the alert-export app registration (`SecurityAlert.Read.All`) are
   shared with other scenarios in this library, don't revoke any of them while those scenarios
   still use them.
5. If cloud indicators were enabled and no other Insider Risk Management policy or Defender for
   Cloud Apps use case in the tenant depends on the connection, disconnect it in the Defender
   portal, confirm first, since these connectors are commonly shared across multiple Defender/
   Purview capabilities.
6. **Do not delete the source Entra security group(s)** used for scoping, that group is owned by
   whatever process governs the tenant's role-based groups, not by this scenario.

There is no "undo" for policy deletion, re-establishing the control means re-running the portal
and script steps in `README.md` §5 from scratch, referencing `deploy/policy/
data-leaks-policy-manifest.json` again as the configuration source of truth.

## What rollback does **not** undo

- **Alert and case history.** Alerts and cases already generated remain in the Purview portal per
  their own retention policy, regardless of whether the policy that generated them still exists.
- **Risk scores already calculated.** Historical record, not live state.
- **The parent DLP policy's own alert/incident history**, independent of this scenario, and
  unaffected by anything this scenario's rollback does.
- **Cloud-app activity already ingested by Defender for Cloud Apps** before a connector was
  disconnected, historical record, not retroactively purged.
- **Audit log entries.** Every action in this scenario (policy edits, indicator-list changes,
  alert activity) is itself an audited event in the Microsoft 365 unified audit log per its own
  retention window.

## Verification after rollback

Re-run the manual checklist section of `validate/Test-DataLeaksIrmSetup.ps1` and confirm the
Purview portal state matches the stage you intended. There is no automated way to confirm policy
deletion or the DLP-alerts indicator list's current state via script.
