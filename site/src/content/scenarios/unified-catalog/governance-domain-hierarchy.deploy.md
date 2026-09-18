---
part: "deploy"
parent: "unified-catalog/governance-domain-hierarchy"
---
The scripts and configuration below deploy this scenario. Review them, then run in order — each is designed to be idempotent and has a matching rollback.


#### `hierarchy/corporate-sales-marketing-hierarchy.json`

```json
{
  "hierarchy": {
    "name": "Corporate",
    "description": "Top-level governance domain for enterprise-wide, highly controlled business concepts and data products that every business unit shares.",
    "type": "FunctionalUnit",
    "attributes": [
      { "name": "Data Classification Tier", "value": "Tier 1 - Enterprise-wide" }
    ],
    "dataEstateMapping": {
      "dataMapDomainName": "Default domain",
      "collectionReferenceName": "corporate-root",
      "collectionFriendlyName": "Corporate Root Collection"
    },
    "children": [
      {
        "name": "Sales",
        "description": "Business concepts and data products owned by the global Sales organization: pipeline, quota, and customer-facing revenue data.",
        "type": "LineOfBusiness",
        "attributes": [
          { "name": "Data Classification Tier", "value": "Tier 2 - Line of business" }
        ],
        "dataEstateMapping": {
          "dataMapDomainName": "Default domain",
          "collectionReferenceName": "sales-global"
        },
        "children": [
          {
            "name": "Sales - EMEA",
            "description": "Regional Sales sub-domain scoping EMEA-resident pipeline and customer data, ring-fenced for GDPR-driven data-residency review.",
            "type": "Regulatory",
            "isRestricted": true,
            "attributes": [
              { "name": "Data Classification Tier", "value": "Tier 3 - Regional/restricted" }
            ],
            "dataEstateMapping": {
              "dataMapDomainName": "Default domain",
              "collectionReferenceName": "sales-emea"
            },
            "children": []
          }
        ]
      },
      {
        "name": "Marketing",
        "description": "Business concepts and data products owned by the global Marketing organization: campaign performance, audience segments, and brand assets.",
        "type": "LineOfBusiness",
        "attributes": [
          { "name": "Data Classification Tier", "value": "Tier 2 - Line of business" }
        ],
        "dataEstateMapping": {
          "dataMapDomainName": "Default domain",
          "collectionReferenceName": "marketing-global"
        },
        "children": []
      }
    ]
  }
}
```

#### `New-GovernanceDomainHierarchy.ps1`

