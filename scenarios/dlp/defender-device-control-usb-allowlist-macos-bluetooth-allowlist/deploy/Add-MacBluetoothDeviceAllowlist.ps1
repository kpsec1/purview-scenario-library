#Requires -Version 7.0
<#
.SYNOPSIS
    Adds one or more vendorId+productId-matched approved-device exceptions to the
    "Deny-AllBluetoothDevices" rule created by
    scenarios/dlp/defender-device-control-usb-allowlist-macos-portable-device-coverage, inside the
    shared macOSCustomConfiguration object created by
    scenarios/dlp/defender-device-control-usb-allowlist-macos.

.DESCRIPTION
    The portable-device-coverage fragment ships Bluetooth as default-deny-only, no exceptions,
    because Microsoft's own worked exception sample for bluetooth_devices
    (deny_all_bluetooth_devices_except_samsung.json) uses a structurally different, single-device
    vendorId+productId AND-match, not the OR'd multi-device serialNumber pattern used for the
    Apple/Portable families (portable-device-coverage/design.md Section 5). This script closes that
    gap for any number (0 or more) of approved devices, without introducing a second,
    differently-shaped multi-device schema for a single device.

    MULTI-DEVICE DESIGN (v2 - see design.md Section 5 for the full history): a rule's includeGroups
    combines multiple groups with AND semantics ("If multiple groups are in the includeGroups, it's
    AND" - Microsoft's own Access policy rule reference table), so N devices cannot be expressed as N
    groups referenced by one rule's includeGroups directly. This script instead reuses the same
    per-device sub-group + parent-group groupId-clause-nesting technique
    scenarios/dlp/defender-device-control-usb-allowlist-macos-apple-portable-vendor-product-matching/
    already built and validated for the identical AND-then-OR problem (vendorId+productId is itself
    an AND pair per device; multiple devices must be OR'd together): each approved device gets its own
    small sub-group (`$type: "and"`, clauses: [primaryId, vendorId, productId], deterministic id -
    RFC 4122 v5 UUID derived from the vendorId:productId pair, so re-running this script never
    duplicates a sub-group for the same device). The single parent "ApprovedBluetoothDevices" group
    (fixed GUID, unchanged across versions of this script) becomes `$type: "or"`, clauses: one
    `groupId` clause per desired sub-group. Neither the Allow-ApprovedBluetoothDevice rule's
    includeGroups nor the Deny-AllBluetoothDevices rule's excludeGroups need to change shape at all -
    both already reference only the single parent group's id, which now transparently represents "any
    of N devices" instead of "exactly one device."

    This script does NOT create a new Intune profile and does NOT create a new top-level
    Bluetooth catch-all group or Bluetooth feature flag - both already exist once
    defender-device-control-usb-allowlist-macos-portable-device-coverage/deploy/
    Add-MacPortableDeviceCoverage.ps1 has been run. This script REFUSES to run if that
    prerequisite fragment's AllBluetoothDevices group and Deny-AllBluetoothDevices rule (identified
    by their fixed GUIDs) are not both present - see README.md Section 3.

    What this script adds/reconciles, by fixed/deterministic GUID:
      1. One sub-group per desired device, "BluetoothVendorProductMatch-<label>" - $type: "and",
         clauses: [primaryId=bluetooth_devices, vendorId=<config>, productId=<config>] - the exact
         per-device shape Microsoft's own deny_all_bluetooth_devices_except_samsung.json sample uses
         for its "Samsung Galaxy S21" exception group (see .NOTES), now nested under a parent OR group
         instead of used as the top-level group directly.
      2. The parent "ApprovedBluetoothDevices" group (fixed GUID, unchanged) - $type: "or", clauses:
         one groupId clause per desired sub-group.
      3. Rewrites the EXISTING "Deny-AllBluetoothDevices" rule (same fixed GUID the
         portable-device-coverage fragment created) to add excludeGroups = [ApprovedBluetoothDevices
         parent group id] - its two deny/auditDeny entries are reproduced byte-for-byte unchanged from
         that fragment's own New-DenyRule call, so this is additive, not destructive, to that rule.
      4. One "Allow-ApprovedBluetoothDevice" rule (fixed GUID, unchanged) - entries: allow +
         auditAllow, access = the two documented bluetoothDevice access strings, includeGroups = the
         parent group's id. This script adds an explicit "allow" enforcement entry (not just
         auditAllow, unlike Microsoft's own sample) because this fragment's shared policy inherits
         settings.global.defaultEnforcement = "deny" (fail-closed) from the parent scenario -
         Microsoft's own sample instead relies on defaultEnforcement = "allow" (its own document's
         default), where excluding a device from the deny rule is sufficient by itself. See design.md
         Section 4 and README.md Section 6.

    Every group/rule/setting this script does not own (the parent's removableMedia coverage, the
    portable-device-coverage fragment's Apple/Portable groups and rules, the Bluetooth deny rule's
    own two entries) is read from the live object and passed through untouched.

    KNOWN ORDERING HAZARD (see README.md Section 11, reviews.md Blue Team finding 1): if
    defender-device-control-usb-allowlist-macos-portable-device-coverage/deploy/
    Add-MacPortableDeviceCoverage.ps1 -Force is run AFTER this script, it unconditionally rebuilds
    the Deny-AllBluetoothDevices rule with ExcludeGroups = $null (that script has no awareness of
    this fragment), silently dropping this fragment's exclusion. If that happens, simply re-run
    THIS script again to restore it - validate/Test-MacBluetoothDeviceAllowlist.ps1 detects and
    flags this specific drift condition.

    Idempotent: reads the live policy JSON, computes each configured device's deterministic sub-group
    id, and diffs the live sub-group/parent-group/rule state against -ConfigPath's current definition.
    A device removed from -ConfigPath has its sub-group dropped on the next run; a device added gets a
    freshly-computed sub-group. Without -Force, an already-reconciled policy is reported and left
    untouched.

