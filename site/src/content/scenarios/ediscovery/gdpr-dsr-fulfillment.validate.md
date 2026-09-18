---
part: "validate"
parent: "ediscovery/gdpr-dsr-fulfillment"
---
Run these checks after deployment to confirm the control is working as designed.


#### `Test-DsrRequest.ps1`

```powershell
#Requires -Modules @{ ModuleName = 'Microsoft.Graph.Security'; ModuleVersion = '2.25.0' }
#Requires -Modules @{ ModuleName = 'Microsoft.Graph.Authentication'; ModuleVersion = '2.25.0' }

<#
.SYNOPSIS
    Reports the Article 12(3) SLA status of every request in the DSR ledger (or one named
    -RequestId), and confirms the underlying eDiscovery case/custodian/search still exist.

.DESCRIPTION
    Read-only. Requires only eDiscovery.Read.All (README.md Section 3) -- never calls a mutating
    Graph endpoint. Exits non-zero if any non-closed request is Overdue (past dueDate without an
    applied extension, or past maxExtendedDueDate regardless), so it's safe to run on a schedule
    as an SLA-breach check.

    For each ledger entry not already Status 'Closed':
      1. SLA status from today's date vs. dueDate/maxExtendedDueDate/extensionApplied:
         [FAIL] Overdue, [WARN] DueSoon (<=7 days remaining) or Status still 'Discovery' with the
         due date already close, [PASS] OnTrack.
      2. Case/custodian/search existence (Graph read).
      3. Request-type-specific fulfillment signal (best-effort, WARN-only -- this script cannot see
         work done entirely outside this scenario's scripts):
         - Access/Portability: whether a review set exists in the case (premium-legal-hold-and-export
           object model).
         - Erasure: whether a purgeData operation exists in the case, and its status.
         - Rectification/Restriction/Objection: no technical fulfillment signal exists --
           reminds the operator this is a manual process step (README.md Section 6).

.PARAMETER LedgerPath
    Path to the ledger JSON file written by deploy/New-DsrRequest.ps1. Defaults to
    ../deploy/dsr-ledger.json relative to this script.

.PARAMETER RequestId
    Check only this request. Default: check every non-Closed entry in the ledger.

.PARAMETER AppId
.PARAMETER TenantId
.PARAMETER CertificateThumbprint
.PARAMETER Certificate
    Same Graph app-only authentication parameters as the deploy/ script. A read-only credential
    (eDiscovery.Read.All only, no ...ReadWrite.All) is sufficient and preferred for this script.

.EXAMPLE
    ./Test-DsrRequest.ps1 -AppId $AppId -TenantId $TenantId -CertificateThumbprint $Thumbprint

    Reports SLA status for every open request in the ledger; exits non-zero if any is overdue.

.NOTES
    SLA math is calendar-month arithmetic against today's date at the time this script runs --
    it does not account for the organization's own internal escalation buffer (e.g. "flag 5
    business days before the legal deadline"); adjust -WarnDaysBeforeDue if you want an earlier
    WARN threshold than the 7-day default.
#>
[CmdletBinding()]
param(
    [string]$LedgerPath = (Join-Path $PSScriptRoot '../deploy/dsr-ledger.json'),

    [string]$RequestId,

    [Parameter(Mandatory)]
    [string]$AppId,

    [Parameter(Mandatory)]
    [string]$TenantId,

    [Parameter(ParameterSetName = 'Thumbprint')]
    [string]$CertificateThumbprint,

    [Parameter(ParameterSetName = 'CertObject')]
    [System.Security.Cryptography.X509Certificates.X509Certificate2]$Certificate,

    [int]$WarnDaysBeforeDue = 7
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

if (-not (Test-Path $LedgerPath)) {
    Write-Check "Ledger not found at $LedgerPath -- run deploy/New-DsrRequest.ps1 first." -Level FAIL
    exit 1
}
$ledger = @(Get-Content -Path $LedgerPath -Raw | ConvertFrom-Json)
if ($RequestId) {
    $ledger = @($ledger | Where-Object { $_.requestId -eq $RequestId })
    if (-not $ledger) {
        Write-Check "No ledger entry found for requestId '$RequestId'." -Level FAIL
        exit 1
    }
} else {
    $ledger = @($ledger | Where-Object { $_.status -ne 'Closed' })
}

if (-not $ledger) {
    Write-Host 'No open (non-Closed) requests in the ledger.'
    exit 0
}

if (Get-MgContext) {
    Write-Verbose 'Reusing existing Microsoft Graph connection.'
} else {
    $connectParams = @{ ClientId = $AppId; TenantId = $TenantId; NoWelcome = $true }
    if ($Certificate) { $connectParams['Certificate'] = $Certificate }
    else { $connectParams['CertificateThumbprint'] = $CertificateThumbprint }
    Connect-MgGraph @connectParams
}

$today = Get-Date

foreach ($entry in $ledger) {
    Write-Host ''
    Write-Host "=== $($entry.requestId) ($($entry.requestType)) -- status: $($entry.status) ==="

    # 1. SLA status
    $dueDate = [datetime]::ParseExact($entry.dueDate, 'yyyy-MM-dd', $null)
    $maxDueDate = [datetime]::ParseExact($entry.maxExtendedDueDate, 'yyyy-MM-dd', $null)
    $effectiveDue = if ($entry.extensionApplied) { $maxDueDate } else { $dueDate }
    $daysRemaining = [math]::Ceiling(($effectiveDue - $today).TotalDays)

    if ($today -gt $effectiveDue) {
        Write-Check "Overdue by $([math]::Abs($daysRemaining)) day(s) against $(if ($entry.extensionApplied) { 'the extended (3-month)' } else { 'the 1-month' }) Article 12(3) deadline ($($effectiveDue.ToString('yyyy-MM-dd')))." -Level FAIL
    } elseif (-not $entry.extensionApplied -and $today -gt $dueDate.AddDays(-$WarnDaysBeforeDue) -and $today -le $dueDate) {
        Write-Check "$daysRemaining day(s) remaining before the 1-month deadline ($($dueDate.ToString('yyyy-MM-dd'))). Extend now (-ApplyExtension) and notify the data subject if this won't be fulfilled in time -- Article 12(3) requires that notice within the original month." -Level WARN
    } elseif ($daysRemaining -le $WarnDaysBeforeDue) {
        Write-Check "$daysRemaining day(s) remaining before $(if ($entry.extensionApplied) { 'the extended' } else { 'the' }) deadline ($($effectiveDue.ToString('yyyy-MM-dd')))." -Level WARN
    } else {
        Write-Check "On track -- $daysRemaining day(s) remaining before $(if ($entry.extensionApplied) { 'the extended' } else { 'the' }) deadline ($($effectiveDue.ToString('yyyy-MM-dd')))." -Level PASS
    }

    # 2. Case/custodian/search existence
    try {
        $case = Get-MgSecurityCaseEdiscoveryCase -EdiscoveryCaseId $entry.caseId
        Write-Check "Case '$($case.DisplayName)' exists (id=$($case.Id))." -Level PASS
    } catch {
        Write-Check "Could not retrieve case $($entry.caseId) -- $($_.Exception.Message)" -Level FAIL
        continue
    }
    try {
        $custodian = Get-MgSecurityCaseEdiscoveryCaseCustodian -EdiscoveryCaseId $entry.caseId -EdiscoveryCustodianId $entry.custodianId
        Write-Check "Custodian '$($custodian.Email)' exists (id=$($custodian.Id))." -Level PASS
    } catch {
        Write-Check "Could not retrieve custodian $($entry.custodianId) -- $($_.Exception.Message)" -Level FAIL
    }
    try {
        Get-MgSecurityCaseEdiscoveryCaseSearch -EdiscoveryCaseId $entry.caseId -EdiscoverySearchId $entry.searchId | Out-Null
        Write-Check 'Search exists.' -Level PASS
    } catch {
        Write-Check "Could not retrieve search $($entry.searchId) -- $($_.Exception.Message)" -Level FAIL
    }
    if ($entry.PSObject.Properties.Name -contains 'participantSearchId' -and $entry.participantSearchId) {
        try {
            Get-MgSecurityCaseEdiscoveryCaseSearch -EdiscoveryCaseId $entry.caseId -EdiscoverySearchId $entry.participantSearchId | Out-Null
            Write-Check 'Tenant-wide participant search exists -- confirm its results were reviewed before inclusion in fulfillment.' -Level PASS
        } catch {
            Write-Check "Could not retrieve participant search $($entry.participantSearchId) -- $($_.Exception.Message)" -Level FAIL
        }
    }

    # 3. Request-type-specific fulfillment signal (best-effort)
    switch ($entry.requestType) {
        { $_ -in @('Access', 'Portability') } {
            $reviewSets = Get-MgSecurityCaseEdiscoveryCaseReviewSet -EdiscoveryCaseId $entry.caseId -All
            if ($reviewSets) {
                Write-Check "$($reviewSets.Count) review set(s) found -- Access/Portability fulfillment appears underway or complete. Confirm export/download separately (premium-legal-hold-and-export/validate)." -Level WARN
            } else {
                Write-Check 'No review set found yet -- Access/Portability fulfillment (README.md Section 5 hand-off) has not started.' -Level WARN
            }
        }
        'Erasure' {
            $ops = Get-MgSecurityCaseEdiscoveryCaseOperation -EdiscoveryCaseId $entry.caseId -All |
                Where-Object { $_.AdditionalProperties['@odata.type'] -eq '#microsoft.graph.security.ediscoveryPurgeDataOperation' } |
                Sort-Object CreatedDateTime -Descending
            if ($ops) {
                Write-Check "Most recent purgeData operation status: $($ops[0].Status)." -Level WARN
            } else {
                Write-Check 'No purgeData operation found yet -- Erasure fulfillment (README.md Section 5 hand-off) has not started.' -Level WARN
            }
        }
        default {
            Write-Check "$($entry.requestType) has no technical fulfillment signal in Purview -- confirm fulfillment status against the organization's own process record (README.md Section 6)." -Level WARN
        }
    }
}

Write-Host ''
Write-Host "Summary: $script:FailCount FAIL, $script:WarnCount WARN."
if ($script:FailCount -gt 0) { exit 1 } else { exit 0 }
```