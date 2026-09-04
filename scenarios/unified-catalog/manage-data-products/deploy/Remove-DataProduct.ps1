#Requires -Version 7.0
<#
.SYNOPSIS
    Staged rollback for scenarios/unified-catalog/manage-data-products/: unpublish (default),
    unlink (-RemoveLinks), or permanently delete (-Purge) the data product this scenario created.

.DESCRIPTION
    Three independent, additive stages - see rollback.md for the full procedure:
      1. Default: sets the data product's status back to DRAFT (PUT), reusing its own
         currently-stored fields (fetched via GET) so a portal-made edit isn't clobbered.
         Reversible - nothing is deleted or unlinked.
      2. -RemoveLinks: also deletes the data-asset and term relationships this scenario's
         New-DataProduct.ps1 created (DELETE .../relationships). The Unified Catalog data asset
         wrapper and the glossary terms themselves are left untouched - they may be referenced by
         other data products this scenario doesn't know about.
      3. -Purge: implies -RemoveLinks, then deletes the data product itself
         (DELETE .../dataProducts/{id}). Add -DeleteDataAssetWrapper to also delete the Unified
         Catalog data asset object this scenario created to wrap the Data Map asset - off by
         default because that wrapper is a shared, reusable object another data product may also
         reference (this script has no reverse lookup to confirm it's now unused - README.md
         Section 11). Never deletes the underlying Data Map asset or the governance domain/terms.

    Author-only reference code. Never connects to a live tenant unless you supply real credentials
    and omit -WhatIf.

.PARAMETER PurviewAccountEndpoint
    Base URL of the Purview Unified Catalog data-plane API.

.PARAMETER TenantId
    Microsoft Entra tenant ID.

.PARAMETER AppId
    Application (client) ID of the service principal. Must hold Data Product Owner on the domain.

.PARAMETER ClientSecret
    Client secret for -AppId, as a SecureString.

.PARAMETER DefinitionPath
    Path to the same data product definition JSON file passed to New-DataProduct.ps1.

.PARAMETER RemoveLinks
    Deletes the data-asset and term relationships this scenario created. Implied by -Purge.

.PARAMETER Purge
    Permanently deletes the data product (after removing its links). Not reversible - re-creating
    it via New-DataProduct.ps1 generates a new data product ID.

.PARAMETER DeleteDataAssetWrapper
    Only meaningful with -Purge. Also deletes the Unified Catalog data asset object wrapping the
    Data Map asset. Confirm no other data product references this wrapper first (README.md
    Section 11) - this script cannot check that for you.

.PARAMETER ApiVersion
    Unified Catalog REST API version to pin. Defaults to '2026-03-20-preview'.

.PARAMETER WhatIf
    Standard PowerShell ShouldProcess dry-run.

.EXAMPLE
    ./Remove-DataProduct.ps1 -PurviewAccountEndpoint 'https://api.purview-service.microsoft.com' `
        -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
        -DefinitionPath './config/customer-master-data-product.sample.json'

    Stage 1: unpublish (set back to DRAFT). Reversible.

.EXAMPLE
    ./Remove-DataProduct.ps1 -PurviewAccountEndpoint 'https://api.purview-service.microsoft.com' `
        -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
        -DefinitionPath './config/customer-master-data-product.sample.json' -Purge

    Stage 3: unlink, then permanently delete the data product (wrapper and terms untouched).
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

    [Parameter(Mandatory)]
    [ValidateScript({ Test-Path $_ -PathType Leaf })]
    [string]$DefinitionPath,

    [Parameter()]
    [switch]$RemoveLinks,

    [Parameter()]
    [switch]$Purge,

    [Parameter()]
    [switch]$DeleteDataAssetWrapper,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$ApiVersion = '2026-03-20-preview'
)

$ErrorActionPreference = 'Stop'
$endpoint = $PurviewAccountEndpoint.TrimEnd('/')
if ($Purge) { $RemoveLinks = $true }

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

