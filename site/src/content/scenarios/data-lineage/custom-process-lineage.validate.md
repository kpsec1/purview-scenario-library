---
part: "validate"
parent: "data-lineage/custom-process-lineage"
---
Run these checks after deployment to confirm the control is working as designed.


#### `Test-ProcessLineage.ps1`

```powershell
#Requires -Version 7.0
<#
.SYNOPSIS
    Read-only validation that the DataSet -> Process -> DataSet lineage chain
    New-CustomProcessLineage.ps1 builds is actually intact: the custom Process type exists, the
    Process entity exists with its expected attributes, and both hops are walkable in order.

.DESCRIPTION
    Four checks, none of them mutating:
      1. Type - Get Entity Def By Name confirms the custom Process type definition exists, AND
         that its live attribute set matches this scenario's definition file - the deploy script's
         own existence check only asks "does a type with this name exist" before skipping Type -
         Bulk Create (never reconciling shape), so a type edited out-of-band (attribute renamed or
         removed) would otherwise drift silently. This check catches that drift; it does not fix
         it - see the inline comment above it for why.
      2. A single Lineage - Get By Unique Attribute call (direction OUTPUT, depth 2, from the
         upstream asset) returns the whole two-hop graph in one round trip.
      3. From that one response: confirms the Process entity is present AND reachable from the
         upstream asset by a walkable edge (not just co-listed), confirms the downstream asset is
         present AND reachable via the Process node specifically (two hops, in the right order -
         not merely "somewhere in the graph"), and confirms the Process entity's columnMapping
         attribute survived (this attribute is directly present in Microsoft's own worked Get
         Lineage response example for a Process-typed entity - README.md reference 5's "View
         lineage" JSON sample for HiveQuery1 - so this is checked as a hard PASS/FAIL, not a soft
         warning, unlike the sibling end-to-end-lineage-validation scenario's relation-level
         columnMapping check, which isn't in the formally documented schema).
    Exits with a non-zero code if any hard check fails, so this script is safe to wire into a
    CI-style pre-flight or a recurring scheduled lineage-health check (README.md Section 8). Safe
    to re-run any number of times.

.PARAMETER PurviewAccountEndpoint
    Base URL of the Purview Data Map / Atlas v2 data-plane API.

.PARAMETER TenantId
    Microsoft Entra tenant ID.

.PARAMETER AppId
    Application (client) ID of a service principal holding at least the Data Reader role on the
    collection containing the target assets - deliberately narrower than the Data Curator role
    the deploy script needs, per this repo's least-privilege convention for validate/ scripts.

.PARAMETER ClientSecret
    Client secret for -AppId, as a SecureString.

.PARAMETER LineageDefinitionPath
    Path to the same process-lineage definition JSON file passed to New-CustomProcessLineage.ps1.

.PARAMETER ApiVersion
    Data Map / Atlas v2 REST API version to pin. Defaults to '2023-09-01'.

.EXAMPLE
    ./Test-ProcessLineage.ps1 -PurviewAccountEndpoint 'https://api.purview-service.microsoft.com' `
        -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
        -LineageDefinitionPath '../deploy/lineage/customer-risk-summary-process-lineage.json'

.NOTES
    Sources (Microsoft Learn, verify before production use):
    - Type - Get Entity Def By Name REST reference (API version 2023-09-01):
      https://learn.microsoft.com/rest/api/purview/datamapdataplane/type/get-entity-def-by-name
    - Lineage - Get By Unique Attribute REST reference (API version 2023-09-01):
      https://learn.microsoft.com/rest/api/purview/datamapdataplane/lineage/get-by-unique-attribute
    - Create and get lineage relationships using the REST API (worked Get Lineage response example
      showing the columnMapping entity attribute survives on a Process-typed node):
      https://learn.microsoft.com/purview/data-gov-api-create-lineage-relationships
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
    [string]$LineageDefinitionPath,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$ApiVersion = '2023-09-01'
)

$ErrorActionPreference = 'Stop'
$script:failures = 0
$endpoint = $PurviewAccountEndpoint.TrimEnd('/')

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
foreach ($required in 'processTypeDefinition', 'process', 'upstream', 'downstream') {
    if (-not $definition.$required) {
        throw "Definition file '$LineageDefinitionPath' is missing required field '$required'."
    }
}

$plainSecret = ConvertTo-PlainText -Secure $ClientSecret
try {
    $token = Get-PurviewAccessToken -TenantId $TenantId -AppId $AppId -PlainSecret $plainSecret
}
finally {
    $plainSecret = $null
}
$headers = @{ Authorization = "Bearer $token" }

Write-Host "Validating DataSet -> Process -> DataSet lineage from '$($definition.upstream.displayName)' through '$($definition.process.displayName)' to '$($definition.downstream.displayName)'..." -ForegroundColor Cyan

# --- Check 1: the custom Process type definition exists ---
$typeName = $definition.processTypeDefinition.name
$typeUri = "$endpoint/datamap/api/atlas/v2/types/entitydef/name/$typeName`?api-version=$ApiVersion"
$liveTypeDef = $null
try { $liveTypeDef = Invoke-RestMethod -Method Get -Uri $typeUri -Headers $headers }
catch { $liveTypeDef = $null }
Test-Check -Description "Custom Process type '$typeName' exists" -Condition ($null -ne $liveTypeDef)

