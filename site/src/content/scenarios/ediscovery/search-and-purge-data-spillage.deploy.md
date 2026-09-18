---
part: "deploy"
parent: "ediscovery/search-and-purge-data-spillage"
---
The scripts and configuration below deploy this scenario. Review them, then run in order — each is designed to be idempotent and has a matching rollback.


#### `Invoke-DataSpillagePurge.ps1`

```powershell
#Requires -Modules @{ ModuleName = 'Microsoft.Graph.Security'; ModuleVersion = '2.25.0' }
#Requires -Modules @{ ModuleName = 'Microsoft.Graph.Authentication'; ModuleVersion = '2.25.0' }

<#
.SYNOPSIS
    Purges (soft-deletes by default; hard-deletes only with explicit double confirmation) the
    Exchange mailbox items matched by an existing eDiscovery search created by
    New-DataSpillageSearch.ps1.

.DESCRIPTION
    The destructive second stage of the eDiscovery search-and-purge data-spillage scenario. Calls
    Microsoft Graph's ediscoverySearch: purgeData action (Clear-MgSecurityCaseEdiscoveryCaseSearchData)
    -- see design.md Section 2 for why this is built on Graph rather than the S&C PowerShell
    New-ComplianceSearchAction -Purge path Microsoft's own current docs still show for interactive
    use (app-only auth for eDiscovery S&C PowerShell cmdlets is unsupported by Microsoft;
    docs/automation-surface.md Section 3).

    Deliberately NOT idempotent-by-skip: unlike this repo's addToReviewSet/export helpers (which
    skip a repeat call once one has already succeeded), re-running a purge against the same search
    is the Microsoft-documented way to clear more than the 100-items-per-mailbox-per-run ceiling, or
    to catch newly matched content -- see README.md Section 6/11. This script therefore lists prior
    purge operations against the search for audit-trail awareness (-ListOnly) but never auto-skips a
    requested purge.

    Purge does NOT override a litigation hold or retention policy -- see the VERIFY in this script's
    own .NOTES and README.md Section 11. For held mailboxes, chain to the already-built
    scenarios/data-lifecycle-management/priority-cleanup-exchange-data-spillage/ sibling instead
    (README.md Section 5 step 4).

.PARAMETER CaseId
    The eDiscoveryCase id (from New-DataSpillageSearch.ps1's output or Get-MgSecurityCaseEdiscoveryCase).

.PARAMETER SearchId
    The ediscoverySearch id within that case (from New-DataSpillageSearch.ps1's output).

.PARAMETER PurgeType
    'Recoverable' (default) -- Graph's soft-delete-equivalent; the user can still recover the item
    until the mailbox's deleted-item retention period expires. 'PermanentlyDelete' -- irreversible;
    requires -ConfirmPermanentDelete as well.

.PARAMETER ConfirmPermanentDelete
    Required in addition to -PurgeType PermanentlyDelete. A second, independent, deliberately-named
    switch so a irreversible hard-delete can never be triggered by a single mistyped/defaulted
    parameter.

.PARAMETER ListOnly
    Only lists prior purgeData operations against this search (status, purgeType/purgeAreas,
    completion time) without starting a new one. Use this to review the audit trail before deciding
    whether another purge run is needed.

.PARAMETER AppId
    Application (client) ID of the Entra app registration used for Graph app-only auth.

.PARAMETER TenantId
    Directory (tenant) ID.

.PARAMETER CertificateThumbprint
    Thumbprint of the client certificate installed in the current user's certificate store.
    Mutually exclusive with -Certificate.

.PARAMETER Certificate
    An in-memory X509Certificate2 object. Mutually exclusive with -CertificateThumbprint.

.EXAMPLE
    ./Invoke-DataSpillagePurge.ps1 -CaseId $caseId -SearchId $searchId -ListOnly `
        -AppId $AppId -TenantId $TenantId -CertificateThumbprint $Thumbprint

    Reports every prior purgeData operation against this search without starting a new one.

