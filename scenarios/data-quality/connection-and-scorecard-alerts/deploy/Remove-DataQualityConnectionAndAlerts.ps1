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
