---
part: "validate"
parent: "dlp/accepted-domains-hygiene-check-on-premises"
---
Run these checks after deployment to confirm the control is working as designed.


#### `Test-OnPremisesAcceptedDomainsHygieneReport.ps1`

```powershell
#Requires -Version 5.1
<#
.SYNOPSIS
    Read-only integrity check for the on-premises accepted-domains hygiene baseline/drift-log files
    this scenario's deploy script produces, plus an optional live reconciliation against the current
    on-premises Get-AcceptedDomain state.

.DESCRIPTION
    Same two-category structure as the parent scenario's validate script
    (../../accepted-domains-hygiene-check/validate/Test-AcceptedDomainsHygieneReport.ps1):
      1. Report-file integrity (no Exchange call needed): the on-premises baseline file has the
         expected shape, the drift log has the expected columns, and there are no duplicate
         (RunId, Category, DomainName) rows - proof the deploy script's replace-by-RunId idempotency
         (design.md Sec 6) is holding.
      2. Live reconciliation (one on-premises Get-AcceptedDomain call, requires an active on-premises
         Exchange remote PowerShell session - README.md Sec 5, the same session the deploy script
         itself needs): confirms every live on-premises domain with a trust-conferring DomainType not
         present in the known-domains config is reflected as an UnexpectedTrustedDomain finding, and
         every required known domain absent from live on-premises state is reflected as a
         MissingExpectedDomain finding - both directions of the deploy script's core detection logic.
    Exits with a non-zero code if any hard check fails - safe to wire into a recurring scheduled check
    immediately after each on-premises deploy script run.

.PARAMETER BaselinePath
    Path to the on-premises baseline JSON file produced by
    deploy/Export-OnPremisesAcceptedDomainsHygieneReport.ps1.

.PARAMETER DriftLogPath
    Path to the on-premises drift-log CSV produced by the same deploy script.

.PARAMETER KnownDomainsConfigPath
    Path to the known-domains config (same file the parent scenario uses). Required only for the
    live-reconciliation check (2, above).

.PARAMETER CheckLive
    If set, additionally runs the live-reconciliation check (2, above). Requires an active on-premises
    Exchange remote PowerShell session and -KnownDomainsConfigPath. Omit for a context with no network
    access to the on-premises server (e.g. a CI job validating only that the previous run's files are
    well-formed).

.PARAMETER CloudBaselinePath
    Optional, -CheckLive only. Path to the parent scenario's own -BaselinePath output file. When
    supplied, additionally confirms every live on-premises/cloud-baseline disagreement on DomainType,
    MatchSubDomains, or Default (excluding ExternalRelay pairs, design.md Sec 4) is reflected as a
    finding under its own category (CrossEnvironmentMismatch / CrossEnvironmentMatchSubDomainsMismatch /
    CrossEnvironmentDefaultMismatch, design.md Sec 4/9) in the most recent drift-log run - the symmetric
    check for the deploy script's cross-environment logic, matching how checks 2's other two directions
    are already validated. Added after this build's own Blue Team review found the first draft
    validated the on-premises-only finding categories but had no way to confirm CrossEnvironmentMismatch
    wasn't silently under-reporting (reviews.md); extended to MatchSubDomains/Default as two sibling
    categories in a later build (design.md Sec 9).

.EXAMPLE
    ./Test-OnPremisesAcceptedDomainsHygieneReport.ps1 `
        -BaselinePath '../deploy/out/onprem-accepted-domains-baseline.json' `
        -DriftLogPath '../deploy/out/onprem-accepted-domains-drift-log.csv'

    File-integrity checks only.

.EXAMPLE
    # After New-PSSession -ConfigurationName Microsoft.Exchange ... ; Import-PSSession ...
    ./Test-OnPremisesAcceptedDomainsHygieneReport.ps1 `
        -BaselinePath '../deploy/out/onprem-accepted-domains-baseline.json' `
        -DriftLogPath '../deploy/out/onprem-accepted-domains-drift-log.csv' `
        -KnownDomainsConfigPath '../../accepted-domains-hygiene-check/deploy/KnownDomains.json' -CheckLive

    Full check: file integrity plus live reconciliation against current on-premises Get-AcceptedDomain
    state.

