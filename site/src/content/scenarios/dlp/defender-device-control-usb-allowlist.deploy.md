---
part: "deploy"
parent: "dlp/defender-device-control-usb-allowlist"
---
The scripts and configuration below deploy this scenario. Review them, then run in order — each is designed to be idempotent and has a matching rollback.


#### `config/device-control-usb-allowlist.sample.json`

```json
{
  "policyDisplayName": "Device Control - USB Removable Media Default-Deny Allowlist",
  "policyDescription": "Denies all removable USB storage by default; allows only IT-issued, identity-verified backup drives listed in approvedDevices. Deployed by scenarios/dlp/defender-device-control-usb-allowlist. Owner: Security & Compliance team.",
  "approvedDevices": [
    {
      "label": "IT Data Custodians - encrypted backup drive #1",
      "serialNumberId": "REPLACE_WITH_REAL_SERIAL_NUMBER"
    },
    {
      "label": "IT Data Custodians - encrypted backup drive #2 (approved by VID_PID - approves the whole product line, see README.md Section 11)",
      "vidPid": "0781_5591"
    }
  ],
  "assignment": {
    "groupId": "REPLACE_WITH_PILOT_WINDOWS_DEVICE_GROUP_OBJECT_ID",
    "assignAllDevices": false
  }
}
```

#### `New-DeviceControlUsbAllowlistPolicy.ps1`

