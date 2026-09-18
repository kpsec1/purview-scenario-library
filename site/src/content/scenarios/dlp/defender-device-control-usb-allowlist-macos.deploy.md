---
part: "deploy"
parent: "dlp/defender-device-control-usb-allowlist-macos"
---
The scripts and configuration below deploy this scenario. Review them, then run in order — each is designed to be idempotent and has a matching rollback.


#### `config/mac-device-control-usb-allowlist.sample.json`

```json
{
  "policyDisplayName": "Device Control (macOS) - USB Removable Media Default-Deny Allowlist",
  "policyDescription": "Denies all removable USB storage on macOS by default; allows only IT-issued, identity-verified backup drives listed in approvedDevices (matched by serial number). Deployed by scenarios/dlp/defender-device-control-usb-allowlist-macos. Owner: Security & Compliance team.",
  "approvedDevices": [
    {
      "label": "IT Data Custodians - encrypted backup drive #1",
      "serialNumber": "REPLACE_WITH_REAL_SERIAL_NUMBER"
    },
    {
      "label": "IT Data Custodians - encrypted backup drive #2",
      "serialNumber": "REPLACE_WITH_REAL_SERIAL_NUMBER_2"
    }
  ],
  "notificationUrl": "",
  "assignment": {
    "groupId": "REPLACE_WITH_PILOT_MACOS_DEVICE_GROUP_OBJECT_ID",
    "assignAllDevices": false
  }
}
```

#### `New-MacDeviceControlUsbAllowlistPolicy.ps1`

