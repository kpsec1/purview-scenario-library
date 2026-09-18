---
part: "deploy"
parent: "unified-catalog/manage-critical-data-elements-related-terms"
---
The scripts and configuration below deploy this scenario. Review them, then run in order — each is designed to be idempotent and has a matching rollback.


#### `Add-CdeRelatedTerm.ps1`

```powershell
#Requires -Version 7.0
<#
.SYNOPSIS
    Idempotently links a Microsoft Purview Unified Catalog critical data element (CDE) to one or
    more existing glossary terms - the "Manage related terms" portal action - from a declarative
    JSON definition file.

.DESCRIPTION
    Calls the Microsoft Purview Unified Catalog REST API (automation surface 4 per
    docs/automation-surface.md) to:
      1. Resolve the governance domain named in the definition file (must already exist).
      2. Resolve the critical data element named in the definition file (must already exist -
         this scenario reuses scenarios/unified-catalog/manage-critical-data-elements/'s output
         rather than creating a CDE of its own - see design.md Section 2).
      3. For each name in the definition file's 'relatedTerms' array: resolve the existing
         glossary term by name (must already exist - reuses
         scenarios/unified-catalog/curate-business-glossary/'s output), then create a
         Critical Data Elements - Create Relationship (entityType=TERM) if not already linked.

    Idempotent by construction: before creating each relationship, Test-CdeRelationshipExists
    lists the CDE's existing entityType=TERM relationships and skips the create call if the term
    is already present - the identical list-before-create guard
    scenarios/unified-catalog/manage-critical-data-elements/'s own
    Add-CdeColumnRelationship/scenarios/unified-catalog/manage-data-products/'s own
    Add-DataProductRelationship use for their own relationship types.

    This scenario never creates a critical data element, a governance domain, or a glossary term -
    it only links objects that already exist, all three resolved strictly by name (design.md
    Section 2's non-goal list).

    Author-only reference code. Never connects to a live tenant unless you supply real credentials
    and omit -WhatIf.

.PARAMETER PurviewAccountEndpoint
    Base URL of the Purview Unified Catalog data-plane API, e.g.
    'https://api.purview-service.microsoft.com'.

.PARAMETER TenantId
    Microsoft Entra tenant ID.

.PARAMETER AppId
    Application (client) ID of the service principal used to call the Unified Catalog REST API.
    Must hold at least Data Steward on the target governance domain (README.md Section 3) - unlike
    scenarios/unified-catalog/manage-critical-data-elements/'s own deploy script, this scenario
    never creates or edits a critical data element's own fields or resolves an owner identity via
    Graph, so no Data Product Owner role or Graph token is needed here.

.PARAMETER ClientSecret
    Client secret for -AppId, as a SecureString. Resolve from a vault at run time - never hard-code.

.PARAMETER DefinitionPath
    Path to the related-terms definition JSON file. See
    deploy/config/customer-id-related-terms.sample.json for the expected shape (domain block,
    criticalDataElement block, relatedTerms array of term names).

.PARAMETER ApiVersion
    Unified Catalog REST API version to pin. Defaults to '2026-03-20-preview' - the version this
    scenario's sibling, scenarios/unified-catalog/manage-critical-data-elements/, was grounded
    against, and the same version whose Critical Data Elements Create Relationship operation this
    script's fresh grounding pass re-confirmed supports entityType=TERM (README.md Section 12).

.PARAMETER WhatIf
    Standard PowerShell ShouldProcess dry-run. Reports every REST call that would be made without
    sending any mutating (POST) request. Invoke-RestMethod has no native ShouldProcess
    integration, so this script wraps the mutating call in its own $PSCmdlet.ShouldProcess() check.

.EXAMPLE
    ./Add-CdeRelatedTerm.ps1 -PurviewAccountEndpoint 'https://api.purview-service.microsoft.com' `
        -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
        -DefinitionPath './config/customer-id-related-terms.sample.json' -WhatIf

    Dry-run: shows exactly which REST calls would be made, changes nothing.

