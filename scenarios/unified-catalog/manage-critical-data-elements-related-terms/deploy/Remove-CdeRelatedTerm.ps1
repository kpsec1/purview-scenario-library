#Requires -Version 7.0
<#
.SYNOPSIS
    Unlinks one or more glossary terms from a Microsoft Purview Unified Catalog critical data
    element (CDE) - the reverse of Add-CdeRelatedTerm.ps1.

.DESCRIPTION
    Two modes, both additive-safe (never deletes the term, the critical data element, or the
    governance domain - see rollback.md):
      1. Default (no -TermNames, no -RemoveAll): unlinks exactly the terms listed in the
         definition file's own 'relatedTerms' array - "undo what Add-CdeRelatedTerm.ps1 would have
         added" - resolving each by name fresh rather than trusting a cached ID.
      2. -TermNames <string[]>: unlinks only the named term(s), regardless of what the definition
         file's 'relatedTerms' array contains - useful for removing a single mistaken link without
         touching the rest.
      3. -RemoveAll: unlinks every entityType=TERM relationship the critical data element
         currently has, enumerated live from the API - not re-derived from the definition file, so
         this also cleans up a term linked outside this scenario's scripts (e.g. via the portal's
         own "+ Add term" button or the reciprocal "Add critical data element" button on a term's
         own Related tab). The same discipline
         scenarios/unified-catalog/manage-critical-data-elements/deploy/Remove-CriticalDataElement.ps1's
         own -RemoveLinks uses for its DATACOLUMN relationships.

    Run this before scenarios/unified-catalog/manage-critical-data-elements/deploy/
    Remove-CriticalDataElement.ps1 -Purge if the CDE has any related terms - Microsoft's own
    documented delete prerequisite for a critical data element is "unpublish it and delete all
    columns within it, and any links to glossary terms" (README.md Section 1), and the sibling
    scenario's own -Purge does not remove TERM relationships (it predates this scenario - see
    rollback.md).

    CAUTION - unlinking is not purely metadata cleanup: if a term carries its own access policy,
    README.md Section 2 documents that policy as inheriting onto every data product the CDE
    touches. Removing the link may loosen that aggregated requirement - see the Write-Warning this
    script prints before every unlink and rollback.md's own caution.

    Author-only reference code. Never connects to a live tenant unless you supply real credentials
    and omit -WhatIf.

.PARAMETER PurviewAccountEndpoint
    Base URL of the Purview Unified Catalog data-plane API.

.PARAMETER TenantId
    Microsoft Entra tenant ID.

.PARAMETER AppId
    Application (client) ID of the service principal. Must hold at least Data Steward on the
    domain.

.PARAMETER ClientSecret
    Client secret for -AppId, as a SecureString.

.PARAMETER DefinitionPath
    Path to the same related-terms definition JSON file passed to Add-CdeRelatedTerm.ps1.

.PARAMETER TermNames
    Optional. Unlink only these term name(s), instead of the definition file's own 'relatedTerms'
    array. Ignored if -RemoveAll is supplied.

.PARAMETER RemoveAll
    Unlinks every entityType=TERM relationship the critical data element currently has, enumerated
    live rather than from the definition file or -TermNames.

.PARAMETER ApiVersion
    Unified Catalog REST API version to pin. Defaults to '2026-03-20-preview'.

.PARAMETER WhatIf
    Standard PowerShell ShouldProcess dry-run.

.EXAMPLE
    ./Remove-CdeRelatedTerm.ps1 -PurviewAccountEndpoint 'https://api.purview-service.microsoft.com' `
        -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
        -DefinitionPath './config/customer-id-related-terms.sample.json'

    Unlinks the terms listed in the definition file's 'relatedTerms' array.

.EXAMPLE
    ./Remove-CdeRelatedTerm.ps1 -PurviewAccountEndpoint 'https://api.purview-service.microsoft.com' `
        -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
        -DefinitionPath './config/customer-id-related-terms.sample.json' -RemoveAll

    Unlinks every term currently linked to the critical data element, regardless of source -
    the prerequisite step before the sibling scenario's -Purge.

.NOTES
    entityType=TERM is used for the relationship delete calls, the same EntityCategory value
    Add-CdeRelatedTerm.ps1 uses to create them (design.md Section 3) - unlike
    scenarios/unified-catalog/manage-critical-data-elements/'s own entityType=DATACOLUMN choice,
    TERM has no documented enum-vs-worked-example discrepancy to flag (README.md Section 12).
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
    [string[]]$TermNames,

    [Parameter()]
    [switch]$RemoveAll,

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
        [Parameter(Mandatory)][ValidateSet('Get', 'Post', 'Delete')][string]$Method,
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

