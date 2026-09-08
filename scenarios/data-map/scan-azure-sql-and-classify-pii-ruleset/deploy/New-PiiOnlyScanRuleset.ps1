#Requires -Version 7.0
<#
.SYNOPSIS
    Creates a custom, PII-only Data Map scan rule set for Azure SQL Database (every system
    classification excluded except the ones you name to keep - U.S. Social Security Number and
    Credit Card Number by default) and reconciles an existing scan onto it.

.DESCRIPTION
    Extends scenarios/data-map/scan-azure-sql-and-classify/ - this script assumes that base
    scenario's deploy/New-AzureSqlDataMapScan.ps1 has already registered the data source and scan
    (System default scan rule set: ~200 built-in sensitive information types). This scenario
    narrows that to a named allowlist, for buyers who want the faster, quieter scan a PII-scoped
    rule set gives them (fewer classification types compared per column = shorter scan time and a
    catalog that only ever shows the handful of classifications a PCI/PII-focused program cares
    about) instead of Microsoft's full ~200-classification system set.

    Calls the Microsoft Purview Data Map / Scanning REST API to:
      1. GET the tenant's current classification type definitions (Data Map "Types" API,
         `type=CLASSIFICATION`) - the live, authoritative list of every system classification
         Microsoft Purview currently supports, both custom and system (`MICROSOFT.*` namespace).
         This script does NOT ship a hard-coded snapshot of that ~200-entry list: Microsoft adds
         and renames system classifications between releases, and typing out ~200 exact
         `MICROSOFT.*` identifiers by hand risks silently fabricating names AGENTS.md Section 4
         forbids. Deriving the exclusion list from the tenant's own live type definitions is both
         more accurate and self-maintaining.
      2. Compute the exclusion set: every classification whose name starts with the reserved
         `MICROSOFT.` namespace (Microsoft's own documented boundary between system and custom
         classifications - reference 6 below), minus whatever you pass to
         -RetainedSystemClassifications (defaults to SSN + Credit Card Number).
      3. PUT (create-or-replace) the custom `AzureSqlDatabaseScanRuleset` object - the confirmed
         REST shape and endpoint below (reference 1).
      4. GET the existing scan object, then PUT it back with only `scanRulesetName`/
         `scanRulesetType` changed - preserves every other scan property (authentication kind,
         database name, collection) exactly as the base scenario left it, rather than
         reconstructing (and risking drifting) the whole scan body from scratch.

    Idempotent by construction: both PUTs are REST create-or-replace calls (same semantics as the
    base scenario's deploy script). Re-running with the same parameters reconciles the ruleset and
    the scan's ruleset reference to this script's current definition.

    Author-only reference code. Never connects to a live tenant unless you supply real credentials
    and omit -WhatIf.

.PARAMETER PurviewAccountName
    Name of the Microsoft Purview account (used to build https://<name>.purview.azure.com).

.PARAMETER TenantId
    Microsoft Entra tenant ID.

.PARAMETER AppId
    Application (client) ID of the service principal used to call the Purview Data Map REST API.
    Must hold the Data Source Administrator role on the target collection - the same role the base
    scenario's deploy script requires (docs/rbac-model.md Section 5). Microsoft Learn does not
    document a narrower role specific to scan rule sets; scan rule set management is covered by
    the same "configure and run a scan" role boundary as the scan itself (reference 7 below).

.PARAMETER ClientSecret
    Client secret for -AppId, as a SecureString. Resolve from a vault at run time - never hard-code.

.PARAMETER DataSourceName
    Name of the data source object already registered by
    scenarios/data-map/scan-azure-sql-and-classify/deploy/New-AzureSqlDataMapScan.ps1.

.PARAMETER ScanName
    Name of the scan object to reconcile onto the new ruleset. Defaults to "<DataSourceName>-scan"
    to match the base scenario's default.

.PARAMETER ScanRulesetName
    Name for the custom scan rule set object. Defaults to 'AzureSqlDatabase-PiiOnly'. Scan rule
    sets are account-wide objects, not scoped to a collection or a single scan (no `collection`
    property exists on `AzureSqlDatabaseScanRulesetProperties` - reference 1) - one PII-only
    ruleset can be reused by every Azure SQL Database scan in the account that wants this same
    narrower scope.

.PARAMETER RetainedSystemClassifications
    System classifications to KEEP (i.e. exclude from the exclusion list). Defaults to
    U.S. Social Security Number and Credit Card Number - the same pair already used in
    scenarios/information-protection/auto-label-confidential-sharepoint/ and
    scenarios/dlp/pci-teams-exfil-block/, confirmed by Microsoft's own worked examples (references
    2 and 3 below).

.PARAMETER IncludedCustomClassificationRuleNames
    Optional. Names of pre-existing CUSTOM classification rules (created via the portal - no
    documented REST endpoint for authoring custom classification rules was found during this
    build, see README.md Section 11) to include alongside the retained system classifications.
    Defaults to none.

.PARAMETER Description
    Free-text description stored on the scan rule set object. Defaults to a generated string
    naming the retained classifications.

.PARAMETER RunNow
    If supplied, starts an immediate Full scan run after the ruleset and scan are reconciled, so
    the narrower classification set takes effect on data already discovered by a prior run.

.PARAMETER ApiVersion
    Data Map REST API version to pin. Defaults to '2023-09-01', confirmed current for both the
    Scan Rulesets and Types endpoints during this build (references 1 and 4 below).

.PARAMETER WhatIf
    Standard PowerShell ShouldProcess dry-run. Reports every REST call that would be made -
    including the computed exclusion list - without sending any mutating (PUT) request. The
    classification type-definitions GET always runs (read-only), even under -WhatIf, so the
    reported exclusion list reflects the tenant's real current classifications.

.EXAMPLE
    ./New-PiiOnlyScanRuleset.ps1 -PurviewAccountName 'contoso-purview' -TenantId $TenantId `
        -AppId $AppId -ClientSecret $ClientSecret -DataSourceName 'sql-contoso-prod-customerdb' -WhatIf

    Dry-run: fetches the tenant's live classification list, computes and prints the exclusion set,
    shows the ruleset PUT and the scan reconciliation PUT that would be made, changes nothing.

.EXAMPLE
    ./New-PiiOnlyScanRuleset.ps1 -PurviewAccountName 'contoso-purview' -TenantId $TenantId `
        -AppId $AppId -ClientSecret $ClientSecret -DataSourceName 'sql-contoso-prod-customerdb' `
        -RetainedSystemClassifications @('MICROSOFT.GOVERNMENT.US.SOCIAL_SECURITY_NUMBER', `
            'MICROSOFT.FINANCIAL.CREDIT_CARD_NUMBER', 'MICROSOFT.GOVERNMENT.US.DRIVERS_LICENSE_NUMBER') `
        -RunNow

    Creates a three-classification ruleset (SSN, credit card, and U.S. driver's license number),
    reconciles the existing scan onto it, and starts an immediate full re-scan.

.NOTES
    GROUNDED (this build): the Scan Rulesets - Create Or Replace and - Get REST reference pages,
    and the Types - List reference page, were all direct-fetched in full during this build - this
    closes the VERIFY the base scenario's README.md Section 11 carried forward ("the exact REST
    JSON body for the 'Scan Rulesets - Create Or Update' operation was not independently
    confirmed"). See README.md Section 11 for the full resolution note.

    VERIFY (pilot tenant, before production use): whether `GET .../types/typedefs?type=CLASSIFICATION`
    paginates once a tenant has a very large number of custom classification rules on top of the
    ~200 system ones - no continuation-token field is documented on this response shape (reference
    4), and this script does not implement paging. Re-open if a pilot tenant run returns a
    truncated classificationDefs array.

    Sources (Microsoft Learn, verify before production use):
    1. Scan Rulesets - Create Or Replace (API version 2023-09-01, confirmed
       AzureSqlDatabaseScanRuleset/AzureSqlDatabaseScanRulesetProperties body schema - direct
       fetch, this build):
       https://learn.microsoft.com/rest/api/purview/scanningdataplane/scan-rulesets/create-or-replace
    2. New-AzPurviewAzureSqlDatabaseScanRulesetObject (Az.Purview PowerShell module - confirms the
       -ExcludedSystemClassification exclusion model with a worked
       MICROSOFT.FINANCIAL.CREDIT_CARD_NUMBER example):
       https://learn.microsoft.com/powershell/module/az.purview/new-azpurviewazuresqldatabasescanrulesetobject
    3. Custom classifications in Data Map ("The Microsoft system classifications are grouped under
       the reserved MICROSOFT. namespace. An example is MICROSOFT.GOVERNMENT.US.SOCIAL_SECURITY_NUMBER."):
       https://learn.microsoft.com/purview/data-map-classification-custom
    4. Type - List (Types API; confirmed `type=CLASSIFICATION` query filter and the
       classificationDefs[].name response shape, worked example
       MICROSOFT.GOVERNMENT.CHILE.CDI_NUMBER - direct fetch, this build):
       https://learn.microsoft.com/rest/api/purview/catalogdataplane/types/get-all-type-definitions
    5. Scan Rulesets - Get (API version 2023-09-01, direct fetch, this build):
       https://learn.microsoft.com/rest/api/purview/scanningdataplane/scan-rulesets/get
    6. Data classification in Data Map ("System classifications: 200+ system classifications...
       formal names... prefixed by MICROSOFT."):
       https://learn.microsoft.com/purview/data-map-classification
    7. Data governance roles and permissions in Microsoft Purview (classic Data Map role
       vocabulary - Data Source Administrator, Data Curator, Data Reader, Collection Admin):
       https://learn.microsoft.com/purview/data-gov-classic-permissions
    8. Scans - Create Or Replace (reused here to reconcile the existing scan's ruleset reference):
       https://learn.microsoft.com/rest/api/purview/scanningdataplane/scans/create-or-replace
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$PurviewAccountName,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$TenantId,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$AppId,

    [Parameter(Mandatory)]
    [SecureString]$ClientSecret,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$DataSourceName,

    [Parameter()]
    [string]$ScanName,

    [Parameter()]
    [ValidatePattern('^[A-Za-z0-9]+(-[A-Za-z0-9]+)*$')]
    [ValidateLength(3, 63)]
    [string]$ScanRulesetName = 'AzureSqlDatabase-PiiOnly',

    [Parameter()]
    [string[]]$RetainedSystemClassifications = @(
        'MICROSOFT.GOVERNMENT.US.SOCIAL_SECURITY_NUMBER',
        'MICROSOFT.FINANCIAL.CREDIT_CARD_NUMBER'
    ),

    [Parameter()]
    [string[]]$IncludedCustomClassificationRuleNames = @(),

    [Parameter()]
    [string]$Description,

    [Parameter()]
    [switch]$RunNow,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$ApiVersion = '2023-09-01'
)

$ErrorActionPreference = 'Stop'

if (-not $ScanName) { $ScanName = "$DataSourceName-scan" }
if (-not $Description) {
    $Description = "PII-only scan rule set - retains only: $($RetainedSystemClassifications -join ', ')"
}

$endpoint = "https://$PurviewAccountName.purview.azure.com"

function Get-PurviewAccessToken {
    <#
        Client-credentials OAuth2 flow against the Data Map data-plane resource - one token is
        valid for both the /scan (Scanning) and /datamap (Types/Catalog) surfaces called below,
        per docs/automation-surface.md Section 3 (single "https://purview.azure.net" resource for
        the whole Data Map data plane).
    #>
    param(
        [Parameter(Mandatory)][string]$TenantId,
        [Parameter(Mandatory)][string]$AppId,
        [Parameter(Mandatory)][SecureString]$ClientSecret
    )
    $plainSecret = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto(
        [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($ClientSecret))
    try {
        $body = @{
            client_id     = $AppId
            client_secret = $plainSecret
            grant_type    = 'client_credentials'
            resource      = 'https://purview.azure.net'
        }
        $response = Invoke-RestMethod -Method Post `
            -Uri "https://login.microsoftonline.com/$TenantId/oauth2/token" -Body $body
        return $response.access_token
    }
    finally {
        $plainSecret = $null
    }
}

