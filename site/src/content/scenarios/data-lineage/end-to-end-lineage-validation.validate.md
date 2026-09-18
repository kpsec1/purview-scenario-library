---
part: "validate"
parent: "data-lineage/end-to-end-lineage-validation"
---
Run these checks after deployment to confirm the control is working as designed.


#### `Test-EndToEndLineage.ps1`

```powershell
#Requires -Version 7.0
<#
.SYNOPSIS
    Walks the Microsoft Purview lineage graph from an origin asset and proves - not just assumes -
    that every asset in the expected downstream chain is actually reachable, with no broken hops.

.DESCRIPTION
    Read-only validation script - never modifies any object. This is the "end-to-end lineage
    validation" this scenario is named for: creating a lineage link (deploy/) proves that one hop
    exists; this script proves the *whole chain*, from the origin asset all the way to every
    asset named in the definition file's expectedDownstreamChain, is connected - which is the
    actual question a root-cause or impact-analysis investigation depends on (README.md Section 2).

    Calls Lineage - Get By Unique Attribute on the origin asset with direction=OUTPUT and a depth
    large enough to cover the full expected chain, then:
      1. Confirms every asset in expectedDownstreamChain appears in the returned guidEntityMap
         (reachable within the traversed graph at all).
      2. Confirms a connected path exists from the origin to each expected asset by walking the
         returned relations edges (breadth-first from baseEntityGuid) - presence in
         guidEntityMap alone is not proof of connectivity, since Get Lineage can return entities
         reached via multiple paths or (per the API's own response shape) entities present without
         a directly walkable edge in unusual graph shapes.
      3. For each link in customLineageLinks (the custom lineage this scenario's deploy script is
         responsible for), confirms the specific relation carries a non-empty columnMapping
         attribute - proof this is the deliberately-authored custom link, not a coincidentally
         similar one, and that column-level (not just table-level) traceability survived.
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
    Path to the same lineage definition JSON file passed to New-CustomLineageRelationship.ps1.

.PARAMETER MaxDepth
    Maximum lineage hops to traverse from the origin asset. Defaults to 10 - generous for the
    single-hop chain in the shipped example file, override for a longer real-world chain.

.PARAMETER ApiVersion
    Data Map / Atlas v2 REST API version to pin. Defaults to '2023-09-01'.

.EXAMPLE
    ./Test-EndToEndLineage.ps1 -PurviewAccountEndpoint 'https://api.purview-service.microsoft.com' `
        -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
        -LineageDefinitionPath '../deploy/lineage/customer-risk-summary-lineage.json'

.NOTES
    A [FAIL] on the "connected by a walkable path" check (an asset present in guidEntityMap but
    not reachable via relations from the origin) is an unambiguous topology gap - -MaxDepth cannot
    explain it, since the asset already had to be within the requested depth to appear in
    guidEntityMap at all. A [FAIL] on the "present in the lineage graph" check is ambiguous between
    a genuine gap and -MaxDepth being too shallow - the script's guidance for that case names both
    possibilities; increase -MaxDepth before concluding the link is missing.

    The columnMapping field this script reads from a relations entry is confirmed present in
    Microsoft's own worked Get Lineage response example (README.md reference 5's "View lineage"
    JSON sample), but is not listed in the formally documented LineageRelation object's field
    table on the canonical Lineage - Get REST reference page (README.md reference 12) - a minor
    gap between the worked example and the formal schema definition. This script treats its
    absence as a soft warning (-Warn), never a hard failure, for exactly this reason.

    Sources (Microsoft Learn, verify before production use):
    - Lineage - Get By Unique Attribute REST reference (API version 2023-09-01):
      https://learn.microsoft.com/rest/api/purview/datamapdataplane/lineage/get-by-unique-attribute
    - Create and get lineage relationships using the REST API (worked Get Lineage response example
      showing columnMapping on a relations entry):
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
    [ValidateRange(1, 50)]
    [int]$MaxDepth = 10,

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

function Find-ConnectedGuids {
    # Breadth-first walk of the OUTPUT relations edges starting at the origin's own GUID, so
    # "reachable" means an actual walkable path exists, not just co-presence in guidEntityMap.
    param([Parameter(Mandatory)][pscustomobject]$Lineage)
    $visited = [System.Collections.Generic.HashSet[string]]::new()
    $queue = [System.Collections.Generic.Queue[string]]::new()
    [void]$visited.Add($Lineage.baseEntityGuid)
    $queue.Enqueue($Lineage.baseEntityGuid)
    while ($queue.Count -gt 0) {
        $current = $queue.Dequeue()
        foreach ($rel in ($Lineage.relations | Where-Object { $_.fromEntityId -eq $current })) {
            if ($visited.Add($rel.toEntityId)) { $queue.Enqueue($rel.toEntityId) }
        }
    }
    return $visited
}