```powershell
#Requires -Version 7.0
<#
.SYNOPSIS
    Idempotently creates or updates a multi-level Microsoft Purview Unified Catalog governance
    domain hierarchy, with per-domain business-concept attribute values and an optional Data Map
    collection ("data estate mapping"), from a single declarative JSON definition file.

.DESCRIPTION
    Calls the Microsoft Purview Unified Catalog REST API (automation surface 4 per
    docs/automation-surface.md) to:
      1. Enumerate every existing business domain in the tenant once (paginated), building an
         in-memory (name, parentId) lookup - the Business Domain operation group has no name-filter
         Query operation, unlike Terms (design.md Section 3).
      2. Walk the definition file's domain tree depth-first, resolving-or-creating each domain in
         DRAFT status, wiring parentId to the already-resolved parent, applying declared
         managedAttributes values, and (unless -SkipDataEstateMapping is passed) recording a Data
         Map collection reference on domains that declare one.
      3. Optionally (-Publish) publish the tree top-down (parent before children).

    Idempotent by construction: every update reuses the full Domain object Enumerate already
    returned for that domain as the PUT body's starting point (design.md Section 4), rather than
    reconstructing it from only the fields this script's own JSON schema knows about - this avoids
    the full-replace-PUT data loss curate-business-glossary's own Publish-BusinessDomain helper is
    disclosed to risk (README.md Section 11 there).

    Enforces Microsoft's documented five-level depth ceiling client-side (throws before making any
    call for a node past level 5) and warns - non-fatally, since enforcement is unconfirmed - when
    the tenant-wide domain count approaches the documented 200-domain ceiling.

    Author-only reference code. Never connects to a live tenant unless you supply real credentials
    and omit -WhatIf. Every domain is created in DRAFT status unless -Publish is passed.

.PARAMETER PurviewAccountEndpoint
    Base URL of the Purview Unified Catalog data-plane API - 'https://api.purview-service.microsoft.com'
    for tenants on the current Microsoft Purview portal, or 'https://<account>.purview.azure.com' for
    the classic portal (curate-business-glossary/README.md Section 11 explains the difference).

.PARAMETER TenantId
    Microsoft Entra tenant ID.

.PARAMETER AppId
    Application (client) ID of the service principal. Must hold Data Steward (to update existing
    domains) and Governance Domain Creator (to create new ones) - docs/rbac-model.md Section 5.

.PARAMETER ClientSecret
    Client secret for -AppId, as a SecureString. Resolve from a vault at run time - never hard-code.

.PARAMETER HierarchyDefinitionPath
    Path to the hierarchy definition JSON file. See
    deploy/hierarchy/corporate-sales-marketing-hierarchy.json for the expected shape: a root
    'hierarchy' object with name/description/type/attributes/dataEstateMapping/isRestricted and a
    recursive 'children' array.

.PARAMETER Publish
    If supplied, publishes every domain in the tree, top-down (parent before children), after
    they're created/updated. Omit to leave everything in DRAFT - see README.md Section 8.

.PARAMETER SkipDataEstateMapping
    If supplied, never sends a 'domains' (data estate mapping) block even for nodes that declare
    one in the definition file. Recommended for a first pilot-tenant run given the undocumented
    'relatedCollections'/'parentCollection.refName' semantics (design.md Section 5, README.md
    Section 11) - confirm the resulting mapping in the portal before removing this switch.

.PARAMETER ApiVersion
    Unified Catalog REST API version to pin. Defaults to '2026-03-20-preview'.

.PARAMETER WhatIf
    Standard PowerShell ShouldProcess dry-run. The initial Enumerate pass and every read-only call
    still execute for real (needed to accurately report create-vs-update per node); only mutating
    POST/PUT calls are suppressed.

.EXAMPLE
    ./New-GovernanceDomainHierarchy.ps1 -PurviewAccountEndpoint 'https://api.purview-service.microsoft.com' `
        -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
        -HierarchyDefinitionPath './hierarchy/corporate-sales-marketing-hierarchy.json' -WhatIf

    Dry-run: shows exactly which domains would be created/updated, changes nothing.

.EXAMPLE
    ./New-GovernanceDomainHierarchy.ps1 -PurviewAccountEndpoint 'https://api.purview-service.microsoft.com' `
        -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
        -HierarchyDefinitionPath './hierarchy/corporate-sales-marketing-hierarchy.json' -SkipDataEstateMapping

    Creates/updates the domain tree and attribute values in DRAFT, without attempting any data
    estate mapping - the recommended first pilot-tenant run (README.md Section 11).

.EXAMPLE
    ./New-GovernanceDomainHierarchy.ps1 -PurviewAccountEndpoint 'https://api.purview-service.microsoft.com' `
        -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
        -HierarchyDefinitionPath './hierarchy/corporate-sales-marketing-hierarchy.json' -Publish

    Creates/updates the full tree (with data estate mappings) and publishes it top-down.