.EXAMPLE
    ./Add-CdeRelatedTerm.ps1 -PurviewAccountEndpoint 'https://api.purview-service.microsoft.com' `
        -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
        -DefinitionPath './config/customer-id-related-terms.sample.json'

    Links the critical data element to every resolvable term in 'relatedTerms' that isn't already
    linked.

.NOTES
    VERIFY before production use (see README.md Section 11 and design.md for full detail):
    - Whether Critical Data Elements - Create Relationship (entityType=TERM) succeeds against a
      *published* glossary term, or requires it to be unpublished (Draft) first. Microsoft's own
      "Create and manage glossary terms" page states the Draft-state requirement only for the
      reciprocal flow (linking a term to a CDE from the *term's own* Related tab's "Add critical
      data element" button) - the "Manage related terms" flow this script automates (the CDE's own
      "+ Add term" button) carries no such stated restriction on its own concept page. This script
      does not attempt to unpublish a term first; if a tenant rejects a published term, the
      underlying REST call's error surfaces directly (this script does not swallow it).
    - The Critical Data Elements Query nameKeyword filter's and the Terms Query nameKeyword
      filter's exact match semantics - the same open question every sibling Unified Catalog
      scenario in this repo already carries for its own Query calls; this script applies the
      identical client-side-exact-match mitigation for both lookups.

    Sources (Microsoft Learn, verify before production use):
    - Critical Data Elements operation group, Create Relationship / List Relationships (entityType
      EntityCategory enum confirmed to include TERM - fetched directly this build, not assumed):
      https://learn.microsoft.com/rest/api/purview/purview-unified-catalog/critical-data-elements/create-relationship?view=rest-purview-purview-unified-catalog-2026-03-20-preview
      https://learn.microsoft.com/rest/api/purview/purview-unified-catalog/critical-data-elements/list-relationships?view=rest-purview-purview-unified-catalog-2026-03-20-preview
    - Critical data elements (preview) - "Manage related terms" portal procedure, reproduced
      exactly in README.md Section 5:
      https://learn.microsoft.com/purview/unified-catalog-critical-data-elements#manage-related-terms
    - Create and manage glossary terms - the reciprocal "Link terms to data products, assets, and
      critical data elements" flow and its Draft-state requirement:
      https://learn.microsoft.com/purview/unified-catalog-glossary-terms-create-manage#link-terms-to-data-products,-assets,-and-critical-data-elements-preview
    - Terms operation group (Query):
      https://learn.microsoft.com/rest/api/purview/purview-unified-catalog/terms?view=rest-purview-purview-unified-catalog-2026-03-20-preview
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
    [ValidateNotNullOrEmpty()]
    [string]$ApiVersion = '2026-03-20-preview'
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

function Invoke-Ucm {
    # Invoke-RestMethod has no native ShouldProcess integration, so the one mutating call this
    # script makes (Create Relationship) is wrapped in its own $PSCmdlet.ShouldProcess() check.
    # -ReadOnly bypasses that gate for calls that are read-only despite using POST (Query/List
    # Relationships) - those must still execute under -WhatIf so the script can accurately report
    # already-linked vs. would-link.
    param(
        [Parameter(Mandatory)][ValidateSet('Get', 'Post')][string]$Method,
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

function Find-TermByName {
    # Duplicated from scenarios/unified-catalog/manage-data-products/deploy/New-DataProduct.ps1
    # by design - each deploy script in this repo is self-contained (AGENTS.md's per-scenario
    # deliverable model), not a shared module.
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

function Add-CdeTermRelationship {
    param(
        [Parameter(Mandatory)][string]$CdeId,
        [Parameter(Mandatory)][string]$CdeName,
        [Parameter(Mandatory)][string]$TermId,
        [Parameter(Mandatory)][string]$TermName,
        [Parameter(Mandatory)][string]$Token
    )
    $entityType = 'TERM'
    if (Test-CdeRelationshipExists -CdeId $CdeId -EntityType $entityType -EntityId $TermId -Token $Token) {
        Write-Host "'$CdeName' is already linked to term '$TermName'." -ForegroundColor Yellow
        return
    }
    $uri = "$endpoint/datagovernance/catalog/criticalDataElements/$CdeId/relationships?api-version=$ApiVersion&entityType=$entityType"
    $body = @{ entityId = $TermId; relationshipType = 'Related' }
    Invoke-Ucm -Method Post -Uri $uri -Body $body -Token $Token `
        -Description "Link '$CdeName' -> term '$TermName'" | Out-Null
    Write-Host "Linked '$CdeName' -> term '$TermName'." -ForegroundColor Green
}

