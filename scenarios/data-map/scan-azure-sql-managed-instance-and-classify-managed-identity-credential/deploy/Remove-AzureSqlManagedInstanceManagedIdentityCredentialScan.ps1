#Requires -Version 7.0
<#
.SYNOPSIS
    Reverts the scan created by scan-azure-sql-managed-instance-and-classify from a ManagedIdentity
    (UAMI) credential back onto Purview's system-assigned managed identity (SAMI).

.DESCRIPTION
    Calls the Microsoft Purview Data Map / Scanning REST API to GET the target scan and PUT it back
    with `kind` reset to AzureSqlDatabaseManagedInstanceMsi and the `credential` property removed
    entirely - every other scan property (database name, server endpoint, collection, scan rule set)
    preserved unchanged. Does not delete the ManagedIdentity credential object itself, the UAMI, or
    its Azure IAM/SQL grants - those are independent objects this script never touches (see
    rollback.md).

    Idempotent: reverting a scan that already authenticates as AzureSqlDatabaseManagedInstanceMsi is
    treated as a no-op success, not an error.

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

.PARAMETER ApiVersion
    Data Map REST API version to pin. Defaults to '2023-09-01'.

.EXAMPLE
    ./Remove-AzureSqlManagedInstanceManagedIdentityCredentialScan.ps1 -PurviewAccountName 'contoso-purview' `
        -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
        -DataSourceName 'mi-contoso-prod-customerdb'

    Reverts the scan back to SAMI authentication (AzureSqlDatabaseManagedInstanceMsi).

.NOTES
    Reverting to SAMI requires the Purview account's own SAMI still holds the Azure IAM Reader grant
    and SQL db_datareader external-provider user from the base scenario - if those were removed when
    the UAMI credential was adopted, re-run this revert only after re-establishing them.

    Source: Scans - Create Or Replace (confirmed create-or-replace PUT semantics):
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
$scanUri = "$endpoint/scan/datasources/$DataSourceName/scans/$ScanName?api-version=$ApiVersion"

$existingScan = $null
try {
    $existingScan = Invoke-RestMethod -Method Get -Uri $scanUri -Headers $headers
}
catch {
    if ($_.Exception.Response -and $_.Exception.Response.StatusCode -eq 404) {
        Write-Host "Scan '$ScanName' on data source '$DataSourceName' does not exist - nothing to revert." -ForegroundColor Yellow
        exit 0
    }
    throw
}

if ($existingScan.kind -eq 'AzureSqlDatabaseManagedInstanceMsi') {
    Write-Host "Scan '$ScanName' already authenticates via SAMI (AzureSqlDatabaseManagedInstanceMsi) - nothing to revert." -ForegroundColor Yellow
    exit 0
}

$scanBody = @{
    kind       = 'AzureSqlDatabaseManagedInstanceMsi'
    properties = @{
        databaseName    = $existingScan.properties.databaseName
        serverEndpoint  = $existingScan.properties.serverEndpoint
        collection      = $existingScan.properties.collection
        scanRulesetName = $existingScan.properties.scanRulesetName
        scanRulesetType = $existingScan.properties.scanRulesetType
    }
}

if ($PSCmdlet.ShouldProcess("Scan '$ScanName'", "PUT $scanUri (revert to AzureSqlDatabaseManagedInstanceMsi)")) {
    $json = $scanBody | ConvertTo-Json -Depth 10
    Invoke-RestMethod -Method Put -Uri $scanUri -Body $json -ContentType 'application/json' -Headers $headers | Out-Null
    Write-Host "Scan '$ScanName' reverted to SAMI authentication (AzureSqlDatabaseManagedInstanceMsi). The ManagedIdentity credential object itself was not deleted." -ForegroundColor Green
}
else {
    Write-Verbose "WhatIf: would PUT $scanUri with body:`n$($scanBody | ConvertTo-Json -Depth 10)"
}
