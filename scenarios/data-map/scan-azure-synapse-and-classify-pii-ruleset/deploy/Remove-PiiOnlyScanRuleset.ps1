#Requires -Version 7.0
<#
.SYNOPSIS
    Reverts the scan created by scan-azure-synapse-and-classify back onto the System scan rule set
    ('AzureSynapseSQL'), then optionally deletes the custom PII-only scan rule set created by
    New-PiiOnlyScanRuleset.ps1.

.DESCRIPTION
    Calls the Microsoft Purview Data Map / Scanning REST API to:
      1. GET the target scan and PUT it back with `scanRulesetName`/`scanRulesetType` reset to the
         System ruleset (every other scan property - authentication kind, dedicated/serverless
         endpoints, collection - preserved unchanged), so the scan reverts to classifying against
         Microsoft's full built-in set instead of the narrower PII-only allowlist.
      2. (only with -DeleteRuleset) DELETE the custom scan rule set object itself.

    Order matters: a scan rule set that is still referenced by a scan is not guaranteed to be
    deletable (no Microsoft documentation confirms deleting an in-use ruleset either succeeds or
    is blocked - this script does not assume either behavior and always detaches the scan first).

    Idempotent: reverting a scan that already points at a System ruleset, or deleting a rule set
    that is already gone, are both treated as success (a 404 on the DELETE call is a no-op, not an
    error).

    Author-only reference code. Never connects to a live tenant unless you supply real credentials
    and omit -WhatIf.

.PARAMETER PurviewAccountName
    Name of the Microsoft Purview account.

.PARAMETER TenantId
    Microsoft Entra tenant ID.

.PARAMETER AppId
    Application (client) ID of the service principal used to call the Purview Data Map REST API.

.PARAMETER ClientSecret
    Client secret for -AppId, as a SecureString.

.PARAMETER DataSourceName
    Name of the data source object the scan belongs to.

.PARAMETER ScanName
    Name of the scan object to revert. Defaults to "<DataSourceName>-scan".

.PARAMETER ScanRulesetName
    Name of the custom scan rule set to detach (and, with -DeleteRuleset, remove). Defaults to
    'AzureSynapseWorkspace-PiiOnly' to match New-PiiOnlyScanRuleset.ps1's default.

.PARAMETER RevertToRulesetName
    System scan rule set to revert the scan onto. Defaults to 'AzureSynapseSQL' - the System
    default NAME for this source type (deliberately NOT 'AzureSynapseWorkspace', the custom
    ruleset's `kind` string - see README.md Section 11's naming-trap callout. Confirmed against
    scan-azure-synapse-and-classify's own -ScanRulesetName default and against
    New-AzPurviewAzureSynapseWorkspaceCredentialScanObject's worked example, which shows
    `ScanRulesetName: AzureSynapseSQL` / `ScanRulesetType: System`).

.PARAMETER DeleteRuleset
    If supplied, also deletes the custom scan rule set object after the scan has been detached
    from it. Omit to keep the ruleset object defined (e.g. it is still referenced by another
    scan - scan rule sets are account-wide, not scoped to one scan) while only reverting this one
    scan.

.PARAMETER ApiVersion
    Data Map REST API version to pin. Defaults to '2023-09-01'.

.PARAMETER WhatIf
    Standard PowerShell ShouldProcess dry-run. Reports every REST call that would be made without
    sending any mutating (PUT/DELETE) request.

