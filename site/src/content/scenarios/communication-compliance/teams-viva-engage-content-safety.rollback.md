---
part: "rollback"
parent: "communication-compliance/teams-viva-engage-content-safety"
---
This scenario has two independent things to roll back: the **policy itself** (portal-only, no
script touches it) and the **audit-trail export** (this scenario's one scripted artifact). Handle
them separately.

> **Before rolling back any part of this scenario, read this section fully.** Unlike both sibling
> Communication Compliance scenarios in this repo, pausing or deleting this policy has a
> consequence beyond losing a general conduct-monitoring control: it removes the tenant's only
> self-harm-risk detection layer for Teams and Viva Engage messaging. Treat that as a deliberate,
> documented decision, not a routine maintenance action.

## Rolling back the policy (portal-only, no script)

There is no `Remove-*` script for this scenario's `deploy/` folder, because there is no script that
creates the policy in the first place (`design.md` §3). Pausing, scoping down, or deleting the
policy is a portal action:

### Stage 1, Pause the policy (reversible, up to 24 hours to take effect)

From **Communication Compliance** → **Policies**, select the policy → **Pause policy** → confirm.
Alert generation stops, but **existing alerts and captured messages remain available** for ongoing
investigations and reviews [[1]](#references). Use this stage for testing, troubleshooting a
false-positive spike, or a temporary business exception.

**Before pausing:** confirm whether `harassment-and-code-of-conduct` is still active in the tenant.
That policy's Threat/Discrimination/Harassment classifiers provide partial, differently-built
coverage for two of this policy's four risk categories (`design.md` §4), but it provides **zero**
coverage for Sexual content or Self-harm risk. Pausing this policy without a documented, deliberate
decision that accounts for the loss of Self-harm-risk detection specifically is the one rollback
action in this repo's Communication Compliance scenarios that carries a duty-of-care consequence,
not just a conduct-monitoring gap.

Resume with **Resume policy**, also up to 24 hours to take effect.

### Stage 2, Revoke reviewer/admin access (reversible)

Remove HR/Legal stakeholders from **Communication Compliance Investigators** for this policy
specifically, or their broader role-group membership if they aren't also reviewing
`harassment-and-code-of-conduct`. Does not affect the policy's captured data or other policies'
reviewer access. **Separately and explicitly stand down the duty-of-care escalation contact** (§3 of
`README.md`) if this policy is being permanently retired, do not leave a named contact expecting
escalations from a policy that no longer generates them, and do not leave one unstood-down if the
policy is only paused (they may still be needed for in-flight cases).

### Stage 3, Delete the policy (not reversible)

From **Communication Compliance** → **Policies**, select the policy → **Delete**. Microsoft's own
guidance:

- **This is permanent.** Deleting the policy **permanently deletes all captured messages,
  attachments, and alerts** it captured [[1]](#references). Re-creating the policy means running the
  full portal runbook in `README.md` §5 again from scratch, including re-confirming the duty-of-care
  escalation contact and re-running the tabletop drill (§7) before go-live.
- If the deactivation reason was the **storage/message limit** being reached rather than a
  deliberate decommission, **copy the policy** first (Communication Compliance's own **Copy policy**
  action) to maintain self-harm/hate/sexual/violence detection continuity before deleting the
  deactivated one [[1]](#references), for this scenario specifically, treat this as the default
  response to a storage-limit deactivation, not an optional consideration.
- **Export any needed evidence first.** There is no equivalent to Compliance Manager's "Export an
  assessment report" for the captured message content itself. If a Legal investigation or an
  in-progress duty-of-care case depends on a specific alert, ensure the relevant evidence has been
  separately preserved (e.g. via an eDiscovery hold, or the organization's HR/EAP case
  record-keeping) before deleting the policy that contains it.

## Rolling back the audit-trail export (scripted)

`deploy/Export-ContentSafetyAuditTrail.ps1` has no "undo" in the usual sense, it only reads from
the unified audit log and writes to a local CSV file. Decommissioning this piece means:

1. **Stop the schedule.** If the script was wired into a scheduled task/pipeline (`README.md` §8),
   disable or delete that schedule. The script itself has no persistent server-side state to
   disable.
2. **Decide the fate of the CSV file.** The rolling audit-trail CSV records who changed the policy,
   when messages matched it, when a reviewer took a remediation action, and, via the
   `ContentSafetyContext`/`SeverityHint` columns, a best-effort record of which classifier matched,
   including any Self-harm matches. Treat it with the same retention discipline as any other
   HR/Legal-relevant and duty-of-care-relevant record rather than deleting it casually. If it must
   be deleted, do so deliberately, document why, and confirm the organization's separate HR/EAP
   case records (outside Communication Compliance) already capture what this CSV would otherwise
   evidence.
3. **Revoke the automation identity's role**, if one was dedicated to this script. The script needs
   only the **View-Only Audit Logs** (or **Audit Logs**) Exchange Online role (`README.md` §3), 
   remove that role assignment from the app registration's service principal or the interactive
   account used to run it. If the same identity also runs either sibling scenario's audit script,
   confirm that sibling is also being decommissioned before revoking a shared role assignment.

## What rollback does **not** undo

- **Audit log records already generated.** `SupervisionRuleMatch`/`SupervisionPolicyCreated`/
  `SupervisionPolicyUpdated`/`SupervisionPolicyDeleted`/`SupervisoryReviewTag` events already logged
  by Microsoft 365 are retained per the tenant's audit retention policy (`README.md` §11) regardless
  of whether this scenario's export script keeps running.
- **Remediation actions or duty-of-care escalations already taken**, those actions, and the
  organization's separate HR/EAP case records arising from them, are permanent regardless of the
  policy's later pause/deletion.
- **A Legal investigation or HR/EAP case already opened** based on an alert this policy generated, 
  that case's own record-keeping and process govern independently of this scenario's technical
  control.

## Verification after rollback

```powershell
# Confirm the audit-trail CSV stopped growing (no new rows after the schedule was disabled):
Import-Csv './out/content-safety-audit-trail.csv' | Sort-Object CreationDate -Descending | Select-Object -First 1

# Confirm the automation identity no longer holds the audit-search role (run as a Global/Compliance
# Administrator, from Exchange Online PowerShell):
Get-RoleGroupMember -Identity 'View-Only Organization Management' | Where-Object { $_.Name -eq '<service principal display name>' }
```

For the policy itself, the only verification is in the portal: confirm its status shows **Paused**
(Stage 1) or that it no longer appears on the **Policies** page (Stage 3). There is no PowerShell or
Graph equivalent (`design.md` §3). **Additionally confirm**, the check unique to this scenario's
rollback, that the duty-of-care escalation contact (§3) has been explicitly told this policy is
paused or deleted, so they don't continue expecting escalations that will no longer arrive.

## References

1. Create and manage Communication Compliance policies, Pause a policy, Copy a policy, storage
   limit deletion warning, <https://learn.microsoft.com/purview/communication-compliance-policies>
