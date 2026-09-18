---
part: "deploy"
parent: "unified-catalog/manage-okrs"
---
The scripts and configuration below deploy this scenario. Review them, then run in order — each is designed to be idempotent and has a matching rollback.


#### `config/customer-data-trust-okr.sample.json`

```json
{
  "domain": {
    "name": "Customer Experience"
  },
  "objective": {
    "id": "00000000-0000-0000-0000-000000000000",
    "definition": "Increase trust in customer master data by reducing duplicate and inconsistent customer records across source systems",
    "owners": ["alice@contoso.com"],
    "targetDate": "2026-12-31T00:00:00Z"
  },
  "keyResults": [
    {
      "id": "00000000-0000-0000-0000-000000000000",
      "definition": "Reduce the duplicate customer-ID rate across source systems from 8% to under 2%",
      "progress": 8,
      "goal": 2,
      "max": 8,
      "status": "NotTracked"
    },
    {
      "id": "00000000-0000-0000-0000-000000000000",
      "definition": "Bring 100% of Customer Master Data's linked source tables under an active data quality score",
      "progress": 0,
      "goal": 100,
      "max": 100,
      "status": "NotTracked"
    }
  ],
  "relatedDataProducts": ["Customer Master Data"]
}
```

#### `Export-OkrProgressTrend.ps1`

```powershell
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
```

#### `New-Okr.ps1`

```powershell
#Requires -Version 7.0
<#
.SYNOPSIS
    Idempotently creates or updates a Microsoft Purview Unified Catalog objective (OKR) and its key
    results, and links the objective to one or more already-existing data products, from a
    declarative JSON definition file.

.DESCRIPTION
    Calls the Microsoft Purview Unified Catalog REST API (automation surface 4 per
    docs/automation-surface.md) to:
      1. Resolve the governance domain named in the definition file (must already exist - this
         scenario reuses the domain scenarios/unified-catalog/curate-business-glossary/ creates,
         it does not create one).
      2. Resolve any owner identity that isn't already an Entra object ID, via Microsoft Graph -
         the same owner-resolution pattern scenarios/unified-catalog/manage-data-products/ and
         .../manage-critical-data-elements/ use.
      3. Create or update (upsert) the objective itself, via the Okr operation group.
      4. Create or update (upsert) each key result under that objective, via the same operation
         group's key-result sub-resource.
      5. Link the objective to each named data product - NOT via the Okr operation group (it has
         no relationship operation at all, unlike Data Products/Critical Data Elements/Terms - see
         design.md Section 4), but via the Data Products - Create Relationship operation with
         entityType=OBJECTIVE, called against the already-existing data product
         (scenarios/unified-catalog/manage-data-products/ owns that product's own lifecycle).
      6. Optionally (-Publish) transition the objective from Draft to Published.

    Idempotency is deliberately NOT name-based, unlike every other Unified Catalog scenario in this
    repo. Microsoft's own docs state that OKR names are not required to be unique ("If you use a
    name that already exists, you'll see a warning during the creation process... you won't be
    blocked from using a duplicate name") - a name-based existence check would be ambiguous by
    design for this object type. Instead, the definition file carries a caller-generated 'id' for
    the objective and for each key result (the same caller-generated-id pattern this repo's other
    Unified Catalog Create operations already use, just promoted here to be the sole identity
    check instead of a name-lookup fallback): this script GETs by that id first, creates on a 404,
    and updates (full-body PUT) on a 200 (design.md Section 3).

    This scenario does NOT create the objective-to-data-product link from the objective's own
    side - there is no such operation to call (design.md Section 4). It calls the Data Products
    operation group's Create Relationship operation instead, exactly as
    scenarios/unified-catalog/manage-data-products/'s own New-DataProduct.ps1 already does for
    DATAASSET/TERM, extended here with entityType=OBJECTIVE.

    Author-only reference code. Never connects to a live tenant unless you supply real credentials
    and omit -WhatIf. The objective is created in Draft status unless -Publish is passed.

.PARAMETER PurviewAccountEndpoint
    Base URL of the Purview Unified Catalog data-plane API, e.g.
    'https://api.purview-service.microsoft.com'.

.PARAMETER TenantId
    Microsoft Entra tenant ID.

.PARAMETER AppId
    Application (client) ID of the service principal used to call both the Unified Catalog REST
    API and Microsoft Graph. Must hold the Data Steward role on the target governance domain
    (docs/rbac-model.md Section 5 - README.md Section 3) plus the Graph application permission
    User.Read.All (README.md Section 3).

.PARAMETER ClientSecret
    Client secret for -AppId, as a SecureString. Resolve from a vault at run time - never hard-code.

.PARAMETER DefinitionPath
    Path to the OKR definition JSON file. See
    deploy/config/customer-data-trust-okr.sample.json for the expected shape (domain block,
    objective block with a caller-generated 'id', keyResults array each with its own
    caller-generated 'id', relatedDataProducts array of existing data product names).

.PARAMETER Publish
    If supplied, transitions the objective from Draft to Published after it and its key results
    are created/updated and linked. Microsoft's docs state the governance domain itself must
    already be published first (README.md Section 3) - this script does not publish the domain.
    Omit to leave the objective in Draft for review.

.PARAMETER ApiVersion
    Unified Catalog REST API version to pin. Defaults to '2026-03-20-preview', the version whose
    Okr and Data Products operation groups this script was grounded against.

.PARAMETER WhatIf
    Standard PowerShell ShouldProcess dry-run. Reports every REST call that would be made without
    sending any mutating (POST/PUT/DELETE) request. Invoke-RestMethod has no native ShouldProcess
    integration, so this script wraps each mutating call in its own $PSCmdlet.ShouldProcess() check.

.EXAMPLE
    ./New-Okr.ps1 -PurviewAccountEndpoint 'https://api.purview-service.microsoft.com' `
        -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
        -DefinitionPath './config/customer-data-trust-okr.sample.json' -WhatIf

    Dry-run: shows exactly which REST calls would be made, changes nothing.

