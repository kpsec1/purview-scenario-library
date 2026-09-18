---
part: "deploy"
parent: "data-map/scan-azure-sql-and-classify"
---
The scripts and configuration below deploy this scenario. Review them, then run in order — each is designed to be idempotent and has a matching rollback.


#### `New-AzureSqlDataMapScan.ps1`

```powershell
#Requires -Version 7.0
<#
.SYNOPSIS
    Registers an Azure SQL Database as a Microsoft Purview Data Map source and configures a
    SAMI-authenticated scan against it, optionally with a recurring trigger and/or an immediate run.

.DESCRIPTION
    Calls the Microsoft Purview Data Map / Scanning REST API (automation surface 4 per
    docs/automation-surface.md) to:
      1. Create or replace the AzureSqlDatabase data source object.
      2. Create or replace an AzureSqlDatabaseMsi scan object (authenticates as the Purview
         account's own system-assigned managed identity - no credential object to manage).
      3. Optionally create or replace a recurring trigger (-RecurrenceFrequency).
      4. Optionally start an immediate scan run (-RunNow).

    Idempotent by construction: every mutating call in this script is a REST PUT against a
    create-or-replace endpoint (Microsoft Learn: scanningdataplane/scans/create-or-replace -
    "If the object doesn't exist, it's created. If it already exists, it's overwritten using the
    new definition."). Re-running this script with the same parameters reconciles the objects to
    the script's current definition rather than erroring or duplicating.

    This script does NOT create the two out-of-band grants the SAMI-authenticated scan depends on:
      - Azure IAM "Reader" role for the Purview account on the SQL Server/resource group/subscription
      - db_datareader for the Purview account as a Microsoft Entra external-provider database user
    Both are one-time, ARM/SQL-side prerequisites documented in README.md Sections 3 and 5 - grant
    them before running this script, or the scan will register successfully but fail on its first run.

    Author-only reference code. Never connects to a live tenant unless you supply real credentials
    and omit -WhatIf. Nothing in this script runs a scan or creates a trigger unless you explicitly
    pass -RunNow or -RecurrenceFrequency.

.PARAMETER PurviewAccountName
    Name of the Microsoft Purview account (used to build https://<name>.purview.azure.com).

.PARAMETER TenantId
    Microsoft Entra tenant ID.

.PARAMETER AppId
    Application (client) ID of the service principal used to call the Purview Data Map REST API.
    Must hold the Data Source Administrator role on the target collection (docs/rbac-model.md Section 5).

.PARAMETER ClientSecret
    Client secret for -AppId, as a SecureString. Resolve from a vault at run time - never hard-code.
    (docs/automation-surface.md documents certificate-based app-only auth as this library's preferred
    pattern for Exchange/S&C/Graph surfaces; the Data Map data-plane token flow documented by
    Microsoft for this surface uses a client secret - see README.md reference 3.)

.PARAMETER SubscriptionId
    Azure subscription ID containing the target Azure SQL logical server.

.PARAMETER ResourceGroupName
    Resource group containing the target Azure SQL logical server.

.PARAMETER SqlServerName
    Name of the Azure SQL logical server (not the fully qualified server endpoint).

.PARAMETER DatabaseName
    Name of the database on the logical server to scan.

.PARAMETER Location
    Azure region of the SQL logical server (e.g. 'eastus').

.PARAMETER CollectionReferenceName
    The Data Map collection's 5-character reference ID (NOT its friendly name) - read it from the
    collection's URL in the Purview portal, or the List Collections REST API. See README.md Section 6.

.PARAMETER DataSourceName
    Name for the registered data source object. Defaults to "<SqlServerName>-<DatabaseName>".

.PARAMETER ScanName
    Name for the scan object. Defaults to "<DataSourceName>-scan".

.PARAMETER ScanRulesetName
    Scan rule set to use. Defaults to 'AzureSqlDatabase' (Microsoft's system default for this
    source type - includes ~200 built-in sensitive information types, including U.S. Social
    Security Number and Credit Card Number). Pass a custom rule set's name if one already exists
    in this collection (this script does not create custom rule sets - see README.md Section 11 VERIFY).

.PARAMETER ScanRulesetType
    'System' (default) or 'Custom'.

.PARAMETER ScanLevel
    'Full' or 'Incremental'. Used for the recurring trigger's default level and for -RunNow.
    Defaults to 'Full'.

.PARAMETER RecurrenceFrequency
    If supplied, creates a recurring trigger at this frequency: Hour, Day, Week, or Month.
    Omit to leave the scan without a schedule (register-only, or run only via -RunNow).

.PARAMETER RecurrenceInterval
    Interval multiplier for -RecurrenceFrequency (e.g. 1 with Week = every week). Defaults to 1.

.PARAMETER RecurrenceStartTime
    UTC start time for the recurring trigger. Defaults to (Get-Date).ToUniversalTime().

.PARAMETER RunNow
    If supplied, starts an immediate scan run (POST-equivalent PUT to the runs/{runId} endpoint)
    after the data source and scan objects are created/updated.

.PARAMETER ApiVersion
    Data Map REST API version to pin. Defaults to '2023-09-01', confirmed current for the Scans
    object at the time of this build (see README.md Section 11 VERIFY for the sibling endpoints).

.PARAMETER WhatIf
    Standard PowerShell ShouldProcess dry-run. Reports every REST call that would be made without
    sending any mutating (PUT) request. Invoke-RestMethod has no native ShouldProcess integration,
    so this script wraps each mutating call in its own $PSCmdlet.ShouldProcess() check.

.EXAMPLE
    ./New-AzureSqlDataMapScan.ps1 -PurviewAccountName 'contoso-purview' -TenantId $TenantId `
        -AppId $AppId -ClientSecret $ClientSecret -SubscriptionId $SubscriptionId `
        -ResourceGroupName 'rg-contoso-data' -SqlServerName 'sql-contoso-prod' `
        -DatabaseName 'customerdb' -Location 'eastus' -CollectionReferenceName 'a1b2c' -WhatIf

    Dry-run: shows exactly which REST calls would be made, changes nothing.