.EXAMPLE
    ./Invoke-DataSpillagePurge.ps1 -CaseId $caseId -SearchId $searchId -PurgeType Recoverable `
        -AppId $AppId -TenantId $TenantId -CertificateThumbprint $Thumbprint -WhatIf

    Reports the purge this run would start, without calling purgeData.

.EXAMPLE
    ./Invoke-DataSpillagePurge.ps1 -CaseId $caseId -SearchId $searchId -PurgeType PermanentlyDelete `
        -ConfirmPermanentDelete -AppId $AppId -TenantId $TenantId -CertificateThumbprint $Thumbprint

    Irreversibly hard-deletes matching items (skips items in mailboxes on litigation hold - see
    README.md Section 11 VERIFY). Only for a mailbox confirmed NOT on hold, after reviewing the
    search's estimateStatistics output.

.NOTES
    Grounded in Microsoft Learn (Microsoft Graph API reference, v1.0, microsoft.graph.security
    namespace) -- see README.md Section 12 for the full citation list. Cmdlet/request shapes:
      - Clear-MgSecurityCaseEdiscoveryCaseSearchData   (POST .../searches/{id}/purgeData)
      - Get-MgSecurityCaseEdiscoveryCaseOperation       (GET .../operations/{id})

    Least-privileged role for this action per Microsoft's own purgeData permissions table:
    Search And Purge (default only to Organization Management members) -- README.md Section 3.

    VERIFY (pilot tenant): whether a mailbox on litigation hold behaves identically for this Graph
    purgeData action as Microsoft's FAQ documents for the PowerShell New-ComplianceSearchAction
    -Purge path (items only hidden from view, not deleted, regardless of purgeType) -- both paths
    share the same underlying eDiscovery search/purge engine, but no Microsoft Learn page
    independently confirms the hold behavior specifically for purgeData. See README.md Section 11
    and design.md Section 2 goal 5.
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory)]
    [string]$CaseId,

    [Parameter(Mandatory)]
    [string]$SearchId,

    [ValidateSet('Recoverable', 'PermanentlyDelete')]
    [string]$PurgeType,

    [switch]$ConfirmPermanentDelete,

    [switch]$ListOnly,

    [Parameter(Mandatory)]
    [string]$AppId,

    [Parameter(Mandatory)]
    [string]$TenantId,

    [Parameter(ParameterSetName = 'Thumbprint')]
    [string]$CertificateThumbprint,

    [Parameter(ParameterSetName = 'CertObject')]
    [System.Security.Cryptography.X509Certificates.X509Certificate2]$Certificate,

    [int]$OperationPollTimeoutSeconds = 1800,
    [int]$OperationPollIntervalSeconds = 30
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($ListOnly -and $PSBoundParameters.ContainsKey('PurgeType')) {
    throw '-ListOnly and -PurgeType are mutually exclusive. Use -ListOnly to review prior purge operations first, then re-run with -PurgeType (no -ListOnly) to start a new one.'
}
if (-not $ListOnly -and -not $PSBoundParameters.ContainsKey('PurgeType')) {
    throw 'Specify either -ListOnly (review prior purge operations) or -PurgeType Recoverable|PermanentlyDelete (start a new purge).'
}
if ($PurgeType -eq 'PermanentlyDelete' -and -not $ConfirmPermanentDelete) {
    throw "-PurgeType PermanentlyDelete requires -ConfirmPermanentDelete as well. This is deliberate -- see .NOTES and README.md Section 11. Permanently deleted items cannot be recovered by the user, an admin, or Microsoft."
}

