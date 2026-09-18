---
part: "rollback"
parent: "insider-risk/security-policy-violations"
---
As with the departing-users sibling, most of what this scenario configures lives in the Purview or
Microsoft Defender portal, not in an object a script created, most rollback steps here are portal
steps. Staged least-disruptive-first, same reasoning as
`security-policy-violations-by-departing-users/rollback.md`.

## Recommended sequence

### Stage 1, Narrow or pause the scope (reversible, seconds)

1. Purview portal → **Insider Risk Management** → **Policies** → select `Security Policy
   Violations` → **Edit policy** → remove some or all users/groups from scope (leaving the policy
   shell in place). Because this template has no triggering-event toggle to disable separately
   (§5 Step 4 of `README.md`, the Defender for Endpoint alert itself is the trigger), narrowing or
   emptying the scope is the only lightweight pause mechanism this template offers, unlike the
   departing-users sibling's option to turn off its triggering events instead.

### Stage 2, Disable the Defender for Endpoint alert-sharing feature only (partial rollback)

If this policy (and any other "Security policy violations…" family policy) should keep running,
but Defender for Endpoint alert sharing into Purview should stop entirely (e.g., as part of a
Defender for Endpoint tenant migration):

1. Microsoft Defender portal → **Settings** → **Endpoints** → **Advanced features** → toggle
   **Share endpoint alerts with Microsoft Compliance Center** to **Off** → **Save preferences**.

This stops **all** Insider Risk Management security-violation-family policies in the tenant from
receiving new Defender for Endpoint alerts, not just this scenario's policy, since the toggle is
tenant-wide, not per-policy. Confirm no other "Security policy violations…" policy depends on it
before disabling (identical coupling to the departing-users sibling's `rollback.md` Stage 2).

### Stage 3, Full removal (not reversible without redoing setup)

1. Purview portal → **Insider Risk Management** → **Policies** → select `Security Policy
   Violations` → **Delete policy**.
2. If the "Share endpoint alerts with Microsoft Compliance Center" feature was enabled solely for
   this scenario and no other security-violation-family policy in the tenant needs it, disable it
   per Stage 2 as well.
3. Revoke the scope-resolution app registration's certificate if it serves no other purpose, 
   Microsoft Entra admin center → **App registrations** → the app used by
   `deploy/Get-SecurityPolicyViolationsScopeCandidates.ps1` → **Certificates & secrets**. If the
   alert-export app registration was reused from the departing-users sibling
   (`SecurityAlert.Read.All`), don't revoke it while that scenario still uses it.
4. **Do not delete the source Entra security group(s)** used for scoping as part of removing this
   scenario, that group is owned by whatever process governs the tenant's role-based groups
   (`design.md` §7), not by this scenario, and is very likely used for purposes unrelated to this
   policy.

There is no "undo" for policy deletion, re-establishing the control means re-running the portal
steps in `README.md` §5 from scratch, referencing
`deploy/policy/security-policy-violations-policy-manifest.json` again as the configuration source
of truth.

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

Re-run the manual checklist section of `validate/Test-SecurityPolicyViolationsIrmSetup.ps1` and
confirm the Purview and Microsoft Defender portal state matches the stage you intended. There is no
automated way to confirm policy deletion or advanced-feature state via script, see `design.md` §4
for why.