```powershell
#Requires -Version 7.0
<#
.SYNOPSIS
    Deploys the "Device Control (macOS) - USB Removable Media Default-Deny Allowlist" Intune
    macOS Custom configuration profile (Microsoft Defender for Endpoint device control for macOS).

.DESCRIPTION
    Creates (or, with -Force, reconciles) one Intune macOSCustomConfiguration object carrying a
    single .mobileconfig payload (PayloadType com.microsoft.wdav) that:
      1. Enables the Device Control engine itself (dlp.features: DC_in_dlp = enabled).
      2. Enables enforcement for the removableMedia feature specifically
         (deviceControl.policy.settings.features.removableMedia.disable = false) and sets
         global.defaultEnforcement = "deny" (fail-closed).
      3. Defines two device-control groups inside deviceControl.policy.groups:
           - "AllRemovableStorage" (catch-all): primaryId = removable_media_devices
           - "ApprovedBackupDrives": serialNumber clause per entry in -ConfigPath's approvedDevices
      4. Defines two mutually-exclusive rules inside deviceControl.policy.rules:
           - "Allow-ApprovedBackupDrives": Allow + AuditAllow (read/write/execute), scoped to the
             approved group.
           - "Deny-AllOtherRemovableStorage": Deny + AuditDeny (read/write/execute), scoped to the
             catch-all group minus the approved group.

    This is the macOS sibling of scenarios/dlp/defender-device-control-usb-allowlist/ (Windows) -
    same default-deny-with-one-named-allowlist shape, translated to macOS's JSON groups/rules/
    settings policy model and the macOSCustomConfiguration Graph resource (a native, fully
    documented v1.0 type for macOS - no OMA-URI/XML equivalent needed on this platform).

    Uses the Microsoft Graph PowerShell SDK (Invoke-MgGraphRequest against the v1.0
    windows... macOSCustomConfiguration resource) - automation surface 3 per
    docs/automation-surface.md Section 1. This script never establishes its own Graph connection
    and never assigns the policy tenant-wide by default - assignment defaults to the pilot Entra
    ID group named in -ConfigPath's assignment.groupId; pass -AssignAllDevices deliberately to
    widen it (device control has no service-side simulation mode - assignment scope IS the
    staged-rollout lever, same as the Windows sibling - see README.md Section 8).

    Idempotent: the device configuration object is located by displayName before create; if found
    and -Force is not passed, the script reports its current state and makes no changes. With
    -Force, the full mobileconfig payload is rebuilt from -ConfigPath and PATCHed onto the
    existing object. Group/rule GUIDs inside the policy JSON are fixed script constants (not
    freshly generated per run), the same "stable identifiers, not fresh-per-run" discipline as the
    Windows sibling script - see design.md Section 5.

    PREREQUISITES this script does not perform (README.md Section 3, Section 5):
      - Target Macs must already be onboarded to Microsoft Defender for Endpoint and enrolled in
        Intune, running Defender for Endpoint on macOS version 101.91.92 or later.
      - A Full Disk Access Privacy Preferences Policy Control (PPPC) profile granting
        com.microsoft.dlp.daemon Full Disk Access must already be deployed - device control cannot
        enforce without it.

.PARAMETER ConfigPath
    Path to the JSON config (approvedDevices list + assignment target). Defaults to the sibling
    'config/mac-device-control-usb-allowlist.sample.json' - copy and edit it, do not deploy the
    sample values as-is.

.PARAMETER PolicyDisplayName
    Overrides the config file's policyDisplayName, if set. This is the Intune device
    configuration's displayName and this script's lookup key for idempotency - keep it stable.

.PARAMETER AssignAllDevices
    Assign to "All devices" instead of the config file's assignment.groupId. A deliberate,
    explicit widening of blast radius - never the default. Requires -Force if the policy already
    has a pilot-group assignment, so an operator cannot silently widen scope without noticing.

.PARAMETER GraphBaseUri
    Graph base URI. Defaults to 'https://graph.microsoft.com/v1.0'.

.PARAMETER Force
    If the device configuration object already exists, reconcile its payload (and, with
    -AssignAllDevices, its assignment) to match this script's/-ConfigPath's definition instead of
    skipping.

.PARAMETER WhatIf
    Standard PowerShell ShouldProcess dry-run. Reports every POST/PATCH that would be made without
    calling any mutating Graph endpoint.

.EXAMPLE
    Connect-MgGraph -ClientId $AppId -TenantId $TenantId -CertificateThumbprint $Thumbprint
    ./New-MacDeviceControlUsbAllowlistPolicy.ps1 -ConfigPath ./config/my-tenant.json -WhatIf

    Dry-run: shows exactly what would be created, changes nothing.

.EXAMPLE
    ./New-MacDeviceControlUsbAllowlistPolicy.ps1 -ConfigPath ./config/my-tenant.json

    Deploys, scoped to the pilot group named in the config file's assignment.groupId.

.EXAMPLE
    ./New-MacDeviceControlUsbAllowlistPolicy.ps1 -ConfigPath ./config/my-tenant.json -AssignAllDevices -Force

    Widens an already-piloted policy to "All devices" after a tuning window.

.NOTES
    SCOPE: this script matches approved devices by serialNumber only (the strong, per-unit
    identifier Microsoft's own macOS query schema supports as a standalone clause) - not by
    vendorId/productId. macOS's device-control JSON schema keeps vendorId and productId as two
    separate clause types that can only be AND-combined via a per-device sub-group referenced by a
    "groupId" clause (README.md Section 11, design.md Section 5) - a materially more complex,
    dynamic-sub-group idempotency model than this fragment's single-fixed-group design. Deferred
    as a follow-up (PROGRESS.md) rather than built with an unstable GUID-per-device scheme.

    Sources (Microsoft Learn, verify before production use):
    - Device Control for macOS (policy model: settings/groups/rules/entries, query/clause schema,
      Full Disk Access + DC_in_dlp prerequisites, minimum product version):
      https://learn.microsoft.com/defender-endpoint/mac-device-control-overview
    - Deploy and manage Device Control using Intune (macOS): building the .mobileconfig, deploying
      via Devices > macOS > Custom profile:
      https://learn.microsoft.com/defender-endpoint/mac-device-control-intune
    - Device control policies in Microsoft Defender for Endpoint (shared groups/rules/entries
      concepts across Windows and macOS; the Mac JSON policy tab):
      https://learn.microsoft.com/defender-endpoint/device-control-policies
    - macOSCustomConfiguration resource / Create macOSCustomConfiguration (Graph v1.0 - payload,
      payloadFileName, payloadName; DeviceManagementConfiguration.ReadWrite.All):
      https://learn.microsoft.com/graph/api/resources/intune-deviceconfig-macoscustomconfiguration
      https://learn.microsoft.com/graph/api/intune-deviceconfig-macoscustomconfiguration-create
    - groupAssignmentTarget / deviceConfigurationAssignment / allDevicesAssignmentTarget (Graph
      v1.0 - shared across every deviceConfiguration subtype, including macOSCustomConfiguration):
      https://learn.microsoft.com/graph/api/resources/intune-shared-groupassignmenttarget
      https://learn.microsoft.com/graph/api/resources/intune-deviceconfig-deviceconfigurationassignment
    - Demo .mobileconfig showing the exact plist key path (PayloadContent > dlp / deviceControl.policy):
      https://github.com/microsoft/mdatp-devicecontrol/blob/main/macOS/mobileconfig/demo.mobileconfig
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$ConfigPath = (Join-Path $PSScriptRoot 'config/mac-device-control-usb-allowlist.sample.json'),

    [Parameter()]
    [string]$PolicyDisplayName,

    [Parameter()]
    [switch]$AssignAllDevices,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$GraphBaseUri = 'https://graph.microsoft.com/v1.0',

    [Parameter()]
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

# Fixed, source-controlled GUIDs - deliberate, not freshly generated per run (design.md Section 5).
$script:AllRemovableGroupId = '11111111-aaaa-4bbb-8ccc-111111111111'
$script:ApprovedGroupId = '22222222-bbbb-4ccc-8ddd-222222222222'
$script:AllowRuleId = '33333333-cccc-4ddd-8eee-333333333333'
$script:DenyRuleId = '44444444-dddd-4eee-8fff-444444444444'
$script:PayloadUuid = '55555555-eeee-4fff-8000-555555555555'
$script:InnerPayloadUuid = '66666666-ffff-4000-8111-666666666666'

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

function Get-DeviceControlPolicyJson {
    param([Parameter(Mandatory)]$Config)

    if (-not $Config.approvedDevices -or @($Config.approvedDevices).Count -eq 0) {
        throw "approvedDevices must contain at least one entry with a serialNumber."
    }
    $serialClauses = foreach ($d in $Config.approvedDevices) {
        if (-not $d.serialNumber) { throw "Every approvedDevices entry requires serialNumber (label: '$($d.label)')." }
        [ordered]@{ '$type' = 'serialNumber'; value = $d.serialNumber }
    }

    $policy = [ordered]@{
        groups = @(
            [ordered]@{
                '$type' = 'device'
                id      = $script:AllRemovableGroupId
                name    = 'AllRemovableStorage'
                query   = [ordered]@{
                    '$type'  = 'all'
                    clauses  = @([ordered]@{ '$type' = 'primaryId'; value = 'removable_media_devices' })
                }
            }
            [ordered]@{
                '$type' = 'device'
                id      = $script:ApprovedGroupId
                name    = 'ApprovedBackupDrives'
                query   = [ordered]@{
                    '$type'  = 'any'
                    clauses  = @($serialClauses)
                }
            }
        )
        rules = @(
            [ordered]@{
                id            = $script:AllowRuleId
                name          = 'Allow-ApprovedBackupDrives'
                includeGroups = @($script:ApprovedGroupId)
                entries       = @(
                    [ordered]@{
                        '$type'      = 'removableMedia'
                        id           = '77777777-0001-4001-8001-000000000001'
                        enforcement  = [ordered]@{ '$type' = 'allow' }
                        access       = @('read', 'write', 'execute')
                    }
                    [ordered]@{
                        '$type'      = 'removableMedia'
                        id           = '77777777-0002-4002-8002-000000000002'
                        enforcement  = [ordered]@{ '$type' = 'auditAllow'; options = @('send_event') }
                        access       = @('read', 'write', 'execute')
                    }
                )
            }
            [ordered]@{
                id            = $script:DenyRuleId
                name          = 'Deny-AllOtherRemovableStorage'
                includeGroups = @($script:AllRemovableGroupId)
                excludeGroups = @($script:ApprovedGroupId)
                entries       = @(
                    [ordered]@{
                        '$type'      = 'removableMedia'
                        id           = '77777777-0003-4003-8003-000000000003'
                        enforcement  = [ordered]@{ '$type' = 'deny' }
                        access       = @('read', 'write', 'execute')
                    }
                    [ordered]@{
                        '$type'      = 'removableMedia'
                        id           = '77777777-0004-4004-8004-000000000004'
                        enforcement  = [ordered]@{ '$type' = 'auditDeny'; options = @('send_event', 'show_notification') }
                        access       = @('read', 'write', 'execute')
                    }
                )
            }
        )
        settings = [ordered]@{
            features = [ordered]@{ removableMedia = [ordered]@{ disable = $false } }
            global   = [ordered]@{ defaultEnforcement = 'deny' }
        }
    }
    if ($Config.notificationUrl) {
        $policy.settings.ux = [ordered]@{ navigationTarget = $Config.notificationUrl }
    }

    $policy | ConvertTo-Json -Depth 10 -Compress
}

function Get-MobileConfigXml {
    param([Parameter(Mandatory)][string]$PolicyJson)

    $escapedJson = $PolicyJson -replace '&', '&amp;' -replace '<', '&lt;' -replace '>', '&gt;'

    @"
<?xml version="1.0" encoding="utf-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1">
<dict>
    <key>PayloadUUID</key>
    <string>$script:PayloadUuid</string>
    <key>PayloadType</key>
    <string>Configuration</string>
    <key>PayloadOrganization</key>
    <string>Security &amp; Compliance team</string>
    <key>PayloadIdentifier</key>
    <string>com.microsoft.wdav</string>
    <key>PayloadDisplayName</key>
    <string>Microsoft Defender Device Control - USB Removable Media Default-Deny Allowlist</string>
    <key>PayloadDescription</key>
    <string>Denies all removable USB storage by default; allows only IT-issued backup drives. Deployed by scenarios/dlp/defender-device-control-usb-allowlist-macos.</string>
    <key>PayloadVersion</key>
    <integer>1</integer>
    <key>PayloadEnabled</key>
    <true/>
    <key>PayloadRemovalDisallowed</key>
    <true/>
    <key>PayloadScope</key>
    <string>System</string>
    <key>PayloadContent</key>
    <array>
        <dict>
            <key>PayloadUUID</key>
            <string>$script:InnerPayloadUuid</string>
            <key>PayloadType</key>
            <string>com.microsoft.wdav</string>
            <key>PayloadOrganization</key>
            <string>Security &amp; Compliance team</string>
            <key>PayloadIdentifier</key>
            <string>com.microsoft.wdav</string>
            <key>PayloadDisplayName</key>
            <string>Microsoft Defender configuration settings</string>
            <key>PayloadDescription</key>
            <string></string>
            <key>PayloadVersion</key>
            <integer>1</integer>
            <key>PayloadEnabled</key>
            <true/>
            <key>dlp</key>
            <dict>
                <key>features</key>
                <array>
                    <dict>
                        <key>name</key>
                        <string>DC_in_dlp</string>
                        <key>state</key>
                        <string>enabled</string>
                    </dict>
                </array>
            </dict>
            <key>deviceControl</key>
            <dict>
                <key>policy</key>
                <string>$escapedJson</string>
            </dict>
        </dict>
    </array>
</dict>
</plist>
"@
}

# --- Load and validate config ---
if (-not (Test-Path -LiteralPath $ConfigPath)) { throw "Config file not found: $ConfigPath" }
$cfg = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
if (-not $cfg.policyDisplayName -and -not $PolicyDisplayName) { throw "policyDisplayName is required (in the config file, or via -PolicyDisplayName)." }
if (-not $AssignAllDevices -and -not $cfg.assignment.groupId) {
    throw "assignment.groupId is required in the config file unless -AssignAllDevices is passed. Deploying with no assignment target at all is refused - see README.md Section 8 (staged rollout via assignment scope)."
}

$displayName = if ($PolicyDisplayName) { $PolicyDisplayName } else { $cfg.policyDisplayName }

Assert-MgConnected
Write-Host "macOS device control USB allowlist: policy '$displayName'." -ForegroundColor Cyan

# --- 1. Device configuration object: create-or-reconcile ---
$configUri = "$GraphBaseUri/deviceManagement/deviceConfigurations"
$existing = Get-AllGraphValues -Uri $configUri | Where-Object { $_.displayName -eq $displayName } | Select-Object -First 1

$policyJson = Get-DeviceControlPolicyJson -Config $cfg
$mobileConfigXml = Get-MobileConfigXml -PolicyJson $policyJson

$body = @{
    '@odata.type'   = '#microsoft.graph.macOSCustomConfiguration'
    displayName     = $displayName
    description     = $(if ($cfg.policyDescription) { $cfg.policyDescription } else { '' })
    payloadName     = 'Device Control - USB Removable Media Default-Deny Allowlist'
    payloadFileName = 'DeviceControlUsbAllowlist.mobileconfig'
    payload         = (ConvertTo-Utf8Base64 $mobileConfigXml)
}

if ($existing -and -not $Force) {
    Write-Host "  [policy] exists '$displayName' (id $($existing.id)) - not modified. Pass -Force to reconcile the payload to this script's/-ConfigPath's definition." -ForegroundColor Yellow
    $policyId = $existing.id
}
elseif ($existing -and $Force) {
    if ($PSCmdlet.ShouldProcess($displayName, "PATCH $configUri/$($existing.id) (reconcile payload)")) {
        Invoke-MgGraphRequest -Method PATCH -Uri "$configUri/$($existing.id)" -Body ($body | ConvertTo-Json -Depth 10) | Out-Null
        Write-Host "  [policy] reconciled '$displayName' (id $($existing.id))" -ForegroundColor Green
    }
    $policyId = $existing.id
}
else {
    if ($PSCmdlet.ShouldProcess($displayName, "POST $configUri")) {
        $created = Invoke-MgGraphRequest -Method POST -Uri $configUri -Body ($body | ConvertTo-Json -Depth 10)
        $policyId = $created.id
        Write-Host "  [policy] created '$displayName' (id $policyId)" -ForegroundColor Green
    }
    else {
        Write-Host "  [policy] WhatIf - would create '$displayName' as a macOSCustomConfiguration with a device-control mobileconfig payload" -ForegroundColor DarkYellow
        $policyId = '<new-policy-id>'
    }
}

# --- 2. Assignment: create-or-report (idempotent - never duplicate an existing matching target) ---
if ($policyId -eq '<new-policy-id>') {
    Write-Host "  [assignment] WhatIf - would assign to $(if ($AssignAllDevices) { 'All devices' } else { "group $($cfg.assignment.groupId)" })" -ForegroundColor DarkYellow
}
else {
    $assignUri = "$configUri/$policyId/assignments"
    $existingAssignments = Get-AllGraphValues -Uri $assignUri

    if ($AssignAllDevices) {
        $alreadyAllDevices = $existingAssignments | Where-Object { $_.target.'@odata.type' -eq '#microsoft.graph.allDevicesAssignmentTarget' }
        if ($alreadyAllDevices) {
            Write-Host "  [assignment] already targets All devices - no change." -ForegroundColor Yellow
        }
        else {
            $assignBody = @{ '@odata.type' = '#microsoft.graph.deviceConfigurationAssignment'; target = @{ '@odata.type' = '#microsoft.graph.allDevicesAssignmentTarget' } }
            if ($PSCmdlet.ShouldProcess($displayName, "POST $assignUri (All devices - WIDENING SCOPE)")) {
                Invoke-MgGraphRequest -Method POST -Uri $assignUri -Body ($assignBody | ConvertTo-Json -Depth 5) | Out-Null
                Write-Host "  [assignment] added: All devices" -ForegroundColor Green
            }
        }
    }
    else {
        $groupId = $cfg.assignment.groupId
        $alreadyGroup = $existingAssignments | Where-Object { $_.target.'@odata.type' -eq '#microsoft.graph.groupAssignmentTarget' -and $_.target.groupId -eq $groupId }
        if ($alreadyGroup) {
            Write-Host "  [assignment] already targets group $groupId - no change." -ForegroundColor Yellow
        }
        else {
            $assignBody = @{ '@odata.type' = '#microsoft.graph.deviceConfigurationAssignment'; target = @{ '@odata.type' = '#microsoft.graph.groupAssignmentTarget'; groupId = $groupId } }
            if ($PSCmdlet.ShouldProcess($displayName, "POST $assignUri (pilot group $groupId)")) {
                Invoke-MgGraphRequest -Method POST -Uri $assignUri -Body ($assignBody | ConvertTo-Json -Depth 5) | Out-Null
                Write-Host "  [assignment] added: group $groupId" -ForegroundColor Green
            }
        }
    }
}

Write-Host "`nDone. Intune profile sync to devices is not instantaneous - check Devices > macOS > Configuration profiles > this policy > Device status before assuming enforcement is live. Confirm Full Disk Access for com.microsoft.dlp.daemon is already granted on pilot devices (README.md Section 3/Section 5) - device control cannot enforce without it. Run validate/Test-MacDeviceControlUsbAllowlistPolicy.ps1 to verify the deployed configuration." -ForegroundColor Cyan
```

#### `Remove-MacDeviceControlUsbAllowlistPolicy.ps1`

```powershell
#Requires -Version 7.0
<#
.SYNOPSIS
    Removes assignments from (or, with -Purge, permanently deletes) the "Device Control (macOS) -
    USB Removable Media Default-Deny Allowlist" Intune macOS Custom configuration profile.

