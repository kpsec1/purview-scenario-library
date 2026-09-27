#Requires -Version 7.0
<#
.SYNOPSIS
    Idempotently creates or updates a Microsoft Purview Unified Catalog data product, wraps an
    already-scanned Data Map asset as a Unified Catalog data asset, and links both the asset and a
    set of glossary terms to the data product, from a declarative JSON definition file.

.DESCRIPTION
    Calls the Microsoft Purview Unified Catalog REST API (automation surface 4 per
    docs/automation-surface.md) to:
      1. Resolve the governance domain named in the definition file (must already exist - this
         scenario reuses the domain scenarios/unified-catalog/curate-business-glossary/ creates,
         it does not create one).
      2. Resolve any owner identity that isn't already an Entra object ID to one, via Microsoft
         Graph (surface 3) - the same owner-resolution pattern as New-BusinessGlossary.ps1.
      3. Create or update (upsert) the data product itself.
      4. Wrap the definition file's Data Map asset (already registered and scanned by
         scenarios/data-map/scan-azure-sql-and-classify/) as a Unified Catalog data asset - a
         separate object the 2026-03-20-preview API introduced that references the Data Map asset
         by ID rather than duplicating its metadata.
      5. Link that data asset, and each named glossary term (already created by
         scenarios/unified-catalog/curate-business-glossary/), to the data product via the Data
         Products - Create Relationship operation.
      6. Optionally (-Publish) transition the data product from DRAFT to PUBLISHED.

    This reproduces, as code, the exact five-step flow Microsoft's own "Master data management in
    Microsoft Purview" article documents: register/scan a source, create a data product, create a
    glossary term and link it, then curate the product by reviewing its linked assets
    (design.md Section 1).

    Idempotent by construction: before creating the data product, the script queries the domain
    for an existing data product with an exact (case-insensitive) name match, mirroring
    New-BusinessGlossary.ps1's term-identity design (design.md Section 3). Before wrapping the
    Data Map asset, it queries existing Unified Catalog data assets by the Data Map asset's own ID
    (sourceAssetIds filter) so re-running this script never creates a second wrapper for the same
    underlying asset. Before creating each relationship, it lists the data product's existing
    relationships of that entity type and skips the create call if the target is already linked.

    Author-only reference code. Never connects to a live tenant unless you supply real credentials
    and omit -WhatIf. The data product is created in DRAFT status unless -Publish is passed - and
    -Publish requires a data product access policy to already be configured in the portal
    (README.md Section 3 and Section 11 - this script does not, and per this build's grounding
    pass cannot, script that policy).

.PARAMETER PurviewAccountEndpoint
    Base URL of the Purview Unified Catalog data-plane API. Use 'https://api.purview-service.microsoft.com'
    for tenants on the current Microsoft Purview portal, or 'https://<account>.purview.azure.com'
    for the classic portal.

.PARAMETER TenantId
    Microsoft Entra tenant ID.

.PARAMETER AppId
    Application (client) ID of the service principal used to call both the Unified Catalog REST
    API and Microsoft Graph. Must hold the Data Product Owner role on the target governance domain
    (docs/rbac-model.md Section 5) and the Graph application permission User.Read.All (README.md
    Section 3).

.PARAMETER ClientSecret
    Client secret for -AppId, as a SecureString. Resolve from a vault at run time - never hard-code.

.PARAMETER DefinitionPath
    Path to the data product definition JSON file. See
    deploy/config/customer-master-data-product.sample.json for the expected shape (domain block,
    dataProduct block, dataAsset block with a Data Map asset GUID, relatedTerms array).

