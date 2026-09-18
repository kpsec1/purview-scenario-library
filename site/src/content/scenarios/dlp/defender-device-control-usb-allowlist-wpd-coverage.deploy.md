---
part: "deploy"
parent: "dlp/defender-device-control-usb-allowlist-wpd-coverage"
---
The scripts and configuration below deploy this scenario. Review them, then run in order — each is designed to be idempotent and has a matching rollback.


#### `Add-WpdDeviceControlCoverage.ps1`

```powershell
#Requires -Version 7.0
<#
.SYNOPSIS
    Extends the "Device Control - USB Removable Media Default-Deny Allowlist" Intune device
    configuration object (scenarios/dlp/defender-device-control-usb-allowlist) to also cover
    Windows Portable Devices (WPD) - phones, tablets, and cameras connected in MTP/PTP mode.

.DESCRIPTION
    The parent scenario's SecuredDevicesConfiguration value ("RemovableMediaDevices") scopes
    enforcement to devices that create a disk letter in Windows. A device that instead enumerates
    as a Windows Portable Device - most phones/cameras in MTP or PTP mode - is a distinct device
    family and is completely invisible to that policy: no block, no audit event
    (defender-device-control-usb-allowlist/README.md Section 11, the confirmed Red Team finding
    this fragment closes).

    This script does NOT create a second Intune profile. It widens the parent's existing
    windows10CustomConfiguration object in place by:
      1. Changing SecuredDevicesConfiguration from "RemovableMediaDevices" to the documented
         pipe-separated multi-value string "RemovableMediaDevices|WpdDevices" (confirmed syntax -
         see .NOTES).
      2. Adding a new "ApprovedWpdDevices" group (matched by FriendlyNameId and/or, unconfirmed,
         SerialNumberId/VID_PID - README.md Section 11 VERIFY) from -ConfigPath's
         approvedWpdDevices list.
      3. Adding a new "AllWpdDevices" catch-all group (PrimaryId = WpdDevices).
      4. Adding "Allow-ApprovedWpdDevices" (Allow + AuditAllowed, AccessMask 63) and
         "Deny-AllOtherWpd" (Deny + AuditDenied, AccessMask 63) rules, mirroring the parent's
         RemovableMediaDevices rule pair exactly - Microsoft's AccessMask semantics (1/2/4/8/16/32)
         are documented as identical across CdRomDevices, RemovableMediaDevices, and WpdDevices.

    A single physical device that enumerates as BOTH a removable media device and a WPD device
    must be present in BOTH approved-device groups to get full access on every entry - Microsoft's
    own guidance ("grant access for all entries associated with the physical device") - see
    README.md Section 6 and Section 11.

    Idempotent: reads the parent object's current omaSettings, detects whether WPD coverage is
    already present (by omaUri, not by value), and with -Force reconciles the full 11-entry array
    (7 original + 4 WPD) via a whole-array PATCH - same replace-not-merge assumption already
    flagged as an open VERIFY in the parent scenario. Without -Force, an already-covered policy is
    reported and left untouched.

    PREREQUISITE this script does not perform: the parent policy
    (deploy/New-DeviceControlUsbAllowlistPolicy.ps1 in
    scenarios/dlp/defender-device-control-usb-allowlist/) must already exist. This script refuses
    to run and create a new object from scratch - see README.md Section 3.

.PARAMETER ConfigPath
    Path to the JSON config (approvedWpdDevices list + parentPolicyDisplayName). Defaults to the
    sibling 'config/wpd-device-control-coverage.sample.json' - copy and edit it.

.PARAMETER GraphBaseUri
    Graph base URI. Defaults to 'https://graph.microsoft.com/v1.0'.

.PARAMETER Force
    If WPD coverage already exists on the parent policy, reconcile it to match -ConfigPath's
    current definition instead of skipping.

.PARAMETER WhatIf
    Standard PowerShell ShouldProcess dry-run. Reports the PATCH that would be made without
    calling any mutating Graph endpoint.

.EXAMPLE
    Connect-MgGraph -ClientId $AppId -TenantId $TenantId -CertificateThumbprint $Thumbprint
    ./Add-WpdDeviceControlCoverage.ps1 -ConfigPath ./config/my-tenant.json -WhatIf

.EXAMPLE
    ./Add-WpdDeviceControlCoverage.ps1 -ConfigPath ./config/my-tenant.json

.NOTES
    VERIFY (README.md Section 11): whether SerialNumberId/VID_PID group-matching properties are
    honored for WpdDevices-classified hardware. Microsoft's "Device control policies" reference
    lists SerialNumberId/VID_PID as supported "Windows devices" properties generically, without
    breaking the table down per PrimaryId family (RemovableMediaDevices/CdRomDevices/WpdDevices/
    PrinterDevices), and no worked example pairing either property with a WpdDevices-scoped group
    was found. This script accepts both friendlyNameId (the only property directly demonstrated
    against portable-device-class hardware in Microsoft's own Device Manager mapping guidance) and
    serialNumberId/vidPid (accepted, but flagged) per config entry - see README.md Section 6/Section 11.
    This corrects an earlier, unsubstantiated PROGRESS.md note that had asserted WPD groups
    support *only* FriendlyNameId/PrimaryId; that stronger claim could not be confirmed either
    during this build's grounding pass and is not repeated here.

    Sources (Microsoft Learn, verify before production use):
    - Device control policies (PrimaryId family list, DescriptorIdList properties, AccessMask
      parity across CdRomDevices/RemovableMediaDevices/WpdDevices, Intune reusable-settings-groups
      device-group types [Printer device / Removable storage only - no WPD reusable-settings type]):
      https://learn.microsoft.com/defender-endpoint/device-control-policies
    - Deploy and manage device control with Intune (SecuredDevicesConfiguration OMA-URI,
      pipe-separated multi-value syntax):
      https://learn.microsoft.com/defender-endpoint/device-control-deploy-manage-intune
    - Device control in Microsoft Defender for Endpoint (WPD added in anti-malware client
      4.18.2107+; "grant access for all entries associated with the physical device"; disk-letter
      definition of a removable media device):
      https://learn.microsoft.com/defender-endpoint/device-control-overview
    - windows10CustomConfiguration / omaSetting* resource types, Update windows10CustomConfiguration
      (Graph v1.0): https://learn.microsoft.com/graph/api/resources/intune-deviceconfig-windows10customconfiguration
    - scenarios/dlp/defender-device-control-usb-allowlist/deploy/New-DeviceControlUsbAllowlistPolicy.ps1
      - the parent object this script extends; same Graph surface and idempotency pattern.
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$ConfigPath = (Join-Path $PSScriptRoot 'config/wpd-device-control-coverage.sample.json'),

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$GraphBaseUri = 'https://graph.microsoft.com/v1.0',

    [Parameter()]
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

# Fixed, source-controlled GUIDs for the four new WPD nodes - distinct from the parent scenario's
# four RemovableMediaDevices GUIDs so both sets coexist in the same omaSettings array.
$script:ApprovedWpdGroupId = 'f5a6b7c8-5555-4e6f-8081-92a3b4c5d6e7'
$script:AllWpdGroupId = 'a6b7c8d9-6666-4f70-9182-a3b4c5d6e7f8'
$script:AllowWpdRuleId = 'b7c8d9e0-7777-4081-a293-b4c5d6e7f809'
$script:DenyWpdRuleId = 'c8d9e0f1-8888-4192-b3a4-c5d6e7f8091a'

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

function New-ApprovedWpdGroupXml {
    param([Parameter(Mandatory)][array]$ApprovedWpdDevices)
    $descriptors = foreach ($d in $ApprovedWpdDevices) {
        if ($d.friendlyNameId) { "    <FriendlyNameId>$($d.friendlyNameId)</FriendlyNameId>" }
        if ($d.serialNumberId) { "    <SerialNumberId>$($d.serialNumberId)</SerialNumberId>" }
        if ($d.vidPid) { "    <VID_PID>$($d.vidPid)</VID_PID>" }
    }
    if (-not $descriptors) { throw 'approvedWpdDevices must contain at least one entry with friendlyNameId, serialNumberId, or vidPid.' }
    @"
<Group Id="{$script:ApprovedWpdGroupId}">
  <MatchType>MatchAny</MatchType>
  <DescriptorIdList>
$($descriptors -join "`n")
  </DescriptorIdList>
