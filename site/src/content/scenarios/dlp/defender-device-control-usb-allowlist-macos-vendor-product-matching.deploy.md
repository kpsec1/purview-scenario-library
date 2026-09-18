---
part: "deploy"
parent: "dlp/defender-device-control-usb-allowlist-macos-vendor-product-matching"
---
The scripts and configuration below deploy this scenario. Review them, then run in order — each is designed to be idempotent and has a matching rollback.


#### `Add-MacVendorProductDeviceAllowlist.ps1`

```powershell
#Requires -Version 7.0
<#
.SYNOPSIS
    Adds vendorId+productId compound-matched approved-device exceptions to the existing
    "ApprovedBackupDrives" group inside the shared macOSCustomConfiguration object created by
    scenarios/dlp/defender-device-control-usb-allowlist-macos, for approved drives that have no
    readable serial number.

.DESCRIPTION
    The parent macOS device-control scenario matches approved removable-media devices by
    serialNumber only, deliberately deferring vendorId/productId compound matching because macOS's
    device-control JSON schema keeps vendorId and productId as two separate clause types that can
    only be AND-combined via a per-device sub-group referenced by a "groupId" clause - a materially
    more complex, per-device dynamic-GUID model the parent fragment's four-fixed-GUID design never
    needed (parent design.md Section 5; this fragment's own design.md Section 3). This script closes
    that gap for a buyer whose approved drives lack a readable serial number - e.g. bulk-imaged
    imaging docks, or third-party hardware whose serialNumber clause macOS reports empty.

    This script does NOT create a new Intune profile and does NOT create the "AllRemovableStorage"
    catch-all group, the "ApprovedBackupDrives" group itself, or the parent's two rules - all four
    already exist once defender-device-control-usb-allowlist-macos/deploy/
    New-MacDeviceControlUsbAllowlistPolicy.ps1 has been run. This script REFUSES to run if the
    parent's "ApprovedBackupDrives" group (identified by its fixed GUID) is not present - see
    README.md Section 3.

    What this script adds/reconciles, per -ConfigPath's vendorProductDevices[] entry:
      1. One per-device sub-group, "VendorProductMatch-<label>" - $type: "and", clauses:
         [primaryId=removable_media_devices, vendorId=<config>, productId=<config>] - the same
         AND-clause shape Microsoft's own deny_all_bluetooth_devices_except_samsung.json sample uses
         for its single-device vendorId+productId exception group, generalized here to the
         removable_media_devices family and to N devices (see .NOTES for the sample citation).
      2. A "groupId" clause referencing that sub-group's id, appended to the EXISTING
         "ApprovedBackupDrives" group's query.clauses array (query.$type stays "any" - unchanged).
         Every serialNumber clause already in that array (owned by the parent script) is reproduced
         byte-for-byte unchanged - this script only adds/removes its own groupId clauses, never
         serialNumber clauses.

    Because the parent's own "Allow-ApprovedBackupDrives" and "Deny-AllOtherRemovableStorage" rules
    already reference the "ApprovedBackupDrives" group's id directly (not any of its clauses), adding
    a device here requires NO new rule and NO edit to either existing rule - unlike the Bluetooth
    sibling fragment, which had to add a brand-new allow rule because Bluetooth's own approved-device
    exception lives in a separate group referenced only via the deny rule's excludeGroups. This
    fragment's device is a first-class OR-branch of "ApprovedBackupDrives" itself, so both rules that
    already key off that one group id automatically cover it.

    DETERMINISTIC PER-DEVICE GUIDs (see .NOTES and design.md Section 4): the parent's and every
    sibling fragment's group/rule ids are fixed literal constants because each fragment owns a fixed,
    small number of groups. This fragment owns a variable number of groups (one per config entry), so
    a fixed-literal scheme does not work. Instead each sub-group's id is derived deterministically
    from its vendorId+productId pair using RFC 4122 Section 4.3's version-5 (name-based, SHA-1) UUID
    algorithm with a fixed namespace constant unique to this fragment - the SAME vendorId+productId
    pair always produces the SAME group id on every run, on every machine, with no state file needed
    - and a DIFFERENT vendorId+productId pair is astronomically unlikely to collide (SHA-1 birthday
    bound). Renaming a device's label does not change its id (only vendorId+productId feed the hash),
    so a cosmetic rename never orphans and recreates a group.

    Idempotent: reads the live policy JSON, computes the desired sub-group set from -ConfigPath,
    diffs it against the sub-groups already present (identified by this fragment's
    "VendorProductMatch-" name prefix - never touching a group with a different prefix, including
    another fragment's own groups that happen to also reference removable_media_devices), and
    reconciles: adds missing sub-groups, removes sub-groups no longer in -ConfigPath (and their
    groupId clause), and adds/removes groupId clauses on "ApprovedBackupDrives" to match. Without
    -Force, an already-fully-reconciled policy is reported and left untouched; a partial/drifted
    state is still reconciled (this script never requires -Force to self-heal drift, only to
    re-write an already-correct state - the same discipline as the Bluetooth sibling fragment).

.PARAMETER ConfigPath
    Path to the JSON config (parentPolicyDisplayName, vendorProductDevices[] - zero or more
    entries). Defaults to the sibling
    'config/mac-vendor-product-device-allowlist.sample.json' - copy and edit it.

.PARAMETER GraphBaseUri
    Graph base URI. Defaults to 'https://graph.microsoft.com/v1.0'.

.PARAMETER Force
    Reconcile even if the live policy already fully matches -ConfigPath's current definition.

.PARAMETER WhatIf
    Standard PowerShell ShouldProcess dry-run. Reports the PATCH that would be made without calling
    any mutating Graph endpoint.

.EXAMPLE
    Connect-MgGraph -ClientId $AppId -TenantId $TenantId -CertificateThumbprint $Thumbprint
    ./Add-MacVendorProductDeviceAllowlist.ps1 -ConfigPath ./config/my-tenant.json -WhatIf

.EXAMPLE
    ./Add-MacVendorProductDeviceAllowlist.ps1 -ConfigPath ./config/my-tenant.json

.NOTES
    SCOPE: this script is limited to the "removable_media_devices" primaryId family - the same
    family the parent scenario's serialNumber-based ApprovedBackupDrives group already covers. It
    does not touch the Apple/Portable/Bluetooth sibling fragments' own groups or rules.

    vendorId/productId identify a DEVICE MODEL, not a unique physical unit - the same disclosed
    limitation as the Bluetooth sibling fragment's own equivalent exception. See README.md Section
    11 and reviews.md.

    No directly-confirmed Microsoft worked example pairs a "groupId" clause with more than one
    sibling sub-group inside one "any" query (Microsoft's own samples only ever show a single
    vendorId+productId exception device per policy) - the groupId clause TYPE itself, its "match if a
    device is a member of another group" semantics, and the "group must be defined within the policy
    before the clause" ordering requirement are directly confirmed from Microsoft's own Clause
    reference table (see Sources below), but the N-sub-groups-in-one-OR-query composition this script
    performs is this fragment's own application of that documented primitive, not itself a worked
    example. Flagged as VERIFY in README.md Section 11 rather than assumed identical to the
    single-device case without qualification.

    The RFC 4122 Section 4.3 version-5 UUID derivation this script implements (Get-
    DeterministicSubGroupId below) is a public, non-Microsoft-specific cryptographic standard, not a
    product fact requiring Microsoft Learn grounding. It was independently verified during this
    fragment's build against Python's standard-library uuid.uuid5() reference implementation for the
    same namespace+name input, producing an identical output GUID.

    Sources (Microsoft Learn, verify before production use):
    - Device Control for macOS (Clause reference table - groupId "Match if a device is a member of
      another group. The value represents the UUID of the group to match against. The group must be
      defined within the policy before the clause."; vendorId/productId "Four digit hexadecimal
      string"; Access policy rule includeGroups AND / excludeGroups OR semantics):
      https://learn.microsoft.com/defender-endpoint/mac-device-control-overview
    - Sample macOS device control policies (deny_removable_media_except_kingston.json - single-
      vendorId exception group shape; deny_all_bluetooth_devices_except_samsung.json - the
      vendorId+productId AND-clause exception-group shape this script generalizes to N devices,
      confirmed by direct fetch of both raw files during this fragment's build):
      https://github.com/microsoft/mdatp-devicecontrol/blob/main/macOS/policy/samples/deny_removable_media_except_kingston.json
      https://github.com/microsoft/mdatp-devicecontrol/blob/main/macOS/policy/samples/deny_all_bluetooth_devices_except_samsung.json
    - scenarios/dlp/defender-device-control-usb-allowlist-macos/deploy/
      New-MacDeviceControlUsbAllowlistPolicy.ps1 - the parent fragment that creates the
      ApprovedBackupDrives group and both rules this script extends; same fixed GUIDs, same
      regex-over-known-XML-shape payload extraction technique this script inherits.
    - RFC 4122, Section 4.3 (name-based UUID, algorithm for creating a version-5 UUID) -
      https://www.rfc-editor.org/rfc/rfc4122#section-4.3
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$ConfigPath = (Join-Path $PSScriptRoot 'config/mac-vendor-product-device-allowlist.sample.json'),

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$GraphBaseUri = 'https://graph.microsoft.com/v1.0',

    [Parameter()]
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

# Prerequisite GUIDs - owned by defender-device-control-usb-allowlist-macos. This script never
# creates these; it only reads the group and reconciles its query.clauses array.
$script:ApprovedBackupDrivesGroupId = '22222222-bbbb-4ccc-8ddd-222222222222'

# This fragment's own fixed namespace constant for RFC 4122 Section 4.3 version-5 UUID derivation -
# distinct from every other GUID literal used by any sibling fragment in this repo. Never reused.
$script:SubGroupNamespaceHex = '8f3a2b108f2e4c4a9b8b2f1a6c9d7e10'
$script:NamePrefix = 'VendorProductMatch-'

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
        which reorders bytes for .NET's mixed-endian internal representation) - this avoids the
        classic UUID-v5-in-.NET endianness bug. Verified during this fragment's build to reproduce
        Python's uuid.uuid5() output exactly for the same namespace+name input.
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
# Where-Object filters out $null - PowerShell's @($cfg.vendorProductDevices) evaluates to a
# 1-element array containing $null (not an empty array) when the JSON key is omitted entirely,
# which would otherwise misfire the per-entry validation loop below with a misleading error
# instead of correctly treating an omitted key the same as an explicit empty array (zero devices).
$configDevices = @($cfg.vendorProductDevices | Where-Object { $_ })

$seenLabels = @{}
$seenPairs = @{}
foreach ($d in $configDevices) {
    if (-not $d.label) { throw "Every vendorProductDevices entry requires a 'label'." }
    if ($seenLabels.ContainsKey($d.label)) { throw "Duplicate vendorProductDevices label '$($d.label)' - labels must be unique within one config file." }
    $seenLabels[$d.label] = $true
    Test-FourDigitHex -Value $d.vendorId -FieldName 'vendorId' -Label $d.label
    Test-FourDigitHex -Value $d.productId -FieldName 'productId' -Label $d.label
    # Two entries sharing one vendorId+productId pair would hash to the SAME deterministic group id
    # (design.md Section 4 - the hash key is vendorId:productId only, not label) but with different
    # names - producing two group objects sharing one id, an invalid/ambiguous policy this script
    # refuses to build rather than silently emit.
    $pairKey = "$($d.vendorId.ToLowerInvariant()):$($d.productId.ToLowerInvariant())"
    if ($seenPairs.ContainsKey($pairKey)) {
        throw "Duplicate vendorId+productId pair '$pairKey' on entries '$($seenPairs[$pairKey])' and '$($d.label)' - each device's vendorId+productId pair determines its group id (design.md Section 4) and must be unique within one config file, even if labels differ. If both labels genuinely refer to the same physical device model, keep only one entry."
    }
    $seenPairs[$pairKey] = $d.label
}

Assert-MgConnected
Write-Host "macOS vendor+product device allowlist: extending parent policy '$parentDisplayName'." -ForegroundColor Cyan

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
#        technique the Bluetooth sibling fragment's own scripts use and document) ---
$policyMatch = [regex]::Match($mobileConfigXml, '<key>policy</key>\s*<string>(.*?)</string>', [System.Text.RegularExpressions.RegexOptions]::Singleline)
if (-not $policyMatch.Success) {
    throw "Could not locate the embedded deviceControl.policy JSON in the parent policy's .mobileconfig payload - it does not look like the expected object. Refusing to modify it."
}
$originalEscapedJson = $policyMatch.Groups[1].Value
$parsedPolicy = (ConvertFrom-XmlEscaped $originalEscapedJson) | ConvertFrom-Json

if (-not $parsedPolicy.groups -or -not $parsedPolicy.rules -or -not $parsedPolicy.settings) {
    throw "Parent policy's deviceControl.policy JSON is missing groups/rules/settings - it does not look like the expected object. Refusing to modify it."
}

# --- 3. Refuse to run if the parent's ApprovedBackupDrives group is not present - this script only
#        extends it, it never creates it from scratch ---
$approvedGroup = $parsedPolicy.groups | Where-Object { $_.id -eq $script:ApprovedBackupDrivesGroupId } | Select-Object -First 1
if (-not $approvedGroup) {
    throw "Prerequisite not met: the ApprovedBackupDrives group (from scenarios/dlp/defender-device-control-usb-allowlist-macos) was not found on '$parentDisplayName'. Deploy that fragment's deploy/New-MacDeviceControlUsbAllowlistPolicy.ps1 first."
}
if ($approvedGroup.query.'$type' -ne 'any') {
    throw "ApprovedBackupDrives group's query.`$type is '$($approvedGroup.query.'$type')', expected 'any' - it does not look like the expected parent-scenario shape. Refusing to modify it."
}

