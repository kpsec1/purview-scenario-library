---
part: "validate"
parent: "ediscovery/search-and-purge-teams-messages"
---
Run these checks after deployment to confirm the control is working as designed.


#### `Test-TeamsMessagePurgeSearchAndPurge.ps1`

```powershell
#Requires -Modules @{ ModuleName = 'Microsoft.Graph.Security'; ModuleVersion = '2.25.0' }
#Requires -Modules @{ ModuleName = 'Microsoft.Graph.Authentication'; ModuleVersion = '2.25.0' }

<#
.SYNOPSIS
    Verifies a Teams-message eDiscovery case/search built by this scenario's deploy scripts: the
    case and search exist, the declared target mailboxes are bound as non-custodial sources, reports
    the latest estimateStatistics result, and lists every purgeData operation against the case.

.DESCRIPTION
    Read-only. Requires only eDiscovery.Read.All (README.md Section 3) -- never calls a mutating
    Graph endpoint, including purgeData itself. Exits non-zero on any hard [FAIL] (case/search
    missing, or the most recent purge operation ended 'failed'/'submissionFailed').

    Checks:
      1. Case exists with the expected DisplayName.
      2. Search exists with the expected contentQuery.
      3. Every declared target mailbox has a bound non-custodial source on the search. [WARN] (not
         [FAIL]) for a missing binding, since this script cannot tell from the search object alone
         whether a mismatch means "not yet run" or "portal edit since deploy."
      4. [WARN-only] Reports the most recent estimateStatistics operation's indexedItemCount/
         mailboxCount, if one has run.
      5. Lists every purgeData operation found in the case (status, completion time). [FAIL] if the
         most recent one is 'failed'/'submissionFailed'; [WARN] if still 'running'/'notStarted';
         [PASS] if 'succeeded'/'partiallySucceeded'.

.PARAMETER DefinitionPath
    Same JSON definition file used by New-TeamsMessagePurgeSearch.ps1.

.PARAMETER CaseId
    The eDiscoveryCase id to validate.

.PARAMETER AppId
.PARAMETER TenantId
.PARAMETER CertificateThumbprint
.PARAMETER Certificate
    Same Graph app-only authentication parameters as the deploy/ scripts. A read-only credential
    (eDiscovery.Read.All only) is sufficient and preferred for this script.

.EXAMPLE
    ./Test-TeamsMessagePurgeSearchAndPurge.ps1 -DefinitionPath ../deploy/policy/teams-message-purge-search-definition.sample.json `
        -CaseId $caseId -AppId $AppId -TenantId $TenantId -CertificateThumbprint $Thumbprint

.NOTES
    Manual verification checklist (no read API exists for these -- confirm directly):
      - Whether a target mailbox still has an active hold at purge time (this script cannot tell
        from the purgeData operation object alone) -- see README.md Section 5 steps 3/6.
      - The Teams client tombstone ("This message was deleted by an admin") for the fastest direct,
        human-visible confirmation of a successful purge -- README.md Section 7.
      - The purge job report (reportFileMetadata.downloadUrl, printed by
        Invoke-TeamsMessagePurge.ps1) for a full itemized proof-of-purge record.
#>
[CmdletBinding()]
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
    [System.Security.Cryptography.X509Certificates.X509Certificate2]$Certificate
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:FailCount = 0
$script:WarnCount = 0

function Write-Check {
    param([string]$Message, [ValidateSet('PASS', 'WARN', 'FAIL')][string]$Level)
    $prefix = "[$Level]"
    switch ($Level) {
        'PASS' { Write-Host "$prefix $Message" -ForegroundColor Green }
        'WARN' { Write-Host "$prefix $Message" -ForegroundColor Yellow; $script:WarnCount++ }
        'FAIL' { Write-Host "$prefix $Message" -ForegroundColor Red; $script:FailCount++ }
    }
}

if (Get-MgContext) {
    Write-Verbose 'Reusing existing Microsoft Graph connection.'
} else {
    $connectParams = @{ ClientId = $AppId; TenantId = $TenantId; NoWelcome = $true }
    if ($Certificate) { $connectParams['Certificate'] = $Certificate }
    else { $connectParams['CertificateThumbprint'] = $CertificateThumbprint }
    Connect-MgGraph @connectParams
}

$definition = Get-Content -Path $DefinitionPath -Raw | ConvertFrom-Json

# 1. Case
try {
    $case = Get-MgSecurityCaseEdiscoveryCase -EdiscoveryCaseId $CaseId
} catch {
    Write-Check "Could not retrieve case $CaseId -- $($_.Exception.Message)" -Level FAIL
    exit 1
}
if ($case.DisplayName -eq $definition.case.displayName) {
    Write-Check "Case exists with expected DisplayName '$($case.DisplayName)'." -Level PASS
} else {
    Write-Check "Case $CaseId DisplayName is '$($case.DisplayName)', expected '$($definition.case.displayName)'." -Level WARN
}

