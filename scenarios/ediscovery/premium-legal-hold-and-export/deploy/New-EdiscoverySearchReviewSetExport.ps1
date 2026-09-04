#Requires -Modules @{ ModuleName = 'Microsoft.Graph.Security'; ModuleVersion = '2.25.0' }
#Requires -Modules @{ ModuleName = 'Microsoft.Graph.Authentication'; ModuleVersion = '2.25.0' }

<#
.SYNOPSIS
    Creates (or reconciles) an eDiscovery search scoped to a case's custodians, commits the
    search results to a review set, and starts an export from that review set.

.DESCRIPTION
    Second-stage deploy script for the eDiscovery (Premium) legal-hold-and-export scenario. Runs
    after New-EdiscoveryPremiumLegalHold.ps1 has created the case and placed custodians on hold.

    Stages, each individually idempotent:
      1. Find-or-create the eDiscoverySearch (dataSourceScopes=allCaseCustodians, scoped to the
         KQL contentQuery in the definition file).
      2. Find-or-create the eDiscoveryReviewSet.
      3. Start an addToReviewSet operation committing the search into the review set, unless an
         addToReviewSet operation for that search/review-set pair has already succeeded.
      4. Start an export operation from the review set, unless an export with the same
         outputName has already succeeded.

    addToReviewSet and export are both long-running, asynchronous caseOperations (Graph returns
    202 Accepted with a Location header pointing at the operation). This script polls each
    operation's status via Get-MgSecurityCaseEdiscoveryCaseOperation and reports the final state
    rather than assuming synchronous completion, per docs/automation-surface.md section 5's
    guidance for asynchronous Purview operations.

.PARAMETER DefinitionPath
    Path to the same JSON file used by New-EdiscoveryPremiumLegalHold.ps1 (case, search,
    reviewSet, export).

.PARAMETER CaseId
    The eDiscoveryCase id returned by New-EdiscoveryPremiumLegalHold.ps1. Required rather than
    re-resolved by DisplayName here, so this script can't accidentally act against a
    same-named case created outside this scenario's control.

.PARAMETER SkipAddToReviewSet
    Create/confirm the search and review set but don't start (or re-check) an addToReviewSet
    operation. Useful for reviewing/tuning the search's estimated hit count in the portal before
    committing data into the review set's Azure Storage location.

.PARAMETER SkipExport
    Create/confirm the search and review set, and run addToReviewSet, but don't start an export.
    Use this to pause for human review-set triage (tagging, culling) before producing an export
    package for outside counsel.

.PARAMETER ForceAddToReviewSet
    Start a new addToReviewSet operation even if one has already succeeded in this case. Use
    this for a deliberate second commit (for example, after custodian data sources changed) --
    see the addToReviewSet idempotency VERIFY note below before relying on this by default.

