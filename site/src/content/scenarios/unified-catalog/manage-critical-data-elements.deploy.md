---
part: "deploy"
parent: "unified-catalog/manage-critical-data-elements"
---
The scripts and configuration below deploy this scenario. Review them, then run in order — each is designed to be idempotent and has a matching rollback.


#### `config/customer-id-cde.sample.json`

```json
{
  "domain": {
    "name": "Customer Experience",
    "note": "Must match the governance domain created by scenarios/unified-catalog/curate-business-glossary/ - this scenario resolves it by name and does not create a domain of its own."
  },
  "criticalDataElement": {
    "name": "Customer ID",
    "description": "The customer identifier as it appears across every source system that stores a customer record. Different systems spell it differently ('CustID', 'CID', 'CustomerID') - this critical data element maps every one of those columns into the same logical concept so a data quality rule, an access policy, or a consumer's mental model only has to deal with 'Customer ID' once, not once per source.",
    "dataType": "TEXT",
    "owners": ["data-governance-lead@contoso.com"]
  },
  "columns": [
    {
      "dataMapAssetId": "00000000-0000-0000-0000-000000000000",
      "columnName": "CustomerID",
      "note": "REPLACE dataMapAssetId with the real Microsoft Purview Data Map asset GUID for customerdb.dbo.Customers (Azure SQL table registered and scanned by scenarios/data-map/scan-azure-sql-and-classify/, the same asset scenarios/unified-catalog/manage-data-products/ already wraps as a Unified Catalog data asset). columnName must match the column's exact display name in Data Map (case-sensitive - see README.md Section 11) - the script resolves the column's own Data Map GUID from this pair rather than requiring you to hunt for a column-level GUID by hand. Add further entries to this array to map the same logical 'Customer ID' concept from other source systems (e.g. a legacy CRM's 'CustID' column) - critical data elements are designed to aggregate more than one physical column, per README.md Section 1."
    }
  ]
}
```

#### `New-CriticalDataElement.ps1`

