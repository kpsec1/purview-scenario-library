#Requires -Version 7.0
<#
.SYNOPSIS
    Rolls back the "Confidentiality - Auto-Label PII in Exchange Email" auto-labeling policy:
    disables it (default) or permanently deletes it (and its rule).

.DESCRIPTION
    Uses Security & Compliance PowerShell. Staged:
      Default   Disable the policy (Set-AutoSensitivityLabelPolicy -Mode Disable) so it stops
                labeling mail in transit. Reversible in seconds (-Mode Enable). No history lost.
      -Purge    Permanently delete the policy AND its rule (Remove-AutoSensitivityLabelPolicy
                removes the rule with it). NOT reversible - re-deploying requires re-running
                New-ConfidentialExchangeAutoLabelPolicy.ps1.

    What rollback does NOT undo: labels (and any encryption the label applies) already stamped on
    email that flowed while the policy was enabled - those stay on the messages; disabling/deleting
    only stops FUTURE labeling. See rollback.md.

    Idempotent: if the policy doesn't exist, the script reports it and exits cleanly.

    -WhatIf is non-functional in Security & Compliance PowerShell, so this script implements -DryRun.
    Connect first with Connect-IPPSSession (this script does not open the session).

.PARAMETER ConfigPath
    Path to the same JSON config used to deploy. Defaults to
    'config/auto-label-confidential-exchange.sample.json'. Only policy.name is read here.

.PARAMETER Purge
    Permanently delete the policy and its rule instead of disabling. See rollback.md for the
    recommended disable-first, purge-later sequence.

.PARAMETER DryRun
    Print the intended cmdlets and run none.

.EXAMPLE
    Connect-IPPSSession -AppId $AppId -Certificate $Cert -Organization 'contoso.onmicrosoft.com'
    ./Remove-ConfidentialExchangeAutoLabelPolicy.ps1 -DryRun

.EXAMPLE
    ./Remove-ConfidentialExchangeAutoLabelPolicy.ps1
    # Disables the policy (soft rollback).

.EXAMPLE
    ./Remove-ConfidentialExchangeAutoLabelPolicy.ps1 -Purge
    # Permanently deletes the policy and its rule.

.NOTES
    Sources: https://learn.microsoft.com/powershell/module/exchangepowershell/set-autosensitivitylabelpolicy
             https://learn.microsoft.com/powershell/module/exchangepowershell/remove-autosensitivitylabelpolicy
#>
[CmdletBinding()]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$ConfigPath = (Join-Path $PSScriptRoot 'config/auto-label-confidential-exchange.sample.json'),

    [Parameter()]
    [switch]$Purge,

    [Parameter()]
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
if (-not (Get-Command Get-AutoSensitivityLabelPolicy -ErrorAction SilentlyContinue)) {
    throw "Auto-labeling cmdlets not found. Connect first: Connect-IPPSSession. See docs/automation-surface.md Section 3."
}
if (-not (Test-Path -LiteralPath $ConfigPath)) { throw "Config file not found: $ConfigPath" }
$cfg = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
if (-not $cfg.policy.name) { throw "policy.name is required." }
$policyName = $cfg.policy.name

function Invoke-Scc {
    param([string]$Describe, [scriptblock]$Action)
    if ($DryRun) { Write-Host "  DRYRUN would run: $Describe" -ForegroundColor DarkYellow; return }
    Write-Host "  $Describe" -ForegroundColor Green
    & $Action
}

$policy = Get-AutoSensitivityLabelPolicy -Identity $policyName -ErrorAction SilentlyContinue
if (-not $policy) {
    Write-Host "  [policy] '$policyName' not found. Nothing to roll back." -ForegroundColor DarkGray
    return
}

if ($Purge) {
    Invoke-Scc -Describe "Remove-AutoSensitivityLabelPolicy -Identity '$policyName' (permanent, also removes its rule)" `
        -Action { Remove-AutoSensitivityLabelPolicy -Identity $policyName -Confirm:$false }
    Write-Host "  [purge] policy '$policyName' and its rule removed. Labels already applied to sent/received mail are NOT removed." -ForegroundColor Red
}
else {
    Invoke-Scc -Describe "Set-AutoSensitivityLabelPolicy -Identity '$policyName' -Mode Disable" `
        -Action { Set-AutoSensitivityLabelPolicy -Identity $policyName -Mode Disable -Confirm:$false }
    Write-Host "  [disable] policy '$policyName' disabled. Re-enable with: Set-AutoSensitivityLabelPolicy -Identity '$policyName' -Mode Enable" -ForegroundColor Yellow
}

Write-Host "`nDone. Disabling/deleting only stops FUTURE labeling of mail in transit - it does not strip labels or encryption from messages already processed. See rollback.md." -ForegroundColor Cyan