.EXAMPLE
    ./New-Okr.ps1 -PurviewAccountEndpoint 'https://api.purview-service.microsoft.com' `
        -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
        -DefinitionPath './config/customer-data-trust-okr.sample.json' -Publish

    Creates/updates the objective and its key results, links to each named data product, publishes.

.NOTES
    VERIFY before production use (see README.md Section 11 and design.md for full detail):
    - The Data Products - Create Relationship operation's REST reference documents only one worked
      request-body example, for entityType=CRITICALDATACOLUMN, whose body includes an `assetId`
      field alongside `entityId`. This script omits `assetId` for the OBJECTIVE relationship it
      creates (sending only entityId/relationshipType/description) - the same reasoning and the
      same open question scenarios/unified-catalog/manage-data-products/'s own
      Add-DataProductRelationship carries for its DATAASSET/TERM relationships. Confirm against a
      pilot tenant if this call is rejected or silently no-ops.
    - Whether a key result's own `domainId` (required on Create/Update Key Result, separate from
      the parent objective's own `domain` field) must exactly match the parent objective's domain,
      or is independently enforced/ignored - not documented either way. This script always sends
      the same domain id for both, which is the only configuration Microsoft's own portal flow
      permits (a key result has no separate domain picker in the UI).
    - The Okr - Update operation's REST reference documents its `additionalProperties` request
      field as type OkrSharedEntityStatus (an enum), inconsistent with Create/Get's own
      ObjectiveAdditionalProperties (an object of computed rollup fields - keyResultsCount,
      overallProgress, etc.) for the same field name on the same resource. This script never sends
      `additionalProperties` on Create or Update, reasoning that a field which is entirely
      platform-computed from the objective's own key results should not be client-supplied -
      flagged as a genuine Microsoft Learn reference inconsistency, not resolved by guessing which
      shape is correct.

    Sources (Microsoft Learn, verify before production use):
    - Okr operation group (Count/Create/Create Key Result/Delete/Delete Key Result/Get/Get Facets/
      Get Key Result/List/List Key Results/Query/Update/Update Key Result):
      https://learn.microsoft.com/rest/api/purview/purview-unified-catalog/okr?view=rest-purview-purview-unified-catalog-2026-03-20-preview
    - Data Products - Create Relationship / Delete Relationship / List Relationships (entityType
      OBJECTIVE and KEYRESULT are documented EntityCategory enum values on all three operations):
      https://learn.microsoft.com/rest/api/purview/purview-unified-catalog/data-products/create-relationship?view=rest-purview-purview-unified-catalog-2026-03-20-preview
    - Objectives and key results (OKRs) in Unified Catalog (concept, duplicate-name behavior):
      https://learn.microsoft.com/purview/unified-catalog-okrs
    - Create and manage OKRs in Unified Catalog (portal flow, steward-role prerequisite, publish
      gating on the governance domain):
      https://learn.microsoft.com/purview/unified-catalog-okrs-create-manage
    - Get a user (Graph, User.Read.All application permission):
      https://learn.microsoft.com/graph/api/user-get
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
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
    [switch]$Publish,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$ApiVersion = '2026-03-20-preview'
)

$ErrorActionPreference = 'Stop'

$endpoint = $PurviewAccountEndpoint.TrimEnd('/')
$guidPattern = '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
$nilGuid = '00000000-0000-0000-0000-000000000000'

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

function Get-GraphAccessToken {
    param(
        [Parameter(Mandatory)][string]$TenantId,
        [Parameter(Mandatory)][string]$AppId,
        [Parameter(Mandatory)][string]$PlainSecret
    )
    $body = @{
        client_id     = $AppId
        client_secret = $PlainSecret
        grant_type    = 'client_credentials'
        scope         = 'https://graph.microsoft.com/.default'
    }
    $response = Invoke-RestMethod -Method Post `
        -Uri "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token" -Body $body
    return $response.access_token
}

