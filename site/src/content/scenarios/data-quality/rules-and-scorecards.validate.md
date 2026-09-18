---
part: "validate"
parent: "data-quality/rules-and-scorecards"
---
Run these checks after deployment to confirm the control is working as designed.


#### `Test-DataQualityRulesAndScorecard.ps1`

```powershell
#Requires -Version 7.0
<#
.SYNOPSIS
    Verifies the data quality rules and schedule deployed by New-DataQualityRulesAndSchedule.ps1,
    and reports the target asset's current data quality score if a scan has run.

.DESCRIPTION
    Read-only validation script - never modifies any object. Checks:
      1. Every rule named in the definition file exists on the target asset and is in the expected
         status ('Active' by default, or whatever -ExpectedRuleStatus is passed).
      2. The one-time scan schedule exists (skipped with a note if the deploy was run with
         -CreateSchedule:$false).
      3. The asset's current data quality score (Get Asset Scores For Asset DQ) - warns (does not
         fail) if no score is available yet, since creating rules/a schedule does not itself
         guarantee a scan has completed.
    Exits with a non-zero code if any hard check fails, so this script is safe to wire into a
    CI-style pre-flight or a post-deploy smoke test. Safe to re-run any number of times.

.PARAMETER PurviewAccountEndpoint
    Base URL of the Purview Unified Catalog / Data Quality data-plane API.

.PARAMETER TenantId
    Microsoft Entra tenant ID.

.PARAMETER AppId
    Application (client) ID of a service principal holding at least the Data Quality Reader role
    on the target governance domain - deliberately narrower than the Data Quality Steward role the
    deploy script needs, per this repo's least-privilege convention for validate/ scripts.

.PARAMETER ClientSecret
    Client secret for -AppId, as a SecureString.

.PARAMETER RulesDefinitionPath
    Path to the same rules definition JSON file passed to New-DataQualityRulesAndSchedule.ps1.

.PARAMETER ScheduleId
    Identifier of the schedule to check. Defaults to "<dataAssetId>-dq-scan", matching the deploy
    script's default. Pass -ScheduleId '' (empty string) to skip the schedule check entirely.

.PARAMETER ExpectedRuleStatus
    'Active' (default) or 'Draft' - the status each rule in the definition file is expected to be
    in. Must match whatever -RuleStatus was passed to the deploy script.

.PARAMETER ApiVersion
    Data Quality REST API version to pin. Defaults to '2026-01-12-preview'.

.EXAMPLE
    ./Test-DataQualityRulesAndScorecard.ps1 -PurviewAccountEndpoint 'https://api.purview-service.microsoft.com' `
        -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
        -RulesDefinitionPath '../deploy/rules/customer-master-data-quality-rules.json'
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

    [Parameter(Mandatory)]
    [ValidateScript({ Test-Path $_ -PathType Leaf })]
    [string]$RulesDefinitionPath,

    [Parameter()]
    [string]$ScheduleId,

    [Parameter()]
    [ValidateSet('Active', 'Draft')]
    [string]$ExpectedRuleStatus = 'Active',

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

$definition = Get-Content -Path $RulesDefinitionPath -Raw | ConvertFrom-Json
if (-not $PSBoundParameters.ContainsKey('ScheduleId')) { $ScheduleId = "$($definition.dataAssetId)-dq-scan" }

$plainSecret = ConvertTo-PlainText -Secure $ClientSecret
try {
    $token = Get-PurviewAccessToken -TenantId $TenantId -AppId $AppId -PlainSecret $plainSecret
}
finally {
    $plainSecret = $null
}
$headers = @{ Authorization = "Bearer $token" }

Write-Host "Validating data quality rules and schedule for asset '$($definition.assetDisplayName)'..." -ForegroundColor Cyan