# --- 4. Compute the desired sub-group set from -ConfigPath (deterministic ids, keyed on
#        vendorId+productId only - a cosmetic label rename never changes a device's id) ---
$desiredDevices = foreach ($d in $configDevices) {
    $vendorNorm = $d.vendorId.ToLowerInvariant()
    $productNorm = $d.productId.ToLowerInvariant()
    [pscustomobject]@{
        Label     = $d.label
        VendorId  = $vendorNorm
        ProductId = $productNorm
        GroupId   = Get-DeterministicSubGroupId -NamespaceHex $script:SubGroupNamespaceHex -Name "mac-vendor-product-match/v1/$vendorNorm`:$productNorm"
        GroupName = "$script:NamePrefix$($d.label)"
    }
}
$desiredGroupIds = @($desiredDevices | ForEach-Object { $_.GroupId })

# --- 5. Existing sub-groups owned by this fragment (identified by name prefix - never touches a
#        group with a different prefix, including another sibling fragment's groups) ---
$existingOwnedGroups = @($parsedPolicy.groups | Where-Object { $_.name -like "$($script:NamePrefix)*" })
$existingOwnedGroupIds = @($existingOwnedGroups | ForEach-Object { $_.id })
$existingGroupIdClauses = @($approvedGroup.query.clauses | Where-Object { $_.'$type' -eq 'groupId' } | ForEach-Object { $_.value })

