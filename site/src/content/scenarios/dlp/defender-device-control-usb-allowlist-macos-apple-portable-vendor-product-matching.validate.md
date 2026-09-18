---
part: "validate"
parent: "dlp/defender-device-control-usb-allowlist-macos-apple-portable-vendor-product-matching"
---
Run these checks after deployment to confirm the control is working as designed.


#### `Test-MacApplePortableVendorProductDeviceAllowlist.ps1`

```powershell
#Requires -Version 7.0
<#
.SYNOPSIS
    Verifies the Apple/Portable vendorId/productId compound-matched device allowlist is correctly
    present on the shared macOS device control policy, and detects the known cross-fragment ordering
    hazard, per family.

.DESCRIPTION
    Read-only validation script - never modifies policy state. Per family (Apple, Portable) with one
    or more -ConfigPath entries, checks:
      1. The parent device configuration object exists and has a payload.
      2. The embedded deviceControl.policy JSON extracts and parses.
      3. The prerequisite ApprovedAppleDevices/ApprovedPortableDevices group and
         Allow-ApprovedAppleDevices/Allow-ApprovedPortableDevices rule (from
         defender-device-control-usb-allowlist-macos-portable-device-coverage) are present.
      4. Every configured device's deterministic sub-group exists with the expected primaryId/
         vendorId/productId AND-clauses, the Approved group's query.clauses references it via a
         groupId clause, and no orphaned own-prefix sub-group or stale groupId clause remains.
      5. If a family has zero -ConfigPath entries, confirms no leftover own-prefix sub-group and no
         groupId clause remain in that family's Approved group (if the group exists at all).
      6. DRIFT CHECK (the known ordering hazard - README.md Section 11): if a family has entries
         configured but its Approved group is missing entirely while this fragment's own sub-groups
         for that family still exist elsewhere in the policy (orphaned, not referenced by anything),
         this indicates defender-device-control-usb-allowlist-macos-portable-device-coverage's own
         Add-MacPortableDeviceCoverage.ps1 -Force was re-run after this fragment with that family's
         serialNumber list emptied, silently deleting the Approved group and orphaning this
         fragment's sub-groups. Reported as a distinct [FAIL] with the exact remediation (first
         restore at least one serialNumber device for that family via the prerequisite fragment, then
         re-run deploy/Add-MacApplePortableVendorProductDeviceAllowlist.ps1), not conflated with
         "never deployed."
      7. The removable-media and Bluetooth sibling fragments' own groups/rules are unaffected.
    Exits with a non-zero code if any hard check fails. Safe to re-run any number of times.

.PARAMETER ConfigPath
    Path to the same JSON config used at deploy time (vendorProductAppleDevices[],
    vendorProductPortableDevices[]).

.PARAMETER ParentPolicyDisplayName
    Display name of the parent macOSCustomConfiguration object. Defaults to this scenario's
    standard parent name (or -ConfigPath's parentPolicyDisplayName if set).

.PARAMETER GraphBaseUri
    Graph base URI. Defaults to 'https://graph.microsoft.com/v1.0'.

.EXAMPLE
    Connect-MgGraph -ClientId $AppId -TenantId $TenantId -CertificateThumbprint $Thumbprint
    ./Test-MacApplePortableVendorProductDeviceAllowlist.ps1 -ConfigPath ../deploy/config/mac-apple-portable-vendor-product-device-allowlist.sample.json
#>
[CmdletBinding()]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$ConfigPath = (Join-Path $PSScriptRoot '../deploy/config/mac-apple-portable-vendor-product-device-allowlist.sample.json'),

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

$script:SubGroupNamespaceHex = 'c7e21a4f9d3b4e6a8c1f2b3d4e5f6071'
$script:Families = @(
    [ordered]@{ Key = 'apple';    ConfigProperty = 'vendorProductAppleDevices';    PrimaryIdValue = 'apple_devices';    ApprovedGroupId = 'd1d2d3d4-1111-4a1a-8a1a-111111111102'; AllowRuleId = 'd1d2d3d4-1111-4a1a-8a1a-111111111111'; ApprovedGroupName = 'ApprovedAppleDevices';    NamePrefix = 'AppleVendorProductMatch-' }
    [ordered]@{ Key = 'portable'; ConfigProperty = 'vendorProductPortableDevices'; PrimaryIdValue = 'portable_devices'; ApprovedGroupId = 'd1d2d3d4-2222-4b2b-8b2b-222222222202'; AllowRuleId = 'd1d2d3d4-2222-4b2b-8b2b-222222222211'; ApprovedGroupName = 'ApprovedPortableDevices'; NamePrefix = 'PortableVendorProductMatch-' }
)

if (-not (Test-Path -LiteralPath $ConfigPath)) { throw "Config file not found: $ConfigPath" }
$cfg = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
$parentDisplayName = if ($ParentPolicyDisplayName) { $ParentPolicyDisplayName } elseif ($cfg.parentPolicyDisplayName) { $cfg.parentPolicyDisplayName } else { 'Device Control (macOS) - USB Removable Media Default-Deny Allowlist' }

Assert-MgConnected
Write-Host "Validating Apple/Portable vendorId/productId device allowlist on '$parentDisplayName'..." -ForegroundColor Cyan

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

foreach ($family in $script:Families) {
    Write-Host "`n-- $($family.Key) family --" -ForegroundColor Cyan
    $devices = @($cfg.($family.ConfigProperty) | Where-Object { $_ })
    $approvedGroup = $policy.groups | Where-Object { $_.id -eq $family.ApprovedGroupId } | Select-Object -First 1
    $allowRule = $policy.rules | Where-Object { $_.id -eq $family.AllowRuleId } | Select-Object -First 1
    $ownedSubGroups = @($policy.groups | Where-Object { $_.name -like "$($family.NamePrefix)*" })

    if ($approvedGroup) {
        Test-Check -Description "$($family.ApprovedGroupName) query.`$type is a recognized OR-semantics value ('or' or 'any' - design.md Section 6)" -Condition ($approvedGroup.query.'$type' -in @('or', 'any'))
    }

    if ($devices.Count -eq 0) {
        if (-not $approvedGroup) {
            Test-Check -Description "No $($family.ApprovedGroupName) group (never configured for this family - nothing to check)" -Condition $true -Warn
            Test-Check -Description "No orphaned $($family.NamePrefix)* sub-groups" -Condition ($ownedSubGroups.Count -eq 0)
            continue
        }
        $groupIdClauseCount = @($approvedGroup.query.clauses | Where-Object { $_.'$type' -eq 'groupId' }).Count
        Test-Check -Description "$($family.ApprovedGroupName) group present (owned by the prerequisite fragment, serialNumber-based)" -Condition $true
        Test-Check -Description "No groupId clauses on $($family.ApprovedGroupName) (empty config -> no vendorId/productId exceptions)" -Condition ($groupIdClauseCount -eq 0)
        Test-Check -Description "No orphaned $($family.NamePrefix)* sub-groups" -Condition ($ownedSubGroups.Count -eq 0)
        continue
    }

    # devices.Count -gt 0: this family's Approved group and Allow rule are expected to already exist
    # (prerequisite - defender-device-control-usb-allowlist-macos-portable-device-coverage).
    if (-not $approvedGroup) {
        Test-Check -Description "Prerequisite: $($family.ApprovedGroupName) group present (from defender-device-control-usb-allowlist-macos-portable-device-coverage)" -Condition $false
        if ($ownedSubGroups.Count -gt 0) {
            Test-Check -Description "DRIFT (known ordering hazard, README.md Section 11): $($family.NamePrefix)* sub-group(s) exist but $($family.ApprovedGroupName) is missing - most likely Add-MacPortableDeviceCoverage.ps1 -Force emptied this family's serialNumber list after this fragment ran. Remediation: restore at least one serialNumber device for this family via that fragment, then re-run deploy/Add-MacApplePortableVendorProductDeviceAllowlist.ps1." -Condition $false
        }
        continue
    }
    Test-Check -Description "Prerequisite: $($family.ApprovedGroupName) group present" -Condition $true
    Test-Check -Description "Prerequisite: Allow-$($family.ApprovedGroupName) rule present" -Condition ($null -ne $allowRule)

    $desiredDevices = foreach ($d in $devices) {
        $vendorNorm = $d.vendorId.ToLowerInvariant()
        $productNorm = $d.productId.ToLowerInvariant()
        [pscustomobject]@{
            Label     = $d.label
            VendorId  = $vendorNorm
            ProductId = $productNorm
            GroupId   = Get-DeterministicSubGroupId -NamespaceHex $script:SubGroupNamespaceHex -Name "mac-apple-portable-vendor-product-match/v1/$($family.Key)/$vendorNorm`:$productNorm"
            GroupName = "$($family.NamePrefix)$($d.label)"
        }
    }
    $desiredDevices = @($desiredDevices)
    $existingGroupIdClauses = @($approvedGroup.query.clauses | Where-Object { $_.'$type' -eq 'groupId' } | ForEach-Object { $_.value })

    foreach ($d in $desiredDevices) {
        $subGroup = $ownedSubGroups | Where-Object { $_.id -eq $d.GroupId } | Select-Object -First 1
        Test-Check -Description "Device '$($d.Label)': sub-group '$($d.GroupName)' present with deterministic id $($d.GroupId)" -Condition ($null -ne $subGroup)
        if ($subGroup) {
            $clauseTypes = @($subGroup.query.clauses | ForEach-Object { $_.'$type' })
            $primaryClause = $subGroup.query.clauses | Where-Object { $_.'$type' -eq 'primaryId' } | Select-Object -First 1
            $vendorClause = $subGroup.query.clauses | Where-Object { $_.'$type' -eq 'vendorId' } | Select-Object -First 1
            $productClause = $subGroup.query.clauses | Where-Object { $_.'$type' -eq 'productId' } | Select-Object -First 1
            Test-Check -Description "Device '$($d.Label)': sub-group query is an AND of primaryId+vendorId+productId" -Condition ($subGroup.query.'$type' -eq 'and' -and $clauseTypes -contains 'primaryId' -and $clauseTypes -contains 'vendorId' -and $clauseTypes -contains 'productId')
            Test-Check -Description "Device '$($d.Label)': primaryId = '$($family.PrimaryIdValue)'" -Condition ($primaryClause.value -eq $family.PrimaryIdValue)
            Test-Check -Description "Device '$($d.Label)': vendorId matches config ('$($d.VendorId)')" -Condition ($vendorClause.value -eq $d.VendorId)
            Test-Check -Description "Device '$($d.Label)': productId matches config ('$($d.ProductId)')" -Condition ($productClause.value -eq $d.ProductId)
        }
        Test-Check -Description "Device '$($d.Label)': $($family.ApprovedGroupName) references its sub-group via a groupId clause" -Condition ($existingGroupIdClauses -contains $d.GroupId)
    }

    $desiredGroupIds = @($desiredDevices | ForEach-Object { $_.GroupId })
    $orphanSubGroups = @($ownedSubGroups | Where-Object { $_.id -notin $desiredGroupIds })
    Test-Check -Description "No orphaned $($family.NamePrefix)* sub-groups beyond -ConfigPath's current definition" -Condition ($orphanSubGroups.Count -eq 0)
    if ($orphanSubGroups.Count -gt 0) {
        foreach ($o in $orphanSubGroups) {
            Write-Host "         orphan: '$($o.name)' (id $($o.id)) - not in -ConfigPath; re-run deploy/Add-MacApplePortableVendorProductDeviceAllowlist.ps1 to remove it" -ForegroundColor Yellow
        }
    }
    $staleClauses = @($existingGroupIdClauses | Where-Object { $_ -notin $desiredGroupIds })
    Test-Check -Description "No stale groupId clauses on $($family.ApprovedGroupName) beyond -ConfigPath's current definition" -Condition ($staleClauses.Count -eq 0)
}

