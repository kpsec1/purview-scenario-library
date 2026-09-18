---
part: "validate"
parent: "data-quality/connection-and-scorecard-alerts"
---
Run these checks after deployment to confirm the control is working as designed.


#### `Test-DataQualityConnectionAndAlerts.ps1`

```powershell
#Requires -Version 7.0
<#
.SYNOPSIS
    Verifies the data-source connection and alerts deployed by New-DataQualityConnection.ps1 and
    New-DataQualityAlert.ps1.

.DESCRIPTION
    Read-only validation script - never modifies any object. Checks:
      1. The data-source connection exists, with the expected type/region/VNet setting.
      2. Every alert in the definition file exists with the expected condition, status, and
         receivers.
    Exits with a non-zero code if any hard check fails, so this script is safe to wire into a
    CI-style pre-flight or a post-deploy smoke test. Safe to re-run any number of times.

.PARAMETER PurviewAccountEndpoint
    Base URL of the Purview Unified Catalog / Data Quality data-plane API.

.PARAMETER TenantId
    Microsoft Entra tenant ID.

.PARAMETER AppId
    Application (client) ID of a service principal holding at least the Data Quality Reader role
    on the target governance domain - deliberately narrower than the Data Quality Steward role the
    deploy scripts need, per this repo's least-privilege convention for validate/ scripts.

.PARAMETER ClientSecret
    Client secret for -AppId, as a SecureString.

.PARAMETER ConnectionDefinitionPath
    Path to the same connection definition JSON file passed to New-DataQualityConnection.ps1. Pass
    an empty string to skip the connection check.

.PARAMETER AlertDefinitionPath
    Path to the same alert definition JSON file passed to New-DataQualityAlert.ps1. Pass an empty
    string to skip the alert checks.

.PARAMETER ApiVersion
    Data Quality REST API version to pin. Defaults to '2026-01-12-preview'.

.EXAMPLE
    ./Test-DataQualityConnectionAndAlerts.ps1 -PurviewAccountEndpoint 'https://api.purview-service.microsoft.com' `
        -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
        -ConnectionDefinitionPath '../deploy/connection/customer-sql-connection.json' `
        -AlertDefinitionPath '../deploy/alerts/customer-master-score-alerts.json'

.EXAMPLE
    ./Test-DataQualityConnectionAndAlerts.ps1 -PurviewAccountEndpoint 'https://api.purview-service.microsoft.com' `
        -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
        -AlertDefinitionPath '../deploy/alerts/customer-360-product-score-alert.json'

    Validates only the product-level companion alert (no -ConnectionDefinitionPath supplied, so the
    connection check is skipped). The alert-existence/condition/status/receivers checks are generic
    over the scope shape - no script change was needed to validate a product-scoped alert.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$PurviewAccountEndpoint,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$TenantId,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$AppId,

    [Parameter(Mandatory)]
    [SecureString]$ClientSecret,

    [Parameter()]
    [string]$ConnectionDefinitionPath,

    [Parameter()]
    [string]$AlertDefinitionPath,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$ApiVersion = '2026-01-12-preview'
)

$ErrorActionPreference = 'Stop'
$script:failures = 0
$endpoint = $PurviewAccountEndpoint.TrimEnd('/')

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

if (-not $ConnectionDefinitionPath -and -not $AlertDefinitionPath) {
    throw "Pass at least one of -ConnectionDefinitionPath or -AlertDefinitionPath."
}

$plainSecret = ConvertTo-PlainText -Secure $ClientSecret
try {
    $token = Get-PurviewAccessToken -TenantId $TenantId -AppId $AppId -PlainSecret $plainSecret
}
finally {
    $plainSecret = $null
}
$headers = @{ Authorization = "Bearer $token" }

# --- Check group 1: data-source connection ---
if ($ConnectionDefinitionPath) {
    $connDef = Get-Content -Path $ConnectionDefinitionPath -Raw | ConvertFrom-Json
    Write-Host "Validating data-source connection '$($connDef.name)'..." -ForegroundColor Cyan

    $connUri = "$endpoint/datagovernance/quality/business-domains/$($connDef.businessDomainId)/data-sources/$($connDef.dataSourceId)?api-version=$ApiVersion"
    $connection = $null
    try { $connection = Invoke-RestMethod -Method Get -Uri $connUri -Headers $headers }
    catch {
        if (-not ($_.Exception.Response -and $_.Exception.Response.StatusCode -eq 404)) { throw }
    }

    Test-Check -Description "Connection '$($connDef.dataSourceId)' exists" -Condition ($null -ne $connection)
    if ($connection) {
        Test-Check -Description "Connection type is '$($connDef.type)'" -Condition ($connection.type -eq $connDef.type)
        Test-Check -Description "Connection region is '$($connDef.region)'" -Condition ($connection.region -eq $connDef.region)
        $expectedVNet = [bool]$connDef.isVNetEnabled
        Test-Check -Description "Connection isVNetEnabled is '$expectedVNet'" -Condition ([bool]$connection.isVNetEnabled -eq $expectedVNet)
        if ($expectedVNet) {
            Test-Check -Description 'Connection has a computeId (managed VNet path)' -Condition ([bool]$connection.computeId)
        }
    }
    Write-Host ''
}
else {
    Write-Host "[SKIP] Connection check skipped (-ConnectionDefinitionPath not supplied)." -ForegroundColor Yellow
}

# --- Check group 2: alerts ---
if ($AlertDefinitionPath) {
    $alertDefFile = Get-Content -Path $AlertDefinitionPath -Raw | ConvertFrom-Json
    Write-Host "Validating $($alertDefFile.alerts.Count) alert(s) in business domain '$($alertDefFile.businessDomainId)'..." -ForegroundColor Cyan

    foreach ($alertDef in $alertDefFile.alerts) {
        $alertUri = "$endpoint/datagovernance/quality/business-domains/$($alertDefFile.businessDomainId)/alerts/$($alertDef.id)?api-version=$ApiVersion"
        $alert = $null
        try { $alert = Invoke-RestMethod -Method Get -Uri $alertUri -Headers $headers }
        catch {
            if (-not ($_.Exception.Response -and $_.Exception.Response.StatusCode -eq 404)) { throw }
        }

        Test-Check -Description "Alert '$($alertDef.name)' (id: $($alertDef.id)) exists" -Condition ($null -ne $alert)
        if ($alert) {
            Test-Check -Description "Alert '$($alertDef.name)' condition matches definition" -Condition ($alert.condition -eq $alertDef.condition)
            $expectedStatus = if ($alertDef.status) { $alertDef.status } else { 'Enabled' }
            Test-Check -Description "Alert '$($alertDef.name)' status is '$expectedStatus'" -Condition ($alert.status -eq $expectedStatus)
            $expectedReceivers = @($alertDef.receivers) | Sort-Object
            $actualReceivers = @($alert.receivers) | Sort-Object
            $receiversMatch = @(Compare-Object -ReferenceObject $expectedReceivers -DifferenceObject $actualReceivers).Count -eq 0
            Test-Check -Description "Alert '$($alertDef.name)' receivers match definition" -Condition $receiversMatch
        }
    }
}
else {
    Write-Host "[SKIP] Alert checks skipped (-AlertDefinitionPath not supplied)." -ForegroundColor Yellow
}

Write-Host "`n$(if ($script:failures -eq 0) { 'All hard checks passed.' } else { "$script:failures hard check(s) failed." })" `
    -ForegroundColor $(if ($script:failures -eq 0) { 'Green' } else { 'Red' })

if ($script:failures -gt 0) { exit 1 }
```