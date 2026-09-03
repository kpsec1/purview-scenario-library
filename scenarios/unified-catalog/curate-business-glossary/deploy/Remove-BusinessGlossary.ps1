#Requires -Version 7.0
<#
.SYNOPSIS
    Rolls back a governance domain and glossary terms deployed by New-BusinessGlossary.ps1.

.DESCRIPTION
    Two rollback modes:
      -Unpublish (default, recommended first step): sets every term and the domain itself back to
       DRAFT status, using each object's own currently-stored fields (fetched via GET) rather than
       the local definition file - so nothing this script didn't author is clobbered. Reversible by
       re-running New-BusinessGlossary.ps1 with -Publish. Nothing is deleted.
      -Purge: permanently deletes every term in the definition file, then the domain itself, via
       DELETE. This is NOT reversible - re-establishing the glossary means re-running
       New-BusinessGlossary.ps1 from scratch (new IDs will be generated).

    Idempotent: if a term or the domain doesn't exist (already deleted, or never created), the
    script reports that and continues rather than erroring.

.PARAMETER PurviewAccountEndpoint
    Base URL of the Purview Unified Catalog data-plane API - must match the value used at deploy
    time. See README.md Section 11.

.PARAMETER TenantId
    Microsoft Entra tenant ID.

.PARAMETER AppId
    Application (client) ID of the service principal. Must hold the Data Steward role on the
    domain (Governance Domain Owner if using -Purge to delete the domain itself).

.PARAMETER ClientSecret
    Client secret for -AppId, as a SecureString.

.PARAMETER GlossaryDefinitionPath
    Path to the same glossary definition JSON file passed to New-BusinessGlossary.ps1 - used only
    to enumerate which domain/term names to look up and roll back.

.PARAMETER Purge
    Permanently delete the domain and its terms instead of unpublishing them. See rollback.md for
    the recommended unpublish-first, purge-later sequence.

.PARAMETER ApiVersion
    Unified Catalog REST API version to pin. Defaults to '2026-03-20-preview'.

.PARAMETER WhatIf
    Standard PowerShell ShouldProcess dry-run - reports the unpublish/deletion that would happen
    without calling any mutating endpoint. Read-only lookups (finding the domain/terms by name)
    still execute under -WhatIf so the script can report accurately.

.EXAMPLE
    ./Remove-BusinessGlossary.ps1 -PurviewAccountEndpoint 'https://api.purview-service.microsoft.com' `
        -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
        -GlossaryDefinitionPath './glossary/customer-experience-glossary.json' -WhatIf

.EXAMPLE
    ./Remove-BusinessGlossary.ps1 -PurviewAccountEndpoint 'https://api.purview-service.microsoft.com' `
        -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
        -GlossaryDefinitionPath './glossary/customer-experience-glossary.json'
    # Unpublishes the domain and every term (soft rollback).

.EXAMPLE
    ./Remove-BusinessGlossary.ps1 -PurviewAccountEndpoint 'https://api.purview-service.microsoft.com' `
        -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
        -GlossaryDefinitionPath './glossary/customer-experience-glossary.json' -Purge
    # Permanently deletes every term, then the domain.

.NOTES
    Sources: https://learn.microsoft.com/rest/api/purview/purview-unified-catalog/terms/delete?view=rest-purview-purview-unified-catalog-2026-03-20-preview
             https://learn.microsoft.com/rest/api/purview/purview-unified-catalog/business-domain/delete?view=rest-purview-purview-unified-catalog-2026-03-20-preview
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
    [string]$GlossaryDefinitionPath,

    [Parameter()]
    [switch]$Purge,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$ApiVersion = '2026-03-20-preview'
)

$ErrorActionPreference = 'Stop'
$endpoint = $PurviewAccountEndpoint.TrimEnd('/')

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
        $params = @{ Method = $Method; Uri = $Uri; Headers = @{ Authorization = "Bearer $Token" } }
        if ($Body) {
            $params.Body = ($Body | ConvertTo-Json -Depth 10)
            $params.ContentType = 'application/json'
        }
        return Invoke-RestMethod @params
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
    $response = Invoke-Ucm -Method Post -Uri $uri -Body $body -Token $Token -ReadOnly `
        -Description "Query terms named like '$Name'"
    return ($response.value | Where-Object { $_.name -eq $Name } | Select-Object -First 1)
}