# 2. Search
$search = Get-MgSecurityCaseEdiscoveryCaseSearch -EdiscoveryCaseId $CaseId -All |
    Where-Object { $_.DisplayName -eq $definition.search.displayName } | Select-Object -First 1
if ($search) {
    Write-Check "Search '$($definition.search.displayName)' exists (id=$($search.Id))." -Level PASS
    if ($search.ContentQuery -ne $definition.search.contentQuery) {
        Write-Check "Search contentQuery differs from the definition file (portal edit since deploy?). Current: '$($search.ContentQuery)'" -Level WARN
    }
} else {
    Write-Check "Search '$($definition.search.displayName)' not found." -Level FAIL
}

# 3. Bound target-mailbox sources
if ($search) {
    $boundSources = Get-MgSecurityCaseEdiscoveryCaseSearchNoncustodialSource -EdiscoveryCaseId $CaseId `
        -EdiscoverySearchId $search.Id -All
    Write-Host "Search has $($boundSources.Count) bound non-custodial source(s)."
    foreach ($target in $definition.search.targetMailboxes) {
        $match = $boundSources | Where-Object { $_.DisplayName -eq $target.email }
        if ($match) {
            Write-Check "Target mailbox '$($target.email)' ($($target.sourceType)) is bound to the search." -Level PASS
        } else {
            Write-Check "Target mailbox '$($target.email)' ($($target.sourceType)) has no matching bound source (matched on DisplayName -- see this script's .NOTES and design.md Section 6 VERIFY)." -Level WARN
        }
    }
}

$allOps = Get-MgSecurityCaseEdiscoveryCaseOperation -EdiscoveryCaseId $CaseId -All

# 4. Latest estimateStatistics
$estimateOps = $allOps | Where-Object {
    $_.AdditionalProperties['@odata.type'] -eq '#microsoft.graph.security.ediscoveryEstimateOperation'
} | Sort-Object CreatedDateTime -Descending

if ($estimateOps) {
    $latest = $estimateOps[0]
    Write-Check "Latest estimateStatistics ($($latest.CreatedDateTime)): status=$($latest.Status), indexedItemCount=$($latest.AdditionalProperties['indexedItemCount']), mailboxCount=$($latest.AdditionalProperties['mailboxCount'])." -Level WARN
} else {
    Write-Check 'No estimateStatistics operation found yet -- run New-TeamsMessagePurgeSearch.ps1 (not -SkipEstimate) before purging.' -Level WARN
}

# 5. purgeData operations (case-wide -- see Invoke-TeamsMessagePurge.ps1's own note on this
# same cross-search limitation).
$purgeOps = $allOps | Where-Object {
    $_.AdditionalProperties['@odata.type'] -eq '#microsoft.graph.security.ediscoveryPurgeDataOperation'
} | Sort-Object CreatedDateTime -Descending

if (-not $purgeOps) {
    Write-Check 'No purgeData operation found in this case yet -- the purge stage has not run. Not itself a failure of search/estimate validation.' -Level WARN
} else {
    Write-Host "Found $($purgeOps.Count) purgeData operation(s) in this case:"
    foreach ($op in $purgeOps) {
        Write-Host "  [$($op.CreatedDateTime)] id=$($op.Id) status=$($op.Status) percentProgress=$($op.PercentProgress)"
    }
    $latestPurge = $purgeOps[0]
    switch ($latestPurge.Status) {
        { $_ -in @('succeeded', 'partiallySucceeded') } {
            Write-Check "Most recent purgeData operation ($($latestPurge.Id)) status is '$($latestPurge.Status)'." -Level PASS
        }
        { $_ -in @('running', 'notStarted') } {
            Write-Check "Most recent purgeData operation ($($latestPurge.Id)) status is '$($latestPurge.Status)' -- still in progress. Re-check later." -Level WARN
        }
        default {
            Write-Check "Most recent purgeData operation ($($latestPurge.Id)) status is '$($latestPurge.Status)'. ResultInfo: $($latestPurge.ResultInfo | ConvertTo-Json -Compress -Depth 5)" -Level FAIL
        }
    }
}

Write-Host ''
Write-Host "Summary: $script:FailCount FAIL, $script:WarnCount WARN."
Write-Host 'Reminder: this script cannot confirm whether a target mailbox still had an active hold at purge time, or that removed holds were reapplied -- see .NOTES and README.md Section 5 steps 3/6.'
if ($script:FailCount -gt 0) { exit 1 } else { exit 0 }
```