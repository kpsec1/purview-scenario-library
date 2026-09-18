---
part: "validate"
parent: "dlp/defender-device-control-usb-allowlist-macos-portable-device-coverage"
---
Run these checks after deployment to confirm the control is working as designed.


#### `Test-MacPortableDeviceCoverage.ps1`

```powershell
#Requires -Version 7.0
<#
.SYNOPSIS
    Verifies Apple/Portable/Bluetooth device control coverage is correctly added to the
    "Device Control (macOS) - USB Removable Media Default-Deny Allowlist" macOSCustomConfiguration
    object.

.DESCRIPTION
    Read-only validation script - never modifies policy state. Checks:
      1. The parent device configuration object exists and has a payload.
      2. The embedded deviceControl.policy JSON extracts and parses.
      3. settings.features has appleDevice/portableDevice/bluetoothDevice all disable=false, and
         the parent's own removableMedia feature flag is still present and unmodified.
      4. The three catch-all groups (AllAppleDevices/AllPortableDevices/AllBluetoothDevices) and
         three deny rules are present with the expected primaryId/entry $type/access-list shape.
      5. If -ConfigPath supplies approvedAppleDevices/approvedPortableDevices, the corresponding
         approved-device group and allow rule are present and contain every configured
         serialNumber; if empty, confirms no allow rule exists (pure default-deny).
      6. The parent's own removableMedia groups/rules (AllRemovableStorage, ApprovedBackupDrives,
         Allow-ApprovedBackupDrives, Deny-AllOtherRemovableStorage) are still present, unaffected
         by this fragment.
    Exits with a non-zero code if any hard check fails. Safe to re-run any number of times.

    Note: like the parent scenario's validate script, this checks the device configuration
    *object* only, not per-device profile sync/apply status or Full Disk Access grant state - see
    scenarios/dlp/defender-device-control-usb-allowlist-macos/README.md Section 7 for the
    functional (on-device) test steps this script cannot replace. A functional test for this
    fragment specifically (connect an approved and an unapproved iPhone/camera/Bluetooth device) is
    documented in this scenario's own README.md Section 7.

.PARAMETER ConfigPath
    Path to the same JSON config used at deploy time (approvedAppleDevices/approvedPortableDevices).

.PARAMETER ParentPolicyDisplayName
    Display name of the parent macOSCustomConfiguration object. Defaults to this scenario's
    standard parent name (or -ConfigPath's parentPolicyDisplayName if set).

.PARAMETER GraphBaseUri
    Graph base URI. Defaults to 'https://graph.microsoft.com/v1.0'.

.EXAMPLE
    Connect-MgGraph -ClientId $AppId -TenantId $TenantId -CertificateThumbprint $Thumbprint
    ./Test-MacPortableDeviceCoverage.ps1 -ConfigPath ../deploy/config/mac-portable-device-coverage.sample.json
#>
[CmdletBinding()]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$ConfigPath = (Join-Path $PSScriptRoot '../deploy/config/mac-portable-device-coverage.sample.json'),

    [Parameter()]
    [string]$ParentPolicyDisplayName,

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

function ConvertFrom-Utf8Base64 { param([Parameter(Mandatory)][string]$Base64) [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($Base64)) }
function ConvertFrom-XmlEscaped { param([Parameter(Mandatory)][string]$Text) $Text -replace '&lt;', '<' -replace '&gt;', '>' -replace '&amp;', '&' }

# Fixed GUIDs - must match deploy/Add-MacPortableDeviceCoverage.ps1 exactly.
$AllAppleGroupId = 'd1d2d3d4-1111-4a1a-8a1a-111111111101'
$ApprovedAppleGroupId = 'd1d2d3d4-1111-4a1a-8a1a-111111111102'
$AllPortableGroupId = 'd1d2d3d4-2222-4b2b-8b2b-222222222201'
$ApprovedPortableGroupId = 'd1d2d3d4-2222-4b2b-8b2b-222222222202'
$AllBluetoothGroupId = 'd1d2d3d4-3333-4c3c-8c3c-333333333301'
$DenyAppleRuleId = 'd1d2d3d4-1111-4a1a-8a1a-111111111110'
$AllowAppleRuleId = 'd1d2d3d4-1111-4a1a-8a1a-111111111111'
$DenyPortableRuleId = 'd1d2d3d4-2222-4b2b-8b2b-222222222210'
$AllowPortableRuleId = 'd1d2d3d4-2222-4b2b-8b2b-222222222211'
$DenyBluetoothRuleId = 'd1d2d3d4-3333-4c3c-8c3c-333333333310'

if (-not (Test-Path -LiteralPath $ConfigPath)) { throw "Config file not found: $ConfigPath" }
$cfg = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
$approvedApple = @($cfg.approvedAppleDevices)
$approvedPortable = @($cfg.approvedPortableDevices)
$parentDisplayName = if ($ParentPolicyDisplayName) { $ParentPolicyDisplayName } elseif ($cfg.parentPolicyDisplayName) { $cfg.parentPolicyDisplayName } else { 'Device Control (macOS) - USB Removable Media Default-Deny Allowlist' }

Assert-MgConnected
Write-Host "Validating Apple/Portable/Bluetooth device control coverage on '$parentDisplayName'..." -ForegroundColor Cyan

$configUri = "$GraphBaseUri/deviceManagement/deviceConfigurations"
$parent = Get-AllGraphValues -Uri $configUri | Where-Object { $_.displayName -eq $parentDisplayName } | Select-Object -First 1

Test-Check -Description "Parent policy '$parentDisplayName' exists" -Condition ($null -ne $parent)
if (-not $parent) {
    Write-Host "`nCannot continue - parent policy not found. $script:failures check(s) failed." -ForegroundColor Red
    exit 1
}

