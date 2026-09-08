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
