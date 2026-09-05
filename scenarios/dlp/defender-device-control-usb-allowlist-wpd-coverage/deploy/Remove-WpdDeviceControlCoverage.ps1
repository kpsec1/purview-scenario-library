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