$definition = Get-Content -Path $LineageDefinitionPath -Raw | ConvertFrom-Json
foreach ($required in 'originAssetQualifiedName', 'originAssetTypeName') {
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

Write-Host "Validating end-to-end lineage from '$($definition.originAssetDisplayName)' (depth $MaxDepth, direction OUTPUT)..." -ForegroundColor Cyan

# --- Fetch the full downstream lineage graph from the origin in one call ---
$encodedQn = [uri]::EscapeDataString($definition.originAssetQualifiedName)
$lineageUri = "$endpoint/datamap/api/atlas/v2/lineage/uniqueAttribute/type/$($definition.originAssetTypeName)" +
"?api-version=$ApiVersion&direction=OUTPUT&depth=$MaxDepth&attr:qualifiedName=$encodedQn"

$lineage = $null
try { $lineage = Invoke-RestMethod -Method Get -Uri $lineageUri -Headers $headers }
catch {
    Test-Check -Description "Origin asset '$($definition.originAssetDisplayName)' reachable via Lineage - Get By Unique Attribute" -Condition $false
    Write-Host "`n$script:failures check(s) failed - cannot continue without the origin asset's lineage graph. Confirm originAssetQualifiedName/originAssetTypeName in '$LineageDefinitionPath' are current." -ForegroundColor Red
    exit 1
}

Test-Check -Description "Origin asset '$($definition.originAssetDisplayName)' has at least one downstream (OUTPUT) lineage relation" `
    -Condition ($lineage.relations.Count -gt 0)

$connected = Find-ConnectedGuids -Lineage $lineage

# --- Check 1: every asset in the expected downstream chain is present AND connected ---
foreach ($expected in $definition.expectedDownstreamChain) {
    $match = $lineage.guidEntityMap.PSObject.Properties |
        Where-Object { $_.Value.attributes.qualifiedName -eq $expected.qualifiedName } |
        Select-Object -First 1

    Test-Check -Description "'$($expected.displayName)' present in the lineage graph within depth $MaxDepth" `
        -Condition ($null -ne $match)

    if ($match) {
        Test-Check -Description "'$($expected.displayName)' is connected to '$($definition.originAssetDisplayName)' by a walkable path (not just co-present)" `
            -Condition ($connected.Contains($match.Name))
    }
    else {
        Write-Host "         Most likely cause: the custom lineage link that should connect this asset was never created (re-run deploy/New-CustomLineageRelationship.ps1); this asset's qualifiedName in '$LineageDefinitionPath' is stale (re-copy it from the portal); or -MaxDepth ($MaxDepth) is too shallow to reach it if this asset sits further downstream than the shipped example's single hop - try increasing it before concluding the link is genuinely missing." -ForegroundColor Yellow
    }
}

# --- Check 2: each custom link's column-level mapping actually made it onto the relationship ---
# Resolves the relation edge from the link's own declared upstream node, not always the origin
# asset (baseEntityGuid) - this generalizes the check to a multi-hop chain where a
# customLineageLinks entry's upstream sits further downstream than the origin's immediate output,
# not just the shipped example's single-hop case where upstream IS the origin asset. The origin
# asset resolves directly to the already-known baseEntityGuid (no lookup needed, no new API
# assumption introduced); any other upstream node is resolved the same way Check 1 already
# resolves expectedDownstreamChain entries - by matching guidEntityMap on qualifiedName.
foreach ($link in $definition.customLineageLinks) {
    if ($link.upstreamQualifiedName -eq $definition.originAssetQualifiedName) {
        $upstreamGuid = $lineage.baseEntityGuid
    }
    else {
        $upstreamGuid = $lineage.guidEntityMap.PSObject.Properties |
            Where-Object { $_.Value.attributes.qualifiedName -eq $link.upstreamQualifiedName } |
            Select-Object -First 1 -ExpandProperty Name
    }

    $downstreamGuid = $lineage.guidEntityMap.PSObject.Properties |
        Where-Object { $_.Value.attributes.qualifiedName -eq $link.downstreamQualifiedName } |
        Select-Object -First 1 -ExpandProperty Name

    if (-not $upstreamGuid) {
        Test-Check -Description "Custom link '$($link.upstreamDisplayName)' -> '$($link.downstreamDisplayName)' exists" -Condition $false
        Write-Host "         Upstream node '$($link.upstreamDisplayName)' is not present in the traversed graph - either it is not reachable from the origin within depth $MaxDepth (try increasing -MaxDepth), or its upstreamQualifiedName in '$LineageDefinitionPath' is stale." -ForegroundColor Yellow
        continue
    }

    if (-not $downstreamGuid) {
        Test-Check -Description "Custom link '$($link.upstreamDisplayName)' -> '$($link.downstreamDisplayName)' exists" -Condition $false
        continue
    }

    $relation = $lineage.relations | Where-Object {
        $_.fromEntityId -eq $upstreamGuid -and $_.toEntityId -eq $downstreamGuid
    } | Select-Object -First 1

    Test-Check -Description "Custom link '$($link.upstreamDisplayName)' -> '$($link.downstreamDisplayName)' exists" `
        -Condition ($null -ne $relation)

    if ($relation -and $link.columnMapping) {
        Test-Check -Description "Custom link '$($link.upstreamDisplayName)' -> '$($link.downstreamDisplayName)' carries a column-level mapping" `
            -Condition (-not [string]::IsNullOrWhiteSpace($relation.columnMapping)) -Warn
    }
}

Write-Host "`n$(if ($script:failures -eq 0) { 'All hard checks passed - the graph is connected end-to-end within the traversed depth.' } else { "$script:failures hard check(s) failed - the lineage graph has a gap. See the guidance above each failed check." })" `
    -ForegroundColor $(if ($script:failures -eq 0) { 'Green' } else { 'Red' })

if ($script:failures -gt 0) { exit 1 }
```