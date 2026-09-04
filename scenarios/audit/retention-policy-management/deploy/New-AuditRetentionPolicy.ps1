#Requires -Version 7.0
<#
.SYNOPSIS
    Creates Microsoft Purview Audit (Premium) audit-log retention policies as code - setting how long
    audit records are kept, scoped by record type / operation / user, with a priority - via Security &
    Compliance PowerShell.

.DESCRIPTION
    Configuration counterpart to the read-only investigation scenario ../../premium-audit-investigation/:
    that one QUERIES the audit log; this one CONFIGURES how long records are retained before they age
    out. Uses New-UnifiedAuditLogRetentionPolicy (automation surface 1 per docs/automation-surface.md).

    For each policy in the config:
      - Located by Name via Get-UnifiedAuditLogRetentionPolicy (which takes filters, not -Identity, and
        does NOT return the built-in default policy) - matched client-side by .Name.
      - Created if absent; if present it is REPORTED, not silently mutated (retention scope is
        high-consequence - change duration/priority deliberately with Set-UnifiedAuditLogRetentionPolicy).

    Custom retention policies take precedence over the built-in default policy (Entra/Exchange/OneDrive/
    SharePoint = 1 year, everything else = 180 days), which cannot be modified and is not returned by
    Get. Priority (1-10000, lower = higher precedence) breaks ties when multiple custom policies match
    the same record. -WhatIf is non-functional in Security & Compliance PowerShell, so this script
    implements its own -DryRun.

    Connect first: Connect-IPPSSession (certificate app-only preferred - docs/automation-surface.md
    Section 3). Requires the Organization Configuration role. This script does not open the session.

.PARAMETER ConfigPath
    Path to the JSON config. Defaults to 'config/audit-retention-policies.sample.json'.

.PARAMETER DryRun
    Print every mutating cmdlet that would run and invoke none (the working substitute for -WhatIf).

.EXAMPLE
    Connect-IPPSSession -AppId $AppId -Certificate $Cert -Organization 'contoso.onmicrosoft.com'
    ./New-AuditRetentionPolicy.ps1 -DryRun

.NOTES
    Grounded in Microsoft Learn (verify before production use):
    - New-UnifiedAuditLogRetentionPolicy (-Name, -Priority [1-10000, mandatory], -RetentionDuration
      [ThreeMonths|SixMonths|NineMonths|TwelveMonths|TenYears, mandatory], -Description, -Operations,
      -RecordTypes, -UserIds): https://learn.microsoft.com/powershell/module/exchangepowershell/new-unifiedauditlogretentionpolicy
    - Get-/Set-/Remove-UnifiedAuditLogRetentionPolicy:
      https://learn.microsoft.com/powershell/module/exchangepowershell/get-unifiedauditlogretentionpolicy
    - Manage audit log retention policies (default policy, 50-policy limit, priority, 10-year add-on):
      https://learn.microsoft.com/purview/audit-log-retention-policies

    VERIFY (README.md Section 11): the Purview portal exposes more duration choices than the cmdlet's
    documented 5-value -RetentionDuration enum; if you need a duration not in the enum, set it in the
    portal and confirm the cmdlet round-trips it. This script only emits the confirmed enum values.
#>
[CmdletBinding()]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$ConfigPath = (Join-Path $PSScriptRoot 'config/audit-retention-policies.sample.json'),

    [Parameter()]
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
$validDurations = 'ThreeMonths', 'SixMonths', 'NineMonths', 'TwelveMonths', 'TenYears'

function Assert-SccConnected {
    if (-not (Get-Command Get-UnifiedAuditLogRetentionPolicy -ErrorAction SilentlyContinue)) {
        throw "Audit retention cmdlets not found. Connect first: Connect-IPPSSession (Security & Compliance PowerShell). See docs/automation-surface.md Section 3."
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
Write-Host "Deploying $(@($cfg.policies).Count) audit-log retention policy(ies)." -ForegroundColor Cyan

# Get-UnifiedAuditLogRetentionPolicy has no -Identity; list all and match by Name client-side.
$existing = @(Get-UnifiedAuditLogRetentionPolicy -ErrorAction SilentlyContinue)

foreach ($p in $cfg.policies) {
    if (-not $p.name) { throw "each policy needs a name." }
    if ($null -eq $p.priority) { throw "policy '$($p.name)' needs a priority (1-10000, mandatory)." }
    if ($p.retentionDuration -notin $validDurations) {
        throw "policy '$($p.name)' retentionDuration '$($p.retentionDuration)' is not one of: $($validDurations -join ', '). If you need another value, set it in the portal (README.md Section 11 VERIFY)."
    }

    if ($existing | Where-Object { $_.Name -eq $p.name }) {
        Write-Host "  [policy] exists '$($p.name)' (not modified - change duration/priority deliberately with Set-UnifiedAuditLogRetentionPolicy)." -ForegroundColor DarkGreen
        continue
    }

    $params = @{
        Name              = $p.name
        Priority          = [int]$p.priority
        RetentionDuration = $p.retentionDuration
    }
    if ($p.description) { $params.Description = $p.description }
    if ($p.recordTypes -and @($p.recordTypes).Count -gt 0) { $params.RecordTypes = @($p.recordTypes) }
    if ($p.operations  -and @($p.operations).Count  -gt 0) { $params.Operations  = @($p.operations) }
    if ($p.userIds     -and @($p.userIds).Count     -gt 0) { $params.UserIds     = @($p.userIds) }

    $scope = @()
    if ($params.RecordTypes) { $scope += "RecordTypes=$($params.RecordTypes -join ',')" }
    if ($params.Operations)  { $scope += "Operations=$($params.Operations -join ',')" }
    if ($params.UserIds)     { $scope += "UserIds=$(@($params.UserIds).Count) user(s)" }
    Invoke-Scc -Describe "New-UnifiedAuditLogRetentionPolicy -Name '$($p.name)' -Priority $($p.priority) -RetentionDuration $($p.retentionDuration) [$($scope -join '; ')]" `
        -Action { New-UnifiedAuditLogRetentionPolicy @params -Confirm:$false } | Out-Null
    Write-Host "  [policy] created '$($p.name)'" -ForegroundColor Green
}

Write-Host "`nDone." -ForegroundColor Cyan
Write-Host "Custom policies override the built-in default (Entra/Exchange/OneDrive/SharePoint 1yr; else 180d). Max 50 policies/org. Validate with validate/Test-AuditRetentionPolicy.ps1." -ForegroundColor Yellow
