#Requires -Version 7.0
<#
.SYNOPSIS
    Unpublishes and/or deletes a Microsoft Purview Unified Catalog governance domain hierarchy
    previously created by New-GovernanceDomainHierarchy.ps1, child-before-parent.

.DESCRIPTION
    Microsoft's own portal guidance for deleting a governance domain requires you to "unpublish it
    and delete all business concepts within it, including any subdomains" before the domain itself
    can be deleted (README.md Section 12, reference 6) - a documented, not assumed, ordering
    requirement. This script walks the same definition file New-GovernanceDomainHierarchy.ps1 took,
    resolves every node by (name, parentId) against a fresh Enumerate pass, and processes the
    resulting flat list **deepest-first** (children before parents) for both stages:

      -Unpublish   sets status back to DRAFT (reversible - see rollback.md Stage 1).
      -Purge       permanently deletes the domain via the Delete operation (irreversible - rollback.md
                   Stage 2). Requires -Confirm:$false to be skipped for scripted/unattended use;
                   otherwise PowerShell's own ShouldProcess confirmation prompts per domain.

    A node named in the definition file but not found in the live tenant is skipped with a warning,
    not an error - safe to re-run after a partial previous rollback.

    Author-only reference code. Never connects to a live tenant unless you supply real credentials
    and omit -WhatIf.

.PARAMETER PurviewAccountEndpoint
    Base URL of the Purview Unified Catalog data-plane API - see New-GovernanceDomainHierarchy.ps1.

.PARAMETER TenantId
    Microsoft Entra tenant ID.

.PARAMETER AppId
    Application (client) ID of the service principal. Must hold a role that can edit/delete the
    target domains (Governance Domain Owner to unpublish/edit; deletion additionally requires
    whatever role the tenant has configured for domain deletion - docs/rbac-model.md Section 5,
    README.md Section 3).

.PARAMETER ClientSecret
    Client secret for -AppId, as a SecureString. Resolve from a vault at run time - never hard-code.

.PARAMETER HierarchyDefinitionPath
    Path to the same hierarchy definition JSON file used to create the tree.

.PARAMETER Unpublish
    Sets every matched domain, deepest-first, back to DRAFT status. Reversible - re-running
    New-GovernanceDomainHierarchy.ps1 with -Publish republishes them.

