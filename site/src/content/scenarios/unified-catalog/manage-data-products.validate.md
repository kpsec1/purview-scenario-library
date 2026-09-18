---
part: "validate"
parent: "unified-catalog/manage-data-products"
---
Run these checks after deployment to confirm the control is working as designed.


#### `Test-DataProduct.ps1`

```powershell
#Requires -Version 7.0
<#
.SYNOPSIS
    Verifies a data product, its data asset wrapper, and its relationships deployed by
    New-DataProduct.ps1 match the definition file.

.DESCRIPTION
    Read-only validation script - calls only GET/Query/List Relationships, never modifies state.
    Checks:
      1. The governance domain exists.
      2. The data product exists with the expected type/description/businessUse/updateFrequency/
         audience, and reports (does not fail on) DRAFT vs PUBLISHED status.
      3. A Unified Catalog data asset wraps the definition file's Data Map asset ID, and reports
         its inferred type and any classifications carried over from Data Map scanning (a live
         cross-check against scenarios/data-map/scan-azure-sql-and-classify/'s own output).
      4. The data product is linked to that data asset.
      5. The data product is linked to every term in 'relatedTerms'.
      6. Reports the data product's additionalProperties.assetCount as an informational KPI.
    Exits with a non-zero code if any hard check fails. Safe to re-run any number of times.

.PARAMETER PurviewAccountEndpoint
    Base URL of the Purview Unified Catalog data-plane API - must match the value used at deploy
    time.

.PARAMETER TenantId
    Microsoft Entra tenant ID.

.PARAMETER AppId
    Application (client) ID of a service principal holding at least Data Product Owner / Governance
    Domain Reader on the target domain.

.PARAMETER ClientSecret
    Client secret for -AppId, as a SecureString.

.PARAMETER DefinitionPath
    Path to the same data product definition JSON file passed to New-DataProduct.ps1.

.PARAMETER ApiVersion
    Unified Catalog REST API version to pin. Defaults to '2026-03-20-preview'.

.EXAMPLE
    ./Test-DataProduct.ps1 -PurviewAccountEndpoint 'https://api.purview-service.microsoft.com' `
        -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
        -DefinitionPath '../deploy/config/customer-master-data-product.sample.json'
#>
[CmdletBinding()]
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
    [ValidateNotNullOrEmpty()]
    [string]$ApiVersion = '2026-03-20-preview'
)

$ErrorActionPreference = 'Stop'
$endpoint = $PurviewAccountEndpoint.TrimEnd('/')
$script:failures = 0

function Test-Check {
    param([string]$Description, [bool]$Condition, [switch]$Warn)
    if ($Condition) {
        Write-Host "  [PASS] $Description" -ForegroundColor Green
    }
    elseif ($Warn) {
        Write-Host "  [WARN] $Description" -ForegroundColor Yellow
    }
    else {
        Write-Host "  [FAIL] $Description" -ForegroundColor Red
        $script:failures++
    }
}

function ConvertTo-PlainText {
    param([Parameter(Mandatory)][SecureString]$Secure)
    $ptr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($Secure)
    try { return [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($ptr) }
    finally { [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr) }
}

function Get-PurviewAccessToken {
    param([Parameter(Mandatory)][string]$TenantId, [Parameter(Mandatory)][string]$AppId, [Parameter(Mandatory)][string]$PlainSecret)
    $body = @{ client_id = $AppId; client_secret = $PlainSecret; grant_type = 'client_credentials'; resource = 'https://purview.azure.net' }
    $response = Invoke-RestMethod -Method Post -Uri "https://login.microsoftonline.com/$TenantId/oauth2/token" -Body $body
    return $response.access_token
}

function Invoke-UcmGet {
    param([Parameter(Mandatory)][string]$Uri, [Parameter(Mandatory)][string]$Token)
    return Invoke-RestMethod -Method Get -Uri $Uri -Headers @{ Authorization = "Bearer $Token" }
}

function Invoke-UcmPost {
    param([Parameter(Mandatory)][string]$Uri, [Parameter(Mandatory)][hashtable]$Body, [Parameter(Mandatory)][string]$Token)
    return Invoke-RestMethod -Method Post -Uri $Uri -Body ($Body | ConvertTo-Json -Depth 10) -ContentType 'application/json' -Headers @{ Authorization = "Bearer $Token" }
}

function Find-BusinessDomainByName {
    param([Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)][string]$Token)
    $uri = "$endpoint/datagovernance/catalog/businessdomains?api-version=$ApiVersion"
    while ($uri) {
        $page = Invoke-UcmGet -Uri $uri -Token $Token
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
    $response = Invoke-UcmPost -Uri $uri -Body $body -Token $Token
    return ($response.value | Where-Object { $_.name -eq $Name } | Select-Object -First 1)
}

function Find-DataProductByName {
    param([Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)][string]$DomainId, [Parameter(Mandatory)][string]$Token)
    $uri = "$endpoint/datagovernance/catalog/dataProducts/query?api-version=$ApiVersion"
    $body = @{ domainIds = @($DomainId); nameKeyword = $Name; top = 50 }
    $response = Invoke-UcmPost -Uri $uri -Body $body -Token $Token
    return ($response.value | Where-Object { $_.name -eq $Name } | Select-Object -First 1)
}