.NOTES
    VERIFY before production use (full detail in README.md Section 11 and design.md Sections 3, 5):
    (1) Enumerate has no documented page-size parameter, so a very large tenant's total call count
    for the initial full pass is unconfirmed. (2) The data estate mapping construction
    (domains[].relatedCollections[].parentCollection.refName) is this build's own inference from
    field names and nesting, not a directly documented mapping to the portal's "Data estate
    mappings" feature - Microsoft's own worked examples for this exact nested object use
    meaningless placeholder strings, unlike the rest of the same request body. (3) Whether the
    5-level/200-domain ceilings are server-enforced or documentation-only guidance is unconfirmed;
    this script enforces the depth ceiling client-side and only warns on the count ceiling.

    Sources (Microsoft Learn, verify before production use):
    - Business Domain - Create/Update/Enumerate/Delete reference:
      https://learn.microsoft.com/rest/api/purview/purview-unified-catalog/business-domain?view=rest-purview-purview-unified-catalog-2026-03-20-preview
    - Create and manage governance domains (parent domain selection, 200-domain/5-level ceiling,
      Data estate mappings tab):
      https://learn.microsoft.com/purview/unified-catalog-governance-domains-create-manage
    - Create and manage business concept attributes (preview) (definitions are portal/admin-only):
      https://learn.microsoft.com/purview/unified-catalog-attributes-business-concept
    - Sample setup for data governance (Corporate -> Sales worked example):
      https://learn.microsoft.com/purview/data-governance-setup-sample
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
    [string]$HierarchyDefinitionPath,

    [Parameter()]
    [switch]$Publish,

    [Parameter()]
    [switch]$SkipDataEstateMapping,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$ApiVersion = '2026-03-20-preview'
)

$ErrorActionPreference = 'Stop'