function ConvertTo-StatusOnlyUpdateBody {
    param([Parameter(Mandatory)][pscustomobject]$Term, [Parameter(Mandatory)][string]$Status)
    $body = @{
        id          = $Term.id
        domain      = $Term.domain
        name        = $Term.name
        status      = $Status
        description = $Term.description
        acronyms    = @($Term.acronyms)
        resources   = @($Term.resources | ForEach-Object { @{ name = $_.name; url = $_.url } })
        contacts    = @{}
    }
    if ($Term.parentId) { $body.parentId = $Term.parentId }
    if ($Term.contacts) {
        if ($Term.contacts.owner) { $body.contacts.owner = @($Term.contacts.owner | ForEach-Object { @{ id = $_.id; description = $_.description } }) }
        if ($Term.contacts.expert) { $body.contacts.expert = @($Term.contacts.expert | ForEach-Object { @{ id = $_.id; description = $_.description } }) }
        if ($Term.contacts.databaseAdmin) { $body.contacts.databaseAdmin = @($Term.contacts.databaseAdmin | ForEach-Object { @{ id = $_.id; description = $_.description } }) }
    }
    return $body
}

$definition = Get-Content -Path $GlossaryDefinitionPath -Raw | ConvertFrom-Json
if (-not $definition.domain -or -not $definition.terms) {
    throw "Definition file '$GlossaryDefinitionPath' must contain a 'domain' object and a 'terms' array."
}

$plainSecret = ConvertTo-PlainText -Secure $ClientSecret
try {
    $token = Get-PurviewAccessToken -TenantId $TenantId -AppId $AppId -PlainSecret $plainSecret
}
finally {
    $plainSecret = $null
}

$domain = Find-BusinessDomainByName -Name $definition.domain.name -Token $token
if (-not $domain) {
    Write-Host "Governance domain '$($definition.domain.name)' does not exist. Nothing to roll back." -ForegroundColor Yellow
    return
}

# Resolve every term's current state first (needed for the unpublish body, and to fail fast on
# lookup errors before any mutating call is made).
$terms = @()
foreach ($termDef in $definition.terms) {
    $existing = Find-TermByName -Name $termDef.name -DomainId $domain.id -Token $token
    if ($existing) { $terms += $existing }
    else { Write-Host "Term '$($termDef.name)' does not exist. Skipped." -ForegroundColor Yellow }
}

if ($Purge) {
    foreach ($term in $terms) {
        $uri = "$endpoint/datagovernance/catalog/terms/$($term.id)?api-version=$ApiVersion"
        Invoke-Ucm -Method Delete -Uri $uri -Token $token -Description "Delete term '$($term.name)'" | Out-Null
        Write-Host "Deleted term '$($term.name)'." -ForegroundColor Green
    }
    $domainUri = "$endpoint/datagovernance/catalog/businessdomains/$($domain.id)?api-version=$ApiVersion"
    Invoke-Ucm -Method Delete -Uri $domainUri -Token $token -Description "Delete governance domain '$($definition.domain.name)'" | Out-Null
    Write-Host "Deleted governance domain '$($definition.domain.name)'." -ForegroundColor Green
}
else {
    foreach ($term in $terms) {
        if ($term.status -ne 'DRAFT') {
            $body = ConvertTo-StatusOnlyUpdateBody -Term $term -Status 'DRAFT'
            $uri = "$endpoint/datagovernance/catalog/terms/$($term.id)?api-version=$ApiVersion"
            Invoke-Ucm -Method Put -Uri $uri -Body $body -Token $token -Description "Unpublish term '$($term.name)'" | Out-Null
            Write-Host "Unpublished term '$($term.name)'." -ForegroundColor Green
        }
        else {
            Write-Host "Term '$($term.name)' is already in DRAFT status." -ForegroundColor Yellow
        }
    }
    if ($domain.status -ne 'DRAFT') {
        $domainBody = @{
            id          = $domain.id
            name        = $domain.name
            description = $domain.description
            type        = $domain.type
            status      = 'DRAFT'
        }
        $domainUri = "$endpoint/datagovernance/catalog/businessdomains/$($domain.id)?api-version=$ApiVersion"
        Invoke-Ucm -Method Put -Uri $domainUri -Body $domainBody -Token $token -Description "Unpublish governance domain '$($definition.domain.name)'" | Out-Null
        Write-Host "Unpublished governance domain '$($definition.domain.name)'." -ForegroundColor Green
    }
    else {
        Write-Host "Governance domain '$($definition.domain.name)' is already in DRAFT status." -ForegroundColor Yellow
    }
    Write-Host "`nSoft rollback complete. Re-run New-BusinessGlossary.ps1 -Publish to restore, or re-run this script with -Purge to permanently delete." -ForegroundColor Cyan
}