.PARAMETER Publish
    If supplied, transitions the data product from DRAFT to PUBLISHED after it is created/updated
    and linked. Requires a data product access policy to already be configured in the portal
    (Manage policies on the data product's details page) - Microsoft's portal explicitly blocks
    Publish without one; this script's own REST call may or may not enforce the same rule
    server-side (README.md Section 11, an explicit VERIFY). Omit to leave the data product in
    DRAFT for review.

.PARAMETER ApiVersion
    Unified Catalog REST API version to pin. Defaults to '2026-03-20-preview', the version whose
    Data Products/Data Assets operation groups this script was grounded against.

.PARAMETER WhatIf
    Standard PowerShell ShouldProcess dry-run. Reports every REST call that would be made without
    sending any mutating (POST/PUT/DELETE) request. Invoke-RestMethod has no native ShouldProcess
    integration, so this script wraps each mutating call in its own $PSCmdlet.ShouldProcess() check.

.EXAMPLE
    ./New-DataProduct.ps1 -PurviewAccountEndpoint 'https://api.purview-service.microsoft.com' `
        -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
        -DefinitionPath './config/customer-master-data-product.sample.json' -WhatIf

    Dry-run: shows exactly which REST calls would be made, changes nothing.

.EXAMPLE
    ./New-DataProduct.ps1 -PurviewAccountEndpoint 'https://api.purview-service.microsoft.com' `
        -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
        -DefinitionPath './config/customer-master-data-product.sample.json'

    Creates/updates the data product and its links in DRAFT status.

.EXAMPLE
    ./New-DataProduct.ps1 -PurviewAccountEndpoint 'https://api.purview-service.microsoft.com' `
        -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
        -DefinitionPath './config/customer-master-data-product.sample.json' -Publish

    Creates/updates, links, then publishes - only after an access policy is already configured.

.NOTES
    VERIFY before production use (see README.md Section 11 and design.md for full detail):
    - CLOSED 2026-09-27 (Microsoft Learn grounding): the Data Products - Create Relationship REST
      reference's single worked example (entityType=CRITICALDATACOLUMN, an entityType value that
      itself is absent from the same page's own EntityCategory enum) shows a body containing
      `assetId`, but this is a documentation-generation artifact, not an `entityType`-specific
      schema. Every sibling relationship-creation operation - Data Assets - Create Relationship,
      Critical Data Elements - Create Relationship (the operation that actually manages CDE
      relationships), and Data Products - Create Relationship's own `DataProductRelationship`
      response type - documents the same plain shape this script already sends:
      entityId/description/relationshipType, no `assetId`. This script's DATAASSET/TERM calls are
      correct as written; no code change needed.
    - Whether the REST API's Data Products - Update operation enforces the portal's own
      "must have a data access policy before Publish" business rule, or whether that is a
      portal-UX-only guardrail this script's direct PUT call bypasses. Not documented either way.
    - The Data Products - Query `nameKeyword` filter's exact match semantics (substring vs. prefix
      vs. tokenized), the same open question as New-BusinessGlossary.ps1's Query Terms VERIFY -
      this script applies the identical client-side-exact-match mitigation.

    Sources (Microsoft Learn, verify before production use):
    - Data Products operation group (Create/Update/Delete/Get/List/Query/Create Relationship/
      List Relationships/Delete Relationship/Count/Get Facets):
      https://learn.microsoft.com/rest/api/purview/purview-unified-catalog/data-products?view=rest-purview-purview-unified-catalog-2026-03-20-preview
    - Data Assets operation group (Create/Update/Delete By Id/Get By Id/List/Query/Create
      Relationship/List Relationships/Delete Relationship):
      https://learn.microsoft.com/rest/api/purview/purview-unified-catalog/data-assets?view=rest-purview-purview-unified-catalog-2026-03-20-preview
    - Create and manage data products (portal flow, prerequisites, Publish gating on assets +
      access policy): https://learn.microsoft.com/purview/unified-catalog-data-products-create-manage
    - Master data management in Microsoft Purview (the five-step register/create/link/curate flow
      this script automates): https://learn.microsoft.com/purview/data-governance-master-data-management
    - Get a user (Graph, User.Read.All application permission):
      https://learn.microsoft.com/graph/api/user-get
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
    [string]$DefinitionPath,

    [Parameter()]
    [switch]$Publish,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$ApiVersion = '2026-03-20-preview'
)

$ErrorActionPreference = 'Stop'

$endpoint = $PurviewAccountEndpoint.TrimEnd('/')
$guidPattern = '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
$nilGuid = '00000000-0000-0000-0000-000000000000'

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

function Get-GraphAccessToken {
    param(
        [Parameter(Mandatory)][string]$TenantId,
        [Parameter(Mandatory)][string]$AppId,
        [Parameter(Mandatory)][string]$PlainSecret
    )
    $body = @{
        client_id     = $AppId
        client_secret = $PlainSecret
        grant_type    = 'client_credentials'
        scope         = 'https://graph.microsoft.com/.default'
    }
    $response = Invoke-RestMethod -Method Post `
        -Uri "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token" -Body $body
    return $response.access_token
}

