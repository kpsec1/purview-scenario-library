---
part: "deploy"
parent: "data-map/scan-azure-synapse-and-classify"
---
The scripts and configuration below deploy this scenario. Review them, then run in order — each is designed to be idempotent and has a matching rollback.


#### `New-AzureSynapseDataMapScan.ps1`

```powershell
#Requires -Version 7.0
<#
.SYNOPSIS
    Registers an Azure Synapse Analytics workspace as a Microsoft Purview Data Map source and
    configures a SAMI-authenticated scan against its dedicated and/or serverless SQL pools,
    optionally with a recurring trigger and/or an immediate run.

.DESCRIPTION
    Calls the Microsoft Purview Data Map / Scanning REST API (automation surface 4 per
    docs/automation-surface.md) to:
      1. Create or replace the AzureSynapseWorkspace data source object - ONE object per workspace,
         carrying the dedicated and/or serverless SQL endpoints as two optional properties (not one
         data source per pool).
      2. Create or replace an AzureSynapseWorkspaceMsi scan object (authenticates as the Purview
         account's own system-assigned managed identity - no credential object to manage).
      3. Optionally create or replace a recurring trigger (-RecurrenceFrequency).
      4. Optionally start an immediate scan run (-RunNow).

    Third sibling of scenarios/data-map/scan-azure-sql-and-classify/ and
    scenarios/data-map/scan-azure-sql-managed-instance-and-classify/ - same object model and the same
    create-or-replace idempotency contract, but Azure Synapse Analytics is a genuinely different
    Purview data source `kind` with its own registration/authentication nuances (see design.md):
      - Registration is per WORKSPACE, not per database - dedicatedSqlEndpoint and
        serverlessSqlEndpoint are two optional properties on the same data source object.
      - The scan `kind` is AzureSynapseWorkspaceMsi and its system scan rule set is named
        "AzureSynapseSQL" - distinct enum values from both sibling scenarios.
      - Serverless SQL pools need a THREE-part enumeration-authentication grant (workspace Reader +
        storage account Storage Blob Data Reader + a per-database CREATE LOGIN) that neither sibling
        scenario needs; dedicated SQL pools need only the workspace-level Reader grant, like the
        siblings.
      - If the workspace's "Allow Azure services and resources to access this workspace" firewall
        control cannot be enabled, Microsoft's own documentation states the PORTAL cannot configure a
        Synapse scan at all, and the REST-API fallback requires SQL Auth (not MSI) - a materially
        different story from either sibling scenario. This script assumes the firewall control is
        enabled (the default, MSI-authenticated path); see README.md Section 11 for the fallback.

    Idempotent by construction: every mutating call in this script is a REST PUT against a
    create-or-replace endpoint (the same generic Data Sources/Scans/Triggers/Scan Result shapes the
    scan-azure-sql-managed-instance-and-classify sibling scenario already confirmed by direct fetch of
    Microsoft's own canonical REST reference - see .NOTES). Re-running this script with the same
    parameters reconciles the objects to the script's current definition rather than erroring or
    duplicating.

    This script does NOT create the out-of-band grants the SAMI-authenticated scan depends on:
      - Azure IAM "Reader" role for the Purview account (its MSI) on the Synapse workspace resource
        (required for BOTH dedicated and serverless scanning)
      - Azure IAM "Storage blob data reader" role for the Purview account (its MSI) on the resource
        group/subscription holding the workspace's associated storage account (SERVERLESS ONLY)
      - Per-serverless-database enumeration login: CREATE LOGIN [<PurviewAccountName>] FROM EXTERNAL
        PROVIDER; (SERVERLESS ONLY, run once per serverless database before the db_datareader grant)
      - Per-dedicated-database read grant: CREATE USER [<PurviewAccountName>] FROM EXTERNAL PROVIDER
        + EXEC sp_addrolemember 'db_datareader', [<PurviewAccountName>]
      - Per-serverless-database read grant: CREATE USER [<PurviewAccountName>] FOR LOGIN
        [<PurviewAccountName>]; ALTER ROLE db_datareader ADD MEMBER [<PurviewAccountName>];
      - (conditional) external-table scoped-credential grant: GRANT REFERENCES ON DATABASE SCOPED
        CREDENTIAL::[scoped_credential] TO [<PurviewAccountName>];
      - "Allow Azure services and resources to access this workspace" = On, in the workspace's
        Firewalls pane
    All are one-time, ARM/SQL-side prerequisites documented in README.md Sections 3 and 5 - grant them
    before running this script, or the scan will register successfully but fail on its first run.

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
    Azure subscription ID containing the target Azure Synapse Analytics workspace.

.PARAMETER ResourceGroupName
    Resource group containing the target Azure Synapse Analytics workspace.

.PARAMETER WorkspaceName
    Name of the Azure Synapse Analytics workspace resource (the `resourceName`).

.PARAMETER DedicatedSqlEndpoint
    The workspace's dedicated SQL pool endpoint, e.g. "ws-contoso.sql.azuresynapse.net" (shown in the
    Azure portal on the workspace's Overview pane). Omit if this workspace has no dedicated SQL pool
    you want scanned. At least one of -DedicatedSqlEndpoint / -ServerlessSqlEndpoint is required.

.PARAMETER ServerlessSqlEndpoint
    The workspace's built-in serverless SQL pool endpoint, e.g.
    "ws-contoso-ondemand.sql.azuresynapse.net". Omit if you don't want the serverless pool scanned.
    At least one of -DedicatedSqlEndpoint / -ServerlessSqlEndpoint is required.

.PARAMETER Location
    Azure region of the workspace (e.g. 'eastus').

.PARAMETER CollectionReferenceName
    The Data Map collection's 5-character reference ID (NOT its friendly name) - read it from the
    collection's URL in the Purview portal, or the List Collections REST API. See README.md Section 6.

.PARAMETER DataSourceName
    Name for the registered data source object. Defaults to "<WorkspaceName>".

.PARAMETER ScanName
    Name for the scan object. Defaults to "<DataSourceName>-scan".

.PARAMETER ScanRulesetName
    Scan rule set to use. Defaults to 'AzureSynapseSQL' (Microsoft's system default for this source
    type). Pass a custom rule set's name if one already exists in this collection (this script does
    not create custom rule sets).

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
    Data Map REST API version to pin. Defaults to '2023-09-01' - the same version both sibling
    scenarios pin, confirmed current for the generic Data Sources/Scans/Triggers/Scan Result call
    shapes this script reuses unchanged (see .NOTES).

.PARAMETER WhatIf
    Standard PowerShell ShouldProcess dry-run. Reports every REST call that would be made without
    sending any mutating request. Invoke-RestMethod has no native ShouldProcess integration, so this
    script wraps each mutating call in its own $PSCmdlet.ShouldProcess() check.

.EXAMPLE
    ./New-AzureSynapseDataMapScan.ps1 -PurviewAccountName 'contoso-purview' -TenantId $TenantId `
        -AppId $AppId -ClientSecret $ClientSecret -SubscriptionId $SubscriptionId `
        -ResourceGroupName 'rg-contoso-data' -WorkspaceName 'ws-contoso-prod' `
        -DedicatedSqlEndpoint 'ws-contoso-prod.sql.azuresynapse.net' `
        -ServerlessSqlEndpoint 'ws-contoso-prod-ondemand.sql.azuresynapse.net' `
        -Location 'eastus' -CollectionReferenceName 'a1b2c' -WhatIf

    Dry-run: shows exactly which REST calls would be made, changes nothing.

