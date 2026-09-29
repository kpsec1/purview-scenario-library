---
part: "runbook"
parent: "data-security-investigations/post-breach-investigation-and-purge"
---
## Implementation steps

### One-time setup (portal, all identities)

1. In the [Microsoft Purview portal](https://purview.microsoft.com/dsi), accept the Privacy Statement
   on first access.
2. Configure billing and AI capacity (Settings → the DSI billing/capacity page) - requires the
   **Data Security Investigations Admins** role group; choose a compute-unit processing location
   (ANZ / EU / UK / US).
3. Provision role-group membership with the script below, rather than the portal's per-user setup
   task, for a repeatable, reviewable deployment.

### RBAC provisioning (script path)

```powershell
Connect-IPPSSession -UserPrincipalName admin@contoso.com

# 1. Preview (changes nothing)
./deploy/New-DsiRoleGroupAssignments.ps1 -ConfigPath ./deploy/policy/dsi-role-assignments.json -WhatIf

# 2. Apply (additive-only by default - see the design notes Section 5)
./deploy/New-DsiRoleGroupAssignments.ps1 -ConfigPath ./deploy/policy/dsi-role-assignments.json

# 3. Confirm
./validate/Test-DsiRoleGroupAssignments.ps1 -ConfigPath ./deploy/policy/dsi-role-assignments.json
```

**Portal path (equivalent, per-user):** Purview portal → **Data Security Investigations** →
**Overview** → **Assign roles to your team members** setup task (Admin/Investigators only), or
**Settings** → **Roles and groups** → **Role groups** for all three groups including Reviewers.

### The investigation workflow itself (portal-only - no script path exists)

1. **Create an investigation** from a Defender XDR incident, an Insider Risk Management case, a DSPM
   (preview) insight, or manually (full draft mode).
2. **Build the scope** - add search results (keyword/query search, or audit search against the
   unified audit log for user-activity-driven investigations, e.g. "Downloaded file" + "Sent email"
   for a departing-employee scenario).
3. **Run AI analysis** - automatic vectorization on scope-add, then categorization (default/custom/
   AI-suggested categories) and targeted examination (credentials, risk score, personal data).
4. **Build the mitigation plan** - add the highest-risk items surfaced by examination.
5. **Purge** - save a search as a purge query, review the estimate, then run it choosing **soft
   purge** (recoverable, Exchange mailbox items only) or **hard purge** (permanent, Exchange mailbox
   + Teams messages; SharePoint/OneDrive are excluded from purge entirely).

### Continuous audit trail (script path)

```powershell
Connect-ExchangeOnline -AppId $AppId -Certificate $Cert -Organization $TenantDomain

# Dry run
./deploy/Export-DsiActivityAuditTrail.ps1 -OutputCsvPath ./out/dsi-audit-trail.csv -WhatIf

# Schedule this daily (Task Scheduler / cron / Azure Automation)
./deploy/Export-DsiActivityAuditTrail.ps1 -OutputCsvPath ./out/dsi-audit-trail.csv

# Optional: also land this run's new records as NDJSON in the audit streaming scenario's own
# Path B output directory, so the same downstream forwarder picks up DSI activity too (Section 8)
./deploy/Export-DsiActivityAuditTrail.ps1 -OutputCsvPath ./out/dsi-audit-trail.csv `
    -NdjsonOutDir ../../audit/streaming-to-sentinel-or-management-api/out
```

## Configuration reference

**Role group permission matrix** (verbatim from Microsoft's own reference - the authoritative source
for what each dedicated DSI role group can do):

| Action | Admins | Investigators | Reviewers |
|---|---|---|---|
| Add/delete/manage mitigation-plan items | Yes | Yes | Yes |
| Create and manage **all** investigations | Yes | No | No |
| Create and manage **assigned** investigations | Yes | Yes | No |
| Create searches, add items to scope | Yes | Yes | No |
| Estimate/preview search results | Yes | Yes | No |
| Manage investigation scope | Yes | Yes | No |
| Run categorization / examination / vector search | Yes | Yes | Yes |
| **Create and run purge queries** | **Yes** | **Yes** | **No** |
| View data risk graphs | Yes | Yes | Yes |
| View Pay-as-you-go usage dashboard | Yes | No | No |

**Purge method comparison**:

| | Soft purge | Hard purge |
|---|---|---|
| Action | Moves items to Recoverable Items | Permanently deletes from the data source |
| Recoverable | Yes, per retention settings | No - irreversible |
| Supported sources | Exchange mailbox items only | Exchange mailbox items **and** Teams messages |
| SharePoint / OneDrive | Not supported (purge disabled entirely if scope includes these) | Not supported |
| Recommended default | Most investigation-driven purges | Only with high confidence + no compliance retention need |

**Other confirmed limits and behaviors:**

| Setting | Value | Source |
|---|---|---|
| Purge cap | Up to **10,000 items per search** | |
| Hold/retention precedence | Both purge methods preserve items under litigation hold, eDiscovery hold, or a retention policy - can't permanently delete until the hold/period lapses | |
| Investigation-scope data location | A **copy** of every item added to scope is stored in an Azure storage account associated with DSI, billed via the storage meter | |
| Purge vs. investigation deletion | Running a purge removes items from their source, **not** from the DSI investigation scope itself - delete the investigation to remove data from DSI's own storage | |
| Billing model | Pay-as-you-go: storage meter (GB/month, all investigations) + Data Security Investigations compute units (AI processing) - **not** a pausable feature in the Purview Usage center | |
| Compute-unit processing locations | ANZ, EU, UK, US (operator choice) | |
| Audit - Operations logged | 28 distinct `DSI*` Operations covering investigation lifecycle, search, AI jobs, mitigation, and purge (`deploy/Export-DsiActivityAuditTrail.ps1`'s full list) | |
| Audit - SIEM companion feed | `-NdjsonOutDir` (optional) writes each run's new records as `DSI-Activity-<runStamp>.ndjson` - same per-run-file convention as `audit/streaming-to-sentinel-or-management-api`'s own Path B exports; point it at that scenario's `-OutDir` to share one downstream forwarder | This repo |

## Operations and tuning

- **`DSIPurgeStarted` is this scenario's single highest-priority signal.** It's the one DSI action
  that can permanently, irreversibly delete tenant data (hard purge). `Export-DsiActivityAuditTrail.ps1`
  emits a console warning on every such row; wire the same filter into whatever SIEM ultimately
  ingests the exported CSV, and alert on it in real time, not on the next scheduled review.
- **Landing this feed in a SIEM without building a second forwarder.** `-NdjsonOutDir` writes new
  records as NDJSON using the exact same per-run-file convention `audit/
  streaming-to-sentinel-or-management-api`'s Path B collector already uses for its own output -
  point it at that scenario's `-OutDir` and whatever forwarder already watches that directory
  (Splunk HEC, the Log Analytics Logs Ingestion API, a file-tail agent) picks up DSI activity too,
  with no new pipeline to stand up. This script still does not forward the NDJSON anywhere itself
  (same non-goal as `Invoke-ManagementActivityPoll.ps1` - the design notes) - a downstream forwarder
  is still required either way. The CSV output is unaffected and remains the primary record
  regardless of whether `-NdjsonOutDir` is used.
- **New-investigation creation is the second-priority signal**, especially
  `DSIInvestigationCreatedFromXDR`/`DSIInvestigationCreatedFromIRM` outside expected incident-response
  hours - confirm each is a recognized, in-progress incident, not credential misuse of a DSI
  Investigator's own access.
- **Compute-unit and storage burn rate** - the Pay-as-you-go usage dashboard (Admins-only, the prerequisites) shows
  per-investigation storage and compute cost; check it during a reactive investigation surge, since
  costs accrue continuously while investigation data remains in scope and are **not** stoppable by
  pausing the feature (it isn't a pausable capability - the configuration reference).
- **Stale saved purge queries are a documented, real risk** - Microsoft's own guidance warns that the
  item count shown during "Review for purge" is an *estimate at that moment*; running a saved purge
  query later can purge substantially more (or different) items than originally reviewed. Operational
  policy: always re-run "Review for purge" immediately before executing a saved query, never rely on
  an old estimate.
- **Least-privilege discipline for Reviewers.** Reviewers can run categorization/examination/vector
  search and see risk graphs - meaning a Reviewer already has visibility into extracted credentials,
  PII, and risk-ranked sensitive content, even though they cannot purge. Treat Reviewer assignment
  with the same care as any role that can view sensitive data at scale (the known limitations, Red Team finding 1).
- **Ingestion latency is shared** with the rest of the unified audit log (~60-90 minutes typical for
  core services) - `DSIPurgeStarted` will not appear in the audit trail instantaneously; this is not a
  substitute for the portal's own real-time Activities tab during active incident response.
- **KPI suggestions:** mean time from investigation creation to first mitigation-plan item (triage
  speed); purge-queue backlog age (items reviewed-for-purge but not yet run); role-group membership
  drift (validate script the validation steps, run on a schedule alongside the audit export).

## Rollback and decommission

See the rollback runbook.

## References

1. Learn about Data Security Investigations (overview, common scenarios, billing summary, entry
   points, integration with unified audit log/DSPM/IRM/Defender XDR) - <https://learn.microsoft.com/purview/data-security-investigations>
2. Learn about the Data Security Investigations workflow (6-step workflow, notifications) - <https://learn.microsoft.com/purview/data-security-investigations-workflow>
3. Get started with Data Security Investigations (privacy terms, permissions, billing, investigation
   creation methods) - <https://learn.microsoft.com/purview/data-security-investigations-get-started>
4. Assign permissions in Data Security Investigations (role group names, permission matrix, the four
   role groups with implicit access, 30-minute propagation, zero-admin guidance) - <https://learn.microsoft.com/purview/data-security-investigations-permissions>
5. Billing in Data Security Investigations (storage meter, compute units, AI capacity, processing
   locations, Pay-as-you-go usage dashboard) - <https://learn.microsoft.com/purview/data-security-investigations-billing>
6. Learn about Microsoft Purview billing models (pay-as-you-go model, data storage meter definition) - <https://learn.microsoft.com/purview/purview-billing-models>
7. Take mitigation actions in Data Security Investigations (mitigation plan, soft/hard purge mechanics,
   purge queue dashboard, hold/retention precedence, stale-query warning) - <https://learn.microsoft.com/purview/data-security-investigations-mitigation-actions>
8. Manage investigation scopes in Data Security Investigations (scope dashboard, item actions) - <https://learn.microsoft.com/purview/data-security-investigations-scope>
9. Use AI analysis in Data Security Investigations (vectorization, categorization, examination) - <https://learn.microsoft.com/purview/data-security-investigations-ai-analysis>
10. Search, review, and refine results in Data Security Investigations (audit search, supported
    activities) - <https://learn.microsoft.com/purview/data-security-investigations-search>
11. Audit log activities - Data Security Investigations activities (all 28 `DSI*` Operations) - <https://learn.microsoft.com/purview/audit-log-activities#data-security-investigations-activities>
12. `dataSecurityInvestigationAuditRecord` resource type (Graph Security API - read-only audit-record
    schema, no management methods) - <https://learn.microsoft.com/graph/api/resources/security-datasecurityinvestigationauditrecord?view=graph-rest-1.0>
13. Application card: Microsoft Purview Data Security Investigations (RBAC as a named safety
    component, human-in-the-loop design intent) - <https://learn.microsoft.com/purview/data-security-investigations-application-card>
14. Manage pay-as-you-go and per-user licensing usage (Usage center pausable-features table - Data
    Security Investigations listed as not pausable) - <https://learn.microsoft.com/purview/purview-billing-usage>
15. Manage role groups in Exchange Online (`Add-RoleGroupMember`/`Remove-RoleGroupMember`/
    `Update-RoleGroupMember`/`Get-RoleGroupMember` reference) - <https://learn.microsoft.com/exchange/permissions-exo/role-groups>
16. `Search-UnifiedAuditLog` reference - <https://learn.microsoft.com/powershell/module/exchangepowershell/search-unifiedauditlog>
17. Create investigations in Data Security Investigations (preview) from the Microsoft Defender portal - <https://learn.microsoft.com/defender-xdr/create-dsi-in-defender>
18. Data Security Investigations limits reference (purge limits - up to 10,000 items per search) - <https://learn.microsoft.com/purview/data-security-investigations-ref-limits>
19. Office 365 Management Activity API schema - AuditLogRecordType enum (value 333,
    `DataSecurityInvestigation`) - <https://learn.microsoft.com/office/office-365-management-api/office-365-management-activity-api-schema#auditlogrecordtype>
19. Manage audit log retention policies (180-day Standard default, 1-year E5 default, up to 10 years
    with Audit Premium) - <https://learn.microsoft.com/purview/audit-log-retention-policies>

> Re-verify all links, the role-group permission matrix, and billing meters against current
> Microsoft Learn before a customer-facing deployment - Data Security Investigations is an actively
> evolving solution (several adjacent features, e.g. the Posture agent and endpoint DLP evidence
> integration, are still in Preview as of this writing).