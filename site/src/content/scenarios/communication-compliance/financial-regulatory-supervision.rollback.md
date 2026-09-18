---
part: "rollback"
parent: "communication-compliance/financial-regulatory-supervision"
---
This scenario has two independent things to roll back: the **policy itself** (portal-only, no script
touches it) and the **audit-trail/evidence-of-review export** (this scenario's one scripted
artifact). Handle them separately. This mirrors
`scenarios/communication-compliance/harassment-and-code-of-conduct/rollback.md` exactly, with the
financial-regulatory-specific evidence-retention considerations called out where they differ.

## Rolling back the policy (portal-only — no script)

There is no `Remove-*` script for this scenario's `deploy/` folder, because there is no script that
creates the policy in the first place (`design.md` §2).

### Stage 1 — Pause the policy (reversible, up to 24 hours to take effect)

From **Communication Compliance** → **Policies**, select the policy → **Pause policy** → confirm.
Alert generation stops, but existing alerts and captured messages remain available. **Before pausing:
notify Compliance/Legal and confirm the firm's WSPs allow a supervision gap** — unlike the harassment
sibling, a paused financial-regulatory-supervision policy is a period during which Rule 3110(b)(4)
supervisory review is not occurring at all for the covered population. Document the pause window and
its business justification.

### Stage 2 — Revoke reviewer/admin access (reversible)

Remove named principals from **Communication Compliance Investigators** and any narrower
policy-specific reviewer assignment. Does not affect the policy's captured data or other policies'
reviewer access. **Update the firm's WSPs to reflect the change** — a WSP that still names a reviewer
who no longer has access is itself a documentation gap an examiner could flag.

### Stage 3 — Delete the policy (not reversible)

From **Communication Compliance** → **Policies**, select the policy → **Delete**.

- **This is permanent.** Deleting the policy permanently deletes all messages, associated
  attachments, and message alerts it captured.
- **Export the evidence-of-review CSV and audit-trail CSV first**, and confirm the firm's own
  retention obligations for supervisory-review evidence (a firm-specific WSP/records-retention
  question, not something this scenario's technical grounding determines) are satisfied by an
  external copy before deleting the policy that generated the underlying native alert records.
- If the deactivation reason was the storage/message limit being reached rather than a deliberate
  decommission, consider **copying the policy** first to maintain supervisory continuity before
  deleting the deactivated one.
- **Do not delete a policy while it may still be the subject of an open examination request or
  litigation hold** — confirm with Legal first, the same evidentiary-preservation discipline that
  applies to any regulated recordkeeping control.

## Rolling back the audit-trail/evidence-of-review export (scripted)

`deploy/Export-FinraSupervisionEvidence.ps1` has no "undo" in the usual sense — it only reads from the
unified audit log and writes to two local CSV files. Decommissioning this piece means:

1. **Stop the schedule.** If the script was wired into a scheduled task/pipeline (`README.md` §8),
   disable or delete that schedule. The script itself has no persistent server-side state to disable.
2. **Decide the fate of both CSV files with Compliance/Legal, not unilaterally.** The evidence-of-review
   CSV in particular may be the firm's primary documented artifact satisfying Rule 3110(b)(4)'s
   evidence-of-review requirement for the period this scenario was active — treat it as a regulated
   record, not an ordinary log file. If it must be deleted, that decision belongs to Compliance/Legal
   and should itself be documented.
3. **Revoke the automation identity's role.** The script needs only the **View-Only Audit Logs** (or
   **Audit Logs**) Exchange Online role — remove that role assignment from the app registration's
   service principal or the interactive account used to run it.

## What rollback does **not** undo

- **Audit log records already generated.** `SupervisionRuleMatch`/`SupervisionPolicy*`/
  `SupervisoryReviewTag` events already logged are retained per the tenant's audit retention policy
  (`README.md` §11) regardless of whether this scenario's export script keeps running.
- **Remediation actions already taken** (a message already resolved, tagged, or removed) — permanent
  regardless of the policy's later pause/deletion.
- **An examination or litigation-hold obligation already triggered** by an alert this policy
  generated — governed independently of this scenario's technical control.
- **The retention obligations `scenarios/data-lifecycle-management/retention-labels-financial-records/`
  addresses.** Rolling back this scenario has no effect on that separate scenario's own regulatory
  record labels — see `README.md` §8/§9 for why the two are independent controls.

## Verification after rollback

```powershell
# Confirm both rolling CSVs stopped growing (no new rows after the schedule was disabled):
Import-Csv './out/finra-audit-trail.csv' | Sort-Object CreationDate -Descending | Select-Object -First 1
Import-Csv './out/finra-evidence-of-review.csv' | Sort-Object ReviewDate -Descending | Select-Object -First 1

# Confirm the automation identity no longer holds the audit-search role (run as a Global/Compliance
# Administrator, from Exchange Online PowerShell):
Get-RoleGroupMember -Identity 'View-Only Organization Management' | Where-Object { $_.Name -eq '<service principal display name>' }
```

For the policy itself, the only verification is in the portal: confirm its status shows **Paused**
(Stage 1) or that it no longer appears on the **Policies** page (Stage 3). There is no PowerShell or
Graph equivalent (`design.md` §2).

## References

1. Create and manage Communication Compliance policies — Pause a policy, Copy a policy, storage limit
   deletion warning — <https://learn.microsoft.com/purview/communication-compliance-policies>
2. `scenarios/communication-compliance/harassment-and-code-of-conduct/rollback.md` — the sibling
   scenario this file's structure mirrors for this module's portal-only rollback pattern.
