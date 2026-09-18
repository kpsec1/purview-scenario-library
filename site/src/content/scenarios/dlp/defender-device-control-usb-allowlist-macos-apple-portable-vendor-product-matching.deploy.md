---
part: "deploy"
parent: "dlp/defender-device-control-usb-allowlist-macos-apple-portable-vendor-product-matching"
---
The scripts and configuration below deploy this scenario. Review them, then run in order — each is designed to be idempotent and has a matching rollback.


#### `Add-MacApplePortableVendorProductDeviceAllowlist.ps1`

```powershell
#Requires -Version 7.0
<#
.SYNOPSIS
    Adds vendorId+productId compound-matched approved-device exceptions to the existing
    "ApprovedAppleDevices" and/or "ApprovedPortableDevices" groups inside the shared
    macOSCustomConfiguration object, for approved Apple/Portable devices that have no readable
    serial number.

.DESCRIPTION
    scenarios/dlp/defender-device-control-usb-allowlist-macos-portable-device-coverage matches
    approved Apple and Portable devices by serialNumber only (README.md Section 6 there), the same
    deliberate scope boundary its own parent scenario already carries for removable media. This
    script closes that gap for the Apple and Portable families the same way
    defender-device-control-usb-allowlist-macos-vendor-product-matching already closed it for
    removable media: a second, independent matching mechanism - vendorId+productId compound
    matching - added as additional OR-branches of the SAME "ApprovedAppleDevices"/
    "ApprovedPortableDevices" groups, never a competing group or a new rule.

    This script does NOT create a new Intune profile, and does NOT create the "AllAppleDevices"/
    "AllPortableDevices" catch-all groups, the "Deny-AllOtherAppleDevices"/
    "Deny-AllOtherPortableDevices" rules, or (this is the one prerequisite this fragment does
    require and the sibling removable-media fragment does not) the "ApprovedAppleDevices"/
    "ApprovedPortableDevices" groups and "Allow-ApprovedAppleDevices"/"Allow-ApprovedPortableDevices"
    rules themselves - all of those are conditional on
    defender-device-control-usb-allowlist-macos-portable-device-coverage's own -ConfigPath already
    having at least one serialNumber device configured for a family (that fragment's
    design.md/README.md; see this fragment's own README.md Section 3 and design.md Section 3 for why
    this script deliberately does not attempt to create either Approved group/Allow rule pair from a
    zero-serialNumber starting state).

    Each family (Apple, Portable) is reconciled independently - a tenant can configure
    vendorId/productId devices for Apple only, Portable only, both, or neither in one run.

    What this script adds/reconciles, per -ConfigPath entry, per family:
      1. One per-device sub-group, "AppleVendorProductMatch-<label>" or
         "PortableVendorProductMatch-<label>" - $type: "and", clauses: [primaryId=<family>,
         vendorId=<config>, productId=<config>] - the same AND-clause shape Microsoft's own
         deny_all_bluetooth_devices_except_samsung.json sample uses for its single-device
         vendorId+productId exception group, already generalized once in this repository (to
         removable_media_devices, by the sibling vendor-product-matching fragment) and generalized a
         second time here (to apple_devices/portable_devices) - see .NOTES for the VERIFY this
         carries.
      2. A "groupId" clause referencing that sub-group's id, appended to the EXISTING
         "ApprovedAppleDevices"/"ApprovedPortableDevices" group's query.clauses array (query.$type
         is read from the live object and left unchanged). Every serialNumber clause already in that
         array (owned by the portable-device-coverage fragment) is reproduced byte-for-byte
         unchanged - this script only adds/removes its own groupId clauses, never serialNumber
         clauses.

    Because the prerequisite fragment's "Allow-ApprovedAppleDevices"/"Allow-ApprovedPortableDevices"
    rules already reference the Approved group's id directly (via includeGroups), and the
    "Deny-AllOtherAppleDevices"/"Deny-AllOtherPortableDevices" rules already reference it via
    excludeGroups, adding a device here requires NO new rule and NO edit to any existing rule - the
    identical "extend the group, not the rule" trade-off the vendor-product-matching sibling
    fragment already established for removable media (design.md Section 2).

    DETERMINISTIC PER-DEVICE GUIDs: same RFC 4122 Section 4.3 version-5 (name-based, SHA-1) UUID
    technique as the vendor-product-matching sibling fragment, with a namespace constant and hash
    input string unique to THIS fragment (never reused from any other fragment in this repository -
    see design.md Section 4) - Apple and Portable devices are hashed under different name strings
    even if a vendorId+productId pair were ever reused across both families, so the two families'
    sub-groups can never collide.

    KNOWN CROSS-FRAGMENT ORDERING HAZARD (see README.md Section 11, design.md Section 7): if
    defender-device-control-usb-allowlist-macos-portable-device-coverage's own
    Add-MacPortableDeviceCoverage.ps1 -Force is re-run AFTER this script, it unconditionally rebuilds
    whichever of "ApprovedAppleDevices"/"ApprovedPortableDevices" it touches from ITS OWN
    -ConfigPath's serialNumber list only (that script has no awareness this fragment exists) -
    silently dropping this fragment's groupId clauses, and removing the group and its Allow rule
    entirely if that other config's serialNumber list for the family is empty. If that happens,
    re-run THIS script again to restore the vendorId/productId exceptions -
    validate/Test-MacApplePortableVendorProductDeviceAllowlist.ps1 detects and flags this specific
    drift condition per family.

    Idempotent per family: reads the live policy JSON, computes the desired sub-group set from
    -ConfigPath, diffs it against the sub-groups already present (identified by this fragment's own
    family-specific name prefix - never touching a group with a different prefix, including the
    removable-media sibling fragment's own "VendorProductMatch-" groups or the Bluetooth sibling's
    "ApprovedBluetoothDevice" group), and reconciles: adds missing sub-groups, removes sub-groups no
    longer in -ConfigPath (and their groupId clause), and adds/removes groupId clauses on the
    relevant Approved group to match. Without -Force, an already-fully-reconciled policy is reported
    and left untouched; a partial/drifted state is still reconciled (this script never requires
    -Force to self-heal drift, only to re-write an already-correct state).

.PARAMETER ConfigPath
    Path to the JSON config (parentPolicyDisplayName, vendorProductAppleDevices[] - zero or more,
    vendorProductPortableDevices[] - zero or more). Defaults to the sibling
    'config/mac-apple-portable-vendor-product-device-allowlist.sample.json' - copy and edit it.

.PARAMETER GraphBaseUri
    Graph base URI. Defaults to 'https://graph.microsoft.com/v1.0'.

.PARAMETER Force
    Reconcile even if the live policy already fully matches -ConfigPath's current definition.

.PARAMETER WhatIf
    Standard PowerShell ShouldProcess dry-run. Reports the PATCH that would be made without calling
    any mutating Graph endpoint.

.EXAMPLE
    Connect-MgGraph -ClientId $AppId -TenantId $TenantId -CertificateThumbprint $Thumbprint
    ./Add-MacApplePortableVendorProductDeviceAllowlist.ps1 -ConfigPath ./config/my-tenant.json -WhatIf

.EXAMPLE
    ./Add-MacApplePortableVendorProductDeviceAllowlist.ps1 -ConfigPath ./config/my-tenant.json

.NOTES
    SCOPE: this script is limited to the "apple_devices" and "portable_devices" primaryId families.
    It never touches the removable-media sibling's "ApprovedBackupDrives" group or the Bluetooth
    sibling's "ApprovedBluetoothDevice" group/rule.

    PREREQUISITE DESIGN CHOICE (design.md Section 3): unlike this being buildable from a
    zero-serialNumber-device starting state, this script REFUSES to run for a family if that
    family's "ApprovedAppleDevices"/"ApprovedPortableDevices" group is not already present - it never
    creates that group or its "Allow-Approved*Devices" rule from scratch. A buyer with zero
    serialNumber-matched devices for a family who wants ONLY a vendorId/productId exception must
    first configure at least one serialNumber device for that family via
    defender-device-control-usb-allowlist-macos-portable-device-coverage's own deploy script.
    Building "create the Approved group and Allow rule from nothing" is tracked as a follow-up in
    PROGRESS.md rather than attempted here without a concrete requirement to design it against.

    vendorId/productId identify a DEVICE MODEL, not a unique physical unit - the same disclosed
    limitation as every other vendorId/productId-based exception in this repository's device-control
    family. See README.md Section 11 and reviews.md.

    No directly-confirmed Microsoft worked example pairs vendorId+productId AND-clause matching with
    the apple_devices or portable_devices primaryId families specifically - Microsoft's own published
    GitHub sample policies demonstrate this AND-clause shape only for bluetooth_devices
    (deny_all_bluetooth_devices_except_samsung.json) and a single-clause vendorId-only variant for
    removable_media_devices (deny_removable_media_except_kingston.json); audit_all_apple_devices_
    except_serial_numbers.json and deny_mobile_devices.json (fetched directly during this fragment's
    build) both use serialNumber-only / primaryId-only matching, never vendorId/productId. This
    fragment generalizes the AND-clause shape to two more primaryId families on the same basis the
    vendor-product-matching sibling fragment already generalized it to a first one (the clause TYPE
    definitions themselves are documented family-agnostically), not on a new, independently-confirmed
    worked example - flagged as VERIFY in README.md Section 11 rather than assumed.

    The RFC 4122 Section 4.3 version-5 UUID derivation this script implements (Get-
    DeterministicSubGroupId below) is copied from
    defender-device-control-usb-allowlist-macos-vendor-product-matching/deploy/
    Add-MacVendorProductDeviceAllowlist.ps1's own implementation, already independently verified
    there against Python's uuid.uuid5() reference implementation - a public, non-Microsoft-specific
    cryptographic standard, not a product fact requiring separate Microsoft Learn grounding.

    Sources (Microsoft Learn, verify before production use):
    - Device Control for macOS (Clause reference table - groupId "Match if a device is a member of
      another group... The group must be defined within the policy before the clause."; vendorId/
      productId "Four digit hexadecimal string"; primaryId values apple_devices/portable_devices;
      includeGroups AND / excludeGroups OR semantics), re-fetched during this fragment's own build:
      https://learn.microsoft.com/defender-endpoint/mac-device-control-overview
    - Sample macOS device control policies (deny_all_bluetooth_devices_except_samsung.json - the
      vendorId+productId AND-clause exception-group shape this script generalizes a second time;
      audit_all_apple_devices_except_serial_numbers.json and deny_mobile_devices.json - both
      re-fetched during this fragment's build and confirmed to use serialNumber/primaryId matching
      only, never vendorId/productId, for these two families):
      https://github.com/microsoft/mdatp-devicecontrol/blob/main/macOS/policy/samples/deny_all_bluetooth_devices_except_samsung.json
      https://github.com/microsoft/mdatp-devicecontrol/blob/main/macOS/policy/samples/audit_all_apple_devices_except_serial_numbers.json
      https://github.com/microsoft/mdatp-devicecontrol/blob/main/macOS/policy/samples/deny_mobile_devices.json
    - scenarios/dlp/defender-device-control-usb-allowlist-macos-portable-device-coverage/deploy/
      Add-MacPortableDeviceCoverage.ps1 - the prerequisite fragment that creates the
      ApprovedAppleDevices/ApprovedPortableDevices groups (conditionally) and both families' Allow/
      Deny rules this script extends; same fixed GUIDs, same regex-over-known-XML-shape extraction
      technique.
    - scenarios/dlp/defender-device-control-usb-allowlist-macos-vendor-product-matching/deploy/
      Add-MacVendorProductDeviceAllowlist.ps1 - the direct precedent this fragment generalizes from
      removable_media_devices to apple_devices/portable_devices; same deterministic-GUID technique,
      same "extend the group, not the rule" reasoning.
    - RFC 4122, Section 4.3 (name-based UUID, algorithm for creating a version-5 UUID):
      https://www.rfc-editor.org/rfc/rfc4122#section-4.3
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$ConfigPath = (Join-Path $PSScriptRoot 'config/mac-apple-portable-vendor-product-device-allowlist.sample.json'),

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$GraphBaseUri = 'https://graph.microsoft.com/v1.0',

    [Parameter()]
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

# This fragment's own fixed namespace constant for RFC 4122 Section 4.3 version-5 UUID derivation -
# distinct from every other GUID/namespace literal used by any sibling fragment in this repo. Never
# reused.
$script:SubGroupNamespaceHex = 'c7e21a4f9d3b4e6a8c1f2b3d4e5f6071'

# Prerequisite GUIDs - owned by defender-device-control-usb-allowlist-macos-portable-device-coverage.
# This script never creates these; it only reads each group/rule and reconciles the group's
# query.clauses array.
$script:Families = @(
    [ordered]@{
        Key              = 'apple'
        ConfigProperty   = 'vendorProductAppleDevices'
        PrimaryIdValue   = 'apple_devices'
        ApprovedGroupId  = 'd1d2d3d4-1111-4a1a-8a1a-111111111102'
        AllowRuleId      = 'd1d2d3d4-1111-4a1a-8a1a-111111111111'
        ApprovedGroupName = 'ApprovedAppleDevices'
        NamePrefix       = 'AppleVendorProductMatch-'
    }
    [ordered]@{
        Key              = 'portable'
        ConfigProperty   = 'vendorProductPortableDevices'
        PrimaryIdValue   = 'portable_devices'
        ApprovedGroupId  = 'd1d2d3d4-2222-4b2b-8b2b-222222222202'
        AllowRuleId      = 'd1d2d3d4-2222-4b2b-8b2b-222222222211'
        ApprovedGroupName = 'ApprovedPortableDevices'
        NamePrefix       = 'PortableVendorProductMatch-'
    }
)

function Assert-MgConnected {
    if (-not (Get-Command Invoke-MgGraphRequest -ErrorAction SilentlyContinue)) {
        throw 'Microsoft Graph PowerShell SDK not found. Install Microsoft.Graph.Authentication and Microsoft.Graph.DeviceManagement, then Connect-MgGraph.'
    }
    if (-not (Get-MgContext -ErrorAction SilentlyContinue)) {
        throw 'Not connected to Microsoft Graph. Run Connect-MgGraph (app-only certificate - see docs/automation-surface.md Section 3) first.'
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

function ConvertTo-Utf8Base64   { param([Parameter(Mandatory)][string]$Text)   [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($Text)) }
function ConvertFrom-Utf8Base64 { param([Parameter(Mandatory)][string]$Base64) [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($Base64)) }
function ConvertTo-XmlEscaped   { param([Parameter(Mandatory)][string]$Text)   $Text -replace '&', '&amp;' -replace '<', '&lt;' -replace '>', '&gt;' }
function ConvertFrom-XmlEscaped { param([Parameter(Mandatory)][string]$Text)   $Text -replace '&lt;', '<' -replace '&gt;', '>' -replace '&amp;', '&' }

function Test-FourDigitHex {
    param([string]$Value, [string]$FieldName, [string]$Label)
    if ($Value -notmatch '^[0-9A-Fa-f]{4}$') {
        throw "Device '$Label': $FieldName must be a four-digit hexadecimal string (e.g. '0951'), got '$Value'."
    }
}

function Get-DeterministicSubGroupId {
    <#
        RFC 4122 Section 4.3 version-5 (name-based, SHA-1) UUID derivation, worked entirely in raw
        hex-string/byte-array form (never round-tripped through [guid]'s byte-array constructor,
        which reorders bytes for .NET's mixed-endian internal representation) - avoids the classic
        UUID-v5-in-.NET endianness bug. Identical implementation to, and independently reusing the
        verification already performed by,
        defender-device-control-usb-allowlist-macos-vendor-product-matching/deploy/
        Add-MacVendorProductDeviceAllowlist.ps1's own Get-DeterministicSubGroupId.
    #>
    param(
        [Parameter(Mandatory)][string]$NamespaceHex,
        [Parameter(Mandatory)][string]$Name
    )
    $nsBytes = [byte[]](0..15 | ForEach-Object { [Convert]::ToByte($NamespaceHex.Substring($_ * 2, 2), 16) })
    $nameBytes = [System.Text.Encoding]::UTF8.GetBytes($Name)
    $toHash = [byte[]]($nsBytes + $nameBytes)

    $sha1 = [System.Security.Cryptography.SHA1]::Create()
    try {
        $hash = $sha1.ComputeHash($toHash)
    }
    finally {
        $sha1.Dispose()
    }

    $b = [byte[]]$hash[0..15]
    $b[6] = [byte](($b[6] -band 0x0F) -bor 0x50)   # version 5
    $b[8] = [byte](($b[8] -band 0x3F) -bor 0x80)   # variant RFC 4122

    $hex = -join ($b | ForEach-Object { $_.ToString('x2') })
    return '{0}-{1}-{2}-{3}-{4}' -f $hex.Substring(0, 8), $hex.Substring(8, 4), $hex.Substring(12, 4), $hex.Substring(16, 4), $hex.Substring(20, 12)
}

# --- Load and validate config ---
if (-not (Test-Path -LiteralPath $ConfigPath)) { throw "Config file not found: $ConfigPath" }
$cfg = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
$parentDisplayName = if ($cfg.parentPolicyDisplayName) { $cfg.parentPolicyDisplayName } else { 'Device Control (macOS) - USB Removable Media Default-Deny Allowlist' }

foreach ($family in $script:Families) {
    # Where-Object filters out $null - see the identical comment/rationale in the removable-media
    # sibling fragment's own deploy script for why this guards against a 1-element-null-array when
    # the config key is omitted entirely.
    $devices = @($cfg.($family.ConfigProperty) | Where-Object { $_ })
    $family['Devices'] = $devices

    $seenLabels = @{}
    $seenPairs = @{}
    foreach ($d in $devices) {
        if (-not $d.label) { throw "Every $($family.ConfigProperty) entry requires a 'label'." }
        if ($seenLabels.ContainsKey($d.label)) { throw "Duplicate $($family.ConfigProperty) label '$($d.label)' - labels must be unique within one family." }
        $seenLabels[$d.label] = $true
        Test-FourDigitHex -Value $d.vendorId -FieldName 'vendorId' -Label $d.label
        Test-FourDigitHex -Value $d.productId -FieldName 'productId' -Label $d.label
        $pairKey = "$($d.vendorId.ToLowerInvariant()):$($d.productId.ToLowerInvariant())"
        if ($seenPairs.ContainsKey($pairKey)) {
            throw "Duplicate vendorId+productId pair '$pairKey' on $($family.ConfigProperty) entries '$($seenPairs[$pairKey])' and '$($d.label)' - each device's vendorId+productId pair determines its group id and must be unique within one family's list, even if labels differ."
        }
        $seenPairs[$pairKey] = $d.label
    }
}

Assert-MgConnected
Write-Host "macOS Apple/Portable vendor+product device allowlist: extending parent policy '$parentDisplayName'." -ForegroundColor Cyan

# --- 1. Locate the parent policy ---
$configUri = "$GraphBaseUri/deviceManagement/deviceConfigurations"
$parent = Get-AllGraphValues -Uri $configUri | Where-Object { $_.displayName -eq $parentDisplayName } | Select-Object -First 1

if (-not $parent) {
    throw "Parent policy '$parentDisplayName' not found. Deploy scenarios/dlp/defender-device-control-usb-allowlist-macos/deploy/New-MacDeviceControlUsbAllowlistPolicy.ps1 first."
}

$full = Invoke-MgGraphRequest -Method GET -Uri "$configUri/$($parent.id)"
if (-not $full.payload) { throw "Parent policy '$parentDisplayName' has no payload - it does not look like the expected macOSCustomConfiguration device control object. Refusing to modify it." }

$mobileConfigXml = ConvertFrom-Utf8Base64 $full.payload

# --- 2. Extract the embedded device control policy JSON string (same regex-over-known-XML-shape
#        technique every sibling fragment in this family uses) ---
$policyMatch = [regex]::Match($mobileConfigXml, '<key>policy</key>\s*<string>(.*?)</string>', [System.Text.RegularExpressions.RegexOptions]::Singleline)
if (-not $policyMatch.Success) {
    throw "Could not locate the embedded deviceControl.policy JSON in the parent policy's .mobileconfig payload - it does not look like the expected object. Refusing to modify it."
}
$originalEscapedJson = $policyMatch.Groups[1].Value
$parsedPolicy = (ConvertFrom-XmlEscaped $originalEscapedJson) | ConvertFrom-Json

if (-not $parsedPolicy.groups -or -not $parsedPolicy.rules -or -not $parsedPolicy.settings) {
    throw "Parent policy's deviceControl.policy JSON is missing groups/rules/settings - it does not look like the expected object. Refusing to modify it."
}

# --- 3. Per family: refuse if devices are configured but the prerequisite Approved group/Allow rule
#        are not present; otherwise compute the desired sub-group set and diff against what's live ---
$newGroupsList = New-Object System.Collections.Generic.List[object]

# Seed with every existing group; families' target groups get their contents replaced in place,
# this fragment's own stale sub-groups (any family) are dropped and re-added fresh at the correct
# position.
$allOwnedPrefixes = @($script:Families | ForEach-Object { $_.NamePrefix })
$allExistingOwnedGroups = @($parsedPolicy.groups | Where-Object { $g = $_; $allOwnedPrefixes | Where-Object { $g.name -like "$_*" } })
$allExistingOwnedGroupIds = @($allExistingOwnedGroups | ForEach-Object { $_.id })

foreach ($family in $script:Families) {
    $devices = $family.Devices
    $approvedGroup = $parsedPolicy.groups | Where-Object { $_.id -eq $family.ApprovedGroupId } | Select-Object -First 1
    $allowRule = $parsedPolicy.rules | Where-Object { $_.id -eq $family.AllowRuleId } | Select-Object -First 1

    if ($approvedGroup -and $approvedGroup.query.'$type' -notin @('or', 'any')) {
        throw "'$($family.ApprovedGroupName)' group's query.`$type is '$($approvedGroup.query.'$type')', expected 'or' or 'any' (both documented OR-semantics synonyms - design.md Section 6) - it does not look like the expected prerequisite-fragment shape. Refusing to modify it."
    }

    if ($devices.Count -eq 0) {
        $family['DesiredDevices'] = @()
        if (-not $approvedGroup) {
            $family['Skip'] = $true
            continue
        }
        # Group exists (owned by the prerequisite fragment) but this family has zero
        # vendorId/productId devices configured here - reconcile to zero (orphan cleanup only),
        # never touch the group's own serialNumber clauses.
    }
    else {
        if (-not $approvedGroup) {
            throw "Prerequisite not met: the '$($family.ApprovedGroupName)' group (from scenarios/dlp/defender-device-control-usb-allowlist-macos-portable-device-coverage) was not found on '$parentDisplayName'. This fragment only extends that group, it never creates it - configure at least one serialNumber device for this family via that fragment's deploy/Add-MacPortableDeviceCoverage.ps1 first (README.md Section 3), or if it was previously present, this is the known cross-fragment ordering hazard (README.md Section 11) - re-check that fragment's own config."
        }
        if (-not $allowRule) {
            throw "Prerequisite not met: the 'Allow-$($family.ApprovedGroupName)' rule was not found on '$parentDisplayName' even though the '$($family.ApprovedGroupName)' group is present - this looks like partial/drifted state from defender-device-control-usb-allowlist-macos-portable-device-coverage, not this fragment. Re-run that fragment's own deploy script before this one."
        }
    }

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
    $family['DesiredDevices'] = @($desiredDevices)
}

