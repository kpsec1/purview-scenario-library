---
part: "validate"
parent: "dlp/defender-device-control-usb-allowlist-wpd-coverage"
---
Run these checks after deployment to confirm the control is working as designed.


#### `Test-WpdDeviceControlCoverage.ps1`

```powershell
#Requires -Version 7.0
<#
.SYNOPSIS
    Verifies Windows Portable Device (WPD) coverage is correctly added to the "Device Control -
    USB Removable Media Default-Deny Allowlist" Intune device configuration object.

.DESCRIPTION
    Read-only validation script - never modifies policy state. Checks:
      1. The parent device configuration object exists.
      2. SecuredDevicesConfiguration includes both RemovableMediaDevices and WpdDevices.
      3. The parent's original 7 RemovableMediaDevices-scoped omaSettings are still present and
         untouched (this scenario must not have regressed the parent's own coverage).
      4. The 4 new WPD-scoped omaSettings (approved group, catch-all group, allow rule, deny rule)
         are present with the expected structure.
      5. The approved-WPD-devices group XML contains every friendlyNameId/serialNumberId/vidPid
         from -ConfigPath.
    Exits with a non-zero code if any hard check fails. Safe to re-run any number of times.

    Note: like the parent scenario's validate script, this checks the device configuration
    *object* only, not per-device profile sync/apply status - see
    scenarios/dlp/defender-device-control-usb-allowlist/README.md Section 7 for the functional
    (on-device) test steps this script cannot replace. A WPD-specific functional test (plug in an
    approved and an unapproved phone/camera in MTP mode) is documented in this scenario's own
    README.md Section 7.

.PARAMETER ConfigPath
    Path to the same JSON config used at deploy time (approvedWpdDevices list).

.PARAMETER GraphBaseUri
    Graph base URI. Defaults to 'https://graph.microsoft.com/v1.0'.

.EXAMPLE
    Connect-MgGraph -ClientId $AppId -TenantId $TenantId -CertificateThumbprint $Thumbprint
    ./Test-WpdDeviceControlCoverage.ps1 -ConfigPath ../deploy/config/wpd-device-control-coverage.sample.json
#>
[CmdletBinding()]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$ConfigPath = (Join-Path $PSScriptRoot '../deploy/config/wpd-device-control-coverage.sample.json'),

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$GraphBaseUri = 'https://graph.microsoft.com/v1.0'
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

function Assert-MgConnected {
    if (-not (Get-Command Invoke-MgGraphRequest -ErrorAction SilentlyContinue)) {
        throw 'Microsoft Graph PowerShell SDK not found. Install Microsoft.Graph.Authentication and Microsoft.Graph.DeviceManagement, then Connect-MgGraph.'
    }
    if (-not (Get-MgContext -ErrorAction SilentlyContinue)) {
        throw 'Not connected to Microsoft Graph. Run Connect-MgGraph first. See docs/automation-surface.md Section 3.'
    }
}

function Get-AllGraphValues {
    param([Parameter(Mandatory)][string]$Uri)
    $items = @()
    $next = $Uri
    while ($next) {
        $resp = Invoke-MgGraphRequest -Method GET -Uri $next
        if ($resp.value) { $items += $resp.value }
        $next = $resp.'@odata.nextLink'
    }
    return $items
}

function ConvertFrom-Utf8Base64 {
    param([Parameter(Mandatory)][string]$Base64)
    [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($Base64))
}

if (-not (Test-Path -LiteralPath $ConfigPath)) { throw "Config file not found: $ConfigPath" }
$cfg = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
$parentDisplayName = if ($cfg.parentPolicyDisplayName) { $cfg.parentPolicyDisplayName } else { 'Device Control - USB Removable Media Default-Deny Allowlist' }

Assert-MgConnected
Write-Host "Validating WPD device control coverage on '$parentDisplayName'..." -ForegroundColor Cyan

$configUri = "$GraphBaseUri/deviceManagement/deviceConfigurations"
$parent = Get-AllGraphValues -Uri $configUri | Where-Object { $_.displayName -eq $parentDisplayName } | Select-Object -First 1

Test-Check -Description "Parent policy '$parentDisplayName' exists" -Condition ($null -ne $parent)
if (-not $parent) {
    Write-Host "`nCannot continue - parent policy not found. $script:failures check(s) failed." -ForegroundColor Red
    exit 1
}

$full = Invoke-MgGraphRequest -Method GET -Uri "$configUri/$($parent.id)"
$settings = @($full.omaSettings)

Test-Check -Description 'Exactly 11 omaSettings entries present (7 parent + 4 WPD)' -Condition ($settings.Count -eq 11) -Warn

function Find-Setting { param([string]$UriSuffix) $settings | Where-Object { $_.omaUri -like "*$UriSuffix*" } | Select-Object -First 1 }

$scope = Find-Setting -UriSuffix 'SecuredDevicesConfiguration'
Test-Check -Description 'SecuredDevicesConfiguration exists' -Condition ($null -ne $scope)
if ($scope) {
    Test-Check -Description "SecuredDevicesConfiguration includes 'RemovableMediaDevices'" -Condition ($scope.value -match 'RemovableMediaDevices')
    Test-Check -Description "SecuredDevicesConfiguration includes 'WpdDevices'" -Condition ($scope.value -match 'WpdDevices')
    Test-Check -Description 'SecuredDevicesConfiguration is the documented pipe-separated form (no spaces)' -Condition ($scope.value -notmatch '\s' -and $scope.value -match '\|')
}

