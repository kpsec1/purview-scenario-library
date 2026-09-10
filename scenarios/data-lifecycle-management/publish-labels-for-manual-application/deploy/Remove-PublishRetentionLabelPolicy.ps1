#Requires -Version 7.0
<#
.SYNOPSIS
    Rolls back the publish label policy: disables (and optionally deletes) the policy/rule that
    makes the label available for manual application. The retention LABEL itself is never touched.

.DESCRIPTION
    Uses Security & Compliance PowerShell. Staged:
      Default    Disable the publish policy (Set-RetentionCompliancePolicy -Enabled $false) so
                 admins/users stop seeing the label as an option to apply going forward.
      -Delete    Additionally delete the policy (Remove-RetentionCompliancePolicy) and its rule.

    This script NEVER touches the retention label (no Remove-ComplianceTag call at all - unlike
    the auto-apply sibling's rollback script, this one has no -TryRemoveLabel option, because
    unpublishing is never a reason to consider deleting a label other scenarios or policies may
    still depend on). Content already manually labeled by a user keeps its label and retention -
    unpublishing only stops new manual applications; it never removes an existing label from
    content. For a record or regulatory record label, removing an already-applied label is
    further restricted or impossible regardless (see rollback.md).

    -WhatIf is non-functional in Security & Compliance PowerShell, so this script implements
    -DryRun. Connect first with Connect-IPPSSession.

.PARAMETER ConfigPath
    Path to the same JSON config used to deploy. Defaults to
    'config/publish-financial-records-label.sample.json'. Only policy.name is read here.

.PARAMETER Delete
    Delete the publish policy and rule (not just disable).

.PARAMETER DryRun
    Print the intended cmdlets and run none.

.EXAMPLE
    Connect-IPPSSession -AppId $AppId -Certificate $Cert -Organization 'contoso.onmicrosoft.com'
    ./Remove-PublishRetentionLabelPolicy.ps1 -DryRun

.NOTES
    Grounded in Microsoft Learn: Set-/Remove-RetentionCompliancePolicy; "Updating retention labels
    and their policies" / "Locking the policy to prevent changes" sections of
    https://learn.microsoft.com/purview/create-apply-retention-labels
#>
[CmdletBinding()]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$ConfigPath = (Join-Path $PSScriptRoot 'config/publish-financial-records-label.sample.json'),

    [Parameter()]
    [switch]$Delete,

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
    Write-Host "  [disable] policy '$($cfg.policy.name)' disabled (stops NEW manual applications)." -ForegroundColor Yellow
    if ($Delete) {
        Invoke-Scc -Describe "Remove-RetentionCompliancePolicy -Identity '$($cfg.policy.name)'" `
            -Action { Remove-RetentionCompliancePolicy -Identity $cfg.policy.name -Confirm:$false }
        Write-Host "  [delete] policy '$($cfg.policy.name)' removed (rule removed with it)." -ForegroundColor Red
    }
}
else { Write-Host "  [policy] '$($cfg.policy.name)' not found." -ForegroundColor DarkGray }

Write-Host "`nDone." -ForegroundColor Cyan
Write-Host "Content already labeled by a user keeps its label and retention - disabling/deleting the publish policy only stops FUTURE manual applications. The retention label itself was never touched by this script. See rollback.md." -ForegroundColor Yellow