# --- Schema-drift check: the deploy script's existence check only asks "does a type with this
# NAME exist" before skipping Type - Bulk Create (its own reference page warns against
# recreating existing types, so it never re-submits the shape to reconcile it - deploy script
# .NOTES). That means a type edited out-of-band (e.g. an attribute renamed or removed directly in
# the portal, or by a different script) would silently diverge from this definition file with
# nothing flagging it - a genuine blind spot raised in this scenario's Blue Team/Product Owner
# review (reviews.md) and closed by this check, which the deploy script itself deliberately does
# NOT perform (it only checks existence, never reconciles shape - staying inside the confirmed
# upsert/create semantics rather than guessing at an unconfirmed "update type" body).
if ($liveTypeDef) {
    $expectedAttrNames = @($definition.processTypeDefinition.attributeDefs | ForEach-Object { $_.name }) | Sort-Object
    $liveAttrNames = @($liveTypeDef.attributeDefs | ForEach-Object { $_.name }) | Sort-Object
    $attrsMatch = @(Compare-Object -ReferenceObject $expectedAttrNames -DifferenceObject $liveAttrNames -SyncWindow 0).Count -eq 0
    Test-Check -Description "Live type '$typeName' attribute set matches the definition file (no undetected schema drift)" `
        -Condition $attrsMatch
    if (-not $attrsMatch) {
        Write-Host "         Expected attributes: $($expectedAttrNames -join ', ')  |  Live attributes: $($liveAttrNames -join ', ')" -ForegroundColor Yellow
        Write-Host "         This script does not attempt to reconcile the drift - Type - Bulk Create's own reference page warns against recreating existing types, and no 'update an existing type definition' body was confirmed in this scenario's grounding pass. Reconcile manually, or via a fresh Type - Bulk Create only after confirming its update semantics against a pilot tenant." -ForegroundColor Yellow
    }
}

# --- Checks 2+: the two-hop lineage graph, fetched in one call ---
$encodedUpstreamQn = [uri]::EscapeDataString($definition.upstream.qualifiedName)
$lineageUri = "$endpoint/datamap/api/atlas/v2/lineage/uniqueAttribute/type/$($definition.upstream.typeName)" +
"?api-version=$ApiVersion&direction=OUTPUT&depth=2&attr:qualifiedName=$encodedUpstreamQn"

$lineage = $null
try { $lineage = Invoke-RestMethod -Method Get -Uri $lineageUri -Headers $headers }
catch {
    Test-Check -Description "Upstream asset '$($definition.upstream.displayName)' reachable via Lineage - Get By Unique Attribute" -Condition $false
    Write-Host "`n$script:failures check(s) failed - cannot continue without the upstream asset's lineage graph. Confirm the upstream qualifiedName in '$LineageDefinitionPath' is current." -ForegroundColor Red
    exit 1
}

$upstreamGuid = $lineage.baseEntityGuid
$processGuid = $lineage.guidEntityMap.PSObject.Properties |
    Where-Object { $_.Value.attributes.qualifiedName -eq $definition.process.qualifiedName } |
    Select-Object -First 1 -ExpandProperty Name
$downstreamGuid = $lineage.guidEntityMap.PSObject.Properties |
    Where-Object { $_.Value.attributes.qualifiedName -eq $definition.downstream.qualifiedName } |
    Select-Object -First 1 -ExpandProperty Name

Test-Check -Description "Process entity '$($definition.process.displayName)' present within depth 2" -Condition ($null -ne $processGuid)

$inputsRelation = if ($processGuid) {
    $lineage.relations | Where-Object { $_.fromEntityId -eq $upstreamGuid -and $_.toEntityId -eq $processGuid } | Select-Object -First 1
}
Test-Check -Description "'$($definition.upstream.displayName)' -> '$($definition.process.displayName)' is a walkable edge (dataset_process_inputs)" `
    -Condition ($null -ne $inputsRelation)

Test-Check -Description "Downstream asset '$($definition.downstream.displayName)' present within depth 2" -Condition ($null -ne $downstreamGuid)

$outputsRelation = if ($processGuid -and $downstreamGuid) {
    $lineage.relations | Where-Object { $_.fromEntityId -eq $processGuid -and $_.toEntityId -eq $downstreamGuid } | Select-Object -First 1
}
Test-Check -Description "'$($definition.process.displayName)' -> '$($definition.downstream.displayName)' is a walkable edge (process_dataset_outputs)" `
    -Condition ($null -ne $outputsRelation)

if (-not $processGuid -or -not $inputsRelation -or -not $outputsRelation) {
    Write-Host "         Most likely cause: New-CustomProcessLineage.ps1 hasn't been run yet (or only partially completed); the process/upstream/downstream qualifiedName values in '$LineageDefinitionPath' are stale; or the Process entity/either relationship was deleted (deliberately via Remove-CustomProcessLineage.ps1, or otherwise)." -ForegroundColor Yellow
}

# --- Check: the Process entity's columnMapping attribute survived ---
if ($processGuid) {
    $processNode = $lineage.guidEntityMap.$processGuid
    Test-Check -Description "Process entity '$($definition.process.displayName)' carries a non-empty columnMapping attribute" `
        -Condition (-not [string]::IsNullOrWhiteSpace($processNode.attributes.columnMapping))
}

Write-Host "`n$(if ($script:failures -eq 0) { 'All hard checks passed - the DataSet -> Process -> DataSet chain is connected end-to-end.' } else { "$script:failures hard check(s) failed - see the guidance above." })" `
    -ForegroundColor $(if ($script:failures -eq 0) { 'Green' } else { 'Red' })

if ($script:failures -gt 0) { exit 1 }
```