.EXAMPLE
    ./Test-OnPremisesAcceptedDomainsHygieneReport.ps1 `
        -BaselinePath '../deploy/out/onprem-accepted-domains-baseline.json' `
        -DriftLogPath '../deploy/out/onprem-accepted-domains-drift-log.csv' `
        -KnownDomainsConfigPath '../../accepted-domains-hygiene-check/deploy/KnownDomains.json' -CheckLive `
        -CloudBaselinePath '../../accepted-domains-hygiene-check/deploy/out/accepted-domains-baseline.json'

    Full check including cross-environment reconciliation: confirms any live on-premises/cloud-baseline
    DomainType, MatchSubDomains, or Default disagreement is reflected as a finding under the matching
    Cross-Environment-*Mismatch category.

.NOTES
    A [WARN] on the live domain-count reconciliation is not, by itself, proof of a bug - the same
    interpretation as the parent scenario's validate script: it is the expected signal immediately
    after any accepted-domain change and before the deploy script has been re-run to record it.

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
    [switch]$CheckLive,

    [Parameter()]
    [ValidateScript({ Test-Path $_ -PathType Leaf })]
    [string]$CloudBaselinePath
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
Write-Host "Checking on-premises baseline file integrity: $BaselinePath" -ForegroundColor Cyan
$baseline = Get-Content -Path $BaselinePath -Raw | ConvertFrom-Json

Test-Check -Description "Baseline has a non-empty 'runId'" -Condition (-not [string]::IsNullOrWhiteSpace($baseline.runId))
Test-Check -Description "Baseline has a non-empty 'runTimestampUtc'" -Condition (-not [string]::IsNullOrWhiteSpace($baseline.runTimestampUtc))
Test-Check -Description "Baseline is tagged environment 'on-premises'" -Condition ($baseline.environment -eq 'on-premises')
Test-Check -Description "Baseline has at least one domain entry" -Condition (@($baseline.domains).Count -gt 0)

$requiredDomainFields = 'DomainName', 'DomainType', 'Default', 'MatchSubDomains'
if (@($baseline.domains).Count -gt 0) {
    $actualFields = $baseline.domains[0].PSObject.Properties.Name
    foreach ($field in $requiredDomainFields) {
        Test-Check -Description "Baseline domain entries carry field '$field'" -Condition ($actualFields -contains $field)
    }
}

# --- 1b: drift-log file shape and idempotency ---
Write-Host "`nChecking on-premises drift-log file integrity: $DriftLogPath" -ForegroundColor Cyan
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

    $duplicateKeys = $driftRows | Group-Object { "$($_.RunId)|$($_.Category)|$($_.DomainName)" } | Where-Object { $_.Count -gt 1 }
    Test-Check -Description "No duplicate (RunId, Category, DomainName) rows in the drift log" -Condition ($duplicateKeys.Count -eq 0)
    if ($duplicateKeys.Count -gt 0) {
        Write-Host "         Duplicate keys: $($duplicateKeys.Name -join ', ')" -ForegroundColor Yellow
    }

    $validSeverities = 'INFO', 'WARN', 'FAIL'
    $invalidSeverityRows = $driftRows | Where-Object { $validSeverities -notcontains $_.Severity }
    Test-Check -Description "Every drift-log row has a recognized Severity (INFO/WARN/FAIL)" -Condition ($invalidSeverityRows.Count -eq 0)

    $validCategories = 'MissingExpectedDomain', 'DomainTypeMismatch', 'UnexpectedTrustedDomain', 'ExternalRelayObserved',
        'DomainAddedSincePreviousRun', 'DomainRemovedSincePreviousRun', 'DomainTypeChangedSincePreviousRun',
        'DefaultChangedSincePreviousRun', 'MatchSubDomainsChangedSincePreviousRun', 'CrossEnvironmentMismatch',
        'CrossEnvironmentMatchSubDomainsMismatch', 'CrossEnvironmentDefaultMismatch'
    $invalidCategoryRows = $driftRows | Where-Object { $validCategories -notcontains $_.Category }
    Test-Check -Description "Every drift-log row has a recognized Category" -Condition ($invalidCategoryRows.Count -eq 0)
}

