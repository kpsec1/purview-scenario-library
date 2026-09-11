#Requires -Version 7.0
<#
.SYNOPSIS
    Rolls back the adaptive-scope auto-apply label policy/rule and, optionally, the adaptive scope -
    staged, per rollback.md. Never touches the label definition or content already labeled.

.DESCRIPTION
    Stage 1 (default): Set-RetentionCompliancePolicy -Enabled $false - stops the policy from
    auto-applying the label to any further content. Reversible (re-run the deploy script to
    re-enable). Content already labeled as a record is NOT affected - see "What rollback does not
    undo" in rollback.md.

    Stage 2 (-Delete): Remove-RetentionCompliancePolicy - removes the policy AND its rule in one call
    (Microsoft's own documented behavior). This stops future auto-apply only. It does NOT unlock or
    remove the record label from content already labeled - only a records manager can do that
    (Get-ComplianceTag / the portal's Records Management > File plan, out of scope for this script),
    and only for a plain record; a regulatory record (if one was created via -Delete's label.regulatory
    path having been skipped from auto-apply entirely) can never be removed by anyone.

    Stage 3 (-Delete -TryRemoveScope): also attempts Remove-AdaptiveScope for the adaptive scope. This
    can fail if the scope is still referenced by another policy (including the adaptive-scope-
    retention sibling, if both are deployed to the same tenant sharing one scope by name) - the script
    reports the failure rather than forcing it (-ForceDeletion is available but NOT used by default;
    pass -ForceScopeDeletion to opt in).

    This script never removes the retention label itself (Remove-ComplianceTag) - a record label
    definition, and any content already locked under it, is out of scope for a policy/rule rollback.
    Remove the label definition manually, deliberately, and only after confirming no content still
    carries it.

    Idempotent / safe to re-run: each stage checks current state before acting.

.PARAMETER ConfigPath
    Path to the JSON config. Defaults to 'config/adaptive-scope-auto-apply-label.sample.json'.

.PARAMETER Delete
    Also remove the auto-apply policy (and its rule). Does not touch the label or labeled content.

.PARAMETER TryRemoveScope
    After -Delete, also attempt to remove the adaptive scope (Remove-AdaptiveScope). Reports failure
    rather than forcing it unless -ForceScopeDeletion is also specified.

.PARAMETER ForceScopeDeletion
    Pass -ForceDeletion to Remove-AdaptiveScope. Only meaningful with -Delete -TryRemoveScope.

.PARAMETER DryRun
    Print every mutating cmdlet that would run and invoke none.

.EXAMPLE
    Connect-IPPSSession -AppId $AppId -Certificate $Cert -Organization 'contoso.onmicrosoft.com'
    ./Remove-AdaptiveScopeAutoApplyLabel.ps1 -DryRun

.EXAMPLE
    Connect-IPPSSession -AppId $AppId -Certificate $Cert -Organization 'contoso.onmicrosoft.com'
    ./Remove-AdaptiveScopeAutoApplyLabel.ps1 -Delete

.NOTES
    Grounded in Microsoft Learn (verify before production use):
    - Remove-RetentionCompliancePolicy (removes policy + rule together):
      https://learn.microsoft.com/powershell/module/exchangepowershell/remove-retentioncompliancepolicy
    - Remove-AdaptiveScope (-Identity/-ForceDeletion):
      https://learn.microsoft.com/powershell/module/exchangepowershell/remove-adaptivescope
    - Declare records / regulatory records (record label removal requires records-manager privilege;
      regulatory record cannot be removed by anyone): https://learn.microsoft.com/purview/declare-records
#>
[CmdletBinding()]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$ConfigPath = (Join-Path $PSScriptRoot 'config/adaptive-scope-auto-apply-label.sample.json'),

    [Parameter()]
    [switch]$Delete,

    [Parameter()]
    [switch]$TryRemoveScope,

    [Parameter()]
    [switch]$ForceScopeDeletion,

    [Parameter()]
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

function Invoke-Scc {
    param([Parameter(Mandatory)][string]$Describe, [Parameter(Mandatory)][scriptblock]$Action)
    if ($DryRun) { Write-Host "  DRYRUN would run: $Describe" -ForegroundColor DarkYellow; return $null }
    Write-Host "  $Describe" -ForegroundColor Green
    return & $Action
}

if (-not (Get-Command Get-RetentionCompliancePolicy -ErrorAction SilentlyContinue)) {
    throw "Retention cmdlets not found. Connect first: Connect-IPPSSession. See docs/automation-surface.md Section 3."
}
if (-not (Test-Path -LiteralPath $ConfigPath)) { throw "Config file not found: $ConfigPath" }
$cfg = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json

$policy = Get-RetentionCompliancePolicy -Identity $cfg.policy.name -ErrorAction SilentlyContinue
if (-not $policy) {
    Write-Host "Policy '$($cfg.policy.name)' not found - nothing to disable/delete (expected if label.regulatory was true, since no policy/rule is created in that case)." -ForegroundColor Yellow
}
elseif ($Delete) {
    Invoke-Scc -Describe "Remove-RetentionCompliancePolicy -Identity '$($cfg.policy.name)' (removes policy + rule)" `
        -Action { Remove-RetentionCompliancePolicy -Identity $cfg.policy.name -Confirm:$false } | Out-Null
    Write-Host "  [policy+rule] removed '$($cfg.policy.name)'. Future content stops being auto-labeled. Content already labeled as a record is UNCHANGED - see rollback.md." -ForegroundColor Green
}
else {
    Invoke-Scc -Describe "Set-RetentionCompliancePolicy -Identity '$($cfg.policy.name)' -Enabled `$false" `
        -Action { Set-RetentionCompliancePolicy -Identity $cfg.policy.name -Enabled $false -Confirm:$false } | Out-Null
    Write-Host "  [policy] disabled '$($cfg.policy.name)' - no new content is auto-labeled; re-run the deploy script to re-enable." -ForegroundColor Green
}

if ($Delete -and $TryRemoveScope) {
    $scope = Get-AdaptiveScope -Identity $cfg.adaptiveScope.name -ErrorAction SilentlyContinue
    if (-not $scope) {
        Write-Host "Adaptive scope '$($cfg.adaptiveScope.name)' not found - nothing to remove." -ForegroundColor Yellow
    }
    else {
        $removeParams = @{ Identity = $cfg.adaptiveScope.name }
        if ($ForceScopeDeletion) { $removeParams.ForceDeletion = $true }
        try {
            Invoke-Scc -Describe "Remove-AdaptiveScope -Identity '$($cfg.adaptiveScope.name)'$(if ($ForceScopeDeletion) { ' -ForceDeletion' })" `
                -Action { Remove-AdaptiveScope @removeParams -Confirm:$false } | Out-Null
            Write-Host "  [scope] removed '$($cfg.adaptiveScope.name)'" -ForegroundColor Green
        }
        catch {
            Write-Host "  [scope] could not remove '$($cfg.adaptiveScope.name)': $($_.Exception.Message)" -ForegroundColor Red
            Write-Host "  This can happen if another policy still references the scope - e.g. the adaptive-scope-retention sibling, if both share this scope name in your tenant. Re-run with -ForceScopeDeletion only after confirming no other policy needs it." -ForegroundColor Yellow
        }
    }
}

Write-Host "`nDone. The retention label definition and any content already labeled as a record are never touched by this script - see rollback.md." -ForegroundColor Cyan