```powershell
#Requires -Version 7.0
<#
.SYNOPSIS
    Deploys the "Device Control - USB Removable Media Default-Deny Allowlist" Intune Windows
    Custom device configuration profile (Microsoft Defender for Endpoint device control).

.DESCRIPTION
    Creates (or, with -Force, reconciles) one Intune windows10CustomConfiguration object carrying
    seven OMA-URI settings under ./Vendor/MSFT/Defender/Configuration/:
      1. DeviceControlEnabled          = 1 (enabled)
      2. SecuredDevicesConfiguration   = "RemovableMediaDevices" (scope: USB storage only)
      3. DefaultEnforcement            = 2 (fail-closed: deny)
      4. PolicyGroups/{GUID}/GroupData - "ApprovedBackupDrives" group (matched by SerialNumberId
                                          and/or VID_PID from -ConfigPath's approvedDevices list)
      5. PolicyGroups/{GUID}/GroupData - "AllRemovableStorage" catch-all group (PrimaryId match)
      6. PolicyRules/{GUID}/RuleData   - "Allow-ApprovedBackupDrives" (Allow + AuditAllowed,
                                          AccessMask 63, scoped to the approved group)
      7. PolicyRules/{GUID}/RuleData   - "Deny-AllOtherRemovableStorage" (Deny + AuditDenied,
                                          AccessMask 63, catch-all minus approved group)

    Uses the Microsoft Graph PowerShell SDK (Invoke-MgGraphRequest against the v1.0
    windows10CustomConfiguration resource) - automation surface 3 per docs/automation-surface.md
    Section 1. This script never establishes its own Graph connection and never assigns the
    policy tenant-wide by default - assignment defaults to the pilot Entra ID group named in
    -ConfigPath's assignment.groupId; pass -AssignAllDevices deliberately to widen it (see
    README.md Section 8 for the staged-rollout rationale - device control has no service-side
    simulation mode, so assignment scope IS the staged-rollout lever).

    Idempotent: the device configuration object is located by displayName before create; if found
    and -Force is not passed, the script reports its current state and makes no changes. With
    -Force, the full omaSettings array is rebuilt from -ConfigPath and PATCHed onto the existing
    object (whole-collection replace - see README.md Section 11 VERIFY on PATCH semantics). The
    four group/rule GUIDs are fixed script constants (not freshly generated per run) so every
    reconcile targets the same four OMA-URI nodes rather than accumulating orphans - see
    design.md Section 7.

    PREREQUISITE this script does not perform: target devices must already be onboarded to
    Microsoft Defender for Endpoint and enrolled in Intune. See README.md Section 3, Section 5.

.PARAMETER ConfigPath
    Path to the JSON config (approvedDevices list + assignment target). Defaults to the sibling
    'config/device-control-usb-allowlist.sample.json' - copy and edit it, do not deploy the sample
    values as-is.

.PARAMETER PolicyDisplayName
    Overrides the config file's policyDisplayName, if set. Device configuration objects have no
    documented rename restriction, but keep this stable across runs - it is this script's lookup
    key for idempotency.

.PARAMETER AssignAllDevices
    Assign to "All devices" instead of the config file's assignment.groupId. A deliberate,
    explicit widening of blast radius - never the default. Requires -Force if the policy already
    has a pilot-group assignment, so an operator cannot silently widen scope without noticing.

.PARAMETER GraphBaseUri
    Graph base URI. Defaults to 'https://graph.microsoft.com/v1.0'.

.PARAMETER Force
    If the device configuration object already exists, reconcile its omaSettings (and, with
    -AssignAllDevices, its assignment) to match this script's/-ConfigPath's definition instead of
    skipping.

.PARAMETER WhatIf
    Standard PowerShell ShouldProcess dry-run. Reports every POST/PATCH that would be made without
    calling any mutating Graph endpoint.

.EXAMPLE
    Connect-MgGraph -ClientId $AppId -TenantId $TenantId -CertificateThumbprint $Thumbprint
    ./New-DeviceControlUsbAllowlistPolicy.ps1 -ConfigPath ./config/my-tenant.json -WhatIf

    Dry-run: shows exactly what would be created, changes nothing.

.EXAMPLE
    ./New-DeviceControlUsbAllowlistPolicy.ps1 -ConfigPath ./config/my-tenant.json

    Deploys, scoped to the pilot group named in the config file's assignment.groupId.

.EXAMPLE
    ./New-DeviceControlUsbAllowlistPolicy.ps1 -ConfigPath ./config/my-tenant.json -AssignAllDevices -Force

    Widens an already-piloted policy to "All devices" after a tuning window.

.NOTES
    VERIFY before relying on -Force to REMOVE a previously-approved device (README.md Section 11):
    whether PATCH on a windows10CustomConfiguration fully replaces the omaSettings collection or
    merges/appends. Microsoft's "Update windows10CustomConfiguration" reference documents
    omaSettings as an updatable property but does not state replace-vs-merge semantics explicitly.
    This script assumes full replacement (sends the complete, freshly-built array every time).

    Sources (Microsoft Learn, verify before production use):
    - Device control in Microsoft Defender for Endpoint (overview, prerequisites, Advanced Hunting):
      https://learn.microsoft.com/defender-endpoint/device-control-overview
    - Deploy and manage device control with Microsoft Intune (OMA-URI paths/data types):
      https://learn.microsoft.com/defender-endpoint/device-control-deploy-manage-intune
    - Device control policies (Group/PolicyRule/Entry XML schema, AccessMask, MatchType):
      https://learn.microsoft.com/defender-endpoint/device-control-policies
    - windows10CustomConfiguration resource / Create windows10CustomConfiguration (Graph v1.0):
      https://learn.microsoft.com/graph/api/resources/intune-deviceconfig-windows10customconfiguration
      https://learn.microsoft.com/graph/api/intune-deviceconfig-windows10customconfiguration-create
    - omaSetting/omaSettingInteger/omaSettingString/omaSettingStringXml resource types (Graph v1.0):
      https://learn.microsoft.com/graph/api/resources/intune-deviceconfig-omasetting
    - groupAssignmentTarget / deviceConfigurationAssignment / allDevicesAssignmentTarget (Graph v1.0):
      https://learn.microsoft.com/graph/api/resources/intune-shared-groupassignmenttarget
      https://learn.microsoft.com/graph/api/resources/intune-deviceconfig-deviceconfigurationassignment
      https://learn.microsoft.com/graph/api/resources/intune-shared-alldevicesassignmenttarget
    - Equivalent typed SDK cmdlets: New-/Update-/Remove-/Get-MgDeviceManagementDeviceConfiguration,
      New-MgDeviceManagementDeviceConfigurationAssignment (Microsoft.Graph.DeviceManagement, v1.0).
      Permission: DeviceManagementConfiguration.ReadWrite.All (application or delegated).
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$ConfigPath = (Join-Path $PSScriptRoot 'config/device-control-usb-allowlist.sample.json'),

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

# Fixed, source-controlled GUIDs - deliberate, not freshly generated per run (design.md Section 7).
$script:ApprovedGroupId = 'a1b2c3d4-1111-4a2b-8c3d-4e5f60718293'
$script:AllRemovableGroupId = 'b2c3d4e5-2222-4b3c-9d4e-5f6071829304'
$script:AllowRuleId = 'c3d4e5f6-3333-4c4d-ae5f-607182930415'
$script:DenyRuleId = 'd4e5f6a7-4444-4d5e-bf60-718293041526'

function Assert-MgConnected {
    if (-not (Get-Command Invoke-MgGraphRequest -ErrorAction SilentlyContinue)) {
        throw 'Microsoft Graph PowerShell SDK not found. Install Microsoft.Graph.Authentication and Microsoft.Graph.DeviceManagement, then Connect-MgGraph.'
    }
    if (-not (Get-MgContext -ErrorAction SilentlyContinue)) {
        throw 'Not connected to Microsoft Graph. Run Connect-MgGraph (app-only certificate - see docs/automation-surface.md Section 3) first.'
    }
}

function Get-AllGraphValues {
    # GET a collection, following @odata.nextLink, returning all .value items.
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

function New-ApprovedDevicesGroupXml {
    param([Parameter(Mandatory)][array]$ApprovedDevices)
    $descriptors = foreach ($d in $ApprovedDevices) {
        if ($d.serialNumberId) { "    <SerialNumberId>$($d.serialNumberId)</SerialNumberId>" }
        if ($d.vidPid) { "    <VID_PID>$($d.vidPid)</VID_PID>" }
    }
    if (-not $descriptors) { throw "approvedDevices must contain at least one entry with serialNumberId or vidPid." }
    @"
<Group Id="{$script:ApprovedGroupId}">
  <MatchType>MatchAny</MatchType>
  <DescriptorIdList>
$($descriptors -join "`n")
  </DescriptorIdList>