# --- Check 1: every rule in the definition file exists with the expected status ---
$rulesBaseUri = "$endpoint/datagovernance/quality/business-domains/$($definition.businessDomainId)" +
"/data-products/$($definition.dataProductId)/data-assets/$($definition.dataAssetId)/rules"
$rulesUri = "$rulesBaseUri?api-version=$ApiVersion"

$existingRules = $null
try { $existingRules = Invoke-RestMethod -Method Get -Uri $rulesUri -Headers $headers }
catch {
    Test-Check -Description "Rules endpoint reachable for asset '$($definition.dataAssetId)'" -Condition $false
    Write-Host "`n$script:failures check(s) failed - cannot continue without the rules list." -ForegroundColor Red
    exit 1
}

foreach ($ruleDef in $definition.rules) {
    $match = $existingRules | Where-Object { $_.name -eq $ruleDef.name } | Select-Object -First 1
    Test-Check -Description "Rule '$($ruleDef.name)' (type: $($ruleDef.type)) exists" -Condition ($null -ne $match)
    if ($match) {
        Test-Check -Description "Rule '$($ruleDef.name)' status is '$ExpectedRuleStatus'" `
            -Condition ($match.status -eq $ExpectedRuleStatus)
    }
}

# --- Check 2: schedule exists (unless explicitly skipped) ---
if ($ScheduleId) {
    $scheduleUri = "$endpoint/datagovernance/quality/business-domains/$($definition.businessDomainId)/schedules/$ScheduleId?api-version=$ApiVersion"
    $schedule = $null
    try { $schedule = Invoke-RestMethod -Method Get -Uri $scheduleUri -Headers $headers }
    catch {
        if (-not ($_.Exception.Response -and $_.Exception.Response.StatusCode -eq 404)) { throw }
    }
    Test-Check -Description "Schedule '$ScheduleId' exists" -Condition ($null -ne $schedule) -Warn
    if ($schedule) {
        Write-Host "    Trigger: $($schedule.trigger.type), scheduled: $($schedule.trigger.typeProperties.isScheduled), fires: $($schedule.trigger.typeProperties.triggerTime)" -ForegroundColor Cyan
    }
}
else {
    Write-Host "  [SKIP] Schedule check skipped (-ScheduleId '')." -ForegroundColor Yellow
}

# --- Check 3: asset score (informational - warns, does not fail, if no scan has run yet) ---
$scoreUri = "$endpoint/datagovernance/quality/business-domains/$($definition.businessDomainId)/asset-scores" +
"?api-version=$ApiVersion&assetId=$($definition.dataAssetId)&dataProductId=$($definition.dataProductId)"
try {
    $scores = Invoke-RestMethod -Method Get -Uri $scoreUri -Headers $headers
    $assetScore = $scores.value | Where-Object { $_.assetId -eq $definition.dataAssetId } | Select-Object -First 1
    if ($assetScore) {
        Write-Host "  [INFO] Current asset score: $([math]::Round($assetScore.score * 100, 1))% (global score, average of Active rules on the asset)." -ForegroundColor Cyan
    }
    else {
        Test-Check -Description "Asset score available (none yet - no scan has completed. Wait for the scheduled run, or trigger one manually)" `
            -Condition $false -Warn
    }
}
catch {
    Write-Host "  [WARN] Could not retrieve asset score. If this asset has never had a data quality scan complete, this is expected. If it HAS completed at least one scan, this instead likely means the businessDomainId/dataProductId/dataAssetId in '$RulesDefinitionPath' don't match a real, existing asset (a wrong or stale GUID looks identical to 'no run yet' from this endpoint's response alone) - double-check those three IDs against the portal before assuming this is just a timing issue." -ForegroundColor Yellow
}

Write-Host "`n$(if ($script:failures -eq 0) { 'All hard checks passed.' } else { "$script:failures hard check(s) failed." })" `
    -ForegroundColor $(if ($script:failures -eq 0) { 'Green' } else { 'Red' })

if ($script:failures -gt 0) { exit 1 }
```