---
part: "validate"
parent: "data-map/scan-azure-sql-managed-instance-and-classify"
---
Run these checks after deployment to confirm the control is working as designed.


#### `Test-AzureSqlManagedInstanceDataMapScan.ps1`

```powershell
#Requires -Version 7.0
<#
.SYNOPSIS
    Verifies the Azure SQL Managed Instance data source and scan created by
    New-AzureSqlManagedInstanceDataMapScan.ps1 are configured as expected, and reports the most
    recent scan run's status.

.DESCRIPTION
    Read-only validation script - never modifies any object. Checks:
      1. The data source exists with kind AzureSqlDatabaseManagedInstance and the expected server
         endpoint.
      2. The scan exists with kind AzureSqlDatabaseManagedInstanceMsi and the expected
         database/scan rule set.
      3. The most recent scan run (if any) and its status, assets-discovered, and
         assets-classified counts - warns (does not fail) if no run has happened yet, since
         registering a scan does not itself execute one.
    Exits with a non-zero code if any hard check fails, so this script is safe to wire into a
    CI-style pre-flight or a post-deploy smoke test. Safe to re-run any number of times.

.PARAMETER PurviewAccountName
    Name of the Microsoft Purview account.

.PARAMETER TenantId
    Microsoft Entra tenant ID.

.PARAMETER AppId
    Application (client) ID of a service principal holding at least the Data Reader Purview role
    on the target collection - deliberately narrower than the Data Source Administrator role the
    deploy script needs, per this repo's least-privilege convention for validate/ scripts.

.PARAMETER ClientSecret
    Client secret for -AppId, as a SecureString.

.PARAMETER DataSourceName
    Name of the data source object to validate.

.PARAMETER ScanName
    Name of the scan object to validate. Defaults to "<DataSourceName>-scan" to match the deploy
    script's default.

.PARAMETER ExpectedServerEndpoint
    Optional. If supplied, checked against the registered data source's server endpoint (expects
    the "tcp:<fqdn>,<port>" form - see README.md Section 6).

.PARAMETER ApiVersion
    Data Map REST API version to pin. Defaults to '2023-09-01' to match the deploy script.

.EXAMPLE
    ./Test-AzureSqlManagedInstanceDataMapScan.ps1 -PurviewAccountName 'contoso-purview' -TenantId $TenantId `
        -AppId $AppId -ClientSecret $ClientSecret -DataSourceName 'mi-contoso-prod-customerdb'

.NOTES
    The scan-run-history check reads assets-discovered/classified from
    `discoveryExecutionDetails.statistics.assets.discovered`/`.classified` on each run record - the
    confirmed nested shape (Microsoft's own REST reference, directly fetched) rather than the flat
    `.assetsDiscovered`/`.assetsClassified` properties the sibling scan-azure-sql-and-classify
    scenario's validate script assumed. See PROGRESS.md for the follow-up to correct that sibling.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$PurviewAccountName,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$TenantId,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$AppId,

    [Parameter(Mandatory)]
    [SecureString]$ClientSecret,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$DataSourceName,

    [Parameter()]
    [string]$ScanName,

    [Parameter()]
    [string]$ExpectedServerEndpoint,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$ApiVersion = '2023-09-01'
)

$ErrorActionPreference = 'Stop'
$script:failures = 0

