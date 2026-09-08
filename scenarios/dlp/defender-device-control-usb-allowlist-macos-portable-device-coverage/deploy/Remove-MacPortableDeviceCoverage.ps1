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