</Group>
"@
}

function New-CatchAllWpdGroupXml {
    @"
<Group Id="{$script:AllWpdGroupId}">
  <MatchType>MatchAny</MatchType>
  <DescriptorIdList>
    <PrimaryId>WpdDevices</PrimaryId>
  </DescriptorIdList>
</Group>
"@
}

function New-AllowWpdRuleXml {
    @"
<PolicyRule Id="{$script:AllowWpdRuleId}">
  <Name>Allow-ApprovedWpdDevices</Name>
  <IncludedIdList>
    <GroupId>{$script:ApprovedWpdGroupId}</GroupId>
  </IncludedIdList>
  <Entry Id="{f1f2f3f4-0001-4001-8001-000000000011}">
    <Type>Allow</Type>
    <Options>0</Options>
    <AccessMask>63</AccessMask>
  </Entry>
  <Entry Id="{f1f2f3f4-0002-4002-8002-000000000012}">
    <Type>AuditAllowed</Type>
    <Options>2</Options>
    <AccessMask>63</AccessMask>
  </Entry>
</PolicyRule>
"@
}

function New-DenyWpdRuleXml {
    @"
<PolicyRule Id="{$script:DenyWpdRuleId}">
  <Name>Deny-AllOtherWpd</Name>
  <IncludedIdList>
    <GroupId>{$script:AllWpdGroupId}</GroupId>
  </IncludedIdList>
  <ExcludedIdList>
    <GroupId>{$script:ApprovedWpdGroupId}</GroupId>
  </ExcludedIdList>
  <Entry Id="{f1f2f3f4-0003-4003-8003-000000000013}">
    <Type>Deny</Type>
    <Options>0</Options>
    <AccessMask>63</AccessMask>
  </Entry>
  <Entry Id="{f1f2f3f4-0004-4004-8004-000000000014}">
    <Type>AuditDenied</Type>
    <Options>3</Options>
    <AccessMask>63</AccessMask>
  </Entry>
</PolicyRule>
"@
}

