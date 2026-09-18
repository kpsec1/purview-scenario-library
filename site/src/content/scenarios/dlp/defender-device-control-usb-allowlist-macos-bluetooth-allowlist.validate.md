---
part: "validate"
parent: "dlp/defender-device-control-usb-allowlist-macos-bluetooth-allowlist"
---
Run these checks after deployment to confirm the control is working as designed.


#### `Test-MacBluetoothDeviceAllowlist.ps1`

```powershell
#Requires -Version 7.0
<#
.SYNOPSIS
    Verifies the approved Bluetooth device exception is correctly present on the shared macOS
    device control policy, and detects the known cross-fragment ordering hazard.

.DESCRIPTION
    Read-only validation script - never modifies policy state. Checks:
      1. The parent device configuration object exists and has a payload.
      2. The embedded deviceControl.policy JSON extracts and parses.
      3. The prerequisite AllBluetoothDevices group and Deny-AllBluetoothDevices rule (from
         defender-device-control-usb-allowlist-macos-portable-device-coverage) are present.
      4. If -ConfigPath supplies approvedBluetoothDevices, the ApprovedBluetoothDevice group exists
         with the expected primaryId/vendorId/productId AND-clauses, the Deny-AllBluetoothDevices
         rule's excludeGroups references it, and the Allow-ApprovedBluetoothDevice rule exists with
         allow + auditAllow entries and the correct access list.
      5. If empty, confirms no ApprovedBluetoothDevice group/allow rule exist and the deny rule has
         no excludeGroups (pure default-deny).
      6. DRIFT CHECK (the known ordering hazard - README.md Section 11): if
         approvedBluetoothDevices is configured but the deny rule's excludeGroups is missing while
         the ApprovedBluetoothDevice group and Allow rule both still exist, this indicates
         Add-MacPortableDeviceCoverage.ps1 -Force was re-run after this fragment's own deploy script,
         silently stripping the exclusion. Reported as a distinct [FAIL] with the exact remediation
         (re-run deploy/Add-MacBluetoothDeviceAllowlist.ps1), not conflated with "never deployed."
      7. The parent's own removableMedia coverage and the prerequisite fragment's Apple/Portable
         groups/rules are still present, unaffected by this fragment.
    Exits with a non-zero code if any hard check fails. Safe to re-run any number of times.

.PARAMETER ConfigPath
    Path to the same JSON config used at deploy time (approvedBluetoothDevices[]).

.PARAMETER ParentPolicyDisplayName
    Display name of the parent macOSCustomConfiguration object. Defaults to this scenario's
    standard parent name (or -ConfigPath's parentPolicyDisplayName if set).

.PARAMETER GraphBaseUri
    Graph base URI. Defaults to 'https://graph.microsoft.com/v1.0'.

.EXAMPLE
    Connect-MgGraph -ClientId $AppId -TenantId $TenantId -CertificateThumbprint $Thumbprint
    ./Test-MacBluetoothDeviceAllowlist.ps1 -ConfigPath ../deploy/config/mac-bluetooth-device-allowlist.sample.json
#>
[CmdletBinding()]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$ConfigPath = (Join-Path $PSScriptRoot '../deploy/config/mac-bluetooth-device-allowlist.sample.json'),

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

# Prerequisite GUIDs (portable-device-coverage) + this fragment's own GUIDs.
$AllBluetoothGroupId      = 'd1d2d3d4-3333-4c3c-8c3c-333333333301'
$DenyBluetoothRuleId      = 'd1d2d3d4-3333-4c3c-8c3c-333333333310'
$ApprovedBluetoothGroupId = 'd1d2d3d4-3333-4c3c-8c3c-333333333302'
$AllowBluetoothRuleId     = 'd1d2d3d4-3333-4c3c-8c3c-333333333311'

if (-not (Test-Path -LiteralPath $ConfigPath)) { throw "Config file not found: $ConfigPath" }
$cfg = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
$approvedDevices = @($cfg.approvedBluetoothDevices)
$parentDisplayName = if ($ParentPolicyDisplayName) { $ParentPolicyDisplayName } elseif ($cfg.parentPolicyDisplayName) { $cfg.parentPolicyDisplayName } else { 'Device Control (macOS) - USB Removable Media Default-Deny Allowlist' }

Assert-MgConnected
Write-Host "Validating Bluetooth device allowlist on '$parentDisplayName'..." -ForegroundColor Cyan

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

function Find-GroupById { param($Groups, $Id) $Groups | Where-Object { $_.id -eq $Id } | Select-Object -First 1 }
function Find-RuleById { param($Rules, $Id) $Rules | Where-Object { $_.id -eq $Id } | Select-Object -First 1 }

# --- Prerequisite check ---
$allBluetooth = Find-GroupById -Groups $policy.groups -Id $AllBluetoothGroupId
$denyBluetooth = Find-RuleById -Rules $policy.rules -Id $DenyBluetoothRuleId
Test-Check -Description 'Prerequisite: AllBluetoothDevices catch-all group present (from defender-device-control-usb-allowlist-macos-portable-device-coverage)' -Condition ($null -ne $allBluetooth)
Test-Check -Description 'Prerequisite: Deny-AllBluetoothDevices rule present' -Condition ($null -ne $denyBluetooth)
if (-not $allBluetooth -or -not $denyBluetooth) {
    Write-Host "`nCannot continue - deploy defender-device-control-usb-allowlist-macos-portable-device-coverage first. $script:failures check(s) failed." -ForegroundColor Red
    exit 1
}

$approvedGroup = Find-GroupById -Groups $policy.groups -Id $ApprovedBluetoothGroupId
$allowRule = Find-RuleById -Rules $policy.rules -Id $AllowBluetoothRuleId
$hasExclude = $denyBluetooth.excludeGroups -contains $ApprovedBluetoothGroupId

