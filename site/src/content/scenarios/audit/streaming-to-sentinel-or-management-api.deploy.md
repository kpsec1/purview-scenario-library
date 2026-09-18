---
part: "deploy"
parent: "audit/streaming-to-sentinel-or-management-api"
---
The scripts and configuration below deploy this scenario. Review them, then run in order — each is designed to be idempotent and has a matching rollback.


#### `config/management-activity-streaming.sample.json`

```json
{
  "_comment": "Config for deploy/Enable-ManagementActivitySubscriptions.ps1 and deploy/Invoke-ManagementActivityPoll.ps1 (Path B - custom Management Activity API streaming). Author-only reference data. This is a separate REST surface from Microsoft Graph - see docs/automation-surface.md Section 4 ('Audit search (API, high volume/bulk export)' row).",
  "apiRoot": "https://manage.office.com",
  "_apiRootNote": "Enterprise (commercial) cloud default. GCC: https://manage-gcc.office.com. GCC High: https://manage.office365.us. DoD: https://manage.protection.apps.mil. Pick the endpoint matching your tenant's cloud.",
  "loginRoot": "https://login.microsoftonline.com",
  "contentTypes": [
    "Audit.AzureActiveDirectory",
    "Audit.Exchange",
    "Audit.SharePoint",
    "Audit.General",
    "DLP.All"
  ],
  "_contentTypesNote": "Audit.General covers Teams, Power Platform, and other workloads not in the three named Audit.* types. DLP.All requires the app registration also hold the separate 'Read DLP policy events' Application permission (only needed if you want DLP.All - see README.md Section 3) - omit DLP.All entirely if that permission isn't granted, or /start will fail for that content type. If you already run the Sentinel native connector (deploy/office365-connector.bicep) for Exchange/SharePoint/Teams, consider trimming this list to just Audit.AzureActiveDirectory and DLP.All to avoid collecting the same events twice through two different paths - see design.md Section 3.",
  "checkpointDir": "./checkpoints",
  "maxLookbackDays": 7,
  "_maxLookbackDaysNote": "Hard API limit - content is retrievable for at most 7 days after it becomes available. Do not increase this value; it documents the API's own ceiling, not a tunable preference.",
  "windowHours": 24,
  "_windowHoursNote": "Hard API limit - startTime/endTime must be no more than 24 hours apart per /content call. Do not increase this value.",
  "export": {
    "outDir": "./out",
    "_exportNote": "One NDJSON file per content type per run (<contentType>-<timestamp>.ndjson). Forward these files to your SIEM/log pipeline - this script does not forward them itself (design.md Section 6)."
  },
  "schemaVersion": "1.0",
  "lastUpdated": "2026-09-10"
}
```

#### `Enable-ManagementActivitySubscriptions.ps1`

