---
part: "validate"
parent: "unified-catalog/manage-critical-data-elements"
---
Run these checks after deployment to confirm the control is working as designed.


#### `Test-CriticalDataElement.ps1`

```powershell
#Requires -Version 7.0
<#
.SYNOPSIS
    Verifies a critical data element and its mapped columns, deployed by
    New-CriticalDataElement.ps1, match the definition file - and reports whether Microsoft's
    automatically-computed "associated data products" rollup is observable via the REST API.

.DESCRIPTION
    Read-only validation script - calls only GET/Query/List Relationships, never modifies state.
    Checks:
      1. The governance domain exists.
      2. The critical data element exists with the expected dataType/description, and reports
         (does not fail on) DRAFT vs PUBLISHED status.
      3. For each column in the definition file: resolves its Data Map column GUID, confirms a
         Unified Catalog data column wrapper exists for it, and confirms the critical data
         element is mapped to it.
      4. Reports critical data elements' relationships of entityType=DATAPRODUCT as an
         informational cross-check against scenarios/unified-catalog/manage-data-products/'s own
         output - this is Microsoft's documented "associated data products" rollup, observed here,
         never created by this scenario (design.md Section 5). Reported as [WARN] if empty, never
         [FAIL] - whether this rollup is actually surfaced through this specific REST call is an
         open VERIFY (README.md Section 11), not a confirmed contract this script can enforce.
    Exits with a non-zero code if any hard check fails. Safe to re-run any number of times.

.PARAMETER PurviewAccountEndpoint
    Base URL of the Purview Unified Catalog data-plane API - must match the value used at deploy
    time.

.PARAMETER DataMapEndpoint
    Base URL of the Purview Data Map/Atlas data-plane API, used to re-resolve each column's Data
    Map GUID the same way New-CriticalDataElement.ps1 does.

.PARAMETER TenantId
    Microsoft Entra tenant ID.

.PARAMETER AppId
    Application (client) ID of a service principal holding at least Data Steward / Governance
    Domain Reader on the target domain and Data Reader on the Data Map collection.

.PARAMETER ClientSecret
    Client secret for -AppId, as a SecureString.

.PARAMETER DefinitionPath
    Path to the same critical data element definition JSON file passed to
    New-CriticalDataElement.ps1.

.PARAMETER DataProductName
    Optional. If supplied, checked by name (within the same domain) against the critical data
    element's DATAPRODUCT relationships - e.g. 'Customer Master Data', the product
    scenarios/unified-catalog/manage-data-products/ creates from the same underlying asset this
    scenario's default config maps a column from. Omit to skip this specific cross-check while
    still reporting the raw DATAPRODUCT relationship list.

.PARAMETER ApiVersion
    Unified Catalog REST API version to pin. Defaults to '2026-03-20-preview'.

.PARAMETER DataMapApiVersion
    Data Map/Atlas REST API version to pin. Defaults to '2023-09-01'.

.EXAMPLE
    ./Test-CriticalDataElement.ps1 -PurviewAccountEndpoint 'https://api.purview-service.microsoft.com' `
        -DataMapEndpoint 'https://api.purview-service.microsoft.com' `
        -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
        -DefinitionPath '../deploy/config/customer-id-cde.sample.json' -DataProductName 'Customer Master Data'
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$PurviewAccountEndpoint,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$DataMapEndpoint,

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
    [string]$DataProductName,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$ApiVersion = '2026-03-20-preview',

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$DataMapApiVersion = '2023-09-01'
)

$ErrorActionPreference = 'Stop'
$endpoint = $PurviewAccountEndpoint.TrimEnd('/')
$dataMapEndpoint = $DataMapEndpoint.TrimEnd('/')
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

function Find-CriticalDataElementByName {
    param([Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)][string]$DomainId, [Parameter(Mandatory)][string]$Token)
    $uri = "$endpoint/datagovernance/catalog/criticalDataElements/query?api-version=$ApiVersion"
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

function Resolve-DataMapColumnId {
    param([Parameter(Mandatory)][string]$TableAssetId, [Parameter(Mandatory)][string]$ColumnName, [Parameter(Mandatory)][string]$Token)
    $uri = "$dataMapEndpoint/datamap/api/atlas/v2/entity/guid/$TableAssetId`?api-version=$DataMapApiVersion"
    $response = Invoke-RestMethod -Method Get -Uri $uri -Headers @{ Authorization = "Bearer $Token" }
    $match = $response.entity.relationshipAttributes.columns | Where-Object { $_.displayText -ceq $ColumnName } | Select-Object -First 1
    return $match.guid
}