$groupsMatch = -not (Compare-Object -ReferenceObject $existingOwnedGroupIds -DifferenceObject $desiredGroupIds)
$clausesMatch = -not (Compare-Object -ReferenceObject ($existingGroupIdClauses | Sort-Object) -DifferenceObject ($desiredGroupIds | Sort-Object))
$isFullyReconciled = $groupsMatch -and $clausesMatch -and ($existingOwnedGroupIds.Count -eq $desiredGroupIds.Count)

if ($isFullyReconciled -and -not $Force) {
    Write-Host "  [coverage] vendorId/productId allowlist already matches -ConfigPath's current definition ($($desiredDevices.Count) device(s)) on '$parentDisplayName' - not modified. Pass -Force to reconcile anyway." -ForegroundColor Yellow
    Write-Host "`nDone. No change made." -ForegroundColor Cyan
    return
}
if (-not $isFullyReconciled -and $existingOwnedGroups.Count -gt 0) {
    Write-Host "  [coverage] Partial or drifted vendorId/productId allowlist state detected on '$parentDisplayName' ($($existingOwnedGroups.Count) existing owned sub-group(s), $($desiredDevices.Count) desired) - reconciling to a complete, consistent state matching -ConfigPath." -ForegroundColor Yellow
}

# --- 6. Build the reconciled groups: keep every group this fragment doesn't own untouched, in
#        original relative order; insert this fragment's desired sub-groups immediately BEFORE
#        ApprovedBackupDrives (groupId clauses require their target group to already be defined
#        earlier in the array - Microsoft's Clause reference table, see .NOTES), then
#        ApprovedBackupDrives itself with its query.clauses rebuilt: every non-groupId clause
#        (serialNumber, owned by the parent script) reproduced byte-for-byte, followed by one
#        groupId clause per desired device ---
$newGroups = New-Object System.Collections.Generic.List[object]
foreach ($g in $parsedPolicy.groups) {
    if ($g.id -eq $script:ApprovedBackupDrivesGroupId) {
        foreach ($d in $desiredDevices) {
            $newGroups.Add([ordered]@{
                '$type' = 'device'
                id      = $d.GroupId
                name    = $d.GroupName
                query   = [ordered]@{
                    '$type'  = 'and'
                    clauses  = @(
                        [ordered]@{ '$type' = 'primaryId'; value = 'removable_media_devices' }
                        [ordered]@{ '$type' = 'vendorId'; value = $d.VendorId }
                        [ordered]@{ '$type' = 'productId'; value = $d.ProductId }
                    )
                }
            })
        }
        $preservedClauses = @($approvedGroup.query.clauses | Where-Object { $_.'$type' -ne 'groupId' })
        $groupIdClauses = @($desiredDevices | ForEach-Object { [ordered]@{ '$type' = 'groupId'; value = $_.GroupId } })
        $newGroups.Add([ordered]@{
            '$type' = 'device'
            id      = $approvedGroup.id
            name    = $approvedGroup.name
            query   = [ordered]@{
                '$type'  = 'any'
                clauses  = @($preservedClauses) + @($groupIdClauses)
            }
        })
    }
    elseif ($g.id -in $existingOwnedGroupIds) {
        continue  # this fragment's own stale sub-group - re-added fresh above, or dropped if no longer desired
    }
    else {
        $newGroups.Add($g)
    }
}

