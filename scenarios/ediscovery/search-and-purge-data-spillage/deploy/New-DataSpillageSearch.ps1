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
