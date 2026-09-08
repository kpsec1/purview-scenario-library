#Requires -Version 7.0
<#
.SYNOPSIS
    Idempotently models a custom data-processing job as a Process-typed Microsoft Purview Data Map
    entity and links it into the lineage graph between two already-registered DataSet entities,
    i.e. DataSet -> Process -> DataSet rather than a single unattributed direct edge.

.DESCRIPTION
    Closes the gap `scenarios/data-lineage/end-to-end-lineage-validation/design.md` Section 7
    deliberately left open: that scenario asserts only a `direct_lineage_dataset_dataset` edge
    because its own grounding pass did not confirm a REST-documented body for creating a *custom*
    Process-typed entity. This scenario's grounding pass found and directly confirmed that body -
    Microsoft's own "Create and get lineage relationships using the REST API" tutorial's Example 1
    creates a Process-typed entity (`hive_view_query`, inheriting the built-in Process type) via
    Entity - Bulk Create Or Update, then links it to two DataSet entities with a
    `dataset_process_inputs` and a `process_dataset_outputs` relationship - and the same tutorial's
    "Create New Custom Types" section separately confirms the body for creating a *custom* Process
    type via Type - Bulk Create (`superTypes: ["Process"]`). This script combines both, directly
    grounded, confirmed shapes (README.md Section 12, references 5-6) rather than the single
    generic Process type: a custom type lets the Process entity carry scenario-specific attributes
    (a runbook URL, a schedule expression) that the bare built-in Process type does not.

    Three REST calls, in order, each independently idempotent:
      1. Type - Bulk Create (`POST /datamap/api/atlas/v2/types/typedefs`) - creates the custom
         Process type definition, but ONLY if Type - Get Entity Def By Name
         (`GET /datamap/api/atlas/v2/types/entitydef/name/{name}`) doesn't already find it. Type -
         Bulk Create's own reference page explicitly warns "Please avoid recreating existing
         types" - unlike Entity - Bulk Create Or Update (next step), it is not documented as an
         upsert, so this script never calls it without checking first.
      2. Entity - Bulk Create Or Update (`POST /datamap/api/atlas/v2/entity/bulk`) - creates or
         updates the Process entity itself. This operation's own reference page states plainly:
         "Existing entity is matched using its unique guid if supplied or by its unique attributes
         eg: qualifiedName" - a directly confirmed upsert, so no separate existence check is
         needed here (a genuine, stronger-grounded improvement over the sibling scenario's
         Relationship - Create path, whose duplicate-POST behavior is NOT confirmed - see step 3).
      3. Relationship - Create (`POST /datamap/api/atlas/v2/relationship`) x2 - links upstream
         DataSet -> Process (`dataset_process_inputs`) and Process -> downstream DataSet
         (`process_dataset_outputs`), each ONLY if a single Lineage - Get By Unique Attribute call
         (direction OUTPUT, depth 2, from the upstream asset) doesn't already show the relation -
         the same existence-check idiom `end-to-end-lineage-validation/deploy/
         New-CustomLineageRelationship.ps1` uses, for the same reason: Relationship - Create's
         reference page doesn't state whether a duplicate POST rejects, no-ops, or duplicates.

    Author-only reference code. Never connects to a live tenant unless you supply real credentials
    and omit -WhatIf. Both the upstream and downstream DataSet assets must already exist in the
    Data Map (registered and scanned) before this script is run - see README.md Section 3/6. This
    script creates only the Process entity and the two relationships connecting it to those
    already-existing assets.

.PARAMETER PurviewAccountEndpoint
    Base URL of the Purview Data Map / Atlas v2 data-plane API. Use
    'https://api.purview-service.microsoft.com' (current portal) or
    'https://<account>.purview.azure.com' (classic portal) - both Microsoft's own documented
    endpoint choices for this API family, same as the sibling end-to-end-lineage-validation
    scenario (README.md reference 9 there).

.PARAMETER TenantId
    Microsoft Entra tenant ID.