function Invoke-PurviewPut {
    param(
        [Parameter(Mandatory)][string]$Uri,
        [Parameter(Mandatory)][hashtable]$Body,
        [Parameter(Mandatory)][string]$Token,
        [Parameter(Mandatory)][string]$Description
    )
    if ($PSCmdlet.ShouldProcess($Description, "PUT $Uri")) {
        $json = $Body | ConvertTo-Json -Depth 10
        return Invoke-RestMethod -Method Put -Uri $Uri -Body $json -ContentType 'application/json' `
            -Headers @{ Authorization = "Bearer $Token" }
    }
    Write-Verbose "WhatIf: would PUT $Uri with body:`n$($Body | ConvertTo-Json -Depth 10)"
    return $null
}

$token = Get-PurviewAccessToken -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret
$headers = @{ Authorization = "Bearer $token" }

# --- Step 1: read-only - fetch the tenant's live classification type definitions ---
Write-Host "Fetching current classification type definitions..." -ForegroundColor Cyan
$typeDefsUri = "$endpoint/datamap/api/atlas/v2/types/typedefs?type=CLASSIFICATION&api-version=$ApiVersion"
$typeDefs = Invoke-RestMethod -Method Get -Uri $typeDefsUri -Headers $headers

$systemClassifications = @($typeDefs.classificationDefs | Where-Object { $_.name -like 'MICROSOFT.*' } | Select-Object -ExpandProperty name)
if ($systemClassifications.Count -lt $RetainedSystemClassifications.Count) {
    throw "Only found $($systemClassifications.Count) MICROSOFT.* system classification(s) in the tenant's type definitions - expected at least $($RetainedSystemClassifications.Count) (the -RetainedSystemClassifications list). Refusing to build a ruleset from an implausibly short list; check the Types API response and -ApiVersion before re-running."
}

$missingRetained = $RetainedSystemClassifications | Where-Object { $_ -notin $systemClassifications }
if ($missingRetained) {
    Write-Warning "The following -RetainedSystemClassifications were not found in the tenant's current type definitions (typo, or Microsoft renamed/retired the classification?): $($missingRetained -join ', ')"
}

$excludedClassifications = @($systemClassifications | Where-Object { $_ -notin $RetainedSystemClassifications } | Sort-Object)
Write-Host "Tenant has $($systemClassifications.Count) system classification(s); retaining $($RetainedSystemClassifications.Count), excluding $($excludedClassifications.Count)." -ForegroundColor Cyan

# --- Step 2: read-only - confirm the target scan exists, and capture its current body ---
$scanUri = "$endpoint/scan/datasources/$DataSourceName/scans/$ScanName?api-version=$ApiVersion"
try {
    $existingScan = Invoke-RestMethod -Method Get -Uri $scanUri -Headers $headers
}
catch {
    if ($_.Exception.Response -and $_.Exception.Response.StatusCode -eq 404) {
        throw "Scan '$ScanName' on data source '$DataSourceName' was not found. This scenario reconciles an EXISTING scan onto a new ruleset - run scenarios/data-map/scan-azure-sql-and-classify/deploy/New-AzureSqlDataMapScan.ps1 first."
    }
    throw
}

# Guard against reconciling a ruleset built for the 'AzureSqlDatabase' data source type onto a
# same-named-but-wrong scan (e.g. a -ScanName/-DataSourceName typo colliding with an unrelated
# scan). Reviews.md Red Team finding: the ruleset's `kind` must match the scan's own source type,
# and PUTting a mismatched scanRulesetName silently succeeds today - it only fails at scan RUN
# time, far away from the mistake that caused it.
$compatibleScanKinds = @('AzureSqlDatabaseMsi', 'AzureSqlDatabaseCredential')
if ($existingScan.kind -notin $compatibleScanKinds) {
    throw "Scan '$ScanName' has kind '$($existingScan.kind)', not one of $($compatibleScanKinds -join '/'). This scenario's scan rule set is kind 'AzureSqlDatabase' and is only compatible with an Azure SQL Database scan - refusing to reconcile a mismatched scan (double-check -DataSourceName/-ScanName)."
}

# --- Step 3: create or replace the custom scan rule set ---
# Scan rule sets are account-wide objects (design.md Section 2, goal 3) - two teams both defaulting
# to -ScanRulesetName 'AzureSqlDatabase-PiiOnly' would silently clobber each other's retained-list
# choice via this create-or-replace PUT. Reviews.md Red Team finding: warn loudly on a content
# change to a pre-existing ruleset (a brand-new ruleset, or a re-run with identical content, stays
# silent) so a shared-object overwrite is never invisible to the operator running this script.
$rulesetUri = "$endpoint/scan/scanrulesets/$ScanRulesetName?api-version=$ApiVersion"
$priorRuleset = $null
try {
    $priorRuleset = Invoke-RestMethod -Method Get -Uri $rulesetUri -Headers $headers
}
catch {
    if (-not ($_.Exception.Response -and $_.Exception.Response.StatusCode -eq 404)) { throw }
}
if ($priorRuleset) {
    $priorExcluded = @($priorRuleset.properties.excludedSystemClassifications)
    $added = @($excludedClassifications | Where-Object { $_ -notin $priorExcluded })
    $removed = @($priorExcluded | Where-Object { $_ -notin $excludedClassifications })
    if ($added -or $removed) {
        Write-Warning "Scan rule set '$ScanRulesetName' already exists with DIFFERENT content - this PUT will overwrite it (account-wide object, may be referenced by other scans). Newly excluded: $($added.Count). No longer excluded (now retained): $($removed.Count)$(if ($removed) { ' -> ' + ($removed -join ', ') })."
    }
}

$rulesetBody = @{
    kind            = 'AzureSqlDatabase'
    scanRulesetType = 'Custom'
    properties      = @{
        description                           = $Description
        excludedSystemClassifications         = $excludedClassifications
        includedCustomClassificationRuleNames = @($IncludedCustomClassificationRuleNames)
    }
}
Invoke-PurviewPut -Uri $rulesetUri -Body $rulesetBody -Token $token `
    -Description "Custom scan rule set '$ScanRulesetName' ($($RetainedSystemClassifications.Count) classification(s) retained)" | Out-Null
Write-Host "Scan rule set '$ScanRulesetName' created/updated." -ForegroundColor Green

# --- Step 4: reconcile the existing scan onto the new ruleset (preserve every other property) ---
$scanBody = @{
    kind       = $existingScan.kind
    properties = @{}
}
foreach ($prop in $existingScan.properties.PSObject.Properties) {
    $scanBody.properties[$prop.Name] = $prop.Value
}
$scanBody.properties['scanRulesetName'] = $ScanRulesetName
$scanBody.properties['scanRulesetType'] = 'Custom'

Invoke-PurviewPut -Uri $scanUri -Body $scanBody -Token $token `
    -Description "Scan '$ScanName' - reconcile onto ruleset '$ScanRulesetName'" | Out-Null
Write-Host "Scan '$ScanName' now references scan rule set '$ScanRulesetName' (Custom)." -ForegroundColor Green

# --- Step 5 (optional): run the scan immediately so the narrower ruleset takes effect ---
if ($RunNow) {
    $runId = [guid]::NewGuid().ToString()
    $runUri = "$endpoint/scan/datasources/$DataSourceName/scans/${ScanName}:run?runId=$runId&scanLevel=Full&api-version=$ApiVersion"
    if ($PSCmdlet.ShouldProcess("Scan '$ScanName'", "Start immediate Full run (runId $runId)")) {
        Invoke-RestMethod -Method Post -Uri $runUri -Headers $headers | Out-Null
        Write-Host "Scan run started (runId: $runId)." -ForegroundColor Cyan
    }
    else {
        Write-Verbose "WhatIf: would POST $runUri to start an immediate Full run."
    }
}

Write-Host "`nDone. Retained classifications: $($RetainedSystemClassifications -join ', ')" -ForegroundColor Cyan