function Invoke-Ucm {
    # Invoke-RestMethod has no native ShouldProcess integration, so every mutating call is
    # wrapped in its own $PSCmdlet.ShouldProcess() check. -ReadOnly bypasses that gate for calls
    # that are read-only despite using POST (Query/List Relationships) - those must still execute
    # under -WhatIf so the script can accurately report create vs. update vs. already-linked.
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

function Find-BusinessDomainByName {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Token
    )
    $uri = "$endpoint/datagovernance/catalog/businessdomains?api-version=$ApiVersion"
    while ($uri) {
        $page = Invoke-Ucm -Method Get -Uri $uri -Token $Token
        $match = $page.value | Where-Object { $_.name -eq $Name } | Select-Object -First 1
        if ($match) { return $match }
        $uri = $page.nextLink
    }
    return $null
}

function Resolve-ContactId {
    param(
        [Parameter(Mandatory)][string]$Identifier,
        [Parameter(Mandatory)][string]$GraphToken,
        [Parameter(Mandatory)][hashtable]$Cache
    )
    if ($Identifier -match $guidPattern) { return $Identifier }
    if ($Cache.ContainsKey($Identifier)) { return $Cache[$Identifier] }
    $uri = "https://graph.microsoft.com/v1.0/users/${Identifier}?`$select=id"
    $user = Invoke-RestMethod -Method Get -Uri $uri -Headers @{ Authorization = "Bearer $GraphToken" }
    $Cache[$Identifier] = $user.id
    Write-Host "Resolved '$Identifier' to Entra object ID $($user.id)." -ForegroundColor Cyan
    return $user.id
}

function Find-TermByName {
    # Duplicated from New-BusinessGlossary.ps1 by design - each deploy script in this repo is
    # self-contained (design.md Section 2 / AGENTS.md's per-scenario deliverable model), not a
    # shared module, so a scenario can be copied and understood on its own.
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$DomainId,
        [Parameter(Mandatory)][string]$Token
    )
    $uri = "$endpoint/datagovernance/catalog/terms/query?api-version=$ApiVersion"
    $body = @{ domainIds = @($DomainId); nameKeyword = $Name; top = 50 }
    $response = Invoke-Ucm -Method Post -Uri $uri -Body $body -Token $Token -ReadOnly `
        -Description "Query terms named like '$Name'"
    return ($response.value | Where-Object { $_.name -eq $Name } | Select-Object -First 1)
}

function Find-DataProductByName {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$DomainId,
        [Parameter(Mandatory)][string]$Token
    )
    $uri = "$endpoint/datagovernance/catalog/dataProducts/query?api-version=$ApiVersion"
    $body = @{ domainIds = @($DomainId); nameKeyword = $Name; top = 50 }
    $response = Invoke-Ucm -Method Post -Uri $uri -Body $body -Token $Token -ReadOnly `
        -Description "Query data products named like '$Name'"
    return ($response.value | Where-Object { $_.name -eq $Name } | Select-Object -First 1)
}