$endpoint = $PurviewAccountEndpoint.TrimEnd('/')
$script:MaxDepth = 5
$script:DomainCeilingWarningThreshold = 200

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
    # Invoke-RestMethod has no native ShouldProcess integration, so every mutating call is wrapped
    # in its own $PSCmdlet.ShouldProcess() check. -ReadOnly bypasses that gate for calls that are
    # read-only despite using GET (none here take a body) so they still run under -WhatIf.
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
        return Invoke-RestMethod @params
    }
    Write-Verbose "WhatIf: would $Method $Uri$(if ($Body) { " with body:`n$($Body | ConvertTo-Json -Depth 10)" })"
    return $null
}

function Get-AllBusinessDomains {
    # One full, paginated Enumerate pass (design.md Section 3) - Business Domain has no name-filter
    # Query operation, unlike Terms. Every returned object is a complete Domain, including any
    # existing managedAttributes/domains/thumbnail - reused as the update-body seed (design.md
    # Section 4) so this script never clobbers a field its own JSON schema doesn't know about.
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

function Find-DomainInSnapshot {
    param(
        [Parameter(Mandatory)][System.Collections.Generic.List[pscustomobject]]$Snapshot,
        [Parameter(Mandatory)][string]$Name,
        [Parameter()][string]$ParentId
    )
    return ($Snapshot | Where-Object {
            $_.name -eq $Name -and ([string]$_.parentId -eq [string]$ParentId)
        } | Select-Object -First 1)
}

function ConvertTo-ManagedAttributesBody {
    param([Parameter()][object[]]$Attributes)
    if (-not $Attributes) { return @() }
    return @($Attributes | ForEach-Object { @{ name = $_.name; value = $_.value } })
}

function ConvertTo-DataEstateMappingBody {
    # design.md Section 5: this exact shape is this build's own inference from field names and
    # nesting, not a directly documented mapping - VERIFY against a pilot tenant's Data estate
    # mappings tab before relying on it. Always returns @() when -SkipDataEstateMapping is set or
    # the node declares no dataEstateMapping, matching the "opt-in" design decision.
    param([Parameter()][pscustomobject]$Mapping)
    if ($SkipDataEstateMapping -or -not $Mapping) { return @() }
    $parentRef = if ($Mapping.parentCollectionReferenceName) { $Mapping.parentCollectionReferenceName } else { $Mapping.collectionReferenceName }
    return @(
        @{
            name             = $Mapping.dataMapDomainName
            friendlyName     = $Mapping.dataMapDomainName
            relatedCollections = @(
                @{
                    name            = $Mapping.collectionReferenceName
                    friendlyName    = if ($Mapping.collectionFriendlyName) { $Mapping.collectionFriendlyName } else { $Mapping.collectionReferenceName }
                    parentCollection = @{
                        type    = 'CollectionReference'
                        refName = $parentRef
                    }
                }
            )
        }
    )
}

function New-DomainRequestBody {
    # Seeds from $Existing (the live Enumerate snapshot object) when present, so fields this
    # script's own schema doesn't model (thumbnail, an out-of-band managedAttribute, etc.) survive
    # a re-run untouched - design.md Section 4. A brand-new domain has no snapshot to seed from.
    param(
        [Parameter(Mandatory)][pscustomobject]$Node,
        [Parameter(Mandatory)][string]$DomainId,
        [Parameter()][string]$ParentId,
        [Parameter(Mandatory)][string]$Status,
        [Parameter()][pscustomobject]$Existing
    )
    $managedAttributes = if ($Existing -and $Existing.managedAttributes) {
        @($Existing.managedAttributes | ForEach-Object { @{ name = $_.name; value = $_.value } })
    } else { @() }
    foreach ($attr in (ConvertTo-ManagedAttributesBody -Attributes $Node.attributes)) {
        $managedAttributes = @($managedAttributes | Where-Object { $_.name -ne $attr.name })
        $managedAttributes += , $attr
    }

    $domainsBody = ConvertTo-DataEstateMappingBody -Mapping $Node.dataEstateMapping
    if (-not $domainsBody -or $domainsBody.Count -eq 0) {
        if ($Existing -and $Existing.domains) { $domainsBody = $Existing.domains }
    }

    $body = @{
        id                = $DomainId
        name              = $Node.name
        description       = $Node.description
        type              = $Node.type
        status            = $Status
        managedAttributes = $managedAttributes
        domains           = @($domainsBody)
    }
    if ($ParentId) { $body.parentId = $ParentId }
    # isRestricted is full-replace-PUT territory like every other field here (design.md Section 4):
    # if the node declares it, that value wins; otherwise seed from the live object so a
    # portal-set restriction isn't silently cleared just because this run's definition file happens
    # not to mention it.
    if ($Node.PSObject.Properties.Match('isRestricted').Count -gt 0) {
        $body.isRestricted = [bool]$Node.isRestricted
    }
    elseif ($Existing -and $null -ne $Existing.isRestricted) {
        $body.isRestricted = $Existing.isRestricted
    }
    return $body
}

function Get-OrNewDomainNode {
    # Depth-first: resolves-or-creates this node, then recurses into its children with this node's
    # resolved id as their parentId. Returns a flat list of @{ Name; Id; Depth } used for reporting
    # and by Publish-DomainTree.
    param(
        [Parameter(Mandatory)][pscustomobject]$Node,
        [Parameter()][string]$ParentId,
        [Parameter(Mandatory)][System.Collections.Generic.List[pscustomobject]]$Snapshot,
        [Parameter(Mandatory)][string]$Token,
        [Parameter(Mandatory)][int]$Depth
    )
    if ($Depth -gt $script:MaxDepth) {
        throw "Node '$($Node.name)' is at depth $Depth, exceeding Microsoft's documented 5-level governance domain hierarchy ceiling. Flatten the definition file (design.md Section 3 / README.md Section 6)."
    }

    $existing = Find-DomainInSnapshot -Snapshot $Snapshot -Name $Node.name -ParentId $ParentId
    $domainId = if ($existing) { $existing.id } else { [guid]::NewGuid().ToString() }
    $status = if ($existing) { $existing.status } else { 'DRAFT' }

    $body = New-DomainRequestBody -Node $Node -DomainId $domainId -ParentId $ParentId -Status $status -Existing $existing

    if ($existing) {
        $uri = "$endpoint/datagovernance/catalog/businessdomains/$domainId?api-version=$ApiVersion"
        Invoke-Ucm -Method Put -Uri $uri -Body $body -Token $Token `
            -Description "Update governance domain '$($Node.name)'" | Out-Null
        Write-Host "Updated governance domain '$($Node.name)' (id: $domainId, depth: $Depth)." -ForegroundColor Green
    }
    else {
        $uri = "$endpoint/datagovernance/catalog/businessdomains?api-version=$ApiVersion"
        Invoke-Ucm -Method Post -Uri $uri -Body $body -Token $Token `
            -Description "Create governance domain '$($Node.name)'" | Out-Null
        Write-Host "Created governance domain '$($Node.name)' (id: $domainId, depth: $Depth, parent: $(if ($ParentId) { $ParentId } else { '<root>' }))." -ForegroundColor Green
        # Add to the in-memory snapshot so a later sibling that references this run's new domain
        # by (name, parentId) - not expected in this schema, but defensive - sees it as existing.
        $Snapshot.Add([pscustomobject]@{ id = $domainId; name = $Node.name; parentId = $ParentId; status = $status })
    }

    $results = [System.Collections.Generic.List[pscustomobject]]::new()
    $results.Add([pscustomobject]@{ Name = $Node.name; Id = $domainId; Depth = $Depth })

    foreach ($child in $Node.children) {
        $childResults = Get-OrNewDomainNode -Node $child -ParentId $domainId -Snapshot $Snapshot `
            -Token $Token -Depth ($Depth + 1)
        foreach ($r in $childResults) { $results.Add($r) }
    }
    return $results
}

