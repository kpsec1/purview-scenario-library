---
part: "deploy"
parent: "data-lineage/end-to-end-lineage-validation"
---
The scripts and configuration below deploy this scenario. Review them, then run in order — each is designed to be idempotent and has a matching rollback.


#### `lineage/customer-risk-summary-lineage.json`

```json
{
  "originAssetTypeName": "azure_sql_table",
  "originAssetQualifiedName": "<REPLACE - copy from customerdb.dbo.Customers asset's Overview page in the Purview portal>",
  "originAssetDisplayName": "customerdb.dbo.Customers",
  "customLineageLinks": [
    {
      "description": "Nightly customer risk-scoring extract. A custom Python job (Azure Functions timer trigger, not Azure Data Factory or any other Purview-lineage-integrated processing system) reads customerdb.dbo.Customers and writes an aggregated risk score per customer into analyticsdb.dbo.CustomerRiskSummary. Purview never sees this hop automatically - see README.md Section 2/11.",
      "relationshipType": "direct_lineage_dataset_dataset",
      "upstreamTypeName": "azure_sql_table",
      "upstreamQualifiedName": "<REPLACE - copy from customerdb.dbo.Customers asset's Overview page in the Purview portal>",
      "upstreamDisplayName": "customerdb.dbo.Customers",
      "downstreamTypeName": "azure_sql_table",
      "downstreamQualifiedName": "<REPLACE - copy from analyticsdb.dbo.CustomerRiskSummary asset's Overview page in the Purview portal>",
      "downstreamDisplayName": "analyticsdb.dbo.CustomerRiskSummary",
      "columnMapping": [
        { "Source": "CustomerId", "Sink": "CustomerId" }
      ]
    }
  ],
  "expectedDownstreamChain": [
    {
      "qualifiedName": "<REPLACE - copy from analyticsdb.dbo.CustomerRiskSummary asset's Overview page in the Purview portal>",
      "displayName": "analyticsdb.dbo.CustomerRiskSummary",
      "typeName": "azure_sql_table"
    }
  ]
}
```

#### `New-CustomLineageRelationship.ps1`

```powershell
#Requires -Version 7.0
<#
.SYNOPSIS
    Idempotently creates custom Microsoft Purview Data Map lineage relationships between two
    already-registered assets, to close a lineage gap left by a data-processing system that
    isn't one of Purview's automatic-lineage-integrated systems.

.DESCRIPTION
    Calls the Microsoft Purview Data Map / Atlas v2 REST API (automation surface 4 per
    docs/automation-surface.md Section 1, API version 2023-09-01) to create a
    'direct_lineage_dataset_dataset' relationship - DataSet1 is upstream of DataSet2, with an
    optional column-level mapping - between two DataSet-typed entities that already exist in the
    Data Map (this script never creates entities, only the lineage relationship between them).

    This is the documented pattern for the case Microsoft's own lineage articles describe:
    "In certain situations, Microsoft Purview's automatically generated lineage is incomplete or
    missing... custom lineage reporting is supported by Apache Atlas hooks and the REST API"
    (README.md reference 6). A direct dataset-to-dataset relationship is used rather than
    modeling an intermediate Process entity, because this build's grounding pass did not confirm
    a REST-documented shape for creating a *custom* Process entity type (see README.md Section 11)
    - direct_lineage_dataset_dataset is explicitly documented for exactly this "we know table A
    feeds table B, but don't want to model the transform as its own asset" case (README.md
    reference 5).

    Idempotent by construction: before creating a relationship, this script calls Lineage - Get By
    Unique Attribute on the upstream asset (direction OUTPUT, depth 1) and checks whether a
    relation to the downstream asset's GUID already exists in the response. Only missing
    relationships are created. This build's grounding pass did not find an explicit statement of
    whether Relationship - Create itself rejects or duplicates a second POST of an identical
    relationship (see README.md Section 11 VERIFY) - this script's own existence check makes that
    question irrelevant to its correctness, matching the idiom already established in this repo's
    scenarios/data-quality/rules-and-scorecards/deploy/New-DataQualityRulesAndSchedule.ps1.

    Author-only reference code. Never connects to a live tenant unless you supply real credentials
    and omit -WhatIf. Both the upstream and downstream assets must already exist in the Data Map
    (registered and scanned) before this script is run - see README.md Section 3/6.

.PARAMETER PurviewAccountEndpoint
    Base URL of the Purview Data Map / Atlas v2 data-plane API. Use
    'https://api.purview-service.microsoft.com' for tenants on the current Microsoft Purview
    portal, or 'https://<account>.purview.azure.com' for the classic portal - both values are
    Microsoft's own documented endpoint choices for this exact API family (README.md reference 9).

.PARAMETER TenantId
    Microsoft Entra tenant ID.

.PARAMETER AppId
    Application (client) ID of the service principal used to call the Data Map REST API. Must
    hold the Data Curator role on the collection containing the two target assets (README.md
    Section 3, docs/rbac-model.md Section 5).

.PARAMETER ClientSecret
    Client secret for -AppId, as a SecureString. Resolve from a vault at run time - never hard-code.

.PARAMETER LineageDefinitionPath
    Path to the lineage definition JSON file. See
    deploy/lineage/customer-risk-summary-lineage.json for the expected shape
    (originAssetQualifiedName + a customLineageLinks array). Each link's upstream/downstream
    qualifiedName must be copied from the existing asset's Overview page in the Purview portal -
    this build's grounding pass did not independently confirm the exact qualifiedName string
    format Purview assigns to an azure_sql_table asset, so this script does not attempt to
    construct or guess it (README.md Section 11).

.PARAMETER ApiVersion
    Data Map / Atlas v2 REST API version to pin. Defaults to '2023-09-01', confirmed current via
    a direct fetch of Microsoft's own REST reference pages for all four operations this scenario
    uses (Entity - Bulk Create Or Update is not called by this script, but Relationship - Create,
    Lineage - Get, and Lineage - Get By Unique Attribute all confirm this same version).

.PARAMETER WhatIf
    Standard PowerShell ShouldProcess dry-run. Reports every REST call that would be made without
    sending any mutating (POST) request. Invoke-RestMethod has no native ShouldProcess
    integration, so this script wraps each mutating call in its own $PSCmdlet.ShouldProcess()
    check. The existence-check GET calls always execute, including under -WhatIf, so the script
    can accurately report create-vs-skip for each link.

.EXAMPLE
    ./New-CustomLineageRelationship.ps1 -PurviewAccountEndpoint 'https://api.purview-service.microsoft.com' `
        -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
        -LineageDefinitionPath './lineage/customer-risk-summary-lineage.json' -WhatIf

    Dry-run: shows exactly which links already exist and which would be created, changes nothing.

