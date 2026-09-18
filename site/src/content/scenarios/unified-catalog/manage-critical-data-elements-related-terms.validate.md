---
part: "validate"
parent: "unified-catalog/manage-critical-data-elements-related-terms"
---
Run these checks after deployment to confirm the control is working as designed.


#### `Test-CdeRelatedTerms.ps1`

```powershell
#Requires -Version 7.0
<#
.SYNOPSIS
    Verifies a critical data element's related-term links, deployed by Add-CdeRelatedTerm.ps1,
    match the definition file.

.DESCRIPTION
    Read-only validation script - calls only GET/Query, never modifies state. Checks:
      1. The governance domain exists.
      2. The critical data element exists.
      3. For each term name in the definition file's 'relatedTerms' array: the term exists by
         name in the same domain, and the critical data element has an entityType=TERM
         relationship pointing at it.
      4. Reports (informational only) the full count of entityType=TERM relationships the
         critical data element currently has, so an operator can see whether a term was linked
         outside this scenario's scripts (e.g. via the portal) that the definition file doesn't
         know about.
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
    Path to the same related-terms definition JSON file passed to Add-CdeRelatedTerm.ps1.

.PARAMETER ApiVersion
    Unified Catalog REST API version to pin. Defaults to '2026-03-20-preview'.

.EXAMPLE
    ./Test-CdeRelatedTerms.ps1 -PurviewAccountEndpoint 'https://api.purview-service.microsoft.com' `
        -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
        -DefinitionPath '../deploy/config/customer-id-related-terms.sample.json'
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

function Find-CriticalDataElementByName {
    param([Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)][string]$DomainId, [Parameter(Mandatory)][string]$Token)
    $uri = "$endpoint/datagovernance/catalog/criticalDataElements/query?api-version=$ApiVersion"
    $body = @{ domainIds = @($DomainId); nameKeyword = $Name; top = 50 }
    $response = Invoke-UcmPost -Uri $uri -Body $body -Token $Token
    return ($response.value | Where-Object { $_.name -eq $Name } | Select-Object -First 1)
}

function Find-TermByName {
    param([Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)][string]$DomainId, [Parameter(Mandatory)][string]$Token)
    $uri = "$endpoint/datagovernance/catalog/terms/query?api-version=$ApiVersion"
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

Write-Host "`nValidating critical data element '$($definition.criticalDataElement.name)'..." -ForegroundColor Cyan
$cde = Find-CriticalDataElementByName -Name $definition.criticalDataElement.name -DomainId $domain.id -Token $token
Test-Check -Description "Critical data element '$($definition.criticalDataElement.name)' exists" -Condition ($null -ne $cde)
if (-not $cde) {
    Write-Host "`nCannot continue - critical data element not found. $script:failures check(s) failed." -ForegroundColor Red
    exit 1
}

Write-Host "`nValidating related-term links..." -ForegroundColor Cyan
$relUri = "$endpoint/datagovernance/catalog/criticalDataElements/$($cde.id)/relationships?api-version=$ApiVersion&entityType=TERM"
$relationships = Invoke-UcmGet -Uri $relUri -Token $token
foreach ($termName in $definition.relatedTerms) {
    $term = Find-TermByName -Name $termName -DomainId $domain.id -Token $token
    Test-Check -Description "Term '$termName' exists in domain '$($domain.name)'" -Condition ($null -ne $term)
    if ($term) {
        Test-Check -Description "Critical data element is linked to term '$termName'" `
            -Condition ([bool]($relationships.value | Where-Object { $_.entityId -eq $term.id }))
    }
}

$totalLinked = @($relationships.value).Count
$expectedCount = @($definition.relatedTerms).Count
Write-Host "`n[INFO] '$($cde.name)' has $totalLinked total entityType=TERM relationship(s); this definition file names $expectedCount term(s)." -ForegroundColor Cyan
if ($totalLinked -gt $expectedCount) {
    Write-Host "[INFO] At least one linked term isn't listed in this definition file - likely added via the portal's own '+ Add term' button or the reciprocal 'Add critical data element' flow on a term's Related tab. Not treated as a failure." -ForegroundColor Cyan
}

Write-Host "`n$(if ($script:failures -eq 0) { 'All hard checks passed.' } else { "$script:failures hard check(s) failed." })" `
    -ForegroundColor $(if ($script:failures -eq 0) { 'Green' } else { 'Red' })

if ($script:failures -gt 0) { exit 1 }
```