function Publish-DomainNode {
    param(
        [Parameter(Mandatory)][string]$DomainId,
        [Parameter(Mandatory)][string]$DomainName,
        [Parameter(Mandatory)][string]$Token
    )
    $current = Invoke-Ucm -Method Get -Uri "$endpoint/datagovernance/catalog/businessdomains/$($DomainId)?api-version=$ApiVersion" -Token $Token
    if ($current -and $current.status -eq 'PUBLISHED') {
        Write-Host "Governance domain '$DomainName' is already published." -ForegroundColor Yellow
        return
    }
    $body = @{
        id                = $current.id
        name              = $current.name
        description       = $current.description
        type              = $current.type
        status            = 'PUBLISHED'
        managedAttributes = @($current.managedAttributes | ForEach-Object { @{ name = $_.name; value = $_.value } })
        domains           = @($current.domains)
    }
    if ($current.parentId) { $body.parentId = $current.parentId }
    if ($null -ne $current.isRestricted) { $body.isRestricted = $current.isRestricted }
    Invoke-Ucm -Method Put -Uri "$endpoint/datagovernance/catalog/businessdomains/$($DomainId)?api-version=$ApiVersion" `
        -Body $body -Token $Token -Description "Publish governance domain '$DomainName'" | Out-Null
    Write-Host "Published governance domain '$DomainName'." -ForegroundColor Green
}

# --- Load and validate the definition file ---
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

# --- Step 1: one full Enumerate pass (design.md Section 3) ---
$snapshot = Get-AllBusinessDomains -Token $token
Write-Host "Enumerated $($snapshot.Count) existing governance domain(s) tenant-wide." -ForegroundColor Cyan
if ($snapshot.Count -ge $script:DomainCeilingWarningThreshold) {
    Write-Warning "Tenant already has $($snapshot.Count) governance domains, at or near Microsoft's documented 200-domain ceiling. New domains created by this run may push the tenant over that ceiling - confirm current enforcement behavior before proceeding at scale."
}

# --- Step 2: walk the tree depth-first, root first ---
$created = Get-OrNewDomainNode -Node $definition.hierarchy -ParentId $null -Snapshot $snapshot -Token $token -Depth 1

# --- Step 3 (optional): publish top-down (parent before children) ---
if ($Publish) {
    foreach ($node in ($created | Sort-Object Depth)) {
        Publish-DomainNode -DomainId $node.Id -DomainName $node.Name -Token $token
    }
}
else {
    Write-Host "`nAll domains left in DRAFT status. Re-run with -Publish once reviewed." -ForegroundColor Cyan
}

Write-Host "`nProcessed $($created.Count) domain(s) across $((($created | Measure-Object -Property Depth -Maximum).Maximum)) level(s)." -ForegroundColor Cyan
Write-Host "Run validate/Test-GovernanceDomainHierarchy.ps1 to verify the deployed configuration." -ForegroundColor Cyan
```

#### `Remove-GovernanceDomainHierarchy.ps1`

```powershell
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
```