# --- 4. Reconciliation check (across both families at once) ---
$isFullyReconciled = $true
foreach ($family in $script:Families) {
    if ($family.Skip) { continue }
    $approvedGroup = $parsedPolicy.groups | Where-Object { $_.id -eq $family.ApprovedGroupId } | Select-Object -First 1
    $existingOwnedGroupIds = @($allExistingOwnedGroups | Where-Object { $_.name -like "$($family.NamePrefix)*" } | ForEach-Object { $_.id })
    $existingGroupIdClauses = @($approvedGroup.query.clauses | Where-Object { $_.'$type' -eq 'groupId' } | ForEach-Object { $_.value })
    $desiredGroupIds = @($family.DesiredDevices | ForEach-Object { $_.GroupId })
    $groupsMatch = -not (Compare-Object -ReferenceObject ($existingOwnedGroupIds | Sort-Object) -DifferenceObject ($desiredGroupIds | Sort-Object))
    $clausesMatch = -not (Compare-Object -ReferenceObject ($existingGroupIdClauses | Sort-Object) -DifferenceObject ($desiredGroupIds | Sort-Object))
    if (-not ($groupsMatch -and $clausesMatch -and $existingOwnedGroupIds.Count -eq $desiredGroupIds.Count)) {
        $isFullyReconciled = $false
    }
}

