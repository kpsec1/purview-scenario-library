---
part: "runbook"
parent: "audit/premium-audit-investigation"
---
## Implementation steps

### Portal path (for a first manual walkthrough)

1. In the [Microsoft Purview portal](https://purview.microsoft.com) → **Audit** → **New search**.
2. Set the **date range**, **users** (the target UPN), and **activities** (the crucial events), then
   **Search**. The job runs server-side and is kept for 30 days.
3. When it completes, review results and **Export** to CSV.

### Script path (repeatable, parameterized, `-WhatIf` preview)

```powershell
# Connect (delegated - or app-only with a certificate)
Connect-MgGraph -Scopes 'AuditLogsQuery.Read.All'

# 0. Readiness check (connectivity, scope, config, + a live probe query)
./validate/Test-AuditInvestigation.ps1 -ConfigPath ./deploy/config/compromise-jdoe.json

# 1. Preview the query body (creates nothing)
./deploy/Invoke-AuditInvestigation.ps1 -ConfigPath ./deploy/config/compromise-jdoe.json -WhatIf

# 2. Run the investigation: create query -> poll -> retrieve -> export CSV/JSON
./deploy/Invoke-AuditInvestigation.ps1 -ConfigPath ./deploy/config/compromise-jdoe.json -OutDir ./out/jdoe
```

The script uses the **Audit Search Graph API** (v1.0 `security` namespace) via the Microsoft Graph
PowerShell SDK (`Invoke-MgGraphRequest`) - automation surface 3 per [Automation surface](/docs/automation-surface/).

## Configuration reference

| Setting | Value this scenario uses | Notes |
|---|---|---|
| Create query | `POST /security/auditLog/queries` | Async job; body below |
| Poll | `GET /security/auditLog/queries/{id}` | Read `status` until terminal |
| Records | `GET /security/auditLog/queries/{id}/records` | Paged via `@odata.nextLink` |
| `displayName` | investigation label | Optional |
| `filterStartDateTime` / `filterEndDateTime` | ISO 8601 UTC, or derived from `lookbackDays` | The window; Premium retention lets it reach back up to 1 year |
| `userPrincipalNameFilters[]` | the target account(s) | The "who" |
| `operationFilters[]` | crucial-events preset (MailItemsAccessed, Send/SendAs, New-/Set-InboxRule, Add-MailboxPermission, FileDownloaded, AnonymousLinkCreated, UserLoggedIn/UserLoginFailed, role/user changes) | The "what" - trim to the incident |
| `recordTypeFilters[]` | optional workload filter | e.g. `exchangeItem`, `sharePointFileOperation`, `azureActiveDirectory` |
| `keywordFilter`, `ipAddressFilters[]`, `objectIdFilters[]` | optional | Non-indexed keyword; source IP; file/object path |
| Export | CSV (key fields) + JSON (full `auditData`) | Timestamped under the output dir |

Record fields exported (CSV): `createdDateTime, userPrincipalName, userId, operation, service,
auditLogRecordType, clientIp, objectId`; JSON keeps the full record incl. `auditData`. Exact bodies and Learn sources are in the script `.NOTES`.

## Operations and tuning

**Investigation runbook (suspected account compromise):**
1. Scope tight first - run with the target UPN + the crucial-events preset over the suspected window.
2. Triage the CSV: look for **`New-InboxRule`/`UpdateInboxRules`** (auto-forward/hide - classic BEC),
   **`Add-MailboxPermission`/`SendAs`** (delegate abuse), **`MailItemsAccessed`** (what was read),
   **`FileDownloaded`/`AnonymousLinkCreated`** (exfil/oversharing), and **`UserLoginFailed` →
   `UserLoggedIn`** patterns with unusual `clientIp`.
3. Pivot: widen to related users/IPs/objects found in step 2 with follow-on queries.
4. Preserve: keep the JSON export as evidence; if litigation is anticipated, hand off to the
   eDiscovery legal-hold scenario in this library.

**Tuning / limits:** broad operation sets over long windows return large result sets and slower jobs;
each admin can run up to **10 search jobs** concurrently (one unfiltered). Prefer
narrow, iterative queries. Record availability lags events by ~60-90 minutes, so
don't conclude "no activity" immediately after an incident.

**Automation:** run app-only (certificate) on a schedule for recurring hunts (e.g. daily
mailbox-rule-creation sweep), writing exports to a secured evidence store.

## Rollback and decommission

See the rollback runbook. This scenario is **read-only** - it creates a transient search job and reads
records; there is no tenant state to undo. The only cleanup is the **exported evidence files** (secure
and dispose per your IR data-handling policy) and, optionally, deleting the saved query. Completed
search jobs are retained by the service for 30 days.

## References

1. Learn about auditing solutions in Microsoft Purview (overview) - <https://learn.microsoft.com/purview/audit-solutions-overview>
2. Auditing solutions - Audit (Standard) vs (Premium) capability comparison (crucial events, retention) - <https://learn.microsoft.com/purview/audit-solutions-overview#comparison-of-key-capabilities>
3. Microsoft Purview service description - Audit (Premium) (1-year/10-year retention, crucial events, high-bandwidth API) - <https://learn.microsoft.com/office365/servicedescriptions/microsoft-365-service-descriptions/microsoft-365-tenantlevel-services-licensing-guidance/microsoft-purview-service-description#microsoft-purview-audit-premium>
4. Create auditLogQuery (`POST /security/auditLog/queries`; body fields; recordTypeFilters enum; AuditLogsQuery permissions) - <https://learn.microsoft.com/graph/api/security-auditcoreroot-post-auditlogqueries?view=graph-rest-1.0>
5. Search the audit log - before you search (ingestion latency, Search-UnifiedAuditLog) - <https://learn.microsoft.com/purview/audit-search#before-you-search-the-audit-log>
6. Search the audit log (server-side jobs, 30-day retention of jobs, 10 concurrent per admin) - <https://learn.microsoft.com/purview/audit-search>
7. Export audit records - <https://learn.microsoft.com/purview/audit-log-export-records>
8. List auditLogRecords (`GET /security/auditLog/queries/{id}/records`; record fields) - <https://learn.microsoft.com/graph/api/security-auditlogquery-list-records?view=graph-rest-1.0>
9. Audit log activities (operation/activity names) - <https://learn.microsoft.com/purview/audit-log-activities>
10. Search-UnifiedAuditLog (classic EXO cmdlet; 5,000/search default, 50,000 max; roles) - <https://learn.microsoft.com/powershell/module/exchange/search-unifiedauditlog>

> Re-verify all links, the API version, request/response shapes, the status enum, and the crucial-
> events/licensing details against current Microsoft Learn before a customer-facing deployment. The
> investigation is read-only; the exported evidence is sensitive - handle it accordingly.