```powershell
#Requires -Version 7.0
<#
.SYNOPSIS
    Idempotently ensures Office 365 Management Activity API subscriptions are active for the
    configured content types (Path B - custom/non-Sentinel streaming). Checks existing
    subscriptions before starting new ones, so re-running never trips the API's 15-minute
    per-content-type cooldown on repeated /start calls.

.DESCRIPTION
    Uses the Office 365 Management Activity API (NOT Microsoft Graph - a separate REST surface,
    OAuth2 client-credentials against manage.office.com or the government-cloud equivalent):
      1. GET  /activity/feed/subscriptions/list         (what's already subscribed, and its state)
      2. POST /activity/feed/subscriptions/start?contentType=X   (only for content types not
         already "enabled" - skipped otherwise)

    This script only manages SUBSCRIPTIONS (the "is this content type being collected at all"
    switch) - it does not poll or retrieve content. Run
    deploy/Invoke-ManagementActivityPoll.ps1 on a schedule afterward to actually collect and export
    events. See README.md Section 5 for the full sequence.

    Requires an Entra app registration granted the Application permission "Read activity data for
    an organization" (ActivityFeed.Read) on the "Office 365 Management APIs" resource, with admin
    consent - see README.md Section 3. Unified audit logging must already be turned on for the
    tenant (a prerequisite of the audit log itself, not of this script).

.PARAMETER ConfigPath
    Path to the JSON config listing content types and the API endpoint to use. Defaults to the
    sibling 'config/management-activity-streaming.sample.json'.

.PARAMETER TenantId
    Entra tenant ID (GUID). Required - used both as the OAuth2 authority and as the
    PublisherIdentifier on every API call (dedicated throttling pool - see README.md Section 11).

.PARAMETER ClientId
    App registration (application) ID used for client-credentials auth.

.PARAMETER ClientSecret
    App registration client secret, as a SecureString. Prefer certificate-based auth in production
    (see docs/automation-surface.md Section 3); this script accepts a SecureString secret for the
    OAuth2 client-credentials grant this API documents, and never writes it to disk or output.

.EXAMPLE
    $secret = Read-Host -AsSecureString -Prompt 'Client secret'
    ./Enable-ManagementActivitySubscriptions.ps1 -TenantId $tid -ClientId $cid -ClientSecret $secret -WhatIf

    Preview which content types would be newly subscribed; starts nothing.

.EXAMPLE
    ./Enable-ManagementActivitySubscriptions.ps1 -ConfigPath ./config/management-activity-streaming.sample.json -TenantId $tid -ClientId $cid -ClientSecret $secret

.NOTES
    Grounded in Microsoft Learn (verify before production use):
    - Office 365 Management Activity API reference (subscriptions start/list, content types):
      https://learn.microsoft.com/office/office-365-management-api/office-365-management-activity-api-reference
    - FAQs and troubleshooting (15-minute /start cooldown, PublisherIdentifier throttling pool,
      app registration + the three permissions, get-an-access-token pattern):
      https://learn.microsoft.com/office/office-365-management-api/troubleshooting-the-office-365-management-activity-api
    - Get started with Office 365 Management APIs (app registration, admin consent, unified audit
      logging prerequisite):
      https://learn.microsoft.com/office/office-365-management-api/get-started-with-office-365-management-apis

    VERIFY (pilot tenant): the exact wall-clock enforcement of the 15-minute /start cooldown (e.g.
    whether it is measured from the previous /start call regardless of outcome, or only from a
    successful one) - Microsoft's guidance states the cooldown but not this edge case. This script
    treats "already present in /subscriptions/list" as sufficient to skip /start regardless, which
    sidesteps the ambiguity rather than resolving it.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$ConfigPath = (Join-Path $PSScriptRoot 'config/management-activity-streaming.sample.json'),

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$TenantId,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$ClientId,

    [Parameter(Mandatory)]
    [System.Security.SecureString]$ClientSecret
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $ConfigPath)) { throw "Config file not found: $ConfigPath" }
$cfg = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json

$apiRoot = if ($cfg.apiRoot) { $cfg.apiRoot } else { 'https://manage.office.com' }
$loginRoot = if ($cfg.loginRoot) { $cfg.loginRoot } else { 'https://login.microsoftonline.com' }
$contentTypes = @($cfg.contentTypes)
if ($contentTypes.Count -eq 0) { throw "Config has no contentTypes - nothing to subscribe." }

Write-Host "Management Activity API - subscription check" -ForegroundColor Cyan
Write-Host "  Tenant:        $TenantId" -ForegroundColor Cyan
Write-Host "  API endpoint:  $apiRoot" -ForegroundColor Cyan
Write-Host "  Content types: $($contentTypes -join ', ')" -ForegroundColor Cyan

# --- Acquire an OAuth2 app-only token (client-credentials grant) ---
$plainSecret = [System.Runtime.InteropServices.Marshal]::PtrToStringUni(
    [System.Runtime.InteropServices.Marshal]::SecureStringToGlobalAllocUnicode($ClientSecret))
try {
    $tokenBody = @{
        client_id     = $ClientId
        client_secret = $plainSecret
        grant_type    = 'client_credentials'
        resource      = $apiRoot
    }
    $oauth = Invoke-RestMethod -Method Post -Uri "$loginRoot/$TenantId/oauth2/token" -Body $tokenBody
}
finally {
    $plainSecret = $null
}
$headers = @{ Authorization = "Bearer $($oauth.access_token)" }

# --- 1. What's already subscribed? ---
$listUri = "$apiRoot/api/v1.0/$TenantId/activity/feed/subscriptions/list?PublisherIdentifier=$TenantId"
$existing = Invoke-RestMethod -Method Get -Headers $headers -Uri $listUri
$existingByType = @{}
foreach ($s in @($existing)) { $existingByType[$s.contentType] = $s.status }

$toStart = [System.Collections.Generic.List[string]]::new()
foreach ($ct in $contentTypes) {
    $status = $existingByType[$ct]
    if ($status -eq 'enabled') {
        Write-Host "  [skip]  $ct - already enabled" -ForegroundColor DarkGray
    }
    else {
        Write-Host "  [start] $ct - $(if ($status) { "currently '$status'" } else { 'not subscribed' })" -ForegroundColor Yellow
        $toStart.Add($ct)
    }
}

if ($toStart.Count -eq 0) {
    Write-Host "`nAll configured content types are already enabled. Nothing to do." -ForegroundColor Green
    return
}

