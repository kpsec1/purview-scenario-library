#Requires -Version 7.0
<#
.SYNOPSIS
    Rolls back the eDiscovery (Premium) matter created by New-EdiscoveryHoldAndCollect.ps1: releases
    (disables) the legal hold, and - with -Delete - deletes the hold and the collection search.

.DESCRIPTION
    Uses the Microsoft Graph eDiscovery API (v1.0 security namespace) via Invoke-MgGraphRequest.
    Staged rollback:
      Default    Release preservation: PATCH the legal hold to isEnabled = false. The case,
                 custodians, search, and any collected/exported content remain.
      -Delete    Additionally DELETE the legal hold and the collection search.

    Releasing a legal hold ends preservation-in-place - do this ONLY when Legal confirms the matter
    (and any litigation-hold obligation) is over. This script never deletes collected content, review
    sets, or exports, and does not delete the case or release custodians (those are deliberate,
    separately-governed steps - see rollback.md).

    Real -WhatIf works here. Connect first with Connect-MgGraph -Scopes 'eDiscovery.ReadWrite.All'.

.PARAMETER ConfigPath
    Path to the same JSON config used to deploy. Defaults to 'config/legal-hold-case.sample.json'.
    Only caseName, legalHold.name, and search.name are read here.

.PARAMETER Delete
    Delete the legal hold and collection search after releasing the hold.

.PARAMETER GraphBaseUri
    Graph base URI. Defaults to 'https://graph.microsoft.com/v1.0'.

.EXAMPLE
    Connect-MgGraph -Scopes 'eDiscovery.ReadWrite.All'
    ./Remove-EdiscoveryHoldAndCollect.ps1 -WhatIf

.EXAMPLE
    Connect-MgGraph -Scopes 'eDiscovery.ReadWrite.All'
    ./Remove-EdiscoveryHoldAndCollect.ps1 -Delete

.NOTES
    Grounded in Microsoft Learn: eDiscovery API (v1.0 security namespace) - legalHold update/delete,
    search delete. https://learn.microsoft.com/graph/api/resources/security-ediscovery-apioverview?view=graph-rest-1.0
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$ConfigPath = (Join-Path $PSScriptRoot 'config/legal-hold-case.sample.json'),

    [Parameter()]
    [switch]$Delete,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$GraphBaseUri = 'https://graph.microsoft.com/v1.0'
)

$ErrorActionPreference = 'Stop'

if (-not (Get-Command Invoke-MgGraphRequest -ErrorAction SilentlyContinue)) {
    throw "Microsoft Graph PowerShell SDK not found. Install Microsoft.Graph and Connect-MgGraph first."
}
if (-not (Get-MgContext -ErrorAction SilentlyContinue)) {
    throw "Not connected to Microsoft Graph. Run Connect-MgGraph -Scopes 'eDiscovery.ReadWrite.All' first."
}
if (-not (Test-Path -LiteralPath $ConfigPath)) { throw "Config file not found: $ConfigPath" }
$cfg = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
if (-not $cfg.caseName) { throw "Config is missing 'caseName'." }

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

$casesUri = "$GraphBaseUri/security/cases/ediscoveryCases"
$case = Get-GraphAll -Uri $casesUri | Where-Object { $_.displayName -eq $cfg.caseName } | Select-Object -First 1
if (-not $case) {
    Write-Host "Case '$($cfg.caseName)' not found. Nothing to do." -ForegroundColor DarkGray
    return
}
$caseBase = "$casesUri/$($case.id)"

# --- Release (disable) the legal hold ---
if ($cfg.legalHold -and $cfg.legalHold.name) {
    $hold = Get-GraphAll -Uri "$caseBase/legalHolds" | Where-Object { $_.displayName -eq $cfg.legalHold.name } | Select-Object -First 1
    if ($hold) {
        if ($PSCmdlet.ShouldProcess("Legal hold '$($cfg.legalHold.name)'", 'Release (isEnabled=false)')) {
            Invoke-MgGraphRequest -Method PATCH -Uri "$caseBase/legalHolds/$($hold.id)" `
                -Body (@{ isEnabled = $false } | ConvertTo-Json) -ContentType 'application/json' | Out-Null
            Write-Host "  [release] hold '$($cfg.legalHold.name)' disabled." -ForegroundColor Yellow
        }
        if ($Delete -and $PSCmdlet.ShouldProcess("Legal hold '$($cfg.legalHold.name)'", 'Delete')) {
            Invoke-MgGraphRequest -Method DELETE -Uri "$caseBase/legalHolds/$($hold.id)" | Out-Null
            Write-Host "  [delete] hold '$($cfg.legalHold.name)' removed." -ForegroundColor Red
        }
    }
    else { Write-Host "  [release] hold '$($cfg.legalHold.name)' not found." -ForegroundColor DarkGray }
}

# --- Delete the collection search (only with -Delete) ---
if ($Delete -and $cfg.search -and $cfg.search.name) {
    $search = Get-GraphAll -Uri "$caseBase/searches" | Where-Object { $_.displayName -eq $cfg.search.name } | Select-Object -First 1
    if ($search -and $PSCmdlet.ShouldProcess("Search '$($cfg.search.name)'", 'Delete')) {
        Invoke-MgGraphRequest -Method DELETE -Uri "$caseBase/searches/$($search.id)" | Out-Null
        Write-Host "  [delete] search '$($cfg.search.name)' removed." -ForegroundColor Red
    }
}

Write-Host "`nDone." -ForegroundColor Cyan
Write-Host "Not touched (deliberately): collected content, review sets, exports, custodians, and the case itself. Release custodians and close the case in the portal when Legal confirms the matter is over - see rollback.md." -ForegroundColor Yellow
