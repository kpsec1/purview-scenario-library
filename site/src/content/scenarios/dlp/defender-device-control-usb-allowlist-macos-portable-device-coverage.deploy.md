---
part: "deploy"
parent: "dlp/defender-device-control-usb-allowlist-macos-portable-device-coverage"
---
The scripts and configuration below deploy this scenario. Review them, then run in order — each is designed to be idempotent and has a matching rollback.


#### `Add-MacPortableDeviceCoverage.ps1`

```powershell
#Requires -Version 7.0
<#
.SYNOPSIS
    Extends the "Device Control (macOS) - USB Removable Media Default-Deny Allowlist"
    macOSCustomConfiguration object (scenarios/dlp/defender-device-control-usb-allowlist-macos) to
    also cover the apple_devices, portable_devices, and bluetooth_devices primaryId families.

.DESCRIPTION
    The parent scenario's device control policy scopes enforcement to
    primaryId: removable_media_devices only. Microsoft documents apple_devices (iOS/iPadOS),
    portable_devices (cameras, Android phones in PTP mode), and bluetooth_devices as three
    separate, independently-enforced primaryId families - a device that enumerates as one of them
    is completely invisible to a removable_media_devices-scoped policy: no block, no audit event
    (defender-device-control-usb-allowlist-macos/README.md Section 11, the confirmed Red Team
    finding this fragment closes - the direct macOS analog of the Windows WPD-coverage sibling).

    This script does NOT create a second Intune profile. It widens the parent's existing
    macOSCustomConfiguration object's .mobileconfig payload in place by:
      1. Enabling three additional device-control features (appleDevice, portableDevice,
         bluetoothDevice - each defaults to disabled per Microsoft's own documentation, "if you
         don't configure this value, it doesn't apply").
      2. Adding one catch-all deny-scoped group per family (AllAppleDevices, AllPortableDevices,
         AllBluetoothDevices - primaryId = apple_devices / portable_devices / bluetooth_devices).
      3. Optionally adding an approved-devices group (ApprovedAppleDevices / ApprovedPortableDevices,
         serialNumber-matched, OR'd) for the Apple and Portable families if -ConfigPath supplies
         one or more entries - confirmed directly against Microsoft's own published
         audit_all_apple_devices_except_serial_numbers.json sample, which uses this exact
         serialNumber/OR/excludeGroups shape for the apple_devices family (see .NOTES). Bluetooth
         has NO approved-device allowlist in this fragment - see .NOTES and README.md Section 11.
      4. Adding a Deny+AuditDeny rule pair per family (scoped to the catch-all group, excluding the
         approved group where one exists) and an Allow+AuditAllow rule pair per family that has an
         approved-device group - entry $type and access-string lists taken verbatim from
         Microsoft's official "Device Control for macOS" Access Types table and cross-checked
         against three of Microsoft's own published GitHub sample policies (see .NOTES).

    Every existing group/rule/setting in the parent's live policy JSON (its removableMedia
    coverage, its ApprovedBackupDrives group, its two RemovableMediaDevices rules, and its
    settings.global/settings.ux) is read from the live object and carried through untouched - this
    script only adds entries, it never removes or edits anything it did not itself add on a prior
    run (identified by this script's own fixed GUIDs).

    Unlike the Windows WPD-coverage sibling (which edits an array of independent OMA-URI
    omaSettings entries), macOS's device control policy is ONE opaque JSON string embedded inside
    the .mobileconfig plist (deviceControl.policy). This script extracts that JSON string via a
    targeted regex against the exact <key>policy</key><string>...</string> shape the parent
    scenario's own New-MacDeviceControlUsbAllowlistPolicy.ps1 always produces (both scripts are
    co-authored in this repo against the same, known output format - the same regex-over-full-XML-
    parse trade-off the parent scenario's own validate script already documents and accepts, see
    defender-device-control-usb-allowlist-macos/reviews.md, Blue Team finding 2), merges in the new
    groups/rules/features, re-escapes, and substitutes only that one <string> node's content back
    into the original .mobileconfig - every other plist key (PayloadUUID, PayloadIdentifier,
    PayloadDisplayName, etc.) is left byte-for-byte untouched.

    Idempotent: reads the live policy JSON, detects whether coverage for all three families is
    already present (by this script's own fixed group/rule GUIDs, not by value), and with -Force
    reconciles to -ConfigPath's current approved-device definition. Without -Force, an
    already-covered policy is reported and left untouched.

    PREREQUISITE this script does not perform: the parent policy
    (deploy/New-MacDeviceControlUsbAllowlistPolicy.ps1 in
    scenarios/dlp/defender-device-control-usb-allowlist-macos/) must already exist. This script
    refuses to run and create a new object from scratch - see README.md Section 3.

.PARAMETER ConfigPath
    Path to the JSON config (parentPolicyDisplayName, approvedAppleDevices[], approvedPortableDevices[]).
    Defaults to the sibling 'config/mac-portable-device-coverage.sample.json' - copy and edit it.

.PARAMETER GraphBaseUri
    Graph base URI. Defaults to 'https://graph.microsoft.com/v1.0'.

.PARAMETER Force
    If coverage for all three families already exists on the parent policy, reconcile the
    approved-device groups to match -ConfigPath's current definition instead of skipping.

.PARAMETER WhatIf
    Standard PowerShell ShouldProcess dry-run. Reports the PATCH that would be made without
    calling any mutating Graph endpoint.

.EXAMPLE
    Connect-MgGraph -ClientId $AppId -TenantId $TenantId -CertificateThumbprint $Thumbprint
    ./Add-MacPortableDeviceCoverage.ps1 -ConfigPath ./config/my-tenant.json -WhatIf

.EXAMPLE
    ./Add-MacPortableDeviceCoverage.ps1 -ConfigPath ./config/my-tenant.json

.NOTES
    SCOPE: Bluetooth devices have NO approved-device allowlist in this fragment - always
    default-deny, no exceptions. Microsoft's own worked sample for this family
    (deny_all_bluetooth_devices_except_samsung.json) demonstrates an exception group matched by
    vendorId+productId (AND'd in a single group query), not serialNumber - a structurally different,
    single-device matching model from the OR'd multi-device serialNumber pattern this script uses
    for Apple/Portable devices and the parent scenario already uses for removable media. Rather than
    introduce a second, differently-shaped config schema for one family in this fragment, Bluetooth
    coverage is deliberately default-deny-only here; a vendorId+productId-matched Bluetooth
    allowlist is tracked as a follow-up in PROGRESS.md (see README.md Section 11, design.md Section
    5) - the same "state the gap honestly rather than guess a shape" discipline this repo's other
    device-control scenarios already follow (e.g. the Windows sibling's deferred VID_PID
    compound-matching follow-up).

    VERIFY (README.md Section 11): serialNumber-matching for the portable_devices family has no
    directly-confirmed Microsoft worked example (only apple_devices does, via
    audit_all_apple_devices_except_serial_numbers.json). Microsoft's "Device Control for macOS"
    Clause reference table is presented as one flat, family-unscoped list (unlike the ambiguity the
    Windows sibling's WPD-coverage fragment had to flag for SerialNumberId/VID_PID), which is
    reasonable but not proof this property is honored for portable_devices specifically.
    validate/Test-MacPortableDeviceCoverage.ps1 checks approvedPortableDevices serial numbers as
    [WARN], not [PASS]/[FAIL], pending pilot-tenant confirmation.

    Entry $type capitalization: this script uses the lowercase-first-letter forms appleDevice/
    portableDevice/bluetoothDevice for entry.$type, confirmed directly against three of Microsoft's
    own published GitHub sample policy JSON files (audit_all_apple_devices.json,
    deny_mobile_devices.json, deny_all_bluetooth_devices_except_samsung.json) - NOT the capitalized
    "PortableDevice" that appears in one cell of the Learn page's entry-$type property table, which
    is inconsistent with every other row in the same table and with the page's own separate Access
    Types table (both use lowercase "portableDevice"). Treated as a documentation table rendering
    inconsistency, not a second valid casing, on the strength of three independently-published,
    concrete worked examples versus zero worked examples using the capitalized form.

    Sources (Microsoft Learn, verify before production use):
    - Device Control for macOS (features/appleDevice/portableDevice/bluetoothDevice enable
      switches, default-disabled behavior, primaryId clause values including apple_devices/
      portable_devices/bluetooth_devices, Access Types table, best-practice guidance to use
      generic access types for a full-block deny policy):
      https://learn.microsoft.com/defender-endpoint/mac-device-control-overview
    - Sample macOS device control policies (worked examples independently confirming entry $type
      casing, access-string lists, and the serialNumber/OR/excludeGroups approved-device pattern
      for apple_devices; the vendorId+productId compound-match pattern for bluetooth_devices):
      https://github.com/microsoft/mdatp-devicecontrol/tree/main/macOS/policy/samples
      - audit_all_apple_devices.json, audit_all_apple_devices_except_serial_numbers.json,
        deny_mobile_devices.json, deny_all_bluetooth_devices_except_samsung.json
    - macOSCustomConfiguration resource / Update macOSCustomConfiguration (Graph v1.0 - payload is
      UTF8 byte array; replace-vs-merge PATCH semantics undocumented, same open VERIFY the parent
      scenario already carries):
      https://learn.microsoft.com/graph/api/resources/intune-deviceconfig-macoscustomconfiguration
    - scenarios/dlp/defender-device-control-usb-allowlist-macos/deploy/New-MacDeviceControlUsbAllowlistPolicy.ps1
      - the parent object this script extends; same Graph surface, same .mobileconfig shape, same
        idempotency discipline.
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$ConfigPath = (Join-Path $PSScriptRoot 'config/mac-portable-device-coverage.sample.json'),

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$GraphBaseUri = 'https://graph.microsoft.com/v1.0',

    [Parameter()]
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

# Fixed, source-controlled GUIDs for this fragment's groups/rules - distinct from the parent
# scenario's own six GUIDs so both sets coexist in the same policy JSON. Not freshly generated per
# run - same idempotent-reconcile discipline as the parent and the Windows WPD-coverage sibling.
$script:AllAppleGroupId       = 'd1d2d3d4-1111-4a1a-8a1a-111111111101'
$script:ApprovedAppleGroupId  = 'd1d2d3d4-1111-4a1a-8a1a-111111111102'
$script:AllPortableGroupId    = 'd1d2d3d4-2222-4b2b-8b2b-222222222201'
$script:ApprovedPortableGroupId = 'd1d2d3d4-2222-4b2b-8b2b-222222222202'
$script:AllBluetoothGroupId   = 'd1d2d3d4-3333-4c3c-8c3c-333333333301'

$script:DenyAppleRuleId       = 'd1d2d3d4-1111-4a1a-8a1a-111111111110'
$script:AllowAppleRuleId      = 'd1d2d3d4-1111-4a1a-8a1a-111111111111'
$script:DenyPortableRuleId    = 'd1d2d3d4-2222-4b2b-8b2b-222222222210'
$script:AllowPortableRuleId   = 'd1d2d3d4-2222-4b2b-8b2b-222222222211'
$script:DenyBluetoothRuleId   = 'd1d2d3d4-3333-4c3c-8c3c-333333333310'

$script:AllMyGroupIds = @($script:AllAppleGroupId, $script:ApprovedAppleGroupId, $script:AllPortableGroupId, $script:ApprovedPortableGroupId, $script:AllBluetoothGroupId)
$script:AllMyRuleIds  = @($script:DenyAppleRuleId, $script:AllowAppleRuleId, $script:DenyPortableRuleId, $script:AllowPortableRuleId, $script:DenyBluetoothRuleId)

# Access-string lists per Microsoft's official Access Types table (mac-device-control-overview),
# cross-checked verbatim against the three GitHub worked samples cited in .NOTES.
$script:AppleAccess     = @('download_files_from_device', 'sync_content_to_device', 'backup_device', 'update_device', 'download_photos_from_device')
$script:PortableAccess  = @('download_files_from_device', 'send_files_to_device', 'download_photos_from_device', 'debug')
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

function ConvertTo-Utf8Base64 {
    param([Parameter(Mandatory)][string]$Text)
    [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($Text))
}

function ConvertFrom-Utf8Base64 {
    param([Parameter(Mandatory)][string]$Base64)
    [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($Base64))
}

function ConvertTo-XmlEscaped {
    param([Parameter(Mandatory)][string]$Text)
    $Text -replace '&', '&amp;' -replace '<', '&lt;' -replace '>', '&gt;'
}

function ConvertFrom-XmlEscaped {
    param([Parameter(Mandatory)][string]$Text)
    $Text -replace '&lt;', '<' -replace '&gt;', '>' -replace '&amp;', '&'
}

function New-DenyRule {
    param([string]$RuleId, [string]$Name, [string]$IncludeGroupId, [string]$ExcludeGroupId, [string]$EntryType, [array]$Access, [string]$EntryPrefix)
    $rule = [ordered]@{
        id            = $RuleId
        name          = $Name
        includeGroups = @($IncludeGroupId)
    }
    if ($ExcludeGroupId) { $rule.excludeGroups = @($ExcludeGroupId) }
    $rule.entries = @(
        [ordered]@{ '$type' = $EntryType; id = "$EntryPrefix-0001-4001-8001-000000000001"; enforcement = [ordered]@{ '$type' = 'deny' }; access = $Access }
        [ordered]@{ '$type' = $EntryType; id = "$EntryPrefix-0002-4002-8002-000000000002"; enforcement = [ordered]@{ '$type' = 'auditDeny'; options = @('send_event', 'show_notification') }; access = $Access }
    )
    $rule
}

function New-AllowRule {
    param([string]$RuleId, [string]$Name, [string]$IncludeGroupId, [string]$EntryType, [array]$Access, [string]$EntryPrefix)
    [ordered]@{
        id            = $RuleId
        name          = $Name
        includeGroups = @($IncludeGroupId)
        entries       = @(
            [ordered]@{ '$type' = $EntryType; id = "$EntryPrefix-0003-4003-8003-000000000003"; enforcement = [ordered]@{ '$type' = 'allow' }; access = $Access }
            [ordered]@{ '$type' = $EntryType; id = "$EntryPrefix-0004-4004-8004-000000000004"; enforcement = [ordered]@{ '$type' = 'auditAllow'; options = @('send_event') }; access = $Access }
        )
    }
}

function Get-SerialNumberGroup {
    param([string]$GroupId, [string]$Name, [array]$Devices)
    $clauses = foreach ($d in $Devices) {
        if (-not $d.serialNumber) { throw "Every entry requires serialNumber (label: '$($d.label)')." }
        [ordered]@{ '$type' = 'serialNumber'; value = $d.serialNumber }
    }
    [ordered]@{
        '$type' = 'device'
        id      = $GroupId
        name    = $Name
        query   = [ordered]@{ '$type' = 'or'; clauses = @($clauses) }
    }
}

function Get-CatchAllGroup {
    param([string]$GroupId, [string]$Name, [string]$PrimaryIdValue)
    [ordered]@{
        '$type' = 'device'
        id      = $GroupId
        name    = $Name
        query   = [ordered]@{ '$type' = 'all'; clauses = @([ordered]@{ '$type' = 'primaryId'; value = $PrimaryIdValue }) }
    }
}

# --- Load and validate config ---
if (-not (Test-Path -LiteralPath $ConfigPath)) { throw "Config file not found: $ConfigPath" }
$cfg = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
$parentDisplayName = if ($cfg.parentPolicyDisplayName) { $cfg.parentPolicyDisplayName } else { 'Device Control (macOS) - USB Removable Media Default-Deny Allowlist' }
$approvedApple = @($cfg.approvedAppleDevices)
$approvedPortable = @($cfg.approvedPortableDevices)

Assert-MgConnected
Write-Host "macOS portable/Apple/Bluetooth device control coverage: extending parent policy '$parentDisplayName'." -ForegroundColor Cyan

# --- 1. Locate the parent policy - refuse to create one from scratch ---
$configUri = "$GraphBaseUri/deviceManagement/deviceConfigurations"
$parent = Get-AllGraphValues -Uri $configUri | Where-Object { $_.displayName -eq $parentDisplayName } | Select-Object -First 1

if (-not $parent) {
    throw "Parent policy '$parentDisplayName' not found. Deploy scenarios/dlp/defender-device-control-usb-allowlist-macos/deploy/New-MacDeviceControlUsbAllowlistPolicy.ps1 first - this script only extends an existing policy, it does not create one."
}

$full = Invoke-MgGraphRequest -Method GET -Uri "$configUri/$($parent.id)"
if (-not $full.payload) { throw "Parent policy '$parentDisplayName' has no payload - it does not look like the expected macOSCustomConfiguration device control object. Refusing to modify it." }

$mobileConfigXml = ConvertFrom-Utf8Base64 $full.payload

# --- 2. Extract the embedded device control policy JSON string (regex over the known, fixed
#        <key>policy</key><string>...</string> shape the parent script always produces - see .NOTES
#        / defender-device-control-usb-allowlist-macos/reviews.md Blue Team finding 2 for the same
#        accepted trade-off) ---
$policyMatch = [regex]::Match($mobileConfigXml, '<key>policy</key>\s*<string>(.*?)</string>', [System.Text.RegularExpressions.RegexOptions]::Singleline)
if (-not $policyMatch.Success) {
    throw "Could not locate the embedded deviceControl.policy JSON in the parent policy's .mobileconfig payload - it does not look like the expected object. Refusing to modify it."
}
$originalEscapedJson = $policyMatch.Groups[1].Value
$parsedPolicy = (ConvertFrom-XmlEscaped $originalEscapedJson) | ConvertFrom-Json

if (-not $parsedPolicy.groups -or -not $parsedPolicy.rules -or -not $parsedPolicy.settings) {
    throw "Parent policy's deviceControl.policy JSON is missing groups/rules/settings - it does not look like the expected object. Refusing to modify it."
}

# --- 3. Coverage detection (by this script's own fixed GUIDs, not by value) ---
$existingGroupIds = @($parsedPolicy.groups | ForEach-Object { $_.id })
$existingRuleIds  = @($parsedPolicy.rules  | ForEach-Object { $_.id })
$myGroupsPresent = @($script:AllMyGroupIds | Where-Object { $_ -in $existingGroupIds })
$myRulesPresent  = @($script:AllMyRuleIds  | Where-Object { $_ -in $existingRuleIds })
# "Fully covered" requires at minimum the 3 mandatory catch-all groups + 3 mandatory deny rules;
# the approved-device (allow) groups/rules are conditional on -ConfigPath, so are not part of this
# baseline check.
$mandatoryGroupIds = @($script:AllAppleGroupId, $script:AllPortableGroupId, $script:AllBluetoothGroupId)
$mandatoryRuleIds  = @($script:DenyAppleRuleId, $script:DenyPortableRuleId, $script:DenyBluetoothRuleId)
$hasAllMandatory = (@($mandatoryGroupIds | Where-Object { $_ -in $existingGroupIds }).Count -eq 3) -and (@($mandatoryRuleIds | Where-Object { $_ -in $existingRuleIds }).Count -eq 3)

if ($hasAllMandatory -and -not $Force) {
    Write-Host "  [coverage] Apple/Portable/Bluetooth device control coverage already present on '$parentDisplayName' - not modified. Pass -Force to reconcile the approved-device lists to -ConfigPath's current definition." -ForegroundColor Yellow
    Write-Host "`nDone. No change made." -ForegroundColor Cyan
    return
}
if (($myGroupsPresent.Count -gt 0 -or $myRulesPresent.Count -gt 0) -and -not $hasAllMandatory) {
    Write-Host "  [coverage] Partial coverage detected ($($myGroupsPresent.Count)/$($script:AllMyGroupIds.Count) of this fragment's groups, $($myRulesPresent.Count)/$($script:AllMyRuleIds.Count) rules present) - reconciling to a complete, consistent state." -ForegroundColor Yellow
}

