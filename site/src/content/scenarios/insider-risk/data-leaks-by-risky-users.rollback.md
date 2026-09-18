---
part: "rollback"
parent: "insider-risk/data-leaks-by-risky-users"
---
As with every Insider Risk Management scenario in this library, most of what this scenario
configures lives in the Purview or Communication Compliance portal, not in an object a script
created, most rollback steps here are portal steps. Staged least-disruptive-first, same reasoning
as `security-policy-violations/rollback.md` and this template's own
`security-policy-violations-by-risky-users/rollback.md`. Unlike that sibling, this scenario has
**no** Microsoft Defender for Endpoint dependency to stage a rollback around, one fewer coupling
to manage.

## Recommended sequence

### Stage 1, Disable one trigger path, narrow scope, or turn off an optional indicator (reversible, seconds to minutes)

1. Purview portal → **Insider Risk Management** → **Policies** → select `Data Leaks by Risky
 Users` → **Edit policy** → disable one of the two triggering-event paths (HR connector or
 Communication Compliance integration), narrow/empty the "Users and groups" scope, or deselect an
 optional indicator (Communication Compliance content indicators, generative-AI indicators, or
 cloud indicators if enabled), leaving the policy shell, both underlying trigger objects, and
 the core Office-indicator scoring in place.
2. Alternatively, stop running
 `../security-policy-violations-by-risky-users/deploy/Send-HrRiskIndicatorRecord.ps1` on its
 scheduled cadence (e.g., disable the scheduled task) without touching the connector or policy
 object at all, new HR signal simply stops arriving, a reversible, non-destructive pause.
3. If cloud indicators were enabled, disconnecting the relevant app in Microsoft Defender for Cloud
 Apps (Settings → Cloud Apps → App Connectors) stops that specific indicator source without
 affecting Office indicators, cumulative exfiltration detection, or either trigger path.

### Stage 2, Full removal (not reversible without redoing setup)

1. Purview portal → **Insider Risk Management** → **Policies** → select `Data Leaks by Risky
 Users` → **Delete policy**.
2. If Communication Compliance integration was enabled, Communication Compliance → **Policies** →
 select the auto-created dedicated "Detect inappropriate text" policy (name per README.md §11's
 disclosed naming inconsistency, confirm the actual live name before selecting) → **Delete**, 
 **only** if no other Insider Risk Management policy in the tenant depends on this same dedicated
 Communication Compliance policy. Deleting the IRM policy in step 1 does not automatically delete
 it.
3. Purview portal → **Settings** → **Data connectors** → **My connectors** → select the dedicated
 HR connector created for this scenario (README.md §5 Step 2, **not** the
 departing-employee-data-theft sibling's Resignation-scoped connector, and **not** the
 security-policy-violations-by-risky-users sibling's own dedicated risk-indicator connector) →
 delete/decommission it, **only** if no other policy or process consumes its imported data.
4. Revoke the HR-connector app registration's certificate/secret if it serves no other purpose, 
 Microsoft Entra admin center → **App registrations** → the app registered via
 `Register-HrConnectorApp.ps1` with this scenario's own `-DisplayName` → **Certificates &
 secrets**. **Do not** revoke either sibling scenario's own, separate app registration, this
 scenario provisioned its own (`design.md` §2 goal 6).
5. If the scope-resolution app registration (`GroupMember.Read.All`) or the alert-export app
 registration (`SecurityAlert.Read.All`) are shared with other IRM scenarios in this library,
 don't revoke either while those scenarios still use them.
6. If cloud indicators were enabled and no other Insider Risk Management policy or Defender for
 Cloud Apps use case in the tenant depends on the Box/Dropbox/Google Drive/Amazon S3/Azure
 connection, disconnect it in the Defender portal, confirm first, since these connectors are
 commonly shared across multiple Defender/Purview capabilities beyond this one policy.
7. **Do not delete the source Entra security group(s)** used for scoping as part of removing this
 scenario, that group is owned by whatever process governs the tenant's role-based groups
 (`design.md` §7), not by this scenario.

There is no "undo" for policy, HR-connector, or Communication-Compliance-policy deletion, 
re-establishing the control means re-running the portal and script steps in `README.md` §5 from
scratch, referencing `deploy/policy/data-leaks-risky-users-policy-manifest.json` again as the
configuration source of truth.

## What rollback does **not** undo

- **Alert and case history.** Alerts and cases already generated remain in the Purview portal per
 their own retention policy, regardless of whether the policy, HR connector, or Communication
 Compliance policy that generated them still exists.
- **Risk scores already calculated.** Historical record, not live state.
- **HR risk-indicator records already ingested by the HR connector**, or **Communication
 Compliance alerts already generated**, both remain in Microsoft's cloud per their own retention
 policy, independent of whether the connector or policy that consumed them still exists.
- **Cloud-app activity already ingested by Defender for Cloud Apps** before a connector was
 disconnected, historical record, not retroactively purged.
- **Audit log entries.** Every action in this scenario (policy edits, connector/policy creation and
 deletion, alert activity) is itself an audited event in the Microsoft 365 unified audit log per
 its own retention window.

## Verification after rollback

Re-run the manual checklist section of `validate/Test-DataLeaksRiskyUsersIrmSetup.ps1` and confirm
the Purview and Communication Compliance portal state matches the stage you intended. There is no
automated way to confirm policy, HR-connector, or Communication-Compliance-policy deletion or state
via script, see `design.md` §2 goal 7 for why.