```powershell
#Requires -Version 7.0
<#
.SYNOPSIS
    Idempotently creates or updates a Microsoft Purview Unified Catalog critical data element
    (CDE), resolves and wraps one or more Data Map columns as Unified Catalog data columns, and
    links them to the CDE, from a declarative JSON definition file.

.DESCRIPTION
    Calls both the Microsoft Purview Unified Catalog REST API (automation surface 4 per
    docs/automation-surface.md) and the Data Map/Atlas Entity API (the same surface 4 family
    scenarios/data-lineage/end-to-end-lineage-validation/ and .../custom-process-lineage/ already
    use) to:
      1. Resolve the governance domain named in the definition file (must already exist - this
         scenario reuses the domain scenarios/unified-catalog/curate-business-glossary/ creates).
      2. Resolve any owner identity that isn't already an Entra object ID, via Microsoft Graph -
         the same owner-resolution pattern scenarios/unified-catalog/manage-data-products/ uses.
      3. Create or update (upsert) the critical data element itself.
      4. For each entry in the definition file's 'columns' array: resolve the named column's own
         Data Map GUID from its parent table's GUID (GET .../datamap/api/atlas/v2/entity/guid/
         {tableGuid}, matching entity.relationshipAttributes.columns[].displayText - see
         design.md Section 4), wrap it as a Unified Catalog "data column" object
         (Data Columns - Ingest) if not already wrapped, then link it to the critical data
         element (Critical Data Elements - Create Relationship) if not already linked.
      5. Optionally (-Publish) transition the critical data element from DRAFT to PUBLISHED.

    Idempotent by construction: before creating the critical data element, the script queries the
    domain for an existing element with an exact (case-insensitive) name match (design.md Section
    3). Before wrapping each Data Map column, it queries existing Unified Catalog data columns by
    the underlying Data Map asset+column GUID pair (Data Columns - Query, sourceAssetId/
    sourceColumnId filters, includingOrphans=true) so re-running this script never creates a
    second wrapper for the same underlying column. Before creating each CDE-to-column
    relationship, it lists the CDE's existing relationships of that entity category and skips the
    create call if the target is already linked.

    This scenario does NOT create, and cannot create, a link between the critical data element and
    any data product - Microsoft's platform computes the "associated data products" rollup shown
    on a CDE's details page automatically from the shared underlying Data Map asset
    (design.md Section 5). Run validate/Test-CriticalDataElement.ps1 to observe that rollup, not
    this script to create it.

    Author-only reference code. Never connects to a live tenant unless you supply real credentials
    and omit -WhatIf.

.PARAMETER PurviewAccountEndpoint
    Base URL of the Purview Unified Catalog data-plane API, e.g.
    'https://api.purview-service.microsoft.com'.

.PARAMETER DataMapEndpoint
    Base URL of the Purview Data Map/Atlas data-plane API used to resolve column GUIDs. Typically
    the same account endpoint as -PurviewAccountEndpoint (both surfaces share one Purview
    account); kept as a separate parameter because docs/automation-surface.md documents the two
    as distinct REST surfaces with independently-versioned APIs.

.PARAMETER TenantId
    Microsoft Entra tenant ID.

.PARAMETER AppId
    Application (client) ID of the service principal used to call the Unified Catalog REST API,
    the Data Map/Atlas REST API, and Microsoft Graph. Must hold Data Steward AND Data Product
    Owner on the target governance domain (docs/rbac-model.md Section 5 - README.md Section 3
    explains why CDEs require both, unlike manage-data-products' Data Product Owner-only
    requirement) plus at least Data Reader on the Data Map collection housing the source asset.

.PARAMETER ClientSecret
    Client secret for -AppId, as a SecureString. Resolve from a vault at run time - never hard-code.

.PARAMETER DefinitionPath
    Path to the critical data element definition JSON file. See
    deploy/config/customer-id-cde.sample.json for the expected shape (domain block,
    criticalDataElement block, columns array of {dataMapAssetId, columnName}).

.PARAMETER Publish
    If supplied, transitions the critical data element from DRAFT to PUBLISHED after it is
    created/updated and its columns are linked. Unlike manage-data-products' -Publish, this has no
    documented access-policy prerequisite - Microsoft's docs only require the governance domain
    itself to already be published (README.md Section 3). Omit to leave the element in DRAFT for
    review.

.PARAMETER ApiVersion
    Unified Catalog REST API version to pin. Defaults to '2026-03-20-preview' - the version whose
    Critical Data Elements and Data Columns operation groups this script was grounded against.

.PARAMETER DataMapApiVersion
    Data Map/Atlas REST API version to pin for the column-GUID-resolution Entity call. Defaults to
    '2023-09-01', the version docs/automation-surface.md already pins for this repo's other
    Data Map/Atlas work.

.PARAMETER WhatIf
    Standard PowerShell ShouldProcess dry-run. Reports every REST call that would be made without
    sending any mutating (POST/PUT/DELETE) request. Invoke-RestMethod has no native ShouldProcess
    integration, so this script wraps each mutating call in its own $PSCmdlet.ShouldProcess() check.

.EXAMPLE
    ./New-CriticalDataElement.ps1 -PurviewAccountEndpoint 'https://api.purview-service.microsoft.com' `
        -DataMapEndpoint 'https://api.purview-service.microsoft.com' `
        -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
        -DefinitionPath './config/customer-id-cde.sample.json' -WhatIf

    Dry-run: shows exactly which REST calls would be made, changes nothing.

.EXAMPLE
    ./New-CriticalDataElement.ps1 -PurviewAccountEndpoint 'https://api.purview-service.microsoft.com' `
        -DataMapEndpoint 'https://api.purview-service.microsoft.com' `
        -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
        -DefinitionPath './config/customer-id-cde.sample.json' -Publish

    Creates/updates the critical data element, maps its columns, and publishes it.

.NOTES
    VERIFY before production use (see README.md Section 11 and design.md for full detail):
    - Every worked example for the Critical Data Elements Create/List/Delete Relationship
      operations uses entityType=CRITICALDATACOLUMN, but the EntityCategory enum each of those
      same pages formally documents has no such value - it lists DATACOLUMN instead. This script
      sends DATACOLUMN (design.md Section 6). If a tenant rejects it, try CRITICALDATACOLUMN.
    - Whether the Critical Data Elements List Relationships entityType=DATAPRODUCT call actually
      surfaces the portal's automatically-computed "associated data products" rollup, or only a
      relationship this script would have to create itself (which it does not - design.md
      Section 5). validate/Test-CriticalDataElement.ps1 reports this as a WARN, not a FAIL.
    - The Critical Data Elements Query nameKeyword filter's exact match semantics, the same open
      question New-BusinessGlossary.ps1's and New-DataProduct.ps1's own Query calls carry - this
      script applies the identical client-side-exact-match mitigation.
    - Column-name matching (entity.relationshipAttributes.columns[].displayText) is case-sensitive
      exact match. Confirm this against a pilot tenant if a column that visibly exists in the
      portal isn't found by this script.

    Sources (Microsoft Learn, verify before production use):
    - Critical Data Elements operation group (Create/Update/Delete/Get/List/Query/Create
      Relationship/List Relationships/Delete Relationship/Get Facets/Count):
      https://learn.microsoft.com/rest/api/purview/purview-unified-catalog/critical-data-elements?view=rest-purview-purview-unified-catalog-2026-03-20-preview
    - Data Columns operation group (Get/Ingest/Query/Add Related Entity/Delete Related/List
      Related Entities):
      https://learn.microsoft.com/rest/api/purview/purview-unified-catalog/data-columns?view=rest-purview-purview-unified-catalog-2026-03-20-preview
    - Critical data elements (preview) - concept, portal flow, prerequisites, Add columns flow:
      https://learn.microsoft.com/purview/unified-catalog-critical-data-elements
    - Entity - Get (Data Map/Atlas, entity/guid/{guid}):
      https://learn.microsoft.com/rest/api/purview/datamapdataplane/entity/get?view=rest-purview-datamapdataplane-2023-09-01
    - Type definitions and how to create custom types (azure_sql_table's 'columns'
      relationshipAttributeDefs, confirmed via Microsoft's own worked example for this exact
      entity type): https://learn.microsoft.com/purview/data-gov-api-custom-types
    - Learn about data governance billing / billing FAQ (governed-asset dedup across a data
      product and a critical data element sharing the same underlying asset):
      https://learn.microsoft.com/purview/data-governance-billing
      https://learn.microsoft.com/purview/data-governance-billing-faq
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
    [string]$DataMapEndpoint,

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
    [string]$ApiVersion = '2026-03-20-preview',

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$DataMapApiVersion = '2023-09-01'
)

$ErrorActionPreference = 'Stop'

$endpoint = $PurviewAccountEndpoint.TrimEnd('/')
$dataMapEndpoint = $DataMapEndpoint.TrimEnd('/')
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

function Find-CriticalDataElementByName {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$DomainId,
        [Parameter(Mandatory)][string]$Token
    )
    $uri = "$endpoint/datagovernance/catalog/criticalDataElements/query?api-version=$ApiVersion"
    $body = @{ domainIds = @($DomainId); nameKeyword = $Name; top = 50 }
    $response = Invoke-Ucm -Method Post -Uri $uri -Body $body -Token $Token -ReadOnly `
        -Description "Query critical data elements named like '$Name'"
    return ($response.value | Where-Object { $_.name -eq $Name } | Select-Object -First 1)
}

