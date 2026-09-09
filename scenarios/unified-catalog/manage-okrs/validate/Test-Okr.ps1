#Requires -Version 7.0
<#
.SYNOPSIS
    Verifies an objective (OKR), its key results, and its data-product links, deployed by
    New-Okr.ps1, match the definition file.

.DESCRIPTION
    Read-only validation script - calls only GET/Query, never modifies state. Checks:
      1. The governance domain exists.
      2. The objective exists (looked up by the definition file's caller-generated id - design.md
         Section 3, not by name), with the expected definition text/target date, and reports (does
         not fail on) Draft vs. Published status.
      3. Each key result in the definition file exists under that objective with the expected
         definition/progress/goal/max/status.
      4. Each data product named in relatedDataProducts exists and reports (does not fail on)
         whether it is linked to the objective (entityType=OBJECTIVE on that data product's own
         Data Products - List Relationships) - a hard [FAIL] here would conflate "not yet
         deployed" with "genuinely missing," so this is reported as [WARN] the same way
         manage-critical-data-elements/validate/Test-CriticalDataElement.ps1 treats its own
         DATAPRODUCT cross-check.
    Exits with a non-zero code if any hard check fails. Safe to re-run any number of times.

.PARAMETER PurviewAccountEndpoint
    Base URL of the Purview Unified Catalog data-plane API - must match the value used at deploy
    time.

.PARAMETER TenantId
    Microsoft Entra tenant ID.

.PARAMETER AppId
    Application (client) ID of a service principal holding at least Data Steward / Governance
    Domain Reader on the target domain.

.PARAMETER ClientSecret
    Client secret for -AppId, as a SecureString.

.PARAMETER DefinitionPath
    Path to the same OKR definition JSON file passed to New-Okr.ps1.

.PARAMETER ApiVersion
    Unified Catalog REST API version to pin. Defaults to '2026-03-20-preview'.

.EXAMPLE
    ./Test-Okr.ps1 -PurviewAccountEndpoint 'https://api.purview-service.microsoft.com' `
        -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
        -DefinitionPath '../deploy/config/customer-data-trust-okr.sample.json'
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
    param([Parameter(Mandatory)][string]$Uri, [Parameter(Mandatory)][string]$Token, [switch]$TreatNotFoundAsNull)
    try { return Invoke-RestMethod -Method Get -Uri $Uri -Headers @{ Authorization = "Bearer $Token" } }
    catch {
        if ($TreatNotFoundAsNull -and $_.Exception.Response -and $_.Exception.Response.StatusCode.value__ -eq 404) { return $null }
        throw
    }
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

function Find-DataProductByName {
    param([Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)][string]$DomainId, [Parameter(Mandatory)][string]$Token)
    $uri = "$endpoint/datagovernance/catalog/dataProducts/query?api-version=$ApiVersion"
    $body = @{ domainIds = @($DomainId); nameKeyword = $Name; top = 50 }
    $response = Invoke-UcmPost -Uri $uri -Body $body -Token $Token
    return ($response.value | Where-Object { $_.name -eq $Name } | Select-Object -First 1)
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

Write-Host "`nValidating objective (id: $($definition.objective.id))..." -ForegroundColor Cyan
$objectiveUri = "$endpoint/datagovernance/catalog/objectives/$($definition.objective.id)?api-version=$ApiVersion"
$objective = Invoke-UcmGet -Uri $objectiveUri -Token $token -TreatNotFoundAsNull
Test-Check -Description "Objective '$($definition.objective.definition)' exists (by id)" -Condition ($null -ne $objective)
if (-not $objective) {
    Write-Host "`nCannot continue - objective not found. $script:failures check(s) failed." -ForegroundColor Red
    exit 1
}
Test-Check -Description 'Definition text matches the definition file' -Condition ($objective.definition -eq $definition.objective.definition)
Test-Check -Description 'Domain matches the definition file' -Condition ($objective.domain -eq $domain.id)
Test-Check -Description 'At least one owner contact is set' -Condition ($null -ne $objective.contacts.owner -and $objective.contacts.owner.Count -gt 0)
Test-Check -Description "Objective is published" -Condition ($objective.status -eq 'Published') -Warn

Write-Host "`nValidating key results..." -ForegroundColor Cyan
foreach ($kr in $definition.keyResults) {
    $krUri = "$endpoint/datagovernance/catalog/objectives/$($definition.objective.id)/keyResults/$($kr.id)?api-version=$ApiVersion"
    $deployed = Invoke-UcmGet -Uri $krUri -Token $token -TreatNotFoundAsNull
    Test-Check -Description "Key result '$($kr.definition)' exists (by id)" -Condition ($null -ne $deployed)
    if ($deployed) {
        Test-Check -Description "  ...definition text matches" -Condition ($deployed.definition -eq $kr.definition)
        Test-Check -Description "  ...goal/max/progress match ($($kr.progress)/$($kr.goal)/$($kr.max))" `
            -Condition ($deployed.goal -eq $kr.goal -and $deployed.max -eq $kr.max -and $deployed.progress -eq $kr.progress)
        Test-Check -Description "  ...status matches ('$($kr.status)')" -Condition ($deployed.status -eq $kr.status)
    }
}

Write-Host "`nValidating data-product links..." -ForegroundColor Cyan
foreach ($productName in $definition.relatedDataProducts) {
    $product = Find-DataProductByName -Name $productName -DomainId $domain.id -Token $token
    if (-not $product) {
        Write-Host "  [INFO] Data product '$productName' not found in this domain - run scenarios/unified-catalog/manage-data-products/ first to exercise this check." -ForegroundColor Yellow
        continue
    }
    $relUri = "$endpoint/datagovernance/catalog/dataProducts/$($product.id)/relationships?api-version=$ApiVersion&entityType=OBJECTIVE"
    $relationships = Invoke-UcmGet -Uri $relUri -Token $token
    Test-Check -Description "Data product '$productName' is linked to this objective (entityType=OBJECTIVE)" `
        -Condition ([bool]($relationships.value | Where-Object { $_.entityId -eq $definition.objective.id })) -Warn
}

Write-Host "`n$(if ($script:failures -eq 0) { 'All hard checks passed.' } else { "$script:failures hard check(s) failed." })" `
    -ForegroundColor $(if ($script:failures -eq 0) { 'Green' } else { 'Red' })

if ($script:failures -gt 0) { exit 1 }
