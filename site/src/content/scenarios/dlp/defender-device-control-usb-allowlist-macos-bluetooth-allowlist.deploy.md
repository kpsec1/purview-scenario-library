---
part: "deploy"
parent: "dlp/defender-device-control-usb-allowlist-macos-bluetooth-allowlist"
---
The scripts and configuration below deploy this scenario. Review them, then run in order — each is designed to be idempotent and has a matching rollback.


#### `Add-MacBluetoothDeviceAllowlist.ps1`

```powershell
#Requires -Version 7.0
<#
.SYNOPSIS
    Adds a single vendorId+productId-matched approved-device exception to the "Deny-AllBluetoothDevices"
    rule created by scenarios/dlp/defender-device-control-usb-allowlist-macos-portable-device-coverage,
    inside the shared macOSCustomConfiguration object created by
    scenarios/dlp/defender-device-control-usb-allowlist-macos.

.DESCRIPTION
    The portable-device-coverage fragment ships Bluetooth as default-deny-only, no exceptions,
    because Microsoft's own worked exception sample for bluetooth_devices
    (deny_all_bluetooth_devices_except_samsung.json) uses a structurally different, single-device
    vendorId+productId AND-match, not the OR'd multi-device serialNumber pattern used for the
    Apple/Portable families (portable-device-coverage/design.md Section 5). This script closes that
    gap by adding exactly ONE approved-device exception in the same shape as Microsoft's own sample,
    without introducing a second, differently-shaped multi-device schema.

    This script does NOT create a new Intune profile and does NOT create a new top-level
    Bluetooth catch-all group or Bluetooth feature flag - both already exist once
    defender-device-control-usb-allowlist-macos-portable-device-coverage/deploy/
    Add-MacPortableDeviceCoverage.ps1 has been run. This script REFUSES to run if that
    prerequisite fragment's AllBluetoothDevices group and Deny-AllBluetoothDevices rule (identified
    by their fixed GUIDs) are not both present - see README.md Section 3.

    What this script adds/reconciles, by fixed GUID:
      1. One group, "ApprovedBluetoothDevice" - $type: "and", clauses:
         [primaryId=bluetooth_devices, vendorId=<config>, productId=<config>] - the exact shape
         Microsoft's own deny_all_bluetooth_devices_except_samsung.json sample uses for its
         "Samsung Galaxy S21" exception group (see .NOTES).
      2. Rewrites the EXISTING "Deny-AllBluetoothDevices" rule (same fixed GUID the
         portable-device-coverage fragment created) to add excludeGroups = [ApprovedBluetoothDevice
         group id] - its two deny/auditDeny entries are reproduced byte-for-byte unchanged from that
         fragment's own New-DenyRule call (same entry ids, same access list) so this is additive,
         not destructive, to that rule.
      3. One new rule, "Allow-ApprovedBluetoothDevice" - entries: allow + auditAllow, access =
         the two documented bluetoothDevice access strings. This script adds an explicit "allow"
         enforcement entry (not just auditAllow, unlike Microsoft's own sample) because this
         fragment's shared policy inherits settings.global.defaultEnforcement = "deny" (fail-closed)
         from the parent scenario - Microsoft's own sample instead relies on defaultEnforcement =
         "allow" (its own document's default), where excluding a device from the deny rule is
         sufficient by itself. Under a fail-closed default, an excluded-but-otherwise-unmatched
         device falls through to deny, not allow - so an explicit allow entry is required to actually
         grant access, the same reasoning already applied to the Apple/Portable approved-device
         allow rules in the portable-device-coverage fragment. See design.md Section 4 and README.md
         Section 6.

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

    Idempotent: reads the live policy JSON, detects whether this fragment's group/rule are already
    present (by fixed GUID), and with -Force reconciles the approved device to -ConfigPath's current
    definition. Without -Force, an already-covered policy is reported and left untouched.

.PARAMETER ConfigPath
    Path to the JSON config (parentPolicyDisplayName, approvedBluetoothDevices[] - exactly 0 or 1
    entries in this v1 fragment, see .NOTES). Defaults to the sibling
    'config/mac-bluetooth-device-allowlist.sample.json' - copy and edit it.

.PARAMETER GraphBaseUri
    Graph base URI. Defaults to 'https://graph.microsoft.com/v1.0'.

.PARAMETER Force
    If this fragment's group/rule already exist, reconcile the approved device to -ConfigPath's
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
    SCOPE: exactly one approved Bluetooth device in v1 - this script throws if -ConfigPath's
    approvedBluetoothDevices array has more than one entry. Supporting more than one AND'd
    vendorId+productId device would need either a separate allow rule per device (includeGroups
    combine with AND semantics, so multiple device groups cannot be combined in one rule's
    includeGroups - confirmed directly from Microsoft's own Access policy rule reference table,
    "If multiple groups are in the includeGroups, it's AND") or the per-device sub-group +
    groupId-clause-nesting technique this repository's sibling scenarios already defer as unverified
    complexity (defender-device-control-usb-allowlist-macos-vendor-product-matching/,
    defender-device-control-usb-allowlist-macos-portable-device-coverage/design.md Section 5).
    Tracked as a follow-up in PROGRESS.md rather than guessed at here.

    vendorId/productId identify a DEVICE MODEL, not a unique physical unit - unlike this repository's
    serialNumber-based allowlists (parent scenario, Apple/Portable families), any Bluetooth device
    sharing the configured vendorId+productId pair (e.g. a colleague's identical phone/scanner model)
    matches this exception, not just one specific approved unit. See README.md Section 11.

    excludeGroups OR semantics confirmed directly from Microsoft's "Access policy rule" reference
    table: "The groups that the policy doesn't apply to... If multiple groups are in the
    excludeGroups, it's OR." (only one group is ever placed there by this v1 script, but the
    semantics matter for the design decision above).

    Sources (Microsoft Learn, verify before production use):
    - Device Control for macOS (Query/Clause/Access policy rule/Enforcement/Access Types reference
      tables - vendorId "Four digit hexadecimal string", productId "Four digit hexadecimal string",
      query $type "and" clause AND semantics, includeGroups AND / excludeGroups OR semantics,
      settings.global.defaultEnforcement "allow" (default) or "deny"):
      https://learn.microsoft.com/defender-endpoint/mac-device-control-overview
    - Sample macOS device control policies (deny_all_bluetooth_devices_except_samsung.json - the
      exact vendorId+productId AND-match exception-group shape this script reproduces, confirmed by
      direct fetch of the raw file content during this fragment's build):
      https://github.com/microsoft/mdatp-devicecontrol/blob/main/macOS/policy/samples/deny_all_bluetooth_devices_except_samsung.json
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
$script:ApprovedBluetoothGroupId = 'd1d2d3d4-3333-4c3c-8c3c-333333333302'
$script:AllowBluetoothRuleId     = 'd1d2d3d4-3333-4c3c-8c3c-333333333311'

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

# --- Load and validate config ---
if (-not (Test-Path -LiteralPath $ConfigPath)) { throw "Config file not found: $ConfigPath" }
$cfg = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
$parentDisplayName = if ($cfg.parentPolicyDisplayName) { $cfg.parentPolicyDisplayName } else { 'Device Control (macOS) - USB Removable Media Default-Deny Allowlist' }
$approvedDevices = @($cfg.approvedBluetoothDevices)

if ($approvedDevices.Count -gt 1) {
    throw "This v1 fragment supports exactly 0 or 1 approvedBluetoothDevices entries (got $($approvedDevices.Count)) - see .NOTES for why multi-device support is deferred, and PROGRESS.md for the tracked follow-up."
}
foreach ($d in $approvedDevices) {
    if (-not $d.label) { throw "Every approvedBluetoothDevices entry requires a 'label'." }
    Test-FourDigitHex -Value $d.vendorId -FieldName 'vendorId' -Label $d.label
    Test-FourDigitHex -Value $d.productId -FieldName 'productId' -Label $d.label
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
$existingRuleIds  = @($parsedPolicy.rules  | ForEach-Object { $_.id })
$denyBluetoothRule = $parsedPolicy.rules | Where-Object { $_.id -eq $script:DenyBluetoothRuleId } | Select-Object -First 1

if ($script:AllBluetoothGroupId -notin $existingGroupIds -or -not $denyBluetoothRule) {
    throw "Prerequisite not met: the AllBluetoothDevices group and/or Deny-AllBluetoothDevices rule (from scenarios/dlp/defender-device-control-usb-allowlist-macos-portable-device-coverage) were not found on '$parentDisplayName'. Deploy that fragment's deploy/Add-MacPortableDeviceCoverage.ps1 first - this script only adds an approved-device exception to its Bluetooth coverage, it does not create Bluetooth coverage itself."
}

# --- 4. Coverage detection (by this fragment's own fixed GUIDs, not by value) ---
$hasApprovedGroup = $script:ApprovedBluetoothGroupId -in $existingGroupIds
$hasAllowRule     = $script:AllowBluetoothRuleId -in $existingRuleIds
$hasExclude       = $denyBluetoothRule.excludeGroups -contains $script:ApprovedBluetoothGroupId
$isFullyReconciled = ($approvedDevices.Count -eq 1 -and $hasApprovedGroup -and $hasAllowRule -and $hasExclude) `
    -or ($approvedDevices.Count -eq 0 -and -not $hasApprovedGroup -and -not $hasAllowRule -and -not $hasExclude)

