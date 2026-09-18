---
part: "deploy"
parent: "ediscovery/search-and-purge-teams-messages"
---
The scripts and configuration below deploy this scenario. Review them, then run in order — each is designed to be idempotent and has a matching rollback.


#### `Invoke-TeamsMessagePurge.ps1`

```powershell
#Requires -Modules @{ ModuleName = 'Microsoft.Graph.Security'; ModuleVersion = '2.25.0' }
#Requires -Modules @{ ModuleName = 'Microsoft.Graph.Authentication'; ModuleVersion = '2.25.0' }

<#
.SYNOPSIS
    Purges Microsoft Teams messages matched by an existing eDiscovery search created by
    New-TeamsMessagePurgeSearch.ps1. Unlike this repo's search-and-purge-data-spillage (mailbox)
    sibling, NO purge of Teams content is reversible for the user-visible message -- both
    -PurgeType values permanently delete it on success -- so -ConfirmPermanentDelete is REQUIRED
    unconditionally, not just for -PurgeType PermanentlyDelete.

.DESCRIPTION
    The destructive second stage of the eDiscovery search-and-purge Teams-messages scenario. Calls
    Microsoft Graph's ediscoverySearch: purgeData action (Clear-MgSecurityCaseEdiscoveryCaseSearchData)
    with purgeAreas: teamsMessages -- see design.md Section 2/Section 7 for why this script's
    confirmation gate differs from the mailbox sibling's. Microsoft's own Graph reference states:
    "When purgeType is set to either recoverable or permanentlyDelete and purgeAreas is set to
    teamsMessages, the Teams messages are permanently deleted." The user-visible message is replaced
    immediately with an admin-deletion tombstone in the Teams client; the compliance copy is
    retained at least 24 hours before background deletion (typically 1-7 days) -- see README.md
    Section 6.

    Deliberately NOT idempotent-by-skip, matching the mailbox sibling: re-running a purge against
    the same search is the documented way to clear more than the 100-items-per-location ceiling, or
    to catch newly matched content. This script therefore lists prior purge operations against the
    case for audit-trail awareness (-ListOnly) but never auto-skips a requested purge.

    An active hold or retention policy on a target mailbox BLOCKS this purge entirely (Microsoft's
    own documented behavior for Teams, a materially different outcome than the mailbox sibling's
    "held mailboxes are just skipped/hidden") -- remove holds before running this script and reapply
    them afterward (README.md Section 5 steps 3/6). This script does not automate either step.

.PARAMETER CaseId
    The eDiscoveryCase id (from New-TeamsMessagePurgeSearch.ps1's output).

.PARAMETER SearchId
    The ediscoverySearch id within that case (from New-TeamsMessagePurgeSearch.ps1's output).

.PARAMETER PurgeType
    'Recoverable' or 'PermanentlyDelete'. For Teams messages, BOTH values permanently delete the
    user-visible message on success -- neither is a safe default the way -PurgeType Recoverable is
    for the mailbox sibling. Kept because it's a required Graph request property and may still
    affect the compliance copy's own retention/hold-interaction timeline (unconfirmed -- see
    README.md Section 11 VERIFY).

.PARAMETER ConfirmPermanentDelete
    REQUIRED for every purge this script runs, regardless of -PurgeType. A deliberate deviation from
    the mailbox sibling (which only requires this for -PurgeType PermanentlyDelete) because no
    Teams purge is reversible for the user-visible message -- design.md Section 7.

.PARAMETER ListOnly
    Only lists prior purgeData operations against the case (status, completion time) without
    starting a new one.

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
    ./Invoke-TeamsMessagePurge.ps1 -CaseId $caseId -SearchId $searchId -ListOnly `
        -AppId $AppId -TenantId $TenantId -CertificateThumbprint $Thumbprint

    Reports every prior purgeData operation in this case without starting a new one.