.EXAMPLE
    ./New-AzureSynapseDataMapScan.ps1 -PurviewAccountName 'contoso-purview' -TenantId $TenantId `
        -AppId $AppId -ClientSecret $ClientSecret -SubscriptionId $SubscriptionId `
        -ResourceGroupName 'rg-contoso-data' -WorkspaceName 'ws-contoso-prod' `
        -DedicatedSqlEndpoint 'ws-contoso-prod.sql.azuresynapse.net' `
        -ServerlessSqlEndpoint 'ws-contoso-prod-ondemand.sql.azuresynapse.net' `
        -Location 'eastus' -CollectionReferenceName 'a1b2c' `
        -RecurrenceFrequency Week -RunNow

    Registers the workspace (both pool types), configures the scan, adds a weekly trigger, and kicks
    off an immediate full scan.

.EXAMPLE
    ./New-AzureSynapseDataMapScan.ps1 -PurviewAccountName 'contoso-purview' -TenantId $TenantId `
        -AppId $AppId -ClientSecret $ClientSecret -SubscriptionId $SubscriptionId `
        -ResourceGroupName 'rg-contoso-data' -WorkspaceName 'ws-contoso-prod' `
        -ServerlessSqlEndpoint 'ws-contoso-prod-ondemand.sql.azuresynapse.net' `
        -Location 'eastus' -CollectionReferenceName 'a1b2c'

    Registers only the serverless SQL pool (no dedicated pool in this workspace).