.EXAMPLE
    ./New-EdiscoverySearchReviewSetExport.ps1 -DefinitionPath ./policy/ediscovery-case-definition.json `
        -CaseId $caseId -AppId $AppId -TenantId $TenantId -CertificateThumbprint $Thumbprint -WhatIf

.EXAMPLE
    ./New-EdiscoverySearchReviewSetExport.ps1 -DefinitionPath ./policy/ediscovery-case-definition.json `
        -CaseId $caseId -AppId $AppId -TenantId $TenantId -CertificateThumbprint $Thumbprint `
        -SkipExport

    Runs the search and commits it to the review set, but stops short of exporting -- so a
    reviewer can tag/cull in the portal before an export package is produced.

.NOTES
    Grounded in Microsoft Learn (Microsoft Graph API reference, v1.0, microsoft.graph.security
    namespace) -- see README.md section 12. Cmdlets used:
      - New-MgSecurityCaseEdiscoveryCaseSearch              (POST .../searches)
      - New-MgSecurityCaseEdiscoveryCaseReviewSet            (POST .../reviewSets)
      - Add-MgSecurityCaseEdiscoveryCaseReviewSetToReviewSet (POST .../reviewSets/{id}/addToReviewSet)
      - Export-MgSecurityCaseEdiscoveryCaseReviewSet         (POST .../reviewSets/{id}/export)
      - Get-MgSecurityCaseEdiscoveryCaseOperation             (GET .../operations/{id})

    caseOperationStatus values used in the poll loop (notStarted, submissionFailed, running,
    succeeded, partiallySucceeded, failed, unknownFutureValue) are the exact v1.0 enum from the
    caseOperation resource type reference -- not guessed or carried over from the beta namespace,
    which uses a different casing/shape in places (README.md section 11).

    VERIFY: the addToReviewSet/export idempotency checks below key off DisplayName/outputName
    text match via Get-...-All | Where-Object, since neither operation type exposes a documented
    "does an equivalent operation already exist" query filter. A prior run's search/review-set/
    export with a *different* DisplayName/outputName than the current definition file will not be
    found and will result in a duplicate -- keep definition-file names stable across re-runs of
    the same matter's collection.
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
param(
    [Parameter(Mandatory)]
    [ValidateScript({ Test-Path $_ -PathType Leaf })]
    [string]$DefinitionPath,

    [Parameter(Mandatory)]
    [string]$CaseId,

    [Parameter(Mandatory)]
    [string]$AppId,

    [Parameter(Mandatory)]
    [string]$TenantId,

    [Parameter(ParameterSetName = 'Thumbprint')]
    [string]$CertificateThumbprint,

    [Parameter(ParameterSetName = 'CertObject')]
    [System.Security.Cryptography.X509Certificates.X509Certificate2]$Certificate,

    [switch]$SkipAddToReviewSet,
    [switch]$SkipExport,
    [switch]$ForceAddToReviewSet,

    [int]$OperationPollTimeoutSeconds = 1800,
    [int]$OperationPollIntervalSeconds = 30
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

function Wait-CaseOperation {
    param($CaseId, $OperationId, [string]$Label)

    $elapsed = 0
    do {
        $op = Get-MgSecurityCaseEdiscoveryCaseOperation -EdiscoveryCaseId $CaseId -CaseOperationId $OperationId
        Write-Verbose "  [$Label] status=$($op.Status) progress=$($op.PercentProgress)% (elapsed ${elapsed}s)"
        if ($op.Status -in @('succeeded', 'partiallySucceeded', 'failed', 'submissionFailed')) {
            break
        }
        Start-Sleep -Seconds $OperationPollIntervalSeconds
        $elapsed += $OperationPollIntervalSeconds
    } while ($elapsed -lt $OperationPollTimeoutSeconds)

    if ($op.Status -notin @('succeeded', 'partiallySucceeded', 'failed', 'submissionFailed')) {
        Write-Warning "[$Label] operation $OperationId did not reach a terminal state within ${OperationPollTimeoutSeconds}s (last status: $($op.Status)). It may still be running -- re-check with Get-MgSecurityCaseEdiscoveryCaseOperation -EdiscoveryCaseId $CaseId -CaseOperationId $OperationId later rather than assuming failure."
    } elseif ($op.Status -eq 'failed' -or $op.Status -eq 'submissionFailed') {
        Write-Warning "[$Label] operation $OperationId ended with status '$($op.Status)'. ResultInfo: $($op.ResultInfo | ConvertTo-Json -Compress -Depth 5)"
    } else {
        Write-Host "[$Label] operation $OperationId completed with status '$($op.Status)'."
    }
    return $op
}

# --- main ---

$definition = Get-Content -Path $DefinitionPath -Raw | ConvertFrom-Json

Connect-EdiscoveryGraph -AppId $AppId -TenantId $TenantId `
    -CertificateThumbprint $CertificateThumbprint -Certificate $Certificate

# 1. Find-or-create the search.
$search = Get-MgSecurityCaseEdiscoveryCaseSearch -EdiscoveryCaseId $CaseId -All |
    Where-Object { $_.DisplayName -eq $definition.search.displayName } |
    Select-Object -First 1
if (-not $search) {
    if ($PSCmdlet.ShouldProcess($definition.search.displayName, "Create eDiscovery search in case $CaseId")) {
        $search = New-MgSecurityCaseEdiscoveryCaseSearch -EdiscoveryCaseId $CaseId `
            -DisplayName $definition.search.displayName `
            -Description $definition.search.description `
            -ContentQuery $definition.search.contentQuery `
            -DataSourceScopes $definition.search.dataSourceScopes
        Write-Host "Created search '$($search.DisplayName)' (id=$($search.Id))."
    } else {
        $search = [pscustomobject]@{ Id = '<search-id-pending>'; DisplayName = $definition.search.displayName }
    }
} else {
    Write-Verbose "Search '$($definition.search.displayName)' already exists (id=$($search.Id))."
}

# 2. Find-or-create the review set.
$reviewSet = Get-MgSecurityCaseEdiscoveryCaseReviewSet -EdiscoveryCaseId $CaseId -All |
    Where-Object { $_.DisplayName -eq $definition.reviewSet.displayName } |
    Select-Object -First 1