$enable = Find-Setting -UriSuffix 'DeviceControlEnabled'
Test-Check -Description "Parent's DeviceControlEnabled = 1 (unaffected by this fragment)" -Condition ($null -ne $enable -and [int]$enable.value -eq 1)

$default = Find-Setting -UriSuffix 'DefaultEnforcement'
Test-Check -Description "Parent's DefaultEnforcement = 2 / Deny (unaffected by this fragment)" -Condition ($null -ne $default -and [int]$default.value -eq 2)

$groupSettings = $settings | Where-Object { $_.omaUri -like '*PolicyGroups*' }
$approvedUsbGroup = $groupSettings | Where-Object { (ConvertFrom-Utf8Base64 $_.value) -match 'SerialNumberId|VID_PID' -and (ConvertFrom-Utf8Base64 $_.value) -notmatch 'FriendlyNameId' -and (ConvertFrom-Utf8Base64 $_.value) -notmatch 'PrimaryId' }
Test-Check -Description "Parent's ApprovedBackupDrives group is still present (unaffected by this fragment)" -Condition ($null -ne $approvedUsbGroup) -Warn

$catchAllWpdGroup = $groupSettings | Where-Object { (ConvertFrom-Utf8Base64 $_.value) -match '<PrimaryId>WpdDevices</PrimaryId>' }
Test-Check -Description 'AllWpdDevices catch-all group (PrimaryId = WpdDevices) present' -Condition ($null -ne $catchAllWpdGroup)

$approvedWpdGroups = @($groupSettings | Where-Object { $_.displayName -eq 'Group: ApprovedWpdDevices' })
Test-Check -Description 'ApprovedWpdDevices group present' -Condition ($approvedWpdGroups.Count -eq 1)

if ($approvedWpdGroups.Count -eq 1) {
    $approvedXml = ConvertFrom-Utf8Base64 $approvedWpdGroups[0].value
    foreach ($d in $cfg.approvedWpdDevices) {
        if ($d.friendlyNameId) {
            Test-Check -Description "ApprovedWpdDevices group includes FriendlyNameId '$($d.friendlyNameId)'" `
                -Condition ($approvedXml -match [regex]::Escape($d.friendlyNameId))
        }
        if ($d.serialNumberId) {
            Test-Check -Description "ApprovedWpdDevices group includes SerialNumberId '$($d.serialNumberId)' (unconfirmed for WPD - README.md Section 11)" `
                -Condition ($approvedXml -match [regex]::Escape($d.serialNumberId)) -Warn
        }
        if ($d.vidPid) {
            Test-Check -Description "ApprovedWpdDevices group includes VID_PID '$($d.vidPid)' (unconfirmed for WPD - README.md Section 11)" `
                -Condition ($approvedXml -match [regex]::Escape($d.vidPid)) -Warn
        }
    }
}

$ruleSettings = $settings | Where-Object { $_.omaUri -like '*PolicyRules*' }
$allowWpdRule = $ruleSettings | Where-Object { (ConvertFrom-Utf8Base64 $_.value) -match 'Allow-ApprovedWpdDevices' }
$denyWpdRule = $ruleSettings | Where-Object { (ConvertFrom-Utf8Base64 $_.value) -match 'Deny-AllOtherWpd' }

Test-Check -Description 'Allow-ApprovedWpdDevices rule XML present' -Condition ($null -ne $allowWpdRule)
Test-Check -Description 'Deny-AllOtherWpd rule XML present' -Condition ($null -ne $denyWpdRule)

if ($allowWpdRule) {
    $allowXml = ConvertFrom-Utf8Base64 $allowWpdRule.value
    Test-Check -Description 'Allow-WPD rule has an Allow entry with AccessMask 63' -Condition ($allowXml -match '<Type>Allow</Type>' -and $allowXml -match '<AccessMask>63</AccessMask>')
    Test-Check -Description 'Allow-WPD rule also audits (AuditAllowed) - not a silent trust' -Condition ($allowXml -match '<Type>AuditAllowed</Type>')
}
if ($denyWpdRule) {
    $denyXml = ConvertFrom-Utf8Base64 $denyWpdRule.value
    Test-Check -Description 'Deny-WPD rule has a Deny entry with AccessMask 63' -Condition ($denyXml -match '<Type>Deny</Type>' -and $denyXml -match '<AccessMask>63</AccessMask>')
    Test-Check -Description 'Deny-WPD rule excludes the approved WPD group (mutually exclusive by construction)' -Condition ($denyXml -match '<ExcludedIdList>')
}

$originalAllowRule = $ruleSettings | Where-Object { (ConvertFrom-Utf8Base64 $_.value) -match 'Allow-ApprovedBackupDrives' }
$originalDenyRule = $ruleSettings | Where-Object { (ConvertFrom-Utf8Base64 $_.value) -match 'Deny-AllOtherRemovableStorage' }
Test-Check -Description "Parent's Allow-ApprovedBackupDrives rule is still present (unaffected by this fragment)" -Condition ($null -ne $originalAllowRule) -Warn
Test-Check -Description "Parent's Deny-AllOtherRemovableStorage rule is still present (unaffected by this fragment)" -Condition ($null -ne $originalDenyRule) -Warn

Write-Host "`n$(if ($script:failures -eq 0) { 'All hard checks passed.' } else { "$script:failures hard check(s) failed." })" `
    -ForegroundColor $(if ($script:failures -eq 0) { 'Green' } else { 'Red' })

if ($script:failures -gt 0) { exit 1 }
```