$full = Invoke-MgGraphRequest -Method GET -Uri "$configUri/$($parent.id)"
Test-Check -Description 'Parent policy has a payload' -Condition ($null -ne $full.payload)
if (-not $full.payload) {
    Write-Host "`nCannot continue - no payload. $script:failures check(s) failed." -ForegroundColor Red
    exit 1
}

$mobileConfigXml = ConvertFrom-Utf8Base64 $full.payload
$policyMatch = [regex]::Match($mobileConfigXml, '<key>policy</key>\s*<string>(.*?)</string>', [System.Text.RegularExpressions.RegexOptions]::Singleline)
Test-Check -Description 'deviceControl.policy JSON string extracted from .mobileconfig payload' -Condition $policyMatch.Success
if (-not $policyMatch.Success) {
    Write-Host "`nCannot continue - policy JSON not found. $script:failures check(s) failed." -ForegroundColor Red
    exit 1
}

$policy = $null
try { $policy = (ConvertFrom-XmlEscaped $policyMatch.Groups[1].Value) | ConvertFrom-Json } catch {}
Test-Check -Description 'deviceControl.policy JSON parses' -Condition ($null -ne $policy)
if (-not $policy) {
    Write-Host "`nCannot continue - policy JSON failed to parse. $script:failures check(s) failed." -ForegroundColor Red
    exit 1
}

# --- Feature flags ---
$features = $policy.settings.features
Test-Check -Description "settings.features.removableMedia.disable = false (parent's own flag, unaffected)" -Condition ($features.removableMedia.disable -eq $false) -Warn
Test-Check -Description 'settings.features.appleDevice.disable = false' -Condition ($features.appleDevice.disable -eq $false)
Test-Check -Description 'settings.features.portableDevice.disable = false' -Condition ($features.portableDevice.disable -eq $false)
Test-Check -Description 'settings.features.bluetoothDevice.disable = false' -Condition ($features.bluetoothDevice.disable -eq $false)