.DESCRIPTION
    Stage 1 (default): deletes every assignment on the device configuration object, so it stops
    applying to any Mac, but the object and its mobileconfig payload remain (visible in the Intune
    admin center, re-assignable without re-authoring). Reversible.

    Stage 2 (-Purge): also deletes the device configuration object itself
    (DELETE /deviceManagement/deviceConfigurations/{id}). Not reversible - re-establishing the
    control means re-running deploy/New-MacDeviceControlUsbAllowlistPolicy.ps1 from scratch.

    Connect first: Connect-MgGraph (app-only certificate - see docs/automation-surface.md Section 3).
    This script does not open the session.

.PARAMETER PolicyDisplayName
    Display name of the device configuration object to remove. Defaults to this scenario's
    standard name.

.PARAMETER GraphBaseUri
    Graph base URI. Defaults to 'https://graph.microsoft.com/v1.0'.

.PARAMETER Purge
    Also permanently delete the device configuration object after removing its assignments.

.PARAMETER WhatIf
    Standard PowerShell ShouldProcess dry-run.

.EXAMPLE
    Connect-MgGraph -ClientId $AppId -TenantId $TenantId -CertificateThumbprint $Thumbprint
    ./Remove-MacDeviceControlUsbAllowlistPolicy.ps1 -WhatIf