function Get-WpdOmaSettings {
    param([Parameter(Mandatory)]$Config)

    $approvedXml = New-ApprovedWpdGroupXml -ApprovedWpdDevices $Config.approvedWpdDevices
    $catchAllXml = New-CatchAllWpdGroupXml
    $allowXml = New-AllowWpdRuleXml
    $denyXml = New-DenyWpdRuleXml

    @(
        @{ '@odata.type' = '#microsoft.graph.omaSettingStringXml'; displayName = 'Group: ApprovedWpdDevices'; omaUri = "./Vendor/MSFT/Defender/Configuration/DeviceControl/PolicyGroups/{$script:ApprovedWpdGroupId}/GroupData"; fileName = 'ApprovedWpdDevices.xml'; value = (ConvertTo-Utf8Base64 $approvedXml) }
        @{ '@odata.type' = '#microsoft.graph.omaSettingStringXml'; displayName = 'Group: AllWpdDevices (catch-all)'; omaUri = "./Vendor/MSFT/Defender/Configuration/DeviceControl/PolicyGroups/{$script:AllWpdGroupId}/GroupData"; fileName = 'AllWpdDevices.xml'; value = (ConvertTo-Utf8Base64 $catchAllXml) }
        @{ '@odata.type' = '#microsoft.graph.omaSettingStringXml'; displayName = 'Rule: Allow-ApprovedWpdDevices'; omaUri = "./Vendor/MSFT/Defender/Configuration/DeviceControl/PolicyRules/{$script:AllowWpdRuleId}/RuleData"; fileName = 'AllowApprovedWpdDevices.xml'; value = (ConvertTo-Utf8Base64 $allowXml) }
        @{ '@odata.type' = '#microsoft.graph.omaSettingStringXml'; displayName = 'Rule: Deny-AllOtherWpd'; omaUri = "./Vendor/MSFT/Defender/Configuration/DeviceControl/PolicyRules/{$script:DenyWpdRuleId}/RuleData"; fileName = 'DenyAllOtherWpd.xml'; value = (ConvertTo-Utf8Base64 $denyXml) }
    )
}