.PARAMETER ConfigPath
    Path to the JSON config (parentPolicyDisplayName, approvedBluetoothDevices[] - zero or more
    entries, each { label, vendorId, productId }). Defaults to the sibling
    'config/mac-bluetooth-device-allowlist.sample.json' - copy and edit it.

.PARAMETER GraphBaseUri
    Graph base URI. Defaults to 'https://graph.microsoft.com/v1.0'.

.PARAMETER Force
    If this fragment's group/rule already exist, reconcile the approved device set to -ConfigPath's
    current definition instead of skipping.

.PARAMETER WhatIf
    Standard PowerShell ShouldProcess dry-run. Reports the PATCH that would be made without calling
    any mutating Graph endpoint.

.EXAMPLE
    Connect-MgGraph -ClientId $AppId -TenantId $TenantId -CertificateThumbprint $Thumbprint
    ./Add-MacBluetoothDeviceAllowlist.ps1 -ConfigPath ./config/my-tenant.json -WhatIf

.EXAMPLE
    ./Add-MacBluetoothDeviceAllowlist.ps1 -ConfigPath ./config/my-tenant.json

.NOTES
    vendorId/productId identify a DEVICE MODEL, not a unique physical unit - unlike this repository's
    serialNumber-based allowlists (parent scenario, Apple/Portable families), any Bluetooth device
    sharing a configured vendorId+productId pair (e.g. a colleague's identical phone/scanner model)
    matches that device's exception, not just one specific approved unit. See README.md Section 11.

    excludeGroups OR semantics and includeGroups AND semantics both confirmed directly from
    Microsoft's "Access policy rule" reference table: "The groups that the policy doesn't apply
    to... If multiple groups are in the excludeGroups, it's OR" / "If multiple groups are in the
    includeGroups, it's AND." The parent-group-of-sub-groups technique below exists specifically to
    express "OR across N devices" through a group's own query (which independently supports an 'or'
    `$type`), not through a rule's includeGroups/excludeGroups arrays.

    Get-DeterministicSubGroupId is an RFC 4122 Section 4.3 version-5 (name-based, SHA-1) UUID
    derivation, worked entirely in raw hex-string/byte-array form (never round-tripped through
    [guid]'s byte-array constructor, which reorders bytes for .NET's mixed-endian internal
    representation) - avoids the classic UUID-v5-in-.NET endianness bug. Identical implementation to
    defender-device-control-usb-allowlist-macos-apple-portable-vendor-product-matching/deploy/
    Add-MacApplePortableVendorProductDeviceAllowlist.ps1's own function of the same name (itself
    reusing defender-device-control-usb-allowlist-macos-vendor-product-matching/deploy/
    Add-MacVendorProductDeviceAllowlist.ps1's verified implementation) - this script uses its own
    distinct namespace constant so its derived ids never collide with either sibling's.

    Sources (Microsoft Learn, verify before production use):
    - Device Control for macOS (Query/Clause/Access policy rule/Enforcement/Access Types reference
      tables - vendorId "Four digit hexadecimal string", productId "Four digit hexadecimal string",
      query $type "and"/"or" clause semantics, includeGroups AND / excludeGroups OR semantics,
      settings.global.defaultEnforcement "allow" (default) or "deny"):
      https://learn.microsoft.com/defender-endpoint/mac-device-control-overview
    - Sample macOS device control policies (deny_all_bluetooth_devices_except_samsung.json - the
      exact vendorId+productId AND-match exception-group shape this script reproduces per device,
      confirmed by direct fetch of the raw file content during this fragment's original build):
      https://github.com/microsoft/mdatp-devicecontrol/blob/main/macOS/policy/samples/deny_all_bluetooth_devices_except_samsung.json
    - scenarios/dlp/defender-device-control-usb-allowlist-macos-apple-portable-vendor-product-matching/
      deploy/Add-MacApplePortableVendorProductDeviceAllowlist.ps1 - the proven sub-group +
      groupId-clause-nesting technique this v2 script ports for the identical AND-then-OR problem.
    - scenarios/dlp/defender-device-control-usb-allowlist-macos-portable-device-coverage/deploy/
      Add-MacPortableDeviceCoverage.ps1 - the prerequisite fragment that creates the
      AllBluetoothDevices group and Deny-AllBluetoothDevices rule this script extends; same fixed
      GUIDs, same regex-over-known-XML-shape extraction technique (see that script's own .NOTES for
      the accepted trade-off this script inherits).
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$ConfigPath = (Join-Path $PSScriptRoot 'config/mac-bluetooth-device-allowlist.sample.json'),

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$GraphBaseUri = 'https://graph.microsoft.com/v1.0',

    [Parameter()]
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

# Prerequisite GUIDs - owned by defender-device-control-usb-allowlist-macos-portable-device-coverage.
# This script never creates these; it only reads and (for the rule) reconciles excludeGroups on them.
$script:AllBluetoothGroupId = 'd1d2d3d4-3333-4c3c-8c3c-333333333301'
$script:DenyBluetoothRuleId = 'd1d2d3d4-3333-4c3c-8c3c-333333333310'

# This fragment's own fixed GUIDs - distinct from every group/rule id used by any sibling fragment.
# ApprovedBluetoothGroupId is now the PARENT (OR) group; per-device sub-groups get deterministic ids.
$script:ApprovedBluetoothGroupId = 'd1d2d3d4-3333-4c3c-8c3c-333333333302'
$script:AllowBluetoothRuleId     = 'd1d2d3d4-3333-4c3c-8c3c-333333333311'
$script:SubGroupNamePrefix       = 'BluetoothVendorProductMatch-'

# This fragment's own fixed namespace constant for RFC 4122 Section 4.3 version-5 UUID derivation -
# distinct from every other GUID/namespace literal used by any sibling fragment in this repo.
$script:SubGroupNamespaceHex = 'e4f5a6b7c8d940e1a2b3c4d5e6f70819'

# Access-string list per Microsoft's official Access Types table - identical to the pair already
# used by the prerequisite fragment's own Deny-AllBluetoothDevices rule.
$script:BluetoothAccess = @('download_files_from_device', 'send_files_to_device')

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

function ConvertTo-Utf8Base64 { param([Parameter(Mandatory)][string]$Text) [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($Text)) }
function ConvertFrom-Utf8Base64 { param([Parameter(Mandatory)][string]$Base64) [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($Base64)) }
function ConvertTo-XmlEscaped { param([Parameter(Mandatory)][string]$Text) $Text -replace '&', '&amp;' -replace '<', '&lt;' -replace '>', '&gt;' }
function ConvertFrom-XmlEscaped { param([Parameter(Mandatory)][string]$Text) $Text -replace '&lt;', '<' -replace '&gt;', '>' -replace '&amp;', '&' }

function Test-FourDigitHex {
    param([string]$Value, [string]$FieldName, [string]$Label)
    if ($Value -notmatch '^[0-9A-Fa-f]{4}$') {
        throw "Device '$Label': $FieldName must be a four-digit hexadecimal string (e.g. '0075'), got '$Value'."
    }
}

function Get-DeterministicSubGroupId {
    <#
        RFC 4122 Section 4.3 version-5 (name-based, SHA-1) UUID derivation - see .NOTES for the
        endianness rationale and the sibling fragment this implementation is ported from unchanged.
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
# Where-Object filters out $null - guards against a 1-element-null-array when the config key is
# omitted entirely (same rationale as the Apple/Portable vendor-product-matching sibling).
$approvedDevices = @($cfg.approvedBluetoothDevices | Where-Object { $_ })

$seenLabels = @{}
$seenPairs = @{}
$desiredDevices = foreach ($d in $approvedDevices) {
    if (-not $d.label) { throw "Every approvedBluetoothDevices entry requires a 'label'." }
    if ($seenLabels.ContainsKey($d.label)) { throw "Duplicate approvedBluetoothDevices label '$($d.label)' - labels must be unique." }
    $seenLabels[$d.label] = $true
    Test-FourDigitHex -Value $d.vendorId -FieldName 'vendorId' -Label $d.label
    Test-FourDigitHex -Value $d.productId -FieldName 'productId' -Label $d.label
    $vendorNorm = $d.vendorId.ToLowerInvariant()
    $productNorm = $d.productId.ToLowerInvariant()
    $pairKey = "$vendorNorm`:$productNorm"
    if ($seenPairs.ContainsKey($pairKey)) {
        throw "Duplicate vendorId+productId pair '$pairKey' on approvedBluetoothDevices entries '$($seenPairs[$pairKey])' and '$($d.label)' - each device's vendorId+productId pair determines its sub-group id and must be unique, even if labels differ."
    }
    $seenPairs[$pairKey] = $d.label
    [pscustomobject]@{
        Label     = $d.label
        VendorId  = $vendorNorm
        ProductId = $productNorm
        GroupId   = Get-DeterministicSubGroupId -NamespaceHex $script:SubGroupNamespaceHex -Name "mac-bluetooth-device-allowlist/v2/$vendorNorm`:$productNorm"
        GroupName = "$($script:SubGroupNamePrefix)$($d.label)"
    }
}

Assert-MgConnected
Write-Host "macOS Bluetooth device allowlist: extending parent policy '$parentDisplayName'." -ForegroundColor Cyan

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
#        technique the prerequisite fragment's own scripts use and document) ---
$policyMatch = [regex]::Match($mobileConfigXml, '<key>policy</key>\s*<string>(.*?)</string>', [System.Text.RegularExpressions.RegexOptions]::Singleline)
if (-not $policyMatch.Success) {
    throw "Could not locate the embedded deviceControl.policy JSON in the parent policy's .mobileconfig payload - it does not look like the expected object. Refusing to modify it."
}
$originalEscapedJson = $policyMatch.Groups[1].Value
$parsedPolicy = (ConvertFrom-XmlEscaped $originalEscapedJson) | ConvertFrom-Json

if (-not $parsedPolicy.groups -or -not $parsedPolicy.rules -or -not $parsedPolicy.settings) {
    throw "Parent policy's deviceControl.policy JSON is missing groups/rules/settings - it does not look like the expected object. Refusing to modify it."
}

# --- 3. Refuse to run if the prerequisite fragment's Bluetooth catch-all group / deny rule are not
#        both present - this script only extends that fragment's Bluetooth coverage, it never
#        creates it from scratch ---
$existingGroupIds = @($parsedPolicy.groups | ForEach-Object { $_.id })
$denyBluetoothRule = $parsedPolicy.rules | Where-Object { $_.id -eq $script:DenyBluetoothRuleId } | Select-Object -First 1

if ($script:AllBluetoothGroupId -notin $existingGroupIds -or -not $denyBluetoothRule) {
    throw "Prerequisite not met: the AllBluetoothDevices group and/or Deny-AllBluetoothDevices rule (from scenarios/dlp/defender-device-control-usb-allowlist-macos-portable-device-coverage) were not found on '$parentDisplayName'. Deploy that fragment's deploy/Add-MacPortableDeviceCoverage.ps1 first - this script only adds approved-device exceptions to its Bluetooth coverage, it does not create Bluetooth coverage itself."
}

# --- 4. Coverage/reconciliation detection (by fixed/deterministic ids, not by value) ---
$approvedGroup = $parsedPolicy.groups | Where-Object { $_.id -eq $script:ApprovedBluetoothGroupId } | Select-Object -First 1
$allowRule = $parsedPolicy.rules | Where-Object { $_.id -eq $script:AllowBluetoothRuleId } | Select-Object -First 1
$hasExclude = $denyBluetoothRule.excludeGroups -contains $script:ApprovedBluetoothGroupId

if ($approvedGroup -and $approvedGroup.query.'$type' -notin @('or', 'any', 'and')) {
    throw "'ApprovedBluetoothDevices' group's query.`$type is '$($approvedGroup.query.'$type')', expected 'or'/'any' (v2, multi-device) or 'and' (v1, single-device, pre-upgrade) - it does not look like a shape this script recognizes. Refusing to modify it."
}

$existingGroupIdClauses = @()
if ($approvedGroup -and $approvedGroup.query.'$type' -in @('or', 'any')) {
    $existingGroupIdClauses = @($approvedGroup.query.clauses | Where-Object { $_.'$type' -eq 'groupId' } | ForEach-Object { $_.value })
}
$existingSubGroupIds = @($parsedPolicy.groups | Where-Object { $_.name -like "$($script:SubGroupNamePrefix)*" } | ForEach-Object { $_.id })
$desiredGroupIds = @($desiredDevices | ForEach-Object { $_.GroupId })

$groupsMatch = -not (Compare-Object -ReferenceObject ($existingSubGroupIds | Sort-Object) -DifferenceObject ($desiredGroupIds | Sort-Object))
$clausesMatch = -not (Compare-Object -ReferenceObject ($existingGroupIdClauses | Sort-Object) -DifferenceObject ($desiredGroupIds | Sort-Object))
$isFullyReconciled = ($desiredDevices.Count -eq 0 -and -not $approvedGroup -and -not $allowRule -and -not $hasExclude) `
    -or ($desiredDevices.Count -gt 0 -and $groupsMatch -and $clausesMatch -and $existingSubGroupIds.Count -eq $desiredGroupIds.Count -and $allowRule -and $hasExclude)

if ($isFullyReconciled -and -not $Force) {
    Write-Host "  [coverage] Bluetooth device allowlist already matches -ConfigPath's current definition on '$parentDisplayName' - not modified. Pass -Force to reconcile anyway." -ForegroundColor Yellow
    Write-Host "`nDone. No change made." -ForegroundColor Cyan
    return
}
if (-not $isFullyReconciled -and ($approvedGroup -or $allowRule -or $hasExclude -or $existingSubGroupIds.Count -gt 0) -and -not $Force) {
    Write-Host "  [coverage] Partial or drifted Bluetooth allowlist state detected on '$parentDisplayName' (parent group present: $([bool]$approvedGroup), sub-groups: $($existingSubGroupIds.Count), allow rule present: $([bool]$allowRule), exclude present: $hasExclude) - reconciling to a complete, consistent state matching -ConfigPath ($($desiredDevices.Count) device(s))." -ForegroundColor Yellow
}

# --- 5. Build the reconciled groups/rules: keep every group/rule not owned by this fragment
#        untouched (including the prerequisite fragment's other groups/rules and any other
#        pre-existing excludeGroups entry on the shared deny rule), drop this fragment's own stale
#        sub-groups and parent group, then re-add fresh sub-groups + parent group + allow rule from
#        -ConfigPath ---
$keptGroups = @($parsedPolicy.groups | Where-Object { $_.id -ne $script:ApprovedBluetoothGroupId -and $_.id -notin $existingSubGroupIds })
$keptRules  = @($parsedPolicy.rules  | Where-Object { $_.id -notin @($script:DenyBluetoothRuleId, $script:AllowBluetoothRuleId) })

$newGroups = @()
$newRules  = @()

if ($desiredDevices.Count -gt 0) {
    foreach ($d in $desiredDevices) {
        # Exact per-device shape of Microsoft's own deny_all_bluetooth_devices_except_samsung.json
        # exception group, now nested as a sub-group under the OR'd parent group.
        $newGroups += [ordered]@{
            '$type' = 'device'
            id      = $d.GroupId
            name    = $d.GroupName
            query   = [ordered]@{
                '$type'  = 'and'
                clauses  = @(
                    [ordered]@{ '$type' = 'primaryId'; value = 'bluetooth_devices' }
                    [ordered]@{ '$type' = 'vendorId'; value = $d.VendorId }
                    [ordered]@{ '$type' = 'productId'; value = $d.ProductId }
                )
            }
        }
        Write-Host "  [plan] Approving Bluetooth device '$($d.Label)' (vendorId=$($d.VendorId), productId=$($d.ProductId), groupId=$($d.GroupId))." -ForegroundColor DarkCyan
    }
    $newGroups += [ordered]@{
        '$type' = 'device'
        id      = $script:ApprovedBluetoothGroupId
        name    = 'ApprovedBluetoothDevices'
        query   = [ordered]@{
            '$type'  = 'or'
            clauses  = @($desiredDevices | ForEach-Object { [ordered]@{ '$type' = 'groupId'; value = $_.GroupId } })
        }
    }

    # Preserve any pre-existing excludeGroups entries this fragment doesn't own (e.g. a manually
    # added exclusion) - never wholesale-replace the array, only ensure this fragment's own entry
    # is present exactly once.
    $otherExcludeGroups = @($denyBluetoothRule.excludeGroups | Where-Object { $_ -ne $script:ApprovedBluetoothGroupId })
    $reconciledDenyRule = [ordered]@{
        id            = $script:DenyBluetoothRuleId
        name          = $denyBluetoothRule.name
        includeGroups = $denyBluetoothRule.includeGroups
        excludeGroups = @($otherExcludeGroups) + @($script:ApprovedBluetoothGroupId)
        entries       = $denyBluetoothRule.entries
    }
    $newRules += $reconciledDenyRule
    # Explicit allow entry required - see .DESCRIPTION for why this fragment does not rely on
    # Microsoft's own sample's implicit "exclude + defaultEnforcement=allow" shortcut.
    $newRules += [ordered]@{
        id            = $script:AllowBluetoothRuleId
        name          = 'Allow-ApprovedBluetoothDevice'
        includeGroups = @($script:ApprovedBluetoothGroupId)
        entries       = @(
            [ordered]@{ '$type' = 'bluetoothDevice'; id = 'aaaaaaaa-0003-4003-8003-000000000003'; enforcement = [ordered]@{ '$type' = 'allow' }; access = $script:BluetoothAccess }
            [ordered]@{ '$type' = 'bluetoothDevice'; id = 'aaaaaaaa-0004-4004-8004-000000000004'; enforcement = [ordered]@{ '$type' = 'auditAllow'; options = @('send_event') }; access = $script:BluetoothAccess }
        )
    }
    $removedLabels = @($parsedPolicy.groups | Where-Object { $_.name -like "$($script:SubGroupNamePrefix)*" -and $_.id -notin $desiredGroupIds } | ForEach-Object { $_.name.Substring($script:SubGroupNamePrefix.Length) })
    foreach ($label in $removedLabels) {
        Write-Host "  [plan] Removing Bluetooth device no longer in -ConfigPath: '$label'." -ForegroundColor DarkCyan
    }
}
else {
    # Empty config: remove only this fragment's own excludeGroups entry, preserving any other
    # pre-existing exclusion this fragment doesn't own.
    $otherExcludeGroups = @($denyBluetoothRule.excludeGroups | Where-Object { $_ -ne $script:ApprovedBluetoothGroupId })
    $revertedRule = [ordered]@{
        id            = $script:DenyBluetoothRuleId
        name          = $denyBluetoothRule.name
        includeGroups = $denyBluetoothRule.includeGroups
        entries       = $denyBluetoothRule.entries
    }
    if ($otherExcludeGroups.Count -gt 0) { $revertedRule.excludeGroups = @($otherExcludeGroups) }
    $newRules += $revertedRule
    Write-Host '  [plan] No approvedBluetoothDevices configured - removing this fragment''s exception(s) (any other pre-existing excludeGroups entry is preserved).' -ForegroundColor DarkCyan
}

$desiredGroups = @($keptGroups) + @($newGroups)
$desiredRules  = @($keptRules) + @($newRules)

$desiredPolicy = [ordered]@{ groups = $desiredGroups; rules = $desiredRules; settings = $parsedPolicy.settings }
$newPolicyJson = $desiredPolicy | ConvertTo-Json -Depth 12 -Compress
$newEscapedJson = ConvertTo-XmlEscaped $newPolicyJson

Write-Host "  [plan] $($parsedPolicy.groups.Count) existing groups / $($parsedPolicy.rules.Count) existing rules -> $($desiredGroups.Count) groups / $($desiredRules.Count) rules ($($desiredDevices.Count) approved device(s))." -ForegroundColor DarkCyan

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

if ($PSCmdlet.ShouldProcess($parentDisplayName, "PATCH $configUri/$($parent.id) (reconcile Bluetooth device allowlist)")) {
    Invoke-MgGraphRequest -Method PATCH -Uri "$configUri/$($parent.id)" -Body ($body | ConvertTo-Json -Depth 12) | Out-Null
    Write-Host "  [coverage] Bluetooth device allowlist reconciled on '$parentDisplayName' (id $($parent.id))" -ForegroundColor Green
}

Write-Host "`nDone. This does not change the parent policy's assignment. Run validate/Test-MacBluetoothDeviceAllowlist.ps1 to verify. Reminder: re-run this script if defender-device-control-usb-allowlist-macos-portable-device-coverage's own Add-MacPortableDeviceCoverage.ps1 -Force is ever run afterward - see README.md Section 11 for the known ordering hazard." -ForegroundColor Cyan
