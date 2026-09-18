---
part: "validate"
parent: "dlp/defender-device-control-usb-allowlist"
---
Run these checks after deployment to confirm the control is working as designed.


#### `Test-DeviceControlUsbAllowlistPolicy.ps1`

```powershell
#Requires -Version 7.0
<#
.SYNOPSIS
    Verifies the "Device Control - USB Removable Media Default-Deny Allowlist" Intune device
    configuration object is deployed correctly.

.DESCRIPTION
    Read-only validation script - never modifies policy state. Checks:
      1. The device configuration object exists and is a windows10CustomConfiguration.
      2. All seven expected omaSettings entries are present with the expected omaUri/value.
      3. The approved-devices group XML contains every serialNumberId/vidPid from -ConfigPath.
      4. The policy has at least one assignment (pilot group or All devices).
    Exits with a non-zero code if any hard check fails, so this script is safe to wire into a
    CI-style pre-flight or a post-deploy smoke test. Safe to re-run any number of times.

    Note: this script validates the device configuration *object* only. It does not and cannot
    confirm per-device profile *sync/apply status* (Intune admin center > Devices > Configuration
    profiles > this policy > Device status) - a correctly configured policy can still be
    unenforced on a specific endpoint that hasn't checked in yet, or that isn't onboarded to
    Defender for Endpoint at all. See README.md Section 7 for the functional (on-device) test
    steps this script cannot replace.

.PARAMETER ConfigPath
    Path to the same JSON config used at deploy time (approvedDevices list + assignment target).

.PARAMETER PolicyDisplayName
    Overrides the config file's policyDisplayName, if set.

.PARAMETER GraphBaseUri
    Graph base URI. Defaults to 'https://graph.microsoft.com/v1.0'.

.EXAMPLE
    Connect-MgGraph -ClientId $AppId -TenantId $TenantId -CertificateThumbprint $Thumbprint
    ./Test-DeviceControlUsbAllowlistPolicy.ps1 -ConfigPath ../deploy/config/device-control-usb-allowlist.sample.json
#>
[CmdletBinding()]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$ConfigPath = (Join-Path $PSScriptRoot '../deploy/config/device-control-usb-allowlist.sample.json'),

    [Parameter()]
    [string]$PolicyDisplayName,

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
$displayName = if ($PolicyDisplayName) { $PolicyDisplayName } else { $cfg.policyDisplayName }

Assert-MgConnected
Write-Host "Validating policy '$displayName'..." -ForegroundColor Cyan

$configUri = "$GraphBaseUri/deviceManagement/deviceConfigurations"
$policy = Get-AllGraphValues -Uri $configUri | Where-Object { $_.displayName -eq $displayName } | Select-Object -First 1

Test-Check -Description "Policy '$displayName' exists" -Condition ($null -ne $policy)
if (-not $policy) {
    Write-Host "`nCannot continue - policy not found. $script:failures check(s) failed." -ForegroundColor Red
    exit 1
}

$full = Invoke-MgGraphRequest -Method GET -Uri "$configUri/$($policy.id)"
Test-Check -Description 'Policy is a windows10CustomConfiguration' `
    -Condition ($full.'@odata.type' -eq '#microsoft.graph.windows10CustomConfiguration')

$settings = @($full.omaSettings)
Test-Check -Description 'Exactly 7 omaSettings entries present' -Condition ($settings.Count -eq 7)

function Find-Setting { param([string]$UriSuffix) $settings | Where-Object { $_.omaUri -like "*$UriSuffix*" } | Select-Object -First 1 }

$enable = Find-Setting -UriSuffix 'DeviceControlEnabled'
Test-Check -Description 'DeviceControlEnabled = 1' -Condition ($null -ne $enable -and [int]$enable.value -eq 1)

$scope = Find-Setting -UriSuffix 'SecuredDevicesConfiguration'
Test-Check -Description "SecuredDevicesConfiguration = 'RemovableMediaDevices'" `
    -Condition ($null -ne $scope -and $scope.value -eq 'RemovableMediaDevices')

