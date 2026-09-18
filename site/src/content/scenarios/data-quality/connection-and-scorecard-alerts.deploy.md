---
part: "deploy"
parent: "data-quality/connection-and-scorecard-alerts"
---
The scripts and configuration below deploy this scenario. Review them, then run in order — each is designed to be idempotent and has a matching rollback.


#### `alerts/customer-360-product-score-alert.json`

```json
{
  "_comment": "Companion example demonstrating PRODUCT-level AlertScope (README.md Section 11) - the alert monitors every asset in the 'Customer 360' data product instead of one named asset. Achieved by omitting dataAssetId entirely from the alert entry (contrast with customer-master-score-alerts.json, which sets both dataProductId and dataAssetId for asset-level scope) - New-DataQualityAlert.ps1 already builds the scopes.dataProduct-only shape whenever dataAssetId is absent, no script change was needed to ship this file. Grounding status: Microsoft's own Update Alert REST worked example sets both dataProduct and dataAsset together (asset-level scope) - no REST worked example with dataAsset omitted was found. The AlertScope object's own schema reference lists dataAsset and dataProduct as two independent, separately-optional Reference fields (neither documented as mutually required), and the portal's 'Set up data quality alerts' conceptual doc's Scope-tab step describes choosing 'data products AND data assets that the alert will monitor' as separate selections, not a mandatory pairing - both corroborate, but do not independently confirm, that this shape is accepted. Same VERIFY class as the sibling receivers/UPN gap already tracked in README.md Section 11 - flagged, not guessed past. businessDomainId/dataProductId reuse the same 'Customer Experience' / 'Customer 360' GUIDs as customer-master-score-alerts.json so both example files target one coherent, already-governed data product.",
  "businessDomainId": "76be16f9-5cb3-4839-83d6-4e3829a8ab0c",
  "alerts": [
    {
      "id": "customer-360-product-score-below-95",
      "name": "Customer 360 data product score below 95% (any asset)",
      "description": "Fires when ANY asset in the 'Customer 360' data product drops below a 95% data quality score on a completed scan - a single alert covering the whole product instead of one alert per asset, for a buyer whose data product has more assets than they want individual per-asset alerts for. Complements, does not replace, customer-master-score-alerts.json's asset-level pair: a product-level alert tells you SOMETHING in the product regressed, not WHICH asset - see README.md Section 8 for the operational trade-off.",
      "condition": "score_threshold(GLOBAL_SCORE) < 95",
      "receivers": [
        "00000000-0000-0000-0000-000000000001"
      ],
      "dataProductId": "2a1d2087-09e2-4ecf-817d-1f5bfcbc31bf",
      "enabledForFailedJobs": true,
      "status": "Enabled"
    }
  ]
}
```

#### `alerts/customer-master-score-alerts.json`

```json
{
  "_comment": "Example values below. businessDomainId/dataProductId/dataAssetId must be the real GUIDs of a governance domain, data product, and data asset that already exist in Unified Catalog - this scenario does not create them. Reuses the same 'Customer' data asset (Azure SQL customerdb.dbo.Customers, 'Customer Experience' governance domain, 'Customer 360' data product) that scenarios/data-quality/rules-and-scorecards/ already scores, so a buyer evaluating this repo end to end sees rules, a scan schedule, a connection, and now alerting, all on one coherent asset. receivers must be the Microsoft Entra object ID of a user or mail-enabled security group - Microsoft's own Create/Get Alert REST examples show only GUIDs, never a raw SMTP address or UPN string, even though the portal's own conceptual documentation calls the field a 'recipient alias' (see README.md Section 11 VERIFY). condition only documents two functions in Microsoft's worked examples - score_threshold(GLOBAL_SCORE) and score_variance(GLOBAL_SCORE) - both used below; do not invent a third.",
  "businessDomainId": "76be16f9-5cb3-4839-83d6-4e3829a8ab0c",
  "alerts": [
    {
      "id": "customer-score-below-95",
      "name": "Customer data quality score below 95%",
      "description": "Fires when the Customer asset's rolled-up global data quality score drops below 95% on any completed scan - the primary go-live alert this scenario's README Section 8 treats as a mandatory gate.",
      "condition": "score_threshold(GLOBAL_SCORE) < 95",
      "receivers": [
        "00000000-0000-0000-0000-000000000001"
      ],
      "dataProductId": "2a1d2087-09e2-4ecf-817d-1f5bfcbc31bf",
      "dataAssetId": "fadb55b6-aa10-47d5-82c4-5e2723ba7869",
      "enabledForFailedJobs": true,
      "status": "Enabled"
    },
    {
      "id": "customer-score-regression",
      "name": "Customer data quality score regressed more than 10 points",
      "description": "Fires when the Customer asset's score drops by more than 10 points versus the prior completed scan - catches a sudden upstream data-pipeline regression even if the absolute score is still above the 95% threshold alert.",
      "condition": "score_variance(GLOBAL_SCORE) > 10",
      "receivers": [
        "00000000-0000-0000-0000-000000000001"
      ],
      "dataProductId": "2a1d2087-09e2-4ecf-817d-1f5bfcbc31bf",
      "dataAssetId": "fadb55b6-aa10-47d5-82c4-5e2723ba7869",
      "enabledForFailedJobs": true,
      "status": "Enabled"
    }
  ]
}
```

