---
part: "validate"
parent: "unified-catalog/governance-domain-hierarchy"
---
Run these checks after deployment to confirm the control is working as designed.


#### `Test-GovernanceDomainHierarchy.ps1`

```powershell
#Requires -Version 7.0
<#
.SYNOPSIS
    Verifies a governance domain hierarchy deployed by New-GovernanceDomainHierarchy.ps1 matches
    the definition file.

.DESCRIPTION
    Read-only validation script - calls only the Business Domain Enumerate/Get operations, never
    modifies state. Checks, for every node in the definition file:
      1. The domain exists, matched by (name, resolved parentId) - not name alone, since names can
         repeat across different parents tenant-wide (design.md Section 3).
      2. Its type and description match the definition file.
      3. Its parentId chain matches the tree shape declared in the file (root has no parent; each
         child's parentId is its resolved parent's id).
      4. Every declared managedAttributes value is present with a matching value.
      5. If the node declares a dataEstateMapping and -SkipDataEstateMapping was not passed at
         deploy time, reports (does not hard-fail on) whether a 'domains' block is present - this
         check is a WARN, not a FAIL, given the undocumented relatedCollections/parentCollection
         semantics disclosed in README.md Section 11 and design.md Section 5.
      6. Reports (does not fail on) DRAFT vs PUBLISHED status, since both are valid depending on
         whether -Publish has been run yet.
      7. Reports the total tenant-wide domain count against the documented 200-domain ceiling.
    Exits with a non-zero code if any hard check fails, so this script is safe to wire into a
    CI-style pre-flight or a post-deploy smoke test. Safe to re-run any number of times.

.PARAMETER PurviewAccountEndpoint
    Base URL of the Purview Unified Catalog data-plane API - must match the value used at deploy
    time.

.PARAMETER TenantId
    Microsoft Entra tenant ID.

.PARAMETER AppId
    Application (client) ID of a service principal holding at least a Catalog Reader role that can
    see the target domains.

.PARAMETER ClientSecret
    Client secret for -AppId, as a SecureString.

.PARAMETER HierarchyDefinitionPath
    Path to the same hierarchy definition JSON file passed to New-GovernanceDomainHierarchy.ps1.

.PARAMETER ApiVersion
    Unified Catalog REST API version to pin. Defaults to '2026-03-20-preview'.

.EXAMPLE
    ./Test-GovernanceDomainHierarchy.ps1 -PurviewAccountEndpoint 'https://api.purview-service.microsoft.com' `
        -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
        -HierarchyDefinitionPath '../deploy/hierarchy/corporate-sales-marketing-hierarchy.json'
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
    [string]$HierarchyDefinitionPath,

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

function Get-AllBusinessDomains {
    param([Parameter(Mandatory)][string]$Token)
    $all = [System.Collections.Generic.List[pscustomobject]]::new()
    $uri = "$endpoint/datagovernance/catalog/businessdomains?api-version=$ApiVersion"
    while ($uri) {
        $page = Invoke-RestMethod -Method Get -Uri $uri -Headers @{ Authorization = "Bearer $Token" }
        foreach ($d in $page.value) { $all.Add($d) }
        $uri = $page.nextLink
    }
    return $all
}

function Get-FlatNodeList {
    param(
        [Parameter(Mandatory)][pscustomobject]$Node,
        [Parameter()][string]$ParentName,
        [Parameter(Mandatory)][int]$Depth
    )
    $results = [System.Collections.Generic.List[pscustomobject]]::new()
    $results.Add([pscustomobject]@{ Node = $Node; ParentName = $ParentName; Depth = $Depth })
    foreach ($child in $Node.children) {
        foreach ($r in (Get-FlatNodeList -Node $child -ParentName $Node.name -Depth ($Depth + 1))) {
            $results.Add($r)
        }
    }
    return $results
}

$definition = Get-Content -Path $HierarchyDefinitionPath -Raw | ConvertFrom-Json
if (-not $definition.hierarchy) {
    throw "Definition file '$HierarchyDefinitionPath' must contain a top-level 'hierarchy' object."
}

$plainSecret = ConvertTo-PlainText -Secure $ClientSecret
try {
    $token = Get-PurviewAccessToken -TenantId $TenantId -AppId $AppId -PlainSecret $plainSecret
}
finally {
    $plainSecret = $null
}

Write-Host "Enumerating all governance domains in the tenant..." -ForegroundColor Cyan
$snapshot = Get-AllBusinessDomains -Token $token
Write-Host "Tenant-wide domain count: $($snapshot.Count) (documented ceiling: 200)." -ForegroundColor Cyan
Test-Check -Description "Tenant-wide domain count ($($snapshot.Count)) is below the documented 200-domain ceiling" `
    -Condition ($snapshot.Count -lt 200) -Warn

$flatNodes = Get-FlatNodeList -Node $definition.hierarchy -ParentName $null -Depth 1
$idByName = @{}

foreach ($entry in ($flatNodes | Sort-Object Depth)) {
    $node = $entry.Node
    $parentId = if ($entry.ParentName) { $idByName[$entry.ParentName] } else { $null }
    Write-Host "`nChecking domain '$($node.name)' (depth $($entry.Depth), parent: $(if ($entry.ParentName) { $entry.ParentName } else { '<root>' }))..." -ForegroundColor Cyan

    $match = $snapshot | Where-Object { $_.name -eq $node.name -and ([string]$_.parentId -eq [string]$parentId) } | Select-Object -First 1
    Test-Check -Description "Domain '$($node.name)' exists under the expected parent" -Condition ([bool]$match)
    if (-not $match) { continue }

    $idByName[$node.name] = $match.id

    Test-Check -Description "Type matches ('$($node.type)')" -Condition ($match.type -eq $node.type)
    Test-Check -Description "Description matches" -Condition ($match.description -eq $node.description)

    if ($entry.ParentName) {
        Test-Check -Description "parentId correctly points at resolved parent '$($entry.ParentName)'" `
            -Condition ($match.parentId -eq $parentId)
    }
    else {
        Test-Check -Description "Root node has no parentId" -Condition ([string]::IsNullOrEmpty($match.parentId))
    }

    if ($node.attributes) {
        foreach ($attr in $node.attributes) {
            $liveAttr = $match.managedAttributes | Where-Object { $_.name -eq $attr.name } | Select-Object -First 1
            Test-Check -Description "Attribute '$($attr.name)' = '$($attr.value)'" `
                -Condition ($liveAttr -and $liveAttr.value -eq $attr.value)
        }
    }

    if ($node.dataEstateMapping) {
        $hasMappingBlock = $match.domains -and $match.domains.Count -gt 0
        Test-Check -Description "Data estate mapping block present (VERIFY - undocumented semantics, README.md Section 11)" `
            -Condition $hasMappingBlock -Warn
    }

    if ($node.isRestricted) {
        Test-Check -Description "isRestricted = true as declared" -Condition ($match.isRestricted -eq $true)
    }

    Test-Check -Description "Publish status is DRAFT or PUBLISHED (report only)" `
        -Condition ($match.status -in @('DRAFT', 'PUBLISHED')) -Warn
    Write-Host "    status: $($match.status)" -ForegroundColor Gray
}

Write-Host "`n----------------------------------------"
if ($script:failures -eq 0) {
    Write-Host "All hard checks passed." -ForegroundColor Green
    exit 0
}
else {
    Write-Host "$($script:failures) check(s) FAILED." -ForegroundColor Red
    exit 1
}
```