function Get-OrNewDataProduct {
    param(
        [Parameter(Mandatory)][pscustomobject]$ProductDef,
        [Parameter(Mandatory)][string]$DomainId,
        [Parameter(Mandatory)][string]$Token,
        [Parameter(Mandatory)][string]$GraphToken,
        [Parameter(Mandatory)][hashtable]$ContactCache
    )
    $existing = Find-DataProductByName -Name $ProductDef.name -DomainId $DomainId -Token $Token
    $productId = if ($existing) { $existing.id } else { [guid]::NewGuid().ToString() }
    $status = if ($existing) { $existing.status } else { 'DRAFT' }

    $ownerIds = @($ProductDef.owners | ForEach-Object {
            Resolve-ContactId -Identifier $_ -GraphToken $GraphToken -Cache $ContactCache
        })

    $body = @{
        id             = $productId
        domain         = $DomainId
        name           = $ProductDef.name
        status         = $status
        type           = $ProductDef.type
        description    = $ProductDef.description
        businessUse    = $ProductDef.businessUse
        updateFrequency = $ProductDef.updateFrequency
        audience       = @($ProductDef.audience)
        contacts       = @{ owner = @($ownerIds | ForEach-Object { @{ id = $_ } }) }
    }

    if ($existing) {
        $uri = "$endpoint/datagovernance/catalog/dataProducts/$productId?api-version=$ApiVersion"
        Invoke-Ucm -Method Put -Uri $uri -Body $body -Token $Token `
            -Description "Update data product '$($ProductDef.name)'" | Out-Null
        Write-Host "Updated data product '$($ProductDef.name)' (id: $productId, status: $status)." -ForegroundColor Green
    }
    else {
        $uri = "$endpoint/datagovernance/catalog/dataProducts?api-version=$ApiVersion"
        Invoke-Ucm -Method Post -Uri $uri -Body $body -Token $Token `
            -Description "Create data product '$($ProductDef.name)'" | Out-Null
        Write-Host "Created data product '$($ProductDef.name)' (id: $productId, status: DRAFT)." -ForegroundColor Green
    }
    return $productId
}

function Find-DataAssetBySourceId {
    param(
        [Parameter(Mandatory)][string]$DataMapAssetId,
        [Parameter(Mandatory)][string]$Token
    )
    $uri = "$endpoint/datagovernance/catalog/dataAssets/query?api-version=$ApiVersion"
    $body = @{ sourceAssetIds = @($DataMapAssetId) }
    $response = Invoke-Ucm -Method Post -Uri $uri -Body $body -Token $Token -ReadOnly `
        -Description "Query data assets wrapping Data Map asset '$DataMapAssetId'"
    return ($response.value | Where-Object { $_.source.assetId -eq $DataMapAssetId } | Select-Object -First 1)
}

function Get-OrNewDataAsset {
    # Wraps an already-scanned Data Map asset (customerdb.dbo.Customers, per
    # scenarios/data-map/scan-azure-sql-and-classify/) as a Unified Catalog "data asset" object -
    # a separate, Unified-Catalog-native identity that Create Relationship links against, distinct
    # from the underlying Data Map catalog entity's own GUID (design.md Section 4).
    param(
        [Parameter(Mandatory)][string]$DataMapAssetId,
        [Parameter(Mandatory)][string]$Token
    )
    $existing = Find-DataAssetBySourceId -DataMapAssetId $DataMapAssetId -Token $Token
    if ($existing) {
        Write-Host "Data asset wrapper for Data Map asset '$DataMapAssetId' already exists (Unified Catalog id: $($existing.id), type: $($existing.type))." -ForegroundColor Yellow
        return $existing.id
    }
    $body = @{ source = @{ assetId = $DataMapAssetId } }
    $uri = "$endpoint/datagovernance/catalog/dataAssets?api-version=$ApiVersion"
    $created = Invoke-Ucm -Method Post -Uri $uri -Body $body -Token $Token `
        -Description "Wrap Data Map asset '$DataMapAssetId' as a Unified Catalog data asset"
    if ($created) {
        Write-Host "Created data asset wrapper (Unified Catalog id: $($created.id), type: $($created.type)) for Data Map asset '$DataMapAssetId'." -ForegroundColor Green
        return $created.id
    }
    # -WhatIf path: no real ID was minted. Use the nil GUID as a readable placeholder so the rest
    # of this dry run can still report what it *would* link against.
    Write-Verbose "WhatIf: data asset wrapper for '$DataMapAssetId' would be created; using a placeholder id for the remainder of this dry run."
    return $nilGuid
}

