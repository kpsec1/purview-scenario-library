---
part: "deploy"
parent: "data-map/scan-azure-sql-managed-instance-and-classify"
---
The scripts and configuration below deploy this scenario. Review them, then run in order — each is designed to be idempotent and has a matching rollback.


#### `New-AzureSqlManagedInstanceDataMapScan.ps1`

```powershell
#Requires -Version 7.0
<#
.SYNOPSIS
    Registers an Azure SQL Managed Instance as a Microsoft Purview Data Map source and configures
    a SAMI-authenticated scan against it, optionally with a recurring trigger and/or an immediate run.

.DESCRIPTION
    Calls the Microsoft Purview Data Map / Scanning REST API (automation surface 4 per
    docs/automation-surface.md) to:
      1. Create or replace the AzureSqlDatabaseManagedInstance data source object.
      2. Create or replace an AzureSqlDatabaseManagedInstanceMsi scan object (authenticates as the
         Purview account's own system-assigned managed identity - no credential object to manage).
      3. Optionally create or replace a recurring trigger (-RecurrenceFrequency).
      4. Optionally start an immediate scan run (-RunNow).

    Sibling of scenarios/data-map/scan-azure-sql-and-classify/ - same object model and the same
    create-or-replace idempotency contract, but Azure SQL Managed Instance is a genuinely different
    Purview data source `kind` with its own registration/authentication nuances (see design.md):
      - The server endpoint is the instance's PUBLIC endpoint FQDN,PORT pair in the literal form
        "tcp:<fqdn>,<port>" - not a bare hostname like the logical-server AzureSqlDatabase scenario.
      - The scan `kind` is AzureSqlDatabaseManagedInstanceMsi (a distinct enum member from
        AzureSqlDatabaseMsi) and its default system scan rule set is named
        "AzureSqlDatabaseManagedInstance", not "AzureSqlDatabase".
      - The instance's own managed identity needs the Microsoft Entra "Directory Readers" role (or
        the equivalent fine-grained Microsoft Graph permissions) before Microsoft Entra
        authentication works at all - a prerequisite the single-database scenario does not have.

    Idempotent by construction: every mutating call in this script is a REST PUT against a
    create-or-replace endpoint, all four confirmed by direct fetch of Microsoft's own canonical REST
    reference during this build (Data Sources, Scans, Triggers, Scan Result - Run Scan - see .NOTES).
    Re-running this script with the same parameters reconciles the objects to the script's current
    definition rather than erroring or duplicating.

    This script does NOT create the out-of-band grants the SAMI-authenticated scan depends on:
      - Microsoft Entra admin set on the managed instance itself (Set-AzSqlInstanceActiveDirectoryAdministrator)
      - "Directory Readers" Microsoft Entra role (or fine-grained Graph permissions) for the
        instance's managed identity - MI-specific; the single-database scenario does not need this
      - Azure IAM "Reader" role for the Purview account on the managed instance resource
      - db_datareader for the Purview account as a Microsoft Entra external-provider database user
        (CREATE USER [<PurviewAccountName>] FROM EXTERNAL PROVIDER;)
      - Public endpoint enabled on the managed instance, and the NSG inbound rule allowing the
        AzureCloud service tag over the ports the instance's connection type requires
    All are one-time, ARM/Entra/SQL-side prerequisites documented in README.md Sections 3 and 5 -
    grant them before running this script, or the scan will register successfully but fail on its
    first run.

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

.PARAMETER SubscriptionId
    Azure subscription ID containing the target Azure SQL Managed Instance.

.PARAMETER ResourceGroupName
    Resource group containing the target Azure SQL Managed Instance.

.PARAMETER InstanceName
    Name of the Azure SQL Managed Instance resource (the `resourceName`, not the public endpoint FQDN).

.PARAMETER PublicEndpointFqdn
    The managed instance's PUBLIC endpoint fully qualified domain name, e.g.
    "mi-contoso.public.ac1b2c3d4e5f.database.windows.net" - shown in the Azure portal on the
    instance's Overview pane, or via `Get-AzSqlInstance` (the `publicEndpointFqdn`/`fullyQualifiedDomainName`
    property, depending on API surface). Required: this scenario defaults to the public-endpoint,
    SAMI-authenticated path (README.md Section 11 covers the private-endpoint alternative).

.PARAMETER DatabaseName
    Name of the database on the managed instance to scan.

.PARAMETER Location
    Azure region of the managed instance (e.g. 'eastus').

.PARAMETER CollectionReferenceName
    The Data Map collection's 5-character reference ID (NOT its friendly name) - read it from the
    collection's URL in the Purview portal, or the List Collections REST API. See README.md Section 6.

.PARAMETER DataSourceName
    Name for the registered data source object. Defaults to "<InstanceName>-<DatabaseName>".

.PARAMETER ScanName
    Name for the scan object. Defaults to "<DataSourceName>-scan".

.PARAMETER Port
    TCP port on the public endpoint. Defaults to 3342 (the managed instance public-endpoint port
    Microsoft's own worked registration example uses). Confirm against the instance's actual
    connection-policy configuration - see README.md Section 6.

.PARAMETER ScanRulesetName
    Scan rule set to use. Defaults to 'AzureSqlDatabaseManagedInstance' (Microsoft's system default
    for this source type). Pass a custom rule set's name if one already exists in this collection
    (this script does not create custom rule sets).

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
    If supplied, starts an immediate scan run after the data source and scan objects are
    created/updated.

.PARAMETER ApiVersion
    Data Map REST API version to pin. Defaults to '2023-09-01', directly confirmed current for all
    four REST calls this script makes (Data Sources, Scans, Triggers, Scan Result - Run Scan) via a
    direct fetch of each operation's own canonical Microsoft Learn REST reference page during this
    build - see .NOTES.

.PARAMETER WhatIf
    Standard PowerShell ShouldProcess dry-run. Reports every REST call that would be made without
    sending any mutating request. Invoke-RestMethod has no native ShouldProcess integration, so this
    script wraps each mutating call in its own $PSCmdlet.ShouldProcess() check.

.EXAMPLE
    ./New-AzureSqlManagedInstanceDataMapScan.ps1 -PurviewAccountName 'contoso-purview' -TenantId $TenantId `
        -AppId $AppId -ClientSecret $ClientSecret -SubscriptionId $SubscriptionId `
        -ResourceGroupName 'rg-contoso-data' -InstanceName 'mi-contoso-prod' `
        -PublicEndpointFqdn 'mi-contoso-prod.public.ac1b2c3d4e5f.database.windows.net' `
        -DatabaseName 'customerdb' -Location 'eastus' -CollectionReferenceName 'a1b2c' -WhatIf

    Dry-run: shows exactly which REST calls would be made, changes nothing.

.EXAMPLE
    ./New-AzureSqlManagedInstanceDataMapScan.ps1 -PurviewAccountName 'contoso-purview' -TenantId $TenantId `
        -AppId $AppId -ClientSecret $ClientSecret -SubscriptionId $SubscriptionId `
        -ResourceGroupName 'rg-contoso-data' -InstanceName 'mi-contoso-prod' `
        -PublicEndpointFqdn 'mi-contoso-prod.public.ac1b2c3d4e5f.database.windows.net' `
        -DatabaseName 'customerdb' -Location 'eastus' -CollectionReferenceName 'a1b2c' `
        -RecurrenceFrequency Week -RunNow

    Registers the source, configures the scan, adds a weekly trigger, and kicks off an immediate
    full scan.

