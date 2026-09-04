#Requires -Modules @{ ModuleName = 'ExchangeOnlineManagement'; ModuleVersion = '3.2.0' }
<#
.SYNOPSIS
    Deletes one or more audit log retention policies created by New-AuditRetentionPolicy.ps1.

.DESCRIPTION
    Wraps Remove-UnifiedAuditLogRetentionPolicy. There is no "disable" or "pause" state for these
    policy objects (Microsoft documents no -Enabled/Mode parameter) - deletion is the only
    lifecycle action beyond create/edit, so this script IS the rollback path, not a staged one.
    See rollback.md and design.md Section 7.

    Deleting a policy does not delete, shorten, or otherwise affect any audit records already
    retained under it - it only stops the policy from governing retention going forward. Affected
    activity reverts to whatever the next-highest-priority matching policy specifies, or the
    tenant's default retention policy if none remains. Microsoft states removal can take up to
    30 minutes to fully apply.

.PARAMETER ConfigPath
    Path to the same JSON config New-AuditRetentionPolicy.ps1 used - every policy named in it is
    a removal candidate. Alternative to -Name.

.PARAMETER Name
    One or more specific policy names to remove. Alternative to -ConfigPath.

.PARAMETER Force
    Passes -ForceDeletion to Remove-UnifiedAuditLogRetentionPolicy (bypasses the cmdlet's own
    confirmation gate for a policy Microsoft flags as still propagating/pending).

.PARAMETER WhatIf
    Reports every deletion this run would perform. Makes no changes.

.EXAMPLE
    ./deploy/Remove-AuditRetentionPolicy.ps1 -ConfigPath ./deploy/config/audit-retention-policies.sample.json -WhatIf

.EXAMPLE
    ./deploy/Remove-AuditRetentionPolicy.ps1 -Name 'ThreeMonth-SharePointSearchNoise'

.NOTES
    Grounded against Remove-UnifiedAuditLogRetentionPolicy (learn.microsoft.com/powershell/module/
    exchangepowershell/remove-unifiedauditlogretentionpolicy) - -Identity/-ForceDeletion/-Confirm/
    -WhatIf parameters, the "up to 30 minutes to fully remove" behavior - and "Manage audit log
    retention policies" (learn.microsoft.com/purview/audit-log-retention-policies), fetched during
    this build, 2026-09-04.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(ParameterSetName = 'FromConfig', Mandatory)]
    [ValidateScript({ Test-Path -Path $_ -PathType Leaf })]
    [string]$ConfigPath,

    [Parameter(ParameterSetName = 'ByName', Mandatory)]
    [string[]]$Name,

    [switch]$Force
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$targets = if ($PSCmdlet.ParameterSetName -eq 'FromConfig') {
    $config = Get-Content -Path $ConfigPath -Raw | ConvertFrom-Json
    @($config.policies | ForEach-Object { $_.name })
}
else {
    $Name
}

if ($targets.Count -eq 0) {
    Write-Warning 'No policy names resolved - nothing to remove.'
    return
}

$livePolicies = @(Get-UnifiedAuditLogRetentionPolicy -ErrorAction Stop)

foreach ($policyName in $targets) {
    $live = $livePolicies | Where-Object { $_.Name -eq $policyName } | Select-Object -First 1
    if (-not $live) {
        Write-Host "[SKIP] '$policyName' does not exist - nothing to remove."
        continue
    }

    if ($PSCmdlet.ShouldProcess($policyName, 'Remove-UnifiedAuditLogRetentionPolicy')) {
        $removeParams = @{ Identity = $policyName; Confirm = $false }
        if ($Force) { $removeParams.ForceDeletion = $true }
        Remove-UnifiedAuditLogRetentionPolicy @removeParams
        Write-Host "[REMOVED] '$policyName' (may take up to 30 minutes to fully clear)."
    }
}