# --- 4. Build the reconciled groups/rules: keep every group/rule not owned by this fragment
#        untouched, then (re)add this fragment's own entries fresh from -ConfigPath ---
$keptGroups = @($parsedPolicy.groups | Where-Object { $_.id -notin $script:AllMyGroupIds })
$keptRules  = @($parsedPolicy.rules  | Where-Object { $_.id -notin $script:AllMyRuleIds })

$newGroups = @(
    (Get-CatchAllGroup -GroupId $script:AllAppleGroupId -Name 'AllAppleDevices' -PrimaryIdValue 'apple_devices')
    (Get-CatchAllGroup -GroupId $script:AllPortableGroupId -Name 'AllPortableDevices' -PrimaryIdValue 'portable_devices')
    (Get-CatchAllGroup -GroupId $script:AllBluetoothGroupId -Name 'AllBluetoothDevices' -PrimaryIdValue 'bluetooth_devices')
)
$newRules = @()

if ($approvedApple.Count -gt 0) {
    $newGroups += (Get-SerialNumberGroup -GroupId $script:ApprovedAppleGroupId -Name 'ApprovedAppleDevices' -Devices $approvedApple)
    $newRules += (New-DenyRule -RuleId $script:DenyAppleRuleId -Name 'Deny-AllOtherAppleDevices' -IncludeGroupId $script:AllAppleGroupId -ExcludeGroupId $script:ApprovedAppleGroupId -EntryType 'appleDevice' -Access $script:AppleAccess -EntryPrefix '88888888')
    $newRules += (New-AllowRule -RuleId $script:AllowAppleRuleId -Name 'Allow-ApprovedAppleDevices' -IncludeGroupId $script:ApprovedAppleGroupId -EntryType 'appleDevice' -Access $script:AppleAccess -EntryPrefix '88888888')
}
else {
    $newRules += (New-DenyRule -RuleId $script:DenyAppleRuleId -Name 'Deny-AllAppleDevices' -IncludeGroupId $script:AllAppleGroupId -ExcludeGroupId $null -EntryType 'appleDevice' -Access $script:AppleAccess -EntryPrefix '88888888')
}