function Invoke-Ucm {
    # Invoke-RestMethod has no native ShouldProcess integration, so every mutating call is
    # wrapped in its own $PSCmdlet.ShouldProcess() check. -ReadOnly bypasses that gate for calls
    # that are read-only despite using POST/GET-that-can-404 - those must still execute under
    # -WhatIf so the script can accurately report create vs. update vs. already-linked.
    # -TreatNotFoundAsNull turns a 404 GET into a $null return instead of a thrown exception, so
    # the id-based existence check (design.md Section 3) reads as ordinary control flow.
    param(
        [Parameter(Mandatory)][ValidateSet('Get', 'Post', 'Put', 'Delete')][string]$Method,
        [Parameter(Mandatory)][string]$Uri,
        [Parameter()][hashtable]$Body,
        [Parameter(Mandatory)][string]$Token,
        [Parameter()][string]$Description = $Uri,
        [Parameter()][switch]$ReadOnly,
        [Parameter()][switch]$TreatNotFoundAsNull
    )
    if ($Method -eq 'Get' -or $ReadOnly) {
        $params = @{ Method = $Method; Uri = $Uri; Headers = @{ Authorization = "Bearer $Token" } }
        if ($Body) {
            $params.Body = ($Body | ConvertTo-Json -Depth 10)
            $params.ContentType = 'application/json'
        }
        try { return Invoke-RestMethod @params }
        catch {
            if ($TreatNotFoundAsNull -and $_.Exception.Response -and $_.Exception.Response.StatusCode.value__ -eq 404) {
                return $null
            }
            throw
        }
    }
    if ($PSCmdlet.ShouldProcess($Description, "$Method $Uri")) {
        $params = @{
            Method      = $Method
            Uri         = $Uri
            ContentType = 'application/json'
            Headers     = @{ Authorization = "Bearer $Token" }
        }
        if ($Body) { $params.Body = ($Body | ConvertTo-Json -Depth 10) }
        return Invoke-RestMethod @params
    }
    Write-Verbose "WhatIf: would $Method $Uri$(if ($Body) { " with body:`n$($Body | ConvertTo-Json -Depth 10)" })"
    return $null
}

function Find-BusinessDomainByName {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Token
    )
    $uri = "$endpoint/datagovernance/catalog/businessdomains?api-version=$ApiVersion"
    while ($uri) {
        $page = Invoke-Ucm -Method Get -Uri $uri -Token $Token
        $match = $page.value | Where-Object { $_.name -eq $Name } | Select-Object -First 1
        if ($match) { return $match }
        $uri = $page.nextLink
    }
    return $null
}

function Resolve-ContactId {
    param(
        [Parameter(Mandatory)][string]$Identifier,
        [Parameter(Mandatory)][string]$GraphToken,
        [Parameter(Mandatory)][hashtable]$Cache
    )
    if ($Identifier -match $guidPattern) { return $Identifier }
    if ($Cache.ContainsKey($Identifier)) { return $Cache[$Identifier] }
    $uri = "https://graph.microsoft.com/v1.0/users/${Identifier}?`$select=id"
    $user = Invoke-RestMethod -Method Get -Uri $uri -Headers @{ Authorization = "Bearer $GraphToken" }
    $Cache[$Identifier] = $user.id
    Write-Host "Resolved '$Identifier' to Entra object ID $($user.id)." -ForegroundColor Cyan
    return $user.id
}

