#Requires -Version 7.0
<#
.SYNOPSIS
    Removes Microsoft Purview Audit (Premium) audit-log retention policies defined in the config, via
    Security & Compliance PowerShell. Safe-by-default: reports what it would remove unless -Confirm.

.DESCRIPTION
    For each policy Name in the config, locates it (Get-UnifiedAuditLogRetentionPolicy matched by .Name -
    the cmdlet has no -Identity and does not return the built-in default policy) and removes it with
    Remove-UnifiedAuditLogRetentionPolicy. -WhatIf is non-functional in Security & Compliance PowerShell,
    so this script implements its own -DryRun.

    Removing a retention policy makes future audit records for its scope fall back to the built-in
    DEFAULT policy (Entra/Exchange/OneDrive/SharePoint = 1 year; else 180 days). It does NOT delete
    audit records already retained, and it does not shorten records already captured. Deletion can take
    up to 30 minutes to take effect.

    Connect first: Connect-IPPSSession. Requires the Organization Configuration role.

.PARAMETER ConfigPath
    Path to the JSON config. Defaults to 'config/audit-retention-policies.sample.json'.

.PARAMETER DryRun
    Print the Remove cmdlets that would run and invoke none.

.PARAMETER Force
    Pass -ForceDeletion to Remove-UnifiedAuditLogRetentionPolicy (skip the interactive removal prompt).

.EXAMPLE
    Connect-IPPSSession -AppId $AppId -Certificate $Cert -Organization 'contoso.onmicrosoft.com'
    ./Remove-AuditRetentionPolicy.ps1 -DryRun
    ./Remove-AuditRetentionPolicy.ps1            # removes the config's policies

.NOTES
    Grounded in Microsoft Learn (verify before production use):
    - Remove-UnifiedAuditLogRetentionPolicy (-Identity accepts Name/DN/GUID; -ForceDeletion; -Confirm):
      https://learn.microsoft.com/powershell/module/exchangepowershell/remove-unifiedauditlogretentionpolicy
    - Manage audit log retention policies (default fallback, ~30-min delete latency):
      https://learn.microsoft.com/purview/audit-log-retention-policies
#>
[CmdletBinding()]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$ConfigPath = (Join-Path $PSScriptRoot 'config/audit-retention-policies.sample.json'),

    [Parameter()]
    [switch]$DryRun,

    [Parameter()]
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

function Assert-SccConnected {
    if (-not (Get-Command Get-UnifiedAuditLogRetentionPolicy -ErrorAction SilentlyContinue)) {
        throw "Audit retention cmdlets not found. Connect first: Connect-IPPSSession. See docs/automation-surface.md Section 3."
    }
}
function Invoke-Scc {
    param([Parameter(Mandatory)][string]$Describe, [Parameter(Mandatory)][scriptblock]$Action)
    if ($DryRun) { Write-Host "  DRYRUN would run: $Describe" -ForegroundColor DarkYellow; return $null }
    Write-Host "  $Describe" -ForegroundColor Green
    return & $Action
}

if (-not (Test-Path -LiteralPath $ConfigPath)) { throw "Config file not found: $ConfigPath" }
$cfg = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
if (-not $cfg.policies -or @($cfg.policies).Count -eq 0) { throw "Config has no 'policies'." }

Assert-SccConnected
Write-Host "Removing audit-log retention policies from config (fallback to the built-in default policy for their scope)." -ForegroundColor Cyan
$existing = @(Get-UnifiedAuditLogRetentionPolicy -ErrorAction SilentlyContinue)

foreach ($p in $cfg.policies) {
    if (-not $p.name) { continue }
    if (-not ($existing | Where-Object { $_.Name -eq $p.name })) {
        Write-Host "  [policy] not found '$($p.name)' - nothing to remove." -ForegroundColor DarkGray
        continue
    }
    $desc = "Remove-UnifiedAuditLogRetentionPolicy -Identity '$($p.name)'$(if ($Force) { ' -ForceDeletion' })"
    Invoke-Scc -Describe $desc -Action {
        if ($Force) { Remove-UnifiedAuditLogRetentionPolicy -Identity $p.name -ForceDeletion -Confirm:$false }
        else { Remove-UnifiedAuditLogRetentionPolicy -Identity $p.name -Confirm:$false }
    } | Out-Null
    Write-Host "  [policy] removed '$($p.name)'" -ForegroundColor Green
}

Write-Host "`nDone. Deletion can take up to 30 minutes. Records already retained are unaffected; future records for these scopes follow the default policy." -ForegroundColor Yellow