if ($approvedPortable.Count -gt 0) {
    $newGroups += (Get-SerialNumberGroup -GroupId $script:ApprovedPortableGroupId -Name 'ApprovedPortableDevices' -Devices $approvedPortable)
    $newRules += (New-DenyRule -RuleId $script:DenyPortableRuleId -Name 'Deny-AllOtherPortableDevices' -IncludeGroupId $script:AllPortableGroupId -ExcludeGroupId $script:ApprovedPortableGroupId -EntryType 'portableDevice' -Access $script:PortableAccess -EntryPrefix '99999999')
    $newRules += (New-AllowRule -RuleId $script:AllowPortableRuleId -Name 'Allow-ApprovedPortableDevices' -IncludeGroupId $script:ApprovedPortableGroupId -EntryType 'portableDevice' -Access $script:PortableAccess -EntryPrefix '99999999')
}
else {
    $newRules += (New-DenyRule -RuleId $script:DenyPortableRuleId -Name 'Deny-AllPortableDevices' -IncludeGroupId $script:AllPortableGroupId -ExcludeGroupId $null -EntryType 'portableDevice' -Access $script:PortableAccess -EntryPrefix '99999999')
}

# Bluetooth: always default-deny, no allowlist in this fragment - see .NOTES.
$newRules += (New-DenyRule -RuleId $script:DenyBluetoothRuleId -Name 'Deny-AllBluetoothDevices' -IncludeGroupId $script:AllBluetoothGroupId -ExcludeGroupId $null -EntryType 'bluetoothDevice' -Access $script:BluetoothAccess -EntryPrefix 'aaaaaaaa')

