#Requires -Version 7.0
<#
.SYNOPSIS
    Rolls back the code-of-conduct supervisory-review policy created by New-CodeOfConductPolicy.ps1:
    disables it (default) or deletes it (-Delete).

.DESCRIPTION
    Uses the Security & Compliance PowerShell SupervisoryReview cmdlets. Two staged levels:
      Default    Disable the policy (Set-SupervisoryReviewPolicyV2 -Enabled $false) - reversible,
                 keeps the policy, rule, and its captured-review history.
      -Delete    Remove the policy entirely (Remove-SupervisoryReviewPolicyV2). Not reversible.

    Locates the policy by the name in the config file. -WhatIf is non-functional in Security &
    Compliance PowerShell, so this script implements its own -DryRun.

    This does NOT undo the trainable-classifier configuration or location selection made in the
    portal - if the policy is deleted those go with it, but if you only disable, review the portal
    policy state too. Author-only reference code; connect first with Connect-IPPSSession.

.PARAMETER ConfigPath
    Path to the same JSON config used to deploy. Defaults to 'config/code-of-conduct.sample.json'.
    Only policyName is read here.

.PARAMETER Delete
    Delete the policy instead of just disabling it.

.PARAMETER DryRun
    Print the mutating cmdlet that would run and invoke none.

.EXAMPLE
    Connect-IPPSSession -AppId $AppId -Certificate $Cert -Organization 'contoso.onmicrosoft.com'
    ./Remove-CodeOfConductPolicy.ps1 -DryRun

.EXAMPLE
    Connect-IPPSSession -AppId $AppId -Certificate $Cert -Organization 'contoso.onmicrosoft.com'
    ./Remove-CodeOfConductPolicy.ps1 -Delete

.NOTES
    Grounded in Microsoft Learn:
    - Remove-/Set-/Get-SupervisoryReviewPolicyV2 (SCC PowerShell):
      https://learn.microsoft.com/powershell/module/exchangepowershell/remove-supervisoryreviewpolicyv2
#>
[CmdletBinding()]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$ConfigPath = (Join-Path $PSScriptRoot 'config/code-of-conduct.sample.json'),

    [Parameter()]
    [switch]$Delete,

    [Parameter()]
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

if (-not (Get-Command Get-SupervisoryReviewPolicyV2 -ErrorAction SilentlyContinue)) {
    throw "SupervisoryReview cmdlets not found. Connect first: Connect-IPPSSession. See docs/automation-surface.md Section 3."
}
if (-not (Test-Path -LiteralPath $ConfigPath)) { throw "Config file not found: $ConfigPath" }
$cfg = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
if (-not $cfg.policyName) { throw "Config is missing 'policyName'." }
$policyName = $cfg.policyName

$existing = Get-SupervisoryReviewPolicyV2 -Identity $policyName -ErrorAction SilentlyContinue
if (-not $existing) {
    Write-Host "Policy '$policyName' not found (already removed?). Nothing to do." -ForegroundColor DarkGray
    return
}

if ($Delete) {
    if ($DryRun) {
        Write-Host "DRYRUN would run: Remove-SupervisoryReviewPolicyV2 -Identity '$policyName'" -ForegroundColor DarkYellow
    }
    else {
        Remove-SupervisoryReviewPolicyV2 -Identity $policyName -Confirm:$false
        Write-Host "[delete] Policy '$policyName' removed." -ForegroundColor Red
    }
}
else {
    if ($DryRun) {
        Write-Host "DRYRUN would run: Set-SupervisoryReviewPolicyV2 -Identity '$policyName' -Enabled `$false" -ForegroundColor DarkYellow
    }
    else {
        Set-SupervisoryReviewPolicyV2 -Identity $policyName -Enabled $false -Confirm:$false
        Write-Host "[disable] Policy '$policyName' disabled (reversible - re-run New-CodeOfConductPolicy.ps1 to re-enable)." -ForegroundColor Yellow
    }
}

Write-Host "`nDone." -ForegroundColor Cyan
Write-Host "Note: captured review items/history and any portal-side classifier configuration are not separately cleaned up here (see rollback.md)." -ForegroundColor Yellow
