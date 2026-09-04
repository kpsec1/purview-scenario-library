#Requires -Version 7.0
<#
.SYNOPSIS
    Verifies (read-only) that the audit-log retention policies in the config exist with the expected
    priority and retention duration.

.DESCRIPTION
    Read-only - issues only Get-UnifiedAuditLogRetentionPolicy, never modifies anything. For each policy
    in the config, matches by Name (the cmdlet has no -Identity and does not return the built-in default
    policy) and checks RetentionDuration and Priority. Exits non-zero on any hard failure. Safe to
    re-run.

    Connect first: Connect-IPPSSession. A role that can read audit retention configuration is sufficient.

.PARAMETER ConfigPath
    Path to the config to validate against. Defaults to
    '../deploy/config/audit-retention-policies.sample.json'.

.EXAMPLE
    Connect-IPPSSession -AppId $AppId -Certificate $Cert -Organization 'contoso.onmicrosoft.com'
    ./Test-AuditRetentionPolicy.ps1
#>
[CmdletBinding()]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$ConfigPath = (Join-Path $PSScriptRoot '../deploy/config/audit-retention-policies.sample.json')
)

$ErrorActionPreference = 'Stop'
$script:failures = 0
function Test-Check {
    param([string]$Description, [bool]$Condition, [switch]$Warn)
    if ($Condition) { Write-Host "  [PASS] $Description" -ForegroundColor Green }
    elseif ($Warn) { Write-Host "  [WARN] $Description" -ForegroundColor Yellow }
    else { Write-Host "  [FAIL] $Description" -ForegroundColor Red; $script:failures++ }
}

if (-not (Get-Command Get-UnifiedAuditLogRetentionPolicy -ErrorAction SilentlyContinue)) {
    throw "Audit retention cmdlets not found. Connect first: Connect-IPPSSession. See docs/automation-surface.md Section 3."
}
if (-not (Test-Path -LiteralPath $ConfigPath)) { throw "Config file not found: $ConfigPath" }
$cfg = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json

Write-Host "Validating $(@($cfg.policies).Count) audit-log retention policy(ies)..." -ForegroundColor Cyan
$all = @(Get-UnifiedAuditLogRetentionPolicy -ErrorAction SilentlyContinue)
Write-Host "  ($($all.Count) custom retention policy(ies) found in tenant; the built-in default policy is not listed.)" -ForegroundColor DarkCyan

foreach ($p in $cfg.policies) {
    $live = $all | Where-Object { $_.Name -eq $p.name } | Select-Object -First 1
    Test-Check -Description "Policy '$($p.name)' exists" -Condition ($null -ne $live)
    if ($live) {
        Test-Check -Description "  RetentionDuration is '$($p.retentionDuration)' (current: $($live.RetentionDuration))" `
            -Condition ("$($live.RetentionDuration)" -eq "$($p.retentionDuration)")
        Test-Check -Description "  Priority is $($p.priority) (current: $($live.Priority))" `
            -Condition ("$($live.Priority)" -eq "$($p.priority)") -Warn
    }
}

Write-Host "$(if ($script:failures -eq 0) { 'All hard checks passed.' } else { "$script:failures hard check(s) failed." })" `
    -ForegroundColor $(if ($script:failures -eq 0) { 'Green' } else { 'Red' })
if ($script:failures -gt 0) { exit 1 }
