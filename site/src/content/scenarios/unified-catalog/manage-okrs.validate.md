---
part: "validate"
parent: "unified-catalog/manage-okrs"
---
Run these checks after deployment to confirm the control is working as designed.


#### `Test-Okr.ps1`

```powershell
#Requires -Version 7.0
<#
.SYNOPSIS
    Verifies an objective (OKR), its key results, and its data-product links, deployed by
    New-Okr.ps1, match the definition file.

.DESCRIPTION
    Read-only validation script - calls only GET/Query, never modifies state. Checks:
      1. The governance domain exists.
      2. The objective exists (looked up by the definition file's caller-generated id - design.md
         Section 3, not by name), with the expected definition text/target date, and reports (does
         not fail on) Draft vs. Published status.
      3. Each key result in the definition file exists under that objective with the expected
         definition/progress/goal/max/status.
      4. Each data product named in relatedDataProducts exists and reports (does not fail on)
         whether it is linked to the objective (entityType=OBJECTIVE on that data product's own
         Data Products - List Relationships) - a hard [FAIL] here would conflate "not yet
         deployed" with "genuinely missing," so this is reported as [WARN] the same way
         manage-critical-data-elements/validate/Test-CriticalDataElement.ps1 treats its own
         DATAPRODUCT cross-check.
    Exits with a non-zero code if any hard check fails. Safe to re-run any number of times.

.PARAMETER PurviewAccountEndpoint
    Base URL of the Purview Unified Catalog data-plane API - must match the value used at deploy
    time.

.PARAMETER TenantId
    Microsoft Entra tenant ID.

.PARAMETER AppId
    Application (client) ID of a service principal holding at least Data Steward / Governance
    Domain Reader on the target domain.

.PARAMETER ClientSecret
    Client secret for -AppId, as a SecureString.

.PARAMETER DefinitionPath
    Path to the same OKR definition JSON file passed to New-Okr.ps1.

.PARAMETER ApiVersion
    Unified Catalog REST API version to pin. Defaults to '2026-03-20-preview'.

.EXAMPLE
    ./Test-Okr.ps1 -PurviewAccountEndpoint 'https://api.purview-service.microsoft.com' `
        -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
        -DefinitionPath '../deploy/config/customer-data-trust-okr.sample.json'
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$PurviewAccountEndpoint,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$TenantId,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$AppId,

    [Parameter(Mandatory)]
    [SecureString]$ClientSecret,

    [Parameter(Mandatory)]
    [ValidateScript({ Test-Path $_ -PathType Leaf })]
    [string]$DefinitionPath,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$ApiVersion = '2026-03-20-preview'
)

$ErrorActionPreference = 'Stop'
$endpoint = $PurviewAccountEndpoint.TrimEnd('/')
$script:failures = 0

function Test-Check {
    param([string]$Description, [bool]$Condition, [switch]$Warn)
    if ($Condition) {
        Write-Host "  [PASS] $Description" -ForegroundColor Green
    }
    elseif ($Warn) {
        Write-Host "  [WARN] $Description" -ForegroundColor Yellow
    }
    else {
        Write-Host "  [FAIL] $Description" -ForegroundColor Red
        $script:failures++
    }
}