function Get-OrNewCriticalDataElement {
    param(
        [Parameter(Mandatory)][pscustomobject]$CdeDef,
        [Parameter(Mandatory)][string]$DomainId,
        [Parameter(Mandatory)][string]$Token,
        [Parameter(Mandatory)][string]$GraphToken,
        [Parameter(Mandatory)][hashtable]$ContactCache
    )
    $existing = Find-CriticalDataElementByName -Name $CdeDef.name -DomainId $DomainId -Token $Token
    $cdeId = if ($existing) { $existing.id } else { [guid]::NewGuid().ToString() }
    $status = if ($existing) { $existing.status } else { 'DRAFT' }

    $ownerIds = @($CdeDef.owners | ForEach-Object {
            Resolve-ContactId -Identifier $_ -GraphToken $GraphToken -Cache $ContactCache
        })

    $body = @{
        id          = $cdeId
        domain      = $DomainId
        name        = $CdeDef.name
        status      = $status
        dataType    = $CdeDef.dataType
        description = $CdeDef.description
        contacts    = @{ owner = @($ownerIds | ForEach-Object { @{ id = $_ } }) }
    }

    if ($existing) {
        $uri = "$endpoint/datagovernance/catalog/criticalDataElements/$cdeId?api-version=$ApiVersion"
        Invoke-Ucm -Method Put -Uri $uri -Body $body -Token $Token `
            -Description "Update critical data element '$($CdeDef.name)'" | Out-Null
        Write-Host "Updated critical data element '$($CdeDef.name)' (id: $cdeId, status: $status)." -ForegroundColor Green
    }
    else {
        $uri = "$endpoint/datagovernance/catalog/criticalDataElements?api-version=$ApiVersion"
        Invoke-Ucm -Method Post -Uri $uri -Body $body -Token $Token `
            -Description "Create critical data element '$($CdeDef.name)'" | Out-Null
        Write-Host "Created critical data element '$($CdeDef.name)' (id: $cdeId, status: DRAFT)." -ForegroundColor Green
    }
    return $cdeId
}

