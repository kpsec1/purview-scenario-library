#Requires -Version 7.0
<#
.SYNOPSIS
    Removes the two lineage relationships and the Process entity created by
    New-CustomProcessLineage.ps1. Never touches the custom Process type definition, or the
    upstream/downstream DataSet assets.

.DESCRIPTION
    For each relationship (dataset_process_inputs, process_dataset_outputs), looks up its GUID via
    the same depth-2 Lineage - Get By Unique Attribute call the deploy script uses, then deletes it
    via Relationship - Delete. Then deletes the Process entity itself via Entity - Delete By Unique
    Attribute. A relationship or entity that's already gone (already deleted, or never
    successfully created) is reported and skipped rather than treated as an error, so this script
    is safe to re-run.

    Deliberately does NOT delete the custom Process type definition
    (PurviewScenarioLibraryEtlProcess by default) - see rollback.md "What rollback does not undo"
    for why.

    Author-only reference code. Never connects to a live tenant unless you supply real credentials
    and omit -WhatIf.

.PARAMETER PurviewAccountEndpoint
    Base URL of the Purview Data Map / Atlas v2 data-plane API. Same values as
    New-CustomProcessLineage.ps1.

.PARAMETER TenantId
    Microsoft Entra tenant ID.

.PARAMETER AppId
    Application (client) ID of the service principal. Must hold the Data Curator role on the
    collection containing the assets.

.PARAMETER ClientSecret
    Client secret for -AppId, as a SecureString.

.PARAMETER LineageDefinitionPath
    Path to the same process-lineage definition JSON file passed to New-CustomProcessLineage.ps1.

.PARAMETER ApiVersion
    Data Map / Atlas v2 REST API version to pin. Defaults to '2023-09-01'.

.PARAMETER WhatIf
    Standard PowerShell ShouldProcess dry-run - reports which relationships and the entity would
    be deleted without deleting them.

.EXAMPLE
    ./Remove-CustomProcessLineage.ps1 -PurviewAccountEndpoint 'https://api.purview-service.microsoft.com' `
        -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
        -LineageDefinitionPath './lineage/customer-risk-summary-process-lineage.json' -WhatIf

.NOTES
    Sources (Microsoft Learn, verify before production use):
    - Relationship - Delete REST reference (API version 2023-09-01; confirms
      DELETE {endpoint}/datamap/api/atlas/v2/relationship/guid/{guid}, 204 No Content on success):
      https://learn.microsoft.com/rest/api/purview/datamapdataplane/relationship/delete
    - Entity - Delete By Unique Attribute (confirmed via the .NET/Python/Java/JS Purview Data Map
      SDK method signatures - DeleteByUniqueAttribute(typeName, attribute) -
      DELETE {endpoint}/datamap/api/atlas/v2/entity/uniqueAttribute/type/{typeName}?attr:qualifiedName={qn};
      this scenario's grounding pass did not independently fetch a canonical REST-reference page
      for this specific operation with the same depth as the others (VERIFY - README.md Section 11)):
      https://learn.microsoft.com/dotnet/api/azure.analytics.purview.datamap.entity.deletebyuniqueattribute
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

# --- Look up both relationships via the same depth-2 lineage call the deploy script uses ---
$encodedUpstreamQn = [uri]::EscapeDataString($definition.upstream.qualifiedName)
$lineageUri = "$endpoint/datamap/api/atlas/v2/lineage/uniqueAttribute/type/$($definition.upstream.typeName)" +
"?api-version=$ApiVersion&direction=OUTPUT&depth=2&attr:qualifiedName=$encodedUpstreamQn"
$lineage = $null
try { $lineage = Invoke-RestMethod -Method Get -Uri $lineageUri -Headers $headers }
catch { Write-Host "[SKIP] Could not fetch lineage from '$($definition.upstream.displayName)' - it may already be disconnected. Nothing to remove." -ForegroundColor Yellow }

if ($lineage) {
    $processGuid = $lineage.guidEntityMap.PSObject.Properties |
        Where-Object { $_.Value.attributes.qualifiedName -eq $definition.process.qualifiedName } |
        Select-Object -First 1 -ExpandProperty Name
    $downstreamGuid = $lineage.guidEntityMap.PSObject.Properties |
        Where-Object { $_.Value.attributes.qualifiedName -eq $definition.downstream.qualifiedName } |
        Select-Object -First 1 -ExpandProperty Name

    $relationshipsToDelete = @(
        @{
            Description = "'$($definition.upstream.displayName)' -> '$($definition.process.displayName)' (dataset_process_inputs)"
            RelId       = ($lineage.relations | Where-Object { $_.fromEntityId -eq $lineage.baseEntityGuid -and $_.toEntityId -eq $processGuid } | Select-Object -First 1).relationshipId
        },
        @{
            Description = "'$($definition.process.displayName)' -> '$($definition.downstream.displayName)' (process_dataset_outputs)"
            RelId       = ($lineage.relations | Where-Object { $_.fromEntityId -eq $processGuid -and $_.toEntityId -eq $downstreamGuid } | Select-Object -First 1).relationshipId
        }
    )

    foreach ($rel in $relationshipsToDelete) {
        if (-not $rel.RelId) {
            Write-Host "[SKIP] $($rel.Description) - already removed, or never created." -ForegroundColor Yellow
            continue
        }
        $deleteUri = "$endpoint/datamap/api/atlas/v2/relationship/guid/$($rel.RelId)?api-version=$ApiVersion"
        if ($PSCmdlet.ShouldProcess("Relationship $($rel.RelId) ($($rel.Description))", 'DELETE')) {
            Invoke-RestMethod -Method Delete -Uri $deleteUri -Headers $headers | Out-Null
            Write-Host "[DELETED] $($rel.Description) (id: $($rel.RelId))." -ForegroundColor Green
        }
        else {
            Write-Verbose "WhatIf: would DELETE $deleteUri"
        }
    }
}

# --- Delete the Process entity itself (Entity - Delete By Unique Attribute) ---
$encodedProcessQn = [uri]::EscapeDataString($definition.process.qualifiedName)
$entityDeleteUri = "$endpoint/datamap/api/atlas/v2/entity/uniqueAttribute/type/$($definition.process.typeName)" +
"?api-version=$ApiVersion&attr:qualifiedName=$encodedProcessQn"
if ($PSCmdlet.ShouldProcess("Process entity '$($definition.process.displayName)'", 'DELETE')) {
    try {
        $result = Invoke-RestMethod -Method Delete -Uri $entityDeleteUri -Headers $headers
        if ($result.mutatedEntities.DELETE) {
            Write-Host "[DELETED] Process entity '$($definition.process.displayName)'." -ForegroundColor Green
        }
        else {
            Write-Host "[SKIP] Process entity '$($definition.process.displayName)' - already removed, or never created." -ForegroundColor Yellow
        }
    }
    catch {
        Write-Host "[SKIP] Process entity '$($definition.process.displayName)' - not found (already removed, or never created)." -ForegroundColor Yellow
    }
}
else {
    Write-Verbose "WhatIf: would DELETE $entityDeleteUri"
}

Write-Host "`nDone. The upstream/downstream assets and the custom Process type definition were not touched - see rollback.md." -ForegroundColor Cyan
