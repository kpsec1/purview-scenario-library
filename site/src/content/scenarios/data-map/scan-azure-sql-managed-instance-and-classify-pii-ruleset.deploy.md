---
part: "deploy"
parent: "data-map/scan-azure-sql-managed-instance-and-classify-pii-ruleset"
---
The scripts and configuration below deploy this scenario. Review them, then run in order — each is designed to be idempotent and has a matching rollback.


#### `New-PiiOnlyScanRuleset.ps1`

```powershell
#Requires -Version 7.0
<#
.SYNOPSIS
    Creates a custom, PII-only Data Map scan rule set for Azure SQL Managed Instance (every system
    classification excluded except the ones you name to keep - U.S. Social Security Number and
    Credit Card Number by default) and reconciles an existing scan onto it.

.DESCRIPTION
    Extends scenarios/data-map/scan-azure-sql-managed-instance-and-classify/ - this script assumes
    that base scenario's deploy/New-AzureSqlManagedInstanceDataMapScan.ps1 has already registered
    the data source and scan (System default scan rule set: name 'AzureSqlDatabaseManagedInstance',
    ~200 built-in sensitive information types). This scenario narrows that to a named allowlist, for
    buyers who want the faster, quieter scan a PII-scoped rule set gives them instead of Microsoft's
    full ~200-classification system set.

    Same pattern as the sibling scenarios/data-map/scan-azure-sql-and-classify-pii-ruleset/ and
    scenarios/data-map/scan-azure-synapse-and-classify-pii-ruleset/:

      1. GET the tenant's current classification type definitions (Data Map "Types" API,
         `type=CLASSIFICATION`) - the live, authoritative list of every system classification
         Microsoft Purview currently supports (tenant-wide, not source-type-specific). This script
         does NOT ship a hard-coded snapshot of that ~200-entry list - see README.md Section 11 and
         design.md Section 2 goal 1 for why.
      2. Compute the exclusion set: every classification whose name starts with the reserved
         `MICROSOFT.` namespace, minus whatever you pass to -RetainedSystemClassifications
         (defaults to SSN + Credit Card Number).
      3. PUT (create-or-replace) the custom AzureSqlDatabaseManagedInstanceScanRuleset object -
         `kind: AzureSqlDatabaseManagedInstance`, confirmed directly against the Az.Purview
         PowerShell module's own GitHub source (reference 1 below). Unlike the Azure Synapse
         Analytics sibling, this `kind` string is IDENTICAL to the System default ruleset's own
         NAME ('AzureSqlDatabaseManagedInstance') - the same name-equals-kind shortcut the Azure SQL
         Database sibling already uses, not the Synapse naming trap - see README.md Section 11.
      4. GET the existing scan object, then PUT it back with only `scanRulesetName`/
         `scanRulesetType` changed - preserves every other scan property (authentication kind,
         server endpoint, database name, collection) exactly as the base scenario left it.

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
    Must hold the Data Source Administrator role on the target collection (docs/rbac-model.md
    Section 5). Microsoft Learn does not document a narrower role specific to scan rule sets.

.PARAMETER ClientSecret
    Client secret for -AppId, as a SecureString. Resolve from a vault at run time - never hard-code.

.PARAMETER DataSourceName
    Name of the data source object already registered by
    scenarios/data-map/scan-azure-sql-managed-instance-and-classify/deploy/
    New-AzureSqlManagedInstanceDataMapScan.ps1 (defaults to "<InstanceName>-<DatabaseName>" in that
    base scenario).

.PARAMETER ScanName
    Name of the scan object to reconcile onto the new ruleset. Defaults to "<DataSourceName>-scan"
    to match the base scenario's default.

.PARAMETER ScanRulesetName
    Name for the custom scan rule set object. Defaults to
    'AzureSqlDatabaseManagedInstance-PiiOnly'. Scan rule sets are account-wide objects, not scoped
    to a collection or a single scan (no `CollectionReferenceName`-equivalent parameter exists on
    the New-AzPurviewAzureSqlDatabaseManagedInstanceScanRulesetObject constructor - reference 1) -
    one PII-only ruleset can be reused by every Azure SQL Managed Instance scan in the account that
    wants this same narrower scope.

.PARAMETER RetainedSystemClassifications
    System classifications to KEEP (i.e. exclude from the exclusion list). Defaults to
    U.S. Social Security Number and Credit Card Number - the same pair every Data Map PII-ruleset
    scenario in this repo uses.

.PARAMETER IncludedCustomClassificationRuleNames
    Optional. Names of pre-existing CUSTOM classification rules (created via the portal - no
    documented REST endpoint for authoring custom classification rules was found, see README.md
    Section 11) to include alongside the retained system classifications. Defaults to none.

.PARAMETER Description
    Free-text description stored on the scan rule set object. Defaults to a generated string
    naming the retained classifications.

.PARAMETER RunNow
    If supplied, starts an immediate Full scan run after the ruleset and scan are reconciled, so
    the narrower classification set takes effect on data already discovered by a prior run.

.PARAMETER ApiVersion
    Data Map REST API version to pin. Defaults to '2023-09-01', matching the base scenario and both
    sibling PII-ruleset scenarios.

.PARAMETER WhatIf
    Standard PowerShell ShouldProcess dry-run. Reports every REST call that would be made -
    including the computed exclusion list - without sending any mutating (PUT) request. The
    classification type-definitions GET always runs (read-only), even under -WhatIf, so the
    reported exclusion list reflects the tenant's real current classifications.

.EXAMPLE
    ./New-PiiOnlyScanRuleset.ps1 -PurviewAccountName 'contoso-purview' -TenantId $TenantId `
        -AppId $AppId -ClientSecret $ClientSecret -DataSourceName 'mi-contoso-prod-customerdb' -WhatIf

    Dry-run: fetches the tenant's live classification list, computes and prints the exclusion set,
    shows the ruleset PUT and the scan reconciliation PUT that would be made, changes nothing.