function Test-Check {
    param(
        [string]$Description,
        [bool]$Condition,
        [switch]$Warn
    )
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

function Get-PurviewAccessToken {
    param(
        [Parameter(Mandatory)][string]$TenantId,
        [Parameter(Mandatory)][string]$AppId,
        [Parameter(Mandatory)][SecureString]$ClientSecret
    )
    $plainSecret = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto(
        [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($ClientSecret))
    try {
        $body = @{
            client_id     = $AppId
            client_secret = $plainSecret
            grant_type    = 'client_credentials'
            resource      = 'https://purview.azure.net'
        }
        $response = Invoke-RestMethod -Method Post `
            -Uri "https://login.microsoftonline.com/$TenantId/oauth2/token" -Body $body
        return $response.access_token
    }
    finally {
        $plainSecret = $null
    }
}

if (-not $ScanName) { $ScanName = "$DataSourceName-scan" }
$endpoint = "https://$PurviewAccountName.purview.azure.com"
$token = Get-PurviewAccessToken -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret
$headers = @{ Authorization = "Bearer $token" }

Write-Host "Validating data source '$DataSourceName' and scan '$ScanName'..." -ForegroundColor Cyan

# --- Check 1: data source exists and is the right kind/endpoint ---
$dataSource = $null
try {
    $dataSourceUri = "$endpoint/scan/datasources/$DataSourceName?api-version=$ApiVersion"
    $dataSource = Invoke-RestMethod -Method Get -Uri $dataSourceUri -Headers $headers
}
catch {
    if (-not ($_.Exception.Response -and $_.Exception.Response.StatusCode -eq 404)) { throw }
}
Test-Check -Description "Data source '$DataSourceName' exists" -Condition ($null -ne $dataSource)
if (-not $dataSource) {
    Write-Host "`nCannot continue - data source not found. $script:failures check(s) failed." -ForegroundColor Red
    exit 1
}

Test-Check -Description "Data source kind is AzureSqlDatabaseManagedInstance" `
    -Condition ($dataSource.kind -eq 'AzureSqlDatabaseManagedInstance')

if ($ExpectedServerEndpoint) {
    Test-Check -Description "Data source server endpoint matches '$ExpectedServerEndpoint'" `
        -Condition ($dataSource.properties.serverEndpoint -eq $ExpectedServerEndpoint)
}
else {
    Test-Check -Description "Data source server endpoint uses the 'tcp:<fqdn>,<port>' form" `
        -Condition ($dataSource.properties.serverEndpoint -like 'tcp:*,*') -Warn
}

# --- Check 2: scan exists and is the right kind/ruleset ---
$scan = $null
try {
    $scanUri = "$endpoint/scan/datasources/$DataSourceName/scans/$ScanName?api-version=$ApiVersion"
    $scan = Invoke-RestMethod -Method Get -Uri $scanUri -Headers $headers
}
catch {
    if (-not ($_.Exception.Response -and $_.Exception.Response.StatusCode -eq 404)) { throw }
}
Test-Check -Description "Scan '$ScanName' exists" -Condition ($null -ne $scan)

if ($scan) {
    Test-Check -Description "Scan kind is AzureSqlDatabaseManagedInstanceMsi (SAMI-authenticated)" `
        -Condition ($scan.kind -eq 'AzureSqlDatabaseManagedInstanceMsi') -Warn
    Test-Check -Description "Scan has a scan rule set assigned" `
        -Condition (-not [string]::IsNullOrEmpty($scan.properties.scanRulesetName))

    # --- Check 3: most recent scan run status ---
    $historyUri = "$endpoint/scan/datasources/$DataSourceName/scans/$ScanName/runs?api-version=$ApiVersion"
    $history = Invoke-RestMethod -Method Get -Uri $historyUri -Headers $headers
    $latestRun = $history.value | Sort-Object -Property { [datetime]$_.startTime } -Descending | Select-Object -First 1
    if ($latestRun) {
        Test-Check -Description "Most recent scan run status is Succeeded (last run: $($latestRun.startTime), status: $($latestRun.status))" `
            -Condition ($latestRun.status -eq 'Succeeded') -Warn
        $discovered = $latestRun.discoveryExecutionDetails.statistics.assets.discovered
        $classified = $latestRun.discoveryExecutionDetails.statistics.assets.classified
        Write-Host "    Assets discovered: $discovered  |  Assets classified: $classified" -ForegroundColor Cyan
    }
    else {
        Test-Check -Description "At least one scan run has completed (none found - run New-AzureSqlManagedInstanceDataMapScan.ps1 with -RunNow, or wait for the recurring trigger)" `
            -Condition $false -Warn
    }
}

Write-Host "`n$(if ($script:failures -eq 0) { 'All hard checks passed.' } else { "$script:failures hard check(s) failed." })" `
    -ForegroundColor $(if ($script:failures -eq 0) { 'Green' } else { 'Red' })

if ($script:failures -gt 0) { exit 1 }
```