if (-not $PSCmdlet.ShouldProcess("Office 365 Management Activity API ($TenantId)", "Start subscription(s) for: $($toStart -join ', ')")) {
    Write-Host "`nWhatIf: would POST /subscriptions/start for: $($toStart -join ', ')" -ForegroundColor DarkYellow
    return
}

# --- 2. Start subscriptions that aren't already enabled ---
foreach ($ct in $toStart) {
    $startUri = "$apiRoot/api/v1.0/$TenantId/activity/feed/subscriptions/start?contentType=$ct&PublisherIdentifier=$TenantId"
    try {
        $result = Invoke-RestMethod -Method Post -Headers $headers -Uri $startUri
        Write-Host "  [started] $ct (status: $($result.status))" -ForegroundColor Green
    }
    catch {
        Write-Warning "Failed to start subscription for $ct - $($_.Exception.Message). If this is the 15-minute cooldown (see README.md Section 11), wait and re-run; this script is idempotent."
    }
}

Write-Host "`nDone. First content blobs for a newly-started subscription can take up to 12 hours to appear (Microsoft's documented ingestion window) - see README.md Section 8 before assuming the pipeline is broken." -ForegroundColor Cyan
```

#### `Invoke-ManagementActivityPoll.ps1`

```powershell
#Requires -Version 7.0
<#
.SYNOPSIS
    Polls the Office 365 Management Activity API for newly-available content blobs since the last
    checkpoint, retrieves them, and exports the records as NDJSON - a resumable, forwarder-agnostic
    collector for Path B (custom/non-Sentinel streaming).