.PARAMETER AppId
    Application (client) ID of the service principal used to call the Data Map REST API. Must
    hold the Data Curator role on the collection containing the upstream/downstream assets
    (README.md Section 3, docs/rbac-model.md Section 5).

.PARAMETER ClientSecret
    Client secret for -AppId, as a SecureString. Resolve from a vault at run time - never hard-code.

.PARAMETER LineageDefinitionPath
    Path to the process-lineage definition JSON file. See
    deploy/lineage/customer-risk-summary-process-lineage.json for the expected shape
    (processTypeDefinition + process + upstream + downstream). The upstream/downstream
    qualifiedName values must be copied from each asset's Overview page in the Purview portal -
    this scenario's grounding pass did not independently confirm the exact qualifiedName string
    format Purview assigns to an azure_sql_table asset (the same open item the sibling scenario
    already carries - README.md Section 11). The process qualifiedName has no such constraint -
    it's authored fresh by this script, not copied from an existing asset.

.PARAMETER ApiVersion
    Data Map / Atlas v2 REST API version to pin. Defaults to '2023-09-01', confirmed current via
    a direct fetch of Microsoft's own REST reference pages for all four operations this script
    calls (Type - Bulk Create, Type - Get Entity Def By Name, Entity - Bulk Create Or Update,
    Relationship - Create) plus Lineage - Get By Unique Attribute.

.PARAMETER WhatIf
    Standard PowerShell ShouldProcess dry-run. Reports every mutating REST call (Type - Bulk
    Create, Entity - Bulk Create Or Update, Relationship - Create) that would be made without
    sending it. The existence-check GET calls (Type - Get Entity Def By Name, Lineage - Get By
    Unique Attribute) always execute, including under -WhatIf, so the script can accurately report
    create-vs-skip.

.EXAMPLE
    ./New-CustomProcessLineage.ps1 -PurviewAccountEndpoint 'https://api.purview-service.microsoft.com' `
        -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
        -LineageDefinitionPath './lineage/customer-risk-summary-process-lineage.json' -WhatIf

    Dry-run: shows whether the custom type, the Process entity, and each relationship already
    exist, and what would be created - changes nothing.

.EXAMPLE
    ./New-CustomProcessLineage.ps1 -PurviewAccountEndpoint 'https://api.purview-service.microsoft.com' `
        -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
        -LineageDefinitionPath './lineage/customer-risk-summary-process-lineage.json'

    Creates the custom Process type (if missing), upserts the Process entity, and creates either
    or both relationships if missing. Safe to re-run - nothing is duplicated.