function Invoke-Ucm {
    param(
        [Parameter(Mandatory)][ValidateSet('Get', 'Post', 'Put', 'Delete')][string]$Method,
        [Parameter(Mandatory)][string]$Uri,
        [Parameter()][hashtable]$Body,
        [Parameter(Mandatory)][string]$Token,
        [Parameter()][string]$Description = $Uri,
        [Parameter()][switch]$ReadOnly
    )
    if ($Method -eq 'Get' -or $ReadOnly) {
        $params = @{ Method = $Method; Uri = $Uri; Headers = @{ Authorization = "Bearer $Token" } }
        if ($Body) {
            $params.Body = ($Body | ConvertTo-Json -Depth 10)
            $params.ContentType = 'application/json'
        }
        return Invoke-RestMethod @params
    }
    if ($PSCmdlet.ShouldProcess($Description, "$Method $Uri")) {
        $params = @{
            Method      = $Method
            Uri         = $Uri
            ContentType = 'application/json'
            Headers     = @{ Authorization = "Bearer $Token" }
        }
        if ($Body) { $params.Body = ($Body | ConvertTo-Json -Depth 10) }
        try { return Invoke-RestMethod @params }
        catch {
            if ($_.Exception.Response -and $_.Exception.Response.StatusCode.value__ -eq 404) {
                Write-Host "$Description - already gone (404). Treating as success." -ForegroundColor Yellow
                return $null
            }
            throw
        }
    }
    Write-Verbose "WhatIf: would $Method $Uri"
    return $null
}

function Find-BusinessDomainByName {
    param([Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)][string]$Token)
    $uri = "$endpoint/datagovernance/catalog/businessdomains?api-version=$ApiVersion"
    while ($uri) {
        $page = Invoke-Ucm -Method Get -Uri $uri -Token $Token
        $match = $page.value | Where-Object { $_.name -eq $Name } | Select-Object -First 1
        if ($match) { return $match }
        $uri = $page.nextLink
    }
    return $null
}

function Find-TermByName {
    param([Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)][string]$DomainId, [Parameter(Mandatory)][string]$Token)
    $uri = "$endpoint/datagovernance/catalog/terms/query?api-version=$ApiVersion"
    $body = @{ domainIds = @($DomainId); nameKeyword = $Name; top = 50 }
    $response = Invoke-Ucm -Method Post -Uri $uri -Body $body -Token $Token -ReadOnly
    return ($response.value | Where-Object { $_.name -eq $Name } | Select-Object -First 1)
}

function Find-DataProductByName {
    param([Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)][string]$DomainId, [Parameter(Mandatory)][string]$Token)
    $uri = "$endpoint/datagovernance/catalog/dataProducts/query?api-version=$ApiVersion"
    $body = @{ domainIds = @($DomainId); nameKeyword = $Name; top = 50 }
    $response = Invoke-Ucm -Method Post -Uri $uri -Body $body -Token $Token -ReadOnly
    return ($response.value | Where-Object { $_.name -eq $Name } | Select-Object -First 1)
}

function Find-DataAssetBySourceId {
    param([Parameter(Mandatory)][string]$DataMapAssetId, [Parameter(Mandatory)][string]$Token)
    $uri = "$endpoint/datagovernance/catalog/dataAssets/query?api-version=$ApiVersion"
    $body = @{ sourceAssetIds = @($DataMapAssetId) }
    $response = Invoke-Ucm -Method Post -Uri $uri -Body $body -Token $Token -ReadOnly
    return ($response.value | Where-Object { $_.source.assetId -eq $DataMapAssetId } | Select-Object -First 1)
}

# --- Load the definition file ---
$definition = Get-Content -Path $DefinitionPath -Raw | ConvertFrom-Json

$plainSecret = ConvertTo-PlainText -Secure $ClientSecret
try { $ucToken = Get-PurviewAccessToken -TenantId $TenantId -AppId $AppId -PlainSecret $plainSecret }
finally { $plainSecret = $null }