function ConvertTo-PlainText {
    param([Parameter(Mandatory)][SecureString]$Secure)
    $ptr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($Secure)
    try { return [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($ptr) }
    finally { [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr) }
}

function Get-PurviewAccessToken {
    param([Parameter(Mandatory)][string]$TenantId, [Parameter(Mandatory)][string]$AppId, [Parameter(Mandatory)][string]$PlainSecret)
    $body = @{ client_id = $AppId; client_secret = $PlainSecret; grant_type = 'client_credentials'; resource = 'https://purview.azure.net' }
    $response = Invoke-RestMethod -Method Post -Uri "https://login.microsoftonline.com/$TenantId/oauth2/token" -Body $body
    return $response.access_token
}

function Invoke-UcmGet {
    param([Parameter(Mandatory)][string]$Uri, [Parameter(Mandatory)][string]$Token, [switch]$TreatNotFoundAsNull)
    try { return Invoke-RestMethod -Method Get -Uri $Uri -Headers @{ Authorization = "Bearer $Token" } }
    catch {
        if ($TreatNotFoundAsNull -and $_.Exception.Response -and $_.Exception.Response.StatusCode.value__ -eq 404) { return $null }
        throw
    }
}

function Invoke-UcmPost {
    param([Parameter(Mandatory)][string]$Uri, [Parameter(Mandatory)][hashtable]$Body, [Parameter(Mandatory)][string]$Token)
    return Invoke-RestMethod -Method Post -Uri $Uri -Body ($Body | ConvertTo-Json -Depth 10) -ContentType 'application/json' -Headers @{ Authorization = "Bearer $Token" }
}

function Find-BusinessDomainByName {
    param([Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)][string]$Token)
    $uri = "$endpoint/datagovernance/catalog/businessdomains?api-version=$ApiVersion"
    while ($uri) {
        $page = Invoke-UcmGet -Uri $uri -Token $Token
        $match = $page.value | Where-Object { $_.name -eq $Name } | Select-Object -First 1
        if ($match) { return $match }
        $uri = $page.nextLink
    }
    return $null
}

function Find-DataProductByName {
    param([Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)][string]$DomainId, [Parameter(Mandatory)][string]$Token)
    $uri = "$endpoint/datagovernance/catalog/dataProducts/query?api-version=$ApiVersion"
    $body = @{ domainIds = @($DomainId); nameKeyword = $Name; top = 50 }
    $response = Invoke-UcmPost -Uri $uri -Body $body -Token $Token
    return ($response.value | Where-Object { $_.name -eq $Name } | Select-Object -First 1)
}

$definition = Get-Content -Path $DefinitionPath -Raw | ConvertFrom-Json
$plainSecret = ConvertTo-PlainText -Secure $ClientSecret
try { $token = Get-PurviewAccessToken -TenantId $TenantId -AppId $AppId -PlainSecret $plainSecret }
finally { $plainSecret = $null }

Write-Host "Validating governance domain '$($definition.domain.name)'..." -ForegroundColor Cyan
$domain = Find-BusinessDomainByName -Name $definition.domain.name -Token $token
Test-Check -Description "Governance domain '$($definition.domain.name)' exists" -Condition ($null -ne $domain)
if (-not $domain) {
    Write-Host "`nCannot continue - domain not found. $script:failures check(s) failed." -ForegroundColor Red
    exit 1
}

Write-Host "`nValidating objective (id: $($definition.objective.id))..." -ForegroundColor Cyan
$objectiveUri = "$endpoint/datagovernance/catalog/objectives/$($definition.objective.id)?api-version=$ApiVersion"
$objective = Invoke-UcmGet -Uri $objectiveUri -Token $token -TreatNotFoundAsNull
Test-Check -Description "Objective '$($definition.objective.definition)' exists (by id)" -Condition ($null -ne $objective)
if (-not $objective) {
    Write-Host "`nCannot continue - objective not found. $script:failures check(s) failed." -ForegroundColor Red
    exit 1
}
Test-Check -Description 'Definition text matches the definition file' -Condition ($objective.definition -eq $definition.objective.definition)
Test-Check -Description 'Domain matches the definition file' -Condition ($objective.domain -eq $domain.id)
Test-Check -Description 'At least one owner contact is set' -Condition ($null -ne $objective.contacts.owner -and $objective.contacts.owner.Count -gt 0)
Test-Check -Description "Objective is published" -Condition ($objective.status -eq 'Published') -Warn

