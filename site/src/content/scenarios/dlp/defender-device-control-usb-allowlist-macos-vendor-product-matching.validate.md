---
part: "validate"
parent: "dlp/defender-device-control-usb-allowlist-macos-vendor-product-matching"
---
Run these checks after deployment to confirm the control is working as designed.


#### `Test-MacVendorProductDeviceAllowlist.ps1`

```powershell
#Requires -Version 7.0
<#
.SYNOPSIS
    Verifies the vendorId/productId device allowlist is correctly present on the shared macOS
    device control policy, and that each configured device's deterministic group id and OR-branch
    into ApprovedBackupDrives are exactly as -ConfigPath specifies.

.DESCRIPTION
    Read-only validation script - never modifies policy state. Checks:
      1. The parent device configuration object exists and has a payload.
      2. The embedded deviceControl.policy JSON extracts and parses.
      3. The prerequisite ApprovedBackupDrives group (from
         defender-device-control-usb-allowlist-macos) is present with query.$type "any".
      4. For every -ConfigPath vendorProductDevices[] entry: a "VendorProductMatch-<label>" group
         exists with the expected deterministic id (recomputed independently by this script - not
         merely re-reading whatever id deploy wrote), an "and" query of
         primaryId=removable_media_devices + vendorId + productId matching the config, and
         ApprovedBackupDrives' query.clauses contains a matching "groupId" clause.
      5. No unexpected "VendorProductMatch-*" group exists beyond what -ConfigPath specifies (stale/
         orphaned sub-group detection), and no stale "groupId" clause on ApprovedBackupDrives
         references a group id no longer in -ConfigPath.
      6. ApprovedBackupDrives' pre-existing serialNumber clauses (owned by the parent script) are
         still present and unchanged in count.
      7. The parent's AllRemovableStorage catch-all group and both of its rules
         (Allow-ApprovedBackupDrives, Deny-AllOtherRemovableStorage) are still present, unaffected by
         this fragment - confirming this fragment needed no rule changes (design.md Section 2).
    Exits with a non-zero code if any hard check fails. Safe to re-run any number of times.

.PARAMETER ConfigPath
    Path to the same JSON config used at deploy time (vendorProductDevices[]).

.PARAMETER ParentPolicyDisplayName
    Display name of the parent macOSCustomConfiguration object. Defaults to this scenario's
    standard parent name (or -ConfigPath's parentPolicyDisplayName if set).

.PARAMETER GraphBaseUri
    Graph base URI. Defaults to 'https://graph.microsoft.com/v1.0'.

.EXAMPLE
    Connect-MgGraph -ClientId $AppId -TenantId $TenantId -CertificateThumbprint $Thumbprint
    ./Test-MacVendorProductDeviceAllowlist.ps1 -ConfigPath ../deploy/config/mac-vendor-product-device-allowlist.sample.json
#>
[CmdletBinding()]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$ConfigPath = (Join-Path $PSScriptRoot '../deploy/config/mac-vendor-product-device-allowlist.sample.json'),

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

function Get-DeterministicSubGroupId {
    # Same RFC 4122 Section 4.3 version-5 UUID derivation as deploy/Add-MacVendorProductDeviceAllowlist.ps1
    # - see that script's .NOTES for the algorithm citation and reference-implementation cross-check.
    param([Parameter(Mandatory)][string]$NamespaceHex, [Parameter(Mandatory)][string]$Name)
    $nsBytes = [byte[]](0..15 | ForEach-Object { [Convert]::ToByte($NamespaceHex.Substring($_ * 2, 2), 16) })
    $nameBytes = [System.Text.Encoding]::UTF8.GetBytes($Name)
    $toHash = [byte[]]($nsBytes + $nameBytes)
    $sha1 = [System.Security.Cryptography.SHA1]::Create()
    try { $hash = $sha1.ComputeHash($toHash) } finally { $sha1.Dispose() }
    $b = [byte[]]$hash[0..15]
    $b[6] = [byte](($b[6] -band 0x0F) -bor 0x50)
    $b[8] = [byte](($b[8] -band 0x3F) -bor 0x80)
    $hex = -join ($b | ForEach-Object { $_.ToString('x2') })
    return '{0}-{1}-{2}-{3}-{4}' -f $hex.Substring(0, 8), $hex.Substring(8, 4), $hex.Substring(12, 4), $hex.Substring(16, 4), $hex.Substring(20, 12)
}

$ApprovedBackupDrivesGroupId = '22222222-bbbb-4ccc-8ddd-222222222222'
$AllRemovableGroupId         = '11111111-aaaa-4bbb-8ccc-111111111111'
$AllowRuleId                 = '33333333-cccc-4ddd-8eee-333333333333'
$DenyRuleId                  = '44444444-dddd-4eee-8fff-444444444444'
$SubGroupNamespaceHex        = '8f3a2b108f2e4c4a9b8b2f1a6c9d7e10'
$NamePrefix                  = 'VendorProductMatch-'

if (-not (Test-Path -LiteralPath $ConfigPath)) { throw "Config file not found: $ConfigPath" }
$cfg = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
# Where-Object filters out $null - see deploy/Add-MacVendorProductDeviceAllowlist.ps1's identical
# comment: @($cfg.vendorProductDevices) alone would be a 1-element array of $null, not empty, when
# the JSON key is omitted entirely.
$configDevices = @($cfg.vendorProductDevices | Where-Object { $_ })
$parentDisplayName = if ($ParentPolicyDisplayName) { $ParentPolicyDisplayName } elseif ($cfg.parentPolicyDisplayName) { $cfg.parentPolicyDisplayName } else { 'Device Control (macOS) - USB Removable Media Default-Deny Allowlist' }

$desiredDevices = foreach ($d in $configDevices) {
    $vendorNorm = $d.vendorId.ToLowerInvariant()
    $productNorm = $d.productId.ToLowerInvariant()
    [pscustomobject]@{
        Label     = $d.label
        VendorId  = $vendorNorm
        ProductId = $productNorm
        GroupId   = Get-DeterministicSubGroupId -NamespaceHex $SubGroupNamespaceHex -Name "mac-vendor-product-match/v1/$vendorNorm`:$productNorm"
        GroupName = "$NamePrefix$($d.label)"
    }
}