function Get-OrNewObjective {
    # design.md Section 3: identity is the caller-generated 'id' in the definition file, never a
    # name lookup - Microsoft's own docs state OKR names are explicitly allowed to duplicate.
    param(
        [Parameter(Mandatory)][pscustomobject]$ObjectiveDef,
        [Parameter(Mandatory)][string]$DomainId,
        [Parameter(Mandatory)][string]$Token,
        [Parameter(Mandatory)][string]$GraphToken,
        [Parameter(Mandatory)][hashtable]$ContactCache
    )
    $objectiveId = $ObjectiveDef.id
    $getUri = "$endpoint/datagovernance/catalog/objectives/$objectiveId`?api-version=$ApiVersion"
    $existing = Invoke-Ucm -Method Get -Uri $getUri -Token $Token -TreatNotFoundAsNull
    $status = if ($existing) { $existing.status } else { 'Draft' }

    $ownerIds = @($ObjectiveDef.owners | ForEach-Object {
            Resolve-ContactId -Identifier $_ -GraphToken $GraphToken -Cache $ContactCache
        })

    $body = @{
        id          = $objectiveId
        domain      = $DomainId
        definition  = $ObjectiveDef.definition
        status      = $status
        targetDate  = $ObjectiveDef.targetDate
        contacts    = @{ owner = @($ownerIds | ForEach-Object { @{ id = $_ } }) }
    }

    if ($existing) {
        Invoke-Ucm -Method Put -Uri $getUri -Body $body -Token $Token `
            -Description "Update objective '$($ObjectiveDef.definition)'" | Out-Null
        Write-Host "Updated objective '$($ObjectiveDef.definition)' (id: $objectiveId, status: $status)." -ForegroundColor Green
    }
    else {
        $uri = "$endpoint/datagovernance/catalog/objectives?api-version=$ApiVersion"
        Invoke-Ucm -Method Post -Uri $uri -Body $body -Token $Token `
            -Description "Create objective '$($ObjectiveDef.definition)'" | Out-Null
        Write-Host "Created objective '$($ObjectiveDef.definition)' (id: $objectiveId, status: Draft)." -ForegroundColor Green
    }
    return $objectiveId
}

function Get-OrNewKeyResult {
    param(
        [Parameter(Mandatory)][string]$ObjectiveId,
        [Parameter(Mandatory)][string]$DomainId,
        [Parameter(Mandatory)][pscustomobject]$KeyResultDef,
        [Parameter(Mandatory)][string]$Token
    )
    $keyResultId = $KeyResultDef.id
    $getUri = "$endpoint/datagovernance/catalog/objectives/$ObjectiveId/keyResults/$keyResultId`?api-version=$ApiVersion"
    $existing = Invoke-Ucm -Method Get -Uri $getUri -Token $Token -TreatNotFoundAsNull

    $body = @{
        id         = $keyResultId
        domainId   = $DomainId
        definition = $KeyResultDef.definition
        progress   = $KeyResultDef.progress
        goal       = $KeyResultDef.goal
        max        = $KeyResultDef.max
        status     = $KeyResultDef.status
    }

    if ($existing) {
        Invoke-Ucm -Method Put -Uri $getUri -Body $body -Token $Token `
            -Description "Update key result '$($KeyResultDef.definition)'" | Out-Null
        Write-Host "  Updated key result '$($KeyResultDef.definition)' (id: $keyResultId)." -ForegroundColor Green
    }
    else {
        $uri = "$endpoint/datagovernance/catalog/objectives/$ObjectiveId/keyResults?api-version=$ApiVersion"
        Invoke-Ucm -Method Post -Uri $uri -Body $body -Token $Token `
            -Description "Create key result '$($KeyResultDef.definition)'" | Out-Null
        Write-Host "  Created key result '$($KeyResultDef.definition)' (id: $keyResultId)." -ForegroundColor Green
    }
}