#### `connection/customer-sql-connection.json`

```json
{
  "_comment": "Example values below. businessDomainId must be the real GUID of a governance domain that already exists in Unified Catalog (this scenario does not create it). This example targets the same 'Customer Experience' governance domain and Azure SQL source as the sibling scenarios/data-quality/rules-and-scorecards/ fragment - one coherent 'Customer' data asset governed, cataloged, scored, and now connected/alerted end to end. dataSourceId is a caller-chosen string (not a GUID) - it becomes part of the REST path, so keep it short and stable.",
  "businessDomainId": "76be16f9-5cb3-4839-83d6-4e3829a8ab0c",
  "dataSourceId": "customerdb-sql-connection",
  "name": "customerdb Azure SQL connection",
  "type": "AzureSqlDatabase",
  "dataSourceType": "sqlServer",
  "region": "eastus2",
  "server": "customerdb-sqlsrv.database.windows.net",
  "database": "customerdb",
  "isVNetEnabled": false,
  "credential": {
    "type": "ManagedServiceIdentity",
    "scopeType": "Sql"
  }
}
```

#### `New-DataQualityAlert.ps1`

```powershell
#Requires -Version 7.0
<#
.SYNOPSIS
    Creates or reconciles Microsoft Purview Unified Catalog Data Quality score-threshold alerts
    from a declarative JSON definition file, and can enable/disable an existing alert.

.DESCRIPTION
    Calls the Microsoft Purview Data Quality REST API for Unified Catalog (Public Preview,
    automation surface 4 per docs/automation-surface.md):
      1. For each alert in the definition file, PUT .../alerts/{alertId} (Update Alert) with the
         caller-chosen alertId from the file - this operation's own REST reference confirms the ID
         is caller-supplied and PUT-addressed, so (unlike Rules in the sibling rules-and-scorecards
         scenario, which must discover an existing ruleId via Get Rules before it can target it)
         no separate existence lookup is needed to know *which* ID to PUT.
      2. Optionally (-Disable/-Enable) instead call PATCH .../alerts/{alertId} (Update Alert
         Status) to flip an existing alert's status without resending its full definition.

    This script still performs a GET before the PUT purely for accurate "Created"/"Updated"
    console reporting - see .NOTES for why the PUT's own create-vs-replace semantics against an
    already-existing ID were not independently confirmed by this build's grounding pass, and why
    that ambiguity does not affect this script's idempotency (the alertId is always caller-chosen
    and stable, so a repeat run always targets the same object either way).

    This script does NOT create the governance domain, data product, or data asset an alert scopes
    to - those are prerequisites documented in README.md Section 3, matching every other Data
    Quality/Unified Catalog scenario in this repo.

    Author-only reference code. Never connects to a live tenant unless you supply real credentials
    and omit -WhatIf.

.PARAMETER PurviewAccountEndpoint
    Base URL of the Purview Unified Catalog / Data Quality data-plane API.

.PARAMETER TenantId
    Microsoft Entra tenant ID.

.PARAMETER AppId
    Application (client) ID of the service principal used to call the Data Quality REST API. Must
    hold the Data Quality Steward role on the target governance domain (docs/rbac-model.md
    Section 5 and README.md Section 3) - Microsoft's "Set up data quality alerts" article
    documents this same role requirement for the portal action this script automates.

.PARAMETER ClientSecret
    Client secret for -AppId, as a SecureString. Resolve from a vault at run time - never hard-code.

.PARAMETER AlertDefinitionPath
    Path to the alert definition JSON file. See
    deploy/alerts/customer-master-score-alerts.json for the expected shape (businessDomainId + an
    alerts array). Each alert's receivers must be Microsoft Entra object IDs, not raw email
    addresses - see README.md Section 11 VERIFY.

.PARAMETER SetStatus
    If supplied ('Enabled' or 'Disabled'), skips the full reconcile pass and instead calls Update
    Alert Status (a lighter-weight PATCH) against every alert ID in the definition file. Use this
    to pause/resume alerting (e.g. during a planned change freeze) without resending the full
    alert body.

.PARAMETER ApiVersion
    Data Quality REST API version to pin. Defaults to '2026-01-12-preview'.

.PARAMETER WhatIf
    Standard PowerShell ShouldProcess dry-run.

.EXAMPLE
    ./New-DataQualityAlert.ps1 -PurviewAccountEndpoint 'https://api.purview-service.microsoft.com' `
        -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
        -AlertDefinitionPath './alerts/customer-master-score-alerts.json' -WhatIf

    Dry-run: shows whether each alert would be created or updated, and its exact request body.

