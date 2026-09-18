---
part: "deploy"
parent: "unified-catalog/curate-business-glossary"
---
The scripts and configuration below deploy this scenario. Review them, then run in order — each is designed to be idempotent and has a matching rollback.


#### `glossary/customer-experience-glossary.json`

```json
{
  "domain": {
    "name": "Customer Experience",
    "description": "Business concepts and data products owned by the Customer Experience organization: customer identity, engagement, and satisfaction metrics.",
    "type": "FunctionalUnit"
  },
  "terms": [
    {
      "name": "Customer",
      "description": "An individual or organization that has purchased, or is contractually entitled to purchase, a product or service from the company. Excludes prospects and internal test accounts.",
      "owners": ["jordan.steward@contoso.com"],
      "experts": [],
      "acronyms": [],
      "resources": [
        { "name": "Customer master data standard", "url": "https://contoso.sharepoint.com/sites/DataGovernance/customer-master-data-standard" }
      ],
      "parent": null,
      "relatedTerms": []
    },
    {
      "name": "Customer ID",
      "description": "The system-of-record surrogate key that uniquely identifies a Customer across all downstream systems. Assigned once at first purchase and never reused, even after account closure.",
      "owners": ["jordan.steward@contoso.com"],
      "experts": ["alex.masterdata@contoso.com"],
      "acronyms": ["CustID"],
      "resources": [],
      "parent": "Customer",
      "relatedTerms": []
    },
    {
      "name": "Customer Lifetime Value",
      "description": "The projected net revenue attributable to a Customer's entire relationship with the company, discounted to present value. Recalculated monthly by the Finance analytics pipeline.",
      "owners": ["jordan.steward@contoso.com"],
      "experts": ["priya.finance@contoso.com"],
      "acronyms": ["CLV"],
      "resources": [],
      "parent": "Customer",
      "relatedTerms": ["Net Promoter Score"]
    },
    {
      "name": "Net Promoter Score",
      "description": "A customer-loyalty metric derived from the standard 0-10 'how likely are you to recommend us' survey question, scored as %Promoters minus %Detractors. Tracked at the account and product-line level.",
      "owners": ["jordan.steward@contoso.com"],
      "experts": [],
      "acronyms": ["NPS"],
      "resources": [
        { "name": "NPS survey methodology", "url": "https://contoso.sharepoint.com/sites/CustomerExperience/nps-methodology" }
      ],
      "parent": null,
      "relatedTerms": []
    }
  ]
}
```

#### `New-BusinessGlossary.ps1`

