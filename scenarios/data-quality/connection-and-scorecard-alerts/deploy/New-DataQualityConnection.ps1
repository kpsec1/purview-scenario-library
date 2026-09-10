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