if ($isFullyReconciled -and -not $Force) {
    Write-Host "  [coverage] Bluetooth device allowlist already matches -ConfigPath's current definition on '$parentDisplayName' - not modified. Pass -Force to reconcile anyway." -ForegroundColor Yellow
    Write-Host "`nDone. No change made." -ForegroundColor Cyan
    return
}
if (-not $isFullyReconciled -and ($hasApprovedGroup -or $hasAllowRule -or $hasExclude) -and -not $Force) {
    Write-Host "  [coverage] Partial or drifted Bluetooth allowlist state detected on '$parentDisplayName' (group present: $hasApprovedGroup, allow rule present: $hasAllowRule, exclude present: $hasExclude) - reconciling to a complete, consistent state matching -ConfigPath." -ForegroundColor Yellow
}

# --- 5. Build the reconciled groups/rules: keep every group/rule not owned by this fragment
#        untouched (including the prerequisite fragment's other groups/rules), rebuild the shared
#        Deny-AllBluetoothDevices rule with its original two entries reproduced byte-for-byte plus
#        this fragment's excludeGroups, and (re)add this fragment's own group/allow-rule fresh from
#        -ConfigPath ---
$keptGroups = @($parsedPolicy.groups | Where-Object { $_.id -ne $script:ApprovedBluetoothGroupId })
$keptRules  = @($parsedPolicy.rules  | Where-Object { $_.id -notin @($script:DenyBluetoothRuleId, $script:AllowBluetoothRuleId) })

