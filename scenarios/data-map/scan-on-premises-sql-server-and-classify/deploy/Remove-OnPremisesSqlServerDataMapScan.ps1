#Requires -Version 7.0
<#
.SYNOPSIS
    Removes the scan (and its trigger, if any) created by New-OnPremisesSqlServerDataMapScan.ps1,
    and optionally the data source registration and/or the integration runtime resource itself.

.DESCRIPTION
    Calls the Microsoft Purview Data Map / Scanning REST API to delete, in order:
      1. The recurring trigger (if present) - DELETE .../scans/{scanName}/triggers/default
      2. The scan object - DELETE .../datasources/{dataSourceName}/scans/{scanName}
      3. (only with -RemoveDataSource) the data source registration itself -
         DELETE .../datasources/{dataSourceName}
      4. (only with -RemoveIntegrationRuntime) the self-hosted integration runtime resource -
         DELETE .../integrationruntimes/{integrationRuntimeName}

    Deleting a scan or data source does NOT delete assets already ingested into the catalog from
    previous scan runs (Microsoft Learn: register-scan-on-premises-sql-server - "Deleting your scan
    does not delete catalog assets created from previous scans"). This script only removes the
    scanning configuration; it never deletes catalog data.

    Deleting the integration runtime RESOURCE in Purview does not uninstall the SHIR SOFTWARE from
    whatever host it's running on, and does not stop that host's Integration Runtime Windows service
    - it only removes Purview's registration of it. If other scans still reference the same
    integration runtime, do not pass -RemoveIntegrationRuntime.

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
    Name of the data source object (matches -DataSourceName used at deploy time, or a sanitized form
    of -ServerEndpoint if it was left to default).

.PARAMETER ScanName
    Name of the scan object. Defaults to "<DataSourceName>-scan" to match the deploy script's default.

.PARAMETER RemoveDataSource
    If supplied, also deletes the data source registration after the scan is removed.

.PARAMETER IntegrationRuntimeName
    Name of the self-hosted integration runtime resource. Required only if -RemoveIntegrationRuntime
    is supplied.

.PARAMETER RemoveIntegrationRuntime
    If supplied, also deletes the integration runtime resource. Do not pass this if any other scan
    (for this or another data source) still references the same integration runtime.

.PARAMETER ApiVersion
    Data Map REST API version to pin. Defaults to '2023-09-01' to match the deploy script.

.PARAMETER WhatIf
    Standard PowerShell ShouldProcess dry-run. Reports every REST call that would be made without
    sending any mutating (DELETE) request.

.EXAMPLE
    ./Remove-OnPremisesSqlServerDataMapScan.ps1 -PurviewAccountName 'contoso-purview' -TenantId $TenantId `
        -AppId $AppId -ClientSecret $ClientSecret -DataSourceName 'sql01-contoso-local' -WhatIf

    Dry-run: shows exactly which DELETE calls would be made, changes nothing.

.EXAMPLE
    ./Remove-OnPremisesSqlServerDataMapScan.ps1 -PurviewAccountName 'contoso-purview' -TenantId $TenantId `
        -AppId $AppId -ClientSecret $ClientSecret -DataSourceName 'sql01-contoso-local' `
        -RemoveDataSource -IntegrationRuntimeName 'shir-onprem-sql' -RemoveIntegrationRuntime

    Full teardown: removes the trigger, the scan, the data source registration, and the integration
    runtime resource. Does not touch the SHIR software/service on its host - see README.md/rollback.md.

.NOTES
    All four DELETE calls follow the same path pattern confirmed by direct fetch of the matching
    Create Or Replace REST reference pages (see New-OnPremisesSqlServerDataMapScan.ps1's .NOTES) -
    Microsoft's REST APIs consistently pair a resource's Create Or Replace and Delete operations on
    the same URI.

    Sources (Microsoft Learn, verify before production use):
    - Connect to and manage an on-premises SQL server instance in Microsoft Purview - "Manage your
      scans" (deleting a scan does not delete catalog assets):
      https://learn.microsoft.com/purview/register-scan-on-premises-sql-server
    - Create and manage a self-hosted integration runtime - "Manage a self-hosted integration
      runtime" (deleting the IR resource vs. the software/service on its host):
      https://learn.microsoft.com/purview/data-map-integration-runtime-self-hosted
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
    [string]$IntegrationRuntimeName,

    [Parameter()]
    [switch]$RemoveIntegrationRuntime,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$ApiVersion = '2023-09-01'
)

$ErrorActionPreference = 'Stop'

if (-not $ScanName) { $ScanName = "$DataSourceName-scan" }
if ($RemoveIntegrationRuntime -and -not $IntegrationRuntimeName) {
    throw "-IntegrationRuntimeName is required when -RemoveIntegrationRuntime is supplied."
}

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

# --- Step 4 (optional): remove the integration runtime resource ---
if ($RemoveIntegrationRuntime) {
    $irUri = "$endpoint/scan/integrationruntimes/$IntegrationRuntimeName?api-version=$ApiVersion"
    Invoke-PurviewDelete -Uri $irUri -Token $token -Description "Integration runtime '$IntegrationRuntimeName'"
    Write-Host "Note: this removed Purview's registration of the integration runtime only. If a SHIR node is still running on a host with this key, stop/uninstall it separately - see rollback.md." -ForegroundColor Yellow
}
elseif ($IntegrationRuntimeName) {
    Write-Host "Integration runtime '$IntegrationRuntimeName' left registered (pass -RemoveIntegrationRuntime to remove it too)." -ForegroundColor Yellow
}

Write-Host "`nDone. Catalog assets already ingested from prior scan runs are not deleted by this script - see rollback.md." -ForegroundColor Cyan
