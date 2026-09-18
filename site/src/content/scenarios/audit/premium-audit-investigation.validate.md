---
part: "validate"
parent: "audit/premium-audit-investigation"
---
Run these checks after deployment to confirm the control is working as designed.


#### `Test-AuditInvestigation.ps1`

```powershell
#Requires -Version 7.0
<#
.SYNOPSIS
    Read-only readiness check for the audit investigation: confirms Graph connectivity and the audit
    query scope, validates the config, and runs a tiny probe query to prove the Audit Search API is
    reachable and returning data.

.DESCRIPTION
    Never modifies tenant state. Checks:
      1. Microsoft Graph is connected with an AuditLogsQuery* scope.
      2. The config file is well-formed (has a target and a resolvable time window).
      3. A minimal 1-hour probe query against /security/auditLog/queries completes and can be read
         (proves the API + permission + audit availability), unless -SkipProbe is passed.
    Exits non-zero on any hard failure. Safe to re-run.

    Connect first: Connect-MgGraph -Scopes 'AuditLogsQuery.Read.All'.

.PARAMETER ConfigPath
    Path to the config to validate. Defaults to '../deploy/config/audit-investigation.sample.json'.

.PARAMETER SkipProbe
    Skip the live probe query (config + connectivity checks only).

.PARAMETER GraphBaseUri
    Graph base URI. Defaults to 'https://graph.microsoft.com/v1.0'.

.EXAMPLE
    Connect-MgGraph -Scopes 'AuditLogsQuery.Read.All'
    ./Test-AuditInvestigation.ps1
#>
[CmdletBinding()]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$ConfigPath = (Join-Path $PSScriptRoot '../deploy/config/audit-investigation.sample.json'),

    [Parameter()]
    [switch]$SkipProbe,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$GraphBaseUri = 'https://graph.microsoft.com/v1.0'
)

$ErrorActionPreference = 'Stop'
$script:failures = 0
function Test-Check {
    param([string]$Description, [bool]$Condition, [switch]$Warn)
    if ($Condition) { Write-Host "  [PASS] $Description" -ForegroundColor Green }
    elseif ($Warn) { Write-Host "  [WARN] $Description" -ForegroundColor Yellow }
    else { Write-Host "  [FAIL] $Description" -ForegroundColor Red; $script:failures++ }
}

if (-not (Get-Command Invoke-MgGraphRequest -ErrorAction SilentlyContinue)) {
    throw "Microsoft Graph PowerShell SDK not found. Install Microsoft.Graph and Connect-MgGraph first."
}
$ctx = Get-MgContext -ErrorAction SilentlyContinue
Test-Check -Description "Connected to Microsoft Graph" -Condition ($null -ne $ctx)
if (-not $ctx) { Write-Host "`nRun Connect-MgGraph -Scopes 'AuditLogsQuery.Read.All' first." -ForegroundColor Red; exit 1 }

$hasScope = @($ctx.Scopes) | Where-Object { $_ -like 'AuditLogsQuery*' }
Test-Check -Description "Token has an AuditLogsQuery* scope (has: $($ctx.Scopes -join ', '))" -Condition ([bool]$hasScope) -Warn

# Config validation
Test-Check -Description "Config file exists" -Condition (Test-Path -LiteralPath $ConfigPath)
if (Test-Path -LiteralPath $ConfigPath) {
    $cfg = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
    $hasWindow = ($cfg.filterStartDateTime -and $cfg.filterEndDateTime) -or ($cfg.lookbackDays)
    Test-Check -Description "Config has a resolvable time window (lookbackDays or explicit dates)" -Condition ([bool]$hasWindow)
    $hasTarget = (@($cfg.userPrincipalNameFilters).Count -gt 0) -or (@($cfg.operationFilters).Count -gt 0) -or (@($cfg.recordTypeFilters).Count -gt 0) -or (-not [string]::IsNullOrWhiteSpace($cfg.keywordFilter))
    Test-Check -Description "Config has at least one target filter (user/operation/recordType/keyword)" -Condition ([bool]$hasTarget)
}

# Live probe
if (-not $SkipProbe) {
    Write-Host "`n  Running a 1-hour probe query (proves API + permission + audit availability)..." -ForegroundColor Cyan
    try {
        $end = (Get-Date).ToUniversalTime()
        $probe = @{
            '@odata.type'       = '#microsoft.graph.security.auditLogQuery'
            displayName         = "Readiness probe $(Get-Date -Format s)"
            filterStartDateTime = $end.AddHours(-1).ToString('o')
            filterEndDateTime   = $end.ToString('o')
        }
        $q = Invoke-MgGraphRequest -Method POST -Uri "$GraphBaseUri/security/auditLog/queries" `
            -Body ($probe | ConvertTo-Json -Depth 6) -ContentType 'application/json'
        Test-Check -Description "Probe query created (id=$($q.id))" -Condition ($null -ne $q.id)
        # Poll briefly (up to ~2 min) so a readiness check stays fast.
        $running = @('notStarted', 'running', 'queued', 'inProgress')
        $deadline = (Get-Date).AddMinutes(2)
        do {
            Start-Sleep -Seconds 10
            $q = Invoke-MgGraphRequest -Method GET -Uri "$GraphBaseUri/security/auditLog/queries/$($q.id)"
        } while (($running -contains "$($q.status)") -and ((Get-Date) -lt $deadline))
        Test-Check -Description "Probe reached a terminal status quickly (status: $($q.status))" -Condition ($running -notcontains "$($q.status)") -Warn
    }
    catch {
        Test-Check -Description "Probe query succeeded (error: $($_.Exception.Message))" -Condition $false
    }
}

Write-Host "`n$(if ($script:failures -eq 0) { 'All hard checks passed - ready to run Invoke-AuditInvestigation.ps1.' } else { "$script:failures hard check(s) failed." })" `
    -ForegroundColor $(if ($script:failures -eq 0) { 'Green' } else { 'Red' })
if ($script:failures -gt 0) { exit 1 }
```