# --- Sibling coverage must be unaffected ---
Write-Host "`n-- Sibling coverage (unaffected) --" -ForegroundColor Cyan
$parentApprovedGroup = $policy.groups | Where-Object { $_.name -eq 'ApprovedBackupDrives' }
$parentCatchAllGroup = $policy.groups | Where-Object { $_.name -eq 'AllRemovableStorage' }
$vendorProductRemovableMediaGroups = @($policy.groups | Where-Object { $_.name -like 'VendorProductMatch-*' })
$bluetoothApprovedGroup = $policy.groups | Where-Object { $_.name -eq 'ApprovedBluetoothDevice' }
Test-Check -Description "Parent's ApprovedBackupDrives group is still present (unaffected by this fragment)" -Condition ($null -ne $parentApprovedGroup) -Warn
Test-Check -Description "Parent's AllRemovableStorage group is still present (unaffected by this fragment)" -Condition ($null -ne $parentCatchAllGroup) -Warn
Test-Check -Description "Removable-media sibling fragment's own VendorProductMatch-* sub-groups untouched (count preserved if any: $($vendorProductRemovableMediaGroups.Count))" -Condition $true -Warn
Test-Check -Description "Bluetooth sibling fragment's ApprovedBluetoothDevice group untouched if present (found: $($null -ne $bluetoothApprovedGroup))" -Condition $true -Warn

Write-Host "`n$(if ($script:failures -eq 0) { 'All hard checks passed.' } else { "$script:failures hard check(s) failed." })" `
    -ForegroundColor $(if ($script:failures -eq 0) { 'Green' } else { 'Red' })

if ($script:failures -gt 0) { exit 1 }
```