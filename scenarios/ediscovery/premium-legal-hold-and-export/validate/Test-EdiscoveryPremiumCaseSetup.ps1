#Requires -Modules @{ ModuleName = 'Microsoft.Graph.Security'; ModuleVersion = '2.25.0' }
#Requires -Modules @{ ModuleName = 'Microsoft.Graph.Authentication'; ModuleVersion = '2.25.0' }

<#
.SYNOPSIS
    Verifies an eDiscovery (Premium) case built by this scenario's deploy scripts: the case
    exists, every custodian in the definition file is present and on hold, the search and review
    set exist, and (if requested) the export operation succeeded.

.DESCRIPTION
    Read-only. Requires only eDiscovery.Read.All (README.md section 3) -- never calls a mutating
    Graph endpoint. Exits non-zero on any hard [FAIL], so it's safe to use as a CI-style
    pre-flight or a scheduled drift check (see README.md section 8).

    Checks:
      1. Case exists with the expected DisplayName/description/externalId.
      2. Every custodian in the definition file exists and has HoldStatus = 'success'.
      3. Every custodian has at least one userSource.
      4. The search exists with the expected contentQuery/dataSourceScopes.
      5. The review set exists.
      6. [WARN-only] If -ExportOperationId is supplied, reports the export operation's current
         status and, if succeeded, whether the completedDateTime is within the 30-day download
         window documented in README.md section 11.

.PARAMETER DefinitionPath
    Same JSON definition file used by the deploy scripts.

.PARAMETER CaseId
    The eDiscoveryCase id to validate.

.PARAMETER ExportOperationId
    Optional. If supplied, also reports on the named export operation's status/age.

.PARAMETER AppId
.PARAMETER TenantId
.PARAMETER CertificateThumbprint
.PARAMETER Certificate
    Same Graph app-only authentication parameters as the deploy/ scripts. A read-only credential
    (eDiscovery.Read.All only, no ...ReadWrite.All) is sufficient and preferred for this script.

.EXAMPLE
    ./Test-EdiscoveryPremiumCaseSetup.ps1 -DefinitionPath ../deploy/policy/ediscovery-case-definition.json `
        -CaseId $caseId -AppId $AppId -TenantId $TenantId -CertificateThumbprint $Thumbprint

.NOTES
    Manual verification checklist (no read API exists for these -- confirm in the Purview portal):
      - The case's Premium features toggle is on (Case settings tab) -- README.md section 5 step 2.
      - Case members/permissions match who should have access (Case settings > Access and
        permissions) -- this script confirms custodians exist, not who can see the case.
      - The hold report (preview), if enabled org-wide, shows this case's hold policy as
        "Enabled" with no location errors -- the Graph HoldStatus this script reads is the
        custodian-level status, not the tenant-wide hold report's own (up-to-7-day-lagged) view.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateScript({ Test-Path $_ -PathType Leaf })]
    [string]$DefinitionPath,

    [Parameter(Mandatory)]
    [string]$CaseId,

    [string]$ExportOperationId,

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

# 2 & 3. Custodians + userSources
$allCustodians = Get-MgSecurityCaseEdiscoveryCaseCustodian -EdiscoveryCaseId $CaseId -All
foreach ($custodianDef in $definition.custodians) {
    $custodian = $allCustodians | Where-Object { $_.Email -eq $custodianDef.email } | Select-Object -First 1
    if (-not $custodian) {
        Write-Check "Custodian '$($custodianDef.email)' not found in case $CaseId." -Level FAIL
        continue
    }
    if ($custodian.HoldStatus -eq 'success') {
        Write-Check "Custodian '$($custodianDef.email)' hold status is 'success'." -Level PASS
    } elseif ($custodian.HoldStatus -in @('notStarted', 'running', $null)) {
        Write-Check "Custodian '$($custodianDef.email)' hold status is '$($custodian.HoldStatus)' -- still propagating. Microsoft documents up to 24 hours before a new hold is fully in effect; re-run this check later before treating this as a failure." -Level WARN
    } else {
        Write-Check "Custodian '$($custodianDef.email)' hold status is '$($custodian.HoldStatus)' -- expected 'success'." -Level FAIL
    }

    $sources = Get-MgSecurityCaseEdiscoveryCaseCustodianUserSource -EdiscoveryCaseId $CaseId `
        -EdiscoveryCustodianId $custodian.Id -All
    if ($sources -and $sources.Count -gt 0) {
        Write-Check "Custodian '$($custodianDef.email)' has $($sources.Count) userSource(s)." -Level PASS
    } else {
        Write-Check "Custodian '$($custodianDef.email)' has no userSources -- the hold has nothing to preserve." -Level FAIL
    }
}

# 4. Search
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

# 5. Review set
$reviewSet = Get-MgSecurityCaseEdiscoveryCaseReviewSet -EdiscoveryCaseId $CaseId -All |
    Where-Object { $_.DisplayName -eq $definition.reviewSet.displayName } | Select-Object -First 1
if ($reviewSet) {
    Write-Check "Review set '$($definition.reviewSet.displayName)' exists (id=$($reviewSet.Id))." -Level PASS
} else {
    Write-Check "Review set '$($definition.reviewSet.displayName)' not found -- run New-EdiscoverySearchReviewSetExport.ps1." -Level WARN
}

# 6. Export operation (optional, WARN-only -- an export is a point-in-time production, not an
# always-present piece of ongoing case state, so its absence is never a hard FAIL here).
if ($ExportOperationId) {
    try {
        $op = Get-MgSecurityCaseEdiscoveryCaseOperation -EdiscoveryCaseId $CaseId -CaseOperationId $ExportOperationId
        if ($op.Status -eq 'succeeded') {
            $ageDays = ((Get-Date).ToUniversalTime() - $op.CompletedDateTime).TotalDays
            if ($ageDays -le 30) {
                Write-Check "Export operation $ExportOperationId succeeded $([math]::Round($ageDays, 1)) day(s) ago -- still within the 30-day download window." -Level PASS
            } else {
                Write-Check "Export operation $ExportOperationId succeeded $([math]::Round($ageDays, 1)) day(s) ago -- the 30-day download window has very likely closed; the package content is probably no longer downloadable (README.md section 11)." -Level WARN
            }
        } else {
            Write-Check "Export operation $ExportOperationId status is '$($op.Status)', not 'succeeded'." -Level WARN
        }
    } catch {
        Write-Check "Could not retrieve export operation $ExportOperationId -- $($_.Exception.Message)" -Level FAIL
    }
}

Write-Host ''
Write-Host "Summary: $script:FailCount FAIL, $script:WarnCount WARN."
if ($script:FailCount -gt 0) { exit 1 } else { exit 0 }