.EXAMPLE
    ./New-DataQualityAlert.ps1 -PurviewAccountEndpoint 'https://api.purview-service.microsoft.com' `
        -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
        -AlertDefinitionPath './alerts/customer-master-score-alerts.json'

    Creates (or updates) both alerts in the definition file.

.EXAMPLE
    ./New-DataQualityAlert.ps1 -PurviewAccountEndpoint 'https://api.purview-service.microsoft.com' `
        -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
        -AlertDefinitionPath './alerts/customer-master-score-alerts.json' -SetStatus Disabled

    Pauses both alerts (Update Alert Status only - condition/receivers/scope untouched) without
    deleting them, e.g. during a planned data-migration change freeze.

.EXAMPLE
    ./New-DataQualityAlert.ps1 -PurviewAccountEndpoint 'https://api.purview-service.microsoft.com' `
        -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
        -AlertDefinitionPath './alerts/customer-360-product-score-alert.json'

    Creates (or updates) the product-level companion alert - one alert covering every asset in the
    "Customer 360" data product instead of a single named asset. No difference in script behavior
    from the asset-level example: this file simply omits dataAssetId from its one alert entry, which
    the scope-construction logic below already treats as an independently optional field. See
    README.md Section 11 for this shape's grounding status.

.NOTES
    VERIFY before production use (see README.md Section 11 for full detail):
    - Whether `receivers` accepts a raw SMTP address/UPN string in addition to a Microsoft Entra
      object ID. Every worked example in Microsoft's Update Alert/Get Alert/Get Alerts REST
      reference pages shows only GUIDs, but the portal's own conceptual "Set up data quality
      alerts" article calls the equivalent field a "recipient alias" without stating the resolved
      value's exact type - this script sends whatever string the definition file supplies
      unmodified, and does not attempt to resolve a UPN to an object ID itself.
    - Whether Update Alert's PUT is strictly create-only (would error against an already-existing
      alertId) or create-or-replace - this build's fetch of its reference page states only
      "Creates an alert scoped to the specified business domain," with no explicit statement about
      reuse against an existing ID. Does not affect this script's idempotency (see .DESCRIPTION),
      but a production integration calling Update Alert directly without this script's existence
      check should confirm the behavior first.
    - The only two `condition` functions confirmed by this build's grounding pass are
      `score_threshold(GLOBAL_SCORE)` and `score_variance(GLOBAL_SCORE)`, both used in the example
      definition file. Whether a per-rule (not just per-asset global score) condition function
      exists was not independently confirmed - if needed, check the portal's alert-creation wizard
      for additional target options before assuming one doesn't exist.

    Sources (Microsoft Learn, verify before production use):
    - Update Alert:
      https://learn.microsoft.com/rest/api/purview/purviewdataquality/update-alert/update-alert?view=rest-purview-purviewdataquality-2026-01-12-preview
    - Update Alert Status:
      https://learn.microsoft.com/rest/api/purview/purviewdataquality/update-alert-status/update-alert-status?view=rest-purview-purviewdataquality-2026-01-12-preview
    - Get Alert / Get Alerts:
      https://learn.microsoft.com/rest/api/purview/purviewdataquality/get-alert/get-alert?view=rest-purview-purviewdataquality-2026-01-12-preview
      https://learn.microsoft.com/rest/api/purview/purviewdataquality/get-alerts/get-alerts?view=rest-purview-purviewdataquality-2026-01-12-preview
    - Set up data quality alerts (portal workflow, required role, recipient/threshold concepts):
      https://learn.microsoft.com/purview/unified-catalog-data-quality-alerts
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
    [string]$AlertDefinitionPath,

    [Parameter()]
    [ValidateSet('Enabled', 'Disabled')]
    [string]$SetStatus,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$ApiVersion = '2026-01-12-preview'
)

$ErrorActionPreference = 'Stop'
$endpoint = $PurviewAccountEndpoint.TrimEnd('/')

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

function Invoke-Dq {
    param(
        [Parameter(Mandatory)][ValidateSet('Get', 'Put', 'Patch')][string]$Method,
        [Parameter(Mandatory)][string]$Uri,
        [Parameter()][hashtable]$Body,
        [Parameter(Mandatory)][string]$Token,
        [Parameter()][string]$Description = $Uri
    )
    if ($Method -eq 'Get') {
        return Invoke-RestMethod -Method Get -Uri $Uri -Headers @{ Authorization = "Bearer $Token" }
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

$def = Get-Content -Path $AlertDefinitionPath -Raw | ConvertFrom-Json
foreach ($required in 'businessDomainId', 'alerts') {
    if (-not $def.$required) {
        throw "Definition file '$AlertDefinitionPath' is missing required field '$required'."
    }
}

$plainSecret = ConvertTo-PlainText -Secure $ClientSecret
try {
    $token = Get-PurviewAccessToken -TenantId $TenantId -AppId $AppId -PlainSecret $plainSecret
}
finally {
    $plainSecret = $null
}

foreach ($alertDef in $def.alerts) {
    foreach ($required in 'id', 'name', 'condition', 'receivers') {
        if (-not $alertDef.$required) {
            throw "Alert entry missing required field '$required' in '$AlertDefinitionPath'."
        }
    }
    $alertUri = "$endpoint/datagovernance/quality/business-domains/$($def.businessDomainId)/alerts/$($alertDef.id)?api-version=$ApiVersion"

    if ($SetStatus) {
        Invoke-Dq -Method Patch -Uri $alertUri -Body @{ status = $SetStatus } -Token $token `
            -Description "Set alert '$($alertDef.name)' status to $SetStatus" | Out-Null
        Write-Host "Alert '$($alertDef.name)' (id: $($alertDef.id)) status set to $SetStatus." -ForegroundColor Green
        continue
    }

    $existing = $null
    try { $existing = Invoke-Dq -Method Get -Uri $alertUri -Token $token }
    catch {
        if (-not ($_.Exception.Response -and $_.Exception.Response.StatusCode -eq 404)) { throw }
    }

    $scopes = @()
    if ($alertDef.dataProductId -or $alertDef.dataAssetId) {
        $scope = @{}
        if ($alertDef.dataProductId) { $scope.dataProduct = @{ referenceId = $alertDef.dataProductId; type = 'DataProductReference' } }
        if ($alertDef.dataAssetId) { $scope.dataAsset = @{ referenceId = $alertDef.dataAssetId; type = 'DataAssetReference' } }
        $scopes = @($scope)
    }

    $body = @{
        id                   = $alertDef.id
        name                 = $alertDef.name
        description          = $alertDef.description
        businessDomain       = @{ referenceId = $def.businessDomainId; type = 'BusinessDomainReference' }
        scopes               = $scopes
        status               = if ($alertDef.status) { $alertDef.status } else { 'Enabled' }
        condition            = $alertDef.condition
        receivers            = @($alertDef.receivers)
        enabledForFailedJobs = if ($null -ne $alertDef.enabledForFailedJobs) { [bool]$alertDef.enabledForFailedJobs } else { $true }
    }

    $verb = if ($existing) { 'Update' } else { 'Create' }
    Invoke-Dq -Method Put -Uri $alertUri -Body $body -Token $token `
        -Description "$verb alert '$($alertDef.name)'" | Out-Null
    Write-Host "$verb`d alert '$($alertDef.name)' (id: $($alertDef.id), condition: $($alertDef.condition), status: $($body.status))." -ForegroundColor Green
}

