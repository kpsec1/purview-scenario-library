---
part: "validate"
parent: "dlp/accepted-domains-hygiene-check"
---
Run these checks after deployment to confirm the control is working as designed.


#### `Test-AcceptedDomainsHygieneReport.ps1`

```powershell
#Requires -Version 7.0
<#
.SYNOPSIS
    Read-only integrity check for the accepted-domains hygiene baseline/drift-log files this
    scenario's deploy script produces, plus an optional live reconciliation against the current
    Get-AcceptedDomain state.

.DESCRIPTION
    Two categories of check, both read-only:
      1. Report-file integrity (no Exchange Online call needed): the baseline file has the expected
         shape (runId, runTimestampUtc, domains array with DomainName/DomainType/Default/
         MatchSubDomains on every entry), the drift log has the expected columns, and there are no
         duplicate (RunId, Category, DomainName) rows in the drift log - proof the deploy script's
         replace-by-RunId idempotency (design.md Sec 4) is actually holding, not silently
         duplicating on every re-run.
      2. Live reconciliation (one Get-AcceptedDomain call, requires an active Exchange Online
         PowerShell session - Connect-ExchangeOnline, same session the deploy script itself needs):
         confirms the baseline file's most recent snapshot still matches the live domain count, that
         every live domain with a trust-conferring DomainType (Authoritative/InternalRelay, design.md
         Sec 2) not present in the known-domains config is reflected as an UnexpectedTrustedDomain
         finding, and that every required known domain absent from live state is reflected as a
         MissingExpectedDomain finding - both directions of the deploy script's core detection logic
         (README.md Sec 3), the concrete proof it is not silently under-reporting either direction.
    Exits with a non-zero code if any hard check fails - safe to wire into a recurring scheduled
    check immediately after each deploy script run, the same pattern this repo's other validate/
    scripts use.

.PARAMETER BaselinePath
    Path to the baseline JSON file produced by deploy/Export-AcceptedDomainsHygieneReport.ps1.

.PARAMETER DriftLogPath
    Path to the drift-log CSV produced by deploy/Export-AcceptedDomainsHygieneReport.ps1.

.PARAMETER KnownDomainsConfigPath
    Path to the known-domains config (deploy/KnownDomains.sample.json schema). Required only for the
    live-reconciliation check (2, above) - omit together with -CheckLive to run the file-integrity
    checks (1) only.

.PARAMETER CheckLive
    If set, additionally runs the live-reconciliation check (2, above). Requires an active
    Connect-ExchangeOnline session and -KnownDomainsConfigPath. Omit for a context with no network
    access to the tenant (e.g. a CI job validating only that the previous run's files are well-formed).

.EXAMPLE
    ./Test-AcceptedDomainsHygieneReport.ps1 -BaselinePath '../deploy/out/accepted-domains-baseline.json' `
        -DriftLogPath '../deploy/out/accepted-domains-drift-log.csv'

    File-integrity checks only - confirms the baseline/drift-log files' own shape and idempotency,
    without a live Get-AcceptedDomain call.

.EXAMPLE
    Connect-ExchangeOnline -AppId $AppId -Certificate $Cert -Organization $TenantDomain
    ./Test-AcceptedDomainsHygieneReport.ps1 -BaselinePath '../deploy/out/accepted-domains-baseline.json' `
        -DriftLogPath '../deploy/out/accepted-domains-drift-log.csv' `
        -KnownDomainsConfigPath '../deploy/KnownDomains.json' -CheckLive

    Full check: file integrity plus live reconciliation against current Get-AcceptedDomain state.