if ($approvedDevices.Count -eq 1) {
    $d = $approvedDevices[0]
    Test-Check -Description 'ApprovedBluetoothDevice group present' -Condition ($null -ne $approvedGroup)
    if ($approvedGroup) {
        $clauseTypes = @($approvedGroup.query.clauses | ForEach-Object { $_.'$type' })
        Test-Check -Description "ApprovedBluetoothDevice group query is an AND of primaryId+vendorId+productId ('`$type': 'and')" -Condition ($approvedGroup.query.'$type' -eq 'and' -and $clauseTypes -contains 'primaryId' -and $clauseTypes -contains 'vendorId' -and $clauseTypes -contains 'productId')
        $vendorClause = $approvedGroup.query.clauses | Where-Object { $_.'$type' -eq 'vendorId' } | Select-Object -First 1
        $productClause = $approvedGroup.query.clauses | Where-Object { $_.'$type' -eq 'productId' } | Select-Object -First 1
        Test-Check -Description "ApprovedBluetoothDevice group vendorId matches config ('$($d.vendorId)')" -Condition ($vendorClause.value -eq $d.vendorId)
        Test-Check -Description "ApprovedBluetoothDevice group productId matches config ('$($d.productId)')" -Condition ($productClause.value -eq $d.productId)
    }
    Test-Check -Description 'Allow-ApprovedBluetoothDevice rule present (allow + auditAllow entries)' -Condition ($null -ne $allowRule -and ($allowRule.entries.enforcement.'$type' -contains 'allow') -and ($allowRule.entries.enforcement.'$type' -contains 'auditAllow'))
    if ($allowRule) {
        $allowAccess = @($allowRule.entries[0].access)
        Test-Check -Description 'Allow-ApprovedBluetoothDevice access list = [download_files_from_device, send_files_to_device]' -Condition (($allowAccess -contains 'download_files_from_device') -and ($allowAccess -contains 'send_files_to_device'))
    }

    if ($hasExclude) {
        Test-Check -Description 'Deny-AllBluetoothDevices excludeGroups references ApprovedBluetoothDevice' -Condition $true
    }
    elseif ($null -ne $approvedGroup -and $null -ne $allowRule) {
        # Drift: the allowlist artifacts exist but the shared deny rule's exclusion was stripped -
        # almost certainly the documented ordering hazard, not "never deployed."
        Test-Check -Description "Deny-AllBluetoothDevices excludeGroups references ApprovedBluetoothDevice - MISSING. Group/allow-rule exist but the exclusion was dropped, most likely because defender-device-control-usb-allowlist-macos-portable-device-coverage's Add-MacPortableDeviceCoverage.ps1 -Force ran after this fragment (README.md Section 11 known ordering hazard). Remediation: re-run deploy/Add-MacBluetoothDeviceAllowlist.ps1." -Condition $false
    }
    else {
        Test-Check -Description 'Deny-AllBluetoothDevices excludeGroups references ApprovedBluetoothDevice' -Condition $false
    }
}
else {
    Test-Check -Description 'No ApprovedBluetoothDevice group (empty config -> pure default-deny, no exceptions)' -Condition ($null -eq $approvedGroup)
    Test-Check -Description 'No Allow-ApprovedBluetoothDevice rule (empty config -> pure default-deny, no exceptions)' -Condition ($null -eq $allowRule)
    Test-Check -Description 'Deny-AllBluetoothDevices has no excludeGroups (empty config -> pure default-deny)' -Condition (-not $hasExclude)
}

Test-Check -Description "Deny-AllBluetoothDevices deny+auditDeny entries unchanged (entry `$type = bluetoothDevice)" -Condition ($denyBluetooth.entries.'$type' -contains 'bluetoothDevice' -and ($denyBluetooth.entries.enforcement.'$type' -contains 'deny') -and ($denyBluetooth.entries.enforcement.'$type' -contains 'auditDeny'))

# --- Sibling coverage must be unaffected ---
$allApple = $policy.groups | Where-Object { $_.name -eq 'AllAppleDevices' }
$allPortable = $policy.groups | Where-Object { $_.name -eq 'AllPortableDevices' }
$parentApprovedGroup = $policy.groups | Where-Object { $_.name -eq 'ApprovedBackupDrives' }
$parentCatchAllGroup = $policy.groups | Where-Object { $_.name -eq 'AllRemovableStorage' }
Test-Check -Description "Sibling fragment's AllAppleDevices group still present (unaffected by this fragment)" -Condition ($null -ne $allApple) -Warn
Test-Check -Description "Sibling fragment's AllPortableDevices group still present (unaffected by this fragment)" -Condition ($null -ne $allPortable) -Warn
Test-Check -Description "Parent's ApprovedBackupDrives group is still present (unaffected by this fragment)" -Condition ($null -ne $parentApprovedGroup) -Warn
Test-Check -Description "Parent's AllRemovableStorage group is still present (unaffected by this fragment)" -Condition ($null -ne $parentCatchAllGroup) -Warn
Test-Check -Description "settings.features.bluetoothDevice.disable = false (owned by the prerequisite fragment, unaffected)" -Condition ($policy.settings.features.bluetoothDevice.disable -eq $false) -Warn
Test-Check -Description "settings.global.defaultEnforcement = 'deny' (fail-closed, unaffected)" -Condition ($policy.settings.global.defaultEnforcement -eq 'deny') -Warn

Write-Host "`n$(if ($script:failures -eq 0) { 'All hard checks passed.' } else { "$script:failures hard check(s) failed." })" `
    -ForegroundColor $(if ($script:failures -eq 0) { 'Green' } else { 'Red' })

if ($script:failures -gt 0) { exit 1 }
```