function Find-DataProductByName {
    # Duplicated from manage-data-products/deploy/New-DataProduct.ps1 by design - each deploy
    # script in this repo is self-contained (AGENTS.md's per-scenario deliverable model), not a
    # shared module.
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$DomainId,
        [Parameter(Mandatory)][string]$Token
    )
    $uri = "$endpoint/datagovernance/catalog/dataProducts/query?api-version=$ApiVersion"
    $body = @{ domainIds = @($DomainId); nameKeyword = $Name; top = 50 }
    $response = Invoke-Ucm -Method Post -Uri $uri -Body $body -Token $Token -ReadOnly `
        -Description "Query data products named like '$Name'"
    return ($response.value | Where-Object { $_.name -eq $Name } | Select-Object -First 1)
}

function Test-DataProductRelationshipExists {
    param(
        [Parameter(Mandatory)][string]$DataProductId,
        [Parameter(Mandatory)][string]$EntityId,
        [Parameter(Mandatory)][string]$Token
    )
    $uri = "$endpoint/datagovernance/catalog/dataProducts/$DataProductId/relationships?api-version=$ApiVersion&entityType=OBJECTIVE"
    $response = Invoke-Ucm -Method Get -Uri $uri -Token $Token
    return [bool]($response.value | Where-Object { $_.entityId -eq $EntityId })
}

function Add-ObjectiveToDataProduct {
    # design.md Section 4: the link is created from the DATA PRODUCT side (Data Products - Create
    # Relationship, entityType=OBJECTIVE) - the Okr operation group itself has no relationship
    # operation at all. VERIFY (README.md Section 11 / this script's .NOTES): the only documented
    # worked request body for this operation is for entityType=CRITICALDATACOLUMN and includes an
    # `assetId` field; this function omits it, matching manage-data-products/New-DataProduct.ps1's
    # own DATAASSET/TERM reasoning.
    param(
        [Parameter(Mandatory)][string]$DataProductName,
        [Parameter(Mandatory)][string]$DomainId,
        [Parameter(Mandatory)][string]$ObjectiveId,
        [Parameter(Mandatory)][string]$ObjectiveLabel,
        [Parameter(Mandatory)][string]$Token
    )
    $product = Find-DataProductByName -Name $DataProductName -DomainId $DomainId -Token $Token
    if (-not $product) {
        Write-Warning "Data product '$DataProductName' was not found in this domain. Skipped - create it first (e.g. via scenarios/unified-catalog/manage-data-products/)."
        return
    }
    if (Test-DataProductRelationshipExists -DataProductId $product.id -EntityId $ObjectiveId -Token $Token) {
        Write-Host "Data product '$DataProductName' is already linked to objective '$ObjectiveLabel'." -ForegroundColor Yellow
        return
    }
    $uri = "$endpoint/datagovernance/catalog/dataProducts/$($product.id)/relationships?api-version=$ApiVersion&entityType=OBJECTIVE"
    $body = @{ entityId = $ObjectiveId; relationshipType = 'Related' }
    Invoke-Ucm -Method Post -Uri $uri -Body $body -Token $Token `
        -Description "Link data product '$DataProductName' -> objective '$ObjectiveLabel'" | Out-Null
    Write-Host "Linked data product '$DataProductName' -> objective '$ObjectiveLabel'." -ForegroundColor Green
}