.DESCRIPTION
    For each configured content type:
      1. Reads (or initializes) a per-content-type checkpoint file holding the last successful
         endTime.
      2. GET /activity/feed/subscriptions/content?contentType=X&startTime&endTime - the window is
         clamped to the API's own limits: no more than 24 hours per call, no more than 7 days of
         total lookback (content older than 7 days from availability is no longer retrievable).
      3. Follows the NextPageUri response header for busy tenants (a different pagination
         mechanism from Microsoft Graph's @odata.nextLink - this API is not Graph).
      4. Retrieves each contentUri's blob (always with PublisherIdentifier - see README.md
         Section 11) and appends its records as newline-delimited JSON to a per-content-type,
         per-run output file.
      5. Advances and persists the checkpoint only after a successful export, so a failed run is
         safely re-run from the same starting point.

    Every raw REST call honors Retry-After / backs off exponentially on a 429/AF429 throttling
    response (docs/automation-surface.md Section 5's requirement for raw, non-SDK REST calls), and
    each content type is processed independently - one type's failure after retries is logged and
    skipped (checkpoint not advanced, so it's retried next run) rather than aborting the rest of the
    run.

    Designed to be invoked on a schedule (Azure Automation runbook, Azure Function timer trigger,
    cron) - see README.md Section 8. This script does not forward the NDJSON anywhere itself
    (design.md Section 6, non-goal); a downstream forwarder (Splunk HEC, the Log Analytics Logs
    Ingestion API, a file-tail agent) reads the output directory.

.PARAMETER ConfigPath
    Path to the JSON config. Defaults to the sibling 'config/management-activity-streaming.sample.json'.

.PARAMETER CheckpointDir
    Directory holding one JSON checkpoint file per content type. Overrides config.checkpointDir.

.PARAMETER OutDir
    Directory to write NDJSON export files to. Overrides config.export.outDir.

.PARAMETER TenantId / ClientId / ClientSecret
    Same app-only client-credentials parameters as Enable-ManagementActivitySubscriptions.ps1.

.EXAMPLE
    $secret = Read-Host -AsSecureString -Prompt 'Client secret'
    ./Invoke-ManagementActivityPoll.ps1 -TenantId $tid -ClientId $cid -ClientSecret $secret -WhatIf

    Preview the content-listing calls that would be made (checkpoints, no retrieval); changes nothing.

.EXAMPLE
    ./Invoke-ManagementActivityPoll.ps1 -ConfigPath ./config/management-activity-streaming.sample.json -TenantId $tid -ClientId $cid -ClientSecret $secret -OutDir ./out

.NOTES
    Grounded in Microsoft Learn (verify before production use):
    - Office 365 Management Activity API reference (list available content, pagination via
      NextPageUri, content retention/expiration):
      https://learn.microsoft.com/office/office-365-management-api/office-365-management-activity-api-reference
    - FAQs and troubleshooting (24h/7-day window limits, PublisherIdentifier, throttling/AF429,
      ~60-90 min ingestion latency, 7-day content-retrieval expiry, content NOT sequential across
      blobs):
      https://learn.microsoft.com/office/office-365-management-api/troubleshooting-the-office-365-management-activity-api

    VERIFY (pilot tenant): the exact HTTP header casing/behavior of NextPageUri across client
    libraries - this script reads it case-insensitively via Invoke-WebRequest's Headers collection,
    but Microsoft's own docs show it only as an illustrative example, not a byte-precise contract.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$ConfigPath = (Join-Path $PSScriptRoot 'config/management-activity-streaming.sample.json'),

    [Parameter()]
    [string]$CheckpointDir,

    [Parameter()]
    [string]$OutDir,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$TenantId,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$ClientId,

    [Parameter(Mandatory)]
    [System.Security.SecureString]$ClientSecret
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $ConfigPath)) { throw "Config file not found: $ConfigPath" }
$cfg = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json

$apiRoot = if ($cfg.apiRoot) { $cfg.apiRoot } else { 'https://manage.office.com' }
$loginRoot = if ($cfg.loginRoot) { $cfg.loginRoot } else { 'https://login.microsoftonline.com' }
$contentTypes = @($cfg.contentTypes)
if ($contentTypes.Count -eq 0) { throw "Config has no contentTypes - nothing to poll." }

$checkpointRoot = if ($CheckpointDir) { $CheckpointDir } elseif ($cfg.checkpointDir) { $cfg.checkpointDir } else { './checkpoints' }
$outRoot = if ($OutDir) { $OutDir } elseif ($cfg.export.outDir) { $cfg.export.outDir } else { './out' }
$maxLookbackDays = if ($cfg.maxLookbackDays) { [int]$cfg.maxLookbackDays } else { 7 }  # API hard limit
$windowHours = if ($cfg.windowHours) { [int]$cfg.windowHours } else { 24 }             # API hard limit