.NOTES
    All four REST operations this script and Remove-AzureSqlManagedInstanceDataMapScan.ps1 call were
    directly fetched from Microsoft's own canonical REST reference during this build (a stronger
    grounding bar than the sibling scan-azure-sql-and-classify scenario achieved, whose Data
    Sources/Triggers/Run-Scan endpoints returned fetch errors at build time and were reconstructed
    from SDK types and PowerShell parameter signatures instead - see that scenario's README.md
    Section 11). Two real discrepancies from that sibling scenario's reconstructed shapes were found
    and corrected here:
      - Scan Result - Run Scan is `POST {endpoint}/scan/datasources/{ds}/scans/{scan}:run?
        runId={guid}&scanLevel={level}&api-version=...` (an action-style POST with a colon suffix),
        not a resource-style `PUT .../runs/{runId}` as the sibling scenario's script sends.
      - Scan Result - List Scan History's per-run asset counts are nested under
        `discoveryExecutionDetails.statistics.assets.discovered`/`.classified`, not flat
        `.assetsDiscovered`/`.assetsClassified` properties on the run object.
    See PROGRESS.md for the follow-up to port both corrections back into the sibling scenario.

    Sources (Microsoft Learn, verify before production use):
    - Data Sources - Create Or Replace (API version 2023-09-01, confirmed AzureSqlDatabaseManagedInstance
      body schema): https://learn.microsoft.com/rest/api/purview/scanningdataplane/data-sources/create-or-replace
    - Scans - Create Or Replace (confirmed AzureSqlDatabaseManagedInstanceMsi body schema):
      https://learn.microsoft.com/rest/api/purview/scanningdataplane/scans/create-or-replace
    - Triggers - Create Or Replace (confirmed body schema, worked example):
      https://learn.microsoft.com/rest/api/purview/scanningdataplane/triggers/create-or-replace
    - Scan Result - Run Scan (confirmed the POST .../:run?runId=... shape):
      https://learn.microsoft.com/rest/api/purview/scanningdataplane/scan-result/run-scan
    - Scan Result - List Scan History (confirmed the nested discoveryExecutionDetails.statistics shape):
      https://learn.microsoft.com/rest/api/purview/scanningdataplane/scan-result/list-scan-history
    - Connect to and manage an Azure SQL Managed Instance in Microsoft Purview (registration, public
      endpoint, SAMI authentication, T-SQL grants, Directory Readers requirement):
      https://learn.microsoft.com/purview/register-scan-azure-sql-managed-instance
    - New-AzPurviewAzureSqlDatabaseManagedInstanceDataSourceObject / -MsiScanObject (Az.Purview
      module - confirms ServerEndpoint's "tcp:<fqdn>,<port>" worked-example format):
      https://learn.microsoft.com/powershell/module/az.purview/new-azpurviewazuresqldatabasemanagedinstancedatasourceobject
      https://learn.microsoft.com/powershell/module/az.purview/new-azpurviewazuresqldatabasemanagedinstancemsiscanobject
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
    [string]$InstanceName,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$PublicEndpointFqdn,

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
    [ValidateRange(1, 65535)]
    [int]$Port = 3342,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$ScanRulesetName = 'AzureSqlDatabaseManagedInstance',

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

if (-not $DataSourceName) { $DataSourceName = "$InstanceName-$DatabaseName" }
if (-not $ScanName) { $ScanName = "$DataSourceName-scan" }

$endpoint = "https://$PurviewAccountName.purview.azure.com"
$serverEndpoint = "tcp:$PublicEndpointFqdn,$Port"
$collectionRef = @{ referenceName = $CollectionReferenceName; type = 'CollectionReference' }

function Get-PurviewAccessToken {
    <#
        Client-credentials OAuth2 flow against the Data Map data-plane resource, per
        docs/automation-surface.md Section 3.
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
    kind       = 'AzureSqlDatabaseManagedInstance'
    properties = @{
        serverEndpoint = $serverEndpoint
        resourceName   = $InstanceName
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
    kind       = 'AzureSqlDatabaseManagedInstanceMsi'
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
Write-Host "Scan '$ScanName' created/updated (kind: AzureSqlDatabaseManagedInstanceMsi, ruleset: $ScanRulesetName [$ScanRulesetType])." -ForegroundColor Green

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
    # query parameter - NOT a resource-style PUT to .../runs/{runId}.
    $runUri = "$endpoint/scan/datasources/$DataSourceName/scans/${ScanName}:run?runId=$runId&scanLevel=$ScanLevel&api-version=$ApiVersion"
    if ($PSCmdlet.ShouldProcess("Scan '$ScanName'", "Start immediate $ScanLevel run (runId $runId)")) {
        Invoke-RestMethod -Method Post -Uri $runUri -Headers @{ Authorization = "Bearer $token" } | Out-Null
        Write-Host "Scan run started (runId: $runId). Poll validate/Test-AzureSqlManagedInstanceDataMapScan.ps1 for status - a first full scan of a nontrivial database can take from minutes to hours." -ForegroundColor Cyan
    }
    else {
        Write-Verbose "WhatIf: would POST $runUri to start an immediate $ScanLevel run."
    }
}

Write-Host "`nDone. Remember: the SAMI-authenticated scan will fail at run time unless the Microsoft Entra admin, Directory Readers role, Azure IAM Reader grant, and SQL db_datareader grant documented in README.md Sections 3 and 5 are already in place." -ForegroundColor Cyan
```

#### `policy/azure-sql-mi-datamap-scan.json`

```json
{
  "$comment": "Reference/documentation copy of the REST request bodies deploy/New-AzureSqlManagedInstanceDataMapScan.ps1 sends. This file is NOT consumed by the deploy script - it exists so the exact shape sent to the Purview Data Map REST API is reviewable in a diff without reading PowerShell. All four bodies below are confirmed against Microsoft's own canonical REST reference (API version 2023-09-01) - see README.md Section 11 and the deploy script's .NOTES for the two shapes that turned out to differ from the sibling scan-azure-sql-and-classify scenario's own (unconfirmed-at-the-time) assumptions.",
  "dataSource": {
    "$comment": "PUT {endpoint}/scan/datasources/{DataSourceName}?api-version=2023-09-01 - kind AzureSqlDatabaseManagedInstance (a distinct enum member from AzureSqlDatabase). serverEndpoint uses the literal 'tcp:<fqdn>,<port>' form, not a bare hostname.",
    "kind": "AzureSqlDatabaseManagedInstance",
    "properties": {
      "serverEndpoint": "tcp:<InstanceName>.public.<dns-zone>.database.windows.net,<Port>",
      "resourceName": "<InstanceName>",
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
    "$comment": "PUT {endpoint}/scan/datasources/{DataSourceName}/scans/{ScanName}?api-version=2023-09-01 - kind AzureSqlDatabaseManagedInstanceMsi authenticates as the Purview account's own system-assigned managed identity; no credential object required. scanRulesetName's system default for this source type is 'AzureSqlDatabaseManagedInstance', not 'AzureSqlDatabase'.",
    "kind": "AzureSqlDatabaseManagedInstanceMsi",
    "properties": {
      "databaseName": "<DatabaseName>",
      "serverEndpoint": "tcp:<InstanceName>.public.<dns-zone>.database.windows.net,<Port>",
      "collection": {
        "referenceName": "<CollectionReferenceName>",
        "type": "CollectionReference"
      },
      "scanRulesetName": "AzureSqlDatabaseManagedInstance",
      "scanRulesetType": "System"
    }
  },
  "trigger": {
    "$comment": "PUT {endpoint}/scan/datasources/{DataSourceName}/scans/{ScanName}/triggers/default?api-version=2023-09-01 - only sent when -RecurrenceFrequency is supplied. Trigger resource name is always 'default' (one trigger per scan). Confirmed against Microsoft's own worked Triggers - Create Or Replace example.",
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
    "$comment": "POST {endpoint}/scan/datasources/{DataSourceName}/scans/{ScanName}:run?runId={new-guid}&scanLevel=Full&api-version=2023-09-01 - only sent when -RunNow is supplied. No request body. Action-style POST with a colon suffix and runId as a query parameter - confirmed against Microsoft's own Scan Result - Run Scan reference, which differs from the resource-style 'PUT .../runs/{runId}' the sibling scan-azure-sql-and-classify scenario's script sends.",
    "scanLevel": "Full"
  }
}
```

#### `Remove-AzureSqlManagedInstanceDataMapScan.ps1`

```powershell
#Requires -Version 7.0
<#
.SYNOPSIS
    Removes the scan (and its trigger, if any) created by New-AzureSqlManagedInstanceDataMapScan.ps1,
    and optionally the data source registration itself.

.DESCRIPTION
    Calls the Microsoft Purview Data Map / Scanning REST API to delete, in order:
      1. The recurring trigger (if present) - DELETE .../scans/{scanName}/triggers/default
      2. The scan object - DELETE .../datasources/{dataSourceName}/scans/{scanName}
      3. (only with -RemoveDataSource) the data source registration itself -
         DELETE .../datasources/{dataSourceName}

    Deleting a scan or data source does NOT delete assets already ingested into the catalog from
    previous scan runs (Microsoft Learn: register-scan-azure-sql-managed-instance - "Deleting your
    scan does not delete catalog assets created from previous scans"). This script only removes the
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
    "<InstanceName>-<DatabaseName>" if it was left to default).

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
    ./Remove-AzureSqlManagedInstanceDataMapScan.ps1 -PurviewAccountName 'contoso-purview' -TenantId $TenantId `
        -AppId $AppId -ClientSecret $ClientSecret -DataSourceName 'mi-contoso-prod-customerdb' -WhatIf

    Dry-run: shows exactly which DELETE calls would be made, changes nothing.

.EXAMPLE
    ./Remove-AzureSqlManagedInstanceDataMapScan.ps1 -PurviewAccountName 'contoso-purview' -TenantId $TenantId `
        -AppId $AppId -ClientSecret $ClientSecret -DataSourceName 'mi-contoso-prod-customerdb' `
        -RemoveDataSource

    Removes the trigger, the scan, and the data source registration itself.

.NOTES
    All three DELETE calls follow the same path pattern confirmed by direct fetch of the matching
    Create Or Replace REST reference pages (see New-AzureSqlManagedInstanceDataMapScan.ps1's
    .NOTES) - Microsoft's REST APIs consistently pair a resource's Create Or Replace and Delete
    operations on the same URI, and the Az.Purview module's Remove-AzPurviewDataSource /
    Remove-AzPurviewScan cmdlets corroborate that a delete operation exists per object type.

    Sources (Microsoft Learn, verify before production use):
    - Connect to and manage an Azure SQL Managed Instance in Microsoft Purview - "Manage your
      scans" (deleting a scan does not delete catalog assets):
      https://learn.microsoft.com/purview/register-scan-azure-sql-managed-instance
    - Remove-AzPurviewDataSource / Remove-AzPurviewScan (Az.Purview module):
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