#Requires -Version 7.0
<#
.SYNOPSIS
    Rolls back the financial-records retention deployment: disables (and optionally deletes) the
    auto-apply policy/rule. The regulatory record LABEL itself is intentionally not force-removed.

.DESCRIPTION
    Uses Security & Compliance PowerShell. Staged:
      Default    Disable the auto-apply policy (Set-RetentionCompliancePolicy -Enabled $false) so it
                 stops stamping the label on NEW content. Content already labeled keeps its label and
                 retention (regulatory records are immutable).
      -Delete    Additionally delete the policy (Remove-RetentionCompliancePolicy) and its rule.

    The retention LABEL is NOT deleted by this script. A regulatory record label that has been applied
    to content CANNOT be deleted, and its retention can't be shortened - that is the whole point of a
    regulatory record (SEC 17a-4 immutability). Removing the policy stops future auto-labeling; it
    does NOT release existing records. This is by design, not a limitation to work around.

    -WhatIf is non-functional in Security & Compliance PowerShell, so this script implements -DryRun.
    Connect first with Connect-IPPSSession.

.PARAMETER ConfigPath
    Path to the same JSON config used to deploy. Defaults to 'config/financial-records-retention.sample.json'.
    Only policy.name (and, with -TryRemoveLabel, label.name) are read here.

.PARAMETER Delete
    Delete the auto-apply policy and rule (not just disable).

.PARAMETER TryRemoveLabel
    Attempt to remove the retention label too (Remove-ComplianceTag). This SUCCEEDS only if the label
    was never applied and isn't a published/regulatory record in use; otherwise the service refuses,
    which this script reports rather than forcing.

.PARAMETER DryRun
    Print the intended cmdlets and run none.

.EXAMPLE
    Connect-IPPSSession -AppId $AppId -Certificate $Cert -Organization 'contoso.onmicrosoft.com'
    ./Remove-FinancialRecordsRetention.ps1 -DryRun

.NOTES
    Grounded in Microsoft Learn: Set-/Remove-RetentionCompliancePolicy, Remove-ComplianceTag; records
    management immutability. https://learn.microsoft.com/purview/records-management
#>
[CmdletBinding()]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$ConfigPath = (Join-Path $PSScriptRoot 'config/financial-records-retention.sample.json'),

    [Parameter()]
    [switch]$Delete,

    [Parameter()]
    [switch]$TryRemoveLabel,

    [Parameter()]
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
if (-not (Get-Command Get-RetentionCompliancePolicy -ErrorAction SilentlyContinue)) {
    throw "Retention cmdlets not found. Connect first: Connect-IPPSSession. See docs/automation-surface.md Section 3."
}
if (-not (Test-Path -LiteralPath $ConfigPath)) { throw "Config file not found: $ConfigPath" }
$cfg = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
if (-not $cfg.policy.name) { throw "policy.name is required." }

function Invoke-Scc {
    param([string]$Describe, [scriptblock]$Action)
    if ($DryRun) { Write-Host "  DRYRUN would run: $Describe" -ForegroundColor DarkYellow; return }
    Write-Host "  $Describe" -ForegroundColor Green
    & $Action
}

$policy = Get-RetentionCompliancePolicy -Identity $cfg.policy.name -ErrorAction SilentlyContinue
if ($policy) {
    Invoke-Scc -Describe "Set-RetentionCompliancePolicy -Identity '$($cfg.policy.name)' -Enabled `$false" `
        -Action { Set-RetentionCompliancePolicy -Identity $cfg.policy.name -Enabled $false -Confirm:$false }
    Write-Host "  [disable] policy '$($cfg.policy.name)' disabled (stops NEW auto-labeling)." -ForegroundColor Yellow
    if ($Delete) {
        Invoke-Scc -Describe "Remove-RetentionCompliancePolicy -Identity '$($cfg.policy.name)'" `
            -Action { Remove-RetentionCompliancePolicy -Identity $cfg.policy.name -Confirm:$false }
        Write-Host "  [delete] policy '$($cfg.policy.name)' removed (rule removed with it)." -ForegroundColor Red
    }
}
else { Write-Host "  [policy] '$($cfg.policy.name)' not found." -ForegroundColor DarkGray }

if ($TryRemoveLabel -and $cfg.label.name) {
    if ($DryRun) {
        Write-Host "  DRYRUN would run: Remove-ComplianceTag -Identity '$($cfg.label.name)'" -ForegroundColor DarkYellow
    }
    else {
        try {
            Remove-ComplianceTag -Identity $cfg.label.name -Confirm:$false
            Write-Host "  [delete] label '$($cfg.label.name)' removed (was not in use)." -ForegroundColor Red
        }
        catch {
            Write-Warning "  Could not remove label '$($cfg.label.name)': $($_.Exception.Message). This is expected for a regulatory record label that has been applied - such labels are immutable and cannot be deleted while records exist. See rollback.md."
        }
    }
}

Write-Host "`nDone." -ForegroundColor Cyan
Write-Host "Existing labeled content keeps its retention (regulatory records are immutable) - disabling/deleting the policy only stops FUTURE auto-labeling. See rollback.md." -ForegroundColor Yellow