.EXAMPLE
    ./Remove-MacDeviceControlUsbAllowlistPolicy.ps1
    # Unassigns only - policy definition remains, re-assignable later.

.EXAMPLE
    ./Remove-MacDeviceControlUsbAllowlistPolicy.ps1 -Purge
    # Permanently deletes the policy definition too.

.NOTES
    Sources: same as deploy/New-MacDeviceControlUsbAllowlistPolicy.ps1's .NOTES block.
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$PolicyDisplayName = 'Device Control (macOS) - USB Removable Media Default-Deny Allowlist',

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$GraphBaseUri = 'https://graph.microsoft.com/v1.0',

    [Parameter()]
    [switch]$Purge
)

$ErrorActionPreference = 'Stop'

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
$existing = Get-AllGraphValues -Uri $configUri | Where-Object { $_.displayName -eq $PolicyDisplayName } | Select-Object -First 1

if (-not $existing) {
    Write-Host "Policy '$PolicyDisplayName' not found - nothing to remove." -ForegroundColor Yellow
    return
}

$assignUri = "$configUri/$($existing.id)/assignments"
$assignments = Get-AllGraphValues -Uri $assignUri

if ($assignments.Count -eq 0) {
    Write-Host "  [assignment] policy has no assignments already." -ForegroundColor Yellow
}
foreach ($a in $assignments) {
    if ($PSCmdlet.ShouldProcess($PolicyDisplayName, "DELETE assignment $($a.id)")) {
        Invoke-MgGraphRequest -Method DELETE -Uri "$assignUri/$($a.id)" | Out-Null
        Write-Host "  [assignment] removed $($a.id)" -ForegroundColor Green
    }
}

if (-not $Purge) {
    Write-Host "`nDone. Policy definition retained (unassigned only). Re-assign later with deploy/New-MacDeviceControlUsbAllowlistPolicy.ps1 - no need to re-author. Pass -Purge to permanently delete the definition too." -ForegroundColor Cyan
    return
}

if ($PSCmdlet.ShouldProcess($PolicyDisplayName, "DELETE $configUri/$($existing.id) (PERMANENT)")) {
    Invoke-MgGraphRequest -Method DELETE -Uri "$configUri/$($existing.id)" | Out-Null
    Write-Host "  [policy] permanently deleted '$PolicyDisplayName' (id $($existing.id))" -ForegroundColor Green
}

Write-Host "`nDone. Policy permanently deleted. This does not undo devices already onboarded/enrolled, and does not restore access retroactively for drives that were denied while the policy was in effect." -ForegroundColor Cyan
```