$desiredGroups = @($keptGroups) + @($newGroups)
$desiredRules  = @($keptRules) + @($newRules)

# --- 5. Merge settings.features: keep every existing feature flag (e.g. the parent's
#        removableMedia), add/overwrite this fragment's three ---
$desiredFeatures = [ordered]@{}
if ($parsedPolicy.settings.features) {
    foreach ($p in $parsedPolicy.settings.features.psobject.Properties) {
        $desiredFeatures[$p.Name] = $p.Value
    }
}
$desiredFeatures['appleDevice']     = [ordered]@{ disable = $false }
$desiredFeatures['portableDevice']  = [ordered]@{ disable = $false }
$desiredFeatures['bluetoothDevice'] = [ordered]@{ disable = $false }

$desiredSettings = [ordered]@{ features = $desiredFeatures; global = $parsedPolicy.settings.global }
if ($parsedPolicy.settings.ux) { $desiredSettings.ux = $parsedPolicy.settings.ux }

$desiredPolicy = [ordered]@{ groups = $desiredGroups; rules = $desiredRules; settings = $desiredSettings }
$newPolicyJson = $desiredPolicy | ConvertTo-Json -Depth 12 -Compress
$newEscapedJson = ConvertTo-XmlEscaped $newPolicyJson

Write-Host "  [plan] $($parsedPolicy.groups.Count) existing groups / $($parsedPolicy.rules.Count) existing rules -> $($desiredGroups.Count) groups / $($desiredRules.Count) rules after adding Apple/Portable/Bluetooth coverage." -ForegroundColor DarkCyan

