#Requires -Version 7.0
<#
.SYNOPSIS
    Runs a read-only forensic audit-log investigation with the Microsoft Graph Audit Search API:
    creates an async audit query for a target user and set of crucial events, waits for it to
    complete, retrieves the records, and exports them to CSV/JSON.

.DESCRIPTION
    Uses the Microsoft Purview Audit Search Graph API (v1.0 security namespace) via
    Invoke-MgGraphRequest - automation surface 3 per docs/automation-surface.md:
      1. POST /security/auditLog/queries        (create the async search job)
      2. GET  /security/auditLog/queries/{id}   (poll until the status is terminal)
      3. GET  /security/auditLog/queries/{id}/records  (retrieve, following @odata.nextLink)
      4. Export the records to CSV (key fields) and/or JSON (full auditData) under the output dir.

    This is READ-ONLY against the tenant: an audit query is a search job over already-recorded
    events - it does not change mailbox, identity, or policy state. There is nothing to roll back
    except the exported evidence files (see rollback.md).

    Connect first: Connect-MgGraph -Scopes 'AuditLogsQuery.Read.All' (or a service-scoped variant
    such as AuditLogsQuery-Exchange.Read.All), delegated or app-only. This script does not open the
    session. -WhatIf previews the query body without creating the job.

.PARAMETER ConfigPath
    Path to the JSON config. Defaults to the sibling 'config/audit-investigation.sample.json'.

.PARAMETER OutDir
    Output directory for exports. Overrides config.export.outDir when supplied.

.PARAMETER PollTimeoutMinutes
    Max minutes to wait for the query to complete. Overrides config.pollTimeoutMinutes.

.PARAMETER GraphBaseUri
    Graph base URI. Defaults to 'https://graph.microsoft.com/v1.0'.

.EXAMPLE
    Connect-MgGraph -Scopes 'AuditLogsQuery.Read.All'
    ./Invoke-AuditInvestigation.ps1 -WhatIf

    Preview the audit query that would be created; create nothing.

.EXAMPLE
    Connect-MgGraph -Scopes 'AuditLogsQuery.Read.All'
    ./Invoke-AuditInvestigation.ps1 -ConfigPath ./config/compromise-jdoe.json -OutDir ./out/jdoe

.NOTES
    Grounded in Microsoft Learn (verify before production use):
    - Audit Search Graph API: create auditLogQuery / get / list records (v1.0 security namespace):
      https://learn.microsoft.com/graph/api/security-auditcoreroot-post-auditlogqueries?view=graph-rest-1.0
      https://learn.microsoft.com/graph/api/security-auditlogquery-list-records?view=graph-rest-1.0
    - Auditing solutions overview (Standard vs Premium, crucial events, retention):
      https://learn.microsoft.com/purview/audit-solutions-overview

    VERIFY (README.md Section 11): the exact auditLogQueryStatus terminal values - this script treats
    any status other than the running set (notStarted/running) as terminal and checks for a
    'succeeded'-like value before reading records.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$ConfigPath = (Join-Path $PSScriptRoot 'config/audit-investigation.sample.json'),

    [Parameter()]
    [string]$OutDir,

    [Parameter()]
    [ValidateRange(1, 240)]
    [int]$PollTimeoutMinutes,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$GraphBaseUri = 'https://graph.microsoft.com/v1.0'
)

$ErrorActionPreference = 'Stop'

if (-not (Get-Command Invoke-MgGraphRequest -ErrorAction SilentlyContinue)) {
    throw "Microsoft Graph PowerShell SDK not found. Install Microsoft.Graph and Connect-MgGraph first."
}
if (-not (Get-MgContext -ErrorAction SilentlyContinue)) {
    throw "Not connected to Microsoft Graph. Run Connect-MgGraph -Scopes 'AuditLogsQuery.Read.All' first (see docs/automation-surface.md Section 3)."
}
if (-not (Test-Path -LiteralPath $ConfigPath)) { throw "Config file not found: $ConfigPath" }
$cfg = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json

# --- Resolve the date range ---
if ($cfg.filterStartDateTime -and $cfg.filterEndDateTime) {
    $startUtc = ([datetimeoffset]$cfg.filterStartDateTime).UtcDateTime
    $endUtc = ([datetimeoffset]$cfg.filterEndDateTime).UtcDateTime
}
else {
    $look = if ($cfg.lookbackDays) { [int]$cfg.lookbackDays } else { 7 }
    $endUtc = (Get-Date).ToUniversalTime()
    $startUtc = $endUtc.AddDays(-$look)
}

# --- Build the query body (omit empty filters) ---
$body = @{
    '@odata.type'       = '#microsoft.graph.security.auditLogQuery'
    displayName         = if ($cfg.displayName) { $cfg.displayName } else { "Investigation $(Get-Date -Format s)" }
    filterStartDateTime = $startUtc.ToString('o')
    filterEndDateTime   = $endUtc.ToString('o')
}
foreach ($f in 'operationFilters', 'recordTypeFilters', 'userPrincipalNameFilters', 'ipAddressFilters', 'objectIdFilters', 'administrativeUnitIdFilters', 'serviceFilters') {
    if ($cfg.$f -and @($cfg.$f).Count -gt 0) { $body[$f] = @($cfg.$f) }
}
if (-not [string]::IsNullOrWhiteSpace($cfg.keywordFilter)) { $body.keywordFilter = $cfg.keywordFilter }