.NOTES
    The generic Data Sources / Scans / Triggers / Scan Result - Run Scan REST call shapes this script
    sends were already confirmed by direct fetch of Microsoft's own canonical REST reference during
    the scan-azure-sql-managed-instance-and-classify sibling scenario's build (they are generic to
    every data source `kind` - only the request BODY differs). This build's own grounding effort
    focused on what's Synapse-specific: the `kind` names and body property names for the data source
    and scan objects, confirmed via the Az.Purview PowerShell module's own worked examples (fetched via
    GitHub raw source after direct learn.microsoft.com fetches returned EGRESS_BLOCKED in this build
    environment), and the full registration/scan/permissions workflow, confirmed via a verified
    byte-for-byte mirror of Microsoft's own register-scan-synapse-workspace article. See design.md
    Section 5 for the full grounding method and PROGRESS.md for this scenario's build record.

    One property is deliberately NOT sent: the scan object's optional `resourceTypes` field. No
    authoritative worked example of its exact JSON shape was found during this build, and the Purview
    portal's own scan wizard exposes only a single "SQL Database" Type for this source (no
    dedicated-vs-serverless toggle to encode) - weak evidence the property may not be required for the
    common case. Omitting it is safer than guessing a shape that could silently mis-scope the scan.
    Flagged as an explicit VERIFY in README.md Section 11.

    Sources (Microsoft Learn, verify before production use):
    - Connect to and manage Azure Synapse Analytics workspaces in Microsoft Purview (registration,
      enumeration/scan authentication for dedicated and serverless SQL, firewall requirement, scan
      wizard "Type" behavior): https://learn.microsoft.com/purview/register-scan-synapse-workspace
    - New-AzPurviewAzureSynapseWorkspaceDataSourceObject (Az.Purview module - confirms
      dedicatedSqlEndpoint/serverlessSqlEndpoint property names via its own worked example):
      https://learn.microsoft.com/powershell/module/az.purview/new-azpurviewazuresynapseworkspacedatasourceobject
    - New-AzPurviewAzureSynapseWorkspaceMsiScanObject (Az.Purview module - confirms
      ScanRulesetName 'AzureSynapseSQL' via its own worked example):
      https://learn.microsoft.com/powershell/module/az.purview/new-azpurviewazuresynapseworkspacemsiscanobject
    - Data Sources - Create Or Replace / Scans - Create Or Replace / Triggers - Create Or Replace /
      Scan Result - Run Scan (API version 2023-09-01, generic call shapes reused unchanged from the
      scan-azure-sql-managed-instance-and-classify sibling scenario's own direct-fetch confirmation):
      https://learn.microsoft.com/rest/api/purview/scanningdataplane/data-sources/create-or-replace
      https://learn.microsoft.com/rest/api/purview/scanningdataplane/scans/create-or-replace
      https://learn.microsoft.com/rest/api/purview/scanningdataplane/triggers/create-or-replace
      https://learn.microsoft.com/rest/api/purview/scanningdataplane/scan-result/run-scan
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
    [string]$WorkspaceName,

    [Parameter()]
    [string]$DedicatedSqlEndpoint,

    [Parameter()]
    [string]$ServerlessSqlEndpoint,

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
    [string]$ScanRulesetName = 'AzureSynapseSQL',

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

if (-not $DedicatedSqlEndpoint -and -not $ServerlessSqlEndpoint) {
    throw "At least one of -DedicatedSqlEndpoint or -ServerlessSqlEndpoint must be supplied - a Synapse workspace data source with neither endpoint has nothing to scan."
}

if (-not $DataSourceName) { $DataSourceName = $WorkspaceName }
if (-not $ScanName) { $ScanName = "$DataSourceName-scan" }

$endpoint = "https://$PurviewAccountName.purview.azure.com"
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

# --- Step 1: register (or reconcile) the data source - one object per WORKSPACE ---
$dataSourceProperties = @{
    resourceName   = $WorkspaceName
    resourceGroup  = $ResourceGroupName
    subscriptionId = $SubscriptionId
    location       = $Location
    collection     = $collectionRef
}
if ($DedicatedSqlEndpoint) { $dataSourceProperties['dedicatedSqlEndpoint'] = $DedicatedSqlEndpoint }
if ($ServerlessSqlEndpoint) { $dataSourceProperties['serverlessSqlEndpoint'] = $ServerlessSqlEndpoint }

$dataSourceUri = "$endpoint/scan/datasources/$DataSourceName?api-version=$ApiVersion"
$dataSourceBody = @{
    kind       = 'AzureSynapseWorkspace'
    properties = $dataSourceProperties
}
Invoke-PurviewPut -Uri $dataSourceUri -Body $dataSourceBody -Token $token `
    -Description "Data source '$DataSourceName' (workspace '$WorkspaceName')" | Out-Null
$scannedPools = @(if ($DedicatedSqlEndpoint) { 'dedicated' }; if ($ServerlessSqlEndpoint) { 'serverless' }) -join ' + '
Write-Host "Data source '$DataSourceName' created/updated ($scannedPools SQL pool endpoint(s))." -ForegroundColor Green

# --- Step 2: create (or reconcile) the scan, authenticating as the Purview account's SAMI ---
# NOTE: resourceTypes is deliberately omitted - see .NOTES and README.md Section 11.
$scanUri = "$endpoint/scan/datasources/$DataSourceName/scans/$ScanName?api-version=$ApiVersion"
$scanBody = @{
    kind       = 'AzureSynapseWorkspaceMsi'
    properties = @{
        collection      = $collectionRef
        scanRulesetName = $ScanRulesetName
        scanRulesetType = $ScanRulesetType
    }
}
Invoke-PurviewPut -Uri $scanUri -Body $scanBody -Token $token `
    -Description "Scan '$ScanName' on data source '$DataSourceName'" | Out-Null
Write-Host "Scan '$ScanName' created/updated (kind: AzureSynapseWorkspaceMsi, ruleset: $ScanRulesetName [$ScanRulesetType])." -ForegroundColor Green

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
    # Action-style POST with a colon suffix and runId as a query parameter - the confirmed shape from
    # the scan-azure-sql-managed-instance-and-classify sibling scenario's own direct-fetch grounding.
    $runUri = "$endpoint/scan/datasources/$DataSourceName/scans/${ScanName}:run?runId=$runId&scanLevel=$ScanLevel&api-version=$ApiVersion"
    if ($PSCmdlet.ShouldProcess("Scan '$ScanName'", "Start immediate $ScanLevel run (runId $runId)")) {
        Invoke-RestMethod -Method Post -Uri $runUri -Headers @{ Authorization = "Bearer $token" } | Out-Null
        Write-Host "Scan run started (runId: $runId). Poll validate/Test-AzureSynapseDataMapScan.ps1 for status - a first full scan of a nontrivial workspace can take from minutes to hours." -ForegroundColor Cyan
    }
    else {
        Write-Verbose "WhatIf: would POST $runUri to start an immediate $ScanLevel run."
    }
}