foreach ($d in $desiredDevices) {
    Write-Host "  [plan] Approving device '$($d.Label)' (vendorId=$($d.VendorId), productId=$($d.ProductId), groupId=$($d.GroupId))." -ForegroundColor DarkCyan
}
$removedLabels = @($existingOwnedGroups | Where-Object { $_.id -notin $desiredGroupIds } | ForEach-Object { $_.name.Substring($script:NamePrefix.Length) })
foreach ($label in $removedLabels) {
    Write-Host "  [plan] Removing device no longer in -ConfigPath: '$label'." -ForegroundColor DarkCyan
}

$desiredPolicy = [ordered]@{ groups = @($newGroups); rules = $parsedPolicy.rules; settings = $parsedPolicy.settings }
$newPolicyJson = $desiredPolicy | ConvertTo-Json -Depth 12 -Compress
$newEscapedJson = ConvertTo-XmlEscaped $newPolicyJson

Write-Host "  [plan] $($parsedPolicy.groups.Count) existing groups -> $($newGroups.Count) groups (rules unchanged - both parent rules already key off ApprovedBackupDrives' group id)." -ForegroundColor DarkCyan

# --- 7. Substitute only the policy <string> node's content; every other plist key is untouched ---
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

if ($PSCmdlet.ShouldProcess($parentDisplayName, "PATCH $configUri/$($parent.id) (reconcile vendorId/productId device allowlist)")) {
    Invoke-MgGraphRequest -Method PATCH -Uri "$configUri/$($parent.id)" -Body ($body | ConvertTo-Json -Depth 12) | Out-Null
    Write-Host "  [coverage] vendorId/productId device allowlist reconciled on '$parentDisplayName' (id $($parent.id))" -ForegroundColor Green
}

