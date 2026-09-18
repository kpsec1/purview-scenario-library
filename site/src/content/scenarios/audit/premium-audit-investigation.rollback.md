---
part: "rollback"
parent: "audit/premium-audit-investigation"
---
## There is no tenant state to roll back

This scenario is **read-only**. `Invoke-AuditInvestigation.ps1` creates a transient audit **search
job** and reads records from the unified audit log — it never changes mailbox, identity, sharing, or
policy state. So "rollback" here is not about undoing a change in the tenant; it is about **handling
the evidence you exported** and cleaning up the transient job.

## 1. Secure and dispose of the exported evidence (the real cleanup)

The CSV/JSON exports can contain **highly sensitive content and PII** — subjects, file paths, IP
addresses, and full workload `auditData`. Treat the output directory as case evidence:

- **Restrict access** to the investigators/legal team who need it (NTFS/ACLs, an evidence share, or a
  secured case system) — do not leave exports on a shared drive or a laptop.
- **Retain per your IR / legal-hold policy** — if litigation is anticipated, preserve the JSON export
  and coordinate with the eDiscovery legal-hold scenario in this library rather than deleting it.
- **Dispose securely** when the matter is closed and no retention obligation remains (secure delete;
  record the disposition in the case file).

## 2. Clean up the transient search job (optional)

Completed audit search jobs are retained by the service for **30 days** and then age out on their own,
so no action is required. If you want to remove a saved query sooner, delete it in the Microsoft
Purview portal (**Audit → search jobs**) or via the Audit Search Graph API. Deleting a query does not
delete any audit records — the unified audit log is immutable and unaffected.

## 3. Nothing else is touched

- **The unified audit log** is immutable — running or deleting a query never alters it.
- **The target account** is not modified — investigation ≠ response. If the investigation confirms
  compromise, remediation (disable account, revoke sessions, remove malicious inbox rules, reset
  credentials) is a separate, deliberate action performed with the appropriate tools and approvals.
- **Permissions/roles** granted for the investigation (the `AuditLogsQuery*` app or role) are not
  changed by this scenario — revoke them separately if the investigator no longer needs access.

## Verification

Re-running `./validate/Test-AuditInvestigation.ps1` after an investigation still `[PASS]`es (the API
and permissions are unchanged) — there is no "removed" state to confirm, because nothing was created
in the tenant beyond the transient, self-expiring query job. Confirm instead that the **exported
files are secured or disposed of** per the steps above.