# --- 6. Substitute only the policy <string> node's content (a plain literal substring replace of
#        the exact text captured by the regex match above); every other plist key (PayloadUUID,
#        PayloadIdentifier, PayloadDisplayName, etc.) is left untouched ---
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

if ($PSCmdlet.ShouldProcess($parentDisplayName, "PATCH $configUri/$($parent.id) (add Apple/Portable/Bluetooth device control coverage)")) {
    Invoke-MgGraphRequest -Method PATCH -Uri "$configUri/$($parent.id)" -Body ($body | ConvertTo-Json -Depth 12) | Out-Null
    Write-Host "  [coverage] Apple/Portable/Bluetooth coverage added/reconciled on '$parentDisplayName' (id $($parent.id))" -ForegroundColor Green
}

Write-Host "`nDone. This does not change the parent policy's assignment - devices already assigned the parent policy receive this widened payload on their next Intune sync. Run validate/Test-MacPortableDeviceCoverage.ps1 to verify. Reminder: Bluetooth devices are always default-deny in this fragment (no allowlist) - see README.md Section 11." -ForegroundColor Cyan
```

#### `config/mac-portable-device-coverage.sample.json`

```json
{
  "parentPolicyDisplayName": "Device Control (macOS) - USB Removable Media Default-Deny Allowlist",
  "approvedAppleDevices": [
    { "label": "REPLACE - e.g. IT-issued iPad, compliance kiosk", "serialNumber": "REPLACE_WITH_REAL_SERIAL_NUMBER" }
  ],
  "approvedPortableDevices": []
}
```

#### `Remove-MacPortableDeviceCoverage.ps1`

```powershell
#Requires -Version 7.0
<#
.SYNOPSIS
    Removes Apple/Portable/Bluetooth device control coverage from the "Device Control (macOS) -
    USB Removable Media Default-Deny Allowlist" macOSCustomConfiguration object, reverting its
    embedded policy JSON to removable-media-only scope.