Write-Host "`nDone. This does not change the parent policy's assignment. Run validate/Test-MacVendorProductDeviceAllowlist.ps1 to verify." -ForegroundColor Cyan
```

#### `config/mac-vendor-product-device-allowlist.sample.json`

```json
{
  "parentPolicyDisplayName": "Device Control (macOS) - USB Removable Media Default-Deny Allowlist",
  "vendorProductDevices": [
    { "label": "REPLACE - e.g. IT-issued imaging dock (no readable serial)", "vendorId": "0951", "productId": "1666" }
  ]
}
```

#### `Remove-MacVendorProductDeviceAllowlist.ps1`

```powershell
#Requires -Version 7.0
<#
.SYNOPSIS
    Removes every vendorId/productId compound-matched device exception this fragment added,
    reverting the parent's "ApprovedBackupDrives" group to serialNumber-only matching.

.DESCRIPTION
    Surgical rollback for scenarios/dlp/defender-device-control-usb-allowlist-macos-vendor-product-
    matching: removes every "VendorProductMatch-*" sub-group this fragment's deploy/
    Add-MacVendorProductDeviceAllowlist.ps1 added, and strips every "groupId" clause from the
    parent's "ApprovedBackupDrives" group's query.clauses array - by name prefix, the same
    identification the deploy and validate scripts use.

    This does NOT touch the parent policy's serialNumber-based ApprovedBackupDrives entries, the
    AllRemovableStorage catch-all group, either of the parent's two rules, the Apple/Portable/
    Bluetooth sibling fragments' own groups and rules, the assignment, or the policy object's
    identity - only this fragment's own additions are removed. Removable-media devices approved only
    by vendorId/productId revert to DENIED (the "ApprovedBackupDrives" OR-branch they matched no
    longer exists); any device also matched by a still-present serialNumber clause is unaffected.

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
    ./Remove-MacVendorProductDeviceAllowlist.ps1 -WhatIf