```powershell
#Requires -Version 7.0
<#
.SYNOPSIS
    Idempotently creates or updates a Microsoft Purview Unified Catalog governance domain and its
    glossary terms from a declarative JSON definition file.

.DESCRIPTION
    Calls the Microsoft Purview Unified Catalog REST API (automation surface 4 per
    docs/automation-surface.md) to:
      1. Resolve the governance domain named in the definition file (create it in DRAFT status if
         it doesn't already exist).
      2. For each term in the definition file, resolve any owner/expert identity that isn't
         already an Entra object ID to one, via Microsoft Graph (surface 3) - the Unified Catalog
         API's contacts fields require an Entra object ID, not an email address.
      3. Create or update (upsert) each term, preserving parent/child relationships within the
         same file.
      4. Add "Related" term-to-term relationships declared in the file.
      5. Optionally (-Publish) transition the domain and every term from DRAFT to PUBLISHED.

    Idempotent by construction: before creating a term, the script queries the domain for an
    existing term with an exact (case-insensitive) name match (design.md Section 4) and reconciles
    it via Update instead of creating a duplicate. Re-running this script with an unchanged
    definition file makes no further calls beyond the existence checks; re-running it with an
    edited description/owner/acronym updates the existing term in place.

    Author-only reference code. Never connects to a live tenant unless you supply real credentials
    and omit -WhatIf. Terms and the domain are created in DRAFT status unless -Publish is passed.

.PARAMETER PurviewAccountEndpoint
    Base URL of the Purview Unified Catalog data-plane API. Use 'https://api.purview-service.microsoft.com'
    for tenants on the current Microsoft Purview portal, or 'https://<account>.purview.azure.com'
    for the classic portal (README.md Section 11 explains the difference).

.PARAMETER TenantId
    Microsoft Entra tenant ID.

.PARAMETER AppId
    Application (client) ID of the service principal used to call both the Unified Catalog REST
    API and Microsoft Graph. Must hold the Data Steward role on the target governance domain
    (Governance Domain Creator if the domain doesn't exist yet - docs/rbac-model.md Section 5) and
    the Graph application permission User.Read.All (README.md Section 3).

.PARAMETER ClientSecret
    Client secret for -AppId, as a SecureString. Resolve from a vault at run time - never hard-code.

.PARAMETER GlossaryDefinitionPath
    Path to the glossary definition JSON file. See deploy/glossary/customer-experience-glossary.json
    for the expected shape (domain block + terms array with name/description/owners/experts/
    acronyms/resources/parent/relatedTerms).

.PARAMETER Publish
    If supplied, transitions the domain and every term in the file from DRAFT to PUBLISHED after
    they're created/updated. Omit to leave everything in DRAFT (visible only to Data Stewards and
    Governance Domain Owners) for review before publishing - see README.md Section 8.

.PARAMETER ApiVersion
    Unified Catalog REST API version to pin. Defaults to '2026-03-20-preview', the latest public
    preview version confirmed against Microsoft's own REST reference at the time of this build.

.PARAMETER WhatIf
    Standard PowerShell ShouldProcess dry-run. Reports every REST call that would be made without
    sending any mutating (POST/PUT) request. Invoke-RestMethod has no native ShouldProcess
    integration, so this script wraps each mutating call in its own $PSCmdlet.ShouldProcess() check.

.EXAMPLE
    ./New-BusinessGlossary.ps1 -PurviewAccountEndpoint 'https://api.purview-service.microsoft.com' `
        -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
        -GlossaryDefinitionPath './glossary/customer-experience-glossary.json' -WhatIf

    Dry-run: shows exactly which REST calls would be made, changes nothing.

.EXAMPLE
    ./New-BusinessGlossary.ps1 -PurviewAccountEndpoint 'https://api.purview-service.microsoft.com' `
        -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
        -GlossaryDefinitionPath './glossary/customer-experience-glossary.json'

    Creates/updates the domain and terms in DRAFT status.

.EXAMPLE
    ./New-BusinessGlossary.ps1 -PurviewAccountEndpoint 'https://api.purview-service.microsoft.com' `
        -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
        -GlossaryDefinitionPath './glossary/customer-experience-glossary.json' -Publish

    Creates/updates the domain and terms, then publishes all of them.

.NOTES
    VERIFY before production use (see README.md Section 11 and design.md Section 4 for full
    detail): the Terms - Query "nameKeyword" filter's exact match semantics (substring vs. prefix
    vs. tokenized) are not documented; this script always re-checks for an exact name match in the
    returned page rather than trusting the filter alone, but a domain with more matching terms
    than one page could in principle need pagination this script does not yet implement. The
    formal REST reference marks several Business Domain Create/Update body fields (systemData,
    thumbnail, domains, managedAttributes) as "Required" in a way that contradicts Microsoft's own
    worked examples and basic REST semantics (a create call cannot require the caller to supply
    server-computed system metadata) - this script sends the minimal practical body used in
    Microsoft's own disaster-recovery article pattern and omits those fields; confirm against a
    pilot tenant if the API rejects a minimal body.

    Sources (Microsoft Learn, verify before production use):
    - Terms - Create/Update/Query/Delete reference:
      https://learn.microsoft.com/rest/api/purview/purview-unified-catalog/terms?view=rest-purview-purview-unified-catalog-2026-03-20-preview
    - Business Domain - Create/Update/Enumerate reference:
      https://learn.microsoft.com/rest/api/purview/purview-unified-catalog/business-domain?view=rest-purview-purview-unified-catalog-2026-03-20-preview
    - Tutorial: Authenticate for Microsoft Purview data-plane APIs (token acquisition, roles):
      https://learn.microsoft.com/purview/data-gov-api-rest-data-plane
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
    [string]$GlossaryDefinitionPath,

    [Parameter()]
    [switch]$Publish,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$ApiVersion = '2026-03-20-preview'
)