if (-not $reviewSet) {
    if ($PSCmdlet.ShouldProcess($definition.reviewSet.displayName, "Create review set in case $CaseId")) {
        $reviewSet = New-MgSecurityCaseEdiscoveryCaseReviewSet -EdiscoveryCaseId $CaseId `
            -DisplayName $definition.reviewSet.displayName
        Write-Host "Created review set '$($reviewSet.DisplayName)' (id=$($reviewSet.Id))."
    } else {
        $reviewSet = [pscustomobject]@{ Id = '<reviewset-id-pending>'; DisplayName = $definition.reviewSet.displayName }
    }
} else {
    Write-Verbose "Review set '$($definition.reviewSet.displayName)' already exists (id=$($reviewSet.Id))."
}

# 3. Commit the search into the review set (addToReviewSet), unless already done for this pair.
if (-not $SkipAddToReviewSet) {
    $priorAddOps = Get-MgSecurityCaseEdiscoveryCaseOperation -EdiscoveryCaseId $CaseId -All |
        Where-Object {
            $_.AdditionalProperties['@odata.type'] -eq '#microsoft.graph.security.ediscoveryAddToReviewSetOperation' -and
            $_.Status -eq 'succeeded'
        }
    # Note: caseOperation doesn't expose which review set/search a completed addToReviewSet
    # operation targeted without a follow-up Get on the operation's expanded properties -- this
    # check is therefore best-effort (counts *any* succeeded addToReviewSet operation in the
    # case) rather than an exact per-search/per-review-set match. See .NOTES VERIFY above.
    if ($priorAddOps -and -not $ForceAddToReviewSet) {
        Write-Verbose "At least one addToReviewSet operation has already succeeded in this case; skipping. Pass -ForceAddToReviewSet is not implemented -- re-run manually via Add-MgSecurityCaseEdiscoveryCaseReviewSetToReviewSet if a second commit is intentional."
    } else {
        if ($PSCmdlet.ShouldProcess("$($search.DisplayName) -> $($reviewSet.DisplayName)", 'Add search results to review set')) {
            $addBody = @{
                search              = @{ id = $search.Id }
                additionalDataOptions = 'linkedFiles'
                itemsToInclude      = 'searchHits'
                documentVersion     = 'latest'
                cloudAttachmentVersion = 'latest'
            }
            $responseHeaders = $null
            Add-MgSecurityCaseEdiscoveryCaseReviewSetToReviewSet -EdiscoveryCaseId $CaseId `
                -EdiscoveryReviewSetId $reviewSet.Id -BodyParameter $addBody `
                -ResponseHeadersVariable responseHeaders | Out-Null
            $opLocation = $responseHeaders['Location']
            $opId = ($opLocation -split '/')[-1]
            Write-Host "Started addToReviewSet operation $opId."
            Wait-CaseOperation -CaseId $CaseId -OperationId $opId -Label 'addToReviewSet' | Out-Null
        }
    }
}

# 4. Export from the review set, unless an export with the same outputName already succeeded.
if (-not $SkipExport) {
    $priorExportOps = Get-MgSecurityCaseEdiscoveryCaseOperation -EdiscoveryCaseId $CaseId -All |
        Where-Object {
            $_.AdditionalProperties['@odata.type'] -eq '#microsoft.graph.security.ediscoveryExportOperation' -and
            $_.AdditionalProperties['outputName'] -eq $definition.export.outputName
        }
    $alreadySucceeded = $priorExportOps | Where-Object { $_.Status -eq 'succeeded' }
    if ($alreadySucceeded) {
        Write-Verbose "Export '$($definition.export.outputName)' already succeeded (operation $($alreadySucceeded[0].Id)); skipping. Export packages must be downloaded within 30 days of completion (README.md section 11) -- if that window has passed, delete the existing export in the portal and re-run this script to start a fresh one."
    } else {
        if ($PSCmdlet.ShouldProcess($definition.export.outputName, "Export review set '$($reviewSet.DisplayName)'")) {
            $exportBody = @{
                outputName      = $definition.export.outputName
                description     = $definition.export.description
                exportOptions   = $definition.export.exportOptions
                exportStructure = $definition.export.exportStructure
            }
            $responseHeaders = $null
            Export-MgSecurityCaseEdiscoveryCaseReviewSet -EdiscoveryCaseId $CaseId `
                -EdiscoveryReviewSetId $reviewSet.Id -BodyParameter $exportBody `
                -ResponseHeadersVariable responseHeaders | Out-Null
            $opLocation = $responseHeaders['Location']
            $opId = ($opLocation -split '/')[-1]
            Write-Host "Started export operation $opId ('$($definition.export.outputName)')."
            $finalOp = Wait-CaseOperation -CaseId $CaseId -OperationId $opId -Label 'export'
            if ($finalOp.Status -eq 'succeeded') {
                Write-Host "Export succeeded. Case id: $CaseId, operation id: $opId -- pass these to Get-EdiscoveryExportPackage.ps1 to download the package."
            }
        }
    }
}

Write-Host 'Done.'