.EXAMPLE
    ./Remove-MacVendorProductDeviceAllowlist.ps1
    # Strips every vendorId/productId device exception back out.

.NOTES
    Sources: same as deploy/Add-MacVendorProductDeviceAllowlist.ps1's .NOTES block.
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

$script:ApprovedBackupDrivesGroupId = '22222222-bbbb-4ccc-8ddd-222222222222'
$script:NamePrefix = 'VendorProductMatch-'

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

$approvedGroup = $parsedPolicy.groups | Where-Object { $_.id -eq $script:ApprovedBackupDrivesGroupId } | Select-Object -First 1
if (-not $approvedGroup) {
    Write-Host "ApprovedBackupDrives group not found on '$ParentPolicyDisplayName' - nothing for this fragment to remove (the parent scenario may not be deployed)." -ForegroundColor Yellow
    return
}

$ownedGroups = @($parsedPolicy.groups | Where-Object { $_.name -like "$($script:NamePrefix)*" })
$existingGroupIdClauseCount = @($approvedGroup.query.clauses | Where-Object { $_.'$type' -eq 'groupId' }).Count

if ($ownedGroups.Count -eq 0 -and $existingGroupIdClauseCount -eq 0) {
    Write-Host "No vendorId/productId device allowlist currently present on '$ParentPolicyDisplayName' - nothing to remove." -ForegroundColor Yellow
    return
}

foreach ($g in $ownedGroups) {
    Write-Host "  [plan] Removing device: '$($g.name.Substring($script:NamePrefix.Length))'." -ForegroundColor DarkCyan
}

$keptGroups = @($parsedPolicy.groups | Where-Object { $_.name -notlike "$($script:NamePrefix)*" -and $_.id -ne $script:ApprovedBackupDrivesGroupId })
$revertedClauses = @($approvedGroup.query.clauses | Where-Object { $_.'$type' -ne 'groupId' })
$revertedApprovedGroup = [ordered]@{
    '$type' = 'device'
    id      = $approvedGroup.id
    name    = $approvedGroup.name
    query   = [ordered]@{ '$type' = 'any'; clauses = @($revertedClauses) }
}
$desiredGroups = @($keptGroups) + @($revertedApprovedGroup)

$desiredPolicy = [ordered]@{ groups = $desiredGroups; rules = $parsedPolicy.rules; settings = $parsedPolicy.settings }
$newPolicyJson = $desiredPolicy | ConvertTo-Json -Depth 12 -Compress
$newEscapedJson = ConvertTo-XmlEscaped $newPolicyJson

Write-Host "  [plan] $($parsedPolicy.groups.Count) existing groups -> $($desiredGroups.Count) groups after removing the vendorId/productId device allowlist (ApprovedBackupDrives reverts to $($revertedClauses.Count) serialNumber clause(s) only)." -ForegroundColor DarkCyan

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

if ($PSCmdlet.ShouldProcess($ParentPolicyDisplayName, "PATCH $configUri/$($parent.id) (remove vendorId/productId device allowlist)")) {
    Invoke-MgGraphRequest -Method PATCH -Uri "$configUri/$($parent.id)" -Body ($body | ConvertTo-Json -Depth 12) | Out-Null
    Write-Host "  [coverage] vendorId/productId device allowlist removed from '$ParentPolicyDisplayName' (id $($parent.id))" -ForegroundColor Green
}

Write-Host "`nDone. Devices that were approved only by vendorId/productId revert to DENIED, not to unrestricted - see rollback.md. Any device also matched by a still-present serialNumber clause is unaffected." -ForegroundColor Cyan
```