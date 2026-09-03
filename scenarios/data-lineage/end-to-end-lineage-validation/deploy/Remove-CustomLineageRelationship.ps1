#Requires -Version 7.0
<#
.SYNOPSIS
    Removes the custom Microsoft Purview Data Map lineage relationships created by
    New-CustomLineageRelationship.ps1.

.DESCRIPTION
    For each link in the lineage definition file, looks up the upstream asset's OUTPUT lineage
    (Lineage - Get By Unique Attribute, depth 1) to find the relationship's GUID, then deletes
    that relationship via Relationship - Delete. A link with no matching relationship found is
    reported and skipped rather than treated as an error, so this script is safe to re-run.

    This script never deletes the upstream or downstream *assets* themselves - only the lineage
    relationship between them (see rollback.md "What rollback does not undo"). Neither asset was
    created by this scenario in the first place (README.md Section 3/6).

    Author-only reference code. Never connects to a live tenant unless you supply real credentials
    and omit -WhatIf.

.PARAMETER PurviewAccountEndpoint
    Base URL of the Purview Data Map / Atlas v2 data-plane API. Same two valid values as
    New-CustomLineageRelationship.ps1 - see that script's parameter help.

.PARAMETER TenantId
    Microsoft Entra tenant ID.

.PARAMETER AppId
    Application (client) ID of the service principal. Must hold the Data Curator role on the
    collection containing the two target assets.

.PARAMETER ClientSecret
    Client secret for -AppId, as a SecureString.

.PARAMETER LineageDefinitionPath
    Path to the same lineage definition JSON file passed to New-CustomLineageRelationship.ps1.

.PARAMETER ApiVersion
    Data Map / Atlas v2 REST API version to pin. Defaults to '2023-09-01'.

.PARAMETER WhatIf
    Standard PowerShell ShouldProcess dry-run - reports which relationships would be deleted
    without deleting them.

.EXAMPLE
    ./Remove-CustomLineageRelationship.ps1 -PurviewAccountEndpoint 'https://api.purview-service.microsoft.com' `
        -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
        -LineageDefinitionPath './lineage/customer-risk-summary-lineage.json' -WhatIf

.NOTES
    Sources (Microsoft Learn, verify before production use):
    - Relationship - Delete REST reference (API version 2023-09-01; confirms
      DELETE {endpoint}/datamap/api/atlas/v2/relationship/guid/{guid}, 204 No Content on success):
      https://learn.microsoft.com/rest/api/purview/datamapdataplane/relationship/delete
    - Lineage - Get By Unique Attribute REST reference (API version 2023-09-01):
      https://learn.microsoft.com/rest/api/purview/datamapdataplane/lineage/get-by-unique-attribute
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
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
    [string]$LineageDefinitionPath,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$ApiVersion = '2023-09-01'
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

$definition = Get-Content -Path $LineageDefinitionPath -Raw | ConvertFrom-Json

$plainSecret = ConvertTo-PlainText -Secure $ClientSecret
try {
    $token = Get-PurviewAccessToken -TenantId $TenantId -AppId $AppId -PlainSecret $plainSecret
}
finally {
    $plainSecret = $null
}
$headers = @{ Authorization = "Bearer $token" }

foreach ($link in $definition.customLineageLinks) {
    $encodedQn = [uri]::EscapeDataString($link.upstreamQualifiedName)
    $lineageUri = "$endpoint/datamap/api/atlas/v2/lineage/uniqueAttribute/type/$($link.upstreamTypeName)" +
    "?api-version=$ApiVersion&direction=OUTPUT&depth=1&attr:qualifiedName=$encodedQn"
    $lineage = Invoke-RestMethod -Method Get -Uri $lineageUri -Headers $headers

    $downstreamGuid = $lineage.guidEntityMap.PSObject.Properties |
        Where-Object { $_.Value.attributes.qualifiedName -eq $link.downstreamQualifiedName } |
        Select-Object -First 1 -ExpandProperty Name

    $relationshipId = $null
    if ($downstreamGuid) {
        $relationshipId = ($lineage.relations | Where-Object {
                $_.fromEntityId -eq $lineage.baseEntityGuid -and $_.toEntityId -eq $downstreamGuid
            } | Select-Object -First 1).relationshipId
    }

    if (-not $relationshipId) {
        Write-Host "[SKIP] No lineage relationship found between '$($link.upstreamDisplayName)' and '$($link.downstreamDisplayName)' - already removed, or never created." -ForegroundColor Yellow
        continue
    }

    $deleteUri = "$endpoint/datamap/api/atlas/v2/relationship/guid/$relationshipId?api-version=$ApiVersion"
    if ($PSCmdlet.ShouldProcess("Relationship $relationshipId ('$($link.upstreamDisplayName)' -> '$($link.downstreamDisplayName)')", 'DELETE')) {
        Invoke-RestMethod -Method Delete -Uri $deleteUri -Headers $headers | Out-Null
        Write-Host "[DELETED] Lineage relationship '$($link.upstreamDisplayName)' -> '$($link.downstreamDisplayName)' (id: $relationshipId)." -ForegroundColor Green
    }
    else {
        Write-Verbose "WhatIf: would DELETE $deleteUri"
    }
}

Write-Host "`nDone. The upstream and downstream assets themselves were not touched - see rollback.md." -ForegroundColor Cyan