# --- Load and validate config ---
if (-not (Test-Path -LiteralPath $ConfigPath)) { throw "Config file not found: $ConfigPath" }
$cfg = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
if (-not $cfg.approvedWpdDevices -or @($cfg.approvedWpdDevices).Count -eq 0) { throw 'approvedWpdDevices must contain at least one entry.' }
$parentDisplayName = if ($cfg.parentPolicyDisplayName) { $cfg.parentPolicyDisplayName } else { 'Device Control - USB Removable Media Default-Deny Allowlist' }

Assert-MgConnected
Write-Host "WPD device control coverage: extending parent policy '$parentDisplayName'." -ForegroundColor Cyan

# --- 1. Locate the parent policy - refuse to create one from scratch ---
$configUri = "$GraphBaseUri/deviceManagement/deviceConfigurations"
$parent = Get-AllGraphValues -Uri $configUri | Where-Object { $_.displayName -eq $parentDisplayName } | Select-Object -First 1

if (-not $parent) {
    throw "Parent policy '$parentDisplayName' not found. Deploy scenarios/dlp/defender-device-control-usb-allowlist/deploy/New-DeviceControlUsbAllowlistPolicy.ps1 first - this script only extends an existing policy, it does not create one."
}

$full = Invoke-MgGraphRequest -Method GET -Uri "$configUri/$($parent.id)"
$existingSettings = @($full.omaSettings)

$scopeSetting = $existingSettings | Where-Object { $_.omaUri -like '*SecuredDevicesConfiguration*' } | Select-Object -First 1
if (-not $scopeSetting) {
    throw "Parent policy '$parentDisplayName' has no SecuredDevicesConfiguration setting - it does not look like the expected device control policy object. Refusing to modify it."
}

$alreadyCoversWpd = $scopeSetting.value -match 'WpdDevices'
$existingWpdNodes = @($existingSettings | Where-Object { $_.omaUri -like "*$script:ApprovedWpdGroupId*" -or $_.omaUri -like "*$script:AllWpdGroupId*" -or $_.omaUri -like "*$script:AllowWpdRuleId*" -or $_.omaUri -like "*$script:DenyWpdRuleId*" })
# Require ALL 4 expected WPD nodes, not just any - a partial set (e.g. from an interrupted prior
# run) must NOT be reported as "already covered", or the missing nodes would never be reconciled
# without an explicit -Force.
$hasAllWpdNodes = $existingWpdNodes.Count -eq 4

if ($alreadyCoversWpd -and $hasAllWpdNodes -and -not $Force) {
    Write-Host "  [coverage] WPD coverage already present on '$parentDisplayName' - not modified. Pass -Force to reconcile the approved-WPD-device list to this script's/-ConfigPath's definition." -ForegroundColor Yellow
    Write-Host "`nDone. No change made." -ForegroundColor Cyan
    return
}
if (($alreadyCoversWpd -or $existingWpdNodes.Count -gt 0) -and -not $hasAllWpdNodes) {
    Write-Host "  [coverage] Partial WPD state detected (scope mentions WpdDevices: $alreadyCoversWpd; $($existingWpdNodes.Count)/4 WPD omaSettings present) - reconciling to a complete, consistent state." -ForegroundColor Yellow
}

# --- 2. Build the reconciled omaSettings array: keep every non-scope, non-WPD setting from the
#        parent untouched, widen SecuredDevicesConfiguration, and (re)add the 4 WPD entries ---
$keptSettings = $existingSettings | Where-Object {
    $_.omaUri -notlike '*SecuredDevicesConfiguration*' -and
    $_.omaUri -notlike "*$script:ApprovedWpdGroupId*" -and
    $_.omaUri -notlike "*$script:AllWpdGroupId*" -and
    $_.omaUri -notlike "*$script:AllowWpdRuleId*" -and
    $_.omaUri -notlike "*$script:DenyWpdRuleId*"
}

$newScopeSetting = @{
    '@odata.type' = '#microsoft.graph.omaSettingString'
    displayName   = $scopeSetting.displayName
    omaUri        = $scopeSetting.omaUri
    value         = 'RemovableMediaDevices|WpdDevices'
}