if (-not (Test-Path -LiteralPath $checkpointRoot)) { New-Item -ItemType Directory -Path $checkpointRoot -Force | Out-Null }
if (-not (Test-Path -LiteralPath $outRoot)) { New-Item -ItemType Directory -Path $outRoot -Force | Out-Null }

# Raw REST calls against this API must implement their own 429-handling (docs/automation-surface.md
# Section 5: "Raw REST calls... must implement their own 429-handling: catch the error, read
# Retry-After from the response headers, wait, retry - never retry immediately in a tight loop").
# This API's own AF429 throttling error is documented in the FAQ/troubleshooting reference (see
# README.md Section 8) - honor Retry-After when present, otherwise back off exponentially.
function Invoke-WithRetry {
    param(
        [Parameter(Mandatory)][scriptblock]$Action,
        [int]$MaxAttempts = 5
    )
    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
        try {
            return & $Action
        }
        catch {
            # $_.Exception.Response here is the raw System.Net.Http.HttpResponseMessage (PS7's
            # underlying HttpClient error path) - its .Headers has no string indexer, unlike
            # Invoke-WebRequest's own successful-response wrapper used below for NextPageUri.
            # TryGetValues is the correct .NET API for this type.
            $resp = $_.Exception.Response
            $status = if ($resp) { [int]$resp.StatusCode } else { 0 }
            $isThrottled = ($status -eq 429) -or ($_.Exception.Message -match 'AF429|Too many requests')
            if (-not $isThrottled -or $attempt -eq $MaxAttempts) { throw }
            $retryAfter = $null
            if ($resp -and $resp.Headers) {
                $values = $null
                if ($resp.Headers.TryGetValues('Retry-After', [ref]$values)) {
                    [int]$retryAfter = @($values) | Select-Object -First 1
                }
            }
            $waitSeconds = if ($retryAfter) { $retryAfter } else { [math]::Pow(2, $attempt) }
            Write-Warning "  Throttled (attempt $attempt/$MaxAttempts) - waiting ${waitSeconds}s before retry."
            Start-Sleep -Seconds $waitSeconds
        }
    }
}

# --- Acquire an OAuth2 app-only token (client-credentials grant) ---
$plainSecret = [System.Runtime.InteropServices.Marshal]::PtrToStringUni(
    [System.Runtime.InteropServices.Marshal]::SecureStringToGlobalAllocUnicode($ClientSecret))
try {
    $tokenBody = @{
        client_id     = $ClientId
        client_secret = $plainSecret
        grant_type    = 'client_credentials'
        resource      = $apiRoot
    }
    $oauth = Invoke-RestMethod -Method Post -Uri "$loginRoot/$TenantId/oauth2/token" -Body $tokenBody
}
finally {
    $plainSecret = $null
}
$headers = @{ Authorization = "Bearer $($oauth.access_token)" }

$nowUtc = (Get-Date).ToUniversalTime()
$runStamp = $nowUtc.ToString('yyyyMMdd-HHmmss')
$totalRecords = 0