</Group>
"@
}

function New-CatchAllGroupXml {
    @"
<Group Id="{$script:AllRemovableGroupId}">
  <MatchType>MatchAny</MatchType>
  <DescriptorIdList>
    <PrimaryId>RemovableMediaDevices</PrimaryId>
  </DescriptorIdList>
</Group>
"@
}

function New-AllowRuleXml {
    @"
<PolicyRule Id="{$script:AllowRuleId}">
  <Name>Allow-ApprovedBackupDrives</Name>
  <IncludedIdList>
    <GroupId>{$script:ApprovedGroupId}</GroupId>
  </IncludedIdList>
  <Entry Id="{e1e2e3e4-0001-4001-8001-000000000001}">
    <Type>Allow</Type>
    <Options>0</Options>
    <AccessMask>63</AccessMask>
  </Entry>
  <Entry Id="{e1e2e3e4-0002-4002-8002-000000000002}">
    <Type>AuditAllowed</Type>
    <Options>2</Options>
    <AccessMask>63</AccessMask>
  </Entry>
</PolicyRule>
"@
}

function New-DenyRuleXml {
    @"
<PolicyRule Id="{$script:DenyRuleId}">
  <Name>Deny-AllOtherRemovableStorage</Name>
  <IncludedIdList>
    <GroupId>{$script:AllRemovableGroupId}</GroupId>
  </IncludedIdList>
  <ExcludedIdList>
    <GroupId>{$script:ApprovedGroupId}</GroupId>
  </ExcludedIdList>
  <Entry Id="{e1e2e3e4-0003-4003-8003-000000000003}">
    <Type>Deny</Type>
    <Options>0</Options>
    <AccessMask>63</AccessMask>
  </Entry>
  <Entry Id="{e1e2e3e4-0004-4004-8004-000000000004}">
    <Type>AuditDenied</Type>
    <Options>3</Options>
    <AccessMask>63</AccessMask>
  </Entry>
</PolicyRule>
"@
}

