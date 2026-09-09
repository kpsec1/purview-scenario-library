#Requires -Version 7.0
<#
.SYNOPSIS
    Staged rollback for scenarios/unified-catalog/manage-okrs/: unpublish (default), unlink from
    data products (-RemoveLinks), or permanently delete the objective and its key results
    (-Purge).

.DESCRIPTION
    Three independent, additive stages - see rollback.md for the full procedure:
      1. Default: sets the objective's status back to Draft (PUT), reusing its own currently-
         stored fields (fetched via GET) so a portal-made edit isn't clobbered. Reversible -
         nothing is deleted or unlinked.
      2. -RemoveLinks: deletes every entityType=OBJECTIVE relationship the objective's linked data
         products hold (DELETE .../dataProducts/{id}/relationships?entityType=OBJECTIVE&entityId=),
         enumerated from the definition file's own relatedDataProducts list, not re-derived from
         the objective (Data Products' own List Relationships is scoped by data product, not by
         objective - there is no "list every data product this objective is linked to" call).
      3. -Purge: implies -RemoveLinks, then deletes every key result (DELETE
         .../objectives/{id}/keyResults/{keyResultId}) and finally the objective itself (DELETE
         .../objectives/{id}) - matching Microsoft's own documented manual deletion order ("first
         unpublish it and delete any key results and links to related data products").

    Author-only reference code. Never connects to a live tenant unless you supply real credentials
    and omit -WhatIf.

.PARAMETER PurviewAccountEndpoint
    Base URL of the Purview Unified Catalog data-plane API.

.PARAMETER TenantId
    Microsoft Entra tenant ID.

.PARAMETER AppId
    Application (client) ID of the service principal. Must hold Data Steward on the domain.

.PARAMETER ClientSecret
    Client secret for -AppId, as a SecureString.

.PARAMETER DefinitionPath
    Path to the same OKR definition JSON file passed to New-Okr.ps1. The objective and key result
    ids are read directly from this file (design.md Section 3) - no name lookup is performed.

.PARAMETER RemoveLinks
    Deletes the objective's data-product relationships this scenario created. Implied by -Purge.

.PARAMETER Purge
    Permanently deletes every key result, then the objective itself. Not reversible - re-creating
    it via New-Okr.ps1 with the same definition file re-creates the identical id (design.md Section
    3), unlike this repo's name-based sibling scenarios, which mint a new id on re-creation.

.PARAMETER ApiVersion
    Unified Catalog REST API version to pin. Defaults to '2026-03-20-preview'.

.PARAMETER WhatIf
    Standard PowerShell ShouldProcess dry-run.

.EXAMPLE
    ./Remove-Okr.ps1 -PurviewAccountEndpoint 'https://api.purview-service.microsoft.com' `
        -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
        -DefinitionPath './config/customer-data-trust-okr.sample.json'

    Stage 1: unpublish (set back to Draft). Reversible.

.EXAMPLE
    ./Remove-Okr.ps1 -PurviewAccountEndpoint 'https://api.purview-service.microsoft.com' `
        -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
        -DefinitionPath './config/customer-data-trust-okr.sample.json' -Purge

    Stage 3: unlink from data products, delete key results, then delete the objective.
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
        [Parameter()][switch]$ReadOnly,
        [Parameter()][switch]$TreatNotFoundAsNull
    )
    if ($Method -eq 'Get' -or $ReadOnly) {
        $params = @{ Method = $Method; Uri = $Uri; Headers = @{ Authorization = "Bearer $Token" } }
        if ($Body) {
            $params.Body = ($Body | ConvertTo-Json -Depth 10)
            $params.ContentType = 'application/json'
        }
        try { return Invoke-RestMethod @params }
        catch {
            if ($TreatNotFoundAsNull -and $_.Exception.Response -and $_.Exception.Response.StatusCode.value__ -eq 404) {
                return $null
            }
            throw
        }
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

function Find-DataProductByName {
    param([Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)][string]$DomainId, [Parameter(Mandatory)][string]$Token)
    $uri = "$endpoint/datagovernance/catalog/dataProducts/query?api-version=$ApiVersion"
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

$objectiveId = $definition.objective.id
$getUri = "$endpoint/datagovernance/catalog/objectives/$objectiveId`?api-version=$ApiVersion"
$objective = Invoke-Ucm -Method Get -Uri $getUri -Token $ucToken -TreatNotFoundAsNull
if (-not $objective) {
    Write-Host "Objective (id: $objectiveId) not found - already removed." -ForegroundColor Yellow
    exit 0
}

# --- Stage: remove data-product links ---
if ($RemoveLinks) {
    foreach ($productName in $definition.relatedDataProducts) {
        $product = Find-DataProductByName -Name $productName -DomainId $domain.id -Token $ucToken
        if (-not $product) {
            Write-Host "Data product '$productName' not found - nothing to unlink." -ForegroundColor Yellow
            continue
        }
        $deleteUri = "$endpoint/datagovernance/catalog/dataProducts/$($product.id)/relationships?api-version=$ApiVersion&entityType=OBJECTIVE&entityId=$objectiveId"
        Invoke-Ucm -Method Delete -Uri $deleteUri -Token $ucToken `
            -Description "Unlink data product '$productName' from objective (id: $objectiveId)" | Out-Null
        Write-Host "Unlinked data product '$productName' from objective '$($objective.definition)'." -ForegroundColor Green
    }
}

# --- Stage: purge (delete key results, then the objective) or default (unpublish) ---
if ($Purge) {
    foreach ($kr in $definition.keyResults) {
        $krUri = "$endpoint/datagovernance/catalog/objectives/$objectiveId/keyResults/$($kr.id)?api-version=$ApiVersion"
        Invoke-Ucm -Method Delete -Uri $krUri -Token $ucToken `
            -Description "Delete key result '$($kr.definition)'" | Out-Null
        Write-Host "Deleted key result '$($kr.definition)' (id: $($kr.id))." -ForegroundColor Green
    }
    $uri = "$endpoint/datagovernance/catalog/objectives/$objectiveId`?api-version=$ApiVersion"
    Invoke-Ucm -Method Delete -Uri $uri -Token $ucToken `
        -Description "Delete objective '$($objective.definition)'" | Out-Null
    Write-Host "Deleted objective '$($objective.definition)' (id: $objectiveId)." -ForegroundColor Green
}
else {
    if ($objective.status -ne 'Published') {
        Write-Host "Objective '$($objective.definition)' is already in $($objective.status) status." -ForegroundColor Yellow
    }
    else {
        $body = @{
            id         = $objective.id
            domain     = $objective.domain
            definition = $objective.definition
            status     = 'Draft'
            targetDate = $objective.targetDate
            contacts   = $objective.contacts
        }
        $uri = "$endpoint/datagovernance/catalog/objectives/$objectiveId`?api-version=$ApiVersion"
        Invoke-Ucm -Method Put -Uri $uri -Body $body -Token $ucToken `
            -Description "Unpublish objective '$($objective.definition)'" | Out-Null
        Write-Host "Unpublished objective '$($objective.definition)' (set back to Draft)." -ForegroundColor Green
    }
}

Write-Host "`nDone. Run validate/Test-Okr.ps1 to confirm the resulting state." -ForegroundColor Cyan