$default = Find-Setting -UriSuffix 'DefaultEnforcement'
Test-Check -Description 'DefaultEnforcement = 2 (fail-closed Deny)' -Condition ($null -ne $default -and [int]$default.value -eq 2)

$groupSettings = $settings | Where-Object { $_.omaUri -like '*PolicyGroups*' }
$catchAllGroupSetting = $groupSettings | Where-Object { (ConvertFrom-Utf8Base64 $_.value) -match 'PrimaryId' }
$approvedGroupSetting = $groupSettings | Where-Object { (ConvertFrom-Utf8Base64 $_.value) -notmatch 'PrimaryId' }

Test-Check -Description 'Approved-devices group XML present' -Condition ($null -ne $approvedGroupSetting)
Test-Check -Description 'Catch-all (RemovableMediaDevices) group XML present' -Condition ($null -ne $catchAllGroupSetting)

if ($approvedGroupSetting) {
    $approvedXml = ConvertFrom-Utf8Base64 $approvedGroupSetting.value
    foreach ($d in $cfg.approvedDevices) {
        if ($d.serialNumberId) {
            Test-Check -Description "Approved group includes SerialNumberId '$($d.serialNumberId)'" `
                -Condition ($approvedXml -match [regex]::Escape($d.serialNumberId))
        }
        if ($d.vidPid) {
            Test-Check -Description "Approved group includes VID_PID '$($d.vidPid)'" `
                -Condition ($approvedXml -match [regex]::Escape($d.vidPid))
        }
    }
}

$ruleSettings = $settings | Where-Object { $_.omaUri -like '*PolicyRules*' }
$allowRule = $ruleSettings | Where-Object { (ConvertFrom-Utf8Base64 $_.value) -match 'Allow-ApprovedBackupDrives' }
$denyRule = $ruleSettings | Where-Object { (ConvertFrom-Utf8Base64 $_.value) -match 'Deny-AllOtherRemovableStorage' }

Test-Check -Description 'Allow-ApprovedBackupDrives rule XML present' -Condition ($null -ne $allowRule)
Test-Check -Description 'Deny-AllOtherRemovableStorage rule XML present' -Condition ($null -ne $denyRule)

if ($allowRule) {
    $allowXml = ConvertFrom-Utf8Base64 $allowRule.value
    Test-Check -Description 'Allow rule has an Allow entry with AccessMask 63' -Condition ($allowXml -match '<Type>Allow</Type>' -and $allowXml -match '<AccessMask>63</AccessMask>')
    Test-Check -Description 'Allow rule also audits (AuditAllowed) - not a silent trust' -Condition ($allowXml -match '<Type>AuditAllowed</Type>')
}
if ($denyRule) {
    $denyXml = ConvertFrom-Utf8Base64 $denyRule.value
    Test-Check -Description 'Deny rule has a Deny entry with AccessMask 63' -Condition ($denyXml -match '<Type>Deny</Type>' -and $denyXml -match '<AccessMask>63</AccessMask>')
    Test-Check -Description 'Deny rule excludes the approved group (mutually exclusive by construction)' -Condition ($denyXml -match '<ExcludedIdList>')
}

$assignments = Get-AllGraphValues -Uri "$configUri/$($policy.id)/assignments"
Test-Check -Description 'Policy has at least one assignment' -Condition ($assignments.Count -gt 0)
if ($assignments.Count -gt 0) {
    $isAllDevices = $assignments | Where-Object { $_.target.'@odata.type' -eq '#microsoft.graph.allDevicesAssignmentTarget' }
    Test-Check -Description 'Assignment is scoped to a pilot group, not tenant-wide "All devices" (confirm this is intentional once past pilot)' `
        -Condition (-not $isAllDevices) -Warn
}

Write-Host "`n$(if ($script:failures -eq 0) { 'All hard checks passed.' } else { "$script:failures hard check(s) failed." })" `
    -ForegroundColor $(if ($script:failures -eq 0) { 'Green' } else { 'Red' })

if ($script:failures -gt 0) { exit 1 }
```