Assert-MgConnected
Write-Host "Validating vendorId/productId device allowlist on '$parentDisplayName' ($($desiredDevices.Count) device(s) in -ConfigPath)..." -ForegroundColor Cyan

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
function Find-RuleById  { param($Rules, $Id)  $Rules  | Where-Object { $_.id -eq $Id } | Select-Object -First 1 }

# --- Prerequisite check ---
$approvedGroup = Find-GroupById -Groups $policy.groups -Id $ApprovedBackupDrivesGroupId
Test-Check -Description 'Prerequisite: ApprovedBackupDrives group present (from defender-device-control-usb-allowlist-macos)' -Condition ($null -ne $approvedGroup)
if (-not $approvedGroup) {
    Write-Host "`nCannot continue - deploy defender-device-control-usb-allowlist-macos first. $script:failures check(s) failed." -ForegroundColor Red
    exit 1
}
Test-Check -Description "ApprovedBackupDrives query.`$type is 'any'" -Condition ($approvedGroup.query.'$type' -eq 'any')

$groupIdClauses = @($approvedGroup.query.clauses | Where-Object { $_.'$type' -eq 'groupId' })
$serialClauses  = @($approvedGroup.query.clauses | Where-Object { $_.'$type' -eq 'serialNumber' })
Test-Check -Description "ApprovedBackupDrives has $($serialClauses.Count) pre-existing serialNumber clause(s) (owned by the parent script, unaffected by this fragment)" -Condition $true -Warn