.EXAMPLE
    ./Invoke-TeamsMessagePurge.ps1 -CaseId $caseId -SearchId $searchId -PurgeType Recoverable `
        -ConfirmPermanentDelete -AppId $AppId -TenantId $TenantId -CertificateThumbprint $Thumbprint -WhatIf

    Reports the purge this run would start, without calling purgeData. Note -ConfirmPermanentDelete
    is required here even though -PurgeType is Recoverable -- see .DESCRIPTION.

.NOTES
    Grounded in Microsoft Learn (Microsoft Graph API reference, v1.0, microsoft.graph.security
    namespace; "Find and delete Microsoft Teams chat messages in eDiscovery") -- see README.md
    Section 12 for the full citation list. Cmdlet/request shapes:
      - Clear-MgSecurityCaseEdiscoveryCaseSearchData   (POST .../searches/{id}/purgeData)
      - Get-MgSecurityCaseEdiscoveryCaseOperation       (GET .../operations/{id})

    Least-privileged role for this action: Search And Purge. For this Teams-specific workflow,
    Microsoft documents it as assigned to the Data Investigator and Organization Management role
    groups by default -- README.md Section 3.

    VERIFY: whether -PurgeType still meaningfully affects the compliance copy's own retention or
    hold-interaction timeline for Teams, even though it no longer gates the user-copy outcome -- no
    Microsoft Learn page found during this build confirms either way. README.md Section 11.
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
if (-not $ListOnly -and -not $ConfirmPermanentDelete) {
    throw "-ConfirmPermanentDelete is required for EVERY Teams purge this script runs, regardless of -PurgeType. This is deliberate -- see .DESCRIPTION and README.md Section 2/11. Both 'recoverable' and 'permanentlyDelete' permanently delete the Teams user-visible message; unlike the mailbox sibling, there is no reversible default here."
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
    param([string]$LocationHeader)
    if ($LocationHeader -match "\(\s*'([^']+)'\s*\)\s*$") {
        return $Matches[1]
    }
    return ($LocationHeader -split '/')[-1]
}

function Get-PriorPurgeOperations {
    param($CaseId)

    Get-MgSecurityCaseEdiscoveryCaseOperation -EdiscoveryCaseId $CaseId -All |
        Where-Object { $_.AdditionalProperties['@odata.type'] -eq '#microsoft.graph.security.ediscoveryPurgeDataOperation' }
    # Case-wide, not search-specific -- same disclosed limitation as the mailbox sibling's
    # Get-PriorPurgeOperations (caseOperation doesn't expose which search or purgeAreas value a
    # completed purgeData operation targeted without a further, undocumented expand).
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

$priorOps = Get-PriorPurgeOperations -CaseId $CaseId
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

Write-Warning 'This purge is IRREVERSIBLE for the Teams user-visible message regardless of -PurgeType. Confirm the estimateStatistics review (New-TeamsMessagePurgeSearch.ps1) and that holds have been removed from every target mailbox (README.md Section 5 step 3) before proceeding.'

$purgeTypeGraphValue = if ($PurgeType -eq 'PermanentlyDelete') { 'permanentlyDelete' } else { 'recoverable' }
$actionLabel = "IRREVERSIBLY delete the Teams user-visible message(s) matching search $SearchId (purgeType=$purgeTypeGraphValue)"

if ($PSCmdlet.ShouldProcess($SearchId, $actionLabel)) {
    $body = @{
        purgeType  = $purgeTypeGraphValue
        purgeAreas = 'teamsMessages'
    }
    $responseHeaders = $null
    Clear-MgSecurityCaseEdiscoveryCaseSearchData -EdiscoveryCaseId $CaseId -EdiscoverySearchId $SearchId `
        -BodyParameter $body -ResponseHeadersVariable responseHeaders | Out-Null
    $opId = Get-OperationIdFromLocation -LocationHeader $responseHeaders['Location']
    Write-Host "Started purgeData operation $opId (purgeType=$purgeTypeGraphValue, purgeAreas=teamsMessages)."

    $op = Wait-CaseOperation -CaseId $CaseId -OperationId $opId -Label 'purgeData'

    if ($op.AdditionalProperties['reportFileMetadata']) {
        Write-Host ''
        Write-Host 'Purge job report available (proof-of-purge record - download and archive with the case):'
        $op.AdditionalProperties['reportFileMetadata'] | ForEach-Object {
            Write-Host "  $($_.fileName) ($($_.size) bytes) - $($_.downloadUrl)"
        }
    }

    Write-Host ''
    Write-Host 'Verify in the Teams client: purged messages are replaced with "This message was deleted by an admin."'
    Write-Host 'Next: re-run ./New-TeamsMessagePurgeSearch.ps1 (estimate only) to confirm indexedItemCount has dropped, then ./validate/Test-TeamsMessagePurgeSearchAndPurge.ps1.'
    Write-Host 'REMINDER: reapply every hold/retention policy removed before this purge (README.md Section 5 step 6).'
}
```

#### `New-TeamsMessagePurgeSearch.ps1`

```powershell
#Requires -Modules @{ ModuleName = 'Microsoft.Graph.Security'; ModuleVersion = '2.25.0' }
#Requires -Modules @{ ModuleName = 'Microsoft.Graph.Authentication'; ModuleVersion = '2.25.0' }