if ($isFullyReconciled -and -not $Force) {
    Write-Host '  [coverage] Apple/Portable vendorId/productId allowlist already matches -ConfigPath''s current definition - not modified. Pass -Force to reconcile anyway.' -ForegroundColor Yellow
    Write-Host "`nDone. No change made." -ForegroundColor Cyan
    return
}

# --- 5. Build the reconciled groups array: every group not owned by this fragment (any family)
#        passes through untouched, in original relative order; when a family's Approved group is
#        reached, insert that family's desired sub-groups immediately BEFORE it (groupId clauses
#        require their target group to already be defined earlier in the array), then the Approved
#        group itself with its query.clauses rebuilt: every non-groupId clause (serialNumber, owned
#        by the prerequisite fragment) reproduced byte-for-byte, followed by one groupId clause per
#        desired device for that family only ---
foreach ($g in $parsedPolicy.groups) {
    $matchedFamily = $script:Families | Where-Object { -not $_.Skip -and $g.id -eq $_.ApprovedGroupId } | Select-Object -First 1
    if ($matchedFamily) {
        foreach ($d in $matchedFamily.DesiredDevices) {
            $newGroupsList.Add([ordered]@{
                '$type' = 'device'
                id      = $d.GroupId
                name    = $d.GroupName
                query   = [ordered]@{
                    '$type'  = 'and'
                    clauses  = @(
                        [ordered]@{ '$type' = 'primaryId'; value = $matchedFamily.PrimaryIdValue }
                        [ordered]@{ '$type' = 'vendorId'; value = $d.VendorId }
                        [ordered]@{ '$type' = 'productId'; value = $d.ProductId }
                    )
                }
            })
        }
        $preservedClauses = @($g.query.clauses | Where-Object { $_.'$type' -ne 'groupId' })
        $groupIdClauses = @($matchedFamily.DesiredDevices | ForEach-Object { [ordered]@{ '$type' = 'groupId'; value = $_.GroupId } })
        $newGroupsList.Add([ordered]@{
            '$type' = 'device'
            id      = $g.id
            name    = $g.name
            query   = [ordered]@{
                '$type'  = $g.query.'$type'
                clauses  = @($preservedClauses) + @($groupIdClauses)
            }
        })
        foreach ($d in $matchedFamily.DesiredDevices) {
            Write-Host "  [plan] Approving $($matchedFamily.Key) device '$($d.Label)' (vendorId=$($d.VendorId), productId=$($d.ProductId), groupId=$($d.GroupId))." -ForegroundColor DarkCyan
        }
        $familyExistingOwned = @($allExistingOwnedGroups | Where-Object { $_.name -like "$($matchedFamily.NamePrefix)*" })
        $desiredGroupIds = @($matchedFamily.DesiredDevices | ForEach-Object { $_.GroupId })
        $removedLabels = @($familyExistingOwned | Where-Object { $_.id -notin $desiredGroupIds } | ForEach-Object { $_.name.Substring($matchedFamily.NamePrefix.Length) })
        foreach ($label in $removedLabels) {
            Write-Host "  [plan] Removing $($matchedFamily.Key) device no longer in -ConfigPath: '$label'." -ForegroundColor DarkCyan
        }
        continue
    }
    if ($g.id -in $allExistingOwnedGroupIds) {
        continue  # this fragment's own stale sub-group (either family) - re-added fresh above, or dropped if no longer desired
    }
    $newGroupsList.Add($g)
}