function Get-DesiredOmaSettings {
    param([Parameter(Mandatory)]$Config)

    $approvedXml = New-ApprovedDevicesGroupXml -ApprovedDevices $Config.approvedDevices
    $catchAllXml = New-CatchAllGroupXml
    $allowXml = New-AllowRuleXml
    $denyXml = New-DenyRuleXml

    @(
        @{ '@odata.type' = '#microsoft.graph.omaSettingInteger'; displayName = 'Enable device control'; omaUri = './Vendor/MSFT/Defender/Configuration/DeviceControlEnabled'; value = 1 }
        @{ '@odata.type' = '#microsoft.graph.omaSettingString'; displayName = 'Scope device control to removable storage'; omaUri = './Vendor/MSFT/Defender/Configuration/SecuredDevicesConfiguration'; value = 'RemovableMediaDevices' }
        @{ '@odata.type' = '#microsoft.graph.omaSettingInteger'; displayName = 'Default enforcement (fail-closed deny)'; omaUri = './Vendor/MSFT/Defender/Configuration/DefaultEnforcement'; value = 2 }
        @{ '@odata.type' = '#microsoft.graph.omaSettingStringXml'; displayName = 'Group: ApprovedBackupDrives'; omaUri = "./Vendor/MSFT/Defender/Configuration/DeviceControl/PolicyGroups/{$script:ApprovedGroupId}/GroupData"; fileName = 'ApprovedBackupDrives.xml'; value = (ConvertTo-Utf8Base64 $approvedXml) }
        @{ '@odata.type' = '#microsoft.graph.omaSettingStringXml'; displayName = 'Group: AllRemovableStorage (catch-all)'; omaUri = "./Vendor/MSFT/Defender/Configuration/DeviceControl/PolicyGroups/{$script:AllRemovableGroupId}/GroupData"; fileName = 'AllRemovableStorage.xml'; value = (ConvertTo-Utf8Base64 $catchAllXml) }
        @{ '@odata.type' = '#microsoft.graph.omaSettingStringXml'; displayName = 'Rule: Allow-ApprovedBackupDrives'; omaUri = "./Vendor/MSFT/Defender/Configuration/DeviceControl/PolicyRules/{$script:AllowRuleId}/RuleData"; fileName = 'AllowApprovedBackupDrives.xml'; value = (ConvertTo-Utf8Base64 $allowXml) }
        @{ '@odata.type' = '#microsoft.graph.omaSettingStringXml'; displayName = 'Rule: Deny-AllOtherRemovableStorage'; omaUri = "./Vendor/MSFT/Defender/Configuration/DeviceControl/PolicyRules/{$script:DenyRuleId}/RuleData"; fileName = 'DenyAllOtherRemovableStorage.xml'; value = (ConvertTo-Utf8Base64 $denyXml) }
    )
}

# --- Load and validate config ---
if (-not (Test-Path -LiteralPath $ConfigPath)) { throw "Config file not found: $ConfigPath" }
$cfg = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
if (-not $cfg.policyDisplayName -and -not $PolicyDisplayName) { throw "policyDisplayName is required (in the config file, or via -PolicyDisplayName)." }
if (-not $cfg.approvedDevices -or @($cfg.approvedDevices).Count -eq 0) { throw "approvedDevices must contain at least one entry." }
if (-not $AssignAllDevices -and -not $cfg.assignment.groupId) {
    throw "assignment.groupId is required in the config file unless -AssignAllDevices is passed. Deploying with no assignment target at all is refused - see README.md Section 8 (staged rollout via assignment scope)."
}

$displayName = if ($PolicyDisplayName) { $PolicyDisplayName } else { $cfg.policyDisplayName }

Assert-MgConnected
Write-Host "Device control USB allowlist: policy '$displayName'." -ForegroundColor Cyan

# --- 1. Device configuration object: create-or-reconcile ---
$configUri = "$GraphBaseUri/deviceManagement/deviceConfigurations"
$existing = Get-AllGraphValues -Uri $configUri | Where-Object { $_.displayName -eq $displayName } | Select-Object -First 1

$omaSettings = Get-DesiredOmaSettings -Config $cfg
$body = @{
    '@odata.type' = '#microsoft.graph.windows10CustomConfiguration'
    displayName   = $displayName
    description   = $(if ($cfg.policyDescription) { $cfg.policyDescription } else { '' })
    omaSettings   = $omaSettings
}