function Publish-Objective {
    param(
        [Parameter(Mandatory)][string]$ObjectiveLabel,
        [Parameter(Mandatory)][string]$ObjectiveId,
        [Parameter(Mandatory)][string]$Token
    )
    $current = Invoke-Ucm -Method Get -Uri "$endpoint/datagovernance/catalog/objectives/$($ObjectiveId)?api-version=$ApiVersion" -Token $Token
    if ($current -and $current.status -eq 'Published') {
        Write-Host "Objective '$ObjectiveLabel' is already published." -ForegroundColor Yellow
        return
    }
    Write-Warning "Publishing '$ObjectiveLabel'. Microsoft's docs require the governance domain itself to already be published before an OKR within it can be published - this script does not publish the domain (README.md Section 3)."
    if (-not $current) {
        Write-Verbose 'WhatIf: publish would run a GET-then-PUT sequence; skipping the PUT body build against a null GET result.'
        return
    }
    $body = @{
        id         = $current.id
        domain     = $current.domain
        definition = $current.definition
        status     = 'Published'
        targetDate = $current.targetDate
        contacts   = $current.contacts
    }
    $uri = "$endpoint/datagovernance/catalog/objectives/$ObjectiveId`?api-version=$ApiVersion"
    Invoke-Ucm -Method Put -Uri $uri -Body $body -Token $Token `
        -Description "Publish objective '$ObjectiveLabel'" | Out-Null
    Write-Host "Published objective '$ObjectiveLabel'." -ForegroundColor Green
}

# --- Load and validate the definition file ---
$definition = Get-Content -Path $DefinitionPath -Raw | ConvertFrom-Json
if (-not $definition.domain -or -not $definition.objective -or -not $definition.keyResults) {
    throw "Definition file '$DefinitionPath' must contain 'domain', 'objective', and 'keyResults' properties."
}
if ($definition.objective.id -eq $nilGuid) {
    throw "Definition file '$DefinitionPath' still has the placeholder objective id ($nilGuid). Generate a real GUID (e.g. PowerShell's [guid]::NewGuid()) and set 'objective.id' before running (README.md Section 11) - unlike this repo's other Unified Catalog scenarios, OKR identity is NOT derived from a name lookup (design.md Section 3)."
}
foreach ($kr in $definition.keyResults) {
    if ($kr.id -eq $nilGuid) {
        throw "Definition file '$DefinitionPath' has a 'keyResults' entry still carrying the placeholder id ($nilGuid). Generate a real GUID for every key result before running."
    }
}

$plainSecret = ConvertTo-PlainText -Secure $ClientSecret
try {
    $ucToken = Get-PurviewAccessToken -TenantId $TenantId -AppId $AppId -PlainSecret $plainSecret
    $graphToken = Get-GraphAccessToken -TenantId $TenantId -AppId $AppId -PlainSecret $plainSecret
}
finally {
    $plainSecret = $null
}

# --- Step 1: resolve the (already-existing) governance domain ---
$domain = Find-BusinessDomainByName -Name $definition.domain.name -Token $ucToken
if (-not $domain) {
    throw "Governance domain '$($definition.domain.name)' was not found. This scenario reuses an existing domain (e.g. from scenarios/unified-catalog/curate-business-glossary/) rather than creating one - run that scenario, or create the domain manually, first."
}

# --- Step 2: create or update the objective ---
$contactCache = @{}
$objectiveId = Get-OrNewObjective -ObjectiveDef $definition.objective -DomainId $domain.id `
    -Token $ucToken -GraphToken $graphToken -ContactCache $contactCache

# --- Step 3: create or update each key result ---
Write-Host "`nReconciling key results..." -ForegroundColor Cyan
foreach ($kr in $definition.keyResults) {
    Get-OrNewKeyResult -ObjectiveId $objectiveId -DomainId $domain.id -KeyResultDef $kr -Token $ucToken
}

# --- Step 4: link the objective to every named data product ---
Write-Host "`nLinking to related data products..." -ForegroundColor Cyan
foreach ($productName in $definition.relatedDataProducts) {
    Add-ObjectiveToDataProduct -DataProductName $productName -DomainId $domain.id `
        -ObjectiveId $objectiveId -ObjectiveLabel $definition.objective.definition -Token $ucToken
}

# --- Step 5 (optional): publish ---
if ($Publish) {
    Publish-Objective -ObjectiveLabel $definition.objective.definition -ObjectiveId $objectiveId -Token $ucToken
}
else {
    Write-Host "`nObjective left in Draft status (visible only to Data Stewards / Governance Domain Owners). Configure/confirm the governance domain is published, then re-run with -Publish." -ForegroundColor Cyan
}

Write-Host "`nDone. Run validate/Test-Okr.ps1 to verify the deployed configuration." -ForegroundColor Cyan
```

#### `Remove-Okr.ps1`

```powershell
#Requires -Version 7.0
<#
.SYNOPSIS
    Staged rollback for scenarios/unified-catalog/manage-okrs/: unpublish (default), unlink from
    data products (-RemoveLinks), or permanently delete the objective and its key results
    (-Purge).

.DESCRIPTION
    Three independent, additive stages - see rollback.md for the full procedure:
      1. Default: sets the objective's status back to Draft (PUT), reusing its own currently-
         stored fields (fetched via GET) so a portal-made edit isn't clobbered. Reversible -
         nothing is deleted or unlinked.
      2. -RemoveLinks: deletes every entityType=OBJECTIVE relationship the objective's linked data
         products hold (DELETE .../dataProducts/{id}/relationships?entityType=OBJECTIVE&entityId=),
         enumerated from the definition file's own relatedDataProducts list, not re-derived from
         the objective (Data Products' own List Relationships is scoped by data product, not by
         objective - there is no "list every data product this objective is linked to" call).
      3. -Purge: implies -RemoveLinks, then deletes every key result (DELETE
         .../objectives/{id}/keyResults/{keyResultId}) and finally the objective itself (DELETE
         .../objectives/{id}) - matching Microsoft's own documented manual deletion order ("first
         unpublish it and delete any key results and links to related data products").

    Author-only reference code. Never connects to a live tenant unless you supply real credentials
    and omit -WhatIf.

.PARAMETER PurviewAccountEndpoint
    Base URL of the Purview Unified Catalog data-plane API.

.PARAMETER TenantId
    Microsoft Entra tenant ID.

.PARAMETER AppId
    Application (client) ID of the service principal. Must hold Data Steward on the domain.

.PARAMETER ClientSecret
    Client secret for -AppId, as a SecureString.

.PARAMETER DefinitionPath
    Path to the same OKR definition JSON file passed to New-Okr.ps1. The objective and key result
    ids are read directly from this file (design.md Section 3) - no name lookup is performed.

.PARAMETER RemoveLinks
    Deletes the objective's data-product relationships this scenario created. Implied by -Purge.

.PARAMETER Purge
    Permanently deletes every key result, then the objective itself. Not reversible - re-creating
    it via New-Okr.ps1 with the same definition file re-creates the identical id (design.md Section
    3), unlike this repo's name-based sibling scenarios, which mint a new id on re-creation.

.PARAMETER ApiVersion
    Unified Catalog REST API version to pin. Defaults to '2026-03-20-preview'.

.PARAMETER WhatIf
    Standard PowerShell ShouldProcess dry-run.

.EXAMPLE
    ./Remove-Okr.ps1 -PurviewAccountEndpoint 'https://api.purview-service.microsoft.com' `
        -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
        -DefinitionPath './config/customer-data-trust-okr.sample.json'

    Stage 1: unpublish (set back to Draft). Reversible.

.EXAMPLE
    ./Remove-Okr.ps1 -PurviewAccountEndpoint 'https://api.purview-service.microsoft.com' `
        -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
        -DefinitionPath './config/customer-data-trust-okr.sample.json' -Purge

    Stage 3: unlink from data products, delete key results, then delete the objective.
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
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
    [switch]$RemoveLinks,

    [Parameter()]
    [switch]$Purge,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$ApiVersion = '2026-03-20-preview'
)

