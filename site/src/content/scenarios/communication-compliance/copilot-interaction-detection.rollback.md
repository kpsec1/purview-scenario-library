---
part: "rollback"
parent: "communication-compliance/copilot-interaction-detection"
---
This scenario has two independent things to roll back: the **policy itself** (portal-only, no
script touches it) and the **audit-trail export** (this scenario's one scripted artifact). Handle
them separately.

## Rolling back the policy (portal-only, no script)

There is no `Remove-*` script for this scenario's `deploy/` folder, because there is no script that
creates the policy in the first place (`design.md` §3). Pausing, scoping down, or deleting the
policy is a portal action:

### Stage 1, Pause the policy (reversible, up to 24 hours to take effect)

From **Communication Compliance** → **Policies**, select the policy → **Pause policy** → confirm.
Alert generation stops, but **existing alerts and captured prompts/responses remain available** for
ongoing investigations and reviews. Use this stage for testing, troubleshooting a
false-positive spike, or a temporary business exception that doesn't warrant deleting the control.
Resume with **Resume policy**, also up to 24 hours to take effect.

### Stage 2, Revoke reviewer/admin access (reversible)

Remove Security/Responsible-AI/Legal stakeholders from **Communication Compliance Investigators**
and, separately, any narrower policy-specific reviewer assignment made in step 2 of `README.md` §5.
Does not affect the policy's captured data or other policies' reviewer access, including
`harassment-and-code-of-conduct`'s independent reviewer pool, if that scenario is also deployed in
this tenant.

### Stage 3, Delete the policy (not reversible)

From **Communication Compliance** → **Policies**, select the policy → **Delete**. Microsoft's own
guidance:

- **This is permanent.** Deleting the policy **permanently deletes all captured prompts, responses,
 attachments, and message alerts** it captured. Re-creating the policy means
 running the full portal runbook in `README.md` §5 again from scratch (selecting the template
 again, the template itself is not consumed or altered by a prior policy's deletion).
- If the deactivation reason was the **storage/message limit** being reached (README.md §8/§11)
 rather than a deliberate decommission, consider **copying the policy** first (Communication
 Compliance's own **Copy policy** action) to maintain detection continuity before deleting the
 deactivated one.
- **Export any needed evidence first.** There is no equivalent to Compliance Manager's "Export an
 assessment report" for the captured prompt/response content itself, the alert/message data lives
 only inside the policy until it's deleted. If an active Security or Legal investigation depends on
 a specific alert (e.g. a confirmed jailbreak attempt under active investigation, `README.md` §8),
 ensure the relevant evidence has been separately preserved (e.g. via an eDiscovery hold or case)
 before deleting the policy that contains it.

## Rolling back the audit-trail export (scripted)

`deploy/Export-CopilotInteractionAuditTrail.ps1` has no "undo" in the usual sense, it only reads
from the unified audit log and writes to a local CSV file. Decommissioning this piece means:

1. **Stop the schedule.** If the script was wired into a scheduled task/pipeline (`README.md` §8),
 disable or delete that schedule. The script itself has no persistent server-side state to
 disable, there is nothing in the tenant to turn off.
2. **Decide the fate of the CSV file.** The rolling audit-trail CSV records who changed the policy,
 when Copilot interactions matched it, and when a reviewer took a remediation action, treat it
 with the same retention discipline as any other Security/Responsible-AI/Legal-relevant audit
 evidence rather than deleting it casually. If it must be deleted, do so deliberately and document
 why.
3. **Revoke the automation identity's role**, if one was dedicated to this script. The script needs
 only the **View-Only Audit Logs** (or **Audit Logs**) Exchange Online role (`README.md` §3), 
 remove that role assignment from the app registration's service principal or the interactive
 account used to run it. If the same identity also runs `harassment-and-code-of-conduct`'s audit
 script, confirm that sibling scenario is also being decommissioned before revoking a shared role
 assignment.

## What rollback does **not** undo

- **Audit log records already generated.** `SupervisionRuleMatch`/`SupervisionPolicyCreated`/
 `SupervisionPolicyUpdated`/`SupervisionPolicyDeleted`/`SupervisoryReviewTag` events already logged
 by Microsoft 365 are retained per the tenant's audit retention policy (`README.md` §11) regardless
 of whether this scenario's export script keeps running.
- **Remediation actions already taken** (an interaction already resolved, tagged, or escalated), 
 those actions are permanent regardless of the policy's later pause/deletion.
- **A Security or Legal investigation or case already opened** based on an alert this policy
 generated, that case's own record-keeping and process govern independently of this scenario's
 technical control.
- **Copilot's own built-in Responsible AI runtime protections** (`design.md` §8, Non-goals), 
 those are Microsoft product-side mitigations, entirely independent of this scenario's Communication
 Compliance layer, and are unaffected by rolling this scenario back.

## Verification after rollback

```powershell
# Confirm the audit-trail CSV stopped growing (no new rows after the schedule was disabled):
Import-Csv './out/copilot-interaction-audit-trail.csv' | Sort-Object CreationDate -Descending | Select-Object -First 1

# Confirm the automation identity no longer holds the audit-search role (run as a Global/Compliance
# Administrator, from Exchange Online PowerShell):
Get-RoleGroupMember -Identity 'View-Only Organization Management' | Where-Object { $_.Name -eq '<service principal display name>' }
```

For the policy itself, the only verification is in the portal: confirm its status shows **Paused**
(Stage 1) or that it no longer appears on the **Policies** page (Stage 3). There is no PowerShell or
Graph equivalent (`design.md` §3).

## References

1. Create and manage Communication Compliance policies, Pause a policy, Copy a policy, storage
 limit deletion warning, <https://learn.microsoft.com/purview/communication-compliance-policies>