# --- Per-device checks ---
foreach ($d in $desiredDevices) {
    $group = Find-GroupById -Groups $policy.groups -Id $d.GroupId
    Test-Check -Description "Device '$($d.Label)': group '$($d.GroupName)' present with the expected deterministic id ($($d.GroupId))" -Condition ($null -ne $group)
    if ($group) {
        $clauseTypes = @($group.query.clauses | ForEach-Object { $_.'$type' })
        Test-Check -Description "Device '$($d.Label)': group query is an AND of primaryId=removable_media_devices + vendorId + productId" -Condition ($group.query.'$type' -eq 'and' -and $clauseTypes -contains 'primaryId' -and $clauseTypes -contains 'vendorId' -and $clauseTypes -contains 'productId')
        $primaryClause = $group.query.clauses | Where-Object { $_.'$type' -eq 'primaryId' } | Select-Object -First 1
        $vendorClause  = $group.query.clauses | Where-Object { $_.'$type' -eq 'vendorId' }  | Select-Object -First 1
        $productClause = $group.query.clauses | Where-Object { $_.'$type' -eq 'productId' } | Select-Object -First 1
        Test-Check -Description "Device '$($d.Label)': primaryId = removable_media_devices" -Condition ($primaryClause.value -eq 'removable_media_devices')
        Test-Check -Description "Device '$($d.Label)': vendorId matches config ('$($d.VendorId)')" -Condition ($vendorClause.value -eq $d.VendorId)
        Test-Check -Description "Device '$($d.Label)': productId matches config ('$($d.ProductId)')" -Condition ($productClause.value -eq $d.ProductId)
    }
    $hasClause = $groupIdClauses.value -contains $d.GroupId
    Test-Check -Description "Device '$($d.Label)': ApprovedBackupDrives has a groupId clause referencing this device's group" -Condition $hasClause
}

# --- Orphan / drift detection ---
$desiredGroupIds = @($desiredDevices | ForEach-Object { $_.GroupId })
$ownedGroups = @($policy.groups | Where-Object { $_.name -like "$($NamePrefix)*" })
$unexpectedGroups = @($ownedGroups | Where-Object { $_.id -notin $desiredGroupIds })
Test-Check -Description 'No orphaned VendorProductMatch-* group beyond -ConfigPath (stale sub-group cleanup)' -Condition ($unexpectedGroups.Count -eq 0)
foreach ($og in $unexpectedGroups) {
    Write-Host "    -> orphaned group found: '$($og.name)' (id $($og.id)) - not in -ConfigPath. Re-run deploy/Add-MacVendorProductDeviceAllowlist.ps1 to reconcile." -ForegroundColor Red
}
$unexpectedClauses = @($groupIdClauses | Where-Object { $_.value -notin $desiredGroupIds })
Test-Check -Description 'No stale groupId clause on ApprovedBackupDrives referencing a removed device' -Condition ($unexpectedClauses.Count -eq 0)

# --- Sibling/parent artifacts must be unaffected ---
$allRemovable = Find-GroupById -Groups $policy.groups -Id $AllRemovableGroupId
$allowRule = Find-RuleById -Rules $policy.rules -Id $AllowRuleId
$denyRule  = Find-RuleById -Rules $policy.rules -Id $DenyRuleId
Test-Check -Description "Parent's AllRemovableStorage catch-all group still present (unaffected by this fragment)" -Condition ($null -ne $allRemovable) -Warn
Test-Check -Description "Parent's Allow-ApprovedBackupDrives rule still present, unchanged (this fragment needed no rule edits)" -Condition ($null -ne $allowRule -and $allowRule.includeGroups -contains $ApprovedBackupDrivesGroupId) -Warn
Test-Check -Description "Parent's Deny-AllOtherRemovableStorage rule still present, unchanged (this fragment needed no rule edits)" -Condition ($null -ne $denyRule -and $denyRule.excludeGroups -contains $ApprovedBackupDrivesGroupId) -Warn

Write-Host "`n$(if ($script:failures -eq 0) { 'All hard checks passed.' } else { "$script:failures hard check(s) failed." })" `
    -ForegroundColor $(if ($script:failures -eq 0) { 'Green' } else { 'Red' })

if ($script:failures -gt 0) { exit 1 }
```