# A family with zero devices AND no live Approved group ($Skip = $true) contributes nothing and was
# never in $parsedPolicy.groups to begin with - nothing further to do for it.

$desiredPolicy = [ordered]@{ groups = @($newGroupsList); rules = $parsedPolicy.rules; settings = $parsedPolicy.settings }
$newPolicyJson = $desiredPolicy | ConvertTo-Json -Depth 12 -Compress
$newEscapedJson = ConvertTo-XmlEscaped $newPolicyJson

Write-Host "  [plan] $($parsedPolicy.groups.Count) existing groups -> $($newGroupsList.Count) groups (rules unchanged - both prerequisite Allow/Deny rules per family already key off their Approved group's id)." -ForegroundColor DarkCyan

# --- 6. Substitute only the policy <string> node's content; every other plist key is untouched ---
$newMobileConfigXml = $mobileConfigXml.Replace($originalEscapedJson, $newEscapedJson)
if ($newMobileConfigXml -eq $mobileConfigXml -and $originalEscapedJson -ne $newEscapedJson) {
    throw 'Failed to locate the captured policy JSON substring for replacement inside the .mobileconfig - refusing to PATCH a possibly-unmodified payload.'
}

$body = @{
    '@odata.type'   = '#microsoft.graph.macOSCustomConfiguration'
    displayName     = $full.displayName
    description     = $full.description
    payloadName     = $full.payloadName
    payloadFileName = $full.payloadFileName
    payload         = (ConvertTo-Utf8Base64 $newMobileConfigXml)
}

