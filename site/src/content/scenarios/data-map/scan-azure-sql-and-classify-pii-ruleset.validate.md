---
part: "validate"
parent: "data-map/scan-azure-sql-and-classify-pii-ruleset"
---
Run these checks after deployment to confirm the control is working as designed.


#### `Test-PiiOnlyScanRuleset.ps1`

```powershell
#Requires -Version 7.0
<#
.SYNOPSIS
    Verifies the custom PII-only scan rule set created by New-PiiOnlyScanRuleset.ps1 exists with
    the expected retained classifications, and that the target scan references it.

.DESCRIPTION
    Read-only validation script - never modifies any object. Checks:
      1. The scan rule set exists, is kind AzureSqlDatabase and scanRulesetType Custom.
      2. Every classification in -ExpectedRetainedClassifications is ABSENT from the ruleset's
         excludedSystemClassifications (i.e. genuinely retained/scanned-for, not excluded).
      3. The exclusion list is non-trivially large (catches an empty or near-empty exclusion list,
         which would mean the ruleset is not meaningfully narrower than the System default).
      4. The target scan exists and its scanRulesetName/scanRulesetType point at this ruleset.
    Exits with a non-zero code if any hard check fails. Safe to re-run any number of times.

.PARAMETER PurviewAccountName
    Name of the Microsoft Purview account.

.PARAMETER TenantId
    Microsoft Entra tenant ID.

.PARAMETER AppId
    Application (client) ID of a service principal holding at least the Data Reader Purview role
    on the target collection - narrower than the Data Source Administrator role the deploy script
    needs, per this repo's least-privilege convention for validate/ scripts.

.PARAMETER ClientSecret
    Client secret for -AppId, as a SecureString.

.PARAMETER DataSourceName
    Name of the data source the scan belongs to.

.PARAMETER ScanName
    Name of the scan object to validate. Defaults to "<DataSourceName>-scan".

.PARAMETER ScanRulesetName
    Name of the custom scan rule set to validate. Defaults to 'AzureSqlDatabase-PiiOnly' to match
    New-PiiOnlyScanRuleset.ps1's default.

.PARAMETER ExpectedRetainedClassifications
    Classifications that must NOT appear in the ruleset's exclusion list. Defaults to
    U.S. Social Security Number and Credit Card Number, matching the deploy script's default.

.PARAMETER ApiVersion
    Data Map REST API version to pin. Defaults to '2023-09-01' to match the deploy script.

.EXAMPLE
    ./Test-PiiOnlyScanRuleset.ps1 -PurviewAccountName 'contoso-purview' -TenantId $TenantId `
        -AppId $AppId -ClientSecret $ClientSecret -DataSourceName 'sql-contoso-prod-customerdb'

.NOTES
    Sources: same REST references as deploy/New-PiiOnlyScanRuleset.ps1's .NOTES.
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
    [ValidateNotNullOrEmpty()]
    [string]$ScanRulesetName = 'AzureSqlDatabase-PiiOnly',

    [Parameter()]
    [string[]]$ExpectedRetainedClassifications = @(
        'MICROSOFT.GOVERNMENT.US.SOCIAL_SECURITY_NUMBER',
        'MICROSOFT.FINANCIAL.CREDIT_CARD_NUMBER'
    ),

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

Write-Host "Validating scan rule set '$ScanRulesetName' and scan '$ScanName'..." -ForegroundColor Cyan

# --- Check 1: the scan rule set exists and is the right kind/type ---
$ruleset = $null
try {
    $rulesetUri = "$endpoint/scan/scanrulesets/$ScanRulesetName?api-version=$ApiVersion"
    $ruleset = Invoke-RestMethod -Method Get -Uri $rulesetUri -Headers $headers
}
catch {
    if (-not ($_.Exception.Response -and $_.Exception.Response.StatusCode -eq 404)) { throw }
}
Test-Check -Description "Scan rule set '$ScanRulesetName' exists" -Condition ($null -ne $ruleset)
if (-not $ruleset) {
    Write-Host "`nCannot continue - scan rule set not found. $script:failures check(s) failed." -ForegroundColor Red
    exit 1
}

Test-Check -Description "Scan rule set kind is AzureSqlDatabase" -Condition ($ruleset.kind -eq 'AzureSqlDatabase')
Test-Check -Description "Scan rule set type is Custom" -Condition ($ruleset.scanRulesetType -eq 'Custom')

# --- Check 2: expected classifications are retained (NOT present in the exclusion list) ---
$excluded = @($ruleset.properties.excludedSystemClassifications)
foreach ($expected in $ExpectedRetainedClassifications) {
    Test-Check -Description "'$expected' is retained (not excluded)" -Condition ($expected -notin $excluded)
}

# --- Check 3: the exclusion list is non-trivially large ---
Test-Check -Description "Exclusion list is meaningfully narrower than System default ($($excluded.Count) classification(s) excluded, expected 100+)" `
    -Condition ($excluded.Count -gt 100) -Warn

# --- Check 4: the target scan exists and references this ruleset ---
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
    Test-Check -Description "Scan references ruleset '$ScanRulesetName'" `
        -Condition ($scan.properties.scanRulesetName -eq $ScanRulesetName)
    Test-Check -Description "Scan ruleset type is Custom" `
        -Condition ($scan.properties.scanRulesetType -eq 'Custom')
}

Write-Host "`n$(if ($script:failures -eq 0) { 'All hard checks passed.' } else { "$script:failures hard check(s) failed." })" `
    -ForegroundColor $(if ($script:failures -eq 0) { 'Green' } else { 'Red' })

if ($script:failures -gt 0) { exit 1 }
```