# --- Catch-all groups ---
function Find-GroupById { param($Groups, $Id) $Groups | Where-Object { $_.id -eq $Id } | Select-Object -First 1 }
function Find-RuleById { param($Rules, $Id) $Rules | Where-Object { $_.id -eq $Id } | Select-Object -First 1 }

$allApple = Find-GroupById -Groups $policy.groups -Id $AllAppleGroupId
Test-Check -Description 'AllAppleDevices catch-all group present (primaryId = apple_devices)' -Condition ($null -ne $allApple -and $allApple.query.clauses[0].value -eq 'apple_devices')
$allPortable = Find-GroupById -Groups $policy.groups -Id $AllPortableGroupId
Test-Check -Description 'AllPortableDevices catch-all group present (primaryId = portable_devices)' -Condition ($null -ne $allPortable -and $allPortable.query.clauses[0].value -eq 'portable_devices')
$allBluetooth = Find-GroupById -Groups $policy.groups -Id $AllBluetoothGroupId
Test-Check -Description 'AllBluetoothDevices catch-all group present (primaryId = bluetooth_devices)' -Condition ($null -ne $allBluetooth -and $allBluetooth.query.clauses[0].value -eq 'bluetooth_devices')

# --- Deny rules (mandatory, always present regardless of allowlist config) ---
$denyApple = Find-RuleById -Rules $policy.rules -Id $DenyAppleRuleId
Test-Check -Description 'Apple deny rule present with deny + auditDeny entries, entry $type = appleDevice' -Condition ($null -ne $denyApple -and $denyApple.entries.'$type' -contains 'appleDevice' -and ($denyApple.entries.enforcement.'$type' -contains 'deny') -and ($denyApple.entries.enforcement.'$type' -contains 'auditDeny'))
$denyPortable = Find-RuleById -Rules $policy.rules -Id $DenyPortableRuleId
Test-Check -Description 'Portable deny rule present with deny + auditDeny entries, entry $type = portableDevice' -Condition ($null -ne $denyPortable -and $denyPortable.entries.'$type' -contains 'portableDevice' -and ($denyPortable.entries.enforcement.'$type' -contains 'deny') -and ($denyPortable.entries.enforcement.'$type' -contains 'auditDeny'))
$denyBluetooth = Find-RuleById -Rules $policy.rules -Id $DenyBluetoothRuleId
Test-Check -Description 'Bluetooth deny rule present with deny + auditDeny entries, entry $type = bluetoothDevice' -Condition ($null -ne $denyBluetooth -and $denyBluetooth.entries.'$type' -contains 'bluetoothDevice' -and ($denyBluetooth.entries.enforcement.'$type' -contains 'deny') -and ($denyBluetooth.entries.enforcement.'$type' -contains 'auditDeny'))
Test-Check -Description 'Bluetooth deny rule has no excludeGroups (default-deny, no allowlist by design - README.md Section 11)' -Condition (-not $denyBluetooth.excludeGroups)

# --- Optional approved-device groups/allow rules ---
if ($approvedApple.Count -gt 0) {
    $approvedAppleGroup = Find-GroupById -Groups $policy.groups -Id $ApprovedAppleGroupId
    Test-Check -Description 'ApprovedAppleDevices group present' -Condition ($null -ne $approvedAppleGroup)
    if ($approvedAppleGroup) {
        $serials = @($approvedAppleGroup.query.clauses | Where-Object { $_.'$type' -eq 'serialNumber' } | ForEach-Object { $_.value })
        foreach ($d in $approvedApple) {
            Test-Check -Description "ApprovedAppleDevices group includes serialNumber '$($d.serialNumber)'" -Condition ($serials -contains $d.serialNumber)
        }
    }
    $allowApple = Find-RuleById -Rules $policy.rules -Id $AllowAppleRuleId
    Test-Check -Description 'Apple allow rule present (allow + auditAllow entries)' -Condition ($null -ne $allowApple -and ($allowApple.entries.enforcement.'$type' -contains 'allow') -and ($allowApple.entries.enforcement.'$type' -contains 'auditAllow'))
    Test-Check -Description 'Apple deny rule excludes the approved Apple group' -Condition ($denyApple.excludeGroups -contains $ApprovedAppleGroupId)
}
else {
    Test-Check -Description 'No ApprovedAppleDevices group (empty config -> pure default-deny, no exceptions)' -Condition ($null -eq (Find-GroupById -Groups $policy.groups -Id $ApprovedAppleGroupId))
    Test-Check -Description 'Apple deny rule has no excludeGroups (empty config -> pure default-deny)' -Condition (-not $denyApple.excludeGroups)
}

