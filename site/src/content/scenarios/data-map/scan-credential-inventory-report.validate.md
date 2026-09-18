---
part: "validate"
parent: "data-map/scan-credential-inventory-report"
---
Run these checks after deployment to confirm the control is working as designed.


#### `Test-CredentialInventoryReport.ps1`

```powershell
#Requires -Version 7.0
<#
.SYNOPSIS
    Read-only integrity check for the credential-inventory trend log and drift-report files this
    scenario's deploy script produces - confirms the report's own internal consistency, and
    independently re-derives the current live count to confirm the exported report isn't stale.

.DESCRIPTION
    Two categories of check, both read-only (Data Reader role, same as the deploy script - no
    additional privilege needed):
      1. Report-file integrity (no Purview call needed): the trend log has the expected columns, no
         duplicate RunId+Name rows (proof this scenario's replace-by-RunId idempotency design is
         actually holding), and every 'Drift'/'Missing' status row in the trend log has a
         MismatchCount greater than zero (and every 'Match' row has zero) - catching a report whose
         summary status and mismatch count have silently disagreed.
      2. Live reconciliation (one Credential - List call): re-fetches the current credential count
         and name set and confirms the most recent run's row count is still consistent with it - a
         drift here means the report is stale (a credential was added/removed since the last
         export), not wrong, which is a different remediation (re-run the export) than an actual bug.
      3. Drift-report gate (no Purview call needed, if -FailOnDrift/-FailOnUntracked is set): fails
         the run if the most recent run's drift-report JSON contains any 'Drift'/'Missing' status
         credential (-FailOnDrift) or any 'NotTracked' status credential (-FailOnUntracked) - the
         check a CI/scheduled pipeline should gate deployment or alerting on. The two switches are
         independent because they answer different questions: -FailOnDrift asks "did a TRACKED
         credential change unexpectedly", -FailOnUntracked asks "does a credential exist that was
         never reviewed and added to the expected state at all" - see .PARAMETER FailOnUntracked.
    Exits with a non-zero code if any hard check fails - safe to wire into a recurring scheduled
    check or a CI pipeline gate, the same pattern this repo's other validate/ scripts use.

.PARAMETER TrendLogPath
    Path to the trend-log CSV produced by deploy/Export-CredentialInventoryReport.ps1.

.PARAMETER DriftReportDirectory
    Directory containing the per-run drift-report JSON files. Required only for the -FailOnDrift
    gate (check 3) and to look up the most recent run's full mismatch detail.

.PARAMETER FailOnDrift
    If set, treats any 'Drift' or 'Missing' status credential in the most recent run's drift report
    as a hard [FAIL] rather than reporting it informationally. Off by default so this script can be
    run purely as a file-integrity check without requiring a fully reconciled inventory yet.

.PARAMETER FailOnUntracked
    If set, ALSO treats any 'NotTracked' status credential (one that exists live but has no
    matching entry in the expected-state file) as a hard [FAIL]. Off by default, because a
    'NotTracked' credential is the expected, benign state right after legitimate onboarding of a
    new data source before the expected-state file is updated to match - see README.md Section 6.
    Without this switch, -FailOnDrift alone does NOT catch a wholly new, unauthorized credential
    (one that was never a re-point of an existing tracked credential) - it will only ever show as
    'NotTracked', not 'Drift', so it passes silently. Set -FailOnUntracked in any environment where
    credential creation is tightly controlled and rare enough that EVERY new credential should be a
    reviewed, deliberate addition to the expected-state file before it is considered acceptable -
    see README.md Section 11's Red Team finding on this exact gap.

.PARAMETER PurviewAccountName
    The Purview account name. Required only for the live-reconciliation check (2, above) - omit
    together with the auth parameters to run the file-integrity checks (1, 3) only, e.g. in a
    context with no network access to the tenant.

.PARAMETER TenantId
    Microsoft Entra tenant ID. Required only for the live-reconciliation check.

.PARAMETER AppId
    Application (client) ID of a service principal holding at least the Data Reader role on the
    collection(s) in scope. Required only for the live-reconciliation check.

.PARAMETER ClientSecret
    Client secret for -AppId, as a SecureString. Required only for the live-reconciliation check.

.PARAMETER ApiVersion
    Purview Scanning data-plane REST API version to pin. Defaults to '2023-09-01'.

.EXAMPLE
    ./Test-CredentialInventoryReport.ps1 -TrendLogPath '../deploy/out/credential-inventory-trend.csv' `
        -DriftReportDirectory '../deploy/out/drift-reports' -FailOnDrift

    File-integrity and drift-gate checks only (no tenant credentials supplied) - fails non-zero if
    the most recent run recorded any drifted or missing credential.