function Connect-EdiscoveryGraph {
    param($AppId, $TenantId, $CertificateThumbprint, $Certificate)
    if (Get-MgContext) { Write-Verbose 'Reusing existing Microsoft Graph connection.'; return }
    $connectParams = @{ ClientId = $AppId; TenantId = $TenantId; NoWelcome = $true }
    if ($Certificate) { $connectParams['Certificate'] = $Certificate }
    else { $connectParams['CertificateThumbprint'] = $CertificateThumbprint }
    Connect-MgGraph @connectParams
}

function Get-OperationIdFromLocation {
    # Microsoft's own estimateStatistics example shows an OData-canonical Location header
    # (".../operations('698514cc118f4c8b8cdf1bf0797bf478')"), while this repo's
    # premium-legal-hold-and-export sibling script assumed a plain path-segment style
    # (".../operations/abc123") for its own addToReviewSet/export polling -- no purgeData-specific
    # example was published to confirm which style this action returns. Handle both rather than
    # guess one: prefer the quoted-parens form if present, otherwise fall back to the last
    # '/'-delimited segment. See README.md Section 11 / design.md for this VERIFY.
    param([string]$LocationHeader)
    if ($LocationHeader -match "\(\s*'([^']+)'\s*\)\s*$") {
        return $Matches[1]
    }
    return ($LocationHeader -split '/')[-1]
}

function Get-PriorPurgeOperations {
    param($CaseId, $SearchId)

    Get-MgSecurityCaseEdiscoveryCaseOperation -EdiscoveryCaseId $CaseId -All |
        Where-Object { $_.AdditionalProperties['@odata.type'] -eq '#microsoft.graph.security.ediscoveryPurgeDataOperation' }
    # Note: like the addToReviewSet/export idempotency checks in
    # New-EdiscoverySearchReviewSetExport.ps1, caseOperation doesn't expose which search a
    # completed purgeData operation targeted without a follow-up expand -- this listing is
    # therefore case-wide, not guaranteed search-specific. Cross-check SearchId manually if the
    # case has more than one search.
}

function Wait-CaseOperation {
    param($CaseId, $OperationId, [string]$Label)

    $elapsed = 0
    do {
        $op = Get-MgSecurityCaseEdiscoveryCaseOperation -EdiscoveryCaseId $CaseId -CaseOperationId $OperationId
        Write-Verbose "  [$Label] status=$($op.Status) progress=$($op.PercentProgress)% (elapsed ${elapsed}s)"
        if ($op.Status -in @('succeeded', 'partiallySucceeded', 'failed', 'submissionFailed')) { break }
        Start-Sleep -Seconds $OperationPollIntervalSeconds
        $elapsed += $OperationPollIntervalSeconds
    } while ($elapsed -lt $OperationPollTimeoutSeconds)

    if ($op.Status -notin @('succeeded', 'partiallySucceeded', 'failed', 'submissionFailed')) {
        Write-Warning "[$Label] operation $OperationId did not reach a terminal state within ${OperationPollTimeoutSeconds}s (last status: $($op.Status)). It may still be running -- re-check with Get-MgSecurityCaseEdiscoveryCaseOperation later rather than assuming failure."
    } elseif ($op.Status -eq 'failed' -or $op.Status -eq 'submissionFailed') {
        Write-Warning "[$Label] operation $OperationId ended with status '$($op.Status)'. ResultInfo: $($op.ResultInfo | ConvertTo-Json -Compress -Depth 5)"
    } else {
        Write-Host "[$Label] operation $OperationId completed with status '$($op.Status)'."
    }
    return $op
}

# --- main ---