$wpdSettings = Get-WpdOmaSettings -Config $cfg
$desiredSettings = @($keptSettings) + @($newScopeSetting) + @($wpdSettings)

Write-Host "  [plan] $($existingSettings.Count) existing omaSettings -> $($desiredSettings.Count) after adding WPD coverage (expect 7 -> 11 on a first run)." -ForegroundColor DarkCyan

$body = @{
    '@odata.type' = '#microsoft.graph.windows10CustomConfiguration'
    omaSettings   = $desiredSettings
}

if ($PSCmdlet.ShouldProcess($parentDisplayName, "PATCH $configUri/$($parent.id) (widen SecuredDevicesConfiguration to include WpdDevices; add 4 WPD omaSettings)")) {
    Invoke-MgGraphRequest -Method PATCH -Uri "$configUri/$($parent.id)" -Body ($body | ConvertTo-Json -Depth 8) | Out-Null
    Write-Host "  [coverage] WPD coverage added/reconciled on '$parentDisplayName' (id $($parent.id))" -ForegroundColor Green
}

Write-Host "`nDone. This does not change the parent policy's assignment - devices already assigned the parent policy receive this widened scope on their next Intune sync. Run validate/Test-WpdDeviceControlCoverage.ps1 to verify. Reminder: a physical device that also enumerates as a RemovableMediaDevices entry needs its identity in BOTH approved-device groups (README.md Section 6)." -ForegroundColor Cyan
```

#### `config/wpd-device-control-coverage.sample.json`

```json
{
  "parentPolicyDisplayName": "Device Control - USB Removable Media Default-Deny Allowlist",
  "approvedWpdDevices": [
    {
      "label": "Field Ops - IT-issued rugged handheld scanner (MTP mode)",
      "friendlyNameId": "REPLACE_WITH_DEVICE_MANAGER_FRIENDLY_NAME"
    },
    {
      "label": "Field Ops - IT-issued rugged handheld scanner - unconfirmed alternate match (see README.md Section 11 VERIFY before relying on this alone)",
      "serialNumberId": "REPLACE_WITH_REAL_SERIAL_NUMBER_IF_CONFIRMED_ON_PILOT"
    }
  ]
}
```

#### `Remove-WpdDeviceControlCoverage.ps1`

```powershell
#Requires -Version 7.0
<#
.SYNOPSIS
    Removes Windows Portable Device (WPD) coverage from the "Device Control - USB Removable Media
    Default-Deny Allowlist" Intune device configuration object, reverting it to
    RemovableMediaDevices-only scope.

.DESCRIPTION
    Surgical rollback for scenarios/dlp/defender-device-control-usb-allowlist-wpd-coverage: reverts
    the parent policy's SecuredDevicesConfiguration value from "RemovableMediaDevices|WpdDevices"
    back to "RemovableMediaDevices" alone, and removes the four WPD-specific omaSettings entries
    (ApprovedWpdDevices group, AllWpdDevices catch-all group, Allow-ApprovedWpdDevices rule,
    Deny-AllOtherWpd rule) added by deploy/Add-WpdDeviceControlCoverage.ps1.

    This does NOT touch the parent policy's original RemovableMediaDevices coverage, its
    assignment, or the policy object itself - only the four WPD-specific settings and the scope
    string are changed. To remove the entire USB device control policy (both RemovableMediaDevices
    and WPD coverage), use scenarios/dlp/defender-device-control-usb-allowlist/deploy/
    Remove-DeviceControlUsbAllowlistPolicy.ps1 instead - see rollback.md.

    Connect first: Connect-MgGraph (app-only certificate - see docs/automation-surface.md
    Section 3). This script does not open the session.

.PARAMETER ParentPolicyDisplayName
    Display name of the parent device configuration object. Defaults to this scenario's
    standard parent name.

.PARAMETER GraphBaseUri
    Graph base URI. Defaults to 'https://graph.microsoft.com/v1.0'.

.PARAMETER WhatIf
    Standard PowerShell ShouldProcess dry-run.

.EXAMPLE
    Connect-MgGraph -ClientId $AppId -TenantId $TenantId -CertificateThumbprint $Thumbprint
    ./Remove-WpdDeviceControlCoverage.ps1 -WhatIf