.PARAMETER Purge
    Permanently deletes every matched domain, deepest-first, via the Delete operation.
    **Irreversible** - see rollback.md Stage 2. Implies unpublishing is not required first (Delete
    does not require DRAFT status per Microsoft's reference), but this script unpublishes first
    anyway when both switches are passed, matching the portal's own documented procedure.

.PARAMETER ApiVersion
    Unified Catalog REST API version to pin. Defaults to '2026-03-20-preview'.

.PARAMETER WhatIf
    Standard PowerShell ShouldProcess dry-run. The Enumerate pass still executes for real; only
    mutating PUT/DELETE calls are suppressed.

.EXAMPLE
    ./Remove-GovernanceDomainHierarchy.ps1 -PurviewAccountEndpoint 'https://api.purview-service.microsoft.com' `
        -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
        -HierarchyDefinitionPath './hierarchy/corporate-sales-marketing-hierarchy.json' -Unpublish -WhatIf

    Dry-run: shows which domains would be unpublished, deepest-first, changes nothing.

.EXAMPLE
    ./Remove-GovernanceDomainHierarchy.ps1 -PurviewAccountEndpoint 'https://api.purview-service.microsoft.com' `
        -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
        -HierarchyDefinitionPath './hierarchy/corporate-sales-marketing-hierarchy.json' -Unpublish

    Reversibly unpublishes the entire tree, children before parents.

.EXAMPLE
    ./Remove-GovernanceDomainHierarchy.ps1 -PurviewAccountEndpoint 'https://api.purview-service.microsoft.com' `
        -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
        -HierarchyDefinitionPath './hierarchy/corporate-sales-marketing-hierarchy.json' -Purge

    Permanently deletes the entire tree, children before parents. Irreversible.

.NOTES
    Sources (Microsoft Learn, verify before production use):
    - Business Domain - Delete reference:
      https://learn.microsoft.com/rest/api/purview/purview-unified-catalog/business-domain?view=rest-purview-purview-unified-catalog-2026-03-20-preview
    - Create and manage governance domains - "Delete governance domains" (unpublish + delete
      subdomains first, documented ordering requirement):
      https://learn.microsoft.com/purview/unified-catalog-governance-domains-create-manage
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
    [string]$HierarchyDefinitionPath,

    [Parameter()]
    [switch]$Unpublish,

    [Parameter()]
    [switch]$Purge,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$ApiVersion = '2026-03-20-preview'
)

$ErrorActionPreference = 'Stop'
if (-not $Unpublish -and -not $Purge) {
    throw "Specify -Unpublish, -Purge, or both. Neither was supplied - nothing to do."
}

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
        [Parameter(Mandatory)][ValidateSet('Get', 'Put', 'Delete')][string]$Method,
        [Parameter(Mandatory)][string]$Uri,
        [Parameter()][hashtable]$Body,
        [Parameter(Mandatory)][string]$Token,
        [Parameter()][string]$Description = $Uri
    )
    if ($Method -eq 'Get') {
        return Invoke-RestMethod -Method Get -Uri $Uri -Headers @{ Authorization = "Bearer $Token" }
    }
    if ($PSCmdlet.ShouldProcess($Description, "$Method $Uri")) {
        $params = @{
            Method      = $Method
            Uri         = $Uri
            Headers     = @{ Authorization = "Bearer $Token" }
        }
        if ($Body) {
            $params.Body = ($Body | ConvertTo-Json -Depth 10)
            $params.ContentType = 'application/json'
        }
        return Invoke-RestMethod @params
    }
    Write-Verbose "WhatIf: would $Method $Uri"
    return $null
}

function Get-AllBusinessDomains {
    param([Parameter(Mandatory)][string]$Token)
    $all = [System.Collections.Generic.List[pscustomobject]]::new()
    $uri = "$endpoint/datagovernance/catalog/businessdomains?api-version=$ApiVersion"
    while ($uri) {
        $page = Invoke-Ucm -Method Get -Uri $uri -Token $Token
        foreach ($d in $page.value) { $all.Add($d) }
        $uri = $page.nextLink
    }
    return $all
}

function Get-FlatNodeList {
    # Walks the definition tree and returns (Name, ParentId placeholder resolved lazily) - resolved
    # top-down first (so a child's declared parent name/path is unambiguous), then the caller
    # reverses the list to process deepest-first.
    param(
        [Parameter(Mandatory)][pscustomobject]$Node,
        [Parameter()][string]$ParentName,
        [Parameter(Mandatory)][int]$Depth
    )
    $results = [System.Collections.Generic.List[pscustomobject]]::new()
    $results.Add([pscustomobject]@{ Name = $Node.name; ParentName = $ParentName; Depth = $Depth })
    foreach ($child in $Node.children) {
        foreach ($r in (Get-FlatNodeList -Node $child -ParentName $Node.name -Depth ($Depth + 1))) {
            $results.Add($r)
        }
    }
    return $results
}

# --- Load definition file and resolve every node against a fresh Enumerate pass ---
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

$snapshot = Get-AllBusinessDomains -Token $token
$flatNodes = Get-FlatNodeList -Node $definition.hierarchy -ParentName $null -Depth 1

# Resolve each node's id by walking parent-name chains against the live snapshot, top-down, so a
# repeated child name under a different parent elsewhere in the tenant is never confused with this
# tree's own node (same (name, parentId) matching discipline as the deploy script).
$resolved = [System.Collections.Generic.List[pscustomobject]]::new()
$idByName = @{}
foreach ($n in ($flatNodes | Sort-Object Depth)) {
    $parentId = if ($n.ParentName) { $idByName[$n.ParentName] } else { $null }
    $match = $snapshot | Where-Object { $_.name -eq $n.Name -and ([string]$_.parentId -eq [string]$parentId) } | Select-Object -First 1
    if (-not $match) {
        Write-Warning "Domain '$($n.Name)' (parent: $(if ($n.ParentName) { $n.ParentName } else { '<root>' })) was not found in the live tenant - already removed, or never deployed. Skipped."
        continue
    }
    $idByName[$n.Name] = $match.id
    $resolved.Add([pscustomobject]@{ Name = $n.Name; Id = $match.id; Depth = $n.Depth; Domain = $match })
}

# --- Process deepest-first (children before parents) - Microsoft's documented delete ordering ---
$orderedDeepestFirst = $resolved | Sort-Object Depth -Descending

if ($Unpublish) {
    foreach ($n in $orderedDeepestFirst) {
        if ($n.Domain.status -ne 'PUBLISHED') {
            Write-Host "Governance domain '$($n.Name)' is not published (status: $($n.Domain.status)). Skipped." -ForegroundColor Yellow
            continue
        }
        $body = @{
            id                = $n.Domain.id
            name              = $n.Domain.name
            description       = $n.Domain.description
            type              = $n.Domain.type
            status            = 'DRAFT'
            managedAttributes = @($n.Domain.managedAttributes | ForEach-Object { @{ name = $_.name; value = $_.value } })
            domains           = @($n.Domain.domains)
        }
        if ($n.Domain.parentId) { $body.parentId = $n.Domain.parentId }
        Invoke-Ucm -Method Put -Uri "$endpoint/datagovernance/catalog/businessdomains/$($n.Id)?api-version=$ApiVersion" `
            -Body $body -Token $token -Description "Unpublish governance domain '$($n.Name)'" | Out-Null
        Write-Host "Unpublished governance domain '$($n.Name)' (depth: $($n.Depth))." -ForegroundColor Green
    }
}

if ($Purge) {
    foreach ($n in $orderedDeepestFirst) {
        Invoke-Ucm -Method Delete -Uri "$endpoint/datagovernance/catalog/businessdomains/$($n.Id)?api-version=$ApiVersion" `
            -Token $token -Description "Delete governance domain '$($n.Name)'" | Out-Null
        Write-Host "Deleted governance domain '$($n.Name)' (depth: $($n.Depth))." -ForegroundColor Green
    }
}

Write-Host "`nDone." -ForegroundColor Cyan