foreach ($ct in $contentTypes) {
    Write-Host "`n[$ct]" -ForegroundColor Cyan

    # --- Resolve the window from the checkpoint (or a fresh 24h window if none exists) ---
    $checkpointPath = Join-Path $checkpointRoot "$ct.checkpoint.json"
    $earliestAllowed = $nowUtc.AddDays(-$maxLookbackDays)
    if (Test-Path -LiteralPath $checkpointPath) {
        $checkpoint = Get-Content -LiteralPath $checkpointPath -Raw | ConvertFrom-Json
        $startUtc = [datetimeoffset]$checkpoint.lastEndTimeUtc
        if ($startUtc -lt $earliestAllowed) {
            Write-Warning "  Checkpoint ($($startUtc.ToString('u'))) is older than the API's $maxLookbackDays-day retrieval window - advancing to the earliest retrievable time. A gap may exist; see README.md Section 11."
            $startUtc = $earliestAllowed
        }
    }
    else {
        $startUtc = $nowUtc.AddHours(-$windowHours)
        Write-Host "  No checkpoint found - starting from $($startUtc.ToString('u')) (first run)." -ForegroundColor DarkGray
    }
    $endUtc = if (($nowUtc - $startUtc).TotalHours -gt $windowHours) { $startUtc.AddHours($windowHours) } else { $nowUtc }

    Write-Host "  Window: $($startUtc.ToString('u')) -> $($endUtc.ToString('u'))" -ForegroundColor DarkGray

    if (-not $PSCmdlet.ShouldProcess("Management Activity API ($ct)", "List + retrieve content for window $($startUtc.ToString('u')) -> $($endUtc.ToString('u'))")) {
        Write-Host "  WhatIf: would list and retrieve content in this window; checkpoint unchanged." -ForegroundColor DarkYellow
        continue
    }

    # One content type's failure (a transient error surviving Invoke-WithRetry's attempts, a bad
    # response, etc.) must not abort the remaining content types in this run - each keeps its own
    # checkpoint, so a per-type failure here is naturally isolated and picked up again next run.
    try {
        # --- List available content, following NextPageUri ---
        $listUri = "$apiRoot/api/v1.0/$TenantId/activity/feed/subscriptions/content" +
                   "?contentType=$ct&startTime=$($startUtc.ToString('s'))&endTime=$($endUtc.ToString('s'))&PublisherIdentifier=$TenantId"
        $contentRefs = [System.Collections.Generic.List[object]]::new()
        $next = $listUri
        while ($next) {
            $nextUri = $next
            $resp = Invoke-WithRetry -Action { Invoke-WebRequest -Method Get -Headers $headers -Uri $nextUri }
            foreach ($item in (@($resp.Content | ConvertFrom-Json))) { $contentRefs.Add($item) }
            $next = $resp.Headers['NextPageUri'] | Select-Object -First 1
        }
        Write-Host "  Content blobs available: $($contentRefs.Count)" -ForegroundColor DarkGray

        # --- Retrieve each blob, write NDJSON ---
        $outFile = Join-Path $outRoot "$ct-$runStamp.ndjson"
        $recordCount = 0
        foreach ($ref in $contentRefs) {
            $blobUri = "$($ref.contentUri)?PublisherIdentifier=$TenantId"
            $records = Invoke-WithRetry -Action { Invoke-RestMethod -Method Get -Headers $headers -Uri $blobUri }
            foreach ($record in @($records)) {
                ($record | ConvertTo-Json -Depth 20 -Compress) | Add-Content -LiteralPath $outFile -Encoding utf8
                $recordCount++
            }
        }
        $totalRecords += $recordCount
        if ($recordCount -gt 0) { Write-Host "  [export] $recordCount record(s) -> $outFile" -ForegroundColor Green }
        else { Write-Host "  No records in this window." -ForegroundColor DarkGray }

        # --- Advance and persist the checkpoint only after a successful export ---
        @{ lastEndTimeUtc = $endUtc.ToString('o'); lastRunUtc = $nowUtc.ToString('o'); contentType = $ct } |
            ConvertTo-Json | Set-Content -LiteralPath $checkpointPath -Encoding utf8
    }
    catch {
        Write-Warning "  [$ct] failed after retries - $($_.Exception.Message). Checkpoint NOT advanced; this content type will retry the same window on the next run."
    }
}

