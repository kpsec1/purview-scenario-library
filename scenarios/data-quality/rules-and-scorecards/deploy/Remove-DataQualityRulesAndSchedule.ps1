#Requires -Version 7.0
<#
.SYNOPSIS
    Removes the scan schedule created by New-DataQualityRulesAndSchedule.ps1, and optionally the
    data quality rules themselves.

.DESCRIPTION
    Staged rollback (see ../rollback.md for the full procedure and what each stage does and does
    not undo):
      Stage 1 (default): delete the schedule only. The rules stay in place (still contributing to
        the asset's score whenever a scan does run - portal ad hoc, or a future re-run of the
        deploy script), but no further automatic scan is scheduled.
      Stage 2 (-RemoveRules): also delete every rule named in the definition file, from the asset.

    Idempotent: deleting an object that no longer exists (404) is treated as already-removed, not
    an error, so this script is safe to re-run.

.PARAMETER PurviewAccountEndpoint
    Base URL of the Purview Unified Catalog / Data Quality data-plane API.

.PARAMETER TenantId
    Microsoft Entra tenant ID.

.PARAMETER AppId
    Application (client) ID of a service principal holding the Data Quality Steward role on the
    target governance domain.

.PARAMETER ClientSecret
    Client secret for -AppId, as a SecureString.

.PARAMETER RulesDefinitionPath
    Path to the same rules definition JSON file passed to New-DataQualityRulesAndSchedule.ps1 -
    used to resolve the businessDomainId/dataProductId/dataAssetId and, with -RemoveRules, which
    rules (by name) to delete.

.PARAMETER ScheduleId
    Identifier of the schedule to delete. Defaults to "<dataAssetId>-dq-scan", matching the deploy
    script's default.

.PARAMETER RemoveRules
    If supplied, also deletes every rule in the definition file from the asset (Stage 2). Omit to
    remove only the schedule (Stage 1).

.PARAMETER ApiVersion
    Data Quality REST API version to pin. Defaults to '2026-01-12-preview', matching the deploy
    script.

.PARAMETER WhatIf
    Standard PowerShell ShouldProcess dry-run.

.EXAMPLE
    ./Remove-DataQualityRulesAndSchedule.ps1 -PurviewAccountEndpoint 'https://api.purview-service.microsoft.com' `
        -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
        -RulesDefinitionPath '../deploy/rules/customer-master-data-quality-rules.json' -WhatIf

    Dry-run of Stage 1 (schedule removal only).

.EXAMPLE
    ./Remove-DataQualityRulesAndSchedule.ps1 -PurviewAccountEndpoint 'https://api.purview-service.microsoft.com' `
        -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
        -RulesDefinitionPath '../deploy/rules/customer-master-data-quality-rules.json' -RemoveRules

    Stage 2: removes the schedule and every rule in the definition file.

.NOTES
    Sources: same as New-DataQualityRulesAndSchedule.ps1 - see that script's .NOTES.
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
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
    [switch]$RemoveRules,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$ApiVersion = '2026-01-12-preview'
)

$ErrorActionPreference = 'Stop'
$endpoint = $PurviewAccountEndpoint.TrimEnd('/')

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

function Remove-IfExists {
    param(
        [Parameter(Mandatory)][string]$Uri,
        [Parameter(Mandatory)][string]$Token,
        [Parameter(Mandatory)][string]$Description
    )
    if (-not $PSCmdlet.ShouldProcess($Description, "DELETE $Uri")) {
        Write-Verbose "WhatIf: would DELETE $Uri"
        return
    }
    try {
        Invoke-RestMethod -Method Delete -Uri $Uri -Headers @{ Authorization = "Bearer $Token" } | Out-Null
        Write-Host "Removed: $Description." -ForegroundColor Green
    }
    catch {
        if ($_.Exception.Response -and $_.Exception.Response.StatusCode -eq 404) {
            Write-Host "Already removed (404): $Description." -ForegroundColor Yellow
        }
        else { throw }
    }
}

$definition = Get-Content -Path $RulesDefinitionPath -Raw | ConvertFrom-Json
if (-not $ScheduleId) { $ScheduleId = "$($definition.dataAssetId)-dq-scan" }

$plainSecret = ConvertTo-PlainText -Secure $ClientSecret
try {
    $token = Get-PurviewAccessToken -TenantId $TenantId -AppId $AppId -PlainSecret $plainSecret
}
finally {
    $plainSecret = $null
}

# --- Stage 1: remove the schedule ---
$scheduleUri = "$endpoint/datagovernance/quality/business-domains/$($definition.businessDomainId)/schedules/$ScheduleId?api-version=$ApiVersion"
Remove-IfExists -Uri $scheduleUri -Token $token -Description "schedule '$ScheduleId'"

# --- Stage 2 (optional): remove every rule in the definition file ---
if ($RemoveRules) {
    $rulesBaseUri = "$endpoint/datagovernance/quality/business-domains/$($definition.businessDomainId)" +
    "/data-products/$($definition.dataProductId)/data-assets/$($definition.dataAssetId)/rules"
    $existingRules = Invoke-RestMethod -Method Get -Uri "$rulesBaseUri?api-version=$ApiVersion" -Headers @{ Authorization = "Bearer $token" }

    foreach ($ruleDef in $definition.rules) {
        $match = $existingRules | Where-Object { $_.name -eq $ruleDef.name } | Select-Object -First 1
        if (-not $match) {
            Write-Host "Rule '$($ruleDef.name)' not found - already removed or never created." -ForegroundColor Yellow
            continue
        }
        $ruleUri = "$rulesBaseUri/$($match.id)?api-version=$ApiVersion"
        Remove-IfExists -Uri $ruleUri -Token $token -Description "rule '$($ruleDef.name)' (id: $($match.id))"
    }
}
else {
    Write-Host "`nRules were left in place (score history and rule definitions still exist). Pass -RemoveRules to also delete them." -ForegroundColor Cyan
}
