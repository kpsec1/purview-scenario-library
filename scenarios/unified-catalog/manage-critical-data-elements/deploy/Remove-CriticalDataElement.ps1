#Requires -Version 7.0
<#
.SYNOPSIS
    Staged rollback for scenarios/unified-catalog/manage-critical-data-elements/: unpublish
    (default), unmap columns (-RemoveLinks), or permanently delete (-Purge) the critical data
    element this scenario created.

.DESCRIPTION
    Three independent, additive stages - see rollback.md for the full procedure:
      1. Default: sets the critical data element's status back to DRAFT (PUT), reusing its own
         currently-stored fields (fetched via GET) so a portal-made edit isn't clobbered.
         Reversible - nothing is deleted or unmapped.
      2. -RemoveLinks: also deletes the CDE-to-column relationships this scenario's
         New-CriticalDataElement.ps1 created (DELETE .../criticalDataElements/{id}/relationships).
         The underlying Unified Catalog data column wrapper objects are NOT deleted - as of the
         2026-03-20-preview API version, the Data Columns operation group has no Delete operation
         at all (design.md Section 7 / non-goals), so an unmapped wrapper is left in place; it is
         inert (not billed - README.md Section 10) once nothing references it.
      3. -Purge: implies -RemoveLinks, then deletes the critical data element itself
         (DELETE .../criticalDataElements/{id}). Never deletes the underlying Data Map asset,
         the governance domain, or any data column wrapper.

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
    Path to the same critical data element definition JSON file passed to
    New-CriticalDataElement.ps1. Column GUID resolution against Data Map is not required for
    rollback - relationships are enumerated directly from the critical data element's own
    DATACOLUMN relationships rather than re-resolved from the definition file.

.PARAMETER RemoveLinks
    Deletes the CDE-to-column relationships this scenario created. Implied by -Purge.

.PARAMETER Purge
    Permanently deletes the critical data element (after removing its column links). Not
    reversible - re-creating it via New-CriticalDataElement.ps1 generates a new element ID.

.PARAMETER ApiVersion
    Unified Catalog REST API version to pin. Defaults to '2026-03-20-preview'.

.PARAMETER WhatIf
    Standard PowerShell ShouldProcess dry-run.

.EXAMPLE
    ./Remove-CriticalDataElement.ps1 -PurviewAccountEndpoint 'https://api.purview-service.microsoft.com' `
        -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
        -DefinitionPath './config/customer-id-cde.sample.json'

    Stage 1: unpublish (set back to DRAFT). Reversible.

.EXAMPLE
    ./Remove-CriticalDataElement.ps1 -PurviewAccountEndpoint 'https://api.purview-service.microsoft.com' `
        -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
        -DefinitionPath './config/customer-id-cde.sample.json' -Purge

    Stage 3: unmap columns, then permanently delete the critical data element.

.NOTES
    entityType=DATACOLUMN is used for the relationship delete calls, matching
    New-CriticalDataElement.ps1's own choice - see that script's .NOTES and design.md Section 6
    for the CRITICALDATACOLUMN-vs-DATACOLUMN discrepancy this repo's grounding pass found.
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

# --- Load the definition file ---
$definition = Get-Content -Path $DefinitionPath -Raw | ConvertFrom-Json

$plainSecret = ConvertTo-PlainText -Secure $ClientSecret
try { $ucToken = Get-PurviewAccessToken -TenantId $TenantId -AppId $AppId -PlainSecret $plainSecret }
finally { $plainSecret = $null }

$domain = Find-BusinessDomainByName -Name $definition.domain.name -Token $ucToken
if (-not $domain) { throw "Governance domain '$($definition.domain.name)' was not found. Nothing to roll back." }

$cde = Find-CriticalDataElementByName -Name $definition.criticalDataElement.name -DomainId $domain.id -Token $ucToken
if (-not $cde) {
    Write-Host "Critical data element '$($definition.criticalDataElement.name)' not found - already removed." -ForegroundColor Yellow
    exit 0
}

# --- Stage: remove links ---
if ($RemoveLinks) {
    $entityType = 'DATACOLUMN'
    $relUri = "$endpoint/datagovernance/catalog/criticalDataElements/$($cde.id)/relationships?api-version=$ApiVersion&entityType=$entityType"
    $relationships = Invoke-Ucm -Method Get -Uri $relUri -Token $ucToken
    foreach ($rel in @($relationships.value)) {
        $deleteUri = "$endpoint/datagovernance/catalog/criticalDataElements/$($cde.id)/relationships?api-version=$ApiVersion&entityType=$entityType&entityId=$($rel.entityId)"
        Invoke-Ucm -Method Delete -Uri $deleteUri -Token $ucToken -Description "Unmap column (data column id: $($rel.entityId)) from '$($cde.name)'" | Out-Null
        Write-Host "Unmapped column (data column id: $($rel.entityId)) from '$($cde.name)'." -ForegroundColor Green
    }
    if (-not $relationships.value -or $relationships.value.Count -eq 0) {
        Write-Host "No mapped columns found for '$($cde.name)' (entityType=$entityType)." -ForegroundColor Yellow
    }
    Write-Host "Note: the underlying Unified Catalog data column wrapper object(s) are not deleted - the Data Columns operation group has no Delete operation as of api-version $ApiVersion (rollback.md)." -ForegroundColor Cyan
}

# --- Stage: purge (delete the CDE) or default (unpublish) ---
if ($Purge) {
    $uri = "$endpoint/datagovernance/catalog/criticalDataElements/$($cde.id)?api-version=$ApiVersion"
    Invoke-Ucm -Method Delete -Uri $uri -Token $ucToken -Description "Delete critical data element '$($cde.name)'" | Out-Null
    Write-Host "Deleted critical data element '$($cde.name)' (id: $($cde.id))." -ForegroundColor Green
}
else {
    if ($cde.status -ne 'PUBLISHED') {
        Write-Host "Critical data element '$($cde.name)' is already in $($cde.status) status." -ForegroundColor Yellow
    }
    else {
        $body = @{
            id          = $cde.id
            domain      = $cde.domain
            name        = $cde.name
            status      = 'DRAFT'
            dataType    = $cde.dataType
            description = $cde.description
            contacts    = $cde.contacts
        }
        $uri = "$endpoint/datagovernance/catalog/criticalDataElements/$($cde.id)?api-version=$ApiVersion"
        Invoke-Ucm -Method Put -Uri $uri -Body $body -Token $ucToken `
            -Description "Unpublish critical data element '$($cde.name)'" | Out-Null
        Write-Host "Unpublished critical data element '$($cde.name)' (set back to DRAFT)." -ForegroundColor Green
    }
}

Write-Host "`nDone. Run validate/Test-CriticalDataElement.ps1 to confirm the resulting state." -ForegroundColor Cyan