# --- 2: optional live reconciliation ---
if ($CheckLive) {
    if (-not $KnownDomainsConfigPath) {
        throw '-CheckLive requires -KnownDomainsConfigPath.'
    }
    $acceptedDomainCommands = @(Get-Command Get-AcceptedDomain -All -ErrorAction SilentlyContinue)
    if ($acceptedDomainCommands.Count -eq 0) {
        throw 'No on-premises Exchange remote PowerShell session found. Import one first (README.md Sec 5), or omit -CheckLive to run file-integrity checks only.'
    }
    if ($acceptedDomainCommands.Count -gt 1) {
        Write-Warning "Multiple 'Get-AcceptedDomain' commands are loaded in this session - the Import-PSSession/Connect-ExchangeOnline name collision documented in design.md Sec 3. This check may silently reconcile against the WRONG environment. See the deploy script's own Assert-OnPremisesExchangeSession warning for the same detection logic and remediation."
    }

    Write-Host "`nReconciling on-premises baseline against live Get-AcceptedDomain state..." -ForegroundColor Cyan
    $liveDomains = @(Get-AcceptedDomain -ResultSize Unlimited)
    $liveCount = $liveDomains.Count
    $baselineCount = @($baseline.domains).Count

    Test-Check -Description "Live on-premises accepted-domain count ($liveCount) matches the baseline's recorded count ($baselineCount)" `
        -Condition ($liveCount -eq $baselineCount) -Warn

    $inOrganizationTypes = @('Authoritative', 'InternalRelay')
    $knownConfig = Get-Content -Path $KnownDomainsConfigPath -Raw | ConvertFrom-Json
    $knownDomainNames = @($knownConfig.knownDomains | ForEach-Object { $_.domainName.ToLowerInvariant() })

    $latestRunId = ($driftRows | Sort-Object RunId -Descending | Select-Object -First 1).RunId
    $latestUnexpectedTrusted = @($driftRows | Where-Object { $_.RunId -eq $latestRunId -and $_.Category -eq 'UnexpectedTrustedDomain' } | ForEach-Object { $_.DomainName.ToLowerInvariant() })
    $latestMissingExpected = @($driftRows | Where-Object { $_.RunId -eq $latestRunId -and $_.Category -eq 'MissingExpectedDomain' } | ForEach-Object { $_.DomainName.ToLowerInvariant() })
    $liveDomainNames = @($liveDomains | ForEach-Object { $_.DomainName.ToLowerInvariant() })

    foreach ($live in $liveDomains) {
        $key = $live.DomainName.ToLowerInvariant()
        if (($inOrganizationTypes -contains $live.DomainType) -and ($knownDomainNames -notcontains $key)) {
            Test-Check -Description "Live untrusted-but-accepted on-premises domain '$($live.DomainName)' (DomainType $($live.DomainType)) is reflected as an UnexpectedTrustedDomain finding in the most recent drift-log run ($latestRunId)" `
                -Condition ($latestUnexpectedTrusted -contains $key) -Warn
        }
    }

    foreach ($known in $knownConfig.knownDomains) {
        if (-not $known.required) { continue }
        $key = $known.domainName.ToLowerInvariant()
        if ($liveDomainNames -notcontains $key) {
            Test-Check -Description "Required known domain '$($known.domainName)', absent from live on-premises Get-AcceptedDomain, is reflected as a MissingExpectedDomain finding in the most recent drift-log run ($latestRunId)" `
                -Condition ($latestMissingExpected -contains $key) -Warn
        }
    }

    # Symmetric check for the cross-environment direction (design.md Sec 4) - confirms
    # CrossEnvironmentMismatch isn't silently under-reporting, the same proof-of-detection standard
    # applied to the two checks above (reviews.md, Blue Team finding).
    if ($CloudBaselinePath) {
        Write-Host "`nReconciling cross-environment mismatches against the cloud baseline: $CloudBaselinePath..." -ForegroundColor Cyan
        $cloud = Get-Content -Path $CloudBaselinePath -Raw | ConvertFrom-Json
        $cloudByDomain = @{}
        foreach ($entry in $cloud.domains) { $cloudByDomain[$entry.DomainName.ToLowerInvariant()] = $entry }
        # design.md Sec 4/9: three separate categories, one per checked field - not one overloaded
        # category - so a domain diverging on more than one field produces one row per category and
        # never collides on the drift log's (RunId, Category, DomainName) key. Reconciled independently
        # here, the same one-check-per-category pattern the rest of this block already uses.
        $latestDomainTypeMismatch = @($driftRows | Where-Object { $_.RunId -eq $latestRunId -and $_.Category -eq 'CrossEnvironmentMismatch' } | ForEach-Object { $_.DomainName.ToLowerInvariant() })
        $latestMatchSubDomainsMismatch = @($driftRows | Where-Object { $_.RunId -eq $latestRunId -and $_.Category -eq 'CrossEnvironmentMatchSubDomainsMismatch' } | ForEach-Object { $_.DomainName.ToLowerInvariant() })
        $latestDefaultMismatch = @($driftRows | Where-Object { $_.RunId -eq $latestRunId -and $_.Category -eq 'CrossEnvironmentDefaultMismatch' } | ForEach-Object { $_.DomainName.ToLowerInvariant() })

        foreach ($live in $liveDomains) {
            $key = $live.DomainName.ToLowerInvariant()
            $cloudEntry = $cloudByDomain[$key]
            if (-not $cloudEntry) { continue }
            if ($live.DomainType -eq 'ExternalRelay' -or $cloudEntry.DomainType -eq 'ExternalRelay') { continue }

            if ($live.DomainType -ne $cloudEntry.DomainType) {
                Test-Check -Description "Live on-premises/cloud-baseline DomainType disagreement for '$($live.DomainName)' (on-premises '$($live.DomainType)' vs. cloud baseline '$($cloudEntry.DomainType)') is reflected as a CrossEnvironmentMismatch finding in the most recent drift-log run ($latestRunId)" `
                    -Condition ($latestDomainTypeMismatch -contains $key) -Warn
            }
            if ($live.MatchSubDomains -ne $cloudEntry.MatchSubDomains) {
                Test-Check -Description "Live on-premises/cloud-baseline MatchSubDomains disagreement for '$($live.DomainName)' (on-premises '$($live.MatchSubDomains)' vs. cloud baseline '$($cloudEntry.MatchSubDomains)') is reflected as a CrossEnvironmentMatchSubDomainsMismatch finding in the most recent drift-log run ($latestRunId)" `
                    -Condition ($latestMatchSubDomainsMismatch -contains $key) -Warn
            }
            if ($live.Default -ne $cloudEntry.Default) {
                Test-Check -Description "Live on-premises/cloud-baseline Default disagreement for '$($live.DomainName)' (on-premises '$($live.Default)' vs. cloud baseline '$($cloudEntry.Default)') is reflected as a CrossEnvironmentDefaultMismatch finding in the most recent drift-log run ($latestRunId)" `
                    -Condition ($latestDefaultMismatch -contains $key) -Warn
            }
        }
    }
    else {
        Write-Host "`nSkipping cross-environment reconciliation check - pass -CloudBaselinePath to validate CrossEnvironmentMismatch findings against a live comparison." -ForegroundColor Yellow
    }
}
else {
    Write-Host "`nSkipping live reconciliation - pass -CheckLive (with -KnownDomainsConfigPath and an active on-premises Exchange remote session) to run it. File-integrity checks only." -ForegroundColor Yellow
}

Write-Host "`n$(if ($script:failures -eq 0) { 'All hard checks passed.' } else { "$script:failures hard check(s) failed." })" `
    -ForegroundColor $(if ($script:failures -eq 0) { 'Green' } else { 'Red' })

if ($script:failures -gt 0) { exit 1 }
```