function Find-CriticalDataElementByName {
    param([Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)][string]$DomainId, [Parameter(Mandatory)][string]$Token)
    $uri = "$endpoint/datagovernance/catalog/criticalDataElements/query?api-version=$ApiVersion"
    $body = @{ domainIds = @($DomainId); nameKeyword = $Name; top = 50 }
    $response = Invoke-Ucm -Method Post -Uri $uri -Body $body -Token $Token -ReadOnly
    return ($response.value | Where-Object { $_.name -eq $Name } | Select-Object -First 1)
}

function Find-TermByName {
    param([Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)][string]$DomainId, [Parameter(Mandatory)][string]$Token)
    $uri = "$endpoint/datagovernance/catalog/terms/query?api-version=$ApiVersion"
    $body = @{ domainIds = @($DomainId); nameKeyword = $Name; top = 50 }
    $response = Invoke-Ucm -Method Post -Uri $uri -Body $body -Token $Token -ReadOnly
    return ($response.value | Where-Object { $_.name -eq $Name } | Select-Object -First 1)
}

# --- Load the definition file ---
$definition = Get-Content -Path $DefinitionPath -Raw | ConvertFrom-Json

$plainSecret = ConvertTo-PlainText -Secure $ClientSecret
try { $ucToken = Get-PurviewAccessToken -TenantId $TenantId -AppId $AppId -PlainSecret $plainSecret }
finally { $plainSecret = $null }

$domain = Find-BusinessDomainByName -Name $definition.domain.name -Token $ucToken
if (-not $domain) { throw "Governance domain '$($definition.domain.name)' was not found. Nothing to roll back." }

$cde = Find-CriticalDataElementByName -Name $definition.criticalDataElement.name -DomainId $domain.id -Token $ucToken
if (-not $cde) {
    Write-Host "Critical data element '$($definition.criticalDataElement.name)' not found - nothing to unlink." -ForegroundColor Yellow
    exit 0
}

Write-Warning "Unlinking a term is not purely metadata cleanup: if the term carries its own access policy (e.g. a manager-approval requirement), README.md Section 2 documents that policy as inheriting/aggregating onto every data product the CDE's mapped columns touch. Removing the link may loosen that aggregated requirement on downstream data products - this script cannot verify Microsoft's platform re-evaluates that aggregation, or when (rollback.md)."

$entityType = 'TERM'
$relUri = "$endpoint/datagovernance/catalog/criticalDataElements/$($cde.id)/relationships?api-version=$ApiVersion&entityType=$entityType"
$relationships = Invoke-Ucm -Method Get -Uri $relUri -Token $ucToken

if ($RemoveAll) {
    $targets = @($relationships.value)
    if ($targets.Count -eq 0) {
        Write-Host "No term relationships found for '$($cde.name)' (entityType=$entityType)." -ForegroundColor Yellow
    }
    foreach ($rel in $targets) {
        $deleteUri = "$endpoint/datagovernance/catalog/criticalDataElements/$($cde.id)/relationships?api-version=$ApiVersion&entityType=$entityType&entityId=$($rel.entityId)"
        Invoke-Ucm -Method Delete -Uri $deleteUri -Token $ucToken -Description "Unlink term (term id: $($rel.entityId)) from '$($cde.name)'" | Out-Null
        Write-Host "Unlinked term (term id: $($rel.entityId)) from '$($cde.name)'." -ForegroundColor Green
    }
}
else {
    $namesToRemove = if ($TermNames -and $TermNames.Count -gt 0) { $TermNames } else { @($definition.relatedTerms) }
    foreach ($termName in $namesToRemove) {
        $term = Find-TermByName -Name $termName -DomainId $domain.id -Token $ucToken
        if (-not $term) {
            Write-Warning "Term '$termName' was not found in domain '$($domain.name)'. Nothing to unlink."
            continue
        }
        $isLinked = [bool]($relationships.value | Where-Object { $_.entityId -eq $term.id })
        if (-not $isLinked) {
            Write-Host "'$($cde.name)' is not linked to term '$termName' - nothing to unlink." -ForegroundColor Yellow
            continue
        }
        $deleteUri = "$endpoint/datagovernance/catalog/criticalDataElements/$($cde.id)/relationships?api-version=$ApiVersion&entityType=$entityType&entityId=$($term.id)"
        Invoke-Ucm -Method Delete -Uri $deleteUri -Token $ucToken -Description "Unlink term '$termName' from '$($cde.name)'" | Out-Null
        Write-Host "Unlinked term '$termName' from '$($cde.name)'." -ForegroundColor Green
    }
}

Write-Host "`nDone. Run validate/Test-CdeRelatedTerms.ps1 to confirm the resulting state." -ForegroundColor Cyan