if ($PSCmdlet.ShouldProcess($parentDisplayName, "PATCH $configUri/$($parent.id) (reconcile Apple/Portable vendorId/productId device allowlist)")) {
    Invoke-MgGraphRequest -Method PATCH -Uri "$configUri/$($parent.id)" -Body ($body | ConvertTo-Json -Depth 12) | Out-Null
    Write-Host "  [coverage] Apple/Portable vendorId/productId device allowlist reconciled on '$parentDisplayName' (id $($parent.id))" -ForegroundColor Green
}

Write-Host "`nDone. This does not change the parent policy's assignment. Run validate/Test-MacApplePortableVendorProductDeviceAllowlist.ps1 to verify. Reminder: re-run this script if defender-device-control-usb-allowlist-macos-portable-device-coverage's own Add-MacPortableDeviceCoverage.ps1 -Force is ever run afterward - see README.md Section 11 for the known ordering hazard." -ForegroundColor Cyan
```

#### `config/mac-apple-portable-vendor-product-device-allowlist.sample.json`

```json
{
  "parentPolicyDisplayName": "Device Control (macOS) - USB Removable Media Default-Deny Allowlist",
  "vendorProductAppleDevices": [
    {
      "label": "Loaner-iPad-EnterpriseImage-01",
      "vendorId": "05ac",
      "productId": "12ab"
    }
  ],
  "vendorProductPortableDevices": [
    {
      "label": "Warehouse-Barcode-Scanner-03",
      "vendorId": "0951",
      "productId": "1666"
    }
  ]
}
```

#### `Remove-MacApplePortableVendorProductDeviceAllowlist.ps1`

```powershell
#Requires -Version 7.0
<#
.SYNOPSIS
    Removes every Apple/Portable vendorId/productId compound-matched device exception this fragment
    added, reverting "ApprovedAppleDevices"/"ApprovedPortableDevices" to serialNumber-only matching.