.NOTES
    A [WARN] on the live domain-count reconciliation is not, by itself, proof of a bug - it is the
    expected signal immediately after any accepted-domain change and before the deploy script has
    been re-run to record it. Re-run deploy/Export-AcceptedDomainsHygieneReport.ps1 and re-check; a
    [WARN] that persists after re-export deserves investigation, one that clears does not.

    Sources (Microsoft Learn, verify before production use):
    - Get-AcceptedDomain reference: https://learn.microsoft.com/powershell/module/exchangepowershell/get-accepteddomain
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateScript({ Test-Path $_ -PathType Leaf })]
    [string]$BaselinePath,

    [Parameter(Mandatory)]
    [ValidateScript({ Test-Path $_ -PathType Leaf })]
    [string]$DriftLogPath,

    [Parameter()]
    [string]$KnownDomainsConfigPath,

    [Parameter()]
    [switch]$CheckLive
)

$ErrorActionPreference = 'Stop'
$script:failures = 0

function Test-Check {
    param([string]$Description, [bool]$Condition, [switch]$Warn)
    if ($Condition) {
        Write-Host "  [PASS] $Description" -ForegroundColor Green
    }
    elseif ($Warn) {
        Write-Host "  [WARN] $Description" -ForegroundColor Yellow
    }
    else {
        Write-Host "  [FAIL] $Description" -ForegroundColor Red
        $script:failures++
    }
}

# --- 1a: baseline file shape ---
Write-Host "Checking baseline file integrity: $BaselinePath" -ForegroundColor Cyan
$baseline = Get-Content -Path $BaselinePath -Raw | ConvertFrom-Json

Test-Check -Description "Baseline has a non-empty 'runId'" -Condition (-not [string]::IsNullOrWhiteSpace($baseline.runId))
Test-Check -Description "Baseline has a non-empty 'runTimestampUtc'" -Condition (-not [string]::IsNullOrWhiteSpace($baseline.runTimestampUtc))
Test-Check -Description "Baseline has at least one domain entry" -Condition (@($baseline.domains).Count -gt 0)

$requiredDomainFields = 'DomainName', 'DomainType', 'Default', 'MatchSubDomains'
if (@($baseline.domains).Count -gt 0) {
    $actualFields = $baseline.domains[0].PSObject.Properties.Name
    foreach ($field in $requiredDomainFields) {
        Test-Check -Description "Baseline domain entries carry field '$field'" -Condition ($actualFields -contains $field)
    }
}

# --- 1b: drift-log file shape and idempotency ---
Write-Host "`nChecking drift-log file integrity: $DriftLogPath" -ForegroundColor Cyan
$driftRows = @(Import-Csv -Path $DriftLogPath)

if ($driftRows.Count -eq 0) {
    Write-Host "  Drift log has no rows yet - this is valid (no findings have ever been recorded), skipping row-shape checks." -ForegroundColor Yellow
}
else {
    $requiredColumns = 'RunId', 'Category', 'Severity', 'DomainName', 'Detail'
    $actualColumns = $driftRows[0].PSObject.Properties.Name
    foreach ($column in $requiredColumns) {
        Test-Check -Description "Drift log has column '$column'" -Condition ($actualColumns -contains $column)
    }

    # No duplicate (RunId, Category, DomainName) rows: proof the deploy script's replace-by-RunId
    # idempotency (design.md Sec 4) is actually holding, not silently appending on every re-run.
    $duplicateKeys = $driftRows | Group-Object { "$($_.RunId)|$($_.Category)|$($_.DomainName)" } | Where-Object { $_.Count -gt 1 }
    Test-Check -Description "No duplicate (RunId, Category, DomainName) rows in the drift log" -Condition ($duplicateKeys.Count -eq 0)
    if ($duplicateKeys.Count -gt 0) {
        Write-Host "         Duplicate keys: $($duplicateKeys.Name -join ', ')" -ForegroundColor Yellow
    }

    $validSeverities = 'INFO', 'WARN', 'FAIL'
    $invalidSeverityRows = $driftRows | Where-Object { $validSeverities -notcontains $_.Severity }
    Test-Check -Description "Every drift-log row has a recognized Severity (INFO/WARN/FAIL)" -Condition ($invalidSeverityRows.Count -eq 0)
}