function Resolve-DataMapColumnId {
    # design.md Section 4: azure_sql_table's own type definition (confirmed via Microsoft's
    # "Type definitions and how to create custom types" tutorial) declares a 'columns'
    # relationshipAttributeDefs entry (relationshipTypeName azure_sql_table_columns) - so the
    # table entity's relationshipAttributes.columns[] array carries each column's own guid and
    # displayText (name). This resolves a plain column name to that guid without requiring the
    # operator to hunt for a column-level GUID by hand.
    param(
        [Parameter(Mandatory)][string]$TableAssetId,
        [Parameter(Mandatory)][string]$ColumnName,
        [Parameter(Mandatory)][string]$Token
    )
    $uri = "$dataMapEndpoint/datamap/api/atlas/v2/entity/guid/$TableAssetId`?api-version=$DataMapApiVersion"
    $response = Invoke-RestMethod -Method Get -Uri $uri -Headers @{ Authorization = "Bearer $Token" }
    $columns = $response.entity.relationshipAttributes.columns
    if (-not $columns) {
        Write-Warning "Data Map entity '$TableAssetId' has no relationshipAttributes.columns - is this really a table entity (e.g. azure_sql_table), and has it completed at least one scan?"
        return $null
    }
    $match = $columns | Where-Object { $_.displayText -ceq $ColumnName } | Select-Object -First 1
    if (-not $match) {
        Write-Warning "No column named '$ColumnName' (case-sensitive) found on Data Map asset '$TableAssetId'. Available: $(($columns | ForEach-Object { $_.displayText }) -join ', ')"
        return $null
    }
    return $match.guid
}