# --- Load and validate the definition file ---
$definition = Get-Content -Path $DefinitionPath -Raw | ConvertFrom-Json
if (-not $definition.domain -or -not $definition.criticalDataElement -or -not $definition.relatedTerms) {
    throw "Definition file '$DefinitionPath' must contain 'domain', 'criticalDataElement', and 'relatedTerms' properties."
}
if (@($definition.relatedTerms).Count -eq 0) {
    throw "Definition file '$DefinitionPath' has an empty 'relatedTerms' array - nothing to link."
}

$plainSecret = ConvertTo-PlainText -Secure $ClientSecret
try { $ucToken = Get-PurviewAccessToken -TenantId $TenantId -AppId $AppId -PlainSecret $plainSecret }
finally { $plainSecret = $null }

# --- Step 1: resolve the (already-existing) governance domain ---
$domain = Find-BusinessDomainByName -Name $definition.domain.name -Token $ucToken
if (-not $domain) {
    throw "Governance domain '$($definition.domain.name)' was not found. This scenario reuses an existing domain (e.g. from scenarios/unified-catalog/curate-business-glossary/) rather than creating one - run that scenario, or create the domain manually, first."
}

# --- Step 2: resolve the (already-existing) critical data element ---
$cde = Find-CriticalDataElementByName -Name $definition.criticalDataElement.name -DomainId $domain.id -Token $ucToken
if (-not $cde) {
    throw "Critical data element '$($definition.criticalDataElement.name)' was not found in domain '$($definition.domain.name)'. This scenario reuses an existing critical data element (created by scenarios/unified-catalog/manage-critical-data-elements/) rather than creating one - run that scenario first."
}