Write-Host "`nValidating key results..." -ForegroundColor Cyan
foreach ($kr in $definition.keyResults) {
    $krUri = "$endpoint/datagovernance/catalog/objectives/$($definition.objective.id)/keyResults/$($kr.id)?api-version=$ApiVersion"
    $deployed = Invoke-UcmGet -Uri $krUri -Token $token -TreatNotFoundAsNull
    Test-Check -Description "Key result '$($kr.definition)' exists (by id)" -Condition ($null -ne $deployed)
    if ($deployed) {
        Test-Check -Description "  ...definition text matches" -Condition ($deployed.definition -eq $kr.definition)
        Test-Check -Description "  ...goal/max/progress match ($($kr.progress)/$($kr.goal)/$($kr.max))" `
            -Condition ($deployed.goal -eq $kr.goal -and $deployed.max -eq $kr.max -and $deployed.progress -eq $kr.progress)
        Test-Check -Description "  ...status matches ('$($kr.status)')" -Condition ($deployed.status -eq $kr.status)
    }
}

Write-Host "`nValidating data-product links..." -ForegroundColor Cyan
foreach ($productName in $definition.relatedDataProducts) {
    $product = Find-DataProductByName -Name $productName -DomainId $domain.id -Token $token
    if (-not $product) {
        Write-Host "  [INFO] Data product '$productName' not found in this domain - run scenarios/unified-catalog/manage-data-products/ first to exercise this check." -ForegroundColor Yellow
        continue
    }
    $relUri = "$endpoint/datagovernance/catalog/dataProducts/$($product.id)/relationships?api-version=$ApiVersion&entityType=OBJECTIVE"
    $relationships = Invoke-UcmGet -Uri $relUri -Token $token
    Test-Check -Description "Data product '$productName' is linked to this objective (entityType=OBJECTIVE)" `
        -Condition ([bool]($relationships.value | Where-Object { $_.entityId -eq $definition.objective.id })) -Warn
}

Write-Host "`n$(if ($script:failures -eq 0) { 'All hard checks passed.' } else { "$script:failures hard check(s) failed." })" `
    -ForegroundColor $(if ($script:failures -eq 0) { 'Green' } else { 'Red' })

if ($script:failures -gt 0) { exit 1 }
```

#### `Test-OkrProgressTrend.ps1`

```powershell
#Requires -Version 7.0
<#
.SYNOPSIS
    Read-only integrity check for the OKR progress-trend log deploy/Export-OkrProgressTrend.ps1
    produces, plus an optional live-reconciliation completeness check and the -FailOnStale gate a
    recurring scheduled check or CI pipeline should wire into.

.DESCRIPTION
    Three categories of check, matching
    scan-credential-inventory-report/validate/Test-CredentialInventoryReport.ps1's own two-category
    shape (file integrity + optional live reconciliation), plus a staleness gate specific to this
    companion:
      1. Trend-log file integrity (no Purview call needed): the file has at least one row, every
         expected column is present, no duplicate (RunId, EntityId) rows (proof
         Export-OkrProgressTrend.ps1's own replace-by-RunId idempotency design is actually holding),
         and no row is simultaneously 'Baseline' ChangeState and Stale='True' (a first-ever-seen
         entity can never already be stale - catches a corrupted or hand-edited trend log).
      2. Staleness gate (no Purview call needed, only if -FailOnStale is set): fails the run if the
         MOST RECENT RunId's rows contain any Stale='True' entity - the check a CI/scheduled
         pipeline should gate an alert (not a deployment) on. Off by default so this script can run
         as a pure file-integrity check without an opinion on how long is too long.
      3. Live reconciliation (Okr - Get / Get Key Result calls, read-only): re-fetches the objective
         and every key result named in -DefinitionPath and confirms the most recent run's trend-log
         rows cover the same entity-id set - catching a trend log that's stale itself (missing an
         entity added to the definition file after the last export ran), a different completeness
         question from staleness gate 2.
    Exits with a non-zero code if any hard check fails - safe to wire into a recurring scheduled
    check or CI pipeline gate, the same pattern this repo's other validate/ scripts use.

.PARAMETER TrendLogPath
    Path to the trend-log CSV produced by deploy/Export-OkrProgressTrend.ps1.

.PARAMETER FailOnStale
    If set, treats any Stale='True' row in the most recent run as a hard [FAIL] rather than an
    informational [WARN]. Off by default - see .PARAMETER FailOnStale's rationale in
    deploy/Export-OkrProgressTrend.ps1's own header (this script's gate, not that script's).

.PARAMETER PurviewAccountEndpoint
    Base URL of the Purview Unified Catalog data-plane API. Required only for the live-
    reconciliation check (3, above) - omit together with the other auth parameters and
    -DefinitionPath to run the file-integrity and staleness-gate checks (1, 2) only.

.PARAMETER TenantId
    Microsoft Entra tenant ID. Required only for the live-reconciliation check.

.PARAMETER AppId
    Application (client) ID of a service principal holding at least Data Steward / Governance
    Domain Reader on the target domain. Required only for the live-reconciliation check.

.PARAMETER ClientSecret
    Client secret for -AppId, as a SecureString. Required only for the live-reconciliation check.

.PARAMETER DefinitionPath
    Path to the same OKR definition JSON file passed to Export-OkrProgressTrend.ps1. Required only
    for the live-reconciliation check.

.PARAMETER ApiVersion
    Unified Catalog REST API version to pin. Defaults to '2026-03-20-preview'.

.EXAMPLE
    ./Test-OkrProgressTrend.ps1 -TrendLogPath '../deploy/out/okr-progress-trend.csv' -FailOnStale

    File-integrity and staleness-gate checks only (no tenant credentials supplied) - fails non-zero
    if the most recent run recorded any stale entity.

.EXAMPLE
    ./Test-OkrProgressTrend.ps1 -TrendLogPath '../deploy/out/okr-progress-trend.csv' -FailOnStale `
        -PurviewAccountEndpoint 'https://api.purview-service.microsoft.com' `
        -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
        -DefinitionPath '../deploy/config/customer-data-trust-okr.sample.json'

    Full check: file integrity, staleness gate, plus a live reconciliation confirming the most
    recent run's rows cover every entity the definition file currently declares.

.NOTES
    A live-reconciliation [WARN] is not, by itself, proof of a bug - it is the expected signal right
    after a key result is added to the definition file and deployed (via New-Okr.ps1) but
    Export-OkrProgressTrend.ps1 hasn't been re-run yet. Re-run the export and re-check; a [WARN]
    that persists deserves investigation. A [FAIL] from -FailOnStale is different: it means an
    already-tracked entity's progress/goal/max/status has not changed in
    -StalenessThresholdDays+ days - see README.md Section 8's operational guidance, since this is
    the specific detective control this companion exists to provide for the "no unattended
    staleness-detection workaround" gap README.md Section 11 discloses.

    Sources (Microsoft Learn, verify before production use):
    - Okr operation group (Get/Get Key Result):
      https://learn.microsoft.com/rest/api/purview/purview-unified-catalog/okr?view=rest-purview-purview-unified-catalog-2026-03-20-preview
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateScript({ Test-Path $_ -PathType Leaf })]
    [string]$TrendLogPath,

    [Parameter()]
    [switch]$FailOnStale,

    [Parameter()]
    [string]$PurviewAccountEndpoint,

    [Parameter()]
    [string]$TenantId,

    [Parameter()]
    [string]$AppId,

    [Parameter()]
    [SecureString]$ClientSecret,

    [Parameter()]
    [string]$DefinitionPath,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$ApiVersion = '2026-03-20-preview'
)

$ErrorActionPreference = 'Stop'
$script:failures = 0

function Test-Check {
    param([string]$Description, [bool]$Condition, [switch]$Warn)
    if ($Condition) {
        Write-Host "  [PASS] $Description" -ForegroundColor Green
    }
    elseif ($Warn) {
        Write-Host "  [WARN] $Description" -ForegroundColor Yellow
    }
    else {
        Write-Host "  [FAIL] $Description" -ForegroundColor Red
        $script:failures++
    }
}

Write-Host "Checking trend-log file integrity: $TrendLogPath" -ForegroundColor Cyan
$rows = @(Import-Csv -Path $TrendLogPath)

Test-Check -Description "Trend log has at least one row" -Condition ($rows.Count -gt 0)
if ($rows.Count -eq 0) {
    Write-Host "`nCannot continue - no rows to validate." -ForegroundColor Red
    exit 1
}

$requiredColumns = 'RunId', 'RunTimestampUtc', 'EntityType', 'EntityId', 'ObjectiveId', 'Label', `
    'ChangeState', 'LastChangedUtc', 'DaysSinceLastChange', 'Stale', 'Definition', 'Progress', `
    'Goal', 'Max', 'Status'
$actualColumns = $rows[0].PSObject.Properties.Name
foreach ($column in $requiredColumns) {
    Test-Check -Description "Column '$column' present" -Condition ($actualColumns -contains $column)
}

# --- No duplicate (RunId, EntityId) rows: proof Export-OkrProgressTrend.ps1's replace-by-RunId
#     idempotency design (design.md's "Progress-trend companion" section) is actually holding. ---
$duplicateKeys = $rows | Group-Object { "$($_.RunId)|$($_.EntityId)" } | Where-Object { $_.Count -gt 1 }
Test-Check -Description "No duplicate (RunId, EntityId) rows in the trend log" -Condition ($duplicateKeys.Count -eq 0)
if ($duplicateKeys.Count -gt 0) {
    Write-Host "         Duplicate keys: $($duplicateKeys.Name -join ', ')" -ForegroundColor Yellow
}

# --- A 'Baseline' row (this entity's first-ever appearance) can never simultaneously be Stale - a
#     stale flag requires an unchanged PRIOR run to compare against, which a baseline row has none
#     of by definition. Catches a corrupted or hand-edited trend log. ---
$inconsistentBaseline = $rows | Where-Object { $_.ChangeState -eq 'Baseline' -and $_.Stale -eq 'True' }
Test-Check -Description "No 'Baseline' row is also flagged Stale" -Condition ($inconsistentBaseline.Count -eq 0)
foreach ($row in $inconsistentBaseline) {
    Write-Host "         $($row.RunId)/$($row.EntityId) ($($row.EntityType) '$($row.Label)') - Baseline row incorrectly marked Stale" -ForegroundColor Yellow
}

# --- Staleness gate: fail (or warn) if the MOST RECENT RunId's rows contain any stale entity ---
$latestRunId = ($rows | Sort-Object RunId -Descending | Select-Object -First 1).RunId
$latestRows = @($rows | Where-Object { $_.RunId -eq $latestRunId })
Write-Host "`nChecking most recent run ('$latestRunId') for stale entities..." -ForegroundColor Cyan
$staleRows = @($latestRows | Where-Object { $_.Stale -eq 'True' })
Test-Check -Description "No stale entity in the most recent run" -Condition ($staleRows.Count -eq 0) -Warn:(-not $FailOnStale)
foreach ($row in $staleRows) {
    Write-Host "         $($row.EntityType) '$($row.Label)' (id: $($row.EntityId)): unchanged $($row.DaysSinceLastChange) day(s), status '$($row.Status)'" -ForegroundColor Yellow
}

# --- Optional live reconciliation against the definition file's current entity set ---
if ($PurviewAccountEndpoint -and $TenantId -and $AppId -and $ClientSecret -and $DefinitionPath) {
    Write-Host "`nReconciling the most recent run against the current definition file..." -ForegroundColor Cyan

    function ConvertTo-PlainText {
        param([Parameter(Mandatory)][SecureString]$Secure)
        $ptr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($Secure)
        try { return [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($ptr) }
        finally { [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr) }
    }

    function Get-PurviewAccessToken {
        param(
            [Parameter(Mandatory)][string]$TenantId,
            [Parameter(Mandatory)][string]$AppId,
            [Parameter(Mandatory)][string]$PlainSecret
        )
        $body = @{
            client_id     = $AppId
            client_secret = $PlainSecret
            grant_type    = 'client_credentials'
            resource      = 'https://purview.azure.net'
        }
        $response = Invoke-RestMethod -Method Post `
            -Uri "https://login.microsoftonline.com/$TenantId/oauth2/token" -Body $body
        return $response.access_token
    }

    $definition = Get-Content -Path $DefinitionPath -Raw | ConvertFrom-Json
    $expectedIds = @($definition.objective.id) + @($definition.keyResults | ForEach-Object { $_.id })

    $plainSecret = ConvertTo-PlainText -Secure $ClientSecret
    try {
        $token = Get-PurviewAccessToken -TenantId $TenantId -AppId $AppId -PlainSecret $plainSecret
    }
    finally {
        $plainSecret = $null
    }

    $endpoint = $PurviewAccountEndpoint.TrimEnd('/')
    $liveIds = @()
    $objUri = "$endpoint/datagovernance/catalog/objectives/$($definition.objective.id)?api-version=$ApiVersion"
    try {
        $obj = Invoke-RestMethod -Method Get -Uri $objUri -Headers @{ Authorization = "Bearer $token" }
        $liveIds += $obj.id
    }
    catch {
        if (-not ($_.Exception.Response -and $_.Exception.Response.StatusCode.value__ -eq 404)) { throw }
    }
    foreach ($kr in $definition.keyResults) {
        $krUri = "$endpoint/datagovernance/catalog/objectives/$($definition.objective.id)/keyResults/$($kr.id)?api-version=$ApiVersion"
        try {
            $deployedKr = Invoke-RestMethod -Method Get -Uri $krUri -Headers @{ Authorization = "Bearer $token" }
            $liveIds += $deployedKr.id
        }
        catch {
            if (-not ($_.Exception.Response -and $_.Exception.Response.StatusCode.value__ -eq 404)) { throw }
        }
    }

    $reportedIds = @($latestRows.EntityId)
    $missingFromReport = @($liveIds | Where-Object { $_ -notin $reportedIds })
    Test-Check -Description "[$latestRunId] Every live entity (objective + key results, $($liveIds.Count) found) is covered by the most recent run" `
        -Condition ($missingFromReport.Count -eq 0) -Warn
    foreach ($missingId in $missingFromReport) {
        Write-Host "         Entity id '$missingId' exists live but is not in the most recent trend-log run - re-run deploy/Export-OkrProgressTrend.ps1." -ForegroundColor Yellow
    }
    $expectedButNotLive = @($expectedIds | Where-Object { $_ -notin $liveIds })
    if ($expectedButNotLive.Count -gt 0) {
        Write-Host "         Definition file names $($expectedButNotLive.Count) entity id(s) not found live - run validate/Test-Okr.ps1 to diagnose (deployment gap, not a trend-log gap)." -ForegroundColor Yellow
    }
}
else {
    Write-Host "`nSkipping live reconciliation - PurviewAccountEndpoint/TenantId/AppId/ClientSecret/DefinitionPath not all supplied. File-integrity and staleness-gate checks only." -ForegroundColor Yellow
}

Write-Host "`n$(if ($script:failures -eq 0) { 'All hard checks passed.' } else { "$script:failures hard check(s) failed." })" `
    -ForegroundColor $(if ($script:failures -eq 0) { 'Green' } else { 'Red' })

if ($script:failures -gt 0) { exit 1 }
```