if ($SetStatus) {
    Write-Host "`nDone. $($def.alerts.Count) alert(s) set to $SetStatus." -ForegroundColor Cyan
}
else {
    Write-Host "`nDone. $($def.alerts.Count) alert(s) reconciled against business domain '$($def.businessDomainId)'." -ForegroundColor Cyan
    Write-Host "Note: alerts only fire on a completed data quality scan (scenarios/data-quality/rules-and-scorecards/) - creating an alert here does not itself trigger one." -ForegroundColor Cyan
}
Write-Host "Run validate/Test-DataQualityConnectionAndAlerts.ps1 to verify the deployed alerts." -ForegroundColor Cyan
```

#### `New-DataQualityConnection.ps1`

```powershell
#Requires -Version 7.0
<#
.SYNOPSIS
    Idempotently creates or updates a Microsoft Purview Unified Catalog Data Quality data-source
    connection (managed-identity credential) from a declarative JSON definition file.

.DESCRIPTION
    Calls the Microsoft Purview Data Quality REST API for Unified Catalog (Public Preview,
    automation surface 4 per docs/automation-surface.md) to reconcile one data-source connection
    against a governance domain: GET Data Source first to check whether it already exists, then
    PUT (Create Data Source) if it does not, or PATCH (Update Data Source) if it does - the two
    operations are documented separately with different HTTP verbs (unlike Rules/Schedule in the
    sibling scenarios/data-quality/rules-and-scorecards/ fragment, which share one PUT for both),
    so this script picks the verb the existence check confirms rather than guessing.

    Scopes to the common, non-VNet path only by default: a managed-identity credential over the
    public endpoint, which this build's grounding confirmed does NOT require a computeId (Get/
    Update Data Source's own non-VNet worked examples omit the field entirely - see README.md
    Section 11). Pass -EnableManagedVNet with a pre-provisioned -ComputeId to also set
    isVNetEnabled/computeId for the managed-virtual-network path - this script never provisions
    the VNet compute location or the managed private endpoint itself (both are Governance Domain
    Administrator-only portal actions with no documented REST provisioning endpoint - README.md
    Section 11).

    This script does NOT create the governance domain, data product, or data asset the connection
    will eventually be used to scan (see the sibling rules-and-scorecards scenario for that
    prerequisite chain), and it does NOT grant the Purview managed identity read access to the
    source database - that grant (e.g. db_datareader for Azure SQL) is a source-side action
    documented in README.md Section 5, matching scenarios/data-map/scan-azure-sql-and-classify/'s
    existing pattern for the same grant.

    Author-only reference code. Never connects to a live tenant unless you supply real credentials
    and omit -WhatIf.

