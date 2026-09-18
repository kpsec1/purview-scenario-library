---
part: "rollback"
parent: "insider-risk/data-leaks-by-priority-users"
---
As with every Insider Risk Management scenario in this library, most of what this scenario
configures lives in the Purview portal, not in an object a script created, most rollback steps
here are portal steps. Staged least-disruptive-first, same reasoning as `../data-leaks/rollback.md`
and `../security-policy-violations-by-priority-users/rollback.md`. This scenario has **no** HR
connector, Communication Compliance trigger policy, or Microsoft Defender for Endpoint dependency
to unwind, fewer moving parts than either HR-connector-triggered sibling in this family.

## Recommended sequence

### Stage 1, Narrow scope, disable the booster, remove a DLP policy, or turn off an optional indicator (reversible, seconds)

1. Purview portal → **Insider Risk Management** → **Policies** → select `Data Leaks by Priority
 Users` → **Edit policy** → remove members from the priority user group itself (leaving both the
 policy and the group shell in place), deselect the **"User is a member of a priority user
 group"** risk score booster (removes the scoring boost while leaving the population and the
 policy otherwise unchanged, a lightweight, fully reversible partial rollback unique to this
 template), or deselect an optional indicator (Communication Compliance content indicators or
 generative-AI indicators, if enabled).
2. If using the DLP-policy trigger, remove the specific DLP policy from **Insider Risk Management**
 → **Settings** → **Policy indicators** → **DLP alerts indicators**, but confirm first that no
 *other* IRM policy in the tenant (including a `Data leaks`, `Data leaks by risky users`, or
 `Data theft by departing users` policy) also relies on that same DLP policy being in the global
 list.
3. Edit the priority user group's own **reviewer permissions** without touching membership or the
 policy at all, if the goal is only to change who can see this population's alerts.
4. Deselecting **Cumulative exfiltration detection** or an optional indicator category takes
 effect immediately and is trivially reversible by reselecting it.

### Stage 2, Full removal (not reversible without redoing setup)

1. Purview portal → **Insider Risk Management** → **Policies** → select `Data Leaks by Priority
 Users` → **Delete policy**.
2. Purview portal → **Settings** → **Insider Risk Management** → **Priority user groups** → select
 the priority user group → **Delete**, **only** if no other policy in the tenant also
 references this same priority user group (e.g., a `Security policy violations by priority
 users` policy sharing the same population). A priority user group is a standalone object;
 deleting the policy in step 1 does not automatically delete it.
3. If no other IRM policy in the tenant uses the DLP-alerts indicator, remove every DLP policy this
 scenario added from **Settings** → **Policy indicators** → **DLP alerts indicators**. **Do not**
 remove a DLP policy that another IRM policy's trigger still depends on.
4. **Do not delete or modify the parent DLP policy/policies themselves**, they are independently
 owned, pre-existing objects this scenario only ever read.
5. If the DLP-policy readiness check's automation identity, the priority-group candidate-resolution
 app registration (`GroupMember.Read.All`), or the alert-export app registration
 (`SecurityAlert.Read.All`) are shared with other scenarios in this library, don't revoke any of
 them while those scenarios still use them.
6. **Do not delete the source Entra security group(s)** used to build the candidate CSV as part of
 removing this scenario, that group is owned by whatever process governs the tenant's role-based
 groups, not by this scenario.

There is no "undo" for policy or priority-user-group deletion, re-establishing the control means
re-running the portal steps in `README.md` §5 from scratch, referencing `deploy/policy/
data-leaks-priority-users-policy-manifest.json` again as the configuration source of truth.
Re-creating the priority user group also means redoing the reviewer-permission assignment, that
scoping is not retained anywhere outside the deleted object.

## What rollback does **not** undo

- **Alert and case history.** Alerts and cases already generated remain in the Purview portal per
 their own retention policy, regardless of whether the policy or priority user group that
 generated them still exists.
- **Risk scores already calculated.** Historical record, not live state.
- **The parent DLP policy's own alert/incident history**, if the DLP trigger was used, independent
 of this scenario, unaffected by anything this scenario's rollback does.
- **Audit log entries.** Every action in this scenario (policy edits, priority-user-group
 membership/reviewer-permission changes, DLP-indicator-list changes, alert activity) is itself an
 audited event in the Microsoft 365 unified audit log per its own retention window.

## Verification after rollback

Re-run the manual checklist section of `validate/Test-DataLeaksPriorityUsersIrmSetup.ps1` and
confirm the Purview portal state matches the stage you intended. There is no automated way to
confirm policy deletion, priority-user-group deletion/membership, the risk score booster's current
state, or the DLP-alerts indicator list's current state via script.
