#Requires -Version 7.0
<#
.SYNOPSIS
    Stands up a Microsoft Purview eDiscovery (Premium) matter as code: creates the case, adds
    custodians and their mailbox/site data sources, places a legal hold, and creates a collection
    search - and, optionally, exports a review set.

.DESCRIPTION
    Uses the Microsoft Graph eDiscovery API (v1.0 security namespace) via the Microsoft Graph
    PowerShell SDK (Invoke-MgGraphRequest) - automation surface 3 per docs/automation-surface.md - to
    build a repeatable legal-hold-and-collection workflow:
      1. Case:       POST /security/cases/ediscoveryCases
      2. Custodians: POST .../{caseId}/custodians  +  .../custodians/{id}/userSources (mailbox[/site])
      3. Legal hold: POST .../{caseId}/legalHolds (isEnabled = true)  -> preservation
      4. Search:     POST .../{caseId}/searches (KQL contentQuery, dataSourceScopes) -> collection
      5. Export:     POST .../{caseId}/reviewSets/{reviewSetId}/export   (only with -Export)

    Idempotent: each object is located in its case by its natural key (case/hold/search by
    displayName, custodian by email) via a paged GET before create, so re-running reconciles rather
    than duplicating. Real -WhatIf works here (unlike Security & Compliance PowerShell) because every
    mutating call is wrapped in $PSCmdlet.ShouldProcess.

    Connect first: Connect-MgGraph -Scopes 'eDiscovery.ReadWrite.All' (delegated - the signed-in user
    needs the eDiscovery Manager or Administrator Purview role), or app-only with a certificate
    (requires E5/Premium - see README.md Section 3). This script does not open the session.

    Author-only reference code. Placing a legal hold and collecting content are consequential,
    legally significant actions - review with -WhatIf, and with Legal, before running for real.

.PARAMETER ConfigPath
    Path to the JSON config. Defaults to the sibling 'config/legal-hold-case.sample.json'.

.PARAMETER Export
    Also start an export from a review set (requires -ReviewSetId). Committing collected content into
    the review set (addToReviewSet) is a prerequisite - see README.md Section 11.

.PARAMETER ReviewSetId
    The eDiscovery review set GUID to export (required with -Export).

.PARAMETER GraphBaseUri
    Graph base URI. Defaults to 'https://graph.microsoft.com/v1.0'.

.EXAMPLE
    Connect-MgGraph -Scopes 'eDiscovery.ReadWrite.All'
    ./New-EdiscoveryHoldAndCollect.ps1 -WhatIf

    Dry-run: shows the case, custodians, hold, and search that would be created.

.EXAMPLE
    Connect-MgGraph -Scopes 'eDiscovery.ReadWrite.All'
    ./New-EdiscoveryHoldAndCollect.ps1 -Export -ReviewSetId '273f11a1-17aa-419c-981d-ff10d33e420f'

.NOTES
    Grounded in Microsoft Learn (verify before production use):
    - eDiscovery API overview / case / custodian / userSource / legalHold / search / reviewSet export
      (v1.0 security namespace): https://learn.microsoft.com/graph/api/resources/security-ediscovery-apioverview?view=graph-rest-1.0
    - Create ediscoveryCase / custodians / userSources / searches / reviewSet: export (request bodies)
    - Assign permissions in eDiscovery (eDiscovery Manager/Administrator roles):
      https://learn.microsoft.com/purview/edisc-permissions

    VERIFY (README.md Section 11): committing search results into a review set (the addToReviewSet
    action) is a prerequisite for -Export and is not scripted here (its exact action body wasn't
    exercised in this build); binding specific custodian sources to the legalHold vs. a broad
    preservation hold is a legal-scoping decision - see design.md.
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$ConfigPath = (Join-Path $PSScriptRoot 'config/legal-hold-case.sample.json'),

    [Parameter()]
    [switch]$Export,

    [Parameter()]
    [ValidatePattern('^[0-9a-fA-F-]{10,}$')]
    [string]$ReviewSetId,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$GraphBaseUri = 'https://graph.microsoft.com/v1.0'
)

$ErrorActionPreference = 'Stop'