.PARAMETER PurviewAccountEndpoint
    Base URL of the Purview Unified Catalog / Data Quality data-plane API. Use
    'https://api.purview-service.microsoft.com' for tenants on the current Microsoft Purview
    portal, or 'https://<account>.purview.azure.com' for the classic portal.

.PARAMETER TenantId
    Microsoft Entra tenant ID.

.PARAMETER AppId
    Application (client) ID of the service principal used to call the Data Quality REST API. Must
    hold the Data Quality Steward role on the target governance domain (docs/rbac-model.md
    Section 5 and README.md Section 3).

.PARAMETER ClientSecret
    Client secret for -AppId, as a SecureString. Resolve from a vault at run time - never hard-code.

.PARAMETER ConnectionDefinitionPath
    Path to the connection definition JSON file. See
    deploy/connection/customer-sql-connection.json for the expected shape.

.PARAMETER EnableManagedVNet
    If supplied, sets isVNetEnabled=true and includes -ComputeId (mandatory when this switch is
    used) in the request body. Requires the VNet compute location to already be provisioned for
    the connection's region (README.md Section 11) - this script does not provision it.

.PARAMETER ComputeId
    Compute resource identifier for the managed-VNet path. Mandatory with -EnableManagedVNet;
    ignored otherwise. Obtain from Settings > Unified Catalog > Virtual network in the portal after
    provisioning the region (README.md Section 5/11) - no REST endpoint to read it back was found
    in this build's grounding pass.

.PARAMETER ManagePrivateEndPointId
    Optional managed private endpoint identifier, if the source also requires a private-endpoint
    connection (README.md Section 11). Portal-provisioned and approved, same as -ComputeId.

.PARAMETER TargetResourceId
    Optional Azure resource ID of the underlying source (e.g. the Azure SQL server ARM resource
    ID). Required by Microsoft's own worked example for the VNet path; optional for the default
    non-VNet path.

.PARAMETER ApiVersion
    Data Quality REST API version to pin. Defaults to '2026-01-12-preview', confirmed current via
    a direct fetch of Microsoft's own REST reference at the time of this build.

.PARAMETER WhatIf
    Standard PowerShell ShouldProcess dry-run. Reports every REST call that would be made without
    sending any mutating (PUT/PATCH) request.

.EXAMPLE
    ./New-DataQualityConnection.ps1 -PurviewAccountEndpoint 'https://api.purview-service.microsoft.com' `
        -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
        -ConnectionDefinitionPath './connection/customer-sql-connection.json' -WhatIf

    Dry-run: shows whether this would create or update the connection, and the exact request body.

.EXAMPLE
    ./New-DataQualityConnection.ps1 -PurviewAccountEndpoint 'https://api.purview-service.microsoft.com' `
        -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
        -ConnectionDefinitionPath './connection/customer-sql-connection.json'

    Creates (or updates, if it already exists) the non-VNet managed-identity connection.