.DESCRIPTION
    Surgical rollback for
    scenarios/dlp/defender-device-control-usb-allowlist-macos-apple-portable-vendor-product-matching:
    removes every "AppleVendorProductMatch-*"/"PortableVendorProductMatch-*" sub-group this
    fragment's deploy/Add-MacApplePortableVendorProductDeviceAllowlist.ps1 added, and strips every
    "groupId" clause it added from "ApprovedAppleDevices"'s and "ApprovedPortableDevices"'s
    query.clauses arrays - by name prefix, the same identification the deploy and validate scripts
    use.

    This does NOT touch either group's serialNumber-based entries, the AllAppleDevices/
    AllPortableDevices catch-all groups, any Allow/Deny rule, the removable-media or Bluetooth
    sibling fragments' own groups and rules, the assignment, or the policy object's identity - only
    this fragment's own additions are removed. An Apple/Portable device approved only by
    vendorId/productId reverts to DENIED (the OR-branch it matched no longer exists); any device also
    matched by a still-present serialNumber clause is unaffected.

    If a family's ApprovedAppleDevices/ApprovedPortableDevices group is not present at all (never
    configured, or removed by the known cross-fragment ordering hazard - README.md Section 11), that
    family is reported as "nothing to remove" and skipped; the other family is still processed.

    Connect first: Connect-MgGraph (app-only certificate - see docs/automation-surface.md Section 3).
    This script does not open the session.