function Find-DataColumnBySource {
    param([Parameter(Mandatory)][string]$DataMapAssetId, [Parameter(Mandatory)][string]$DataMapColumnId, [Parameter(Mandatory)][string]$Token)
    $uri = "$endpoint/datagovernance/catalog/dataColumns/query?api-version=$ApiVersion"
    $body = @{
        includingOrphans = $true
        filter           = @{
            and = @(
                @{ sourceAssetId = @{ eq = $DataMapAssetId } }
                @{ sourceColumnId = @{ eq = $DataMapColumnId } }
            )
        }
    }
    $response = Invoke-UcmPost -Uri $uri -Body $body -Token $Token
    return ($response.value | Where-Object { $_.source.columnId -eq $DataMapColumnId } | Select-Object -First 1)
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

Write-Host "`nValidating critical data element '$($definition.criticalDataElement.name)'..." -ForegroundColor Cyan
$cde = Find-CriticalDataElementByName -Name $definition.criticalDataElement.name -DomainId $domain.id -Token $token
Test-Check -Description "Critical data element '$($definition.criticalDataElement.name)' exists" -Condition ($null -ne $cde)
if (-not $cde) {
    Write-Host "`nCannot continue - critical data element not found. $script:failures check(s) failed." -ForegroundColor Red
    exit 1
}
Test-Check -Description "Data type is '$($definition.criticalDataElement.dataType)'" -Condition ($cde.dataType -eq $definition.criticalDataElement.dataType)
Test-Check -Description 'Description matches the definition file' -Condition ($cde.description -eq $definition.criticalDataElement.description)
Test-Check -Description 'At least one owner contact is set' -Condition ($null -ne $cde.contacts.owner -and $cde.contacts.owner.Count -gt 0)
Test-Check -Description 'Critical data element is published' -Condition ($cde.status -eq 'PUBLISHED') -Warn

Write-Host "`nValidating mapped columns for '$($definition.criticalDataElement.name)'..." -ForegroundColor Cyan
$colRelUri = "$endpoint/datagovernance/catalog/criticalDataElements/$($cde.id)/relationships?api-version=$ApiVersion&entityType=DATACOLUMN"
$colRelationships = Invoke-UcmGet -Uri $colRelUri -Token $token
foreach ($col in $definition.columns) {
    $label = "$($col.columnName) ($($col.dataMapAssetId))"
    $dataMapColumnId = Resolve-DataMapColumnId -TableAssetId $col.dataMapAssetId -ColumnName $col.columnName -Token $token
    if (-not $dataMapColumnId) {
        Test-Check -Description "Column '$label' resolved on Data Map" -Condition $false
        continue
    }
    $dataColumn = Find-DataColumnBySource -DataMapAssetId $col.dataMapAssetId -DataMapColumnId $dataMapColumnId -Token $token
    Test-Check -Description "Unified Catalog data column wraps '$label'" -Condition ($null -ne $dataColumn)
    if ($dataColumn) {
        Test-Check -Description "Critical data element is mapped to '$label'" `
            -Condition ([bool]($colRelationships.value | Where-Object { $_.entityId -eq $dataColumn.id }))
    }
    else {
        Test-Check -Description "Critical data element is mapped to '$label'" -Condition $false
    }
}

Write-Host "`nChecking the 'associated data products' rollup (design.md Section 5 - observed, not created by this scenario)..." -ForegroundColor Cyan
$prodRelUri = "$endpoint/datagovernance/catalog/criticalDataElements/$($cde.id)/relationships?api-version=$ApiVersion&entityType=DATAPRODUCT"
try {
    $prodRelationships = Invoke-UcmGet -Uri $prodRelUri -Token $token
    $count = @($prodRelationships.value).Count
    if ($count -gt 0) {
        Write-Host "  [INFO] $count associated data product relationship(s) reported via the API." -ForegroundColor Cyan
    }
    else {
        Test-Check -Description "At least one associated data product reported (entityType=DATAPRODUCT)" -Condition $false -Warn
    }
    if ($DataProductName) {
        $product = Find-DataProductByName -Name $DataProductName -DomainId $domain.id -Token $token
        if ($product) {
            Test-Check -Description "Auto-linked to data product '$DataProductName' (cross-scenario check against manage-data-products)" `
                -Condition ([bool]($prodRelationships.value | Where-Object { $_.entityId -eq $product.id })) -Warn
        }
        else {
            Write-Host "  [INFO] Data product '$DataProductName' not found in this domain - run scenarios/unified-catalog/manage-data-products/ first to exercise this cross-check." -ForegroundColor Yellow
        }
    }
}
catch {
    Write-Host "  [WARN] Could not query entityType=DATAPRODUCT relationships ($($_.Exception.Message)) - this is an open VERIFY (README.md Section 11), not treated as a hard failure." -ForegroundColor Yellow
}

Write-Host "`n$(if ($script:failures -eq 0) { 'All hard checks passed.' } else { "$script:failures hard check(s) failed." })" `
    -ForegroundColor $(if ($script:failures -eq 0) { 'Green' } else { 'Red' })

if ($script:failures -gt 0) { exit 1 }
```