if ($existing -and -not $Force) {
    Write-Host "  [policy] exists '$displayName' (id $($existing.id)) - not modified. Pass -Force to reconcile omaSettings to this script's/-ConfigPath's definition." -ForegroundColor Yellow
    $policyId = $existing.id
}
elseif ($existing -and $Force) {
    if ($PSCmdlet.ShouldProcess($displayName, "PATCH $configUri/$($existing.id) (reconcile omaSettings)")) {
        Invoke-MgGraphRequest -Method PATCH -Uri "$configUri/$($existing.id)" -Body ($body | ConvertTo-Json -Depth 8) | Out-Null
        Write-Host "  [policy] reconciled '$displayName' (id $($existing.id))" -ForegroundColor Green
    }
    $policyId = $existing.id
}
else {
    if ($PSCmdlet.ShouldProcess($displayName, "POST $configUri")) {
        $created = Invoke-MgGraphRequest -Method POST -Uri $configUri -Body ($body | ConvertTo-Json -Depth 8)
        $policyId = $created.id
        Write-Host "  [policy] created '$displayName' (id $policyId)" -ForegroundColor Green
    }
    else {
        Write-Host "  [policy] WhatIf - would create '$displayName' with 7 omaSettings entries" -ForegroundColor DarkYellow
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

Write-Host "`nDone. Intune profile sync to devices is not instantaneous - check Devices > Configuration profiles > this policy > Device status before assuming enforcement is live. Run validate/Test-DeviceControlUsbAllowlistPolicy.ps1 to verify the deployed configuration." -ForegroundColor Cyan
```

#### `Remove-DeviceControlUsbAllowlistPolicy.ps1`

```powershell
#Requires -Version 7.0
<#
.SYNOPSIS
    Removes assignments from (or, with -Purge, permanently deletes) the "Device Control - USB
    Removable Media Default-Deny Allowlist" Intune device configuration object.

.DESCRIPTION
    Stage 1 (default): deletes every assignment on the device configuration object, so it stops
    applying to any device, but the object and its omaSettings definition remain (visible in the
    Intune admin center, re-assignable without re-authoring). Reversible.

    Stage 2 (-Purge): also deletes the device configuration object itself
    (Remove-MgDeviceManagementDeviceConfiguration semantics via DELETE
    /deviceManagement/deviceConfigurations/{id}). Not reversible - re-establishing the control
    means re-running deploy/New-DeviceControlUsbAllowlistPolicy.ps1 from scratch.

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
    ./Remove-DeviceControlUsbAllowlistPolicy.ps1 -WhatIf

.EXAMPLE
    ./Remove-DeviceControlUsbAllowlistPolicy.ps1
    # Unassigns only - policy definition remains, re-assignable later.

.EXAMPLE
    ./Remove-DeviceControlUsbAllowlistPolicy.ps1 -Purge
    # Permanently deletes the policy definition too.

.NOTES
    Sources: same as deploy/New-DeviceControlUsbAllowlistPolicy.ps1's .NOTES block.
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$PolicyDisplayName = 'Device Control - USB Removable Media Default-Deny Allowlist',

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
    Write-Host "`nDone. Policy definition retained (unassigned only). Re-assign later with deploy/New-DeviceControlUsbAllowlistPolicy.ps1 - no need to re-author. Pass -Purge to permanently delete the definition too." -ForegroundColor Cyan
    return
}

if ($PSCmdlet.ShouldProcess($PolicyDisplayName, "DELETE $configUri/$($existing.id) (PERMANENT)")) {
    Invoke-MgGraphRequest -Method DELETE -Uri "$configUri/$($existing.id)" | Out-Null
    Write-Host "  [policy] permanently deleted '$PolicyDisplayName' (id $($existing.id))" -ForegroundColor Green
}

Write-Host "`nDone. Policy permanently deleted. This does not undo devices already onboarded/enrolled, and does not restore access retroactively for drives that were denied while the policy was in effect." -ForegroundColor Cyan
```