function Test-RelationshipExists {
    param(
        [Parameter(Mandatory)][string]$DataProductId,
        [Parameter(Mandatory)][string]$EntityType,
        [Parameter(Mandatory)][string]$EntityId,
        [Parameter(Mandatory)][string]$Token
    )
    $uri = "$endpoint/datagovernance/catalog/dataProducts/$DataProductId/relationships?api-version=$ApiVersion&entityType=$EntityType"
    $response = Invoke-Ucm -Method Get -Uri $uri -Token $Token
    return [bool]($response.value | Where-Object { $_.entityId -eq $EntityId })
}

function Add-DataProductRelationship {
    # CLOSED 2026-09-27 (see this script's .NOTES and README.md Section 11): omitting `assetId`
    # here is grounded, not a guess - every sibling Create Relationship operation on
    # Microsoft Learn documents the plain entityId/description/relationshipType shape sent below.
    param(
        [Parameter(Mandatory)][string]$DataProductId,
        [Parameter(Mandatory)][string]$ProductName,
        [Parameter(Mandatory)][ValidateSet('DATAASSET', 'TERM')][string]$EntityType,
        [Parameter(Mandatory)][string]$EntityId,
        [Parameter(Mandatory)][string]$EntityLabel,
        [Parameter(Mandatory)][string]$Token
    )
    if (Test-RelationshipExists -DataProductId $DataProductId -EntityType $EntityType -EntityId $EntityId -Token $Token) {
        Write-Host "'$ProductName' is already linked to $EntityType '$EntityLabel'." -ForegroundColor Yellow
        return
    }
    $uri = "$endpoint/datagovernance/catalog/dataProducts/$DataProductId/relationships?api-version=$ApiVersion&entityType=$EntityType"
    $body = @{ entityId = $EntityId; relationshipType = 'Related' }
    Invoke-Ucm -Method Post -Uri $uri -Body $body -Token $Token `
        -Description "Link '$ProductName' -> $EntityType '$EntityLabel'" | Out-Null
    Write-Host "Linked '$ProductName' -> $EntityType '$EntityLabel'." -ForegroundColor Green
}

function Publish-DataProduct {
    param(
        [Parameter(Mandatory)][string]$ProductName,
        [Parameter(Mandatory)][string]$ProductId,
        [Parameter(Mandatory)][string]$Token
    )
    $current = Invoke-Ucm -Method Get -Uri "$endpoint/datagovernance/catalog/dataProducts/$($ProductId)?api-version=$ApiVersion" -Token $Token
    if ($current -and $current.status -eq 'PUBLISHED') {
        Write-Host "Data product '$ProductName' is already published." -ForegroundColor Yellow
        return
    }
    Write-Warning "Publishing '$ProductName'. Microsoft's portal blocks Publish unless a data product access policy is already configured (Manage policies) - this script does not create one (README.md Section 11). If this call fails, configure the access policy in the portal first."
    if (-not $current) {
        Write-Verbose 'WhatIf: publish would run a GET-then-PUT sequence; skipping the PUT body build against a null GET result.'
        return
    }
    # Full-replace PUT reusing the server's own current fields, changing only status - the same
    # discipline as New-BusinessGlossary.ps1's ConvertTo-TermUpdateBody, so a portal-made edit
    # (e.g. terms of use added directly in the UI) survives this status-only transition.
    $body = @{
        id              = $current.id
        domain          = $current.domain
        name            = $current.name
        status          = 'PUBLISHED'
        type            = $current.type
        description     = $current.description
        businessUse     = $current.businessUse
        updateFrequency = $current.updateFrequency
        audience        = @($current.audience)
        endorsed        = [bool]$current.endorsed
        contacts        = $current.contacts
    }
    $uri = "$endpoint/datagovernance/catalog/dataProducts/$ProductId?api-version=$ApiVersion"
    Invoke-Ucm -Method Put -Uri $uri -Body $body -Token $Token `
        -Description "Publish data product '$ProductName'" | Out-Null
    Write-Host "Published data product '$ProductName'." -ForegroundColor Green
}