.DESCRIPTION
    Surgical rollback for scenarios/dlp/defender-device-control-usb-allowlist-macos-portable-
    device-coverage: removes the three catch-all groups (AllAppleDevices/AllPortableDevices/
    AllBluetoothDevices), the optional approved-device groups (ApprovedAppleDevices/
    ApprovedPortableDevices), the five deny/allow rule pairs, and the three feature-enable flags
    (appleDevice/portableDevice/bluetoothDevice) this fragment's deploy/
    Add-MacPortableDeviceCoverage.ps1 added - by their fixed GUIDs, the same identification this
    scenario's deploy and validate scripts use.

    This does NOT touch the parent policy's removableMedia coverage, its ApprovedBackupDrives/
    AllRemovableStorage groups, its two RemovableMediaDevices rules, its settings.global/settings.ux,
    its assignment, or the policy object's identity (PayloadUUID, PayloadIdentifier, etc.) - only
    this fragment's own additions are removed. To remove the entire macOS device control policy,
    use scenarios/dlp/defender-device-control-usb-allowlist-macos/deploy/
    Remove-MacDeviceControlUsbAllowlistPolicy.ps1 instead - see rollback.md.

    Connect first: Connect-MgGraph (app-only certificate - see docs/automation-surface.md
    Section 3). This script does not open the session.