.PARAMETER ParentPolicyDisplayName
    Display name of the parent macOSCustomConfiguration object. Defaults to this scenario's
    standard parent name.

.PARAMETER GraphBaseUri
    Graph base URI. Defaults to 'https://graph.microsoft.com/v1.0'.

.PARAMETER WhatIf
    Standard PowerShell ShouldProcess dry-run.

.EXAMPLE
    Connect-MgGraph -ClientId $AppId -TenantId $TenantId -CertificateThumbprint $Thumbprint
    ./Remove-MacApplePortableVendorProductDeviceAllowlist.ps1 -WhatIf

.EXAMPLE
    ./Remove-MacApplePortableVendorProductDeviceAllowlist.ps1
    # Strips every Apple/Portable vendorId/productId device exception back out of both families.

.NOTES
    Sources: same as deploy/Add-MacApplePortableVendorProductDeviceAllowlist.ps1's .NOTES block.
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$ParentPolicyDisplayName = 'Device Control (macOS) - USB Removable Media Default-Deny Allowlist',

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$GraphBaseUri = 'https://graph.microsoft.com/v1.0'
)

$ErrorActionPreference = 'Stop'

$script:Families = @(
    [ordered]@{ Key = 'apple';    ApprovedGroupId = 'd1d2d3d4-1111-4a1a-8a1a-111111111102'; ApprovedGroupName = 'ApprovedAppleDevices';    NamePrefix = 'AppleVendorProductMatch-' }
    [ordered]@{ Key = 'portable'; ApprovedGroupId = 'd1d2d3d4-2222-4b2b-8b2b-222222222202'; ApprovedGroupName = 'ApprovedPortableDevices'; NamePrefix = 'PortableVendorProductMatch-' }
)

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

function ConvertTo-Utf8Base64   { param([Parameter(Mandatory)][string]$Text)   [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($Text)) }
function ConvertFrom-Utf8Base64 { param([Parameter(Mandatory)][string]$Base64) [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($Base64)) }
function ConvertTo-XmlEscaped   { param([Parameter(Mandatory)][string]$Text)   $Text -replace '&', '&amp;' -replace '<', '&lt;' -replace '>', '&gt;' }
function ConvertFrom-XmlEscaped { param([Parameter(Mandatory)][string]$Text)   $Text -replace '&lt;', '<' -replace '&gt;', '>' -replace '&amp;', '&' }

Assert-MgConnected

$configUri = "$GraphBaseUri/deviceManagement/deviceConfigurations"
$parent = Get-AllGraphValues -Uri $configUri | Where-Object { $_.displayName -eq $ParentPolicyDisplayName } | Select-Object -First 1

if (-not $parent) {
    Write-Host "Parent policy '$ParentPolicyDisplayName' not found - nothing to remove." -ForegroundColor Yellow
    return
}

$full = Invoke-MgGraphRequest -Method GET -Uri "$configUri/$($parent.id)"
if (-not $full.payload) {
    Write-Host "Parent policy '$ParentPolicyDisplayName' has no payload - nothing to remove." -ForegroundColor Yellow
    return
}