.EXAMPLE
    ./Test-CredentialInventoryReport.ps1 -TrendLogPath '../deploy/out/credential-inventory-trend.csv' `
        -DriftReportDirectory '../deploy/out/drift-reports' -FailOnDrift `
        -PurviewAccountName 'contoso-purview' -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret

    Full check: file integrity, drift gate, plus a live reconciliation of the most recent run's
    credential count/name set against the current tenant state.

.NOTES
    A [WARN] on live-reconciliation drift is not, by itself, proof of a bug - it is the expected
    signal after any credential was legitimately added or removed since the last report run. Re-run
    deploy/Export-CredentialInventoryReport.ps1 and re-check; a [WARN] that persists after re-export
    deserves investigation, one that clears does not. A [FAIL] from -FailOnDrift is different: it
    means a TRACKED credential's own fingerprint no longer matches its checked-in expected state -
    see README.md Section 8's runbook, since this is the specific detective control this scenario
    exists to provide for the silent-re-point risk.

    Sources (Microsoft Learn, verify before production use):
    - Credential - List REST reference (API version 2023-09-01):
      https://learn.microsoft.com/rest/api/purview/scanningdataplane/credential/list
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateScript({ Test-Path $_ -PathType Leaf })]
    [string]$TrendLogPath,

    [Parameter()]
    [string]$DriftReportDirectory,

    [Parameter()]
    [switch]$FailOnDrift,

    [Parameter()]
    [switch]$FailOnUntracked,

    [Parameter()]
    [string]$PurviewAccountName,

    [Parameter()]
    [string]$TenantId,

    [Parameter()]
    [string]$AppId,

    [Parameter()]
    [SecureString]$ClientSecret,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$ApiVersion = '2023-09-01'
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

Write-Host "Checking trend-log file integrity: $TrendLogPath" -ForegroundColor Cyan
$rows = @(Import-Csv -Path $TrendLogPath)

Test-Check -Description "Trend log has at least one row" -Condition ($rows.Count -gt 0)
if ($rows.Count -eq 0) {
    Write-Host "`nCannot continue - no rows to validate." -ForegroundColor Red
    exit 1
}

$requiredColumns = 'RunId', 'RunTimestampUtc', 'Name', 'Kind', 'Status', 'MismatchCount'
$actualColumns = $rows[0].PSObject.Properties.Name
foreach ($column in $requiredColumns) {
    Test-Check -Description "Column '$column' present" -Condition ($actualColumns -contains $column)
}

# --- No duplicate RunId+Name rows: proof the deploy script's replace-by-RunId idempotency design
# (design.md Section 5) is actually holding, not silently appending on every re-run.
$duplicateKeys = $rows | Group-Object { "$($_.RunId)|$($_.Name)" } | Where-Object { $_.Count -gt 1 }
Test-Check -Description "No duplicate (RunId, Name) rows in the trend log" -Condition ($duplicateKeys.Count -eq 0)
if ($duplicateKeys.Count -gt 0) {
    Write-Host "         Duplicate keys: $($duplicateKeys.Name -join ', ')" -ForegroundColor Yellow
}

# --- Status/MismatchCount internal consistency ---
foreach ($row in $rows) {
    $mismatchCount = [int]$row.MismatchCount
    $consistent = switch ($row.Status) {
        'Match'      { $mismatchCount -eq 0 }
        'NotTracked' { $mismatchCount -eq 0 }
        default      { $mismatchCount -gt 0 }   # Drift, Missing
    }
    Test-Check -Description "[$($row.RunId)/$($row.Name)] Status '$($row.Status)' is consistent with MismatchCount ($mismatchCount)" -Condition $consistent
}