function Assert-MgConnected {
    if (-not (Get-Command Invoke-MgGraphRequest -ErrorAction SilentlyContinue)) {
        throw "Microsoft Graph PowerShell SDK not found. Install Microsoft.Graph and run Connect-MgGraph -Scopes 'eDiscovery.ReadWrite.All'."
    }
    if (-not (Get-MgContext -ErrorAction SilentlyContinue)) {
        throw "Not connected to Microsoft Graph. Run Connect-MgGraph -Scopes 'eDiscovery.ReadWrite.All' first (see docs/automation-surface.md Section 3)."
    }
}

function Get-GraphAll {
    # GET a collection, following @odata.nextLink, returning all items.
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

function Invoke-GraphWrite {
    param(
        [Parameter(Mandatory)][string]$Method,
        [Parameter(Mandatory)][string]$Uri,
        [Parameter()][hashtable]$Body,
        [Parameter(Mandatory)][string]$Target,
        [Parameter(Mandatory)][string]$Action
    )
    if (-not $PSCmdlet.ShouldProcess($Target, $Action)) {
        Write-Verbose "WhatIf: would $Method $Uri"
        if ($Body) { Write-Verbose ($Body | ConvertTo-Json -Depth 10) }
        return $null
    }
    $params = @{ Method = $Method; Uri = $Uri }
    if ($Body) { $params.Body = ($Body | ConvertTo-Json -Depth 10); $params.ContentType = 'application/json' }
    return Invoke-MgGraphRequest @params
}

# --- Load config ---
if (-not (Test-Path -LiteralPath $ConfigPath)) { throw "Config file not found: $ConfigPath" }
$cfg = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
if (-not $cfg.caseName) { throw "Config is missing 'caseName'." }
if ($Export -and -not $ReviewSetId) { throw "-Export requires -ReviewSetId." }

Assert-MgConnected
$casesUri = "$GraphBaseUri/security/cases/ediscoveryCases"

Write-Host "Deploying eDiscovery (Premium) matter '$($cfg.caseName)'." -ForegroundColor Cyan
Write-Host "NOTE: legal hold and collection are legally significant. Review with -WhatIf and with Legal before running for real." -ForegroundColor Yellow

# --- 1. Case ---
$case = Get-GraphAll -Uri $casesUri | Where-Object { $_.displayName -eq $cfg.caseName } | Select-Object -First 1
if (-not $case) {
    $body = @{ displayName = $cfg.caseName }
    if ($cfg.description) { $body.description = $cfg.description }
    if ($cfg.externalId) { $body.externalId = $cfg.externalId }
    $case = Invoke-GraphWrite -Method POST -Uri $casesUri -Body $body -Target "Case '$($cfg.caseName)'" -Action 'Create eDiscovery case'
    Write-Host "  [case] created $($cfg.caseName)" -ForegroundColor Green
}
else { Write-Host "  [case] exists $($cfg.caseName) ($($case.id))" -ForegroundColor DarkGreen }
$caseId = if ($case) { $case.id } else { '<whatif-case-id>' }
$caseBase = "$casesUri/$caseId"

# --- 2. Custodians + user sources ---
$existingCustodians = if ($case) { Get-GraphAll -Uri "$caseBase/custodians" } else { @() }
foreach ($c in @($cfg.custodians)) {
    $cust = $existingCustodians | Where-Object { $_.email -eq $c.email } | Select-Object -First 1
    if (-not $cust) {
        $cust = Invoke-GraphWrite -Method POST -Uri "$caseBase/custodians" -Body @{ email = $c.email } `
            -Target "Custodian '$($c.email)'" -Action 'Add custodian'
        Write-Host "  [custodian] added $($c.email)" -ForegroundColor Green
    }
    else { Write-Host "  [custodian] exists $($c.email)" -ForegroundColor DarkGreen }
    $custId = if ($cust) { $cust.id } else { '<whatif-custodian-id>' }

    $existingSources = if ($cust) { Get-GraphAll -Uri "$caseBase/custodians/$custId/userSources" } else { @() }
    $needed = @('mailbox')
    if ($c.includeSite) { $needed += 'site' }
    foreach ($src in $needed) {
        $have = $existingSources | Where-Object { "$($_.includedSources)" -match $src } | Select-Object -First 1
        if (-not $have) {
            Invoke-GraphWrite -Method POST -Uri "$caseBase/custodians/$custId/userSources" `
                -Body @{ email = $c.email; includedSources = $src } `
                -Target "userSource $src for '$($c.email)'" -Action "Add $src source" | Out-Null
            Write-Host "    [source] $src for $($c.email)" -ForegroundColor Green
        }
    }
}

# --- 3. Legal hold (preservation) ---
if ($cfg.legalHold -and $cfg.legalHold.name) {
    $holds = if ($case) { Get-GraphAll -Uri "$caseBase/legalHolds" } else { @() }
    $hold = $holds | Where-Object { $_.displayName -eq $cfg.legalHold.name } | Select-Object -First 1
    if (-not $hold) {
        $body = @{ displayName = $cfg.legalHold.name; isEnabled = $true }
        if ($cfg.legalHold.description) { $body.description = $cfg.legalHold.description }
        if (-not [string]::IsNullOrWhiteSpace($cfg.legalHold.contentQuery)) { $body.contentQuery = $cfg.legalHold.contentQuery }
        Invoke-GraphWrite -Method POST -Uri "$caseBase/legalHolds" -Body $body `
            -Target "Legal hold '$($cfg.legalHold.name)'" -Action 'Create legal hold (isEnabled=true)' | Out-Null
        Write-Host "  [hold] created '$($cfg.legalHold.name)' (enabled)" -ForegroundColor Green
    }
    else { Write-Host "  [hold] exists '$($cfg.legalHold.name)'" -ForegroundColor DarkGreen }
}

# --- 4. Collection search ---
if ($cfg.search -and $cfg.search.name) {
    $searches = if ($case) { Get-GraphAll -Uri "$caseBase/searches" } else { @() }
    $search = $searches | Where-Object { $_.displayName -eq $cfg.search.name } | Select-Object -First 1
    if (-not $search) {
        $body = @{ displayName = $cfg.search.name }
        if ($cfg.search.description) { $body.description = $cfg.search.description }
        if (-not [string]::IsNullOrWhiteSpace($cfg.search.contentQuery)) { $body.contentQuery = $cfg.search.contentQuery }
        if ($cfg.search.dataSourceScopes) { $body.dataSourceScopes = $cfg.search.dataSourceScopes }
        Invoke-GraphWrite -Method POST -Uri "$caseBase/searches" -Body $body `
            -Target "Search '$($cfg.search.name)'" -Action 'Create collection search' | Out-Null
        Write-Host "  [search] created '$($cfg.search.name)' (scope: $($cfg.search.dataSourceScopes))" -ForegroundColor Green
    }
    else { Write-Host "  [search] exists '$($cfg.search.name)'" -ForegroundColor DarkGreen }
}

# --- 5. Export (opt-in) ---
if ($Export) {
    $ex = $cfg.export
    if (-not $ex -or -not $ex.outputName) { throw "-Export set but config has no export.outputName." }
    $body = @{ outputName = $ex.outputName }
    if ($ex.description) { $body.description = $ex.description }
    if ($ex.exportOptions) { $body.exportOptions = $ex.exportOptions }
    if ($ex.exportStructure) { $body.exportStructure = $ex.exportStructure }
    $exportUri = "$caseBase/reviewSets/$ReviewSetId/export"
    Invoke-GraphWrite -Method POST -Uri $exportUri -Body $body `
        -Target "Review set $ReviewSetId" -Action "Start export '$($ex.outputName)'" | Out-Null
    Write-Host "  [export] started '$($ex.outputName)' from review set $ReviewSetId (async - poll the case operations / portal)." -ForegroundColor Cyan
}

Write-Host "`nDone. Case '$($cfg.caseName)' reconciled." -ForegroundColor Cyan
if (-not $Export) {
    Write-Host "Collection search created but not run/committed. Run the search and commit results to a review set (portal or a follow-on), then re-run with -Export -ReviewSetId. See README.md Section 5." -ForegroundColor Yellow
}