.EXAMPLE
    ./Remove-WpdDeviceControlCoverage.ps1
    # Reverts SecuredDevicesConfiguration to RemovableMediaDevices-only and drops the 4 WPD
    # omaSettings entries. The parent policy's original USB coverage is unaffected.

.NOTES
    Sources: same as deploy/Add-WpdDeviceControlCoverage.ps1's .NOTES block.
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$ParentPolicyDisplayName = 'Device Control - USB Removable Media Default-Deny Allowlist',

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$GraphBaseUri = 'https://graph.microsoft.com/v1.0'
)

$ErrorActionPreference = 'Stop'

# Must match the fixed GUIDs in deploy/Add-WpdDeviceControlCoverage.ps1 exactly.
$script:ApprovedWpdGroupId = 'f5a6b7c8-5555-4e6f-8081-92a3b4c5d6e7'
$script:AllWpdGroupId = 'a6b7c8d9-6666-4f70-9182-a3b4c5d6e7f8'
$script:AllowWpdRuleId = 'b7c8d9e0-7777-4081-a293-b4c5d6e7f809'
$script:DenyWpdRuleId = 'c8d9e0f1-8888-4192-b3a4-c5d6e7f8091a'

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

Assert-MgConnected

$configUri = "$GraphBaseUri/deviceManagement/deviceConfigurations"
$parent = Get-AllGraphValues -Uri $configUri | Where-Object { $_.displayName -eq $ParentPolicyDisplayName } | Select-Object -First 1

if (-not $parent) {
    Write-Host "Parent policy '$ParentPolicyDisplayName' not found - nothing to remove." -ForegroundColor Yellow
    return
}

$full = Invoke-MgGraphRequest -Method GET -Uri "$configUri/$($parent.id)"
$existingSettings = @($full.omaSettings)

$scopeSetting = $existingSettings | Where-Object { $_.omaUri -like '*SecuredDevicesConfiguration*' } | Select-Object -First 1
if (-not $scopeSetting -or $scopeSetting.value -notmatch 'WpdDevices') {
    Write-Host "Parent policy '$ParentPolicyDisplayName' does not currently have WPD coverage - nothing to remove." -ForegroundColor Yellow
    return
}

$keptSettings = $existingSettings | Where-Object {
    $_.omaUri -notlike '*SecuredDevicesConfiguration*' -and
    $_.omaUri -notlike "*$script:ApprovedWpdGroupId*" -and
    $_.omaUri -notlike "*$script:AllWpdGroupId*" -and
    $_.omaUri -notlike "*$script:AllowWpdRuleId*" -and
    $_.omaUri -notlike "*$script:DenyWpdRuleId*"
}

$revertedScopeSetting = @{
    '@odata.type' = '#microsoft.graph.omaSettingString'
    displayName   = $scopeSetting.displayName
    omaUri        = $scopeSetting.omaUri
    value         = 'RemovableMediaDevices'
}

$desiredSettings = @($keptSettings) + @($revertedScopeSetting)

Write-Host "  [plan] $($existingSettings.Count) existing omaSettings -> $($desiredSettings.Count) after removing WPD coverage (expect 11 -> 7)." -ForegroundColor DarkCyan

$body = @{
    '@odata.type' = '#microsoft.graph.windows10CustomConfiguration'
    omaSettings   = $desiredSettings
}

if ($PSCmdlet.ShouldProcess($ParentPolicyDisplayName, "PATCH $configUri/$($parent.id) (revert SecuredDevicesConfiguration to RemovableMediaDevices-only; remove 4 WPD omaSettings)")) {
    Invoke-MgGraphRequest -Method PATCH -Uri "$configUri/$($parent.id)" -Body ($body | ConvertTo-Json -Depth 8) | Out-Null
    Write-Host "  [coverage] WPD coverage removed from '$ParentPolicyDisplayName' (id $($parent.id))" -ForegroundColor Green
}

Write-Host "`nDone. Parent policy's RemovableMediaDevices coverage, assignment, and object identity are unchanged. A previously-approved WPD device (e.g. a phone in MTP mode) is now unrestricted again, not denied - see rollback.md before relying on this as an incident-response containment step." -ForegroundColor Cyan
```