Write-Host "`nDone. Remember: the SAMI-authenticated scan will fail at run time unless the workspace Reader grant, (serverless-only) Storage Blob Data Reader grant, per-database enumeration/read grants, and workspace firewall setting documented in README.md Sections 3 and 5 are already in place." -ForegroundColor Cyan
```

#### `policy/azure-synapse-datamap-scan.json`

```json
{
  "$comment": "Reference/documentation copy of the REST request bodies deploy/New-AzureSynapseDataMapScan.ps1 sends. This file is NOT consumed by the deploy script - it exists so the exact shape sent to the Purview Data Map REST API is reviewable in a diff without reading PowerShell. dataSource/scan kind names and property names confirmed via the Az.Purview PowerShell module's own worked examples (New-AzPurviewAzureSynapseWorkspaceDataSourceObject / New-AzPurviewAzureSynapseWorkspaceMsiScanObject) - see README.md Section 11 and design.md Section 5 for the full grounding method, including the one field (resourceTypes) deliberately omitted rather than guessed.",
  "dataSource": {
    "$comment": "PUT {endpoint}/scan/datasources/{DataSourceName}?api-version=2023-09-01 - kind AzureSynapseWorkspace. ONE data source object per WORKSPACE (not per pool) - dedicatedSqlEndpoint and serverlessSqlEndpoint are both optional properties on the same object; supply at least one.",
    "kind": "AzureSynapseWorkspace",
    "properties": {
      "dedicatedSqlEndpoint": "<WorkspaceName>.sql.azuresynapse.net",
      "serverlessSqlEndpoint": "<WorkspaceName>-ondemand.sql.azuresynapse.net",
      "resourceName": "<WorkspaceName>",
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
    "$comment": "PUT {endpoint}/scan/datasources/{DataSourceName}/scans/{ScanName}?api-version=2023-09-01 - kind AzureSynapseWorkspaceMsi authenticates as the Purview account's own system-assigned managed identity; no credential object required. scanRulesetName's system default for this source type is 'AzureSynapseSQL'. The optional 'resourceTypes' property (seen on the Az.Purview PowerShell object model as -ResourceType) is deliberately NOT included here - its exact JSON shape was not independently confirmed during this build, and the Purview portal's own scan wizard exposes only a single 'SQL Database' Type for this source with no dedicated/serverless split to encode. See README.md Section 11 (VERIFY).",
    "kind": "AzureSynapseWorkspaceMsi",
    "properties": {
      "collection": {
        "referenceName": "<CollectionReferenceName>",
        "type": "CollectionReference"
      },
      "scanRulesetName": "AzureSynapseSQL",
      "scanRulesetType": "System"
    }
  },
  "trigger": {
    "$comment": "PUT {endpoint}/scan/datasources/{DataSourceName}/scans/{ScanName}/triggers/default?api-version=2023-09-01 - only sent when -RecurrenceFrequency is supplied. Generic shape, unchanged from both sibling scenarios (Trigger resource name is always 'default').",
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
    "$comment": "POST {endpoint}/scan/datasources/{DataSourceName}/scans/{ScanName}:run?runId={new-guid}&scanLevel=Full&api-version=2023-09-01 - only sent when -RunNow is supplied. No request body. Generic action-style POST shape, unchanged from both sibling scenarios.",
    "scanLevel": "Full"
  }
}
```

#### `Remove-AzureSynapseDataMapScan.ps1`

```powershell
#Requires -Version 7.0
<#
.SYNOPSIS
    Removes the scan (and its trigger, if any) created by New-AzureSynapseDataMapScan.ps1,
    and optionally the data source registration itself.

.DESCRIPTION
    Calls the Microsoft Purview Data Map / Scanning REST API to delete, in order:
      1. The recurring trigger (if present) - DELETE .../scans/{scanName}/triggers/default
      2. The scan object - DELETE .../datasources/{dataSourceName}/scans/{scanName}
      3. (only with -RemoveDataSource) the data source registration itself -
         DELETE .../datasources/{dataSourceName}

    Deleting a scan or data source does NOT delete assets already ingested into the catalog from
    previous scan runs, the same documented behavior as both sibling scenarios' own Remove scripts.
    This script only removes the scanning configuration; it never deletes catalog data.

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
    Name of the data source object (matches -DataSourceName used at deploy time, or the workspace
    name if it was left to default).

.PARAMETER ScanName
    Name of the scan object. Defaults to "<DataSourceName>-scan" to match the deploy script's default.

.PARAMETER RemoveDataSource
    If supplied, also deletes the data source registration after the scan is removed. Omit to keep
    the workspace registered (e.g. so a differently configured scan can be added later) while removing
    only this scenario's scan/trigger.

.PARAMETER ApiVersion
    Data Map REST API version to pin. Defaults to '2023-09-01' to match the deploy script.

.PARAMETER WhatIf
    Standard PowerShell ShouldProcess dry-run. Reports every REST call that would be made without
    sending any mutating (DELETE) request.

.EXAMPLE
    ./Remove-AzureSynapseDataMapScan.ps1 -PurviewAccountName 'contoso-purview' -TenantId $TenantId `
        -AppId $AppId -ClientSecret $ClientSecret -DataSourceName 'ws-contoso-prod' -WhatIf

    Dry-run: shows exactly which DELETE calls would be made, changes nothing.

.EXAMPLE
    ./Remove-AzureSynapseDataMapScan.ps1 -PurviewAccountName 'contoso-purview' -TenantId $TenantId `
        -AppId $AppId -ClientSecret $ClientSecret -DataSourceName 'ws-contoso-prod' -RemoveDataSource

    Removes the trigger, the scan, and the data source registration itself.

.NOTES
    Same DELETE-pairs-with-Create-Or-Replace precedent both sibling scenarios rely on - Microsoft's
    REST APIs consistently pair a resource's Create Or Replace and Delete operations on the same URI.

    Sources (Microsoft Learn, verify before production use):
    - Connect to and manage Azure Synapse Analytics workspaces in Microsoft Purview:
      https://learn.microsoft.com/purview/register-scan-synapse-workspace
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