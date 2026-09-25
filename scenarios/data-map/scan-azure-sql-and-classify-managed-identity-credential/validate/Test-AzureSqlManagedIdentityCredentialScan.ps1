#Requires -Version 7.0
<#
.SYNOPSIS
    Verifies the scan reconciled by New-AzureSqlManagedIdentityCredentialScan.ps1 authenticates via
    the expected ManagedIdentity credential, and reports the most recent scan run's status.

.DESCRIPTION
    Read-only validation script - never modifies any object. Checks:
      1. The scan exists.
      2. The scan's kind is AzureSqlDatabaseCredential (not AzureSqlDatabaseMsi/SAMI).
      3. The scan's credential reference is credentialType 'ManagedIdentity' and, if supplied,
         referenceName matches -ExpectedCredentialReferenceName.
      4. (-CheckCredentialObject) the referenced credential object itself exists and is kind
         ManagedIdentity - the same structural check New-AzureSqlManagedIdentityCredentialScan.ps1
         runs at deploy time, repeatable independently to catch drift (e.g. someone deleted or
         retyped the credential object after this scan was reconciled).
      5. The most recent scan run (if any) and its status - warns (does not fail) if no run has
         happened yet.
    Exits with a non-zero code if any hard check fails. Safe to re-run any number of times.

.PARAMETER PurviewAccountName
    Name of the Microsoft Purview account.

.PARAMETER TenantId
    Microsoft Entra tenant ID.

.PARAMETER AppId
    Application (client) ID of a service principal holding at least the Data Reader Purview role on
    the target collection - deliberately narrower than the Data Source Administrator role the deploy
    script needs.

.PARAMETER ClientSecret
    Client secret for -AppId, as a SecureString.

.PARAMETER DataSourceName
    Name of the data source object the scan belongs to.

.PARAMETER ScanName
    Name of the scan object to validate. Defaults to "<DataSourceName>-scan".

.PARAMETER ExpectedCredentialReferenceName
    Optional. If supplied, checked against the scan's credential.referenceName.

.PARAMETER CheckCredentialObject
    Also GET the referenced credential object and confirm it exists and is kind ManagedIdentity.

.PARAMETER ApiVersion
    Data Map REST API version to pin. Defaults to '2023-09-01'.

.EXAMPLE
    ./Test-AzureSqlManagedIdentityCredentialScan.ps1 -PurviewAccountName 'contoso-purview' `
        -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
        -DataSourceName 'sql-contoso-prod-customerdb' -ExpectedCredentialReferenceName 'sql-contoso-uami' `
        -CheckCredentialObject

.NOTES
    Source: Scans - Create Or Replace / Credential - Get (confirmed CredentialReference {
    credentialType, referenceName } shape and the CredentialType enum's 'ManagedIdentity' value):
    https://learn.microsoft.com/rest/api/purview/scanningdataplane/scans/create-or-replace
    https://learn.microsoft.com/rest/api/purview/scanningdataplane/credential
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
    [string]$ExpectedCredentialReferenceName,

    [Parameter()]
    [switch]$CheckCredentialObject,

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

Write-Host "Validating scan '$ScanName' authenticates via a ManagedIdentity credential..." -ForegroundColor Cyan

# --- Check 1: scan exists ---
$scan = $null
try {
    $scanUri = "$endpoint/scan/datasources/$DataSourceName/scans/$ScanName?api-version=$ApiVersion"
    $scan = Invoke-RestMethod -Method Get -Uri $scanUri -Headers $headers
}
catch {
    if (-not ($_.Exception.Response -and $_.Exception.Response.StatusCode -eq 404)) { throw }
}
Test-Check -Description "Scan '$ScanName' exists" -Condition ($null -ne $scan)
if (-not $scan) {
    Write-Host "`nCannot continue - scan not found. $script:failures check(s) failed." -ForegroundColor Red
    exit 1
}

# --- Check 2: scan kind ---
Test-Check -Description "Scan kind is AzureSqlDatabaseCredential (not SAMI)" `
    -Condition ($scan.kind -eq 'AzureSqlDatabaseCredential')

# --- Check 3: credential reference ---
$credRef = $scan.properties.credential
Test-Check -Description "Scan's credential.credentialType is 'ManagedIdentity'" `
    -Condition ($credRef -and $credRef.credentialType -eq 'ManagedIdentity')

if ($ExpectedCredentialReferenceName) {
    Test-Check -Description "Scan's credential.referenceName matches '$ExpectedCredentialReferenceName'" `
        -Condition ($credRef -and $credRef.referenceName -eq $ExpectedCredentialReferenceName)
}
elseif ($credRef) {
    Write-Host "  [INFO] Scan references credential '$($credRef.referenceName)' (no -ExpectedCredentialReferenceName supplied to assert against)." -ForegroundColor Cyan
}

# --- Check 4 (optional): the referenced credential object itself ---
if ($CheckCredentialObject -and $credRef -and $credRef.referenceName) {
    $credentialUri = "$endpoint/scan/credentials/$($credRef.referenceName)?api-version=$ApiVersion"
    $credentialObj = $null
    try {
        $credentialObj = Invoke-RestMethod -Method Get -Uri $credentialUri -Headers $headers
    }
    catch {
        if (-not ($_.Exception.Response -and $_.Exception.Response.StatusCode -eq 404)) { throw }
    }
    Test-Check -Description "Referenced credential object '$($credRef.referenceName)' exists" `
        -Condition ($null -ne $credentialObj)
    if ($credentialObj) {
        Test-Check -Description "Referenced credential object is kind ManagedIdentity" `
            -Condition ($credentialObj.kind -eq 'ManagedIdentity')
    }
}

# --- Check 5: most recent scan run status ---
try {
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
        Test-Check -Description "At least one scan run has completed under the UAMI credential (none found - run New-AzureSqlManagedIdentityCredentialScan.ps1 with -RunNow)" `
            -Condition $false -Warn
    }
}
catch {
    Write-Host "  [WARN] Could not retrieve scan run history. Check scan run status manually in the Purview portal." -ForegroundColor Yellow
}

Write-Host "`n$(if ($script:failures -eq 0) { 'All hard checks passed.' } else { "$script:failures hard check(s) failed." })" `
    -ForegroundColor $(if ($script:failures -eq 0) { 'Green' } else { 'Red' })

if ($script:failures -gt 0) { exit 1 }