# --- Load and validate the definition file ---
$definition = Get-Content -Path $DefinitionPath -Raw | ConvertFrom-Json
if (-not $definition.domain -or -not $definition.dataProduct -or -not $definition.dataAsset) {
    throw "Definition file '$DefinitionPath' must contain 'domain', 'dataProduct', and 'dataAsset' objects."
}
if ($definition.dataAsset.dataMapAssetId -eq $nilGuid) {
    throw "Definition file '$DefinitionPath' still has the placeholder Data Map asset GUID ($nilGuid). Replace 'dataAsset.dataMapAssetId' with the real asset ID before running (README.md Section 11)."
}

$plainSecret = ConvertTo-PlainText -Secure $ClientSecret
try {
    $ucToken = Get-PurviewAccessToken -TenantId $TenantId -AppId $AppId -PlainSecret $plainSecret
    $graphToken = Get-GraphAccessToken -TenantId $TenantId -AppId $AppId -PlainSecret $plainSecret
}
finally {
    $plainSecret = $null
}

# --- Step 1: resolve the (already-existing) governance domain ---
$domain = Find-BusinessDomainByName -Name $definition.domain.name -Token $ucToken
if (-not $domain) {
    throw "Governance domain '$($definition.domain.name)' was not found. This scenario reuses an existing domain (e.g. from scenarios/unified-catalog/curate-business-glossary/) rather than creating one - run that scenario, or create the domain manually, first."
}

# --- Step 2: create or update the data product ---
$contactCache = @{}
$productId = Get-OrNewDataProduct -ProductDef $definition.dataProduct -DomainId $domain.id `
    -Token $ucToken -GraphToken $graphToken -ContactCache $contactCache

# --- Step 3: wrap the Data Map asset as a Unified Catalog data asset ---
$dataAssetId = Get-OrNewDataAsset -DataMapAssetId $definition.dataAsset.dataMapAssetId -Token $ucToken

# --- Step 4: link the data asset and every related term to the data product ---
Add-DataProductRelationship -DataProductId $productId -ProductName $definition.dataProduct.name `
    -EntityType 'DATAASSET' -EntityId $dataAssetId -EntityLabel $definition.dataAsset.dataMapAssetId -Token $ucToken

foreach ($termName in $definition.relatedTerms) {
    $term = Find-TermByName -Name $termName -DomainId $domain.id -Token $ucToken
    if (-not $term) {
        Write-Warning "Term '$termName' was not found in domain '$($definition.domain.name)'. Skipped - create it first (e.g. via scenarios/unified-catalog/curate-business-glossary/)."
        continue
    }
    Add-DataProductRelationship -DataProductId $productId -ProductName $definition.dataProduct.name `
        -EntityType 'TERM' -EntityId $term.id -EntityLabel $termName -Token $ucToken
}

# --- Step 5 (optional): publish ---
if ($Publish) {
    Publish-DataProduct -ProductName $definition.dataProduct.name -ProductId $productId -Token $ucToken
}
else {
    Write-Host "`nData product left in DRAFT status (visible only to Data Stewards / Data Product Owners / Governance Domain Owners). Configure a data product access policy in the portal, then re-run with -Publish." -ForegroundColor Cyan
}

Write-Host "`nDone. Run validate/Test-DataProduct.ps1 to verify the deployed configuration." -ForegroundColor Cyan