.NOTES
    VERIFY before production use (see README.md Section 11 for full detail):
    - The exact qualifiedName string format Purview assigns to an azure_sql_table asset (applies
      to -Upstream/-Downstream only, not the Process entity, whose qualifiedName this script
      authors itself). Same open item as end-to-end-lineage-validation/README.md Section 11.
    - Whether Relationship - Create rejects, no-ops, or duplicates a second POST of an identical
      relationship. This script's own existence check (a single depth-2 Lineage - Get By Unique
      Attribute call before either relationship POST) makes its own idempotency independent of the
      answer.
    - The exact HTTP status code Type - Get Entity Def By Name returns when the named type does
      NOT exist. Its reference page documents only a 200 OK success shape and a generic "Other
      Status Codes -> AtlasErrorResponse" for everything else, without naming the not-found status
      explicitly. This script treats ANY non-success response from that GET as "type does not
      exist yet" (defensive default - see Test-ProcessTypeExists below) rather than assuming 404
      specifically.
    - Whether a relationship end's `typeName` must be the entity's own concrete type
      (`PurviewScenarioLibraryEtlProcess`) or may be an ancestor type (`Process`) when resolving by
      `uniqueAttributes.qualifiedName`. This script uses the literal `Process` for both
      relationship ends that reference the Process entity, exactly matching Microsoft's own worked
      example (README.md reference 5), where the created entity's concrete type was
      `hive_view_query` but the relationship JSON referenced it as `Process`. Not independently
      re-confirmed for a *custom* subtype specifically (as opposed to a built-in one like
      `hive_view_query`) - flagged in README.md Section 11.

    Sources (Microsoft Learn, verify before production use):
    - Create and get lineage relationships using the REST API (Example 1: create a Process entity
      and both relationship types; "Create New Custom Types": custom Process/DataSet type bodies):
      https://learn.microsoft.com/purview/data-gov-api-create-lineage-relationships
    - Entity - Bulk Create Or Update REST reference (API version 2023-09-01; confirms
      upsert-by-qualifiedName semantics in its own description):
      https://learn.microsoft.com/rest/api/purview/datamapdataplane/entity/bulk-create-or-update
    - Type - Bulk Create REST reference (API version 2023-09-01; "Please avoid recreating existing
      types"):
      https://learn.microsoft.com/rest/api/purview/datamapdataplane/type/bulk-create
    - Type - Get Entity Def By Name REST reference (API version 2023-09-01):
      https://learn.microsoft.com/rest/api/purview/datamapdataplane/type/get-entity-def-by-name
    - Relationship - Create REST reference (API version 2023-09-01):
      https://learn.microsoft.com/rest/api/purview/datamapdataplane/relationship/create
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

function Test-ProcessTypeExists {
    # Type - Get Entity Def By Name. Any non-success response (this script does not assume the
    # not-found status is specifically 404 - see .NOTES) is treated as "does not exist yet".
    param(
        [Parameter(Mandatory)][string]$TypeName,
        [Parameter(Mandatory)][string]$Token
    )
    $uri = "$endpoint/datamap/api/atlas/v2/types/entitydef/name/$TypeName`?api-version=$ApiVersion"
    try {
        Invoke-RestMethod -Method Get -Uri $uri -Headers @{ Authorization = "Bearer $Token" } | Out-Null
        return $true
    }
    catch {
        return $false
    }
}

function New-ProcessTypeDefinition {
    param(
        [Parameter(Mandatory)][pscustomobject]$TypeDef,
        [Parameter(Mandatory)][string]$Token
    )
    if (Test-ProcessTypeExists -TypeName $TypeDef.name -Token $Token) {
        # Existence-only check, deliberately not a schema comparison: this script never attempts
        # to reconcile an existing type's attributeDefs against this definition file, because no
        # "update an existing type definition" body was confirmed in this scenario's grounding
        # pass, and Type - Bulk Create's own reference page warns against recreating existing
        # types. A type edited out-of-band could silently drift from this file - caught (not
        # fixed) by validate/Test-ProcessLineage.ps1's schema-drift check, per this scenario's
        # Blue Team/Product Owner review (reviews.md).
        Write-Host "[SKIP] Custom Process type '$($TypeDef.name)' already exists (attribute shape not re-verified - see validate/Test-ProcessLineage.ps1)." -ForegroundColor Yellow
        return
    }

    $body = @{
        enumDefs           = @()
        structDefs          = @()
        classificationDefs = @()
        relationshipDefs   = @()
        entityDefs         = @($TypeDef)
    }
    $uri = "$endpoint/datamap/api/atlas/v2/types/typedefs?api-version=$ApiVersion"
    $description = "Create custom Process type '$($TypeDef.name)'"

    if ($PSCmdlet.ShouldProcess($description, "POST $uri")) {
        Invoke-RestMethod -Method Post -Uri $uri -ContentType 'application/json' `
            -Headers @{ Authorization = "Bearer $Token" } -Body ($body | ConvertTo-Json -Depth 10) | Out-Null
        Write-Host "[CREATED] Custom Process type '$($TypeDef.name)'." -ForegroundColor Green
    }
    else {
        Write-Verbose "WhatIf: would $description"
    }
}

function New-ProcessEntity {
    # Entity - Bulk Create Or Update: directly documented as an upsert-by-qualifiedName, so this
    # function never needs a separate existence check - see .DESCRIPTION step 2.
    param(
        [Parameter(Mandatory)][pscustomobject]$Process,
        [Parameter(Mandatory)][string]$Token
    )
    $attributes = @{
        qualifiedName = $Process.qualifiedName
        name          = $Process.displayName
        description   = $Process.description
    }
    if ($Process.runbookUrl) { $attributes.runbookUrl = $Process.runbookUrl }
    if ($Process.scheduleExpression) { $attributes.scheduleExpression = $Process.scheduleExpression }
    if ($Process.columnMapping) {
        # columnMapping is a JSON-encoded *string* attribute, matching Microsoft's own worked
        # DataSet -> Process -> DataSet example (README.md reference 5, Example 1) exactly.
        $attributes.columnMapping = ($Process.columnMapping | ConvertTo-Json -Depth 10 -Compress)
    }

    $body = @{
        entities = @(
            @{
                typeName   = $Process.typeName
                attributes = $attributes
            }
        )
    }
    $uri = "$endpoint/datamap/api/atlas/v2/entity/bulk?api-version=$ApiVersion"
    $description = "Upsert Process entity '$($Process.displayName)' (type $($Process.typeName))"

    if ($PSCmdlet.ShouldProcess($description, "POST $uri")) {
        $result = Invoke-RestMethod -Method Post -Uri $uri -ContentType 'application/json' `
            -Headers @{ Authorization = "Bearer $Token" } -Body ($body | ConvertTo-Json -Depth 10)
        $verb = if ($result.mutatedEntities.CREATE) { 'CREATED' } elseif ($result.mutatedEntities.UPDATE) { 'UPDATED (no-op content match or attribute refresh)' } else { 'RECONCILED' }
        Write-Host "[$verb] Process entity '$($Process.displayName)'." -ForegroundColor Green
    }
    else {
        Write-Verbose "WhatIf: would $description"
    }
}

function Get-UpstreamLineageDepth2 {
    param(
        [Parameter(Mandatory)][pscustomobject]$Upstream,
        [Parameter(Mandatory)][string]$Token
    )
    $encodedQn = [uri]::EscapeDataString($Upstream.qualifiedName)
    $uri = "$endpoint/datamap/api/atlas/v2/lineage/uniqueAttribute/type/$($Upstream.typeName)" +
    "?api-version=$ApiVersion&direction=OUTPUT&depth=2&attr:qualifiedName=$encodedQn"
    return Invoke-RestMethod -Method Get -Uri $uri -Headers @{ Authorization = "Bearer $Token" }
}

function Find-EntityGuidByQualifiedName {
    param([Parameter(Mandatory)][pscustomobject]$Lineage, [Parameter(Mandatory)][string]$QualifiedName)
    return $Lineage.guidEntityMap.PSObject.Properties |
        Where-Object { $_.Value.attributes.qualifiedName -eq $QualifiedName } |
        Select-Object -First 1 -ExpandProperty Name
}

function Test-RelationExists {
    param([Parameter(Mandatory)][pscustomobject]$Lineage, [string]$FromGuid, [string]$ToGuid)
    if (-not $FromGuid -or -not $ToGuid) { return $false }
    return [bool]($Lineage.relations | Where-Object { $_.fromEntityId -eq $FromGuid -and $_.toEntityId -eq $ToGuid })
}

function New-ProcessRelationship {
    param(
        [Parameter(Mandatory)][string]$RelationshipType,
        [Parameter(Mandatory)][hashtable]$End1,
        [Parameter(Mandatory)][hashtable]$End2,
        [Parameter(Mandatory)][string]$Description,
        [Parameter(Mandatory)][string]$Token
    )
    $body = @{ typeName = $RelationshipType; end1 = $End1; end2 = $End2 }
    $uri = "$endpoint/datamap/api/atlas/v2/relationship?api-version=$ApiVersion"

    if ($PSCmdlet.ShouldProcess($Description, "POST $uri")) {
        Invoke-RestMethod -Method Post -Uri $uri -ContentType 'application/json' `
            -Headers @{ Authorization = "Bearer $Token" } -Body ($body | ConvertTo-Json -Depth 10) | Out-Null
        Write-Host "[CREATED] $Description" -ForegroundColor Green
    }
    else {
        Write-Verbose "WhatIf: would create $Description"
    }
}

# --- Load and validate the definition file ---
$definition = Get-Content -Path $LineageDefinitionPath -Raw | ConvertFrom-Json
foreach ($required in 'processTypeDefinition', 'process', 'upstream', 'downstream') {
    if (-not $definition.$required) {
        throw "Definition file '$LineageDefinitionPath' is missing required field '$required'."
    }
}
foreach ($assetRef in $definition.upstream, $definition.downstream) {
    if ([string]::IsNullOrWhiteSpace($assetRef.qualifiedName) -or $assetRef.qualifiedName -like '<REPLACE*') {
        throw "'$($assetRef.displayName)' has an unset or placeholder qualifiedName. Copy the real value from the Purview portal before running this script - see README.md Section 11."
    }
}

$plainSecret = ConvertTo-PlainText -Secure $ClientSecret
try {
    $token = Get-PurviewAccessToken -TenantId $TenantId -AppId $AppId -PlainSecret $plainSecret
}
finally {
    $plainSecret = $null
}

# --- Step 1: custom Process type ---
New-ProcessTypeDefinition -TypeDef $definition.processTypeDefinition -Token $token

# --- Step 2: the Process entity itself (idempotent upsert) ---
New-ProcessEntity -Process $definition.process -Token $token

# --- Step 3: both relationships, each created only if missing ---
$lineage = Get-UpstreamLineageDepth2 -Upstream $definition.upstream -Token $token
$processGuid = Find-EntityGuidByQualifiedName -Lineage $lineage -QualifiedName $definition.process.qualifiedName
$downstreamGuid = Find-EntityGuidByQualifiedName -Lineage $lineage -QualifiedName $definition.downstream.qualifiedName
$upstreamGuid = $lineage.baseEntityGuid

$inputsExist = Test-RelationExists -Lineage $lineage -FromGuid $upstreamGuid -ToGuid $processGuid
if ($inputsExist) {
    Write-Host "[SKIP] '$($definition.upstream.displayName)' -> '$($definition.process.displayName)' (dataset_process_inputs) already exists." -ForegroundColor Yellow
}
else {
    New-ProcessRelationship -RelationshipType 'dataset_process_inputs' `
        -End1 @{ typeName = $definition.upstream.typeName; uniqueAttributes = @{ qualifiedName = $definition.upstream.qualifiedName } } `
        -End2 @{ typeName = 'Process'; uniqueAttributes = @{ qualifiedName = $definition.process.qualifiedName } } `
        -Description "'$($definition.upstream.displayName)' -> '$($definition.process.displayName)' (dataset_process_inputs)" `
        -Token $token
}

# The outputs check only means anything once the Process entity is known to exist (processGuid
# resolved) - under -WhatIf on a first run against an empty tenant, processGuid will be $null
# (the entity wasn't actually created), so this is correctly reported as "would create" too.
$outputsExist = Test-RelationExists -Lineage $lineage -FromGuid $processGuid -ToGuid $downstreamGuid
if ($outputsExist) {
    Write-Host "[SKIP] '$($definition.process.displayName)' -> '$($definition.downstream.displayName)' (process_dataset_outputs) already exists." -ForegroundColor Yellow
}
else {
    New-ProcessRelationship -RelationshipType 'process_dataset_outputs' `
        -End1 @{ typeName = 'Process'; uniqueAttributes = @{ qualifiedName = $definition.process.qualifiedName } } `
        -End2 @{ typeName = $definition.downstream.typeName; uniqueAttributes = @{ qualifiedName = $definition.downstream.qualifiedName } } `
        -Description "'$($definition.process.displayName)' -> '$($definition.downstream.displayName)' (process_dataset_outputs)" `
        -Token $token
}

Write-Host "`nDone. Run validate/Test-ProcessLineage.ps1 to confirm the full DataSet -> Process -> DataSet chain is connected." -ForegroundColor Cyan