.EXAMPLE
    ./Remove-PiiOnlyScanRuleset.ps1 -PurviewAccountName 'contoso-purview' -TenantId $TenantId `
        -AppId $AppId -ClientSecret $ClientSecret -DataSourceName 'ws-contoso-prod' -WhatIf

    Dry-run: shows the scan-revert PUT that would be made, changes nothing.

.EXAMPLE
    ./Remove-PiiOnlyScanRuleset.ps1 -PurviewAccountName 'contoso-purview' -TenantId $TenantId `
        -AppId $AppId -ClientSecret $ClientSecret -DataSourceName 'ws-contoso-prod' `
        -DeleteRuleset

    Reverts the scan to the System default ruleset ('AzureSynapseSQL'), then deletes the custom
    PII-only ruleset object.

.NOTES
    Sources (Microsoft Learn / Az.Purview module, verify before production use):
    - New-AzPurviewAzureSynapseWorkspaceCredentialScanObject (Az.Purview PowerShell module -
      confirms 'AzureSynapseSQL'/'System' as the shared System default, direct fetch via GitHub raw
      source, this build):
      https://raw.githubusercontent.com/Azure/azure-powershell/main/src/Purview/Purview/help/New-AzPurviewAzureSynapseWorkspaceCredentialScanObject.md
    - Scan Rulesets - Get / Delete (API version 2023-09-01):
      https://learn.microsoft.com/rest/api/purview/scanningdataplane/scan-rulesets/get
    - Remove-AzPurviewScanRuleset (Az.Purview PowerShell module - corroborates the delete operation
      exists per scan rule set object):
      https://learn.microsoft.com/powershell/module/az.purview/remove-azpurviewscanruleset
    - Scans - Create Or Replace (reused here to revert the scan's ruleset reference):
      https://learn.microsoft.com/rest/api/purview/scanningdataplane/scans/create-or-replace
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
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
    [string]$ScanRulesetName = 'AzureSynapseWorkspace-PiiOnly',

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$RevertToRulesetName = 'AzureSynapseSQL',

    [Parameter()]
    [switch]$DeleteRuleset,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$ApiVersion = '2023-09-01'
)

$ErrorActionPreference = 'Stop'

if (-not $ScanName) { $ScanName = "$DataSourceName-scan" }

$endpoint = "https://$PurviewAccountName.purview.azure.com"

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

$token = Get-PurviewAccessToken -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret
$headers = @{ Authorization = "Bearer $token" }

# --- Step 1: revert the scan onto the System ruleset (preserve every other scan property) ---
$scanUri = "$endpoint/scan/datasources/$DataSourceName/scans/$ScanName?api-version=$ApiVersion"
$existingScan = $null
try {
    $existingScan = Invoke-RestMethod -Method Get -Uri $scanUri -Headers $headers
}
catch {
    if (-not ($_.Exception.Response -and $_.Exception.Response.StatusCode -eq 404)) { throw }
}

if ($existingScan) {
    $scanBody = @{
        kind       = $existingScan.kind
        properties = @{}
    }
    foreach ($prop in $existingScan.properties.PSObject.Properties) {
        $scanBody.properties[$prop.Name] = $prop.Value
    }
    $scanBody.properties['scanRulesetName'] = $RevertToRulesetName
    $scanBody.properties['scanRulesetType'] = 'System'

    if ($PSCmdlet.ShouldProcess("Scan '$ScanName'", "Revert to ruleset '$RevertToRulesetName' (System)")) {
        $json = $scanBody | ConvertTo-Json -Depth 10
        Invoke-RestMethod -Method Put -Uri $scanUri -Body $json -ContentType 'application/json' -Headers $headers | Out-Null
        Write-Host "Scan '$ScanName' reverted to ruleset '$RevertToRulesetName' (System)." -ForegroundColor Green
    }
    else {
        Write-Verbose "WhatIf: would PUT $scanUri to revert scanRulesetName to '$RevertToRulesetName' (System)."
    }
}
else {
    Write-Host "Scan '$ScanName' on data source '$DataSourceName' not found (already removed?) - nothing to revert." -ForegroundColor Yellow
}

# --- Step 2 (optional): delete the custom scan rule set object ---
if ($DeleteRuleset) {
    $rulesetUri = "$endpoint/scan/scanrulesets/$ScanRulesetName?api-version=$ApiVersion"
    if ($PSCmdlet.ShouldProcess("Scan rule set '$ScanRulesetName'", "DELETE $rulesetUri")) {
        try {
            Invoke-RestMethod -Method Delete -Uri $rulesetUri -Headers $headers | Out-Null
            Write-Host "Scan rule set '$ScanRulesetName' deleted." -ForegroundColor Green
        }
        catch {
            if ($_.Exception.Response -and $_.Exception.Response.StatusCode -eq 404) {
                Write-Host "Scan rule set '$ScanRulesetName' already absent (no-op)." -ForegroundColor Yellow
            }
            else {
                throw
            }
        }
    }
    else {
        Write-Verbose "WhatIf: would DELETE $rulesetUri"
    }
}
else {
    Write-Host "Scan rule set '$ScanRulesetName' left in place (pass -DeleteRuleset to remove it too - confirm no other scan still references it first)." -ForegroundColor Yellow
}

Write-Host "`nDone." -ForegroundColor Cyan