Write-Host "Audit investigation: '$($body.displayName)'" -ForegroundColor Cyan
Write-Host "  Window: $($startUtc.ToString('u')) -> $($endUtc.ToString('u'))" -ForegroundColor Cyan
if ($body.userPrincipalNameFilters) { Write-Host "  Users:  $($body.userPrincipalNameFilters -join ', ')" -ForegroundColor Cyan }
if ($body.operationFilters) { Write-Host "  Ops:    $(@($body.operationFilters).Count) operation filter(s)" -ForegroundColor Cyan }

if (-not $PSCmdlet.ShouldProcess("Audit Search API", "Create audit log query '$($body.displayName)'")) {
    Write-Host "`nWhatIf: would POST /security/auditLog/queries with body:" -ForegroundColor DarkYellow
    Write-Host ($body | ConvertTo-Json -Depth 8) -ForegroundColor DarkGray
    return
}

# --- 1. Create the query ---
$query = Invoke-MgGraphRequest -Method POST -Uri "$GraphBaseUri/security/auditLog/queries" `
    -Body ($body | ConvertTo-Json -Depth 8) -ContentType 'application/json'
$queryId = $query.id
Write-Host "  [query] created id=$queryId (status: $($query.status))" -ForegroundColor Green

# --- 2. Poll until terminal ---
$timeout = if ($PSBoundParameters.ContainsKey('PollTimeoutMinutes')) { $PollTimeoutMinutes }
    elseif ($cfg.pollTimeoutMinutes) { [int]$cfg.pollTimeoutMinutes } else { 30 }
$deadline = (Get-Date).AddMinutes($timeout)
$runningStates = @('notStarted', 'running', 'queued', 'inProgress')
do {
    Start-Sleep -Seconds 15
    $query = Invoke-MgGraphRequest -Method GET -Uri "$GraphBaseUri/security/auditLog/queries/$queryId"
    $status = "$($query.status)"
    Write-Host "  [poll] status: $status" -ForegroundColor DarkGray
    if ($status -and $runningStates -notcontains $status) { break }
} while ((Get-Date) -lt $deadline)

if ($runningStates -contains "$($query.status)") {
    throw "Audit query $queryId did not complete within $timeout minute(s) (status: $($query.status)). Re-check later with Get on the query id."
}
if ("$($query.status)" -notmatch 'succeed') {
    Write-Warning "Audit query finished with status '$($query.status)' (expected a 'succeeded'-like status - see README.md Section 11 VERIFY). Attempting to read records anyway."
}

# --- 3. Retrieve records (paged) ---
$records = [System.Collections.Generic.List[object]]::new()
$next = "$GraphBaseUri/security/auditLog/queries/$queryId/records"
while ($next) {
    $page = Invoke-MgGraphRequest -Method GET -Uri $next
    foreach ($r in @($page.value)) { $records.Add($r) }
    $next = $page.'@odata.nextLink'
}
Write-Host "  [records] retrieved $($records.Count)" -ForegroundColor Green

# --- 4. Export ---
$outRoot = if ($OutDir) { $OutDir } elseif ($cfg.export.outDir) { $cfg.export.outDir } else { './out' }
if (-not (Test-Path -LiteralPath $outRoot)) { New-Item -ItemType Directory -Path $outRoot -Force | Out-Null }
$stamp = (Get-Date -Format 'yyyyMMdd-HHmmss')
$base = Join-Path $outRoot "audit-$stamp"
$formats = if ($cfg.export.formats) { @($cfg.export.formats) } else { @('csv', 'json') }

if ($formats -contains 'json') {
    $records | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath "$base.json" -Encoding utf8
    Write-Host "  [export] $base.json" -ForegroundColor Cyan
}
if ($formats -contains 'csv') {
    $records | ForEach-Object {
        [pscustomobject]@{
            createdDateTime     = $_.createdDateTime
            userPrincipalName   = $_.userPrincipalName
            userId              = $_.userId
            operation           = $_.operation
            service             = $_.service
            auditLogRecordType  = $_.auditLogRecordType
            clientIp            = $_.clientIp
            objectId            = $_.objectId
        }
    } | Sort-Object createdDateTime | Export-Csv -LiteralPath "$base.csv" -NoTypeInformation -Encoding utf8
    Write-Host "  [export] $base.csv" -ForegroundColor Cyan
}

# --- Summary ---
Write-Host "`nTop operations:" -ForegroundColor Cyan
$records | Group-Object operation | Sort-Object Count -Descending | Select-Object -First 15 |
    ForEach-Object { Write-Host ("  {0,6}  {1}" -f $_.Count, $_.Name) }
Write-Host "`nDone. $($records.Count) record(s) exported to $outRoot." -ForegroundColor Cyan
Write-Host "Handle the export as evidence - it can contain sensitive content/PII (see rollback.md)." -ForegroundColor Yellow