Connect-EdiscoveryGraph -AppId $AppId -TenantId $TenantId `
    -CertificateThumbprint $CertificateThumbprint -Certificate $Certificate

$priorOps = Get-PriorPurgeOperations -CaseId $CaseId -SearchId $SearchId
if ($priorOps) {
    Write-Host "=== Prior purgeData operations in this case ($($priorOps.Count)) ==="
    $priorOps | Sort-Object CreatedDateTime | ForEach-Object {
        Write-Host "  [$($_.CreatedDateTime)] id=$($_.Id) status=$($_.Status)"
    }
} else {
    Write-Host 'No prior purgeData operations found in this case.'
}

if ($ListOnly) {
    return
}

$purgeTypeGraphValue = if ($PurgeType -eq 'PermanentlyDelete') { 'permanentlyDelete' } else { 'recoverable' }
$actionLabel = if ($PurgeType -eq 'PermanentlyDelete') {
    "IRREVERSIBLY hard-delete (permanentlyDelete) matching mailbox items for search $SearchId"
} else {
    "Soft-delete (recoverable) matching mailbox items for search $SearchId"
}

if ($PSCmdlet.ShouldProcess($SearchId, $actionLabel)) {
    $body = @{
        purgeType  = $purgeTypeGraphValue
        purgeAreas = 'mailboxes'
    }
    $responseHeaders = $null
    Clear-MgSecurityCaseEdiscoveryCaseSearchData -EdiscoveryCaseId $CaseId -EdiscoverySearchId $SearchId `
        -BodyParameter $body -ResponseHeadersVariable responseHeaders | Out-Null
    $opId = Get-OperationIdFromLocation -LocationHeader $responseHeaders['Location']
    Write-Host "Started purgeData operation $opId (purgeType=$purgeTypeGraphValue)."

    $op = Wait-CaseOperation -CaseId $CaseId -OperationId $opId -Label 'purgeData'

    if ($op.AdditionalProperties['reportFileMetadata']) {
        Write-Host ''
        Write-Host 'Purge job report available (proof-of-purge record - download and archive with the case):'
        $op.AdditionalProperties['reportFileMetadata'] | ForEach-Object {
            Write-Host "  $($_.fileName) ($($_.size) bytes) - $($_.downloadUrl)"
        }
    }

    Write-Host ''
    Write-Host 'Next: re-run ./New-DataSpillageSearch.ps1 (estimate only) to confirm indexedItemCount has dropped, then ./validate/Test-DataSpillageSearchAndPurge.ps1.'
    if ($PurgeType -eq 'Recoverable') {
        Write-Host 'If any target mailbox is on a litigation hold or retention policy, this purge only hid the item from view - it was NOT permanently deleted. See README.md Section 5 step 4 to chain to priority-cleanup-exchange-data-spillage.'
    }
}
```

#### `New-DataSpillageSearch.ps1`

```powershell
#Requires -Modules @{ ModuleName = 'Microsoft.Graph.Security'; ModuleVersion = '2.25.0' }
#Requires -Modules @{ ModuleName = 'Microsoft.Graph.Authentication'; ModuleVersion = '2.25.0' }

<#
.SYNOPSIS
    Creates (or finds) an eDiscovery case and search for a data-spillage incident, then runs and
    reports an item/mailbox-count estimate -- the "search and validate" half of the search-and-purge
    workflow, before any content is touched.

.DESCRIPTION
    Idempotent, parameterized deploy script for the first (safe, read-only-against-mailbox-content)
    stage of the eDiscovery search-and-purge data-spillage scenario. Uses Microsoft Graph
    (automation surface 3 per docs/automation-surface.md) -- the same reason and the same object
    model as this repo's scenarios/ediscovery/premium-legal-hold-and-export/ sibling: app-only
    authentication for eDiscovery cmdlets in Security & Compliance PowerShell is explicitly
    unsupported by Microsoft (docs/automation-surface.md Section 3).

    Stages, each individually idempotent (re-running this script is always safe -- it never purges):
      1. Find-or-create the eDiscoveryCase by DisplayName.
      2. Find-or-create the search (by DisplayName) with the given contentQuery/dataSourceScopes.
      3. Run a fresh estimateStatistics operation and report indexedItemCount/mailboxCount.

    Every mutating Graph cmdlet used here (New-MgSecurityCaseEdiscoveryCase,
    New-MgSecurityCaseEdiscoveryCaseSearch) natively implements ShouldProcess, so -WhatIf on this
    script fans out to a true dry run -- no case, search, or estimate operation is created.

    This script never calls purgeData. See Invoke-DataSpillagePurge.ps1 for the destructive stage,
    and review this script's estimate output (indexedItemCount / mailboxCount) before running it.