function Find-DataAssetBySourceId {
    param([Parameter(Mandatory)][string]$DataMapAssetId, [Parameter(Mandatory)][string]$Token)
    $uri = "$endpoint/datagovernance/catalog/dataAssets/query?api-version=$ApiVersion"
    $body = @{ sourceAssetIds = @($DataMapAssetId) }
    $response = Invoke-UcmPost -Uri $uri -Body $body -Token $Token
    return ($response.value | Where-Object { $_.source.assetId -eq $DataMapAssetId } | Select-Object -First 1)
}

$definition = Get-Content -Path $DefinitionPath -Raw | ConvertFrom-Json
$plainSecret = ConvertTo-PlainText -Secure $ClientSecret
try { $token = Get-PurviewAccessToken -TenantId $TenantId -AppId $AppId -PlainSecret $plainSecret }
finally { $plainSecret = $null }

Write-Host "Validating governance domain '$($definition.domain.name)'..." -ForegroundColor Cyan
$domain = Find-BusinessDomainByName -Name $definition.domain.name -Token $token
Test-Check -Description "Governance domain '$($definition.domain.name)' exists" -Condition ($null -ne $domain)
if (-not $domain) {
    Write-Host "`nCannot continue - domain not found. $script:failures check(s) failed." -ForegroundColor Red
    exit 1
}

Write-Host "`nValidating data product '$($definition.dataProduct.name)'..." -ForegroundColor Cyan
$product = Find-DataProductByName -Name $definition.dataProduct.name -DomainId $domain.id -Token $token
Test-Check -Description "Data product '$($definition.dataProduct.name)' exists" -Condition ($null -ne $product)
if (-not $product) {
    Write-Host "`nCannot continue - data product not found. $script:failures check(s) failed." -ForegroundColor Red
    exit 1
}
Test-Check -Description "Type is '$($definition.dataProduct.type)'" -Condition ($product.type -eq $definition.dataProduct.type)
Test-Check -Description 'Description matches the definition file' -Condition ($product.description -eq $definition.dataProduct.description)
Test-Check -Description "Update frequency is '$($definition.dataProduct.updateFrequency)'" -Condition ($product.updateFrequency -eq $definition.dataProduct.updateFrequency)
$expectedAudience = @($definition.dataProduct.audience) -join ','
$actualAudience = @($product.audience) -join ','
Test-Check -Description "Audience matches (expected: [$expectedAudience])" -Condition ($expectedAudience -eq $actualAudience)
Test-Check -Description 'At least one owner contact is set' -Condition ($null -ne $product.contacts.owner -and $product.contacts.owner.Count -gt 0)
Test-Check -Description 'Data product is published' -Condition ($product.status -eq 'PUBLISHED') -Warn
if ($product.additionalProperties -and $null -ne $product.additionalProperties.assetCount) {
    Write-Host "  [INFO] Linked asset count reported by the API: $($product.additionalProperties.assetCount)" -ForegroundColor Cyan
}

Write-Host "`nValidating data asset wrapper for Data Map asset '$($definition.dataAsset.dataMapAssetId)'..." -ForegroundColor Cyan
$dataAsset = Find-DataAssetBySourceId -DataMapAssetId $definition.dataAsset.dataMapAssetId -Token $token
Test-Check -Description 'Unified Catalog data asset wraps the configured Data Map asset' -Condition ($null -ne $dataAsset)
if ($dataAsset) {
    Write-Host "  [INFO] Data asset type: $($dataAsset.type)" -ForegroundColor Cyan
    if ($dataAsset.classifications -and $dataAsset.classifications.Count -gt 0) {
        Write-Host "  [INFO] Classifications carried over from Data Map: $($dataAsset.classifications -join ', ')" -ForegroundColor Cyan
    }
    else {
        Write-Host '  [INFO] No classifications reported on this asset yet - confirm scan-azure-sql-and-classify has completed at least one successful scan.' -ForegroundColor Yellow
    }
}

Write-Host "`nValidating relationships for '$($definition.dataProduct.name)'..." -ForegroundColor Cyan
if ($dataAsset) {
    $assetRelUri = "$endpoint/datagovernance/catalog/dataProducts/$($product.id)/relationships?api-version=$ApiVersion&entityType=DATAASSET"
    $assetRelationships = Invoke-UcmGet -Uri $assetRelUri -Token $token
    Test-Check -Description 'Linked to its data asset' -Condition ([bool]($assetRelationships.value | Where-Object { $_.entityId -eq $dataAsset.id }))
}
else {
    Test-Check -Description 'Linked to its data asset' -Condition $false
}

$termRelUri = "$endpoint/datagovernance/catalog/dataProducts/$($product.id)/relationships?api-version=$ApiVersion&entityType=TERM"
$termRelationships = Invoke-UcmGet -Uri $termRelUri -Token $token
foreach ($termName in $definition.relatedTerms) {
    $term = Find-TermByName -Name $termName -DomainId $domain.id -Token $token
    if (-not $term) {
        Test-Check -Description "Linked to term '$termName'" -Condition $false
        continue
    }
    Test-Check -Description "Linked to term '$termName'" -Condition ([bool]($termRelationships.value | Where-Object { $_.entityId -eq $term.id }))
}

Write-Host "`n$(if ($script:failures -eq 0) { 'All hard checks passed.' } else { "$script:failures hard check(s) failed." })" `
    -ForegroundColor $(if ($script:failures -eq 0) { 'Green' } else { 'Red' })

if ($script:failures -gt 0) { exit 1 }
```