.EXAMPLE
    ./New-DataQualityConnection.ps1 -PurviewAccountEndpoint 'https://api.purview-service.microsoft.com' `
        -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
        -ConnectionDefinitionPath './connection/customer-sql-connection.json' `
        -EnableManagedVNet -ComputeId $ComputeId -TargetResourceId $SqlServerResourceId

    Creates/updates the same connection with the managed-VNet path enabled, using a compute
    location already provisioned via the portal.

.NOTES
    VERIFY before production use (see README.md Section 11 for full detail):
    - Whether computeId is genuinely optional for a non-VNet connection, or merely absent from the
      one non-VNet worked example (Get/Update Data Source's AdlsGen2 example) this build's
      grounding pass found - Microsoft's Create Data Source reference does not mark any request-
      body field as required/optional in its property table (unlike its own URI-parameter table,
      which does), so this is inferred from the shape of the confirmed examples, not from an
      explicit requiredness statement.
    - Whether Create Data Source's PUT is strictly create-only (would 409/error if -dataSourceId
      already exists) or would silently succeed as a replace - this script never relies on the
      answer because it always GETs first and only calls PUT on a confirmed 404, but a production
      integration calling Create Data Source directly should confirm this.
    - Whether Update Data Source's PATCH performs a partial merge or expects (and replaces with)
      the full object - Microsoft's own worked example sends the complete object shape on PATCH,
      which is what this script does too, but the semantics of omitting a field were not
      independently confirmed.

    Sources (Microsoft Learn, verify before production use):
    - Create Data Source:
      https://learn.microsoft.com/rest/api/purview/purviewdataquality/create-data-source/create-data-source?view=rest-purview-purviewdataquality-2026-01-12-preview
    - Update Data Source:
      https://learn.microsoft.com/rest/api/purview/purviewdataquality/update-data-source/update-data-source?view=rest-purview-purviewdataquality-2026-01-12-preview
    - Get Data Source:
      https://learn.microsoft.com/rest/api/purview/purviewdataquality/get-data-source/get-data-source?view=rest-purview-purviewdataquality-2026-01-12-preview
    - Set up data source connection for data quality in Unified Catalog:
      https://learn.microsoft.com/purview/unified-catalog-data-quality-supported-sources-connection
    - Set up managed virtual networks for data quality scans (compute provisioning, Governance
      Domain Administrator role, per-region/per-source shared compute):
      https://learn.microsoft.com/purview/unified-catalog-data-quality-managed-virtual-networks
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
    [string]$ConnectionDefinitionPath,

    [Parameter()]
    [switch]$EnableManagedVNet,

    [Parameter()]
    [string]$ComputeId,

    [Parameter()]
    [string]$ManagePrivateEndPointId,

    [Parameter()]
    [string]$TargetResourceId,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$ApiVersion = '2026-01-12-preview'
)

$ErrorActionPreference = 'Stop'

if ($EnableManagedVNet -and -not $ComputeId) {
    throw "-EnableManagedVNet requires -ComputeId (provision a virtual network compute location via Settings > Unified Catalog > Virtual network in the portal first - see README.md Section 5/11)."
}

$endpoint = $PurviewAccountEndpoint.TrimEnd('/')

