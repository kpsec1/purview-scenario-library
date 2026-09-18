---
part: "validate"
parent: "data-map/scan-on-premises-sql-server-and-classify"
---
Run these checks after deployment to confirm the control is working as designed.


#### `Test-OnPremisesSqlServerDataMapScan.ps1`

```powershell
#Requires -Version 7.0
<#
.SYNOPSIS
    Verifies the integration runtime, on-premises SQL Server data source, and scan created by
    New-OnPremisesSqlServerDataMapScan.ps1 are configured as expected, and reports the most recent
    scan run's status.

.DESCRIPTION
    Read-only validation script - never modifies any object. Checks:
      1. The integration runtime resource exists and is kind SelfHosted.
      2. The data source exists with kind SqlServerDatabase and the expected server endpoint.
      3. The scan exists with kind SqlServerDatabaseCredential, references the expected integration
         runtime and credential, and has a scan rule set assigned.
      4. The most recent scan run (if any) and its status, assets-discovered, and
         assets-classified counts - warns (does not fail) if no run has happened yet, since
         registering a scan does not itself execute one.
    Exits with a non-zero code if any hard check fails, so this script is safe to wire into a
    CI-style pre-flight or a post-deploy smoke test. Safe to re-run any number of times.

    This script CANNOT confirm whether a SHIR node is actually installed, registered, and "Running"
    on its host - that state lives in the Purview portal's Integration Runtimes page / Nodes tab,
    not in any field this script's REST calls return (the Integration Runtimes - Get operation
    returns the resource definition, not live node health). A scan can pass every check below and
    still fail at run time if no SHIR node has registered against -IntegrationRuntimeName yet - see
    README.md Section 7 for the manual confirmation step.

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

.PARAMETER IntegrationRuntimeName
    Name of the integration runtime resource to validate. Optional - if omitted, check 1 and the
    scan's connectedVia check are skipped.

.PARAMETER ExpectedServerEndpoint
    Optional. If supplied, checked against the registered data source's server endpoint.

.PARAMETER ApiVersion
    Data Map REST API version to pin. Defaults to '2023-09-01' to match the deploy script.

.EXAMPLE
    ./Test-OnPremisesSqlServerDataMapScan.ps1 -PurviewAccountName 'contoso-purview' -TenantId $TenantId `
        -AppId $AppId -ClientSecret $ClientSecret -DataSourceName 'sql01-contoso-local' `
        -IntegrationRuntimeName 'shir-onprem-sql'

.NOTES
    Reads assets-discovered/classified from
    discoveryExecutionDetails.statistics.assets.discovered/.classified on each run record - the
    nested shape confirmed by scan-azure-sql-managed-instance-and-classify's own build (see that
    scenario's design.md Section 5), reused unchanged here since Scan Result operations are
    source-type-agnostic.
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
    [string]$IntegrationRuntimeName,

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

# --- Check 1 (optional): integration runtime resource exists ---
if ($IntegrationRuntimeName) {
    $ir = $null
    try {
        $irUri = "$endpoint/scan/integrationruntimes/$IntegrationRuntimeName?api-version=$ApiVersion"
        $ir = Invoke-RestMethod -Method Get -Uri $irUri -Headers $headers
    }
    catch {
        if (-not ($_.Exception.Response -and $_.Exception.Response.StatusCode -eq 404)) { throw }
    }
    Test-Check -Description "Integration runtime '$IntegrationRuntimeName' exists" -Condition ($null -ne $ir)
    if ($ir) {
        Test-Check -Description "Integration runtime kind is SelfHosted" -Condition ($ir.kind -eq 'SelfHosted')
    }
    Write-Host "  [INFO] This check confirms the Purview RESOURCE exists - it cannot confirm a SHIR node is installed and 'Running' on a host. Confirm that in the portal: Data Map > Integration runtimes > $IntegrationRuntimeName > Nodes." -ForegroundColor DarkGray
}

# --- Check 2: data source exists and is the right kind/endpoint ---
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

Test-Check -Description "Data source kind is SqlServerDatabase" `
    -Condition ($dataSource.kind -eq 'SqlServerDatabase')

if ($ExpectedServerEndpoint) {
    Test-Check -Description "Data source server endpoint matches '$ExpectedServerEndpoint'" `
        -Condition ($dataSource.properties.serverEndpoint -eq $ExpectedServerEndpoint)
}

# --- Check 3: scan exists and is the right kind/ruleset/IR/credential ---
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
    Test-Check -Description "Scan kind is SqlServerDatabaseCredential" `
        -Condition ($scan.kind -eq 'SqlServerDatabaseCredential')
    Test-Check -Description "Scan has a scan rule set assigned" `
        -Condition (-not [string]::IsNullOrEmpty($scan.properties.scanRulesetName))
    Test-Check -Description "Scan has a credential reference assigned" `
        -Condition (-not [string]::IsNullOrEmpty($scan.properties.credential.referenceName))
    if ($IntegrationRuntimeName) {
        Test-Check -Description "Scan's connectedVia references integration runtime '$IntegrationRuntimeName'" `
            -Condition ($scan.properties.connectedVia.referenceName -eq $IntegrationRuntimeName)
    }

    # --- Check 4: most recent scan run status ---
    $historyUri = "$endpoint/scan/datasources/$DataSourceName/scans/$ScanName/runs?api-version=$ApiVersion"
    $history = Invoke-RestMethod -Method Get -Uri $historyUri -Headers $headers
    $latestRun = $history.value | Sort-Object -Property { [datetime]$_.startTime } -Descending | Select-Object -First 1
    if ($latestRun) {
        Test-Check -Description "Most recent scan run status is Succeeded (last run: $($latestRun.startTime), status: $($latestRun.status))" `
            -Condition ($latestRun.status -eq 'Succeeded') -Warn
        $discovered = $latestRun.discoveryExecutionDetails.statistics.assets.discovered
        $classified = $latestRun.discoveryExecutionDetails.statistics.assets.classified
        Write-Host "    Assets discovered: $discovered  |  Assets classified: $classified" -ForegroundColor Cyan
        if ($latestRun.status -ne 'Succeeded') {
            Write-Host "    [INFO] A failed run against an on-premises source is most commonly caused by: the SHIR node isn't 'Running', the credential object's password is stale, or a network/firewall path to the instance is blocked. See README.md Section 8." -ForegroundColor DarkGray
        }
    }
    else {
        Test-Check -Description "At least one scan run has completed (none found - run New-OnPremisesSqlServerDataMapScan.ps1 with -RunNow, or wait for the recurring trigger)" `
            -Condition $false -Warn
    }
}

Write-Host "`n$(if ($script:failures -eq 0) { 'All hard checks passed.' } else { "$script:failures hard check(s) failed." })" `
    -ForegroundColor $(if ($script:failures -eq 0) { 'Green' } else { 'Red' })

if ($script:failures -gt 0) { exit 1 }
```