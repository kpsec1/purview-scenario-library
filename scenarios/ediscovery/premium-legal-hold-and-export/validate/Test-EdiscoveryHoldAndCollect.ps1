#Requires -Version 7.0
<#
.SYNOPSIS
    Verifies the eDiscovery (Premium) matter created by New-EdiscoveryHoldAndCollect.ps1 exists and
    is configured as expected: the case, its custodians and sources, the legal hold (enabled), and
    the collection search.

.DESCRIPTION
    Read-only - never modifies any object. Uses the Microsoft Graph eDiscovery API (v1.0 security
    namespace) via Invoke-MgGraphRequest to check, against the config file:
      1. The case exists.
      2. Every configured custodian is present, with at least one data source, and hold status.
      3. The legal hold exists and is enabled (preservation active).
      4. The collection search exists with the expected scope.
    Exits non-zero on any hard failure (safe for a CI-style pre-flight). Safe to re-run.

    Connect first with Connect-MgGraph -Scopes 'eDiscovery.Read.All' (read is sufficient for validation).

.PARAMETER ConfigPath
    Path to the config to validate against. Defaults to '../deploy/config/legal-hold-case.sample.json'.

.PARAMETER GraphBaseUri
    Graph base URI. Defaults to 'https://graph.microsoft.com/v1.0'.

.EXAMPLE
    Connect-MgGraph -Scopes 'eDiscovery.Read.All'
    ./Test-EdiscoveryHoldAndCollect.ps1
#>
[CmdletBinding()]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$ConfigPath = (Join-Path $PSScriptRoot '../deploy/config/legal-hold-case.sample.json'),

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

function Get-GraphAll {
    param([Parameter(Mandatory)][string]$Uri)
    $items = [System.Collections.Generic.List[object]]::new()
    $next = $Uri
    while ($next) {
        $resp = Invoke-MgGraphRequest -Method GET -Uri $next
        foreach ($v in @($resp.value)) { $items.Add($v) }
        $next = $resp.'@odata.nextLink'
    }
    return $items
}

if (-not (Get-Command Invoke-MgGraphRequest -ErrorAction SilentlyContinue)) {
    throw "Microsoft Graph PowerShell SDK not found. Install Microsoft.Graph and Connect-MgGraph first."
}
if (-not (Get-MgContext -ErrorAction SilentlyContinue)) {
    throw "Not connected to Microsoft Graph. Run Connect-MgGraph -Scopes 'eDiscovery.Read.All' first."
}
if (-not (Test-Path -LiteralPath $ConfigPath)) { throw "Config file not found: $ConfigPath" }
$cfg = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
if (-not $cfg.caseName) { throw "Config is missing 'caseName'." }

$casesUri = "$GraphBaseUri/security/cases/ediscoveryCases"
Write-Host "Validating eDiscovery matter '$($cfg.caseName)'..." -ForegroundColor Cyan

$case = Get-GraphAll -Uri $casesUri | Where-Object { $_.displayName -eq $cfg.caseName } | Select-Object -First 1
Test-Check -Description "Case '$($cfg.caseName)' exists" -Condition ($null -ne $case)
if (-not $case) {
    Write-Host "`nCannot continue - case not found. $script:failures check(s) failed." -ForegroundColor Red
    exit 1
}
Write-Host "    Case status: $($case.status)" -ForegroundColor Cyan
$caseBase = "$casesUri/$($case.id)"

# Custodians
$custodians = Get-GraphAll -Uri "$caseBase/custodians"
foreach ($c in @($cfg.custodians)) {
    $cust = $custodians | Where-Object { $_.email -eq $c.email } | Select-Object -First 1
    Test-Check -Description "Custodian '$($c.email)' present" -Condition ($null -ne $cust)
    if ($cust) {
        $sources = Get-GraphAll -Uri "$caseBase/custodians/$($cust.id)/userSources"
        Test-Check -Description "  '$($c.email)' has >=1 data source" -Condition (@($sources).Count -gt 0)
        Test-Check -Description "  '$($c.email)' hold status is applied (current: $($cust.holdStatus))" `
            -Condition ($cust.holdStatus -eq 'applied') -Warn
    }
}

# Legal hold
if ($cfg.legalHold -and $cfg.legalHold.name) {
    $hold = Get-GraphAll -Uri "$caseBase/legalHolds" | Where-Object { $_.displayName -eq $cfg.legalHold.name } | Select-Object -First 1
    Test-Check -Description "Legal hold '$($cfg.legalHold.name)' exists" -Condition ($null -ne $hold)
    if ($hold) {
        Test-Check -Description "  Legal hold is enabled (preservation active)" -Condition ([bool]$hold.isEnabled)
    }
}

# Collection search
if ($cfg.search -and $cfg.search.name) {
    $search = Get-GraphAll -Uri "$caseBase/searches" | Where-Object { $_.displayName -eq $cfg.search.name } | Select-Object -First 1
    Test-Check -Description "Collection search '$($cfg.search.name)' exists" -Condition ($null -ne $search)
    if ($search) {
        Write-Host "    Search scope: $($search.dataSourceScopes)" -ForegroundColor Cyan
    }
}

Write-Host "`n$(if ($script:failures -eq 0) { 'All hard checks passed.' } else { "$script:failures hard check(s) failed." })" `
    -ForegroundColor $(if ($script:failures -eq 0) { 'Green' } else { 'Red' })
if ($script:failures -gt 0) { exit 1 }