$ErrorActionPreference = 'Stop'
$endpoint = $PurviewAccountEndpoint.TrimEnd('/')
if ($Purge) { $RemoveLinks = $true }

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

function Invoke-Ucm {
    param(
        [Parameter(Mandatory)][ValidateSet('Get', 'Post', 'Put', 'Delete')][string]$Method,
        [Parameter(Mandatory)][string]$Uri,
        [Parameter()][hashtable]$Body,
        [Parameter(Mandatory)][string]$Token,
        [Parameter()][string]$Description = $Uri,
        [Parameter()][switch]$ReadOnly,
        [Parameter()][switch]$TreatNotFoundAsNull
    )
    if ($Method -eq 'Get' -or $ReadOnly) {
        $params = @{ Method = $Method; Uri = $Uri; Headers = @{ Authorization = "Bearer $Token" } }
        if ($Body) {
            $params.Body = ($Body | ConvertTo-Json -Depth 10)
            $params.ContentType = 'application/json'
        }
        try { return Invoke-RestMethod @params }
        catch {
            if ($TreatNotFoundAsNull -and $_.Exception.Response -and $_.Exception.Response.StatusCode.value__ -eq 404) {
                return $null
            }
            throw
        }
    }
    if ($PSCmdlet.ShouldProcess($Description, "$Method $Uri")) {
        $params = @{
            Method      = $Method
            Uri         = $Uri
            ContentType = 'application/json'
            Headers     = @{ Authorization = "Bearer $Token" }
        }
        if ($Body) { $params.Body = ($Body | ConvertTo-Json -Depth 10) }
        try { return Invoke-RestMethod @params }
        catch {
            if ($_.Exception.Response -and $_.Exception.Response.StatusCode.value__ -eq 404) {
                Write-Host "$Description - already gone (404). Treating as success." -ForegroundColor Yellow
                return $null
            }
            throw
        }
    }
    Write-Verbose "WhatIf: would $Method $Uri"
    return $null
}

