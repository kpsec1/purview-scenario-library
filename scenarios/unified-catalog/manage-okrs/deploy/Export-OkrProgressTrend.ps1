#Requires -Version 7.0
<#
.SYNOPSIS
    Re-fetches an objective (OKR) and its key results and appends a row per entity to a local,
    historical trend log - the scheduled companion `README.md` Section 8 and Section 11's "Progress
    tracking is manual" limitation both name as the only unattended staleness-detection workaround
    available today for a key result's `progress` value.

.DESCRIPTION
    Calls only the Microsoft Purview Unified Catalog REST API's read-only Okr - Get / Okr - Get Key
    Result operations (automation surface 4 per docs/automation-surface.md) - never Graph, never a
    mutating call. For the objective named in -DefinitionPath and each of its key results:
      1. GET the current definition/status (objective) or definition/progress/goal/max/status (key
         result) by the definition file's own caller-generated id - the same id-based lookup
         validate/Test-Okr.ps1 already uses (design.md Section 3).
      2. Compare the current values to this entity's own most recent PRIOR row in -TrendLogPath (not
         to a checked-in expected-state file - see design.md's new "Progress-trend companion" section
         for why this scenario's drift model differs from scan-credential-inventory-report's).
      3. If unchanged, carry the prior row's own LastChangedUtc forward and compute how many days it
         has been unchanged; a value at or beyond -StalenessThresholdDays is flagged [STALE] (a
         signal to review, never a hard failure from this script itself - see
         validate/Test-OkrProgressTrend.ps1's own -FailOnStale gate for that).
      4. If changed (or this is the entity's first-ever run), reset LastChangedUtc to now and record
         [CHANGED] or [BASELINE].
      5. Append/replace this run's rows (replace-by-RunId, matching
         scan-credential-inventory-report/deploy/Export-CredentialInventoryReport.ps1's own
         idempotency model - design.md Section 5 there) in the trend-log CSV.

    Idempotency model: re-running for the same -RunId (default: current UTC date, 'yyyy-MM-dd')
    REPLACES that RunId's rows rather than appending duplicates - identical to
    scan-credential-inventory-report's own pattern.

    Author-only reference code. Never connects to a live tenant unless you supply real credentials
    and omit -WhatIf. Read-only against Purview throughout - this script creates, modifies, and
    deletes nothing in the tenant; its only side effect is writing the local trend-log CSV.

    Deliberately does NOT invoke validate/Test-Okr.ps1 as a child process to "diff its console
    output" literally, and does NOT dot-source it either - design.md's new section explains both:
    an in-process `&` call to a script that itself calls `exit` on failure would terminate this
    script's own process before the staleness comparison below ever ran, and a child-process
    invocation would require passing the SecureString -ClientSecret across a process boundary as
    plaintext. This script re-derives the minimal structured data it needs (progress/goal/max/status,
    not the full existence/definition/domain/data-product-link checks Test-Okr.ps1 owns) and diffs
    that structured state run-over-run instead - a stronger, machine-comparable signal than
    text-diffing colorized console output would have been. Run both scripts back-to-back on your
    chosen cadence (README.md Section 8) for full coverage: Test-Okr.ps1 for existence/definition
    drift, this script for progress-staleness trending.

.PARAMETER PurviewAccountEndpoint
    Base URL of the Purview Unified Catalog data-plane API - must match the value used at deploy
    time (e.g. 'https://api.purview-service.microsoft.com').

.PARAMETER TenantId
    Microsoft Entra tenant ID.

.PARAMETER AppId
    Application (client) ID of a service principal holding at least Data Steward / Governance
    Domain Reader on the target domain - the same read-only bar validate/Test-Okr.ps1 requires. No
    Graph permission is needed (unlike deploy/New-Okr.ps1) - this script never resolves an owner
    identity.

.PARAMETER ClientSecret
    Client secret for -AppId, as a SecureString. Resolve from a vault at run time - never hard-code.

.PARAMETER DefinitionPath
    Path to the same OKR definition JSON file passed to New-Okr.ps1 / Test-Okr.ps1. Only
    `objective.id` and `keyResults[].id` are read - domain and relatedDataProducts are ignored (out
    of scope for a progress-trend report).

.PARAMETER TrendLogPath
    Path to the append/replace-by-RunId CSV trend log (one row per RunId x EntityId). Created with a
    header row if it doesn't already exist. Defaults to './out/okr-progress-trend.csv' (the
    'out/' directory is repo-gitignored - see rollback.md).

