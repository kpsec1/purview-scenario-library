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
    console reporting - Update Alert's PUT is a confirmed create-or-replace against an existing
    alertId (see .NOTES), so the GET is not needed for correctness, only for console messaging.
    The alertId is always caller-chosen and stable, so a repeat run always targets the same object
    either way.

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
    - CONFIRMED (2026-09-27, direct Microsoft Learn fetch): Update Alert's PUT is create-or-replace
      against an already-existing alertId, not create-only. Microsoft's reference page now
      documents the alertId URI parameter itself as "Unique identifier of the alert to create or
      replace." Never affected this script's idempotency (the alertId is always caller-chosen and
      stable), but a production integration calling Update Alert directly now has an authoritative
      citation instead of an open question.
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
