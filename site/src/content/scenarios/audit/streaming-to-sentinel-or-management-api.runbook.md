---
part: "runbook"
parent: "audit/streaming-to-sentinel-or-management-api"
---
## Implementation steps

### Path A - Sentinel native connector

**Portal path:**
1. In [Microsoft Sentinel](https://portal.azure.com) → **Data connectors**, search **Microsoft 365
   (formerly, Office 365)** → **Open connector page**.
2. Under **Configuration**, select the workloads to stream (**Exchange**, **SharePoint**,
   **Teams**) → **Apply Changes**.

**Script path (repeatable IaC, native what-if):**
```powershell
# 1. Preview (creates/changes nothing)
New-AzResourceGroupDeployment -WhatIf -ResourceGroupName <rg> `
  -TemplateFile ./deploy/office365-connector.bicep `
  -workspaceName <sentinelWorkspaceName> -tenantId <tenantGuid>

# 2. Apply
New-AzResourceGroupDeployment -ResourceGroupName <rg> `
  -TemplateFile ./deploy/office365-connector.bicep `
  -workspaceName <sentinelWorkspaceName> -tenantId <tenantGuid>
```
Uses the `Microsoft.SecurityInsights/dataConnectors` ARM resource, `kind: Office365`
 - Azure Resource Manager (not a Purview automation surface), authenticated with
the deploying user's/service principal's own Azure RBAC on the resource group.

### Path B - Management Activity API (custom)

```powershell
$secret = Read-Host -AsSecureString -Prompt 'Client secret'

# 0. Readiness check (token, subscription status, checkpoint freshness)
./validate/Test-ManagementActivityStreaming.ps1 -TenantId $tid -ClientId $cid -ClientSecret $secret -SkipCheckpointCheck

# 1. Ensure subscriptions are active (idempotent - preview first)
./deploy/Enable-ManagementActivitySubscriptions.ps1 -TenantId $tid -ClientId $cid -ClientSecret $secret -WhatIf
./deploy/Enable-ManagementActivitySubscriptions.ps1 -TenantId $tid -ClientId $cid -ClientSecret $secret

# 2. Poll once (or schedule this - Azure Automation runbook / Function timer trigger / cron)
./deploy/Invoke-ManagementActivityPoll.ps1 -TenantId $tid -ClientId $cid -ClientSecret $secret -OutDir ./out
```

Uses the **Office 365 Management Activity API** - a separate REST surface from Microsoft Graph, at
`manage.office.com` (or the government-cloud equivalent), authenticated with an app registration's
OAuth2 client-credentials grant. See [Automation surface, section 4](/docs/automation-surface/#4-routing-table---which-surface-for-which-purview-task) for how this surface relates to
the Graph-based Audit Search API used by *Forensic Investigation of a Compromised Account*.

## Configuration reference

| Setting | Path | Value this scenario uses | Notes |
|---|---|---|---|
| Connector kind | A | `Office365` | Portal calls it "Microsoft 365 (formerly, Office 365)"; the ARM/Bicep `kind` is still literally `Office365` |
| Data types | A | `exchange`, `sharePoint`, `teams` - each independently `Enabled`/`Disabled` | No `entra`/`dlp` data type exists on this connector kind - that's the coverage gap Path B fills |
| Destination table | A | `OfficeActivity` | Free Log Analytics data source |
| Content types | B | `Audit.AzureActiveDirectory`, `Audit.Exchange`, `Audit.SharePoint`, `Audit.General`, `DLP.All` | Config-driven list; trim to avoid double-collecting what Path A already streams |
| Subscribe | B | `POST /activity/feed/subscriptions/start?contentType=X` | Idempotent in this script - checks `/subscriptions/list` first; 15-minute cooldown between `/start` calls per content type |
| List content | B | `GET /activity/feed/subscriptions/content?contentType=X&startTime&endTime` | Window ≤24h, lookback ≤7 days (both hard API limits) |
| Retrieve blob | B | `GET {contentUri}?PublisherIdentifier={tenantId}` | `PublisherIdentifier` always included - dedicated throttling pool |
| Pagination | B | `NextPageUri` response header | Not `@odata.nextLink` - a different convention from Microsoft Graph |
| Output | B | NDJSON, one file per content type per run | Forwarder-agnostic hand-off |
| Checkpoint | B | `checkpoints/<contentType>.checkpoint.json` - `lastEndTimeUtc`, `lastRunUtc` | Advances only after a successful export |

## Operations and tuning

- **First content lag.** A newly-started Path B subscription can take **up to 12 hours** before its
  first content blobs appear - don't conclude the pipeline is broken before then.
- **Scheduling cadence (Path B).** Poll at least once every few hours; the 24-hour-per-call window
  and 7-day retrieval ceiling mean an outage longer than 7 days creates a **permanent gap** (the
  script's stale-checkpoint warning surfaces this - page the validation steps item 3, `validate/` check 3).
- **Throttling (Path B).** Baseline **2,000 requests/minute** per tenant, roughly double for
  Microsoft 365/Office 365 E5 tenants; always send `PublisherIdentifier` for a
  dedicated pool rather than the shared general pool. A sustained `AF429`
  response means back off, not retry-in-a-tight-loop.
- **Ordering is not guaranteed.** Content blobs are not necessarily sequential - a later-arriving
  blob can contain earlier events than one already processed. Downstream
  analytics should key off event timestamps inside each record, not blob-arrival order.
- **Avoid double-collection.** If both paths are deployed, don't subscribe Path B to
  `Audit.Exchange`/`Audit.SharePoint` content that duplicates what Path A already streams into
  `OfficeActivity`, unless the destination pipelines are genuinely separate and dedup is handled
  downstream.
- **Other scenarios can share this scenario's `-OutDir`.** `data-security-investigations/
  post-breach-investigation-and-purge/deploy/Export-DsiActivityAuditTrail.ps1`'s own
  `-NdjsonOutDir` parameter writes `DSI-Activity-<runStamp>.ndjson` files using the exact same
  per-run-file convention `Invoke-ManagementActivityPoll.ps1` uses here - point it at this
  scenario's `-OutDir` to have one downstream forwarder pick up both feeds. DSI records reach that
  directory via `Search-UnifiedAuditLog`, not the Management Activity API - they are not a Path B
  content type and are not subject to this API's 24-hour/7-day window limits (that scenario's own
  the known limitations).
- **DLP.All is sensitive.** Detected sensitive-information events can themselves carry excerpts of
  matched content - treat Path B's `DLP.All` export files with the same handling discipline as the
  audit-investigation exports in this library's *Forensic Investigation of a Compromised Account*.
  **Restrict filesystem access to `-OutDir`** (NTFS/POSIX ACLs, or a private storage container if the
  scheduled poll runs in Azure Automation/Functions) the same way you would any other directory
  holding unified-audit-log content - the NDJSON files are plaintext, at rest, for as long as they
  sit there before a downstream forwarder picks them up.
- **429 handling is built in.** Every raw REST call in `Invoke-ManagementActivityPoll.ps1` honors
  `Retry-After`/backs off exponentially on a 429/AF429 response, and each content type fails
  independently (checkpoint not advanced) rather than aborting the whole run - see the script's
  `.DESCRIPTION` and [Automation surface, section 5](/docs/automation-surface/#5-throttling-scale-and-resilience-patterns).

## Rollback and decommission

See the rollback runbook.

## References

1. Office 365 Management Activity API reference (subscriptions, content types, pagination via NextPageUri, content not guaranteed sequential) - <https://learn.microsoft.com/office/office-365-management-api/office-365-management-activity-api-reference>
2. Office 365 Management Activity API reference - List available content (startTime/endTime ≤24h apart, ≤7-day lookback) - <https://learn.microsoft.com/office/office-365-management-api/office-365-management-activity-api-reference#list-available-content>
3. Office 365 Management Activity API FAQs and troubleshooting (15-min /start cooldown, PublisherIdentifier throttling pool, app registration + three permissions, AF429) - <https://learn.microsoft.com/office/office-365-management-api/troubleshooting-the-office-365-management-activity-api>
4. Get started with Office 365 Management APIs (app registration, admin consent, unified audit logging prerequisite) - <https://learn.microsoft.com/office/office-365-management-api/get-started-with-office-365-management-apis>
5. Search the audit log - before you search (ingestion latency) - <https://learn.microsoft.com/purview/audit-search#before-you-search-the-audit-log>
6. Management Activity API throttling limits (2,000 req/min baseline, ~2x for E5) - <https://learn.microsoft.com/office/office-365-management-api/troubleshooting-the-office-365-management-activity-api#frequently-asked-questions-about-the-office-365-management-activity-api>
7. Content retrieval window (7 days after notification) - <https://learn.microsoft.com/office/office-365-management-api/troubleshooting-the-office-365-management-activity-api#frequently-asked-questions-about-the-office-365-management-activity-api>
8. Connect Office 365 logs to Microsoft Sentinel (portal steps, workload toggles) - <https://learn.microsoft.com/azure/sentinel/connect-office-365>
9. Microsoft.SecurityInsights dataConnectors resource format - Office365 kind (exchange/sharePoint/teams data types, tenantId) - <https://learn.microsoft.com/azure/templates/microsoft.securityinsights/2024-03-01/dataconnectors>
10. Microsoft Sentinel pricing and billing - free data sources (Office 365 Audit Logs) - <https://learn.microsoft.com/azure/sentinel/billing#free-data-sources>
11. Stream data from Microsoft Purview Information Protection to Microsoft Sentinel (preview, prerequisites, gathered via Office Management API) - <https://learn.microsoft.com/azure/sentinel/connect-microsoft-purview>
12. Microsoft Purview Information Protection connector - known issues and limitations (label names, duplication with OfficeActivity) - <https://learn.microsoft.com/azure/sentinel/connect-microsoft-purview#known-issues-and-limitations>
13. Integrate Microsoft Sentinel and Microsoft Purview - prerequisites (existing Sentinel workspace + Purview onboarded) - <https://learn.microsoft.com/azure/sentinel/purview-solution>
14. Connect Microsoft Sentinel to other Microsoft services with an API-based data connector - prerequisites (Security Administrator, Log Analytics read/write) - <https://learn.microsoft.com/azure/sentinel/connect-services-api-based#prerequisites>
15. Microsoft Sentinel in the Azure portal retirement timeline (March 31, 2027) - <https://learn.microsoft.com/azure/sentinel/overview#microsoft-sentinel-in-the-azure-portal-retirement-timeline>
16. RestApiPoller data connector reference for the Codeless Connector Framework - URI parameters (`dataConnectorId` must be a unique name matching the request body's `name`) - <https://learn.microsoft.com/azure/sentinel/data-connector-connection-rules-reference>
16. ARM/Bicep deployment what-if operation (`New-AzResourceGroupDeployment -WhatIf`) - <https://learn.microsoft.com/azure/azure-resource-manager/bicep/deploy-what-if>

> Re-verify all links, the API version/resource schema, throttling figures, and connector coverage
> against current Microsoft Learn before a customer-facing deployment. `DLP.All` exports can contain
> sensitive content - handle output accordingly.