.PARAMETER RunId
    Identifier for this report run, used both as a trend-log column and to make re-runs replace
    rather than duplicate. Defaults to the current UTC date ('yyyy-MM-dd') - if you override it with
    a custom scheme, keep it sortable as a plain string (this script picks the "previous" row by
    string-descending RunId, not by RunTimestampUtc, matching
    scan-credential-inventory-report/deploy/Export-CredentialInventoryReport.ps1's own convention).

.PARAMETER StalenessThresholdDays
    Number of days a key result's progress/goal/max/status (or the objective's own status) must stay
    completely unchanged before this script flags it [STALE] in its console summary and trend-log
    row. Defaults to 30. This script itself never fails the run on a stale entity - see
    validate/Test-OkrProgressTrend.ps1's own -FailOnStale gate for that.

.PARAMETER ApiVersion
    Unified Catalog REST API version to pin. Defaults to '2026-03-20-preview', matching every other
    script in this scenario.

.PARAMETER WhatIf
    Standard PowerShell ShouldProcess dry-run. The read-only Okr - Get / Get Key Result calls still
    execute (needed to report accurate would-be staleness numbers), but the trend-log CSV is not
    written - the script prints a summary instead.

.EXAMPLE
    ./Export-OkrProgressTrend.ps1 -PurviewAccountEndpoint 'https://api.purview-service.microsoft.com' `
        -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
        -DefinitionPath './config/customer-data-trust-okr.sample.json' -WhatIf

    Dry run: fetches current objective/key-result state, computes what this run's rows and
    staleness flags would be, writes nothing to disk.

.EXAMPLE
    ./Export-OkrProgressTrend.ps1 -PurviewAccountEndpoint 'https://api.purview-service.microsoft.com' `
        -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
        -DefinitionPath './config/customer-data-trust-okr.sample.json' `
        -TrendLogPath './out/okr-progress-trend.csv' -StalenessThresholdDays 21

    Full run on a recurring schedule (Windows Task Scheduler, cron, Azure Automation runbook -
    README.md Section 8): appends/replaces today's row(s) and flags any entity unchanged for 21+
    days.

.NOTES
    VERIFY before production use (see README.md Section 11 and design.md for full detail):
    - No Microsoft-documented REST/Graph event, webhook, or subscription notifies on an Okr/Key
      Result change - confirmed unchanged from the original scenario build's own grounding pass
      (reviews.md Round 1, Blue Team finding 2). This build additionally checked the "Audit log
      activities" reference's own "Microsoft Purview governance activities" category
      (EntityCreated/EntityUpdated/EntityDeleted, Classification*, GlossaryTerm*,
      SensitivityLabelChanged - the classic Atlas-model entity-audit event set) and found no
      Objective/KeyResult/OKR-specific friendly name in it - corroborating, but not conclusively
      proving, the "no audit trail for this object type" finding, since the Unified Catalog OKR
      REST surface is a distinct, newer data-plane API from the classic Atlas-based entity model
      those operations describe; whether an OKR change is silently logged there under a generic
      operation name this build didn't recognize is not ruled out.
    - This script's own local trend-log CSV is therefore the only historical record of an OKR's
      progress over time this repo can produce - it is a client-side compensating control, not a
      read of any Microsoft-side change history.

    Sources (Microsoft Learn, verify before production use):
    - Okr operation group (Get/Get Key Result - the only two operations this script calls):
      https://learn.microsoft.com/rest/api/purview/purview-unified-catalog/okr?view=rest-purview-purview-unified-catalog-2026-03-20-preview
    - Audit log activities - "Microsoft Purview governance activities" category (checked for an
      Objective/KeyResult/OKR-specific operation; none found):
      https://learn.microsoft.com/purview/audit-log-activities#microsoft-purview-governance-activities
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Low')]
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
    [string]$TrendLogPath = (Join-Path $PSScriptRoot 'out/okr-progress-trend.csv'),

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$RunId = ([datetime]::UtcNow.ToString('yyyy-MM-dd')),

    [Parameter()]
    [ValidateRange(1, 3650)]
    [int]$StalenessThresholdDays = 30,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$ApiVersion = '2026-03-20-preview'
)

$ErrorActionPreference = 'Stop'
$endpoint = $PurviewAccountEndpoint.TrimEnd('/')
$nowUtc = [datetime]::UtcNow

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

function Invoke-UcmGet {
    param(
        [Parameter(Mandatory)][string]$Uri,
        [Parameter(Mandatory)][string]$Token,
        [switch]$TreatNotFoundAsNull
    )
    try { return Invoke-RestMethod -Method Get -Uri $Uri -Headers @{ Authorization = "Bearer $Token" } }
    catch {
        if ($TreatNotFoundAsNull -and $_.Exception.Response -and $_.Exception.Response.StatusCode.value__ -eq 404) {
            return $null
        }
        throw
    }
}

function Get-PriorRow {
    # Picks this entity's most recent row from a PRIOR (string-descending, excluding this RunId)
    # run - never the row this run is about to replace. Returns $null if this is the entity's first
    # appearance in the trend log (a "baseline" run).
    param(
        [Parameter(Mandatory)][array]$ExistingRows,
        [Parameter(Mandatory)][string]$EntityId,
        [Parameter(Mandatory)][string]$CurrentRunId
    )
    return $ExistingRows |
        Where-Object { $_.EntityId -eq $EntityId -and $_.RunId -ne $CurrentRunId } |
        Sort-Object RunId -Descending |
        Select-Object -First 1
}

function New-TrendRow {
    # Builds one entity's trend-log row: compares $CurrentFields (an ordered hashtable of the
    # fields that define "changed" for this entity type) against $PriorRow's own same-named
    # columns, then classifies Baseline / Changed / Unchanged and computes staleness.
    param(
        [Parameter(Mandatory)][string]$EntityType,
        [Parameter(Mandatory)][string]$EntityId,
        [Parameter(Mandatory)][string]$ObjectiveId,
        [Parameter(Mandatory)][string]$Label,
        [Parameter(Mandatory)][System.Collections.Specialized.OrderedDictionary]$CurrentFields,
        [Parameter()]$PriorRow,
        [Parameter(Mandatory)][int]$StalenessThresholdDays,
        [Parameter(Mandatory)][datetime]$NowUtc
    )
    $changeState = 'Baseline'
    $lastChangedUtc = $NowUtc
    if ($PriorRow) {
        $unchanged = $true
        foreach ($key in $CurrentFields.Keys) {
            $priorValue = if ($PriorRow.PSObject.Properties.Name -contains $key) { [string]$PriorRow.$key } else { $null }
            if ([string]$CurrentFields[$key] -ne $priorValue) { $unchanged = $false; break }
        }
        if ($unchanged) {
            $changeState = 'Unchanged'
            $lastChangedUtc = if ($PriorRow.PSObject.Properties.Name -contains 'LastChangedUtc' -and $PriorRow.LastChangedUtc) {
                [datetime]::Parse($PriorRow.LastChangedUtc, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::RoundtripKind)
            }
            else {
                # Defensive fallback - a hand-edited or older-format trend log missing this column.
                $NowUtc
            }
        }
        else {
            $changeState = 'Changed'
        }
    }
    $daysSinceLastChange = [Math]::Round(($NowUtc - $lastChangedUtc).TotalDays, 1)
    $stale = ($changeState -ne 'Baseline') -and ($daysSinceLastChange -ge $StalenessThresholdDays)

    $row = [ordered]@{
        RunId                = $RunId
        RunTimestampUtc      = $NowUtc.ToString('o')
        EntityType           = $EntityType
        EntityId             = $EntityId
        ObjectiveId          = $ObjectiveId
        Label                = $Label
        ChangeState          = $changeState
        LastChangedUtc       = $lastChangedUtc.ToString('o')
        DaysSinceLastChange  = $daysSinceLastChange
        Stale                = $stale
    }
    foreach ($key in $CurrentFields.Keys) { $row[$key] = $CurrentFields[$key] }
    return [pscustomobject]$row
}

# --- Load the definition file (id-only - domain/relatedDataProducts are out of scope here) ---
$definition = Get-Content -Path $DefinitionPath -Raw | ConvertFrom-Json
if (-not $definition.objective -or -not $definition.keyResults) {
    throw "Definition file '$DefinitionPath' must contain 'objective' and 'keyResults' properties."
}

# --- Authenticate (Purview only - no Graph token needed, unlike New-Okr.ps1) ---
$plainSecret = ConvertTo-PlainText -Secure $ClientSecret
try {
    $token = Get-PurviewAccessToken -TenantId $TenantId -AppId $AppId -PlainSecret $plainSecret
}
finally {
    $plainSecret = $null
}

# --- Load existing trend log (if any) - used both to find each entity's prior row and to carry
#     forward every OTHER RunId's rows unchanged (replace-by-RunId, not append, matching
#     scan-credential-inventory-report's own model) ---
$existingRows = @()
if (Test-Path -Path $TrendLogPath -PathType Leaf) {
    $existingRows = @(Import-Csv -Path $TrendLogPath)
}

# --- Fetch the objective ---
$objectiveUri = "$endpoint/datagovernance/catalog/objectives/$($definition.objective.id)?api-version=$ApiVersion"
$objective = Invoke-UcmGet -Uri $objectiveUri -Token $token -TreatNotFoundAsNull
if (-not $objective) {
    throw "Objective (id: $($definition.objective.id)) was not found. Run validate/Test-Okr.ps1 first to diagnose - this script only trends an already-deployed objective, it does not deploy or validate one."
}

$rows = @()
# Every row (Objective or KeyResult) uses the SAME field set (Definition/Progress/Goal/Max/Status) -
# Progress/Goal/Max are blank for an Objective row. This is deliberate, not an oversight: Export-Csv
# derives its column headers from the FIRST object in the pipeline only, so mixing a narrower
# Objective shape with a wider KeyResult shape would silently truncate Progress/Goal/Max from every
# row in the file - the exact data this script exists to trend. A uniform schema avoids that.
$objectiveFields = [ordered]@{ Definition = $objective.definition; Progress = ''; Goal = ''; Max = ''; Status = $objective.status }
$objectivePrior = Get-PriorRow -ExistingRows $existingRows -EntityId $objective.id -CurrentRunId $RunId
$rows += New-TrendRow -EntityType 'Objective' -EntityId $objective.id -ObjectiveId $objective.id `
    -Label $objective.definition -CurrentFields $objectiveFields -PriorRow $objectivePrior `
    -StalenessThresholdDays $StalenessThresholdDays -NowUtc $nowUtc

# --- Fetch each key result ---
foreach ($kr in $definition.keyResults) {
    $krUri = "$endpoint/datagovernance/catalog/objectives/$($definition.objective.id)/keyResults/$($kr.id)?api-version=$ApiVersion"
    $deployed = Invoke-UcmGet -Uri $krUri -Token $token -TreatNotFoundAsNull
    if (-not $deployed) {
        Write-Warning "Key result '$($kr.definition)' (id: $($kr.id)) was not found - skipped. Run validate/Test-Okr.ps1 first to diagnose."
        continue
    }
    $krFields = [ordered]@{
        Definition = $deployed.definition
        Progress   = $deployed.progress
        Goal       = $deployed.goal
        Max        = $deployed.max
        Status     = $deployed.status
    }
    $krPrior = Get-PriorRow -ExistingRows $existingRows -EntityId $deployed.id -CurrentRunId $RunId
    $rows += New-TrendRow -EntityType 'KeyResult' -EntityId $deployed.id -ObjectiveId $objective.id `
        -Label $deployed.definition -CurrentFields $krFields -PriorRow $krPrior `
        -StalenessThresholdDays $StalenessThresholdDays -NowUtc $nowUtc
}

# --- Console summary (printed regardless of -WhatIf) ---
Write-Host "OKR progress trend for objective '$($objective.definition)' (RunId '$RunId'):" -ForegroundColor Cyan
foreach ($row in $rows) {
    $color = if ($row.Stale) { 'Yellow' } elseif ($row.ChangeState -eq 'Changed') { 'Green' } else { 'Cyan' }
    $tag = if ($row.Stale) { 'STALE' } else { $row.ChangeState.ToUpperInvariant() }
    $detail = if ($row.EntityType -eq 'KeyResult') { " progress=$($row.Progress)/$($row.Goal) (max $($row.Max)), status=$($row.Status)" } else { " status=$($row.Status)" }
    Write-Host ("  [{0}] {1} '{2}'{3} - unchanged {4} day(s)" -f $tag, $row.EntityType, $row.Label, $detail, $row.DaysSinceLastChange) -ForegroundColor $color
}
$staleCount = @($rows | Where-Object { $_.Stale }).Count
if ($staleCount -gt 0) {
    Write-Warning "$staleCount entit(y/ies) unchanged for $StalenessThresholdDays+ day(s). A frozen 'on track' key result is worse than no OKR at all for the board-legible-narrative goal in README.md Section 2 - verify the underlying metric with the objective's own owner before the next business review."
}

# --- Write the trend-log CSV (replace-by-RunId) ---
$writeDescription = "Write/replace RunId '$RunId' row(s) in trend log '$TrendLogPath'"
if ($PSCmdlet.ShouldProcess($writeDescription, 'Write trend-log file')) {
    $carriedForwardRows = @($existingRows | Where-Object { $_.RunId -ne $RunId })
    $allRows = $carriedForwardRows + $rows
    $trendDir = Split-Path -Path $TrendLogPath -Parent
    if ($trendDir -and -not (Test-Path -Path $trendDir -PathType Container)) {
        New-Item -Path $trendDir -ItemType Directory -Force | Out-Null
    }
    $allRows | Sort-Object RunId, EntityType, EntityId | Export-Csv -Path $TrendLogPath -NoTypeInformation
    Write-Host "`nTrend log updated: $TrendLogPath" -ForegroundColor Cyan
}
else {
    Write-Verbose "WhatIf: would $writeDescription"
}
