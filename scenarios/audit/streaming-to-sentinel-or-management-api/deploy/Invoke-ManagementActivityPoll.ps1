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