.EXAMPLE
    ./New-CustomLineageRelationship.ps1 -PurviewAccountEndpoint 'https://api.purview-service.microsoft.com' `
        -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
        -LineageDefinitionPath './lineage/customer-risk-summary-lineage.json'

    Creates any missing custom lineage relationships in the definition file. Safe to re-run - an
    already-existing relationship is reported and skipped, never duplicated.

.NOTES
    VERIFY before production use (see README.md Section 11 for full detail):
    - Whether Relationship - Create rejects, no-ops, or duplicates a second POST of an identical
      relationship. This script's own existence check (Lineage - Get By Unique Attribute before
      every POST) makes its own idempotency independent of the answer, but a production
      integration calling Relationship - Create directly, without this script's check first,
      should confirm the behavior.
    - The exact qualifiedName string format Purview assigns to an azure_sql_table asset. This
      script does not construct or guess it - the operator copies it from the asset's Overview
      page in the portal (or resolves it via the Data Map search/GraphQL API) into the definition
      file. See README.md Section 11.

    Sources (Microsoft Learn, verify before production use):
    - Create and get lineage relationships using the REST API (concepts, relationship types,
      worked Bulk Create / Create Relationship / Get Lineage examples):
      https://learn.microsoft.com/purview/data-gov-api-create-lineage-relationships
    - Relationship - Create REST reference (API version 2023-09-01):
      https://learn.microsoft.com/rest/api/purview/datamapdataplane/relationship/create
    - Lineage - Get By Unique Attribute REST reference (API version 2023-09-01):
      https://learn.microsoft.com/rest/api/purview/datamapdataplane/lineage/get-by-unique-attribute
    - Tutorial: Authenticate for Microsoft Purview data-plane APIs (token acquisition, Data
      Curator/Data Reader roles for the Catalog Data plane):
      https://learn.microsoft.com/purview/data-gov-api-rest-data-plane
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
    # v1 client-credentials flow against the shared Data Map / Unified Catalog data-plane
    # resource, per docs/automation-surface.md Section 3.
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

function Get-LineageByUniqueAttribute {
    param(
        [Parameter(Mandatory)][string]$TypeName,
        [Parameter(Mandatory)][string]$QualifiedName,
        [Parameter(Mandatory)][ValidateSet('INPUT', 'OUTPUT', 'BOTH')][string]$Direction,
        [Parameter(Mandatory)][int]$Depth,
        [Parameter(Mandatory)][string]$Token
    )
    $encodedQn = [uri]::EscapeDataString($QualifiedName)
    $uri = "$endpoint/datamap/api/atlas/v2/lineage/uniqueAttribute/type/$TypeName" +
    "?api-version=$ApiVersion&direction=$Direction&depth=$Depth&attr:qualifiedName=$encodedQn"
    return Invoke-RestMethod -Method Get -Uri $uri -Headers @{ Authorization = "Bearer $Token" }
}

function Test-LinkAlreadyExists {
    # Looks up the upstream asset's own OUTPUT lineage at depth 1 and checks whether a relation
    # already points at an entity whose qualifiedName matches the downstream target - this is the
    # existence check that makes this script's idempotency independent of Relationship - Create's
    # own (unconfirmed) duplicate-POST behavior. See the script's .NOTES.
    param(
        [Parameter(Mandatory)][pscustomobject]$Link,
        [Parameter(Mandatory)][string]$Token
    )
    $lineage = Get-LineageByUniqueAttribute -TypeName $Link.upstreamTypeName `
        -QualifiedName $Link.upstreamQualifiedName -Direction OUTPUT -Depth 1 -Token $Token

    $downstreamGuid = $lineage.guidEntityMap.PSObject.Properties |
        Where-Object { $_.Value.attributes.qualifiedName -eq $Link.downstreamQualifiedName } |
        Select-Object -First 1 -ExpandProperty Name

    if (-not $downstreamGuid) { return $false }

    $baseGuid = $lineage.baseEntityGuid
    return [bool]($lineage.relations | Where-Object {
            $_.fromEntityId -eq $baseGuid -and $_.toEntityId -eq $downstreamGuid
        })
}