.EXAMPLE
    ./New-PiiOnlyScanRuleset.ps1 -PurviewAccountName 'contoso-purview' -TenantId $TenantId `
        -AppId $AppId -ClientSecret $ClientSecret -DataSourceName 'mi-contoso-prod-customerdb' `
        -RetainedSystemClassifications @('MICROSOFT.GOVERNMENT.US.SOCIAL_SECURITY_NUMBER', `
            'MICROSOFT.FINANCIAL.CREDIT_CARD_NUMBER', 'MICROSOFT.GOVERNMENT.US.DRIVERS_LICENSE_NUMBER') `
        -RunNow

    Creates a three-classification ruleset (SSN, credit card, and U.S. driver's license number),
    reconciles the existing scan onto it, and starts an immediate full re-scan.

.NOTES
    GROUNDED (this build): the Custom AzureSqlDatabaseManagedInstanceScanRuleset object shape and
    its `Kind: AzureSqlDatabaseManagedInstance` value were confirmed via direct fetch
    (raw.githubusercontent.com) of the Az.Purview PowerShell module's own
    New-AzPurviewAzureSqlDatabaseManagedInstanceScanRulesetObject.md source, after
    learn.microsoft.com's REST API reference pages returned EGRESS_BLOCKED in this build
    environment - the same access restriction and workaround the Synapse sibling's own build
    documented. Confirmed: this source type's custom ruleset `kind` is the IDENTICAL string to the
    System default ruleset's NAME ('AzureSqlDatabaseManagedInstance') - the Azure SQL Database
    sibling's name-equals-kind pattern, not the Synapse sibling's naming trap. Do not assume this
    holds for the still-unbuilt on-premises SQL Server sibling without its own independent check
    (PROGRESS.md tracks that as a separate, not-yet-built fragment).

    VERIFY (pilot tenant or a future pass once learn.microsoft.com is reachable): an independent
    direct fetch of the Scan Rulesets - Create Or Replace REST reference page specifically for the
    AzureSqlDatabaseManagedInstanceScanRuleset body shape (the generic call shape and the Azure SQL
    Database variant's body were confirmed this way in an earlier build; this build's Managed
    Instance-specific confirmation came from the PowerShell module source instead, a materially
    different but still official Microsoft-maintained reference). See README.md Section 11.

    VERIFY (pilot tenant, before production use): whether `GET .../types/typedefs?type=CLASSIFICATION`
    paginates once a tenant has a very large number of custom classification rules on top of the
    ~200 system ones - no continuation-token field is documented on this response shape, and this
    script does not implement paging. Re-open if a pilot tenant run returns a truncated
    classificationDefs array. Same open item every sibling PII-ruleset scenario in this repo carries.

    Sources (Microsoft Learn / Az.Purview module, verify before production use):
    1. New-AzPurviewAzureSqlDatabaseManagedInstanceScanRulesetObject (Az.Purview PowerShell module -
       confirms the Custom AzureSqlDatabaseManagedInstanceScanRuleset shape and
       Kind: AzureSqlDatabaseManagedInstance, direct fetch via GitHub raw source, this build):
       https://raw.githubusercontent.com/Azure/azure-powershell/main/src/Purview/Purview/help/New-AzPurviewAzureSqlDatabaseManagedInstanceScanRulesetObject.md
    2. New-AzPurviewAzureSqlDatabaseManagedInstanceMsiScanObject (Az.Purview PowerShell module -
       confirms Kind: AzureSqlDatabaseManagedInstanceMsi and
       ScanRulesetName: AzureSqlDatabaseManagedInstance / ScanRulesetType: System as the shared
       System default, reused unchanged from the base scenario's own citation):
       https://learn.microsoft.com/powershell/module/az.purview/new-azpurviewazuresqldatabasemanagedinstancemsiscanobject
    3. Scan Rulesets - Create Or Replace / - Get (API version 2023-09-01, generic call shape
       confirmed by direct fetch during the Azure SQL Database sibling scenario's build):
       https://learn.microsoft.com/rest/api/purview/scanningdataplane/scan-rulesets/create-or-replace
       https://learn.microsoft.com/rest/api/purview/scanningdataplane/scan-rulesets/get
    4. Type - List (Types API; tenant-wide, source-type-agnostic; reused unchanged from the Azure
       SQL Database sibling's own direct fetch):
       https://learn.microsoft.com/rest/api/purview/catalogdataplane/types/get-all-type-definitions
    5. Connect to and manage an Azure SQL Managed Instance in Microsoft Purview (confirms
       'AzureSqlDatabaseManagedInstance' as the System default scan rule set name):
       https://learn.microsoft.com/purview/register-scan-azure-sql-managed-instance
    6. Scans - Create Or Replace (reused here to reconcile the existing scan's ruleset reference):
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
    [string]$ScanRulesetName = 'AzureSqlDatabaseManagedInstance-PiiOnly',

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
        throw "Scan '$ScanName' on data source '$DataSourceName' was not found. This scenario reconciles an EXISTING scan onto a new ruleset - run scenarios/data-map/scan-azure-sql-managed-instance-and-classify/deploy/New-AzureSqlManagedInstanceDataMapScan.ps1 first."
    }
    throw
}

# Guard against reconciling a ruleset built for the 'AzureSqlDatabaseManagedInstance' data source
# type onto a same-named-but-wrong scan (e.g. a -ScanName/-DataSourceName typo colliding with an
# unrelated scan). Same Red Team-flagged guard both sibling PII-ruleset scenarios already carry:
# the ruleset's `kind` must match the scan's own source type, and PUTting a mismatched
# scanRulesetName silently succeeds today - it only fails at scan RUN time, far away from the
# mistake that caused it.
$compatibleScanKinds = @('AzureSqlDatabaseManagedInstanceMsi', 'AzureSqlDatabaseManagedInstanceCredential')
if ($existingScan.kind -notin $compatibleScanKinds) {
    throw "Scan '$ScanName' has kind '$($existingScan.kind)', not one of $($compatibleScanKinds -join '/'). This scenario's scan rule set is kind 'AzureSqlDatabaseManagedInstance' and is only compatible with an Azure SQL Managed Instance scan - refusing to reconcile a mismatched scan (double-check -DataSourceName/-ScanName)."
}

# --- Step 3: create or replace the custom scan rule set ---
# Scan rule sets are account-wide objects (design.md Section 2, goal 3) - two teams both defaulting
# to -ScanRulesetName 'AzureSqlDatabaseManagedInstance-PiiOnly' would silently clobber each other's
# retained-list choice via this create-or-replace PUT. Same guard both sibling scenarios use: warn
# loudly on a content change to a pre-existing ruleset (a brand-new ruleset, or a re-run with
# identical content, stays silent) so a shared-object overwrite is never invisible to the operator
# running this script.
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
    kind            = 'AzureSqlDatabaseManagedInstance'
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
        Write-Host "Scan run started (runId: $runId). A first full scan of a nontrivial managed instance database can take from minutes to hours - poll validate/Test-PiiOnlyScanRuleset.ps1 or the portal for status." -ForegroundColor Cyan
    }
    else {
        Write-Verbose "WhatIf: would POST $runUri to start an immediate Full run."
    }
}

Write-Host "`nDone. Retained classifications: $($RetainedSystemClassifications -join ', ')" -ForegroundColor Cyan
```

#### `Remove-PiiOnlyScanRuleset.ps1`

```powershell
#Requires -Version 7.0
<#
.SYNOPSIS
    Reverts the scan created by scan-azure-sql-managed-instance-and-classify back onto the System
    scan rule set ('AzureSqlDatabaseManagedInstance'), then optionally deletes the custom PII-only
    scan rule set created by New-PiiOnlyScanRuleset.ps1.

.DESCRIPTION
    Calls the Microsoft Purview Data Map / Scanning REST API to:
      1. GET the target scan and PUT it back with `scanRulesetName`/`scanRulesetType` reset to the
         System ruleset (every other scan property - authentication kind, server endpoint, database
         name, collection - preserved unchanged), so the scan reverts to classifying against
         Microsoft's full built-in set instead of the narrower PII-only allowlist.
      2. (only with -DeleteRuleset) DELETE the custom scan rule set object itself.

    Order matters: a scan rule set that is still referenced by a scan is not guaranteed to be
    deletable (no Microsoft documentation confirms deleting an in-use ruleset either succeeds or
    is blocked - this script does not assume either behavior and always detaches the scan first).

    Idempotent: reverting a scan that already points at a System ruleset, or deleting a rule set
    that is already gone, are both treated as success (a 404 on the DELETE call is a no-op, not an
    error).

    Author-only reference code. Never connects to a live tenant unless you supply real credentials
    and omit -WhatIf.

.PARAMETER PurviewAccountName
    Name of the Microsoft Purview account.

.PARAMETER TenantId
    Microsoft Entra tenant ID.

.PARAMETER AppId
    Application (client) ID of the service principal used to call the Purview Data Map REST API.

.PARAMETER ClientSecret
    Client secret for -AppId, as a SecureString.

.PARAMETER DataSourceName
    Name of the data source object the scan belongs to.

.PARAMETER ScanName
    Name of the scan object to revert. Defaults to "<DataSourceName>-scan".

.PARAMETER ScanRulesetName
    Name of the custom scan rule set to detach (and, with -DeleteRuleset, remove). Defaults to
    'AzureSqlDatabaseManagedInstance-PiiOnly' to match New-PiiOnlyScanRuleset.ps1's default.

.PARAMETER RevertToRulesetName
    System scan rule set to revert the scan onto. Defaults to 'AzureSqlDatabaseManagedInstance' -
    the System default NAME for this source type, which (unlike the Azure Synapse Analytics
    sibling) is the IDENTICAL string to the custom ruleset's own `kind` value. Confirmed against
    scan-azure-sql-managed-instance-and-classify's own -ScanRulesetName default and against
    New-AzPurviewAzureSqlDatabaseManagedInstanceMsiScanObject's worked example, which shows
    `ScanRulesetName: AzureSqlDatabaseManagedInstance` / `ScanRulesetType: System`.

.PARAMETER DeleteRuleset
    If supplied, also deletes the custom scan rule set object after the scan has been detached
    from it. Omit to keep the ruleset object defined (e.g. it is still referenced by another
    scan - scan rule sets are account-wide, not scoped to one scan) while only reverting this one
    scan.

.PARAMETER ApiVersion
    Data Map REST API version to pin. Defaults to '2023-09-01'.

.PARAMETER WhatIf
    Standard PowerShell ShouldProcess dry-run. Reports every REST call that would be made without
    sending any mutating (PUT/DELETE) request.

.EXAMPLE
    ./Remove-PiiOnlyScanRuleset.ps1 -PurviewAccountName 'contoso-purview' -TenantId $TenantId `
        -AppId $AppId -ClientSecret $ClientSecret -DataSourceName 'mi-contoso-prod-customerdb' -WhatIf

    Dry-run: shows the scan-revert PUT that would be made, changes nothing.

.EXAMPLE
    ./Remove-PiiOnlyScanRuleset.ps1 -PurviewAccountName 'contoso-purview' -TenantId $TenantId `
        -AppId $AppId -ClientSecret $ClientSecret -DataSourceName 'mi-contoso-prod-customerdb' `
        -DeleteRuleset

    Reverts the scan to the System default ruleset ('AzureSqlDatabaseManagedInstance'), then
    deletes the custom PII-only ruleset object.

.NOTES
    Sources (Microsoft Learn / Az.Purview module, verify before production use):
    - New-AzPurviewAzureSqlDatabaseManagedInstanceMsiScanObject (Az.Purview PowerShell module -
      confirms 'AzureSqlDatabaseManagedInstance'/'System' as the shared System default, reused
      unchanged from the base scenario's own citation):
      https://learn.microsoft.com/powershell/module/az.purview/new-azpurviewazuresqldatabasemanagedinstancemsiscanobject
    - Scan Rulesets - Get / Delete (API version 2023-09-01):
      https://learn.microsoft.com/rest/api/purview/scanningdataplane/scan-rulesets/get
    - Remove-AzPurviewScanRuleset (Az.Purview PowerShell module - corroborates the delete operation
      exists per scan rule set object):
      https://learn.microsoft.com/powershell/module/az.purview/remove-azpurviewscanruleset
    - Scans - Create Or Replace (reused here to revert the scan's ruleset reference):
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
    [ValidateNotNullOrEmpty()]
    [string]$ScanRulesetName = 'AzureSqlDatabaseManagedInstance-PiiOnly',

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$RevertToRulesetName = 'AzureSqlDatabaseManagedInstance',

    [Parameter()]
    [switch]$DeleteRuleset,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$ApiVersion = '2023-09-01'
)

$ErrorActionPreference = 'Stop'

if (-not $ScanName) { $ScanName = "$DataSourceName-scan" }

$endpoint = "https://$PurviewAccountName.purview.azure.com"

function Get-PurviewAccessToken {
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

$token = Get-PurviewAccessToken -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret
$headers = @{ Authorization = "Bearer $token" }

# --- Step 1: revert the scan onto the System ruleset (preserve every other scan property) ---
$scanUri = "$endpoint/scan/datasources/$DataSourceName/scans/$ScanName?api-version=$ApiVersion"
$existingScan = $null
try {
    $existingScan = Invoke-RestMethod -Method Get -Uri $scanUri -Headers $headers
}
catch {
    if (-not ($_.Exception.Response -and $_.Exception.Response.StatusCode -eq 404)) { throw }
}

if ($existingScan) {
    $scanBody = @{
        kind       = $existingScan.kind
        properties = @{}
    }
    foreach ($prop in $existingScan.properties.PSObject.Properties) {
        $scanBody.properties[$prop.Name] = $prop.Value
    }
    $scanBody.properties['scanRulesetName'] = $RevertToRulesetName
    $scanBody.properties['scanRulesetType'] = 'System'

    if ($PSCmdlet.ShouldProcess("Scan '$ScanName'", "Revert to ruleset '$RevertToRulesetName' (System)")) {
        $json = $scanBody | ConvertTo-Json -Depth 10
        Invoke-RestMethod -Method Put -Uri $scanUri -Body $json -ContentType 'application/json' -Headers $headers | Out-Null
        Write-Host "Scan '$ScanName' reverted to ruleset '$RevertToRulesetName' (System)." -ForegroundColor Green
    }
    else {
        Write-Verbose "WhatIf: would PUT $scanUri to revert scanRulesetName to '$RevertToRulesetName' (System)."
    }
}
else {
    Write-Host "Scan '$ScanName' on data source '$DataSourceName' not found (already removed?) - nothing to revert." -ForegroundColor Yellow
}

# --- Step 2 (optional): delete the custom scan rule set object ---
if ($DeleteRuleset) {
    $rulesetUri = "$endpoint/scan/scanrulesets/$ScanRulesetName?api-version=$ApiVersion"
    if ($PSCmdlet.ShouldProcess("Scan rule set '$ScanRulesetName'", "DELETE $rulesetUri")) {
        try {
            Invoke-RestMethod -Method Delete -Uri $rulesetUri -Headers $headers | Out-Null
            Write-Host "Scan rule set '$ScanRulesetName' deleted." -ForegroundColor Green
        }
        catch {
            if ($_.Exception.Response -and $_.Exception.Response.StatusCode -eq 404) {
                Write-Host "Scan rule set '$ScanRulesetName' already absent (no-op)." -ForegroundColor Yellow
            }
            else {
                throw
            }
        }
    }
    else {
        Write-Verbose "WhatIf: would DELETE $rulesetUri"
    }
}
else {
    Write-Host "Scan rule set '$ScanRulesetName' left in place (pass -DeleteRuleset to remove it too - confirm no other scan still references it first)." -ForegroundColor Yellow
}

Write-Host "`nDone." -ForegroundColor Cyan
```