$domain = Find-BusinessDomainByName -Name $definition.domain.name -Token $ucToken
if (-not $domain) { throw "Governance domain '$($definition.domain.name)' was not found. Nothing to roll back." }

$product = Find-DataProductByName -Name $definition.dataProduct.name -DomainId $domain.id -Token $ucToken
if (-not $product) {
    Write-Host "Data product '$($definition.dataProduct.name)' not found - already removed." -ForegroundColor Yellow
    exit 0
}

# --- Stage: remove links ---
if ($RemoveLinks) {
    $dataAsset = Find-DataAssetBySourceId -DataMapAssetId $definition.dataAsset.dataMapAssetId -Token $ucToken
    if ($dataAsset) {
        $uri = "$endpoint/datagovernance/catalog/dataProducts/$($product.id)/relationships?api-version=$ApiVersion&entityType=DATAASSET&entityId=$($dataAsset.id)"
        Invoke-Ucm -Method Delete -Uri $uri -Token $ucToken -Description "Unlink data asset from '$($product.name)'" | Out-Null
        Write-Host "Unlinked data asset (id: $($dataAsset.id)) from '$($product.name)'." -ForegroundColor Green
    }
    foreach ($termName in $definition.relatedTerms) {
        $term = Find-TermByName -Name $termName -DomainId $domain.id -Token $ucToken
        if (-not $term) { continue }
        $uri = "$endpoint/datagovernance/catalog/dataProducts/$($product.id)/relationships?api-version=$ApiVersion&entityType=TERM&entityId=$($term.id)"
        Invoke-Ucm -Method Delete -Uri $uri -Token $ucToken -Description "Unlink term '$termName' from '$($product.name)'" | Out-Null
        Write-Host "Unlinked term '$termName' from '$($product.name)'." -ForegroundColor Green
    }

    if ($Purge -and $DeleteDataAssetWrapper -and $dataAsset) {
        Write-Warning "Deleting the Unified Catalog data asset wrapper (id: $($dataAsset.id)) even though this script cannot confirm no other data product still references it."
        $uri = "$endpoint/datagovernance/catalog/dataAssets/$($dataAsset.id)?api-version=$ApiVersion"
        Invoke-Ucm -Method Delete -Uri $uri -Token $ucToken -Description "Delete data asset wrapper (id: $($dataAsset.id))" | Out-Null
        Write-Host "Deleted data asset wrapper (id: $($dataAsset.id))." -ForegroundColor Green
    }
}

# --- Stage: purge (delete the data product) or default (unpublish) ---
if ($Purge) {
    $uri = "$endpoint/datagovernance/catalog/dataProducts/$($product.id)?api-version=$ApiVersion"
    Invoke-Ucm -Method Delete -Uri $uri -Token $ucToken -Description "Delete data product '$($product.name)'" | Out-Null
    Write-Host "Deleted data product '$($product.name)' (id: $($product.id))." -ForegroundColor Green
}
else {
    if ($product.status -ne 'PUBLISHED') {
        Write-Host "Data product '$($product.name)' is already in $($product.status) status." -ForegroundColor Yellow
    }
    else {
        $body = @{
            id              = $product.id
            domain          = $product.domain
            name            = $product.name
            status          = 'DRAFT'
            type            = $product.type
            description     = $product.description
            businessUse     = $product.businessUse
            updateFrequency = $product.updateFrequency
            audience        = @($product.audience)
            endorsed        = [bool]$product.endorsed
            contacts        = $product.contacts
        }
        $uri = "$endpoint/datagovernance/catalog/dataProducts/$($product.id)?api-version=$ApiVersion"
        Invoke-Ucm -Method Put -Uri $uri -Body $body -Token $ucToken `
            -Description "Unpublish data product '$($product.name)'" | Out-Null
        Write-Host "Unpublished data product '$($product.name)' (set back to DRAFT)." -ForegroundColor Green
    }
}

Write-Host "`nDone. Run validate/Test-DataProduct.ps1 to confirm the resulting state." -ForegroundColor Cyan
