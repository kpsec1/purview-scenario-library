#Requires -Version 7.0
<#
.SYNOPSIS
    Idempotently creates or updates a Microsoft Purview Unified Catalog objective (OKR) and its key
    results, and links the objective to one or more already-existing data products, from a
    declarative JSON definition file.

.DESCRIPTION
    Calls the Microsoft Purview Unified Catalog REST API (automation surface 4 per
    docs/automation-surface.md) to:
      1. Resolve the governance domain named in the definition file (must already exist - this
         scenario reuses the domain scenarios/unified-catalog/curate-business-glossary/ creates,
         it does not create one).
      2. Resolve any owner identity that isn't already an Entra object ID, via Microsoft Graph -
         the same owner-resolution pattern scenarios/unified-catalog/manage-data-products/ and
         .../manage-critical-data-elements/ use.
      3. Create or update (upsert) the objective itself, via the Okr operation group.
      4. Create or update (upsert) each key result under that objective, via the same operation
         group's key-result sub-resource.
      5. Link the objective to each named data product - NOT via the Okr operation group (it has
         no relationship operation at all, unlike Data Products/Critical Data Elements/Terms - see
         design.md Section 4), but via the Data Products - Create Relationship operation with
         entityType=OBJECTIVE, called against the already-existing data product
         (scenarios/unified-catalog/manage-data-products/ owns that product's own lifecycle).
      6. Optionally (-Publish) transition the objective from Draft to Published.

    Idempotency is deliberately NOT name-based, unlike every other Unified Catalog scenario in this
    repo. Microsoft's own docs state that OKR names are not required to be unique ("If you use a
    name that already exists, you'll see a warning during the creation process... you won't be
    blocked from using a duplicate name") - a name-based existence check would be ambiguous by
    design for this object type. Instead, the definition file carries a caller-generated 'id' for
    the objective and for each key result (the same caller-generated-id pattern this repo's other
    Unified Catalog Create operations already use, just promoted here to be the sole identity
    check instead of a name-lookup fallback): this script GETs by that id first, creates on a 404,
    and updates (full-body PUT) on a 200 (design.md Section 3).

    This scenario does NOT create the objective-to-data-product link from the objective's own
    side - there is no such operation to call (design.md Section 4). It calls the Data Products
    operation group's Create Relationship operation instead, exactly as
    scenarios/unified-catalog/manage-data-products/'s own New-DataProduct.ps1 already does for
    DATAASSET/TERM, extended here with entityType=OBJECTIVE.

    Author-only reference code. Never connects to a live tenant unless you supply real credentials
    and omit -WhatIf. The objective is created in Draft status unless -Publish is passed.

.PARAMETER PurviewAccountEndpoint
    Base URL of the Purview Unified Catalog data-plane API, e.g.
    'https://api.purview-service.microsoft.com'.

.PARAMETER TenantId
    Microsoft Entra tenant ID.

.PARAMETER AppId
    Application (client) ID of the service principal used to call both the Unified Catalog REST
    API and Microsoft Graph. Must hold the Data Steward role on the target governance domain
    (docs/rbac-model.md Section 5 - README.md Section 3) plus the Graph application permission
    User.Read.All (README.md Section 3).

.PARAMETER ClientSecret
    Client secret for -AppId, as a SecureString. Resolve from a vault at run time - never hard-code.

.PARAMETER DefinitionPath
    Path to the OKR definition JSON file. See
    deploy/config/customer-data-trust-okr.sample.json for the expected shape (domain block,
    objective block with a caller-generated 'id', keyResults array each with its own
    caller-generated 'id', relatedDataProducts array of existing data product names).

.PARAMETER Publish
    If supplied, transitions the objective from Draft to Published after it and its key results
    are created/updated and linked. Microsoft's docs state the governance domain itself must
    already be published first (README.md Section 3) - this script does not publish the domain.
    Omit to leave the objective in Draft for review.

.PARAMETER ApiVersion
    Unified Catalog REST API version to pin. Defaults to '2026-03-20-preview', the version whose
    Okr and Data Products operation groups this script was grounded against.

.PARAMETER WhatIf
    Standard PowerShell ShouldProcess dry-run. Reports every REST call that would be made without
    sending any mutating (POST/PUT/DELETE) request. Invoke-RestMethod has no native ShouldProcess
    integration, so this script wraps each mutating call in its own $PSCmdlet.ShouldProcess() check.

.EXAMPLE
    ./New-Okr.ps1 -PurviewAccountEndpoint 'https://api.purview-service.microsoft.com' `
        -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
        -DefinitionPath './config/customer-data-trust-okr.sample.json' -WhatIf

    Dry-run: shows exactly which REST calls would be made, changes nothing.

.EXAMPLE
    ./New-Okr.ps1 -PurviewAccountEndpoint 'https://api.purview-service.microsoft.com' `
        -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
        -DefinitionPath './config/customer-data-trust-okr.sample.json' -Publish

    Creates/updates the objective and its key results, links to each named data product, publishes.

.NOTES
    VERIFY before production use (see README.md Section 11 and design.md for full detail):
    - The Data Products - Create Relationship operation's REST reference documents only one worked
      request-body example, for entityType=CRITICALDATACOLUMN, whose body includes an `assetId`
      field alongside `entityId`. This script omits `assetId` for the OBJECTIVE relationship it
      creates (sending only entityId/relationshipType/description) - the same reasoning and the
      same open question scenarios/unified-catalog/manage-data-products/'s own
      Add-DataProductRelationship carries for its DATAASSET/TERM relationships. Confirm against a
      pilot tenant if this call is rejected or silently no-ops.
    - Whether a key result's own `domainId` (required on Create/Update Key Result, separate from
      the parent objective's own `domain` field) must exactly match the parent objective's domain,
      or is independently enforced/ignored - not documented either way. This script always sends
      the same domain id for both, which is the only configuration Microsoft's own portal flow
      permits (a key result has no separate domain picker in the UI).
    - The Okr - Update operation's REST reference documents its `additionalProperties` request
      field as type OkrSharedEntityStatus (an enum), inconsistent with Create/Get's own
      ObjectiveAdditionalProperties (an object of computed rollup fields - keyResultsCount,
      overallProgress, etc.) for the same field name on the same resource. This script never sends
      `additionalProperties` on Create or Update, reasoning that a field which is entirely
      platform-computed from the objective's own key results should not be client-supplied -
      flagged as a genuine Microsoft Learn reference inconsistency, not resolved by guessing which
      shape is correct.

    Sources (Microsoft Learn, verify before production use):
    - Okr operation group (Count/Create/Create Key Result/Delete/Delete Key Result/Get/Get Facets/
      Get Key Result/List/List Key Results/Query/Update/Update Key Result):
      https://learn.microsoft.com/rest/api/purview/purview-unified-catalog/okr?view=rest-purview-purview-unified-catalog-2026-03-20-preview
    - Data Products - Create Relationship / Delete Relationship / List Relationships (entityType
      OBJECTIVE and KEYRESULT are documented EntityCategory enum values on all three operations):
      https://learn.microsoft.com/rest/api/purview/purview-unified-catalog/data-products/create-relationship?view=rest-purview-purview-unified-catalog-2026-03-20-preview
    - Objectives and key results (OKRs) in Unified Catalog (concept, duplicate-name behavior):
      https://learn.microsoft.com/purview/unified-catalog-okrs
    - Create and manage OKRs in Unified Catalog (portal flow, steward-role prerequisite, publish
      gating on the governance domain):
      https://learn.microsoft.com/purview/unified-catalog-okrs-create-manage
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
    # that are read-only despite using POST/GET-that-can-404 - those must still execute under
    # -WhatIf so the script can accurately report create vs. update vs. already-linked.
    # -TreatNotFoundAsNull turns a 404 GET into a $null return instead of a thrown exception, so
    # the id-based existence check (design.md Section 3) reads as ordinary control flow.
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

function Get-OrNewObjective {
    # design.md Section 3: identity is the caller-generated 'id' in the definition file, never a
    # name lookup - Microsoft's own docs state OKR names are explicitly allowed to duplicate.
    param(
        [Parameter(Mandatory)][pscustomobject]$ObjectiveDef,
        [Parameter(Mandatory)][string]$DomainId,
        [Parameter(Mandatory)][string]$Token,
        [Parameter(Mandatory)][string]$GraphToken,
        [Parameter(Mandatory)][hashtable]$ContactCache
    )
    $objectiveId = $ObjectiveDef.id
    $getUri = "$endpoint/datagovernance/catalog/objectives/$objectiveId`?api-version=$ApiVersion"
    $existing = Invoke-Ucm -Method Get -Uri $getUri -Token $Token -TreatNotFoundAsNull
    $status = if ($existing) { $existing.status } else { 'Draft' }

    $ownerIds = @($ObjectiveDef.owners | ForEach-Object {
            Resolve-ContactId -Identifier $_ -GraphToken $GraphToken -Cache $ContactCache
        })

    $body = @{
        id          = $objectiveId
        domain      = $DomainId
        definition  = $ObjectiveDef.definition
        status      = $status
        targetDate  = $ObjectiveDef.targetDate
        contacts    = @{ owner = @($ownerIds | ForEach-Object { @{ id = $_ } }) }
    }

    if ($existing) {
        Invoke-Ucm -Method Put -Uri $getUri -Body $body -Token $Token `
            -Description "Update objective '$($ObjectiveDef.definition)'" | Out-Null
        Write-Host "Updated objective '$($ObjectiveDef.definition)' (id: $objectiveId, status: $status)." -ForegroundColor Green
    }
    else {
        $uri = "$endpoint/datagovernance/catalog/objectives?api-version=$ApiVersion"
        Invoke-Ucm -Method Post -Uri $uri -Body $body -Token $Token `
            -Description "Create objective '$($ObjectiveDef.definition)'" | Out-Null
        Write-Host "Created objective '$($ObjectiveDef.definition)' (id: $objectiveId, status: Draft)." -ForegroundColor Green
    }
    return $objectiveId
}

function Get-OrNewKeyResult {
    param(
        [Parameter(Mandatory)][string]$ObjectiveId,
        [Parameter(Mandatory)][string]$DomainId,
        [Parameter(Mandatory)][pscustomobject]$KeyResultDef,
        [Parameter(Mandatory)][string]$Token
    )
    $keyResultId = $KeyResultDef.id
    $getUri = "$endpoint/datagovernance/catalog/objectives/$ObjectiveId/keyResults/$keyResultId`?api-version=$ApiVersion"
    $existing = Invoke-Ucm -Method Get -Uri $getUri -Token $Token -TreatNotFoundAsNull

    $body = @{
        id         = $keyResultId
        domainId   = $DomainId
        definition = $KeyResultDef.definition
        progress   = $KeyResultDef.progress
        goal       = $KeyResultDef.goal
        max        = $KeyResultDef.max
        status     = $KeyResultDef.status
    }

    if ($existing) {
        Invoke-Ucm -Method Put -Uri $getUri -Body $body -Token $Token `
            -Description "Update key result '$($KeyResultDef.definition)'" | Out-Null
        Write-Host "  Updated key result '$($KeyResultDef.definition)' (id: $keyResultId)." -ForegroundColor Green
    }
    else {
        $uri = "$endpoint/datagovernance/catalog/objectives/$ObjectiveId/keyResults?api-version=$ApiVersion"
        Invoke-Ucm -Method Post -Uri $uri -Body $body -Token $Token `
            -Description "Create key result '$($KeyResultDef.definition)'" | Out-Null
        Write-Host "  Created key result '$($KeyResultDef.definition)' (id: $keyResultId)." -ForegroundColor Green
    }
}

function Find-DataProductByName {
    # Duplicated from manage-data-products/deploy/New-DataProduct.ps1 by design - each deploy
    # script in this repo is self-contained (AGENTS.md's per-scenario deliverable model), not a
    # shared module.
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

function Test-DataProductRelationshipExists {
    param(
        [Parameter(Mandatory)][string]$DataProductId,
        [Parameter(Mandatory)][string]$EntityId,
        [Parameter(Mandatory)][string]$Token
    )
    $uri = "$endpoint/datagovernance/catalog/dataProducts/$DataProductId/relationships?api-version=$ApiVersion&entityType=OBJECTIVE"
    $response = Invoke-Ucm -Method Get -Uri $uri -Token $Token
    return [bool]($response.value | Where-Object { $_.entityId -eq $EntityId })
}

function Add-ObjectiveToDataProduct {
    # design.md Section 4: the link is created from the DATA PRODUCT side (Data Products - Create
    # Relationship, entityType=OBJECTIVE) - the Okr operation group itself has no relationship
    # operation at all. VERIFY (README.md Section 11 / this script's .NOTES): the only documented
    # worked request body for this operation is for entityType=CRITICALDATACOLUMN and includes an
    # `assetId` field; this function omits it, matching manage-data-products/New-DataProduct.ps1's
    # own DATAASSET/TERM reasoning.
    param(
        [Parameter(Mandatory)][string]$DataProductName,
        [Parameter(Mandatory)][string]$DomainId,
        [Parameter(Mandatory)][string]$ObjectiveId,
        [Parameter(Mandatory)][string]$ObjectiveLabel,
        [Parameter(Mandatory)][string]$Token
    )
    $product = Find-DataProductByName -Name $DataProductName -DomainId $DomainId -Token $Token
    if (-not $product) {
        Write-Warning "Data product '$DataProductName' was not found in this domain. Skipped - create it first (e.g. via scenarios/unified-catalog/manage-data-products/)."
        return
    }
    if (Test-DataProductRelationshipExists -DataProductId $product.id -EntityId $ObjectiveId -Token $Token) {
        Write-Host "Data product '$DataProductName' is already linked to objective '$ObjectiveLabel'." -ForegroundColor Yellow
        return
    }
    $uri = "$endpoint/datagovernance/catalog/dataProducts/$($product.id)/relationships?api-version=$ApiVersion&entityType=OBJECTIVE"
    $body = @{ entityId = $ObjectiveId; relationshipType = 'Related' }
    Invoke-Ucm -Method Post -Uri $uri -Body $body -Token $Token `
        -Description "Link data product '$DataProductName' -> objective '$ObjectiveLabel'" | Out-Null
    Write-Host "Linked data product '$DataProductName' -> objective '$ObjectiveLabel'." -ForegroundColor Green
}

function Publish-Objective {
    param(
        [Parameter(Mandatory)][string]$ObjectiveLabel,
        [Parameter(Mandatory)][string]$ObjectiveId,
        [Parameter(Mandatory)][string]$Token
    )
    $current = Invoke-Ucm -Method Get -Uri "$endpoint/datagovernance/catalog/objectives/$($ObjectiveId)?api-version=$ApiVersion" -Token $Token
    if ($current -and $current.status -eq 'Published') {
        Write-Host "Objective '$ObjectiveLabel' is already published." -ForegroundColor Yellow
        return
    }
    Write-Warning "Publishing '$ObjectiveLabel'. Microsoft's docs require the governance domain itself to already be published before an OKR within it can be published - this script does not publish the domain (README.md Section 3)."
    if (-not $current) {
        Write-Verbose 'WhatIf: publish would run a GET-then-PUT sequence; skipping the PUT body build against a null GET result.'
        return
    }
    $body = @{
        id         = $current.id
        domain     = $current.domain
        definition = $current.definition
        status     = 'Published'
        targetDate = $current.targetDate
        contacts   = $current.contacts
    }
    $uri = "$endpoint/datagovernance/catalog/objectives/$ObjectiveId`?api-version=$ApiVersion"
    Invoke-Ucm -Method Put -Uri $uri -Body $body -Token $Token `
        -Description "Publish objective '$ObjectiveLabel'" | Out-Null
    Write-Host "Published objective '$ObjectiveLabel'." -ForegroundColor Green
}

# --- Load and validate the definition file ---
$definition = Get-Content -Path $DefinitionPath -Raw | ConvertFrom-Json
if (-not $definition.domain -or -not $definition.objective -or -not $definition.keyResults) {
    throw "Definition file '$DefinitionPath' must contain 'domain', 'objective', and 'keyResults' properties."
}
if ($definition.objective.id -eq $nilGuid) {
    throw "Definition file '$DefinitionPath' still has the placeholder objective id ($nilGuid). Generate a real GUID (e.g. PowerShell's [guid]::NewGuid()) and set 'objective.id' before running (README.md Section 11) - unlike this repo's other Unified Catalog scenarios, OKR identity is NOT derived from a name lookup (design.md Section 3)."
}
foreach ($kr in $definition.keyResults) {
    if ($kr.id -eq $nilGuid) {
        throw "Definition file '$DefinitionPath' has a 'keyResults' entry still carrying the placeholder id ($nilGuid). Generate a real GUID for every key result before running."
    }
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

# --- Step 2: create or update the objective ---
$contactCache = @{}
$objectiveId = Get-OrNewObjective -ObjectiveDef $definition.objective -DomainId $domain.id `
    -Token $ucToken -GraphToken $graphToken -ContactCache $contactCache

# --- Step 3: create or update each key result ---
Write-Host "`nReconciling key results..." -ForegroundColor Cyan
foreach ($kr in $definition.keyResults) {
    Get-OrNewKeyResult -ObjectiveId $objectiveId -DomainId $domain.id -KeyResultDef $kr -Token $ucToken
}

# --- Step 4: link the objective to every named data product ---
Write-Host "`nLinking to related data products..." -ForegroundColor Cyan
foreach ($productName in $definition.relatedDataProducts) {
    Add-ObjectiveToDataProduct -DataProductName $productName -DomainId $domain.id `
        -ObjectiveId $objectiveId -ObjectiveLabel $definition.objective.definition -Token $ucToken
}

# --- Step 5 (optional): publish ---
if ($Publish) {
    Publish-Objective -ObjectiveLabel $definition.objective.definition -ObjectiveId $objectiveId -Token $ucToken
}
else {
    Write-Host "`nObjective left in Draft status (visible only to Data Stewards / Governance Domain Owners). Configure/confirm the governance domain is published, then re-run with -Publish." -ForegroundColor Cyan
}

Write-Host "`nDone. Run validate/Test-Okr.ps1 to verify the deployed configuration." -ForegroundColor Cyan
