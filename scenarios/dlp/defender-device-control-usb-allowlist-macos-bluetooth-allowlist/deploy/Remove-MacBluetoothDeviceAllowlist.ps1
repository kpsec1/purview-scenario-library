#Requires -Version 7.0
<#
.SYNOPSIS
    Removes the approved Bluetooth device exception this fragment added, reverting the
    Deny-AllBluetoothDevices rule (owned by defender-device-control-usb-allowlist-macos-portable-
    device-coverage) to unconditional deny with no exceptions.

.DESCRIPTION
    Surgical rollback for scenarios/dlp/defender-device-control-usb-allowlist-macos-bluetooth-
    allowlist: removes the ApprovedBluetoothDevices parent group, every per-device sub-group this
    fragment's deploy/Add-MacBluetoothDeviceAllowlist.ps1 added (identified by the
    "BluetoothVendorProductMatch-" name prefix, since sub-group ids are deterministically derived
    from config at deploy time and this script has no config to re-derive them from), and the
    Allow-ApprovedBluetoothDevice rule, and strips excludeGroups from the Deny-AllBluetoothDevices
    rule - the parent group/rule by fixed GUID, the same identification the deploy and validate
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
$script:SubGroupNamePrefix       = 'BluetoothVendorProductMatch-'

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
$existingSubGroupIds = @($parsedPolicy.groups | Where-Object { $_.name -like "$($script:SubGroupNamePrefix)*" } | ForEach-Object { $_.id })

if ($script:ApprovedBluetoothGroupId -notin $existingGroupIds -and $existingSubGroupIds.Count -eq 0 -and -not $denyBluetoothRule.excludeGroups) {
    Write-Host "No Bluetooth device allowlist currently present on '$ParentPolicyDisplayName' - nothing to remove." -ForegroundColor Yellow
    return
}

$keptGroups = @($parsedPolicy.groups | Where-Object { $_.id -ne $script:ApprovedBluetoothGroupId -and $_.id -notin $existingSubGroupIds })
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

Write-Host "  [plan] $($parsedPolicy.groups.Count) existing groups / $($parsedPolicy.rules.Count) existing rules -> $($keptGroups.Count) groups / $($desiredRules.Count) rules after removing the Bluetooth device allowlist ($($existingSubGroupIds.Count) device sub-group(s) removed)." -ForegroundColor DarkCyan

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
