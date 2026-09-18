---
part: "rollback"
parent: "communication-compliance/harassment-and-code-of-conduct"
---
This scenario has two independent things to roll back: the **policy itself** (portal-only, no
script touches it) and the **audit-trail export** (this scenario's one scripted artifact). Handle
them separately.

## Rolling back the policy (portal-only — no script)

There is no `Remove-*` script for this scenario's `deploy/` folder, because there is no script
that creates the policy in the first place (`design.md` §2). Pausing, scoping down, or deleting the
policy is a portal action:

### Stage 1 — Pause the policy (reversible, up to 24 hours to take effect)

From **Communication Compliance** → **Policies**, select the policy → **Pause policy** → confirm.
Alert generation stops, but **existing alerts and captured messages remain available** for ongoing
investigations and reviews [[1]](#references). Use this stage for testing, troubleshooting a
false-positive spike, or a temporary business exception that doesn't warrant deleting the control.
Resume with **Resume policy** — also up to 24 hours to take effect.

### Stage 2 — Revoke reviewer/admin access (reversible)

Remove HR/Legal stakeholders from **Communication Compliance Investigators** and, separately, any
narrower policy-specific reviewer assignment made in step 5 of `README.md` §5. Does not affect the
policy's captured data or other policies' reviewer access.

### Stage 3 — Delete the policy (not reversible)

From **Communication Compliance** → **Policies**, select the policy → **Delete**. Microsoft's own
guidance:

- **This is permanent.** Deleting the policy **permanently deletes all messages, associated
  attachments, and message alerts** it captured [[1]](#references). Re-creating the policy means
  running the full portal runbook in `README.md` §5 again from scratch.
- If the deactivation reason was the **storage/message limit** being reached (README.md §8/§11)
  rather than a deliberate decommission, consider **copying the policy** first (Communication
  Compliance's own **Copy policy** action) to maintain detection continuity before deleting the
  deactivated one [[1]](#references).
- **Export any needed evidence first.** There is no equivalent to Compliance Manager's "Export an
  assessment report" for the captured message content itself — the alert/message data lives only
  inside the policy until it's deleted. If an active HR/Legal investigation depends on a specific
  alert, ensure the relevant evidence has been separately preserved (e.g. via an eDiscovery hold or
  case) before deleting the policy that contains it.

### The User-reported messages policy is separate and cannot be deleted

The **User-reported messages** system policy (`README.md` §5, step 9) is auto-created by the
tenant's Communication Compliance license and is not a policy this scenario created — it cannot be
deleted, and "you can only modify the assigned reviewers for the policy... You can't edit all other
policy properties" [[2]](#references). The only rollback action available for it is reverting its
reviewers back to the default (Communication Compliance Admins/Global Admin fallback) if HR/Legal
should no longer receive user-reported Teams/Viva Engage messages — not recommended, since that
reverts to Microsoft's own documented weaker default (§9 of `README.md`).

## Rolling back the audit-trail export (scripted)

`deploy/Export-CommunicationComplianceAuditTrail.ps1` has no "undo" in the usual sense — it only
reads from the unified audit log and writes to a local CSV file. Decommissioning this piece means:

1. **Stop the schedule.** If the script was wired into a scheduled task/pipeline (`README.md` §8),
   disable or delete that schedule. The script itself has no persistent server-side state to
   disable — there is nothing in the tenant to turn off.
2. **Decide the fate of the CSV file.** The rolling audit-trail CSV records who changed the policy,
   when messages matched it, and when a reviewer took a remediation action — treat it with the
   same retention discipline as any other HR/compliance-relevant audit evidence rather than
   deleting it casually. If it must be deleted, do so deliberately and document why.
3. **Revoke the automation identity's role**, if one was dedicated to this script. The script needs
   only the **View-Only Audit Logs** (or **Audit Logs**) Exchange Online role (`README.md` §3) —
   remove that role assignment from the app registration's service principal or the interactive
   account used to run it.

## What rollback does **not** undo

- **Audit log records already generated.** `SupervisionRuleMatch`/`SupervisionPolicyCreated`/
  `SupervisionPolicyUpdated`/`SupervisionPolicyDeleted`/`SupervisoryReviewTag` events already
  logged by Microsoft 365 are retained per the tenant's audit retention policy (`README.md` §11)
  regardless of whether this scenario's export script keeps running.
- **Remediation actions already taken** (a message already resolved, tagged, or removed from
  Teams) — those actions are permanent regardless of the policy's later pause/deletion.
- **An HR/Legal investigation or case already opened** based on an alert this policy generated —
  that case's own record-keeping and process govern independently of this scenario's technical
  control.

## Verification after rollback

```powershell
# Confirm the audit-trail CSV stopped growing (no new rows after the schedule was disabled):
Import-Csv './out/cc-audit-trail.csv' | Sort-Object CreationDate -Descending | Select-Object -First 1

# Confirm the automation identity no longer holds the audit-search role (run as a Global/Compliance
# Administrator, from Exchange Online PowerShell):
Get-RoleGroupMember -Identity 'View-Only Organization Management' | Where-Object { $_.Name -eq '<service principal display name>' }
```

For the policy itself, the only verification is in the portal: confirm its status shows **Paused**
(Stage 1) or that it no longer appears on the **Policies** page (Stage 3). There is no PowerShell
or Graph equivalent (`design.md` §2).

## References

1. Create and manage Communication Compliance policies — Pause a policy, Copy a policy, storage
   limit deletion warning — <https://learn.microsoft.com/purview/communication-compliance-policies>
2. Create and manage Communication Compliance policies — User-reported messages policy (reviewer-
   only editability) — <https://learn.microsoft.com/purview/communication-compliance-policies#user-reported-messages-policy>