# --- 2: optional live reconciliation ---
if ($CheckLive) {
    if (-not $KnownDomainsConfigPath) {
        throw '-CheckLive requires -KnownDomainsConfigPath.'
    }
    if (-not (Get-Command Get-AcceptedDomain -ErrorAction SilentlyContinue)) {
        throw 'No Exchange Online PowerShell session found. Run Connect-ExchangeOnline first, or omit -CheckLive to run file-integrity checks only.'
    }

    Write-Host "`nReconciling baseline against live Get-AcceptedDomain state..." -ForegroundColor Cyan
    $liveDomains = @(Get-AcceptedDomain -ResultSize Unlimited)
    $liveCount = $liveDomains.Count
    $baselineCount = @($baseline.domains).Count

    Test-Check -Description "Live accepted-domain count ($liveCount) matches the baseline's recorded count ($baselineCount)" `
        -Condition ($liveCount -eq $baselineCount) -Warn

    $inOrganizationTypes = @('Authoritative', 'InternalRelay')
    $knownConfig = Get-Content -Path $KnownDomainsConfigPath -Raw | ConvertFrom-Json
    $knownDomainNames = @($knownConfig.knownDomains | ForEach-Object { $_.domainName.ToLowerInvariant() })

    $latestRunId = ($driftRows | Sort-Object RunId -Descending | Select-Object -First 1).RunId
    $latestUnexpectedTrusted = @($driftRows | Where-Object { $_.RunId -eq $latestRunId -and $_.Category -eq 'UnexpectedTrustedDomain' } | ForEach-Object { $_.DomainName.ToLowerInvariant() })
    $latestMissingExpected = @($driftRows | Where-Object { $_.RunId -eq $latestRunId -and $_.Category -eq 'MissingExpectedDomain' } | ForEach-Object { $_.DomainName.ToLowerInvariant() })
    $liveDomainNames = @($liveDomains | ForEach-Object { $_.DomainName.ToLowerInvariant() })

    # Silent-bypass direction: every live in-organization domain missing from the known-domains
    # config is reflected as an UnexpectedTrustedDomain finding.
    foreach ($live in $liveDomains) {
        $key = $live.DomainName.ToLowerInvariant()
        if (($inOrganizationTypes -contains $live.DomainType) -and ($knownDomainNames -notcontains $key)) {
            Test-Check -Description "Live untrusted-but-accepted domain '$($live.DomainName)' (DomainType $($live.DomainType)) is reflected as an UnexpectedTrustedDomain finding in the most recent drift-log run ($latestRunId)" `
                -Condition ($latestUnexpectedTrusted -contains $key) -Warn
        }
    }

    # False-positive-exclusion direction: every required known domain absent from live
    # Get-AcceptedDomain is reflected as a MissingExpectedDomain finding.
    foreach ($known in $knownConfig.knownDomains) {
        if (-not $known.required) { continue }
        $key = $known.domainName.ToLowerInvariant()
        if ($liveDomainNames -notcontains $key) {
            Test-Check -Description "Required known domain '$($known.domainName)', absent from live Get-AcceptedDomain, is reflected as a MissingExpectedDomain finding in the most recent drift-log run ($latestRunId)" `
                -Condition ($latestMissingExpected -contains $key) -Warn
        }
    }
}
else {
    Write-Host "`nSkipping live reconciliation - pass -CheckLive (with -KnownDomainsConfigPath and an active Connect-ExchangeOnline session) to run it. File-integrity checks only." -ForegroundColor Yellow
}

Write-Host "`n$(if ($script:failures -eq 0) { 'All hard checks passed.' } else { "$script:failures hard check(s) failed." })" `
    -ForegroundColor $(if ($script:failures -eq 0) { 'Green' } else { 'Red' })

if ($script:failures -gt 0) { exit 1 }
```