$newGroups = @()
$newRules  = @()

if ($approvedDevices.Count -eq 1) {
    $d = $approvedDevices[0]
    # Exact shape of Microsoft's own deny_all_bluetooth_devices_except_samsung.json exception group.
    $newGroups += [ordered]@{
        '$type' = 'device'
        id      = $script:ApprovedBluetoothGroupId
        name    = 'ApprovedBluetoothDevice'
        query   = [ordered]@{
            '$type'  = 'and'
            clauses  = @(
                [ordered]@{ '$type' = 'primaryId'; value = 'bluetooth_devices' }
                [ordered]@{ '$type' = 'vendorId'; value = $d.vendorId }
                [ordered]@{ '$type' = 'productId'; value = $d.productId }
            )
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
    Write-Host "  [plan] Approving Bluetooth device '$($d.label)' (vendorId=$($d.vendorId), productId=$($d.productId))." -ForegroundColor DarkCyan
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
    Write-Host '  [plan] No approvedBluetoothDevices configured - removing this fragment''s exception (any other pre-existing excludeGroups entry is preserved).' -ForegroundColor DarkCyan
}

$desiredGroups = @($keptGroups) + @($newGroups)
$desiredRules  = @($keptRules) + @($newRules)

$desiredPolicy = [ordered]@{ groups = $desiredGroups; rules = $desiredRules; settings = $parsedPolicy.settings }
$newPolicyJson = $desiredPolicy | ConvertTo-Json -Depth 12 -Compress
$newEscapedJson = ConvertTo-XmlEscaped $newPolicyJson

Write-Host "  [plan] $($parsedPolicy.groups.Count) existing groups / $($parsedPolicy.rules.Count) existing rules -> $($desiredGroups.Count) groups / $($desiredRules.Count) rules." -ForegroundColor DarkCyan

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
```

#### `config/mac-bluetooth-device-allowlist.sample.json`

```json
{
  "parentPolicyDisplayName": "Device Control (macOS) - USB Removable Media Default-Deny Allowlist",
  "approvedBluetoothDevices": [
    { "label": "REPLACE - e.g. IT-issued barcode scanner", "vendorId": "0075", "productId": "0100" }
  ]
}
```

#### `Remove-MacBluetoothDeviceAllowlist.ps1`

```powershell
#Requires -Version 7.0
<#
.SYNOPSIS
    Removes the approved Bluetooth device exception this fragment added, reverting the
    Deny-AllBluetoothDevices rule (owned by defender-device-control-usb-allowlist-macos-portable-
    device-coverage) to unconditional deny with no exceptions.

.DESCRIPTION
    Surgical rollback for scenarios/dlp/defender-device-control-usb-allowlist-macos-bluetooth-
    allowlist: removes the ApprovedBluetoothDevice group and Allow-ApprovedBluetoothDevice rule this
    fragment's deploy/Add-MacBluetoothDeviceAllowlist.ps1 added, and strips excludeGroups from the
    Deny-AllBluetoothDevices rule - by fixed GUID, the same identification the deploy and validate
    scripts use.

    This does NOT touch the parent policy's removableMedia coverage, the portable-device-coverage
    fragment's Apple/Portable groups and rules, the AllBluetoothDevices catch-all group, the
    Deny-AllBluetoothDevices rule's own two deny/auditDeny entries, the assignment, or the policy
    object's identity - only this fragment's own additions are removed. Bluetooth reverts to the
    portable-device-coverage fragment's original default-deny-only-no-exceptions state, not to
    "unrestricted."

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
    ./Remove-MacBluetoothDeviceAllowlist.ps1 -WhatIf

.EXAMPLE
    ./Remove-MacBluetoothDeviceAllowlist.ps1
    # Strips the Bluetooth device exception back out. Bluetooth reverts to unconditional deny.

.NOTES
    Sources: same as deploy/Add-MacBluetoothDeviceAllowlist.ps1's .NOTES block.
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

$script:DenyBluetoothRuleId      = 'd1d2d3d4-3333-4c3c-8c3c-333333333310'
$script:ApprovedBluetoothGroupId = 'd1d2d3d4-3333-4c3c-8c3c-333333333302'
$script:AllowBluetoothRuleId     = 'd1d2d3d4-3333-4c3c-8c3c-333333333311'

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

function ConvertTo-Utf8Base64 { param([Parameter(Mandatory)][string]$Text) [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($Text)) }
function ConvertFrom-Utf8Base64 { param([Parameter(Mandatory)][string]$Base64) [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($Base64)) }
function ConvertTo-XmlEscaped { param([Parameter(Mandatory)][string]$Text) $Text -replace '&', '&amp;' -replace '<', '&lt;' -replace '>', '&gt;' }
function ConvertFrom-XmlEscaped { param([Parameter(Mandatory)][string]$Text) $Text -replace '&lt;', '<' -replace '&gt;', '>' -replace '&amp;', '&' }

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

$existingGroupIds = @($parsedPolicy.groups | ForEach-Object { $_.id })
$denyBluetoothRule = $parsedPolicy.rules | Where-Object { $_.id -eq $script:DenyBluetoothRuleId } | Select-Object -First 1

if (-not $denyBluetoothRule) {
    Write-Host "Deny-AllBluetoothDevices rule not found on '$ParentPolicyDisplayName' - nothing for this fragment to remove (the portable-device-coverage prerequisite may not be deployed)." -ForegroundColor Yellow
    return
}
if ($script:ApprovedBluetoothGroupId -notin $existingGroupIds -and -not $denyBluetoothRule.excludeGroups) {
    Write-Host "No Bluetooth device allowlist currently present on '$ParentPolicyDisplayName' - nothing to remove." -ForegroundColor Yellow
    return
}

$keptGroups = @($parsedPolicy.groups | Where-Object { $_.id -ne $script:ApprovedBluetoothGroupId })
$keptRules  = @($parsedPolicy.rules  | Where-Object { $_.id -ne $script:AllowBluetoothRuleId })

# Revert the shared deny rule - entries reproduced unchanged, remove only this fragment's own
# excludeGroups entry, preserving any other pre-existing exclusion this fragment doesn't own.
$otherExcludeGroups = @($denyBluetoothRule.excludeGroups | Where-Object { $_ -ne $script:ApprovedBluetoothGroupId })
$revertedDenyRule = [ordered]@{
    id            = $denyBluetoothRule.id
    name          = $denyBluetoothRule.name
    includeGroups = $denyBluetoothRule.includeGroups
    entries       = $denyBluetoothRule.entries
}
if ($otherExcludeGroups.Count -gt 0) { $revertedDenyRule.excludeGroups = @($otherExcludeGroups) }
$desiredRules = @($keptRules | Where-Object { $_.id -ne $script:DenyBluetoothRuleId }) + @($revertedDenyRule)

$desiredPolicy = [ordered]@{ groups = $keptGroups; rules = $desiredRules; settings = $parsedPolicy.settings }
$newPolicyJson = $desiredPolicy | ConvertTo-Json -Depth 12 -Compress
$newEscapedJson = ConvertTo-XmlEscaped $newPolicyJson

Write-Host "  [plan] $($parsedPolicy.groups.Count) existing groups / $($parsedPolicy.rules.Count) existing rules -> $($keptGroups.Count) groups / $($desiredRules.Count) rules after removing the Bluetooth device allowlist." -ForegroundColor DarkCyan

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

if ($PSCmdlet.ShouldProcess($ParentPolicyDisplayName, "PATCH $configUri/$($parent.id) (remove Bluetooth device allowlist)")) {
    Invoke-MgGraphRequest -Method PATCH -Uri "$configUri/$($parent.id)" -Body ($body | ConvertTo-Json -Depth 12) | Out-Null
    Write-Host "  [coverage] Bluetooth device allowlist removed from '$ParentPolicyDisplayName' (id $($parent.id))" -ForegroundColor Green
}

Write-Host "`nDone. Bluetooth devices revert to unconditional deny (the portable-device-coverage fragment's original state), not to unrestricted - see rollback.md." -ForegroundColor Cyan
```