function New-CustomLineageLink {
    param(
        [Parameter(Mandatory)][pscustomobject]$Link,
        [Parameter(Mandatory)][string]$Token
    )
    if ($Link.relationshipType -ne 'direct_lineage_dataset_dataset') {
        throw "Link '$($Link.description)' uses relationshipType '$($Link.relationshipType)' - " +
        "this script only supports 'direct_lineage_dataset_dataset'. See README.md Section 11/design.md Section 7."
    }

    if (Test-LinkAlreadyExists -Link $Link -Token $Token) {
        Write-Host "[SKIP] Lineage already connects '$($Link.upstreamDisplayName)' -> '$($Link.downstreamDisplayName)'." -ForegroundColor Yellow
        return
    }

    $body = @{
        typeName = 'direct_lineage_dataset_dataset'
        end1     = @{
            typeName        = $Link.upstreamTypeName
            uniqueAttributes = @{ qualifiedName = $Link.upstreamQualifiedName }
        }
        end2     = @{
            typeName        = $Link.downstreamTypeName
            uniqueAttributes = @{ qualifiedName = $Link.downstreamQualifiedName }
        }
    }
    if ($Link.columnMapping) {
        # columnMapping is a JSON-encoded *string* attribute, not a nested JSON object - matching
        # Microsoft's own worked example exactly (README.md reference 5/Example 2).
        $body.attributes = @{ columnMapping = ($Link.columnMapping | ConvertTo-Json -Depth 5 -Compress) }
    }

    $uri = "$endpoint/datamap/api/atlas/v2/relationship?api-version=$ApiVersion"
    $description = "Create direct_lineage_dataset_dataset '$($Link.upstreamDisplayName)' -> '$($Link.downstreamDisplayName)'"

    if ($PSCmdlet.ShouldProcess($description, "POST $uri")) {
        Invoke-RestMethod -Method Post -Uri $uri -ContentType 'application/json' `
            -Headers @{ Authorization = "Bearer $Token" } -Body ($body | ConvertTo-Json -Depth 10) | Out-Null
        Write-Host "[CREATED] Lineage relationship '$($Link.upstreamDisplayName)' -> '$($Link.downstreamDisplayName)'." -ForegroundColor Green
    }
    else {
        Write-Verbose "WhatIf: would $description"
    }
}

# --- Load and validate the definition file ---
$definition = Get-Content -Path $LineageDefinitionPath -Raw | ConvertFrom-Json
foreach ($required in 'originAssetQualifiedName', 'customLineageLinks') {
    if (-not $definition.$required) {
        throw "Definition file '$LineageDefinitionPath' is missing required field '$required'."
    }
}
foreach ($link in $definition.customLineageLinks) {
    foreach ($field in 'upstreamQualifiedName', 'downstreamQualifiedName', 'upstreamTypeName', 'downstreamTypeName') {
        if ([string]::IsNullOrWhiteSpace($link.$field) -or $link.$field -like '<REPLACE*') {
            throw "Link '$($link.description)' has an unset or placeholder '$field'. Copy the real qualifiedName from the Purview portal before running this script - see README.md Section 11."
        }
    }
}

$plainSecret = ConvertTo-PlainText -Secure $ClientSecret
try {
    $token = Get-PurviewAccessToken -TenantId $TenantId -AppId $AppId -PlainSecret $plainSecret
}
finally {
    $plainSecret = $null
}

foreach ($link in $definition.customLineageLinks) {
    New-CustomLineageLink -Link $link -Token $token
}

Write-Host "`n$($definition.customLineageLinks.Count) custom lineage link(s) reconciled." -ForegroundColor Cyan
Write-Host "Run validate/Test-EndToEndLineage.ps1 to walk the full graph from '$($definition.originAssetDisplayName)' and confirm end-to-end connectivity." -ForegroundColor Cyan
```

#### `Remove-CustomLineageRelationship.ps1`

```powershell
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
```