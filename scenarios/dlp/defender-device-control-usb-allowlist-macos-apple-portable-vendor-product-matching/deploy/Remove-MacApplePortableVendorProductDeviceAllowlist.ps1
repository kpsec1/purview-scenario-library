#Requires -Version 7.0
<#
.SYNOPSIS
    Removes every Apple/Portable vendorId/productId compound-matched device exception this fragment
    added, reverting "ApprovedAppleDevices"/"ApprovedPortableDevices" to serialNumber-only matching.

.DESCRIPTION
    Surgical rollback for
    scenarios/dlp/defender-device-control-usb-allowlist-macos-apple-portable-vendor-product-matching:
    removes every "AppleVendorProductMatch-*"/"PortableVendorProductMatch-*" sub-group this
    fragment's deploy/Add-MacApplePortableVendorProductDeviceAllowlist.ps1 added, and strips every
    "groupId" clause it added from "ApprovedAppleDevices"'s and "ApprovedPortableDevices"'s
    query.clauses arrays - by name prefix, the same identification the deploy and validate scripts
    use.

    This does NOT touch either group's serialNumber-based entries, the AllAppleDevices/
    AllPortableDevices catch-all groups, any Allow/Deny rule, the removable-media or Bluetooth
    sibling fragments' own groups and rules, the assignment, or the policy object's identity - only
    this fragment's own additions are removed. An Apple/Portable device approved only by
    vendorId/productId reverts to DENIED (the OR-branch it matched no longer exists); any device also
    matched by a still-present serialNumber clause is unaffected.

    If a family's ApprovedAppleDevices/ApprovedPortableDevices group is not present at all (never
    configured, or removed by the known cross-fragment ordering hazard - README.md Section 11), that
    family is reported as "nothing to remove" and skipped; the other family is still processed.

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
    ./Remove-MacApplePortableVendorProductDeviceAllowlist.ps1 -WhatIf

.EXAMPLE
    ./Remove-MacApplePortableVendorProductDeviceAllowlist.ps1
    # Strips every Apple/Portable vendorId/productId device exception back out of both families.

.NOTES
    Sources: same as deploy/Add-MacApplePortableVendorProductDeviceAllowlist.ps1's .NOTES block.
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

$script:Families = @(
    [ordered]@{ Key = 'apple';    ApprovedGroupId = 'd1d2d3d4-1111-4a1a-8a1a-111111111102'; ApprovedGroupName = 'ApprovedAppleDevices';    NamePrefix = 'AppleVendorProductMatch-' }
    [ordered]@{ Key = 'portable'; ApprovedGroupId = 'd1d2d3d4-2222-4b2b-8b2b-222222222202'; ApprovedGroupName = 'ApprovedPortableDevices'; NamePrefix = 'PortableVendorProductMatch-' }
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

$anyOwnedGroup = $false
foreach ($family in $script:Families) {
    $approvedGroup = $parsedPolicy.groups | Where-Object { $_.id -eq $family.ApprovedGroupId } | Select-Object -First 1
    if (-not $approvedGroup) {
        Write-Host "$($family.ApprovedGroupName) not found on '$ParentPolicyDisplayName' - nothing for this fragment to remove for the $($family.Key) family." -ForegroundColor Yellow
        continue
    }
    $ownedGroups = @($parsedPolicy.groups | Where-Object { $_.name -like "$($family.NamePrefix)*" })
    $groupIdClauseCount = @($approvedGroup.query.clauses | Where-Object { $_.'$type' -eq 'groupId' }).Count
    if ($ownedGroups.Count -eq 0 -and $groupIdClauseCount -eq 0) {
        Write-Host "No $($family.Key) vendorId/productId device allowlist currently present on '$ParentPolicyDisplayName' - nothing to remove for this family." -ForegroundColor Yellow
        continue
    }
    $anyOwnedGroup = $true
    foreach ($g in $ownedGroups) {
        Write-Host "  [plan] Removing $($family.Key) device: '$($g.name.Substring($family.NamePrefix.Length))'." -ForegroundColor DarkCyan
    }
}

if (-not $anyOwnedGroup) {
    Write-Host "`nDone. No change made." -ForegroundColor Cyan
    return
}

$allNamePrefixes = @($script:Families | ForEach-Object { $_.NamePrefix })

$newGroupsList = New-Object System.Collections.Generic.List[object]
foreach ($g in $parsedPolicy.groups) {
    $matchedFamily = $script:Families | Where-Object { $g.id -eq $_.ApprovedGroupId } | Select-Object -First 1
    if ($matchedFamily) {
        $revertedClauses = @($g.query.clauses | Where-Object { $_.'$type' -ne 'groupId' })
        $newGroupsList.Add([ordered]@{
            '$type' = 'device'
            id      = $g.id
            name    = $g.name
            query   = [ordered]@{ '$type' = $g.query.'$type'; clauses = @($revertedClauses) }
        })
        Write-Host "  [plan] $($matchedFamily.ApprovedGroupName) reverts to $($revertedClauses.Count) serialNumber clause(s) only." -ForegroundColor DarkCyan
        continue
    }
    $isOwnedSubGroup = $false
    foreach ($prefix in $allNamePrefixes) {
        if ($g.name -like "$prefix*") { $isOwnedSubGroup = $true; break }
    }
    if ($isOwnedSubGroup) { continue }  # this fragment's own per-device sub-group - dropped, not kept
    $newGroupsList.Add($g)
}

$desiredPolicy = [ordered]@{ groups = @($newGroupsList); rules = $parsedPolicy.rules; settings = $parsedPolicy.settings }
$newPolicyJson = $desiredPolicy | ConvertTo-Json -Depth 12 -Compress
$newEscapedJson = ConvertTo-XmlEscaped $newPolicyJson

Write-Host "  [plan] $($parsedPolicy.groups.Count) existing groups -> $($newGroupsList.Count) groups after removing the Apple/Portable vendorId/productId device allowlist." -ForegroundColor DarkCyan

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

if ($PSCmdlet.ShouldProcess($ParentPolicyDisplayName, "PATCH $configUri/$($parent.id) (remove Apple/Portable vendorId/productId device allowlist)")) {
    Invoke-MgGraphRequest -Method PATCH -Uri "$configUri/$($parent.id)" -Body ($body | ConvertTo-Json -Depth 12) | Out-Null
    Write-Host "  [coverage] Apple/Portable vendorId/productId device allowlist removed from '$ParentPolicyDisplayName' (id $($parent.id))" -ForegroundColor Green
}

Write-Host "`nDone. Devices that were approved only by vendorId/productId revert to DENIED, not to unrestricted - see rollback.md. Any device also matched by a still-present serialNumber clause is unaffected." -ForegroundColor Cyan
