---
part: "rollback"
parent: "insider-risk/security-policy-violations-by-risky-users"
---
As with every sibling in this template family, most of what this scenario configures lives in the
Purview, Microsoft Defender, or Communication Compliance portal, not in an object a script created
, most rollback steps here are portal steps. Staged least-disruptive-first, same reasoning as
`security-policy-violations/rollback.md` and the other siblings' own `rollback.md`. This scenario
adds **two** extra objects versus the base template's rollback: the dedicated HR connector, and (if
enabled) the auto-created Communication Compliance policy.

## Recommended sequence

### Stage 1, Disable one trigger path, or narrow scope (reversible, seconds to minutes)

1. Purview portal → **Insider Risk Management** → **Policies** → select `Security Policy
 Violations by Risky Users` → **Edit policy** → disable one of the two triggering-event paths
 (HR connector or Communication Compliance integration), or narrow/empty the "Users and groups"
 scope, leaving the policy shell and both underlying objects in place. Unlike the base/
 priority-users siblings (which have no triggering-event toggle at all), this template's HR and
 Communication Compliance paths can each be turned off independently without touching the other,
 the same partial-pause flexibility the departing-users sibling's own two optional triggers
 offer.
2. Alternatively, stop running `deploy/Send-HrRiskIndicatorRecord.ps1` on its scheduled cadence
 (e.g., disable the scheduled task) without touching the connector or policy object at all, new
 HR signal simply stops arriving, a reversible, non-destructive pause.

### Stage 2, Disable the Defender for Endpoint alert-sharing feature only (partial rollback)

If this policy (and any other "Security policy violations…" family policy) should keep running,
but Defender for Endpoint alert sharing into Purview should stop entirely (e.g., as part of a
Defender for Endpoint tenant migration):

1. Microsoft Defender portal → **Settings** → **Endpoints** → **Advanced features** → toggle
 **Share endpoint alerts with Microsoft Compliance Center** to **Off** → **Save preferences**.

This stops **all** Insider Risk Management security-violation-family policies in the tenant from
receiving new Defender for Endpoint alerts, not just this scenario's policy, since the toggle is
tenant-wide, not per-policy. Confirm no other "Security policy violations…" policy depends on it
before disabling (identical coupling to every sibling's own `rollback.md` Stage 2).

### Stage 3, Full removal (not reversible without redoing setup)

1. Purview portal → **Insider Risk Management** → **Policies** → select `Security Policy
 Violations by Risky Users` → **Delete policy**.
2. If Communication Compliance integration was enabled, Communication Compliance → **Policies** →
 select the auto-created dedicated "Detect inappropriate text" policy (name per README.md §11's
 disclosed naming inconsistency, confirm the actual live name before selecting) → **Delete**, 
 **only** if no other Insider Risk Management policy in the tenant depends on this same dedicated
 Communication Compliance policy. Deleting the IRM policy in step 1 does not automatically delete
 it.
3. Purview portal → **Settings** → **Data connectors** → **My connectors** → select the dedicated
 HR connector created for this scenario (§5 Step 2, **not** the departing-employee-data-theft
 sibling's Resignation-scoped connector) → delete/decommission it, **only** if no other policy or
 process consumes its imported data.
4. If the "Share endpoint alerts with Microsoft Compliance Center" feature was enabled solely for
 this scenario and no other security-violation-family policy in the tenant needs it, disable it
 per Stage 2 as well.
5. Revoke the HR-connector app registration's certificate/secret if it serves no other purpose, 
 Microsoft Entra admin center → **App registrations** → the app registered via
 `../security-policy-violations-by-departing-users/../departing-employee-data-theft/deploy/
 Register-HrConnectorApp.ps1` with this scenario's own `-DisplayName` → **Certificates &
 secrets**. **Do not** revoke the departing-employee-data-theft sibling's own, separate app
 registration, this scenario provisioned its own (design.md §2 goal 4).
6. If the scope-resolution app registration (`GroupMember.Read.All`) or the alert-export app
 registration (`SecurityAlert.Read.All`) are shared with the base or departing-users siblings,
 don't revoke either while those scenarios still use them.
7. **Do not delete the source Entra security group(s)** used for scoping as part of removing this
 scenario, that group is owned by whatever process governs the tenant's role-based groups
 (`design.md` §7), not by this scenario, and is very likely used for purposes unrelated to this
 policy.

There is no "undo" for policy, HR-connector, or Communication-Compliance-policy deletion, 
re-establishing the control means re-running the portal and script steps in `README.md` §5 from
scratch, referencing `deploy/policy/security-policy-violations-risky-users-policy-manifest.json`
again as the configuration source of truth.

## What rollback does **not** undo

- **Alert and case history.** Alerts and cases already generated remain in the Purview portal and
 Microsoft Defender portal per their own retention policy, regardless of whether the policy, HR
 connector, or Communication Compliance policy that generated them still exists.
- **Risk scores already calculated.** Historical record, not live state.
- **Defender for Endpoint alerts already shared with Purview** before the feature was disabled, 
 those records are not retroactively purged.
- **HR risk-indicator records already ingested by the HR connector**, or **Communication Compliance
 alerts already generated**, both remain in Microsoft's cloud per their own retention policy,
 independent of whether the connector or policy that consumed them still exists.
- **Audit log entries.** Every action in this scenario (policy edits, connector/policy creation and
 deletion, advanced-feature toggle changes, alert activity) is itself an audited event in the
 Microsoft 365 unified audit log per its own retention window.

## Verification after rollback

Re-run the manual checklist section of `validate/Test-RiskyUsersIrmSetup.ps1` and confirm the
Purview, Microsoft Defender, and Communication Compliance portal state matches the stage you
intended. There is no automated way to confirm policy, HR-connector, or Communication-Compliance-
policy deletion or state via script, see `design.md` §2 goal 7 for why.