$mobileConfigXml = ConvertFrom-Utf8Base64 $full.payload
$policyMatch = [regex]::Match($mobileConfigXml, '<key>policy</key>\s*<string>(.*?)</string>', [System.Text.RegularExpressions.RegexOptions]::Singleline)
if (-not $policyMatch.Success) {
    Write-Host "Could not locate the embedded deviceControl.policy JSON - nothing to remove." -ForegroundColor Yellow
    return
}
$originalEscapedJson = $policyMatch.Groups[1].Value
$parsedPolicy = (ConvertFrom-XmlEscaped $originalEscapedJson) | ConvertFrom-Json

$anyOwnedGroup = $false
foreach ($family in $script:Families) {
    $approvedGroup = $parsedPolicy.groups | Where-Object { $_.id -eq $family.ApprovedGroupId } | Select-Object -First 1
    if (-not $approvedGroup) {
        Write-Host "$($family.ApprovedGroupName) not found on '$ParentPolicyDisplayName' - nothing for this fragment to remove for the $($family.Key) family." -ForegroundColor Yellow
        continue
    }
    $ownedGroups = @($parsedPolicy.groups | Where-Object { $_.name -like "$($family.NamePrefix)*" })
    $groupIdClauseCount = @($approvedGroup.query.clauses | Where-Object { $_.'$type' -eq 'groupId' }).Count
    if ($ownedGroups.Count -eq 0 -and $groupIdClauseCount -eq 0) {
        Write-Host "No $($family.Key) vendorId/productId device allowlist currently present on '$ParentPolicyDisplayName' - nothing to remove for this family." -ForegroundColor Yellow
        continue
    }
    $anyOwnedGroup = $true
    foreach ($g in $ownedGroups) {
        Write-Host "  [plan] Removing $($family.Key) device: '$($g.name.Substring($family.NamePrefix.Length))'." -ForegroundColor DarkCyan
    }
}

if (-not $anyOwnedGroup) {
    Write-Host "`nDone. No change made." -ForegroundColor Cyan
    return
}

$allNamePrefixes = @($script:Families | ForEach-Object { $_.NamePrefix })

$newGroupsList = New-Object System.Collections.Generic.List[object]
foreach ($g in $parsedPolicy.groups) {
    $matchedFamily = $script:Families | Where-Object { $g.id -eq $_.ApprovedGroupId } | Select-Object -First 1
    if ($matchedFamily) {
        $revertedClauses = @($g.query.clauses | Where-Object { $_.'$type' -ne 'groupId' })
        $newGroupsList.Add([ordered]@{
            '$type' = 'device'
            id      = $g.id
            name    = $g.name
            query   = [ordered]@{ '$type' = $g.query.'$type'; clauses = @($revertedClauses) }
        })
        Write-Host "  [plan] $($matchedFamily.ApprovedGroupName) reverts to $($revertedClauses.Count) serialNumber clause(s) only." -ForegroundColor DarkCyan
        continue
    }
    $isOwnedSubGroup = $false
    foreach ($prefix in $allNamePrefixes) {
        if ($g.name -like "$prefix*") { $isOwnedSubGroup = $true; break }
    }
    if ($isOwnedSubGroup) { continue }  # this fragment's own per-device sub-group - dropped, not kept
    $newGroupsList.Add($g)
}

$desiredPolicy = [ordered]@{ groups = @($newGroupsList); rules = $parsedPolicy.rules; settings = $parsedPolicy.settings }
$newPolicyJson = $desiredPolicy | ConvertTo-Json -Depth 12 -Compress
$newEscapedJson = ConvertTo-XmlEscaped $newPolicyJson

Write-Host "  [plan] $($parsedPolicy.groups.Count) existing groups -> $($newGroupsList.Count) groups after removing the Apple/Portable vendorId/productId device allowlist." -ForegroundColor DarkCyan

$newMobileConfigXml = $mobileConfigXml.Replace($originalEscapedJson, $newEscapedJson)
if ($newMobileConfigXml -eq $mobileConfigXml -and $originalEscapedJson -ne $newEscapedJson) {
    throw 'Failed to locate the captured policy JSON substring for replacement inside the .mobileconfig - refusing to PATCH a possibly-unmodified payload.'
}

$body = @{
    '@odata.type'   = '#microsoft.graph.macOSCustomConfiguration'
    displayName     = $full.displayName
    description     = $full.description
    payloadName     = $full.payloadName
    payloadFileName = $full.payloadFileName
    payload         = (ConvertTo-Utf8Base64 $newMobileConfigXml)
}

if ($PSCmdlet.ShouldProcess($ParentPolicyDisplayName, "PATCH $configUri/$($parent.id) (remove Apple/Portable vendorId/productId device allowlist)")) {
    Invoke-MgGraphRequest -Method PATCH -Uri "$configUri/$($parent.id)" -Body ($body | ConvertTo-Json -Depth 12) | Out-Null
    Write-Host "  [coverage] Apple/Portable vendorId/productId device allowlist removed from '$ParentPolicyDisplayName' (id $($parent.id))" -ForegroundColor Green
}

Write-Host "`nDone. Devices that were approved only by vendorId/productId revert to DENIED, not to unrestricted - see rollback.md. Any device also matched by a still-present serialNumber clause is unaffected." -ForegroundColor Cyan
```