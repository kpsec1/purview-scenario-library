#Requires -Version 7.0
<#
.SYNOPSIS
    Rolls back the adaptive-scope retention policy/rule and, optionally, the adaptive scope
    itself and the policy/rule objects - staged, per rollback.md.

.DESCRIPTION
    Stage 1 (default): Set-RetentionCompliancePolicy -Enabled $false - stops future retention
    enforcement for new/changed content. Reversible (re-run the deploy script to re-enable).

    Stage 2 (-Delete): Remove-RetentionCompliancePolicy - removes the policy AND its rule in one
    call (Microsoft's own documented behavior: "This cmdlet also removes the corresponding
    retention rule"). Per Remove-RetentionComplianceRule's own documented description, removing
    the rule "causes the release of all Exchange mailbox and SharePoint site retentions that are
    associated with the rule" - i.e. this is NOT a record label: there is no locked content to
    force-release, unlike the sibling retention-labels-financial-records scenario. See .NOTES.

    Stage 3 (-Delete -TryRemoveScope): also attempts Remove-AdaptiveScope for the adaptive scope.
    This can fail if the scope is still referenced by another policy (Insider Risk Management,
    Communication Compliance, or another retention policy also use adaptive scopes) - the script
    reports the failure rather than forcing it (-ForceDeletion is available but NOT used by
    default; pass -ForceScopeDeletion to opt in).

    Idempotent / safe to re-run: each stage checks current state before acting.

.PARAMETER ConfigPath
    Path to the JSON config. Defaults to 'config/adaptive-scope-retention.sample.json'.

.PARAMETER Delete
    Also remove the retention policy (and its rule).

.PARAMETER TryRemoveScope
    After -Delete, also attempt to remove the adaptive scope (Remove-AdaptiveScope). Reports
    failure rather than forcing it unless -ForceScopeDeletion is also specified.

.PARAMETER ForceScopeDeletion
    Pass -ForceDeletion to Remove-AdaptiveScope. Only meaningful with -Delete -TryRemoveScope.

.PARAMETER DryRun
    Print every mutating cmdlet that would run and invoke none.

.EXAMPLE
    Connect-IPPSSession -AppId $AppId -Certificate $Cert -Organization 'contoso.onmicrosoft.com'
    ./Remove-AdaptiveScopeRetention.ps1 -DryRun

.EXAMPLE
    Connect-IPPSSession -AppId $AppId -Certificate $Cert -Organization 'contoso.onmicrosoft.com'
    ./Remove-AdaptiveScopeRetention.ps1 -Delete -TryRemoveScope

.NOTES
    Grounded in Microsoft Learn (verify before production use):
    - Remove-RetentionCompliancePolicy (removes policy + rule together):
      https://learn.microsoft.com/powershell/module/exchangepowershell/remove-retentioncompliancepolicy
    - Remove-RetentionComplianceRule ("causes the release of all Exchange mailbox and SharePoint
      site retentions that are associated with the rule" - the source of this script's "not a
      record, retention is released" framing):
      https://learn.microsoft.com/powershell/module/exchangepowershell/remove-retentioncompliancerule
    - Remove-AdaptiveScope (-Identity/-ForceDeletion):
      https://learn.microsoft.com/powershell/module/exchangepowershell/remove-adaptivescope
#>
[CmdletBinding()]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$ConfigPath = (Join-Path $PSScriptRoot 'config/adaptive-scope-retention.sample.json'),

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
    Write-Host "Policy '$($cfg.policy.name)' not found - nothing to disable/delete." -ForegroundColor Yellow
}
elseif ($Delete) {
    Invoke-Scc -Describe "Remove-RetentionCompliancePolicy -Identity '$($cfg.policy.name)' (removes policy + rule)" `
        -Action { Remove-RetentionCompliancePolicy -Identity $cfg.policy.name -Confirm:$false } | Out-Null
    Write-Host "  [policy+rule] removed '$($cfg.policy.name)'. Retention already applied to content is released (this is a Keep-only policy, not a record label)." -ForegroundColor Green
}
else {
    Invoke-Scc -Describe "Set-RetentionCompliancePolicy -Identity '$($cfg.policy.name)' -Enabled `$false" `
        -Action { Set-RetentionCompliancePolicy -Identity $cfg.policy.name -Enabled $false -Confirm:$false } | Out-Null
    Write-Host "  [policy] disabled '$($cfg.policy.name)' - no new content is retained under it; re-run the deploy script to re-enable." -ForegroundColor Green
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
            Write-Host "  This can happen if another policy still references the scope. Re-run with -ForceScopeDeletion only after confirming no other policy needs it." -ForegroundColor Yellow
        }
    }
}

Write-Host "`nDone." -ForegroundColor Cyan