<#
.SYNOPSIS
    Creates (or finds) an eDiscovery case and search for a Microsoft Teams message incident, binds
    the declared target mailboxes as non-custodial data sources, then runs and reports an
    item/mailbox-count estimate -- the "search and validate" half of the Teams search-and-purge
    workflow, before any content is touched.

.DESCRIPTION
    Idempotent, parameterized deploy script for the first (safe, read-only-against-Teams-content)
    stage of the eDiscovery search-and-purge Teams-messages scenario. Uses Microsoft Graph
    (automation surface 3 per docs/automation-surface.md), the same reason and object model as this
    repo's scenarios/ediscovery/search-and-purge-data-spillage/ sibling.

    Unlike that sibling's -DataSourceScopes allTenantMailboxes, Teams content has no Teams-appropriate
    blanket scope -- this script instead binds each declared target mailbox (design.md Section 4:
    chat participants, a parent team's mailbox, or a private-channel mailbox) as an explicit
    ediscoveryNoncustodialDataSource, then attaches those sources to the search via
    noncustodialSources@odata.bind (create) or the /noncustodialSources/$ref endpoint (attach to an
    existing search on a later run).

    Stages, each individually idempotent (re-running this script is always safe -- it never purges):
      1. Find-or-create the eDiscoveryCase by DisplayName.
      2. Find-or-create a case-level noncustodialDataSource for each declared target mailbox.
      3. Find-or-create the search (by DisplayName), binding every resolved noncustodialDataSource.
      4. Run a fresh estimateStatistics operation and report indexedItemCount/mailboxCount.

    This script never calls purgeData. See Invoke-TeamsMessagePurge.ps1 for the destructive stage --
    and note that, unlike the mailbox sibling, NO purge of Teams content is reversible for the
    user-visible message (README.md Section 2). Review this script's estimate output before running
    the purge stage, and remove any hold/retention policy from each target mailbox first (README.md
    Section 5 step 3) -- an active hold blocks a Teams purge entirely rather than just hiding it.

.PARAMETER DefinitionPath
    Path to a JSON file matching deploy/policy/teams-message-purge-search-definition.sample.json's
    shape (case, search.contentQuery, search.targetMailboxes[]).

.PARAMETER AppId
    Application (client) ID of the Entra app registration used for Graph app-only auth.

.PARAMETER TenantId
    Directory (tenant) ID.

.PARAMETER CertificateThumbprint
    Thumbprint of the client certificate installed in the current user's certificate store.
    Mutually exclusive with -Certificate.

.PARAMETER Certificate
    An in-memory X509Certificate2 object. Mutually exclusive with -CertificateThumbprint.

.PARAMETER SkipEstimate
    Skip the estimateStatistics call (for example, to only reconcile the case/search/source objects).
    Off by default -- reviewing the estimate before purging is the entire point of this script.

.EXAMPLE
    ./New-TeamsMessagePurgeSearch.ps1 -DefinitionPath ./policy/teams-message-purge-search-definition.sample.json `
        -AppId $AppId -TenantId $TenantId -CertificateThumbprint $Thumbprint -WhatIf

    Reports every case/source/search/estimate action this run would take, without calling any
    mutating Graph endpoint.

.EXAMPLE
    ./New-TeamsMessagePurgeSearch.ps1 -DefinitionPath ./policy/teams-message-purge-search-definition.sample.json `
        -AppId $AppId -TenantId $TenantId -CertificateThumbprint $Thumbprint

    Creates the case, target-mailbox sources, and search (if they don't already exist) and prints
    the current item/mailbox count estimate.

.NOTES
    Grounded in Microsoft Learn (Microsoft Graph API reference, v1.0, microsoft.graph.security
    namespace) -- see README.md Section 12 for the full citation list. Cmdlet/request shapes used:
      - New-MgSecurityCaseEdiscoveryCase                              (POST /security/cases/ediscoveryCases)
      - New-MgSecurityCaseEdiscoveryCaseNoncustodialDataSource        (POST .../noncustodialDataSources)
      - New-MgSecurityCaseEdiscoveryCaseSearch (-BodyParameter)       (POST .../searches, with noncustodialSources@odata.bind)
      - Invoke-MgEstimateSecurityCaseEdiscoveryCaseSearchStatistics   (POST .../searches/{id}/estimateStatistics)
      - Get-MgSecurityCaseEdiscoveryCaseOperation                     (GET .../operations/{id})

    VERIFY (pilot tenant or a future Microsoft Learn/SDK pass): this script binds a
    noncustodialDataSource onto an EXISTING search (the case where the search was created on a
    prior run without every currently-declared mailbox) via a raw Invoke-MgGraphRequest POST to
    .../searches/{id}/noncustodialSources/$ref rather than a typed cmdlet -- this build found no
    Microsoft Learn page confirming the typed Microsoft.Graph.Security v1.0 cmdlet name for that
    specific $ref-bind action (the SDK's usual convention would suggest something like
    New-MgSecurityCaseEdiscoveryCaseSearchNoncustodialSourceByRef, but that name is unconfirmed).
    See README.md Section 11 / design.md Section 6.

    VERIFY (pilot tenant): a case-level ediscoveryNoncustodialDataSource's DisplayName for a
    userSource (mailbox) is not shown in any worked example this build found (only a siteSource
    example, where DisplayName is the SharePoint site title) -- Get-OrNewTargetSource below matches
    on DisplayName as a best-effort heuristic. design.md Section 6.
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

function Get-OrNewTeamsCase {
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

function Get-OrNewTargetSource {
    # Find-or-create a case-level noncustodialDataSource for one target mailbox. Matches on
    # DisplayName as a best-effort heuristic -- see this script's .NOTES VERIFY.
    param($CaseId, [string]$Email)

    $existing = Get-MgSecurityCaseEdiscoveryCaseNoncustodialDataSource -EdiscoveryCaseId $CaseId -All |
        Where-Object { $_.DisplayName -eq $Email } | Select-Object -First 1
    if ($existing) {
        Write-Verbose "Non-custodial source for '$Email' already exists (id=$($existing.Id))."
        return $existing
    }

    $body = @{
        dataSource = @{
            '@odata.type' = 'microsoft.graph.security.userSource'
            email         = $Email
        }
    }
    if ($PSCmdlet.ShouldProcess($Email, "Create non-custodial data source in case $CaseId")) {
        $created = New-MgSecurityCaseEdiscoveryCaseNoncustodialDataSource -EdiscoveryCaseId $CaseId -BodyParameter $body
        Write-Host "Created non-custodial data source for '$Email' (id=$($created.Id))."
        return $created
    }
    return [pscustomobject]@{ Id = '<source-id-pending>'; DisplayName = $Email }
}

function Get-OrNewTeamsSearch {
    param($CaseId, $Definition, [array]$SourceIds)

    $existing = Get-MgSecurityCaseEdiscoveryCaseSearch -EdiscoveryCaseId $CaseId -All |
        Where-Object { $_.DisplayName -eq $Definition.displayName } |
        Select-Object -First 1
    if ($existing) {
        Write-Verbose "Search '$($Definition.displayName)' already exists (id=$($existing.Id))."
        # Attach any source not yet bound (e.g. a mailbox added to the definition file after the
        # search was first created). See this script's .NOTES VERIFY on the $ref-bind cmdlet name.
        $boundIds = (Get-MgSecurityCaseEdiscoveryCaseSearchNoncustodialSource -EdiscoveryCaseId $CaseId `
                -EdiscoverySearchId $existing.Id -All).Id
        foreach ($sourceId in $SourceIds) {
            if ($sourceId -in $boundIds) { continue }
            $refBody = @{ '@odata.id' = "https://graph.microsoft.com/v1.0/security/cases/ediscoveryCases/$CaseId/noncustodialDataSources/$sourceId" }
            if ($PSCmdlet.ShouldProcess($sourceId, "Bind non-custodial source to search $($existing.Id)")) {
                Invoke-MgGraphRequest -Method POST `
                    -Uri "https://graph.microsoft.com/v1.0/security/cases/ediscoveryCases/$CaseId/searches/$($existing.Id)/noncustodialSources/`$ref" `
                    -Body ($refBody | ConvertTo-Json) -ContentType 'application/json' | Out-Null
                Write-Host "Bound non-custodial source $sourceId to existing search $($existing.Id)."
            }
        }
        return $existing
    }

    $bindUris = $SourceIds | ForEach-Object {
        "https://graph.microsoft.com/v1.0/security/cases/ediscoveryCases/$CaseId/noncustodialDataSources/$_"
    }
    $body = @{
        displayName                    = $Definition.displayName
        description                    = $Definition.description
        contentQuery                   = $Definition.contentQuery
        dataSourceScopes               = 'none'
        'noncustodialSources@odata.bind' = @($bindUris)
    }
    if ($PSCmdlet.ShouldProcess($Definition.displayName, "Create eDiscovery search in case $CaseId with $($SourceIds.Count) bound source(s)")) {
        $created = New-MgSecurityCaseEdiscoveryCaseSearch -EdiscoveryCaseId $CaseId -BodyParameter $body
        Write-Host "Created search '$($created.DisplayName)' (id=$($created.Id)) with $($SourceIds.Count) bound source(s)."
        return $created
    }
    return [pscustomobject]@{ Id = '<search-id-pending>'; DisplayName = $Definition.displayName }
}

function Get-OperationIdFromLocation {
    # See search-and-purge-data-spillage's identical helper: both the OData-canonical
    # ("operations('id')") and plain path-segment ("operations/id") Location styles are handled
    # rather than assuming one.
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

$case = Get-OrNewTeamsCase -Definition $definition.case

$sourceIds = foreach ($target in $definition.search.targetMailboxes) {
    $source = Get-OrNewTargetSource -CaseId $case.Id -Email $target.email
    Write-Verbose "Target mailbox '$($target.email)' (sourceType=$($target.sourceType)) -> source id $($source.Id)"
    $source.Id
}

$search = Get-OrNewTeamsSearch -CaseId $case.Id -Definition $definition.search -SourceIds $sourceIds

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
        Write-Host "  Status:              $($op.Status)"
        Write-Host "  Indexed items:       $($op.AdditionalProperties['indexedItemCount'])"
        Write-Host "  Indexed size:        $($op.AdditionalProperties['indexedItemsSize']) bytes"
        Write-Host "  Mailboxes with hits: $($op.AdditionalProperties['mailboxCount'])"
        Write-Host "  Unindexed items:     $($op.AdditionalProperties['unindexedItemCount']) (NOT deleted by purge)"
        Write-Host ''
        Write-Host "If these counts don't match the known incident scope, refine the definition file's search.contentQuery and re-run this script (idempotent) before running Invoke-TeamsMessagePurge.ps1."
    }
} else {
    Write-Verbose '-SkipEstimate passed; not running estimateStatistics.'
}

Write-Host ''
Write-Host "Done. Case '$($case.DisplayName)' (id=$($case.Id)), search '$($search.DisplayName)' (id=$($search.Id)), $($sourceIds.Count) target mailbox source(s) bound."
Write-Host 'REMINDER: remove any hold/retention policy from every target mailbox before purging -- an active hold blocks a Teams purge entirely (README.md Section 5 step 3).'
Write-Host "Next: ./Invoke-TeamsMessagePurge.ps1 -CaseId $($case.Id) -SearchId $($search.Id) -PurgeType Recoverable -ConfirmPermanentDelete -WhatIf"
```

#### `policy/teams-message-purge-search-definition.sample.json`

```json
{
  "_comment": "Reference definition for the eDiscovery search-and-purge Teams-messages scenario. Consumed by New-TeamsMessagePurgeSearch.ps1 via -DefinitionPath. Author-only reference for the buyer's own tenant -- replace every value below before use. No secrets belong in this file. targetMailboxes must be pre-resolved (README.md Section 3/5): standard/shared channel -> parent team mailbox via ../../teams-group-hold-resolution/; 1:1/group chat -> the known participant addresses; private channel -> confirm against README.md Section 11's open VERIFY before relying on a single mailbox. The contentQuery itself may end up containing sensitive keywords from the incident -- treat this file as sensitive for the life of the incident, same as the search-and-purge-data-spillage sibling's own sample config.",
  "case": {
    "displayName": "CONTOSO-TEAMS-2026-014",
    "description": "Inappropriate content posted in the Payments Team standard channel and forwarded via 1:1 chat. Reported by HR 2026-09-10.",
    "externalId": "2026-014"
  },
  "search": {
    "displayName": "CONTOSO-TEAMS-2026-014 - Teams message sweep",
    "description": "Named target mailboxes for the reported channel post and its 1:1 forward. Narrow the date range further if the estimate's indexedItemCount is larger than expected.",
    "contentQuery": "kind:microsoftteams AND (received>=2026-09-09)",
    "targetMailboxes": [
      {
        "email": "payments-team@contoso.com",
        "sourceType": "StandardOrSharedChannel",
        "note": "Parent team mailbox for the Payments Team standard channel, resolved via ../../teams-group-hold-resolution/deploy/Resolve-TeamsGroupHoldLocations.ps1"
      },
      {
        "email": "alex.chen@contoso.com",
        "sourceType": "OneToOneChat",
        "note": "Forwarded the channel post via 1:1 chat to jordan.lee@contoso.com"
      },
      {
        "email": "jordan.lee@contoso.com",
        "sourceType": "OneToOneChat",
        "note": "Recipient of the 1:1 forward"
      }
    ]
  }
}
```