# --- Drift gate: fail the run if the most recent run recorded any Drift/Missing credential ---
if ($DriftReportDirectory -and (Test-Path -Path $DriftReportDirectory -PathType Container)) {
    $latestRunId = ($rows | Sort-Object RunId -Descending | Select-Object -First 1).RunId
    $reportPath = Join-Path $DriftReportDirectory "$latestRunId-credential-inventory-drift.json"
    if (Test-Path -Path $reportPath -PathType Leaf) {
        $latestReport = Get-Content -Path $reportPath -Raw | ConvertFrom-Json -Depth 10
        $drifted = @($latestReport | Where-Object { $_.Status -in 'Drift', 'Missing' })
        Write-Host "`nChecking most recent run ('$latestRunId') drift report: $reportPath" -ForegroundColor Cyan
        Test-Check -Description "No 'Drift' or 'Missing' status credential in the most recent run" `
            -Condition ($drifted.Count -eq 0) -Warn:(-not $FailOnDrift)
        foreach ($item in $drifted) {
            Write-Host "         $($item.Name) ($($item.Kind)): $($item.MismatchCount) mismatch(es)" -ForegroundColor Yellow
            foreach ($mismatch in $item.Mismatches) {
                Write-Host "           - $($mismatch.Field): expected '$($mismatch.Expected)', actual '$($mismatch.Actual)'" -ForegroundColor Yellow
            }
        }

        # -FailOnDrift alone does NOT catch a wholly new, unauthorized credential - one that is not
        # a re-point of an already-tracked credential shows only as 'NotTracked', never 'Drift'.
        # See README.md Section 11's Red Team finding and .PARAMETER FailOnUntracked above.
        $untracked = @($latestReport | Where-Object { $_.Status -eq 'NotTracked' })
        Test-Check -Description "No 'NotTracked' (unreviewed, not-yet-approved) credential in the most recent run" `
            -Condition ($untracked.Count -eq 0) -Warn:(-not $FailOnUntracked)
        foreach ($item in $untracked) {
            Write-Host "         $($item.Name) ($($item.Kind)): exists live but has no expected-state entry" -ForegroundColor Yellow
        }
    }
    else {
        Write-Warning "Drift report for the most recent run ('$latestRunId') was not found at '$reportPath' - skipping the drift gate."
    }
}
elseif ($FailOnDrift -or $FailOnUntracked) {
    Write-Warning "-FailOnDrift/-FailOnUntracked was set but -DriftReportDirectory was not supplied or does not exist - the drift gate cannot run."
}

# --- Optional live reconciliation against the most recent run ---
if ($PurviewAccountName -and $TenantId -and $AppId -and $ClientSecret) {
    Write-Host "`nReconciling the most recent run against live Credential - List data..." -ForegroundColor Cyan

    function ConvertTo-PlainText {
        param([Parameter(Mandatory)][SecureString]$Secure)
        $ptr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($Secure)
        try { return [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($ptr) }
        finally { [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr) }
    }

    function Get-PurviewAccessToken {
        param(
            [Parameter(Mandatory)][string]$TenantId,
            [Parameter(Mandatory)][string]$AppId,
            [Parameter(Mandatory)][string]$PlainSecret
        )
        $body = @{
            client_id     = $AppId
            client_secret = $PlainSecret
            grant_type    = 'client_credentials'
            resource      = 'https://purview.azure.net'
        }
        $response = Invoke-RestMethod -Method Post `
            -Uri "https://login.microsoftonline.com/$TenantId/oauth2/token" -Body $body
        return $response.access_token
    }

    $plainSecret = ConvertTo-PlainText -Secure $ClientSecret
    try {
        $token = Get-PurviewAccessToken -TenantId $TenantId -AppId $AppId -PlainSecret $plainSecret
    }
    finally {
        $plainSecret = $null
    }

    $endpoint = "https://$PurviewAccountName.purview.azure.com"
    $liveNames = @()
    $uri = "$endpoint/scan/credentials?api-version=$ApiVersion"
    do {
        $response = Invoke-RestMethod -Method Get -Uri $uri -Headers @{ Authorization = "Bearer $token" }
        $liveNames += @($response.value | ForEach-Object { $_.name })
        $uri = $response.nextLink
    } while ($uri)

    $latestRunId = ($rows | Sort-Object RunId -Descending | Select-Object -First 1).RunId
    $latestRows = @($rows | Where-Object { $_.RunId -eq $latestRunId -and $_.Status -ne 'Missing' })
    $reportedNames = @($latestRows | ForEach-Object { $_.Name })

    Test-Check -Description "[$latestRunId] Live credential count ($($liveNames.Count)) matches reported count ($($reportedNames.Count))" `
        -Condition ($liveNames.Count -eq $reportedNames.Count) -Warn

    $newSinceReport = @($liveNames | Where-Object { $_ -notin $reportedNames })
    if ($newSinceReport.Count -gt 0) {
        Write-Host "         Credential(s) present live but not in the most recent report (added since last export): $($newSinceReport -join ', ')" -ForegroundColor Yellow
    }
}
else {
    Write-Host "`nSkipping live reconciliation - PurviewAccountName/TenantId/AppId/ClientSecret not all supplied. File-integrity and drift-gate checks only." -ForegroundColor Yellow
}

Write-Host "`n$(if ($script:failures -eq 0) { 'All hard checks passed.' } else { "$script:failures hard check(s) failed." })" `
    -ForegroundColor $(if ($script:failures -eq 0) { 'Green' } else { 'Red' })

if ($script:failures -gt 0) { exit 1 }
```