# --- Step 3: resolve and link each related term ---
foreach ($termName in $definition.relatedTerms) {
    $term = Find-TermByName -Name $termName -DomainId $domain.id -Token $ucToken
    if (-not $term) {
        Write-Warning "Term '$termName' was not found in domain '$($definition.domain.name)'. Skipped - create it first (e.g. via scenarios/unified-catalog/curate-business-glossary/)."
        continue
    }
    Add-CdeTermRelationship -CdeId $cde.id -CdeName $definition.criticalDataElement.name `
        -TermId $term.id -TermName $termName -Token $ucToken
}

Write-Host "`nDone. Run validate/Test-CdeRelatedTerms.ps1 to verify the deployed configuration." -ForegroundColor Cyan
```

#### `config/customer-id-related-terms.sample.json`

```json
{
  "domain": {
    "name": "Customer Experience",
    "note": "Must match the governance domain used by scenarios/unified-catalog/curate-business-glossary/ and scenarios/unified-catalog/manage-critical-data-elements/ - this scenario resolves it by name and does not create a domain of its own."
  },
  "criticalDataElement": {
    "name": "Customer ID",
    "note": "Must already exist - created by scenarios/unified-catalog/manage-critical-data-elements/. This scenario resolves it by name and does not create a critical data element of its own (design.md Section 2)."
  },
  "relatedTerms": [
    "Customer ID",
    "Customer"
  ],
  "_termNote": "Each entry must be the exact (case-insensitive per Find-TermByName's client-side match) name of an existing, already-created glossary term in the same governance domain - created by scenarios/unified-catalog/curate-business-glossary/. 'Customer ID' (the business term defining what the identifier means) and 'Customer' (its parent term) are both defined in that scenario's customer-experience-glossary.json. A term name that doesn't resolve is skipped with a warning, not treated as fatal - see README.md Section 11."
}
```

#### `Remove-CdeRelatedTerm.ps1`

```powershell
#Requires -Version 7.0
<#
.SYNOPSIS
    Unlinks one or more glossary terms from a Microsoft Purview Unified Catalog critical data
    element (CDE) - the reverse of Add-CdeRelatedTerm.ps1.

.DESCRIPTION
    Two modes, both additive-safe (never deletes the term, the critical data element, or the
    governance domain - see rollback.md):
      1. Default (no -TermNames, no -RemoveAll): unlinks exactly the terms listed in the
         definition file's own 'relatedTerms' array - "undo what Add-CdeRelatedTerm.ps1 would have
         added" - resolving each by name fresh rather than trusting a cached ID.
      2. -TermNames <string[]>: unlinks only the named term(s), regardless of what the definition
         file's 'relatedTerms' array contains - useful for removing a single mistaken link without
         touching the rest.
      3. -RemoveAll: unlinks every entityType=TERM relationship the critical data element
         currently has, enumerated live from the API - not re-derived from the definition file, so
         this also cleans up a term linked outside this scenario's scripts (e.g. via the portal's
         own "+ Add term" button or the reciprocal "Add critical data element" button on a term's
         own Related tab). The same discipline
         scenarios/unified-catalog/manage-critical-data-elements/deploy/Remove-CriticalDataElement.ps1's
         own -RemoveLinks uses for its DATACOLUMN relationships.

    Run this before scenarios/unified-catalog/manage-critical-data-elements/deploy/
    Remove-CriticalDataElement.ps1 -Purge if the CDE has any related terms - Microsoft's own
    documented delete prerequisite for a critical data element is "unpublish it and delete all
    columns within it, and any links to glossary terms" (README.md Section 1), and the sibling
    scenario's own -Purge does not remove TERM relationships (it predates this scenario - see
    rollback.md).

    CAUTION - unlinking is not purely metadata cleanup: if a term carries its own access policy,
    README.md Section 2 documents that policy as inheriting onto every data product the CDE
    touches. Removing the link may loosen that aggregated requirement - see the Write-Warning this
    script prints before every unlink and rollback.md's own caution.

    Author-only reference code. Never connects to a live tenant unless you supply real credentials
    and omit -WhatIf.

.PARAMETER PurviewAccountEndpoint
    Base URL of the Purview Unified Catalog data-plane API.

.PARAMETER TenantId
    Microsoft Entra tenant ID.

.PARAMETER AppId
    Application (client) ID of the service principal. Must hold at least Data Steward on the
    domain.

.PARAMETER ClientSecret
    Client secret for -AppId, as a SecureString.

.PARAMETER DefinitionPath
    Path to the same related-terms definition JSON file passed to Add-CdeRelatedTerm.ps1.

.PARAMETER TermNames
    Optional. Unlink only these term name(s), instead of the definition file's own 'relatedTerms'
    array. Ignored if -RemoveAll is supplied.

.PARAMETER RemoveAll
    Unlinks every entityType=TERM relationship the critical data element currently has, enumerated
    live rather than from the definition file or -TermNames.

.PARAMETER ApiVersion
    Unified Catalog REST API version to pin. Defaults to '2026-03-20-preview'.

.PARAMETER WhatIf
    Standard PowerShell ShouldProcess dry-run.

.EXAMPLE
    ./Remove-CdeRelatedTerm.ps1 -PurviewAccountEndpoint 'https://api.purview-service.microsoft.com' `
        -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
        -DefinitionPath './config/customer-id-related-terms.sample.json'

    Unlinks the terms listed in the definition file's 'relatedTerms' array.

.EXAMPLE
    ./Remove-CdeRelatedTerm.ps1 -PurviewAccountEndpoint 'https://api.purview-service.microsoft.com' `
        -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
        -DefinitionPath './config/customer-id-related-terms.sample.json' -RemoveAll

    Unlinks every term currently linked to the critical data element, regardless of source -
    the prerequisite step before the sibling scenario's -Purge.