.PARAMETER DefinitionPath
    Path to a JSON file matching deploy/policy/data-spillage-search-definition.sample.json's shape
    (case, search). Keeps the case/query definition out of the script body -- see that file's own
    _comment about treating it as sensitive for the life of the incident.

.PARAMETER AppId
    Application (client) ID of the Entra app registration used for Graph app-only auth.

.PARAMETER TenantId
    Directory (tenant) ID.

.PARAMETER CertificateThumbprint
    Thumbprint of the client certificate installed in the current user's certificate store, used
    for certificate-based app-only authentication (docs/automation-surface.md Section 3). Mutually
    exclusive with -Certificate.

.PARAMETER Certificate
    An in-memory X509Certificate2 object (for example, resolved from Key Vault at run time) to use
    instead of -CertificateThumbprint. Mutually exclusive with -CertificateThumbprint.

.PARAMETER SkipEstimate
    Skip the estimateStatistics call (for example, to only reconcile the case/search objects).
    Off by default -- reviewing the estimate before purging is the entire point of this script.

.EXAMPLE
    ./New-DataSpillageSearch.ps1 -DefinitionPath ./policy/data-spillage-search-definition.sample.json `
        -AppId $AppId -TenantId $TenantId -CertificateThumbprint $Thumbprint -WhatIf

    Reports every case/search/estimate action this run would take, without calling any mutating
    Graph endpoint.

.EXAMPLE
    ./New-DataSpillageSearch.ps1 -DefinitionPath ./policy/data-spillage-search-definition.sample.json `
        -AppId $AppId -TenantId $TenantId -CertificateThumbprint $Thumbprint

    Creates the case and search (if they don't already exist) and prints the current item/mailbox
    count estimate.

.NOTES
    Grounded in Microsoft Learn (Microsoft Graph API reference, v1.0, microsoft.graph.security
    namespace) -- see README.md Section 12 for the full citation list. Cmdlet names and request
    shapes used here:
      - New-MgSecurityCaseEdiscoveryCase                              (POST /security/cases/ediscoveryCases)
      - New-MgSecurityCaseEdiscoveryCaseSearch                        (POST .../searches)
      - Invoke-MgEstimateSecurityCaseEdiscoveryCaseSearchStatistics   (POST .../searches/{id}/estimateStatistics)
      - Get-MgSecurityCaseEdiscoveryCaseOperation                     (GET .../operations/{id})

    A Graph-created case is an eDiscovery (Premium)-configured case -- see README.md Section 3 and
    design.md Section 3 for the licensing implication (E5/Suite/add-on, not E3).
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
param(
    [Parameter(Mandatory)]
    [ValidateScript({ Test-Path $_ -PathType Leaf })]
    [string]$DefinitionPath,

    [Parameter(Mandatory)]
    [string]$AppId,

    [Parameter(Mandatory)]
    [string]$TenantId,

    [Parameter(ParameterSetName = 'Thumbprint')]
    [string]$CertificateThumbprint,

    [Parameter(ParameterSetName = 'CertObject')]
    [System.Security.Cryptography.X509Certificates.X509Certificate2]$Certificate,

    [switch]$SkipEstimate,

    [int]$OperationPollTimeoutSeconds = 900,
    [int]$OperationPollIntervalSeconds = 20
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Connect-EdiscoveryGraph {
    param($AppId, $TenantId, $CertificateThumbprint, $Certificate)
    if (Get-MgContext) { Write-Verbose 'Reusing existing Microsoft Graph connection.'; return }
    $connectParams = @{ ClientId = $AppId; TenantId = $TenantId; NoWelcome = $true }
    if ($Certificate) { $connectParams['Certificate'] = $Certificate }
    else { $connectParams['CertificateThumbprint'] = $CertificateThumbprint }
    Connect-MgGraph @connectParams
}

function Get-OrNewSpillageCase {
    param($Definition)

    $existing = Get-MgSecurityCaseEdiscoveryCase -All |
        Where-Object { $_.DisplayName -eq $Definition.displayName } |
        Select-Object -First 1
    if ($existing) {
        Write-Verbose "Case '$($Definition.displayName)' already exists (id=$($existing.Id))."
        return $existing
    }

    $body = @{
        displayName = $Definition.displayName
        description = $Definition.description
        externalId  = $Definition.externalId
    }
    if ($PSCmdlet.ShouldProcess($Definition.displayName, 'Create eDiscovery case')) {
        $created = New-MgSecurityCaseEdiscoveryCase -BodyParameter $body
        Write-Host "Created case '$($created.DisplayName)' (id=$($created.Id))."
        return $created
    }
    return [pscustomobject]@{ Id = '<case-id-pending>'; DisplayName = $Definition.displayName }
}

function Get-OrNewSpillageSearch {
    param($CaseId, $Definition)

    $existing = Get-MgSecurityCaseEdiscoveryCaseSearch -EdiscoveryCaseId $CaseId -All |
        Where-Object { $_.DisplayName -eq $Definition.displayName } |
        Select-Object -First 1
    if ($existing) {
        Write-Verbose "Search '$($Definition.displayName)' already exists (id=$($existing.Id))."
        return $existing
    }

    if ($PSCmdlet.ShouldProcess($Definition.displayName, "Create eDiscovery search in case $CaseId")) {
        $created = New-MgSecurityCaseEdiscoveryCaseSearch -EdiscoveryCaseId $CaseId `
            -DisplayName $Definition.displayName `
            -Description $Definition.description `
            -ContentQuery $Definition.contentQuery `
            -DataSourceScopes $Definition.dataSourceScopes
        Write-Host "Created search '$($created.DisplayName)' (id=$($created.Id))."
        return $created
    }
    return [pscustomobject]@{ Id = '<search-id-pending>'; DisplayName = $Definition.displayName }
}

function Get-OperationIdFromLocation {
    # See Invoke-DataSpillagePurge.ps1's identical helper for why both the OData-canonical
    # ("operations('id')") and plain path-segment ("operations/id") Location styles are handled
    # rather than assuming one -- Microsoft's own estimateStatistics example uses the former, while
    # this repo's premium-legal-hold-and-export sibling assumed the latter for its own polling.
    param([string]$LocationHeader)
    if ($LocationHeader -match "\(\s*'([^']+)'\s*\)\s*$") {
        return $Matches[1]
    }
    return ($LocationHeader -split '/')[-1]
}

function Wait-CaseOperation {
    param($CaseId, $OperationId, [string]$Label)

    $elapsed = 0
    do {
        $op = Get-MgSecurityCaseEdiscoveryCaseOperation -EdiscoveryCaseId $CaseId -CaseOperationId $OperationId
        Write-Verbose "  [$Label] status=$($op.Status) progress=$($op.PercentProgress)% (elapsed ${elapsed}s)"
        if ($op.Status -in @('succeeded', 'partiallySucceeded', 'failed', 'submissionFailed')) { break }
        Start-Sleep -Seconds $OperationPollIntervalSeconds
        $elapsed += $OperationPollIntervalSeconds
    } while ($elapsed -lt $OperationPollTimeoutSeconds)

    if ($op.Status -notin @('succeeded', 'partiallySucceeded', 'failed', 'submissionFailed')) {
        Write-Warning "[$Label] operation $OperationId did not reach a terminal state within ${OperationPollTimeoutSeconds}s (last status: $($op.Status)). It may still be running -- re-check with Get-MgSecurityCaseEdiscoveryCaseOperation later rather than assuming failure."
    }
    return $op
}

# --- main ---

$definition = Get-Content -Path $DefinitionPath -Raw | ConvertFrom-Json

Connect-EdiscoveryGraph -AppId $AppId -TenantId $TenantId `
    -CertificateThumbprint $CertificateThumbprint -Certificate $Certificate

$case = Get-OrNewSpillageCase -Definition $definition.case
$search = Get-OrNewSpillageSearch -CaseId $case.Id -Definition $definition.search

if (-not $SkipEstimate) {
    if ($PSCmdlet.ShouldProcess($search.DisplayName, 'Run estimateStatistics')) {
        $responseHeaders = $null
        Invoke-MgEstimateSecurityCaseEdiscoveryCaseSearchStatistics -EdiscoveryCaseId $case.Id `
            -EdiscoverySearchId $search.Id -ResponseHeadersVariable responseHeaders | Out-Null
        $opId = Get-OperationIdFromLocation -LocationHeader $responseHeaders['Location']
        Write-Host "Started estimateStatistics operation $opId."
        $op = Wait-CaseOperation -CaseId $case.Id -OperationId $opId -Label 'estimateStatistics'

        Write-Host ''
        Write-Host '=== Estimate result - review before purging ==='
        Write-Host "  Status:            $($op.Status)"
        Write-Host "  Indexed items:     $($op.AdditionalProperties['indexedItemCount'])"
        Write-Host "  Indexed size:      $($op.AdditionalProperties['indexedItemsSize']) bytes"
        Write-Host "  Mailboxes with hits: $($op.AdditionalProperties['mailboxCount'])"
        Write-Host "  Unindexed items:   $($op.AdditionalProperties['unindexedItemCount']) (NOT deleted by purge - see README.md Section 11)"
        Write-Host ''
        Write-Host "If these counts don't match the known spillage scope, refine the definition file's search.contentQuery and re-run this script (idempotent) before running Invoke-DataSpillagePurge.ps1."
    }
} else {
    Write-Verbose '-SkipEstimate passed; not running estimateStatistics.'
}