function Find-BusinessDomainByName {
    param([Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)][string]$Token)
    $uri = "$endpoint/datagovernance/catalog/businessdomains?api-version=$ApiVersion"
    while ($uri) {
        $page = Invoke-Ucm -Method Get -Uri $uri -Token $Token
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
    $response = Invoke-Ucm -Method Post -Uri $uri -Body $body -Token $Token -ReadOnly
    return ($response.value | Where-Object { $_.name -eq $Name } | Select-Object -First 1)
}

# --- Load the definition file ---
$definition = Get-Content -Path $DefinitionPath -Raw | ConvertFrom-Json

$plainSecret = ConvertTo-PlainText -Secure $ClientSecret
try { $ucToken = Get-PurviewAccessToken -TenantId $TenantId -AppId $AppId -PlainSecret $plainSecret }
finally { $plainSecret = $null }

$domain = Find-BusinessDomainByName -Name $definition.domain.name -Token $ucToken
if (-not $domain) { throw "Governance domain '$($definition.domain.name)' was not found. Nothing to roll back." }

$objectiveId = $definition.objective.id
$getUri = "$endpoint/datagovernance/catalog/objectives/$objectiveId`?api-version=$ApiVersion"
$objective = Invoke-Ucm -Method Get -Uri $getUri -Token $ucToken -TreatNotFoundAsNull
if (-not $objective) {
    Write-Host "Objective (id: $objectiveId) not found - already removed." -ForegroundColor Yellow
    exit 0
}

# --- Stage: remove data-product links ---
if ($RemoveLinks) {
    foreach ($productName in $definition.relatedDataProducts) {
        $product = Find-DataProductByName -Name $productName -DomainId $domain.id -Token $ucToken
        if (-not $product) {
            Write-Host "Data product '$productName' not found - nothing to unlink." -ForegroundColor Yellow
            continue
        }
        $deleteUri = "$endpoint/datagovernance/catalog/dataProducts/$($product.id)/relationships?api-version=$ApiVersion&entityType=OBJECTIVE&entityId=$objectiveId"
        Invoke-Ucm -Method Delete -Uri $deleteUri -Token $ucToken `
            -Description "Unlink data product '$productName' from objective (id: $objectiveId)" | Out-Null
        Write-Host "Unlinked data product '$productName' from objective '$($objective.definition)'." -ForegroundColor Green
    }
}

# --- Stage: purge (delete key results, then the objective) or default (unpublish) ---
if ($Purge) {
    foreach ($kr in $definition.keyResults) {
        $krUri = "$endpoint/datagovernance/catalog/objectives/$objectiveId/keyResults/$($kr.id)?api-version=$ApiVersion"
        Invoke-Ucm -Method Delete -Uri $krUri -Token $ucToken `
            -Description "Delete key result '$($kr.definition)'" | Out-Null
        Write-Host "Deleted key result '$($kr.definition)' (id: $($kr.id))." -ForegroundColor Green
    }
    $uri = "$endpoint/datagovernance/catalog/objectives/$objectiveId`?api-version=$ApiVersion"
    Invoke-Ucm -Method Delete -Uri $uri -Token $ucToken `
        -Description "Delete objective '$($objective.definition)'" | Out-Null
    Write-Host "Deleted objective '$($objective.definition)' (id: $objectiveId)." -ForegroundColor Green
}
else {
    if ($objective.status -ne 'Published') {
        Write-Host "Objective '$($objective.definition)' is already in $($objective.status) status." -ForegroundColor Yellow
    }
    else {
        $body = @{
            id         = $objective.id
            domain     = $objective.domain
            definition = $objective.definition
            status     = 'Draft'
            targetDate = $objective.targetDate
            contacts   = $objective.contacts
        }
        $uri = "$endpoint/datagovernance/catalog/objectives/$objectiveId`?api-version=$ApiVersion"
        Invoke-Ucm -Method Put -Uri $uri -Body $body -Token $ucToken `
            -Description "Unpublish objective '$($objective.definition)'" | Out-Null
        Write-Host "Unpublished objective '$($objective.definition)' (set back to Draft)." -ForegroundColor Green
    }
}

Write-Host "`nDone. Run validate/Test-Okr.ps1 to confirm the resulting state." -ForegroundColor Cyan
```