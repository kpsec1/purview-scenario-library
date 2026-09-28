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
    for the mailbox sibling. Kept because it's a required Graph request property; Microsoft's own
    ediscoverySearch: purgeData reference confirms both values behave identically for
    teamsMessages, with no separate compliance-copy timing per value either (grounded 2026-09-28 --
    see README.md Section 11 and design.md Section 7).

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

    Grounded 2026-09-28 (Microsoft Learn MCP), not a VERIFY: -PurgeType does not meaningfully affect
    the compliance copy's retention or hold-interaction timeline for Teams -- Microsoft's own
    ediscoverySearch: purgeData reference confirms both values behave identically for
    teamsMessages. README.md Section 11.
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
