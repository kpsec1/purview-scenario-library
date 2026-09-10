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