function ConvertTo-PlainText {
    param([Parameter(Mandatory)][SecureString]$Secure)
    $ptr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($Secure)
    try { return [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($ptr) }
    finally { [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr) }
}

function Get-PurviewAccessToken {
    # v1 client-credentials flow against the shared Data Map / Unified Catalog / Data Quality
    # data-plane resource, per docs/automation-surface.md Section 3.
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

function Invoke-Dq {
    # Invoke-RestMethod has no native ShouldProcess integration, so every mutating call is wrapped
    # in its own $PSCmdlet.ShouldProcess() check. GET always executes, including under -WhatIf, so
    # the script can accurately report create vs. update.
    param(
        [Parameter(Mandatory)][ValidateSet('Get', 'Put', 'Patch')][string]$Method,
        [Parameter(Mandatory)][string]$Uri,
        [Parameter()][hashtable]$Body,
        [Parameter(Mandatory)][string]$Token,
        [Parameter()][string]$Description = $Uri
    )
    if ($Method -eq 'Get') {
        return Invoke-RestMethod -Method Get -Uri $Uri -Headers @{ Authorization = "Bearer $Token" }
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

# --- Load and validate the definition file ---
$def = Get-Content -Path $ConnectionDefinitionPath -Raw | ConvertFrom-Json
foreach ($required in 'businessDomainId', 'dataSourceId', 'name', 'type', 'server', 'database', 'region') {
    if (-not $def.$required) {
        throw "Definition file '$ConnectionDefinitionPath' is missing required field '$required'."
    }
}

$plainSecret = ConvertTo-PlainText -Secure $ClientSecret
try {
    $token = Get-PurviewAccessToken -TenantId $TenantId -AppId $AppId -PlainSecret $plainSecret
}
finally {
    $plainSecret = $null
}

$connectionUri = "$endpoint/datagovernance/quality/business-domains/$($def.businessDomainId)/data-sources/$($def.dataSourceId)?api-version=$ApiVersion"

$existing = $null
try { $existing = Invoke-Dq -Method Get -Uri $connectionUri -Token $token }
catch {
    if (-not ($_.Exception.Response -and $_.Exception.Response.StatusCode -eq 404)) { throw }
}

$scopeType = if ($def.credential.scopeType) { $def.credential.scopeType } else { 'Sql' }

$body = @{
    id             = $def.dataSourceId
    name           = $def.name
    type           = $def.type
    dataSourceType = if ($def.dataSourceType) { $def.dataSourceType } else { $def.type }
    region         = $def.region
    isVNetEnabled  = [bool]$EnableManagedVNet
    businessDomain = @{ referenceId = $def.businessDomainId; type = 'BusinessDomainReference' }
    credential     = @{
        type           = 'ManagedServiceIdentity'
        typeProperties = @{
            scopes = @(
                @{ scope = @{ type = $scopeType; includes = @() } }
            )
        }
    }
    typeProperties = @{
        server   = $def.server
        database = $def.database
    }
}

if ($EnableManagedVNet) {
    $body.computeId = $ComputeId
    if ($ManagePrivateEndPointId) { $body.managePrivateEndPointId = $ManagePrivateEndPointId }
}
if ($TargetResourceId) { $body.targetResourceId = $TargetResourceId }

$verb = if ($existing) { 'Update' } else { 'Create' }
$method = if ($existing) { 'Patch' } else { 'Put' }

Invoke-Dq -Method $method -Uri $connectionUri -Body $body -Token $token `
    -Description "$verb data source connection '$($def.name)'" | Out-Null

Write-Host "$verb`d data source connection '$($def.name)' (id: $($def.dataSourceId), type: $($def.type), region: $($def.region), managed VNet: $([bool]$EnableManagedVNet))." -ForegroundColor Green

if (-not $EnableManagedVNet) {
    Write-Host "`nNon-VNet path: no computeId sent (see README.md Section 11 for why this is expected, not a gap)." -ForegroundColor Cyan
}

Write-Host "`nNote: this script does not test the connection or grant the Purview managed identity read access to the source - grant the source-appropriate read role (e.g. db_datareader for Azure SQL) separately, and use the portal's Test connection action or run/schedule a scan (scenarios/data-quality/rules-and-scorecards/) to confirm end-to-end reachability." -ForegroundColor Cyan
Write-Host "Run validate/Test-DataQualityConnectionAndAlerts.ps1 to verify the deployed connection." -ForegroundColor Cyan
```

#### `Remove-DataQualityConnectionAndAlerts.ps1`

```powershell
#Requires -Version 7.0
<#
.SYNOPSIS
    Removes the alerts created by New-DataQualityAlert.ps1, and optionally the data-source
    connection created by New-DataQualityConnection.ps1.

.DESCRIPTION
    Staged rollback (see ../rollback.md for the full procedure and what each stage does and does
    not undo):
      Stage 1 (default): delete every alert named in the alert definition file. The connection
        stays in place - it's a shared, comparatively expensive-to-reprovision object (especially
        on the managed-VNet path, where the compute location and private endpoint are portal
        actions with their own approval workflow), so this script does not remove it by default.
      Stage 2 (-RemoveConnection): also delete the data-source connection.

    Idempotent: deleting an object that no longer exists (404) is treated as already-removed, not
    an error, so this script is safe to re-run.

.PARAMETER PurviewAccountEndpoint
    Base URL of the Purview Unified Catalog / Data Quality data-plane API.

.PARAMETER TenantId
    Microsoft Entra tenant ID.

.PARAMETER AppId
    Application (client) ID of a service principal holding the Data Quality Steward role on the
    target governance domain.

.PARAMETER ClientSecret
    Client secret for -AppId, as a SecureString.

.PARAMETER AlertDefinitionPath
    Path to the same alert definition JSON file passed to New-DataQualityAlert.ps1 - used to
    resolve which alert IDs (Stage 1) to delete. Pass an empty string to skip alert removal.

.PARAMETER ConnectionDefinitionPath
    Path to the same connection definition JSON file passed to New-DataQualityConnection.ps1 -
    required only with -RemoveConnection.

.PARAMETER RemoveConnection
    If supplied, also deletes the data-source connection (Stage 2). Omit to remove only the
    alerts (Stage 1).

.PARAMETER ApiVersion
    Data Quality REST API version to pin. Defaults to '2026-01-12-preview', matching the deploy
    scripts.

.PARAMETER WhatIf
    Standard PowerShell ShouldProcess dry-run.

.EXAMPLE
    ./Remove-DataQualityConnectionAndAlerts.ps1 -PurviewAccountEndpoint 'https://api.purview-service.microsoft.com' `
        -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
        -AlertDefinitionPath '../deploy/alerts/customer-master-score-alerts.json' -WhatIf

    Dry-run of Stage 1 (alert removal only).

.EXAMPLE
    ./Remove-DataQualityConnectionAndAlerts.ps1 -PurviewAccountEndpoint 'https://api.purview-service.microsoft.com' `
        -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
        -AlertDefinitionPath '../deploy/alerts/customer-master-score-alerts.json' `
        -ConnectionDefinitionPath '../deploy/connection/customer-sql-connection.json' -RemoveConnection

    Stage 2: removes both alerts and the data-source connection.

.NOTES
    Sources: same as New-DataQualityConnection.ps1 and New-DataQualityAlert.ps1 - see those
    scripts' .NOTES. Delete Alert / Delete Data Source:
    https://learn.microsoft.com/rest/api/purview/purviewdataquality/delete-alert/delete-alert?view=rest-purview-purviewdataquality-2026-01-12-preview
    https://learn.microsoft.com/rest/api/purview/purviewdataquality/delete-data-source/delete-data-source?view=rest-purview-purviewdataquality-2026-01-12-preview
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

    [Parameter()]
    [string]$AlertDefinitionPath,

    [Parameter()]
    [string]$ConnectionDefinitionPath,

    [Parameter()]
    [switch]$RemoveConnection,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$ApiVersion = '2026-01-12-preview'
)

$ErrorActionPreference = 'Stop'
$endpoint = $PurviewAccountEndpoint.TrimEnd('/')

if ($RemoveConnection -and -not $ConnectionDefinitionPath) {
    throw "-RemoveConnection requires -ConnectionDefinitionPath."
}
if (-not $AlertDefinitionPath -and -not $RemoveConnection) {
    throw "Nothing to do: pass -AlertDefinitionPath (Stage 1) and/or -RemoveConnection with -ConnectionDefinitionPath (Stage 2)."
}

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

function Remove-IfExists {
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
        Write-Host "Removed: $Description." -ForegroundColor Green
    }
    catch {
        if ($_.Exception.Response -and $_.Exception.Response.StatusCode -eq 404) {
            Write-Host "Already removed (404): $Description." -ForegroundColor Yellow
        }
        else { throw }
    }
}

$plainSecret = ConvertTo-PlainText -Secure $ClientSecret
try {
    $token = Get-PurviewAccessToken -TenantId $TenantId -AppId $AppId -PlainSecret $plainSecret
}
finally {
    $plainSecret = $null
}

# --- Stage 1: remove alerts ---
if ($AlertDefinitionPath) {
    $alertDefFile = Get-Content -Path $AlertDefinitionPath -Raw | ConvertFrom-Json
    foreach ($alertDef in $alertDefFile.alerts) {
        $alertUri = "$endpoint/datagovernance/quality/business-domains/$($alertDefFile.businessDomainId)/alerts/$($alertDef.id)?api-version=$ApiVersion"
        Remove-IfExists -Uri $alertUri -Token $token -Description "alert '$($alertDef.name)' (id: $($alertDef.id))"
    }
}
else {
    Write-Host "[SKIP] Alert removal skipped (-AlertDefinitionPath not supplied)." -ForegroundColor Yellow
}

# --- Stage 2 (optional): remove the data-source connection ---
if ($RemoveConnection) {
    $connDef = Get-Content -Path $ConnectionDefinitionPath -Raw | ConvertFrom-Json
    $connUri = "$endpoint/datagovernance/quality/business-domains/$($connDef.businessDomainId)/data-sources/$($connDef.dataSourceId)?api-version=$ApiVersion"
    Remove-IfExists -Uri $connUri -Token $token -Description "data source connection '$($connDef.name)' (id: $($connDef.dataSourceId))"
    Write-Host "`nNote: this does not de-provision a managed-VNet compute location or private endpoint (both are portal/Governance Domain Administrator actions - README.md Section 11); deleting the connection object alone does not release them." -ForegroundColor Cyan
}
else {
    Write-Host "`nConnection was left in place. Pass -RemoveConnection with -ConnectionDefinitionPath to also delete it." -ForegroundColor Cyan
}
```