Write-Host "`nDone. $totalRecords total record(s) exported across $($contentTypes.Count) content type(s) to $outRoot." -ForegroundColor Cyan
Write-Host "Schedule this script to re-run before checkpoints approach the $maxLookbackDays-day retrieval window (README.md Section 8)." -ForegroundColor Yellow
```

#### `office365-connector.bicep`

```
// office365-connector.bicep
//
// Enables the native Microsoft Sentinel "Microsoft 365 (formerly, Office 365)" data connector
// (ARM/Bicep kind: 'Office365') on an existing Log Analytics workspace with Sentinel already
// onboarded. Streams Exchange/SharePoint/Teams admin+user activity into the OfficeActivity table -
// a free Log Analytics data source (no per-GB ingestion charge). Does NOT cover Entra ID audit
// (Audit.AzureActiveDirectory) or DLP.All - see deploy/Enable-ManagementActivitySubscriptions.ps1
// (Path B) and README.md Section 3 for that coverage gap.
//
// Idempotent: Bicep/ARM deployment is declarative - re-deploying with the same parameters converges
// to the same connector state rather than erroring or duplicating. Preview with native what-if
// before applying (see README.md Section 5):
//   New-AzResourceGroupDeployment -WhatIf -ResourceGroupName <rg> \
//     -TemplateFile ./office365-connector.bicep -workspaceName <name> -tenantId <tenantGuid>
//
// Grounded in Microsoft Learn (verify before production use):
// - Microsoft.SecurityInsights dataConnectors resource format (Office365 kind):
//   https://learn.microsoft.com/azure/templates/microsoft.securityinsights/2024-03-01/dataconnectors
// - Connect Office 365 logs to Microsoft Sentinel (portal path, OfficeActivity table):
//   https://learn.microsoft.com/azure/sentinel/connect-office-365
// - Microsoft Sentinel free data sources (Office 365 Audit Logs are free):
//   https://learn.microsoft.com/azure/sentinel/billing#free-data-sources
// - ARM/Bicep what-if:
//   https://learn.microsoft.com/azure/azure-resource-manager/bicep/deploy-what-if
//
// VERIFY (pilot tenant): whether the data-connector resource `name` must be a GUID (several
// Microsoft samples for other connector kinds use one) or accepts an arbitrary string for the
// Office365 kind specifically - this template defaults to a deterministic GUID (guid()) so re-runs
// target the same resource, but Microsoft's Office365-kind reference page does not state the name
// constraint explicitly.

@description('Name of the existing Log Analytics workspace that has Microsoft Sentinel enabled.')
param workspaceName string

@description('Microsoft Entra tenant ID whose Office 365 activity this connector streams.')
param tenantId string = tenant().tenantId

@description('Enable the Exchange admin/user activity data type.')
@allowed(['Enabled', 'Disabled'])
param exchangeState string = 'Enabled'

@description('Enable the SharePoint (and OneDrive) activity data type.')
@allowed(['Enabled', 'Disabled'])
param sharePointState string = 'Enabled'

@description('Enable the Microsoft Teams activity data type.')
@allowed(['Enabled', 'Disabled'])
param teamsState string = 'Enabled'

resource workspace 'Microsoft.OperationalInsights/workspaces@2022-10-01' existing = {
  name: workspaceName
}

// Deterministic name so repeat deployments target the same connector resource instead of
// creating duplicates (see the VERIFY note above re: the exact naming contract for this kind).
var connectorName = guid(workspace.id, 'office365-data-connector')

resource office365Connector 'Microsoft.SecurityInsights/dataConnectors@2024-03-01' = {
  name: connectorName
  scope: workspace
  kind: 'Office365'
  properties: {
    tenantId: tenantId
    dataTypes: {
      exchange: {
        state: exchangeState
      }
      sharePoint: {
        state: sharePointState
      }
      teams: {
        state: teamsState
      }
    }
  }
}

@description('Resource ID of the deployed (or already-existing, if unchanged) Office 365 data connector.')
output connectorId string = office365Connector.id

@description('Resource name of the connector - stable across re-deployments, derived from the workspace ID.')
output connectorName string = connectorName
```