Write-Host ''
Write-Host "Done. Case '$($case.DisplayName)' (id=$($case.Id)), search '$($search.DisplayName)' (id=$($search.Id))."
Write-Host "Next: ./Invoke-DataSpillagePurge.ps1 -CaseId $($case.Id) -SearchId $($search.Id) -PurgeType Recoverable -WhatIf"
```

#### `policy/data-spillage-search-definition.sample.json`

```json
{
  "_comment": "Reference definition for the eDiscovery search-and-purge data-spillage scenario. Consumed by New-DataSpillageSearch.ps1 via -DefinitionPath. Author-only reference for the buyer's own tenant -- replace every value below before use. No secrets belong in this file. The contentQuery itself may end up containing spilled data (e.g. a distinctive phrase from the leaked document) -- treat this file as sensitive for the life of the incident and delete/archive it with the rest of the case record once closed (README.md Section 11 / retired walkthrough's own 'delete the search query' step, cited in design.md Section 2).",
  "case": {
    "displayName": "CONTOSO-SPILL-2026-031",
    "description": "Confidential Q3 restructuring memo emailed to an internal distribution list outside the intended recipient set. Reported by Legal 2026-09-10.",
    "externalId": "2026-031"
  },
  "search": {
    "displayName": "CONTOSO-SPILL-2026-031 - Restructuring memo sweep",
    "description": "All tenant mailboxes for the leaked attachment name and the reporting date range. Narrow further (sender, exact subject phrase) if the estimate's mailboxCount is larger than the known distribution list.",
    "contentQuery": "(AttachmentNames:\"Q3-Restructuring-Draft.docx\") AND (sent>=2026-09-09)",
    "dataSourceScopes": "allTenantMailboxes"
  }
}
```