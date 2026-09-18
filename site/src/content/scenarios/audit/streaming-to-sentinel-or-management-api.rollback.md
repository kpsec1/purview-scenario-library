---
part: "rollback"
parent: "audit/streaming-to-sentinel-or-management-api"
---
Both paths create state that should be deliberately torn down, not just abandoned, a stopped
subscription still shows up in `/subscriptions/list`, and an unused Sentinel connector still counts
against license/RBAC review checklists.

## 1. Path A, Sentinel native connector

**Portal:** Microsoft Sentinel → **Data connectors** → **Microsoft 365 (formerly, Office 365)** →
**Open connector page** → toggle **Exchange**/**SharePoint**/**Teams** off (or **Disconnect**, if
offered) → **Apply Changes**.

**IaC (matches how it was deployed):** re-deploy `deploy/office365-connector.bicep` with all three
`*State` parameters set to `'Disabled'`, this keeps the resource itself in place (fully declarative,
`New-AzResourceGroupDeployment -WhatIf` still previews the exact diff first) rather than deleting it
out-of-band:
```powershell
New-AzResourceGroupDeployment -WhatIf -ResourceGroupName <rg> `
  -TemplateFile ./deploy/office365-connector.bicep `
  -workspaceName <sentinelWorkspaceName> -tenantId <tenantGuid> `
  -exchangeState Disabled -sharePointState Disabled -teamsState Disabled
```
To remove the connector resource entirely instead of just disabling its data types, delete it via
`Remove-AzResource` against the resource ID from the template's `connectorId` output, or from the
Sentinel portal's connector page.

**What this does NOT undo:** events already ingested into `OfficeActivity` before disconnection stay
in the workspace for its configured retention period, disabling the connector stops new ingestion,
it doesn't purge history. Purge/retention changes are a Log Analytics workspace-level decision,
outside this scenario's scope.

## 2. Path B, Management Activity API

**Stop the scheduled poll first** (disable the Azure Automation runbook / Function timer trigger /
cron entry running `Invoke-ManagementActivityPoll.ps1`) so nothing races the subscription teardown
below.

**Stop the subscriptions**, unlike `/start`, `/stop` has no documented cooldown and can be called
any time [[ref: Office 365 Management Activity API reference, "Please don't submit multiple requests
to start a subscription... This throttling policy doesn't apply to stop a subscription"]]:
```powershell
$secret = Read-Host -AsSecureString -Prompt 'Client secret'
$plain = [System.Runtime.InteropServices.Marshal]::PtrToStringUni(
    [System.Runtime.InteropServices.Marshal]::SecureStringToGlobalAllocUnicode($secret))
$token = (Invoke-RestMethod -Method Post -Uri "https://login.microsoftonline.com/$tenantId/oauth2/token" `
    -Body @{ client_id = $clientId; client_secret = $plain; grant_type = 'client_credentials'; resource = 'https://manage.office.com' }).access_token
foreach ($ct in @('Audit.AzureActiveDirectory','Audit.Exchange','Audit.SharePoint','Audit.General','DLP.All')) {
    Invoke-RestMethod -Method Post -Headers @{ Authorization = "Bearer $token" } `
        -Uri "https://manage.office.com/api/v1.0/$tenantId/activity/feed/subscriptions/stop?contentType=$ct&PublisherIdentifier=$tenantId"
}
```
Confirm with `/subscriptions/list` that each stopped content type no longer shows `status: enabled`.

**Clean up local state:**
- Remove or archive the `checkpoints/` directory, stale checkpoints from a decommissioned pipeline
  are misleading if `Test-ManagementActivityStreaming.ps1` is ever pointed at this config again.
- Secure or dispose of the `out/*.ndjson` export files per your data-handling policy, they can
  contain sensitive content, especially anything exported while `DLP.All` was subscribed (README.md
  §8/§11). While the pipeline is live, restrict filesystem access to `-OutDir` the same way; these
  are plaintext files sitting at rest until a downstream forwarder consumes them, not just a
  decommissioning concern.

**Revoke the app registration's access** if it's no longer needed: remove the granted **Office 365
Management APIs** permissions (and admin consent) from the Entra app registration, or delete the app
registration/credential entirely if it was created solely for this pipeline.

## 3. Nothing else is touched

- **The unified audit log itself** is unaffected by either path's teardown, both paths only read
  from it (Path A via the managed connector, Path B via subscribe/poll); neither ever writes to or
  purges it.
- **Unified audit logging** (the tenant-wide on/off switch) is a shared prerequisite for other
  scenarios in this library (e.g. `premium-audit-investigation`), do not turn it off as part of this
  rollback.

## Verification

Re-run `./validate/Test-ManagementActivityStreaming.ps1 -TenantId $tid -ClientId $cid -ClientSecret
$secret` after stopping Path B's subscriptions: the content-type checks should now report `[FAIL]`
(status not `enabled`), that's the expected, confirming signal that the subscriptions are actually
stopped, not a regression. For Path A, confirm the Sentinel **Data connectors** page shows the
connector's status as no longer streaming (or that `Get-AzResource` on the connector ID reflects the
`Disabled` data-type states, or 404s if deleted).