.EXAMPLE
    ./New-AzureSqlDataMapScan.ps1 -PurviewAccountName 'contoso-purview' -TenantId $TenantId `
        -AppId $AppId -ClientSecret $ClientSecret -SubscriptionId $SubscriptionId `
        -ResourceGroupName 'rg-contoso-data' -SqlServerName 'sql-contoso-prod' `
        -DatabaseName 'customerdb' -Location 'eastus' -CollectionReferenceName 'a1b2c' `
        -RecurrenceFrequency Week -RunNow

    Registers the source, configures the scan, adds a weekly trigger, and kicks off an immediate
    full scan.

.NOTES
    VERIFY before production use (see README.md Section 11 for full detail): the Data Sources and
    Triggers REST body shapes were reconstructed from the confirmed Scans - Create Or Replace
    endpoint's path pattern and API version, the official @azure-rest/purview-scanning JS SDK type
    definitions, and the Az.Purview PowerShell module's parameter signatures - their own canonical
    REST reference pages returned fetch errors in this build's environment. Confirm against a pilot
    tenant or the OpenAPI spec before relying on this in production.

    CORRECTED (2026-09-04, backported from scenarios/data-map/scan-azure-sql-managed-instance-and-
    classify/, whose build independently direct-fetched the canonical Scan Result reference pages
    this scenario's original build could not reach): Scan Result - Run Scan is an action-style
    `POST {endpoint}/scan/datasources/{ds}/scans/{scan}:run?runId={guid}&scanLevel={level}&
    api-version=...` (colon-suffixed action, runId as a query parameter) - this script previously
    sent an unconfirmed resource-style `PUT .../runs/{runId}`, now corrected below. See
    validate/Test-AzureSqlDataMapScan.ps1 for the matching List Scan History correction.

    Sources (Microsoft Learn, verify before production use):
    - Scans - Create Or Replace (API version 2023-09-01, confirmed body schema):
      https://learn.microsoft.com/rest/api/purview/scanningdataplane/scans/create-or-replace
    - Scan Result - Run Scan (confirmed the POST .../:run?runId=... shape, direct-fetched during the
      Azure SQL Managed Instance sibling scenario's build):
      https://learn.microsoft.com/rest/api/purview/scanningdataplane/scan-result/run-scan
    - Discover and govern Azure SQL Database (registration, SAMI authentication, T-SQL grants):
      https://learn.microsoft.com/purview/register-scan-azure-sql-database
    - Tutorial: Authenticate for Microsoft Purview data-plane APIs (token acquisition, roles):
      https://learn.microsoft.com/purview/data-gov-api-rest-data-plane
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
    [string]$SubscriptionId,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$ResourceGroupName,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$SqlServerName,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$DatabaseName,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$Location,

    [Parameter(Mandatory)]
    [ValidatePattern('^[A-Za-z0-9]{1,10}$')]
    [string]$CollectionReferenceName,

    [Parameter()]
    [ValidatePattern('^[A-Za-z0-9]+(-[A-Za-z0-9]+)*$')]
    [string]$DataSourceName,

    [Parameter()]
    [ValidatePattern('^[A-Za-z0-9]+(-[A-Za-z0-9]+)*$')]
    [string]$ScanName,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$ScanRulesetName = 'AzureSqlDatabase',

    [Parameter()]
    [ValidateSet('System', 'Custom')]
    [string]$ScanRulesetType = 'System',

    [Parameter()]
    [ValidateSet('Full', 'Incremental')]
    [string]$ScanLevel = 'Full',

    [Parameter()]
    [ValidateSet('Hour', 'Day', 'Week', 'Month')]
    [string]$RecurrenceFrequency,

    [Parameter()]
    [ValidateRange(1, 1000)]
    [int]$RecurrenceInterval = 1,

    [Parameter()]
    [datetime]$RecurrenceStartTime = (Get-Date).ToUniversalTime(),

    [Parameter()]
    [switch]$RunNow,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$ApiVersion = '2023-09-01'
)

$ErrorActionPreference = 'Stop'

if (-not $DataSourceName) { $DataSourceName = "$SqlServerName-$DatabaseName" }
if (-not $ScanName) { $ScanName = "$DataSourceName-scan" }

$endpoint = "https://$PurviewAccountName.purview.azure.com"
$serverEndpoint = "$SqlServerName.database.windows.net"
$collectionRef = @{ referenceName = $CollectionReferenceName; type = 'CollectionReference' }

function Get-PurviewAccessToken {
    <#
        Client-credentials OAuth2 flow against the Data Map data-plane resource, per
        docs/automation-surface.md Section 3 and README.md reference 3 (data-gov-api-rest-data-plane).
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

# --- Step 1: register (or reconcile) the data source ---
$dataSourceUri = "$endpoint/scan/datasources/$DataSourceName?api-version=$ApiVersion"
$dataSourceBody = @{
    kind       = 'AzureSqlDatabase'
    properties = @{
        serverEndpoint = $serverEndpoint
        resourceName   = $SqlServerName
        resourceGroup  = $ResourceGroupName
        subscriptionId = $SubscriptionId
        location       = $Location
        collection     = $collectionRef
    }
}
Invoke-PurviewPut -Uri $dataSourceUri -Body $dataSourceBody -Token $token `
    -Description "Data source '$DataSourceName' ($serverEndpoint)" | Out-Null
Write-Host "Data source '$DataSourceName' created/updated." -ForegroundColor Green

# --- Step 2: create (or reconcile) the scan, authenticating as the Purview account's SAMI ---
$scanUri = "$endpoint/scan/datasources/$DataSourceName/scans/$ScanName?api-version=$ApiVersion"
$scanBody = @{
    kind       = 'AzureSqlDatabaseMsi'
    properties = @{
        databaseName    = $DatabaseName
        serverEndpoint  = $serverEndpoint
        collection      = $collectionRef
        scanRulesetName = $ScanRulesetName
        scanRulesetType = $ScanRulesetType
    }
}
Invoke-PurviewPut -Uri $scanUri -Body $scanBody -Token $token `
    -Description "Scan '$ScanName' on data source '$DataSourceName'" | Out-Null
Write-Host "Scan '$ScanName' created/updated (kind: AzureSqlDatabaseMsi, ruleset: $ScanRulesetName [$ScanRulesetType])." -ForegroundColor Green

# --- Step 3 (optional): create a recurring trigger ---
if ($RecurrenceFrequency) {
    $triggerUri = "$endpoint/scan/datasources/$DataSourceName/scans/$ScanName/triggers/default?api-version=$ApiVersion"
    $triggerBody = @{
        properties = @{
            scanLevel  = $ScanLevel
            recurrence = @{
                frequency = $RecurrenceFrequency
                interval  = $RecurrenceInterval
                startTime = $RecurrenceStartTime.ToString('o')
            }
        }
    }
    Invoke-PurviewPut -Uri $triggerUri -Body $triggerBody -Token $token `
        -Description "Recurring trigger for scan '$ScanName' (every $RecurrenceInterval $RecurrenceFrequency)" | Out-Null
    Write-Host "Recurring trigger created/updated: every $RecurrenceInterval $RecurrenceFrequency, level $ScanLevel, starting $($RecurrenceStartTime.ToString('u'))." -ForegroundColor Green
}

# --- Step 4 (optional): run the scan immediately ---
if ($RunNow) {
    $runId = [guid]::NewGuid().ToString()
    # Confirmed shape (README.md reference 5): action-style POST with a colon suffix and runId as a
    # query parameter - NOT a resource-style PUT to .../runs/{runId}. Corrected 2026-09-04; see .NOTES.
    $runUri = "$endpoint/scan/datasources/$DataSourceName/scans/${ScanName}:run?runId=$runId&scanLevel=$ScanLevel&api-version=$ApiVersion"
    if ($PSCmdlet.ShouldProcess("Scan '$ScanName'", "Start immediate $ScanLevel run (runId $runId)")) {
        Invoke-RestMethod -Method Post -Uri $runUri -Headers @{ Authorization = "Bearer $token" } | Out-Null
        Write-Host "Scan run started (runId: $runId). Poll validate/Test-AzureSqlDataMapScan.ps1 for status - a first full scan of a nontrivial database can take from minutes to hours." -ForegroundColor Cyan
    }
    else {
        Write-Verbose "WhatIf: would POST $runUri to start an immediate $ScanLevel run."
    }
}

Write-Host "`nDone. Remember: the SAMI-authenticated scan will fail at run time unless the Azure IAM Reader grant and the SQL db_datareader grant documented in README.md Sections 3 and 5 are already in place." -ForegroundColor Cyan
```

#### `policy/azure-sql-datamap-scan.json`

```json
{
  "$comment": "Reference/documentation copy of the three REST request bodies deploy/New-AzureSqlDataMapScan.ps1 sends. This file is NOT consumed by the deploy script - it exists so the exact shape sent to the Purview Data Map REST API is reviewable in a diff without reading PowerShell. See README.md Section 11 for the VERIFY status of the dataSource and trigger bodies (the scan body's shape is confirmed against Microsoft's own REST reference, API version 2023-09-01).",
  "dataSource": {
    "$comment": "PUT {endpoint}/scan/datasources/{DataSourceName}?api-version=2023-09-01",
    "kind": "AzureSqlDatabase",
    "properties": {
      "serverEndpoint": "<SqlServerName>.database.windows.net",
      "resourceName": "<SqlServerName>",
      "resourceGroup": "<ResourceGroupName>",
      "subscriptionId": "<SubscriptionId>",
      "location": "<Location>",
      "collection": {
        "referenceName": "<CollectionReferenceName>",
        "type": "CollectionReference"
      }
    }
  },
  "scan": {
    "$comment": "PUT {endpoint}/scan/datasources/{DataSourceName}/scans/{ScanName}?api-version=2023-09-01 - kind AzureSqlDatabaseMsi authenticates as the Purview account's own system-assigned managed identity; no credential object required.",
    "kind": "AzureSqlDatabaseMsi",
    "properties": {
      "databaseName": "<DatabaseName>",
      "serverEndpoint": "<SqlServerName>.database.windows.net",
      "collection": {
        "referenceName": "<CollectionReferenceName>",
        "type": "CollectionReference"
      },
      "scanRulesetName": "AzureSqlDatabase",
      "scanRulesetType": "System"
    }
  },
  "trigger": {
    "$comment": "PUT {endpoint}/scan/datasources/{DataSourceName}/scans/{ScanName}/triggers/default?api-version=2023-09-01 - only sent when -RecurrenceFrequency is supplied. Trigger resource name is always 'default' (one trigger per scan).",
    "properties": {
      "scanLevel": "Incremental",
      "recurrence": {
        "frequency": "Week",
        "interval": 1,
        "startTime": "<RecurrenceStartTime, ISO 8601>"
      }
    }
  },
  "runScan": {
    "$comment": "PUT {endpoint}/scan/datasources/{DataSourceName}/scans/{ScanName}/runs/{new-guid}?api-version=2023-09-01&scanLevel=Full - only sent when -RunNow is supplied. No request body.",
    "scanLevel": "Full"
  }
}
```

#### `Remove-AzureSqlDataMapScan.ps1`

```powershell
#Requires -Version 7.0
<#
.SYNOPSIS
    Removes the scan (and its trigger, if any) created by New-AzureSqlDataMapScan.ps1, and
    optionally the data source registration itself.

.DESCRIPTION
    Calls the Microsoft Purview Data Map / Scanning REST API to delete, in order:
      1. The recurring trigger (if present) - DELETE .../scans/{scanName}/triggers/default
      2. The scan object - DELETE .../datasources/{dataSourceName}/scans/{scanName}
      3. (only with -RemoveDataSource) the data source registration itself -
         DELETE .../datasources/{dataSourceName}

    Deleting a scan or data source does NOT delete assets already ingested into the catalog from
    previous scan runs (Microsoft Learn: register-scan-azure-sql-database - "Deleting your scan
    does not delete catalog assets created from previous scans"). This script only removes the
    scanning configuration; it never deletes catalog data.

    Idempotent: deleting an object that doesn't exist (already removed) is treated as success, not
    an error, so this script is safe to re-run.

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
    Name of the data source object (matches -DataSourceName used at deploy time, or
    "<SqlServerName>-<DatabaseName>" if it was left to default).

.PARAMETER ScanName
    Name of the scan object. Defaults to "<DataSourceName>-scan" to match the deploy script's default.

.PARAMETER RemoveDataSource
    If supplied, also deletes the data source registration after the scan is removed. Omit to keep
    the source registered (e.g. so a differently configured scan can be added later) while removing
    only this scenario's scan/trigger.

.PARAMETER ApiVersion
    Data Map REST API version to pin. Defaults to '2023-09-01' to match the deploy script.

.PARAMETER WhatIf
    Standard PowerShell ShouldProcess dry-run. Reports every REST call that would be made without
    sending any mutating (DELETE) request.

.EXAMPLE
    ./Remove-AzureSqlDataMapScan.ps1 -PurviewAccountName 'contoso-purview' -TenantId $TenantId `
        -AppId $AppId -ClientSecret $ClientSecret -DataSourceName 'sql-contoso-prod-customerdb' -WhatIf

    Dry-run: shows exactly which DELETE calls would be made, changes nothing.

.EXAMPLE
    ./Remove-AzureSqlDataMapScan.ps1 -PurviewAccountName 'contoso-purview' -TenantId $TenantId `
        -AppId $AppId -ClientSecret $ClientSecret -DataSourceName 'sql-contoso-prod-customerdb' `
        -RemoveDataSource

    Removes the trigger, the scan, and the data source registration itself.

.NOTES
    See New-AzureSqlDataMapScan.ps1's .NOTES for the same VERIFY caveat on the exact REST shapes
    for the Triggers and Data Sources endpoints (this script's Scan delete call is the one
    confirmed against Microsoft's own REST reference, matching the create-or-replace path).

    Sources (Microsoft Learn, verify before production use):
    - Discover and govern Azure SQL Database - "Manage a scan" (deleting a scan does not delete
      catalog assets): https://learn.microsoft.com/purview/register-scan-azure-sql-database
    - Remove-AzPurviewDataSource / Remove-AzPurviewScan (Az.Purview module - confirms the delete
      operation exists per object type, corroborating this script's DELETE call shape):
      https://learn.microsoft.com/powershell/module/az.purview/remove-azpurviewdatasource
      https://learn.microsoft.com/powershell/module/az.purview/remove-azpurviewscan
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
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
    [switch]$RemoveDataSource,

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

function Invoke-PurviewDelete {
    param(
        [Parameter(Mandatory)][string]$Uri,
        [Parameter(Mandatory)][string]$Token,
        [Parameter(Mandatory)][string]$Description
    )
    if (-not $PSCmdlet.ShouldProcess($Description, "DELETE $Uri")) {
        Write-Verbose "WhatIf: would DELETE $Uri"
        return
    }
    try {
        Invoke-RestMethod -Method Delete -Uri $Uri -Headers @{ Authorization = "Bearer $Token" } | Out-Null
        Write-Host "Removed: $Description" -ForegroundColor Green
    }
    catch {
        if ($_.Exception.Response -and $_.Exception.Response.StatusCode -eq 404) {
            Write-Host "Already absent (no-op): $Description" -ForegroundColor Yellow
        }
        else {
            throw
        }
    }
}

$token = Get-PurviewAccessToken -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret

# --- Step 1: remove the recurring trigger, if any ---
$triggerUri = "$endpoint/scan/datasources/$DataSourceName/scans/$ScanName/triggers/default?api-version=$ApiVersion"
Invoke-PurviewDelete -Uri $triggerUri -Token $token -Description "Trigger on scan '$ScanName'"

# --- Step 2: remove the scan ---
$scanUri = "$endpoint/scan/datasources/$DataSourceName/scans/$ScanName?api-version=$ApiVersion"
Invoke-PurviewDelete -Uri $scanUri -Token $token -Description "Scan '$ScanName' on data source '$DataSourceName'"

# --- Step 3 (optional): remove the data source registration ---
if ($RemoveDataSource) {
    $dataSourceUri = "$endpoint/scan/datasources/$DataSourceName?api-version=$ApiVersion"
    Invoke-PurviewDelete -Uri $dataSourceUri -Token $token -Description "Data source '$DataSourceName'"
}
else {
    Write-Host "Data source '$DataSourceName' left registered (pass -RemoveDataSource to remove it too)." -ForegroundColor Yellow
}

Write-Host "`nDone. Catalog assets already ingested from prior scan runs are not deleted by this script - see rollback.md." -ForegroundColor Cyan
```