if ($approvedPortable.Count -gt 0) {
    $approvedPortableGroup = Find-GroupById -Groups $policy.groups -Id $ApprovedPortableGroupId
    Test-Check -Description 'ApprovedPortableDevices group present' -Condition ($null -ne $approvedPortableGroup)
    if ($approvedPortableGroup) {
        $serials = @($approvedPortableGroup.query.clauses | Where-Object { $_.'$type' -eq 'serialNumber' } | ForEach-Object { $_.value })
        foreach ($d in $approvedPortable) {
            Test-Check -Description "ApprovedPortableDevices group includes serialNumber '$($d.serialNumber)' (VERIFY: serialNumber-for-portable_devices has no directly-confirmed Microsoft worked example - README.md Section 11)" -Condition ($serials -contains $d.serialNumber) -Warn
        }
    }
    $allowPortable = Find-RuleById -Rules $policy.rules -Id $AllowPortableRuleId
    Test-Check -Description 'Portable allow rule present (allow + auditAllow entries)' -Condition ($null -ne $allowPortable -and ($allowPortable.entries.enforcement.'$type' -contains 'allow') -and ($allowPortable.entries.enforcement.'$type' -contains 'auditAllow'))
    Test-Check -Description 'Portable deny rule excludes the approved Portable group' -Condition ($denyPortable.excludeGroups -contains $ApprovedPortableGroupId)
}
else {
    Test-Check -Description 'No ApprovedPortableDevices group (empty config -> pure default-deny, no exceptions)' -Condition ($null -eq (Find-GroupById -Groups $policy.groups -Id $ApprovedPortableGroupId))
    Test-Check -Description 'Portable deny rule has no excludeGroups (empty config -> pure default-deny)' -Condition (-not $denyPortable.excludeGroups)
}

# --- Parent's own removableMedia coverage must be unaffected ---
$parentAllowRule = $policy.rules | Where-Object { $_.name -eq 'Allow-ApprovedBackupDrives' }
$parentDenyRule = $policy.rules | Where-Object { $_.name -eq 'Deny-AllOtherRemovableStorage' }
$parentApprovedGroup = $policy.groups | Where-Object { $_.name -eq 'ApprovedBackupDrives' }
$parentCatchAllGroup = $policy.groups | Where-Object { $_.name -eq 'AllRemovableStorage' }
Test-Check -Description "Parent's Allow-ApprovedBackupDrives rule is still present (unaffected by this fragment)" -Condition ($null -ne $parentAllowRule) -Warn
Test-Check -Description "Parent's Deny-AllOtherRemovableStorage rule is still present (unaffected by this fragment)" -Condition ($null -ne $parentDenyRule) -Warn
Test-Check -Description "Parent's ApprovedBackupDrives group is still present (unaffected by this fragment)" -Condition ($null -ne $parentApprovedGroup) -Warn
Test-Check -Description "Parent's AllRemovableStorage group is still present (unaffected by this fragment)" -Condition ($null -ne $parentCatchAllGroup) -Warn

Write-Host "`n$(if ($script:failures -eq 0) { 'All hard checks passed.' } else { "$script:failures hard check(s) failed." })" `
    -ForegroundColor $(if ($script:failures -eq 0) { 'Green' } else { 'Red' })

if ($script:failures -gt 0) { exit 1 }
```