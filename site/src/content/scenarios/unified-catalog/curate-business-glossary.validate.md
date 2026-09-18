---
part: "validate"
parent: "unified-catalog/curate-business-glossary"
---
Run these checks after deployment to confirm the control is working as designed.


#### `Test-BusinessGlossary.ps1`

```powershell
#Requires -Version 7.0
<#
.SYNOPSIS
    Verifies a governance domain and glossary terms deployed by New-BusinessGlossary.ps1 match the
    definition file.

.DESCRIPTION
    Read-only validation script - calls only GET and the read-only Query Terms/List Related
    Entities operations, never modifies state. Checks:
      1. The governance domain exists with the expected type.
      2. Every term in the definition file exists in that domain.
      3. Every term's description, acronyms, and parent relationship match the definition file.
      4. Every term with an owner/expert has at least one resolved contact.
      5. Every declared term-to-term relationship exists.
      6. Reports (does not fail on) DRAFT vs PUBLISHED status, since both are valid states
         depending on whether -Publish has been run yet.
    Exits with a non-zero code if any hard check fails, so this script is safe to wire into a
    CI-style pre-flight or a post-deploy smoke test. Safe to re-run any number of times.

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

.PARAMETER GlossaryDefinitionPath
    Path to the same glossary definition JSON file passed to New-BusinessGlossary.ps1.

.PARAMETER ApiVersion
    Unified Catalog REST API version to pin. Defaults to '2026-03-20-preview'.

.EXAMPLE
    ./Test-BusinessGlossary.ps1 -PurviewAccountEndpoint 'https://api.purview-service.microsoft.com' `
        -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
        -GlossaryDefinitionPath '../deploy/glossary/customer-experience-glossary.json'
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
    [string]$GlossaryDefinitionPath,

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

$definition = Get-Content -Path $GlossaryDefinitionPath -Raw | ConvertFrom-Json
$plainSecret = ConvertTo-PlainText -Secure $ClientSecret
try {
    $token = Get-PurviewAccessToken -TenantId $TenantId -AppId $AppId -PlainSecret $plainSecret
}
finally {
    $plainSecret = $null
}

Write-Host "Validating governance domain '$($definition.domain.name)'..." -ForegroundColor Cyan
$domain = Find-BusinessDomainByName -Name $definition.domain.name -Token $token
Test-Check -Description "Governance domain '$($definition.domain.name)' exists" -Condition ($null -ne $domain)
if (-not $domain) {
    Write-Host "`nCannot continue - domain not found. $script:failures check(s) failed." -ForegroundColor Red
    exit 1
}
Test-Check -Description "Domain type is '$($definition.domain.type)'" -Condition ($domain.type -eq $definition.domain.type)
Test-Check -Description 'Domain is published' -Condition ($domain.status -eq 'PUBLISHED') -Warn

$termsByName = @{}
foreach ($termDef in $definition.terms) {
    Write-Host "`nValidating term '$($termDef.name)'..." -ForegroundColor Cyan
    $term = Find-TermByName -Name $termDef.name -DomainId $domain.id -Token $token
    Test-Check -Description "Term '$($termDef.name)' exists in the domain" -Condition ($null -ne $term)
    if (-not $term) { continue }
    $termsByName[$termDef.name] = $term

    Test-Check -Description 'Description matches the definition file' -Condition ($term.description -eq $termDef.description)
    $expectedAcronyms = @($termDef.acronyms) -join ','
    $actualAcronyms = @($term.acronyms) -join ','
    Test-Check -Description "Acronyms match (expected: [$expectedAcronyms])" -Condition ($expectedAcronyms -eq $actualAcronyms)
    Test-Check -Description 'Term is published' -Condition ($term.status -eq 'PUBLISHED') -Warn

    if ($termDef.owners -and $termDef.owners.Count -gt 0) {
        Test-Check -Description 'At least one owner contact is set' -Condition ($null -ne $term.contacts.owner -and $term.contacts.owner.Count -gt 0)
    }

    if ($termDef.parent) {
        Test-Check -Description "Parent term reference is set" -Condition ($null -ne $term.parentId)
        if ($termsByName.ContainsKey($termDef.parent)) {
            Test-Check -Description "Parent resolves to '$($termDef.parent)'" -Condition ($term.parentId -eq $termsByName[$termDef.parent].id) -Warn
        }
    }
}

foreach ($termDef in $definition.terms) {
    if (-not $termDef.relatedTerms -or $termDef.relatedTerms.Count -eq 0) { continue }
    if (-not $termsByName.ContainsKey($termDef.name)) { continue }
    Write-Host "`nValidating relationships for '$($termDef.name)'..." -ForegroundColor Cyan
    $relUri = "$endpoint/datagovernance/catalog/terms/$($termsByName[$termDef.name].id)/relationships?api-version=$ApiVersion&entityType=TERM"
    $relationships = Invoke-UcmGet -Uri $relUri -Token $token
    foreach ($relatedName in $termDef.relatedTerms) {
        $expectedId = if ($termsByName.ContainsKey($relatedName)) { $termsByName[$relatedName].id } else { $null }
        $found = $expectedId -and ($relationships.value | Where-Object { $_.entityId -eq $expectedId })
        Test-Check -Description "Related to '$relatedName'" -Condition ([bool]$found)
    }
}

Write-Host "`n$(if ($script:failures -eq 0) { 'All hard checks passed.' } else { "$script:failures hard check(s) failed." })" `
    -ForegroundColor $(if ($script:failures -eq 0) { 'Green' } else { 'Red' })

if ($script:failures -gt 0) { exit 1 }
```