.PARAMETER ParentPolicyDisplayName
    Display name of the parent macOSCustomConfiguration object. Defaults to this scenario's
    standard parent name.

.PARAMETER GraphBaseUri
    Graph base URI. Defaults to 'https://graph.microsoft.com/v1.0'.

.PARAMETER WhatIf
    Standard PowerShell ShouldProcess dry-run.

.EXAMPLE
    Connect-MgGraph -ClientId $AppId -TenantId $TenantId -CertificateThumbprint $Thumbprint
    ./Remove-MacPortableDeviceCoverage.ps1 -WhatIf

.EXAMPLE
    ./Remove-MacPortableDeviceCoverage.ps1
    # Strips Apple/Portable/Bluetooth coverage back out of the parent's .mobileconfig payload. The
    # parent policy's own removableMedia coverage is unaffected.

.NOTES
    Sources: same as deploy/Add-MacPortableDeviceCoverage.ps1's .NOTES block.
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

# Must match the fixed GUIDs in deploy/Add-MacPortableDeviceCoverage.ps1 exactly.
$script:AllMyGroupIds = @(
    'd1d2d3d4-1111-4a1a-8a1a-111111111101', 'd1d2d3d4-1111-4a1a-8a1a-111111111102',
    'd1d2d3d4-2222-4b2b-8b2b-222222222201', 'd1d2d3d4-2222-4b2b-8b2b-222222222202',
    'd1d2d3d4-3333-4c3c-8c3c-333333333301'
)
$script:AllMyRuleIds = @(
    'd1d2d3d4-1111-4a1a-8a1a-111111111110', 'd1d2d3d4-1111-4a1a-8a1a-111111111111',
    'd1d2d3d4-2222-4b2b-8b2b-222222222210', 'd1d2d3d4-2222-4b2b-8b2b-222222222211',
    'd1d2d3d4-3333-4c3c-8c3c-333333333310'
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
$existingRuleIds = @($parsedPolicy.rules | ForEach-Object { $_.id })
if (-not (@($script:AllMyGroupIds | Where-Object { $_ -in $existingGroupIds }).Count -gt 0 -or @($script:AllMyRuleIds | Where-Object { $_ -in $existingRuleIds }).Count -gt 0)) {
    Write-Host "Parent policy '$ParentPolicyDisplayName' does not currently have Apple/Portable/Bluetooth coverage - nothing to remove." -ForegroundColor Yellow
    return
}

$keptGroups = @($parsedPolicy.groups | Where-Object { $_.id -notin $script:AllMyGroupIds })
$keptRules = @($parsedPolicy.rules | Where-Object { $_.id -notin $script:AllMyRuleIds })

$keptFeatures = [ordered]@{}
if ($parsedPolicy.settings.features) {
    foreach ($p in $parsedPolicy.settings.features.psobject.Properties) {
        if ($p.Name -notin @('appleDevice', 'portableDevice', 'bluetoothDevice')) { $keptFeatures[$p.Name] = $p.Value }
    }
}
$desiredSettings = [ordered]@{ features = $keptFeatures; global = $parsedPolicy.settings.global }
if ($parsedPolicy.settings.ux) { $desiredSettings.ux = $parsedPolicy.settings.ux }

$desiredPolicy = [ordered]@{ groups = $keptGroups; rules = $keptRules; settings = $desiredSettings }
$newPolicyJson = $desiredPolicy | ConvertTo-Json -Depth 12 -Compress
$newEscapedJson = ConvertTo-XmlEscaped $newPolicyJson

Write-Host "  [plan] $($parsedPolicy.groups.Count) existing groups / $($parsedPolicy.rules.Count) existing rules -> $($keptGroups.Count) groups / $($keptRules.Count) rules after removing Apple/Portable/Bluetooth coverage." -ForegroundColor DarkCyan

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

if ($PSCmdlet.ShouldProcess($ParentPolicyDisplayName, "PATCH $configUri/$($parent.id) (remove Apple/Portable/Bluetooth device control coverage)")) {
    Invoke-MgGraphRequest -Method PATCH -Uri "$configUri/$($parent.id)" -Body ($body | ConvertTo-Json -Depth 12) | Out-Null
    Write-Host "  [coverage] Apple/Portable/Bluetooth coverage removed from '$ParentPolicyDisplayName' (id $($parent.id))" -ForegroundColor Green
}

Write-Host "`nDone. Parent policy's removableMedia coverage, assignment, and object identity are unchanged. A previously-approved Apple/Portable device (and every Bluetooth device) is now unrestricted again, not denied - see rollback.md before relying on this as an incident-response containment step." -ForegroundColor Cyan
```