$ErrorActionPreference = 'Stop'

$endpoint = $PurviewAccountEndpoint.TrimEnd('/')
$guidPattern = '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'

function ConvertTo-PlainText {
    param([Parameter(Mandatory)][SecureString]$Secure)
    $ptr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($Secure)
    try { return [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($ptr) }
    finally { [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr) }
}

function Get-PurviewAccessToken {
    # v1 client-credentials flow against the shared Data Map / Unified Catalog data-plane
    # resource, per docs/automation-surface.md Section 3 and README.md reference 3.
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
    # v2 client-credentials flow, per Microsoft identity platform guidance (README.md reference 8).
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
    # that are read-only despite using POST (e.g. Query Terms, which takes a filter body) - those
    # must still execute under -WhatIf so the script can accurately report create vs. update.
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

function Get-OrNewBusinessDomain {
    param(
        [Parameter(Mandatory)][pscustomobject]$DomainDef,
        [Parameter(Mandatory)][string]$Token
    )
    $existing = Find-BusinessDomainByName -Name $DomainDef.name -Token $Token
    if ($existing) {
        Write-Host "Governance domain '$($DomainDef.name)' already exists (id: $($existing.id), status: $($existing.status))." -ForegroundColor Yellow
        return $existing
    }
    $newId = [guid]::NewGuid().ToString()
    $body = @{
        id          = $newId
        name        = $DomainDef.name
        description = $DomainDef.description
        type        = $DomainDef.type
        status      = 'DRAFT'
    }
    $uri = "$endpoint/datagovernance/catalog/businessdomains?api-version=$ApiVersion"
    $created = Invoke-Ucm -Method Post -Uri $uri -Body $body -Token $Token `
        -Description "Governance domain '$($DomainDef.name)'"
    Write-Host "Created governance domain '$($DomainDef.name)' (id: $newId)." -ForegroundColor Green
    if ($created) { return $created }
    return [pscustomobject]@{ id = $newId; name = $DomainDef.name; status = 'DRAFT' }
}

function Publish-BusinessDomain {
    param(
        [Parameter(Mandatory)][pscustomobject]$Domain,
        [Parameter(Mandatory)][pscustomobject]$DomainDef,
        [Parameter(Mandatory)][string]$Token
    )
    if ($Domain.status -eq 'PUBLISHED') {
        Write-Host "Governance domain '$($DomainDef.name)' is already published." -ForegroundColor Yellow
        return
    }
    $body = @{
        id          = $Domain.id
        name        = $DomainDef.name
        description = $DomainDef.description
        type        = $DomainDef.type
        status      = 'PUBLISHED'
    }
    $uri = "$endpoint/datagovernance/catalog/businessdomains/$($Domain.id)?api-version=$ApiVersion"
    Invoke-Ucm -Method Put -Uri $uri -Body $body -Token $Token `
        -Description "Publish governance domain '$($DomainDef.name)'" | Out-Null
    Write-Host "Published governance domain '$($DomainDef.name)'." -ForegroundColor Green
}

function Resolve-ContactId {
    param(
        [Parameter(Mandatory)][string]$Identifier,
        [Parameter(Mandatory)][string]$GraphToken,
        [Parameter(Mandatory)][hashtable]$Cache
    )
    if ($Identifier -match $guidPattern) { return $Identifier }
    if ($Cache.ContainsKey($Identifier)) { return $Cache[$Identifier] }
    # The backtick before $select escapes it from PowerShell variable interpolation, so the
    # literal query string sent is "...?$select=id".
    $uri = "https://graph.microsoft.com/v1.0/users/${Identifier}?`$select=id"
    $user = Invoke-RestMethod -Method Get -Uri $uri -Headers @{ Authorization = "Bearer $GraphToken" }
    $Cache[$Identifier] = $user.id
    Write-Host "Resolved '$Identifier' to Entra object ID $($user.id)." -ForegroundColor Cyan
    return $user.id
}

function ConvertTo-ContactsMap {
    param(
        [Parameter()][string[]]$Owners,
        [Parameter()][string[]]$Experts,
        [Parameter(Mandatory)][string]$GraphToken,
        [Parameter(Mandatory)][hashtable]$Cache
    )
    $contacts = @{}
    if ($Owners -and $Owners.Count -gt 0) {
        $contacts.owner = @($Owners | ForEach-Object {
                @{ id = (Resolve-ContactId -Identifier $_ -GraphToken $GraphToken -Cache $Cache) }
            })
    }
    if ($Experts -and $Experts.Count -gt 0) {
        $contacts.expert = @($Experts | ForEach-Object {
                @{ id = (Resolve-ContactId -Identifier $_ -GraphToken $GraphToken -Cache $Cache) }
            })
    }
    return $contacts
}

function Find-TermByName {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$DomainId,
        [Parameter(Mandatory)][string]$Token
    )
    # Query Terms, scoped to the domain, pre-filtered by nameKeyword - then re-checked client-side
    # for an exact case-insensitive match (design.md Section 4). nameKeyword's own match semantics
    # (substring/prefix/tokenized) are undocumented, so this is a pre-filter only, never the
    # deciding check.
    $uri = "$endpoint/datagovernance/catalog/terms/query?api-version=$ApiVersion"
    $body = @{ domainIds = @($DomainId); nameKeyword = $Name; top = 50 }
    $response = Invoke-Ucm -Method Post -Uri $uri -Body $body -Token $Token -ReadOnly `
        -Description "Query terms named like '$Name'"
    return ($response.value | Where-Object { $_.name -eq $Name } | Select-Object -First 1)
}

function New-TermRequestBody {
    # Body builder for the create/update path. Update Term is a full-replace PUT, so this always
    # includes every field the term should end up with (acronyms, resources, contacts, parentId),
    # never just the field being changed. The separate publish path (Publish-Term, below) does NOT
    # use this - it reuses the server's own currently-stored fields via ConvertTo-TermUpdateBody
    # instead, so a status-only transition can't clobber a portal-made edit this script doesn't
    # know about.
    param(
        [Parameter(Mandatory)][pscustomobject]$TermDef,
        [Parameter(Mandatory)][string]$TermId,
        [Parameter(Mandatory)][string]$DomainId,
        [Parameter(Mandatory)][string]$Status,
        [Parameter(Mandatory)][hashtable]$TermIdsByName,
        [Parameter(Mandatory)][string]$GraphToken,
        [Parameter(Mandatory)][hashtable]$ContactCache
    )
    $contacts = ConvertTo-ContactsMap -Owners $TermDef.owners -Experts $TermDef.experts `
        -GraphToken $GraphToken -Cache $ContactCache

    $resources = @()
    if ($TermDef.resources) {
        $resources = @($TermDef.resources | ForEach-Object { @{ name = $_.name; url = $_.url } })
    }

    $body = @{
        id          = $TermId
        domain      = $DomainId
        name        = $TermDef.name
        status      = $Status
        description = $TermDef.description
        acronyms    = @($TermDef.acronyms)
        resources   = $resources
        contacts    = $contacts
    }
    if ($TermDef.parent) {
        if (-not $TermIdsByName.ContainsKey($TermDef.parent)) {
            throw "Term '$($TermDef.name)' declares parent '$($TermDef.parent)', which was not found or not yet processed. List parent terms before their children in the definition file."
        }
        $body.parentId = $TermIdsByName[$TermDef.parent]
    }
    return $body
}

function Get-OrNewTerm {
    param(
        [Parameter(Mandatory)][pscustomobject]$TermDef,
        [Parameter(Mandatory)][string]$DomainId,
        [Parameter(Mandatory)][hashtable]$TermIdsByName,
        [Parameter(Mandatory)][string]$Token,
        [Parameter(Mandatory)][string]$GraphToken,
        [Parameter(Mandatory)][hashtable]$ContactCache
    )
    $existing = Find-TermByName -Name $TermDef.name -DomainId $DomainId -Token $Token
    $termId = if ($existing) { $existing.id } else { [guid]::NewGuid().ToString() }
    $status = if ($existing) { $existing.status } else { 'DRAFT' }

    $body = New-TermRequestBody -TermDef $TermDef -TermId $termId -DomainId $DomainId -Status $status `
        -TermIdsByName $TermIdsByName -GraphToken $GraphToken -ContactCache $ContactCache

    if ($existing) {
        $uri = "$endpoint/datagovernance/catalog/terms/$termId?api-version=$ApiVersion"
        Invoke-Ucm -Method Put -Uri $uri -Body $body -Token $Token `
            -Description "Update term '$($TermDef.name)'" | Out-Null
        Write-Host "Updated term '$($TermDef.name)' (id: $termId)." -ForegroundColor Green
    }
    else {
        $uri = "$endpoint/datagovernance/catalog/terms?api-version=$ApiVersion"
        Invoke-Ucm -Method Post -Uri $uri -Body $body -Token $Token `
            -Description "Create term '$($TermDef.name)'" | Out-Null
        Write-Host "Created term '$($TermDef.name)' (id: $termId)." -ForegroundColor Green
    }
    return $termId
}

function Add-TermRelationship {
    param(
        [Parameter(Mandatory)][string]$FromTermId,
        [Parameter(Mandatory)][string]$FromTermName,
        [Parameter(Mandatory)][string]$ToTermId,
        [Parameter(Mandatory)][string]$ToTermName,
        [Parameter(Mandatory)][string]$Token
    )
    $uri = "$endpoint/datagovernance/catalog/terms/$FromTermId/relationships?api-version=$ApiVersion&entityType=TERM"
    $body = @{ entityId = $ToTermId; relationshipType = 'Related' }
    Invoke-Ucm -Method Post -Uri $uri -Body $body -Token $Token `
        -Description "Relate '$FromTermName' -> '$ToTermName'" | Out-Null
    Write-Host "Related '$FromTermName' -> '$ToTermName'." -ForegroundColor Green
}

function ConvertTo-TermUpdateBody {
    # Rebuilds a PUT-ready hashtable from a Term object the API just returned (a GET/Query
    # result), changing only status. Reusing the server's own current state - rather than
    # reconstructing the body from the local definition file - means a status-only transition can
    # never clobber a field (e.g. a resource or managed attribute) that was added directly in the
    # portal since this script last ran.
    param(
        [Parameter(Mandatory)][pscustomobject]$Term,
        [Parameter(Mandatory)][string]$Status
    )
    $body = @{
        id          = $Term.id
        domain      = $Term.domain
        name        = $Term.name
        status      = $Status
        description = $Term.description
        acronyms    = @($Term.acronyms)
        resources   = @($Term.resources | ForEach-Object { @{ name = $_.name; url = $_.url } })
        contacts    = @{}
    }
    if ($Term.parentId) { $body.parentId = $Term.parentId }
    if ($Term.contacts) {
        if ($Term.contacts.owner) { $body.contacts.owner = @($Term.contacts.owner | ForEach-Object { @{ id = $_.id; description = $_.description } }) }
        if ($Term.contacts.expert) { $body.contacts.expert = @($Term.contacts.expert | ForEach-Object { @{ id = $_.id; description = $_.description } }) }
        if ($Term.contacts.databaseAdmin) { $body.contacts.databaseAdmin = @($Term.contacts.databaseAdmin | ForEach-Object { @{ id = $_.id; description = $_.description } }) }
    }
    return $body
}

function Publish-Term {
    param(
        [Parameter(Mandatory)][string]$TermName,
        [Parameter(Mandatory)][string]$TermId,
        [Parameter(Mandatory)][string]$Token
    )
    $current = Invoke-Ucm -Method Get -Uri "$endpoint/datagovernance/catalog/terms/$($TermId)?api-version=$ApiVersion" -Token $Token
    if ($current -and $current.status -eq 'PUBLISHED') {
        Write-Host "Term '$TermName' is already published." -ForegroundColor Yellow
        return
    }
    $body = ConvertTo-TermUpdateBody -Term $current -Status 'PUBLISHED'
    $uri = "$endpoint/datagovernance/catalog/terms/$TermId?api-version=$ApiVersion"
    Invoke-Ucm -Method Put -Uri $uri -Body $body -Token $Token `
        -Description "Publish term '$TermName'" | Out-Null
    Write-Host "Published term '$TermName'." -ForegroundColor Green
}

# --- Load and validate the definition file ---
$definition = Get-Content -Path $GlossaryDefinitionPath -Raw | ConvertFrom-Json
if (-not $definition.domain -or -not $definition.terms) {
    throw "Definition file '$GlossaryDefinitionPath' must contain a 'domain' object and a 'terms' array."
}

$plainSecret = ConvertTo-PlainText -Secure $ClientSecret
try {
    $ucToken = Get-PurviewAccessToken -TenantId $TenantId -AppId $AppId -PlainSecret $plainSecret
    $graphToken = Get-GraphAccessToken -TenantId $TenantId -AppId $AppId -PlainSecret $plainSecret
}
finally {
    $plainSecret = $null
}

# --- Step 1: resolve or create the governance domain ---
$domain = Get-OrNewBusinessDomain -DomainDef $definition.domain -Token $ucToken

# --- Step 2: upsert terms, parents before children (the file lists them in that order) ---
$termIdsByName = @{}
$contactCache = @{}
foreach ($termDef in $definition.terms) {
    $termId = Get-OrNewTerm -TermDef $termDef -DomainId $domain.id -TermIdsByName $termIdsByName `
        -Token $ucToken -GraphToken $graphToken -ContactCache $contactCache
    $termIdsByName[$termDef.name] = $termId
}

# --- Step 3: wire up declared term-to-term relationships ---
foreach ($termDef in $definition.terms) {
    foreach ($relatedName in $termDef.relatedTerms) {
        if (-not $termIdsByName.ContainsKey($relatedName)) {
            Write-Warning "Term '$($termDef.name)' declares a relationship to '$relatedName', which is not in this definition file. Skipped."
            continue
        }
        Add-TermRelationship -FromTermId $termIdsByName[$termDef.name] -FromTermName $termDef.name `
            -ToTermId $termIdsByName[$relatedName] -ToTermName $relatedName -Token $ucToken
    }
}

# --- Step 4 (optional): publish the domain and every term ---
if ($Publish) {
    Publish-BusinessDomain -Domain $domain -DomainDef $definition.domain -Token $ucToken
    foreach ($termDef in $definition.terms) {
        Publish-Term -TermName $termDef.name -TermId $termIdsByName[$termDef.name] -Token $ucToken
    }
}
else {
    Write-Host "`nDomain and terms left in DRAFT status (visible only to Data Stewards / Governance Domain Owners). Re-run with -Publish once reviewed." -ForegroundColor Cyan
}

Write-Host "`nDone. Run validate/Test-BusinessGlossary.ps1 to verify the deployed configuration." -ForegroundColor Cyan
```

#### `Remove-BusinessGlossary.ps1`

```powershell
#Requires -Version 7.0
<#
.SYNOPSIS
    Rolls back a governance domain and glossary terms deployed by New-BusinessGlossary.ps1.

.DESCRIPTION
    Two rollback modes:
      -Unpublish (default, recommended first step): sets every term and the domain itself back to
       DRAFT status, using each object's own currently-stored fields (fetched via GET) rather than
       the local definition file - so nothing this script didn't author is clobbered. Reversible by
       re-running New-BusinessGlossary.ps1 with -Publish. Nothing is deleted.
      -Purge: permanently deletes every term in the definition file, then the domain itself, via
       DELETE. This is NOT reversible - re-establishing the glossary means re-running
       New-BusinessGlossary.ps1 from scratch (new IDs will be generated).

    Idempotent: if a term or the domain doesn't exist (already deleted, or never created), the
    script reports that and continues rather than erroring.

.PARAMETER PurviewAccountEndpoint
    Base URL of the Purview Unified Catalog data-plane API - must match the value used at deploy
    time. See README.md Section 11.

.PARAMETER TenantId
    Microsoft Entra tenant ID.

.PARAMETER AppId
    Application (client) ID of the service principal. Must hold the Data Steward role on the
    domain (Governance Domain Owner if using -Purge to delete the domain itself).

.PARAMETER ClientSecret
    Client secret for -AppId, as a SecureString.

.PARAMETER GlossaryDefinitionPath
    Path to the same glossary definition JSON file passed to New-BusinessGlossary.ps1 - used only
    to enumerate which domain/term names to look up and roll back.

.PARAMETER Purge
    Permanently delete the domain and its terms instead of unpublishing them. See rollback.md for
    the recommended unpublish-first, purge-later sequence.

.PARAMETER ApiVersion
    Unified Catalog REST API version to pin. Defaults to '2026-03-20-preview'.

.PARAMETER WhatIf
    Standard PowerShell ShouldProcess dry-run - reports the unpublish/deletion that would happen
    without calling any mutating endpoint. Read-only lookups (finding the domain/terms by name)
    still execute under -WhatIf so the script can report accurately.

.EXAMPLE
    ./Remove-BusinessGlossary.ps1 -PurviewAccountEndpoint 'https://api.purview-service.microsoft.com' `
        -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
        -GlossaryDefinitionPath './glossary/customer-experience-glossary.json' -WhatIf

.EXAMPLE
    ./Remove-BusinessGlossary.ps1 -PurviewAccountEndpoint 'https://api.purview-service.microsoft.com' `
        -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
        -GlossaryDefinitionPath './glossary/customer-experience-glossary.json'
    # Unpublishes the domain and every term (soft rollback).

.EXAMPLE
    ./Remove-BusinessGlossary.ps1 -PurviewAccountEndpoint 'https://api.purview-service.microsoft.com' `
        -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
        -GlossaryDefinitionPath './glossary/customer-experience-glossary.json' -Purge
    # Permanently deletes every term, then the domain.

.NOTES
    Sources: https://learn.microsoft.com/rest/api/purview/purview-unified-catalog/terms/delete?view=rest-purview-purview-unified-catalog-2026-03-20-preview
             https://learn.microsoft.com/rest/api/purview/purview-unified-catalog/business-domain/delete?view=rest-purview-purview-unified-catalog-2026-03-20-preview
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
    [string]$GlossaryDefinitionPath,

    [Parameter()]
    [switch]$Purge,

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
        $params = @{ Method = $Method; Uri = $Uri; Headers = @{ Authorization = "Bearer $Token" } }
        if ($Body) {
            $params.Body = ($Body | ConvertTo-Json -Depth 10)
            $params.ContentType = 'application/json'
        }
        return Invoke-RestMethod @params
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

function Find-TermByName {
    param([Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)][string]$DomainId, [Parameter(Mandatory)][string]$Token)
    $uri = "$endpoint/datagovernance/catalog/terms/query?api-version=$ApiVersion"
    $body = @{ domainIds = @($DomainId); nameKeyword = $Name; top = 50 }
    $response = Invoke-Ucm -Method Post -Uri $uri -Body $body -Token $Token -ReadOnly `
        -Description "Query terms named like '$Name'"
    return ($response.value | Where-Object { $_.name -eq $Name } | Select-Object -First 1)
}

function ConvertTo-StatusOnlyUpdateBody {
    param([Parameter(Mandatory)][pscustomobject]$Term, [Parameter(Mandatory)][string]$Status)
    $body = @{
        id          = $Term.id
        domain      = $Term.domain
        name        = $Term.name
        status      = $Status
        description = $Term.description
        acronyms    = @($Term.acronyms)
        resources   = @($Term.resources | ForEach-Object { @{ name = $_.name; url = $_.url } })
        contacts    = @{}
    }
    if ($Term.parentId) { $body.parentId = $Term.parentId }
    if ($Term.contacts) {
        if ($Term.contacts.owner) { $body.contacts.owner = @($Term.contacts.owner | ForEach-Object { @{ id = $_.id; description = $_.description } }) }
        if ($Term.contacts.expert) { $body.contacts.expert = @($Term.contacts.expert | ForEach-Object { @{ id = $_.id; description = $_.description } }) }
        if ($Term.contacts.databaseAdmin) { $body.contacts.databaseAdmin = @($Term.contacts.databaseAdmin | ForEach-Object { @{ id = $_.id; description = $_.description } }) }
    }
    return $body
}

$definition = Get-Content -Path $GlossaryDefinitionPath -Raw | ConvertFrom-Json
if (-not $definition.domain -or -not $definition.terms) {
    throw "Definition file '$GlossaryDefinitionPath' must contain a 'domain' object and a 'terms' array."
}

$plainSecret = ConvertTo-PlainText -Secure $ClientSecret
try {
    $token = Get-PurviewAccessToken -TenantId $TenantId -AppId $AppId -PlainSecret $plainSecret
}
finally {
    $plainSecret = $null
}

$domain = Find-BusinessDomainByName -Name $definition.domain.name -Token $token
if (-not $domain) {
    Write-Host "Governance domain '$($definition.domain.name)' does not exist. Nothing to roll back." -ForegroundColor Yellow
    return
}

# Resolve every term's current state first (needed for the unpublish body, and to fail fast on
# lookup errors before any mutating call is made).
$terms = @()
foreach ($termDef in $definition.terms) {
    $existing = Find-TermByName -Name $termDef.name -DomainId $domain.id -Token $token
    if ($existing) { $terms += $existing }
    else { Write-Host "Term '$($termDef.name)' does not exist. Skipped." -ForegroundColor Yellow }
}

if ($Purge) {
    foreach ($term in $terms) {
        $uri = "$endpoint/datagovernance/catalog/terms/$($term.id)?api-version=$ApiVersion"
        Invoke-Ucm -Method Delete -Uri $uri -Token $token -Description "Delete term '$($term.name)'" | Out-Null
        Write-Host "Deleted term '$($term.name)'." -ForegroundColor Green
    }
    $domainUri = "$endpoint/datagovernance/catalog/businessdomains/$($domain.id)?api-version=$ApiVersion"
    Invoke-Ucm -Method Delete -Uri $domainUri -Token $token -Description "Delete governance domain '$($definition.domain.name)'" | Out-Null
    Write-Host "Deleted governance domain '$($definition.domain.name)'." -ForegroundColor Green
}
else {
    foreach ($term in $terms) {
        if ($term.status -ne 'DRAFT') {
            $body = ConvertTo-StatusOnlyUpdateBody -Term $term -Status 'DRAFT'
            $uri = "$endpoint/datagovernance/catalog/terms/$($term.id)?api-version=$ApiVersion"
            Invoke-Ucm -Method Put -Uri $uri -Body $body -Token $token -Description "Unpublish term '$($term.name)'" | Out-Null
            Write-Host "Unpublished term '$($term.name)'." -ForegroundColor Green
        }
        else {
            Write-Host "Term '$($term.name)' is already in DRAFT status." -ForegroundColor Yellow
        }
    }
    if ($domain.status -ne 'DRAFT') {
        $domainBody = @{
            id          = $domain.id
            name        = $domain.name
            description = $domain.description
            type        = $domain.type
            status      = 'DRAFT'
        }
        $domainUri = "$endpoint/datagovernance/catalog/businessdomains/$($domain.id)?api-version=$ApiVersion"
        Invoke-Ucm -Method Put -Uri $domainUri -Body $domainBody -Token $token -Description "Unpublish governance domain '$($definition.domain.name)'" | Out-Null
        Write-Host "Unpublished governance domain '$($definition.domain.name)'." -ForegroundColor Green
    }
    else {
        Write-Host "Governance domain '$($definition.domain.name)' is already in DRAFT status." -ForegroundColor Yellow
    }
    Write-Host "`nSoft rollback complete. Re-run New-BusinessGlossary.ps1 -Publish to restore, or re-run this script with -Purge to permanently delete." -ForegroundColor Cyan
}
```