.NOTES
    entityType=TERM is used for the relationship delete calls, the same EntityCategory value
    Add-CdeRelatedTerm.ps1 uses to create them (design.md Section 3) - unlike
    scenarios/unified-catalog/manage-critical-data-elements/'s own entityType=DATACOLUMN choice,
    TERM has no documented enum-vs-worked-example discrepancy to flag (README.md Section 12).
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
    [string[]]$TermNames,

    [Parameter()]
    [switch]$RemoveAll,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$ApiVersion = '2026-03-20-preview'
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

function Invoke-Ucm {
    param(
        [Parameter(Mandatory)][ValidateSet('Get', 'Post', 'Delete')][string]$Method,
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

function Find-TermByName {
    param([Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)][string]$DomainId, [Parameter(Mandatory)][string]$Token)
    $uri = "$endpoint/datagovernance/catalog/terms/query?api-version=$ApiVersion"
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
    Write-Host "Critical data element '$($definition.criticalDataElement.name)' not found - nothing to unlink." -ForegroundColor Yellow
    exit 0
}

Write-Warning "Unlinking a term is not purely metadata cleanup: if the term carries its own access policy (e.g. a manager-approval requirement), README.md Section 2 documents that policy as inheriting/aggregating onto every data product the CDE's mapped columns touch. Removing the link may loosen that aggregated requirement on downstream data products - this script cannot verify Microsoft's platform re-evaluates that aggregation, or when (rollback.md)."

$entityType = 'TERM'
$relUri = "$endpoint/datagovernance/catalog/criticalDataElements/$($cde.id)/relationships?api-version=$ApiVersion&entityType=$entityType"
$relationships = Invoke-Ucm -Method Get -Uri $relUri -Token $ucToken

if ($RemoveAll) {
    $targets = @($relationships.value)
    if ($targets.Count -eq 0) {
        Write-Host "No term relationships found for '$($cde.name)' (entityType=$entityType)." -ForegroundColor Yellow
    }
    foreach ($rel in $targets) {
        $deleteUri = "$endpoint/datagovernance/catalog/criticalDataElements/$($cde.id)/relationships?api-version=$ApiVersion&entityType=$entityType&entityId=$($rel.entityId)"
        Invoke-Ucm -Method Delete -Uri $deleteUri -Token $ucToken -Description "Unlink term (term id: $($rel.entityId)) from '$($cde.name)'" | Out-Null
        Write-Host "Unlinked term (term id: $($rel.entityId)) from '$($cde.name)'." -ForegroundColor Green
    }
}
else {
    $namesToRemove = if ($TermNames -and $TermNames.Count -gt 0) { $TermNames } else { @($definition.relatedTerms) }
    foreach ($termName in $namesToRemove) {
        $term = Find-TermByName -Name $termName -DomainId $domain.id -Token $ucToken
        if (-not $term) {
            Write-Warning "Term '$termName' was not found in domain '$($domain.name)'. Nothing to unlink."
            continue
        }
        $isLinked = [bool]($relationships.value | Where-Object { $_.entityId -eq $term.id })
        if (-not $isLinked) {
            Write-Host "'$($cde.name)' is not linked to term '$termName' - nothing to unlink." -ForegroundColor Yellow
            continue
        }
        $deleteUri = "$endpoint/datagovernance/catalog/criticalDataElements/$($cde.id)/relationships?api-version=$ApiVersion&entityType=$entityType&entityId=$($term.id)"
        Invoke-Ucm -Method Delete -Uri $deleteUri -Token $ucToken -Description "Unlink term '$termName' from '$($cde.name)'" | Out-Null
        Write-Host "Unlinked term '$termName' from '$($cde.name)'." -ForegroundColor Green
    }
}

Write-Host "`nDone. Run validate/Test-CdeRelatedTerms.ps1 to confirm the resulting state." -ForegroundColor Cyan
```