function Find-DataColumnBySource {
    param(
        [Parameter(Mandatory)][string]$DataMapAssetId,
        [Parameter(Mandatory)][string]$DataMapColumnId,
        [Parameter(Mandatory)][string]$Token
    )
    $uri = "$endpoint/datagovernance/catalog/dataColumns/query?api-version=$ApiVersion"
    $body = @{
        includingOrphans = $true
        filter           = @{
            and = @(
                @{ sourceAssetId = @{ eq = $DataMapAssetId } }
                @{ sourceColumnId = @{ eq = $DataMapColumnId } }
            )
        }
    }
    $response = Invoke-Ucm -Method Post -Uri $uri -Body $body -Token $Token -ReadOnly `
        -Description "Query data columns wrapping Data Map column '$DataMapColumnId'"
    return ($response.value | Where-Object { $_.source.columnId -eq $DataMapColumnId } | Select-Object -First 1)
}

function Get-OrNewDataColumn {
    param(
        [Parameter(Mandatory)][string]$DataMapAssetId,
        [Parameter(Mandatory)][string]$DataMapColumnId,
        [Parameter(Mandatory)][string]$Token
    )
    $existing = Find-DataColumnBySource -DataMapAssetId $DataMapAssetId -DataMapColumnId $DataMapColumnId -Token $Token
    if ($existing) {
        Write-Host "Data column wrapper for Data Map column '$DataMapColumnId' already exists (Unified Catalog id: $($existing.id))." -ForegroundColor Yellow
        return $existing.id
    }
    $uri = "$endpoint/datagovernance/catalog/dataColumns/ingest?api-version=$ApiVersion"
    $body = @{ requests = @(@{ dataMapAssetId = $DataMapAssetId; dataMapColumnId = $DataMapColumnId }) }
    $result = Invoke-Ucm -Method Post -Uri $uri -Body $body -Token $Token `
        -Description "Ingest Data Map column '$DataMapColumnId' as a Unified Catalog data column"
    if ($result) {
        Write-Host "Ingested data column wrapper (Unified Catalog id: $($result.id)) for Data Map column '$DataMapColumnId'." -ForegroundColor Green
        return $result.id
    }
    Write-Verbose "WhatIf: data column wrapper for '$DataMapColumnId' would be created; using a placeholder id for the remainder of this dry run."
    return $nilGuid
}

function Test-CdeRelationshipExists {
    param(
        [Parameter(Mandatory)][string]$CdeId,
        [Parameter(Mandatory)][string]$EntityType,
        [Parameter(Mandatory)][string]$EntityId,
        [Parameter(Mandatory)][string]$Token
    )
    $uri = "$endpoint/datagovernance/catalog/criticalDataElements/$CdeId/relationships?api-version=$ApiVersion&entityType=$EntityType"
    $response = Invoke-Ucm -Method Get -Uri $uri -Token $Token
    return [bool]($response.value | Where-Object { $_.entityId -eq $EntityId })
}

function Add-CdeColumnRelationship {
    # design.md Section 6: this repo's grounding pass found every worked example for this
    # operation uses entityType=CRITICALDATACOLUMN, but the formally-documented EntityCategory
    # enum has no such value - it lists DATACOLUMN instead. This function sends DATACOLUMN,
    # reasoning the declared enum is more likely to be the real contract. VERIFY before relying on
    # this at scale (README.md Section 11): if a tenant rejects DATACOLUMN, try CRITICALDATACOLUMN.
    param(
        [Parameter(Mandatory)][string]$CdeId,
        [Parameter(Mandatory)][string]$CdeName,
        [Parameter(Mandatory)][string]$ColumnId,
        [Parameter(Mandatory)][string]$ColumnLabel,
        [Parameter(Mandatory)][string]$Token
    )
    $entityType = 'DATACOLUMN'
    if (Test-CdeRelationshipExists -CdeId $CdeId -EntityType $entityType -EntityId $ColumnId -Token $Token) {
        Write-Host "'$CdeName' is already mapped to column '$ColumnLabel'." -ForegroundColor Yellow
        return
    }
    $uri = "$endpoint/datagovernance/catalog/criticalDataElements/$CdeId/relationships?api-version=$ApiVersion&entityType=$entityType"
    $body = @{ entityId = $ColumnId; relationshipType = 'Related' }
    Invoke-Ucm -Method Post -Uri $uri -Body $body -Token $Token `
        -Description "Map '$CdeName' -> column '$ColumnLabel'" | Out-Null
    Write-Host "Mapped '$CdeName' -> column '$ColumnLabel'." -ForegroundColor Green
}

function Publish-CriticalDataElement {
    param(
        [Parameter(Mandatory)][string]$CdeName,
        [Parameter(Mandatory)][string]$CdeId,
        [Parameter(Mandatory)][string]$Token
    )
    $current = Invoke-Ucm -Method Get -Uri "$endpoint/datagovernance/catalog/criticalDataElements/$($CdeId)?api-version=$ApiVersion" -Token $Token
    if ($current -and $current.status -eq 'PUBLISHED') {
        Write-Host "Critical data element '$CdeName' is already published." -ForegroundColor Yellow
        return
    }
    Write-Warning "Publishing '$CdeName'. Microsoft's docs require the governance domain itself to already be published before a critical data element within it can be published - this script does not publish the domain (README.md Section 3)."
    if (-not $current) {
        Write-Verbose 'WhatIf: publish would run a GET-then-PUT sequence; skipping the PUT body build against a null GET result.'
        return
    }
    $body = @{
        id          = $current.id
        domain      = $current.domain
        name        = $current.name
        status      = 'PUBLISHED'
        dataType    = $current.dataType
        description = $current.description
        contacts    = $current.contacts
    }
    $uri = "$endpoint/datagovernance/catalog/criticalDataElements/$CdeId?api-version=$ApiVersion"
    Invoke-Ucm -Method Put -Uri $uri -Body $body -Token $Token `
        -Description "Publish critical data element '$CdeName'" | Out-Null
    Write-Host "Published critical data element '$CdeName'." -ForegroundColor Green
}

