---
part: "validate"
parent: "audit/streaming-to-sentinel-or-management-api"
---
Run these checks after deployment to confirm the control is working as designed.


#### `Test-ManagementActivityStreaming.ps1`

```powershell
#Requires -Version 7.0
<#
.SYNOPSIS
    Read-only readiness/health check for Path B (Management Activity API streaming): confirms
    token acquisition, that configured content types are subscribed and enabled, and (optionally)
    that recent checkpoints/exports show the pipeline is actually producing output.

.DESCRIPTION
    Never modifies tenant state or subscriptions. Checks:
      1. An OAuth2 app-only token can be acquired for the configured tenant/app.
      2. Every configured content type in config.contentTypes has status 'enabled' per
         /subscriptions/list (a 'not subscribed' or non-enabled status fails the check).
      3. If -CheckpointDir is reachable, each content type's checkpoint file exists and its
         lastRunUtc is within -MaxStaleHours (default 26h - one run cycle plus slack) of now, i.e.
         the scheduled poll is actually running.
    Exits non-zero on any hard failure. Safe to re-run.

    This does NOT validate the Sentinel native connector (Path A) - that connector's state is
    checked via `Get-AzResourceGroupDeployment`/the Sentinel portal's Data connectors page, since
    it has no equivalent "is it enabled" REST call this library scripts around (see README.md
    Section 7).

.PARAMETER ConfigPath
    Path to the config to validate. Defaults to '../deploy/config/management-activity-streaming.sample.json'.

.PARAMETER CheckpointDir
    Directory to check for recent checkpoint files. Defaults to config.checkpointDir. Skipped if
    -SkipCheckpointCheck is passed or the directory doesn't exist yet (e.g. before the first poll run).

.PARAMETER MaxStaleHours
    Maximum age, in hours, a content type's checkpoint may be before it's flagged as stale.

.PARAMETER SkipCheckpointCheck
    Skip the checkpoint-freshness check (token + subscription checks only).

.PARAMETER TenantId / ClientId / ClientSecret
    Same app-only client-credentials parameters as the deploy scripts.

.EXAMPLE
    $secret = Read-Host -AsSecureString -Prompt 'Client secret'
    ./Test-ManagementActivityStreaming.ps1 -TenantId $tid -ClientId $cid -ClientSecret $secret
#>
[CmdletBinding()]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$ConfigPath = (Join-Path $PSScriptRoot '../deploy/config/management-activity-streaming.sample.json'),

    [Parameter()]
    [string]$CheckpointDir,

    [Parameter()]
    [ValidateRange(1, 168)]
    [int]$MaxStaleHours = 26,

    [Parameter()]
    [switch]$SkipCheckpointCheck,

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
$script:failures = 0
function Test-Check {
    param([string]$Description, [bool]$Condition, [switch]$Warn)
    if ($Condition) { Write-Host "  [PASS] $Description" -ForegroundColor Green }
    elseif ($Warn) { Write-Host "  [WARN] $Description" -ForegroundColor Yellow }
    else { Write-Host "  [FAIL] $Description" -ForegroundColor Red; $script:failures++ }
}

Test-Check -Description "Config file exists" -Condition (Test-Path -LiteralPath $ConfigPath)
if (-not (Test-Path -LiteralPath $ConfigPath)) { Write-Host "`nCannot continue without a config file." -ForegroundColor Red; exit 1 }
$cfg = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json

$apiRoot = if ($cfg.apiRoot) { $cfg.apiRoot } else { 'https://manage.office.com' }
$loginRoot = if ($cfg.loginRoot) { $cfg.loginRoot } else { 'https://login.microsoftonline.com' }
$contentTypes = @($cfg.contentTypes)
Test-Check -Description "Config has at least one contentType" -Condition ($contentTypes.Count -gt 0)

# --- 1. Token acquisition ---
$plainSecret = [System.Runtime.InteropServices.Marshal]::PtrToStringUni(
    [System.Runtime.InteropServices.Marshal]::SecureStringToGlobalAllocUnicode($ClientSecret))
$oauth = $null
try {
    $tokenBody = @{ client_id = $ClientId; client_secret = $plainSecret; grant_type = 'client_credentials'; resource = $apiRoot }
    $oauth = Invoke-RestMethod -Method Post -Uri "$loginRoot/$TenantId/oauth2/token" -Body $tokenBody
    Test-Check -Description "Acquired an app-only token for $apiRoot" -Condition ($null -ne $oauth.access_token)
}
catch {
    Test-Check -Description "Acquired an app-only token for $apiRoot (error: $($_.Exception.Message))" -Condition $false
}
finally {
    $plainSecret = $null
}

if (-not $oauth) {
    Write-Host "`nCannot continue without a token - check ClientId/ClientSecret/TenantId and the app registration's Office 365 Management APIs permission grant (README.md Section 3)." -ForegroundColor Red
    exit 1
}
$headers = @{ Authorization = "Bearer $($oauth.access_token)" }

# --- 2. Subscription status per content type ---
try {
    $listUri = "$apiRoot/api/v1.0/$TenantId/activity/feed/subscriptions/list?PublisherIdentifier=$TenantId"
    $existing = Invoke-RestMethod -Method Get -Headers $headers -Uri $listUri
    $existingByType = @{}
    foreach ($s in @($existing)) { $existingByType[$s.contentType] = $s.status }
    foreach ($ct in $contentTypes) {
        $status = $existingByType[$ct]
        Test-Check -Description "Content type '$ct' is subscribed and enabled (status: $(if ($status) { $status } else { 'not subscribed' }))" -Condition ($status -eq 'enabled')
    }
}
catch {
    Test-Check -Description "Retrieved subscription list (error: $($_.Exception.Message))" -Condition $false
}

# --- 3. Checkpoint freshness (pipeline is actually running) ---
if (-not $SkipCheckpointCheck) {
    $checkpointRoot = if ($CheckpointDir) { $CheckpointDir } elseif ($cfg.checkpointDir) { $cfg.checkpointDir } else { './checkpoints' }
    if (-not (Test-Path -LiteralPath $checkpointRoot)) {
        Test-Check -Description "Checkpoint directory '$checkpointRoot' exists (skip with -SkipCheckpointCheck before the first poll run)" -Condition $false -Warn
    }
    else {
        foreach ($ct in $contentTypes) {
            $checkpointPath = Join-Path $checkpointRoot "$ct.checkpoint.json"
            if (-not (Test-Path -LiteralPath $checkpointPath)) {
                Test-Check -Description "Checkpoint for '$ct' exists (Invoke-ManagementActivityPoll.ps1 has run at least once)" -Condition $false -Warn
                continue
            }
            $checkpoint = Get-Content -LiteralPath $checkpointPath -Raw | ConvertFrom-Json
            $lastRun = [datetimeoffset]$checkpoint.lastRunUtc
            $ageHours = ((Get-Date).ToUniversalTime() - $lastRun.UtcDateTime).TotalHours
            Test-Check -Description "Checkpoint for '$ct' is fresh (last run $([math]::Round($ageHours, 1))h ago, threshold ${MaxStaleHours}h)" -Condition ($ageHours -le $MaxStaleHours)
        }
    }
}

Write-Host "`n$(if ($script:failures -eq 0) { 'All hard checks passed.' } else { "$script:failures hard check(s) failed." })" `
    -ForegroundColor $(if ($script:failures -eq 0) { 'Green' } else { 'Red' })
if ($script:failures -gt 0) { exit 1 }
```