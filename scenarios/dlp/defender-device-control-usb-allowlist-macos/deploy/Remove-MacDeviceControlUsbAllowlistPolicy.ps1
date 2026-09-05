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