# --- Load and validate the definition file ---
$definition = Get-Content -Path $DefinitionPath -Raw | ConvertFrom-Json
if (-not $definition.domain -or -not $definition.criticalDataElement -or -not $definition.columns) {
    throw "Definition file '$DefinitionPath' must contain 'domain', 'criticalDataElement', and 'columns' properties."
}
foreach ($col in $definition.columns) {
    if ($col.dataMapAssetId -eq $nilGuid) {
        throw "Definition file '$DefinitionPath' has a 'columns' entry still carrying the placeholder Data Map asset GUID ($nilGuid). Replace 'dataMapAssetId' with the real asset ID before running (README.md Section 11)."
    }
}

$plainSecret = ConvertTo-PlainText -Secure $ClientSecret
try {
    $ucToken = Get-PurviewAccessToken -TenantId $TenantId -AppId $AppId -PlainSecret $plainSecret
    $dataMapToken = $ucToken # Both surfaces share the https://purview.azure.net resource token.
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

# --- Step 2: create or update the critical data element ---
$contactCache = @{}
$cdeId = Get-OrNewCriticalDataElement -CdeDef $definition.criticalDataElement -DomainId $domain.id `
    -Token $ucToken -GraphToken $graphToken -ContactCache $contactCache

# --- Step 3: resolve, wrap, and map each column ---
foreach ($col in $definition.columns) {
    $columnLabel = "$($col.dataMapAssetId)/$($col.columnName)"
    $dataMapColumnId = Resolve-DataMapColumnId -TableAssetId $col.dataMapAssetId -ColumnName $col.columnName -Token $dataMapToken
    if (-not $dataMapColumnId) {
        Write-Warning "Skipping column '$columnLabel' - could not resolve its Data Map column GUID."
        continue
    }
    $dataColumnId = Get-OrNewDataColumn -DataMapAssetId $col.dataMapAssetId -DataMapColumnId $dataMapColumnId -Token $ucToken
    Add-CdeColumnRelationship -CdeId $cdeId -CdeName $definition.criticalDataElement.name `
        -ColumnId $dataColumnId -ColumnLabel "$($col.columnName) ($columnLabel)" -Token $ucToken
}

# --- Step 4 (optional): publish ---
if ($Publish) {
    Publish-CriticalDataElement -CdeName $definition.criticalDataElement.name -CdeId $cdeId -Token $ucToken
}
else {
    Write-Host "`nCritical data element left in DRAFT status (visible only to Data Stewards / Data Product Owners / Governance Domain Owners). Re-run with -Publish once you're ready." -ForegroundColor Cyan
}

Write-Host "`nDone. Run validate/Test-CriticalDataElement.ps1 to verify the deployed configuration." -ForegroundColor Cyan
```

#### `Remove-CriticalDataElement.ps1`

```powershell
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
```