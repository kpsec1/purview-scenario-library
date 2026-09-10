#Requires -Version 7.0
<#
.SYNOPSIS
    Creates an adaptive scope and an adaptive-scope retention policy/rule that retains executive
    communications (Exchange mail, OneDrive) for a fixed period - using Security & Compliance
    PowerShell. The membership is query-driven (Entra attribute), not a static list.

.DESCRIPTION
    Uses the Data Lifecycle Management cmdlets in Security & Compliance PowerShell (automation
    surface 2 per docs/automation-surface.md):
      1. New-AdaptiveScope             -> a User-type adaptive scope (query on the Title attribute)
      2. New-RetentionCompliancePolicy -> a retention policy scoped via -AdaptiveScopeLocation
      3. New-RetentionComplianceRule   -> a Keep-only rule (no record/regulatory-record semantics)

    This is the adaptive-scope companion to scenarios/data-lifecycle-management/
    retention-labels-financial-records/, which uses a static SharePoint location and notes
    adaptive scopes as a follow-up for large/dynamic estates (its README.md Section 11). It models
    Microsoft's own documented example for adaptive scopes: retaining executives' content longer
    without maintaining a static distribution list that goes stale as people are promoted, hired,
    or leave (see .NOTES).

    GENUINE GAP, disclosed rather than guessed (see README.md Section 11 / design.md Section 4):
    New-RetentionCompliancePolicy's AdaptiveScopeLocation parameter set exposes -AdaptiveScopeLocation
    and -Applications only - no separate -ExchangeLocation/-OneDriveLocation/-SharePointLocation
    toggles the way the Default (static) parameter set does. Which of the adaptive scope's
    User-type locations (Exchange mailboxes, OneDrive, Teams chats, Copilot experiences, etc.) the
    policy actually applies to is not exposed as a documented parameter on this cmdlet. This
    script creates the policy as documented and does not claim a narrower scope than what
    Microsoft's reference actually supports - VERIFY in a pilot tenant before assuming Exchange+
    OneDrive-only.

    Idempotent: each object is located by name via Get-* before create; if present it is reported
    (not silently mutated - re-running is safe). -WhatIf is non-functional in Security & Compliance
    PowerShell, so this script implements its own -DryRun that prints the intended cmdlets and runs
    none.

    Lower irreversibility than a record label: this is a Keep-only retention policy, not a record
    or regulatory record. Removing the rule/policy releases the retention (see rollback.md) - it
    does not leave content permanently locked. Still: adaptive scope membership takes up to 5 days
    to populate/change, and this targets executives' mailboxes - validate the scope's actual
    membership (Get-AdaptiveScopeMembers) before relying on it operationally.

    Connect first: Connect-IPPSSession (certificate app-only preferred - docs/automation-surface.md
    Section 3). This script does not open the session.

.PARAMETER ConfigPath
    Path to the JSON config. Defaults to 'config/adaptive-scope-retention.sample.json'.

.PARAMETER DryRun
    Print every mutating cmdlet that would run and invoke none (the working substitute for -WhatIf,
    which does not function in Security & Compliance PowerShell).

.EXAMPLE
    Connect-IPPSSession -AppId $AppId -Certificate $Cert -Organization 'contoso.onmicrosoft.com'
    ./New-AdaptiveScopeRetention.ps1 -DryRun

.EXAMPLE
    Connect-IPPSSession -AppId $AppId -Certificate $Cert -Organization 'contoso.onmicrosoft.com'
    ./New-AdaptiveScopeRetention.ps1

.NOTES
    Grounded in Microsoft Learn (verify before production use):
    - New-AdaptiveScope (-Name/-LocationType/-FilterConditions/-RawQuery/-AdministrativeUnit):
      https://learn.microsoft.com/powershell/module/exchangepowershell/new-adaptivescope
    - Adaptive scopes overview + the documented "retain executives' content longer, targeted by the
      Title attribute" example + configuration/attribute tables + 5-day population delay:
      https://learn.microsoft.com/purview/purview-adaptive-scopes
      https://learn.microsoft.com/purview/retention#adaptive-or-static-policy-scopes-for-retention
    - New-RetentionCompliancePolicy (-AdaptiveScopeLocation, AdaptiveScopeLocation parameter set -
      no separate location-type params in this set, the disclosed gap above):
      https://learn.microsoft.com/powershell/module/exchangepowershell/new-retentioncompliancepolicy
    - New-RetentionComplianceRule (-RetentionDuration/-RetentionComplianceAction/-ExpirationDateOption):
      https://learn.microsoft.com/powershell/module/exchangepowershell/new-retentioncompliancerule
    - Scope Manager role (Records Management, Compliance Administrator, Compliance Data
      Administrator, Organization Management, Communication Compliance / Communication Compliance
      Admins role groups) required to create adaptive scopes:
      https://learn.microsoft.com/purview/purview-adaptive-scopes#configure-adaptive-scopes
#>
[CmdletBinding()]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$ConfigPath = (Join-Path $PSScriptRoot 'config/adaptive-scope-retention.sample.json'),

    [Parameter()]
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

function Assert-SccConnected {
    if (-not (Get-Command Get-RetentionCompliancePolicy -ErrorAction SilentlyContinue)) {
        throw "Retention cmdlets not found. Connect first: Connect-IPPSSession (Security & Compliance PowerShell). See docs/automation-surface.md Section 3."
    }
}
function Invoke-Scc {
    param([Parameter(Mandatory)][string]$Describe, [Parameter(Mandatory)][scriptblock]$Action)
    if ($DryRun) { Write-Host "  DRYRUN would run: $Describe" -ForegroundColor DarkYellow; return $null }
    Write-Host "  $Describe" -ForegroundColor Green
    return & $Action
}
function ConvertTo-FilterConditionsHashtable {
    param([Parameter(Mandatory)]$FilterConditions)
    $conditions = @()
    foreach ($c in $FilterConditions.conditions) {
        $conditions += @{ Name = $c.name; Operator = $c.operator; Value = $c.value }
    }
    return @{ Conditions = $conditions; Conjunction = $FilterConditions.conjunction }
}

if (-not (Test-Path -LiteralPath $ConfigPath)) { throw "Config file not found: $ConfigPath" }
$cfg = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
foreach ($k in 'adaptiveScope', 'policy', 'rule') { if (-not $cfg.$k) { throw "Config missing '$k' section." } }
if (-not $cfg.adaptiveScope.name) { throw "adaptiveScope.name is required." }
if (-not $cfg.policy.name) { throw "policy.name is required." }

Assert-SccConnected
Write-Host "Deploying adaptive-scope retention: scope '$($cfg.adaptiveScope.name)' + policy '$($cfg.policy.name)'." -ForegroundColor Cyan
Write-Host "NOTE: adaptive scope membership takes up to 5 days to populate/change - do not expect an immediate roster. See README.md Section 7/8." -ForegroundColor Yellow

# --- 1. Adaptive scope (New-AdaptiveScope) ---
$existingScope = Get-AdaptiveScope -Identity $cfg.adaptiveScope.name -ErrorAction SilentlyContinue
if ($existingScope) {
    Write-Host "  [scope] exists '$($cfg.adaptiveScope.name)' (not modified - edit deliberately with Set-AdaptiveScope if the query needs to change)." -ForegroundColor DarkGreen
}
else {
    $filterHash = ConvertTo-FilterConditionsHashtable -FilterConditions $cfg.adaptiveScope.filterConditions
    $scopeParams = @{
        Name             = $cfg.adaptiveScope.name
        LocationType     = $cfg.adaptiveScope.locationType
        FilterConditions = $filterHash
    }
    if ($cfg.adaptiveScope.comment) { $scopeParams.Comment = $cfg.adaptiveScope.comment }
    if ($cfg.adaptiveScope.administrativeUnit) { $scopeParams.AdministrativeUnit = $cfg.adaptiveScope.administrativeUnit }

    $desc = "New-AdaptiveScope -Name '$($cfg.adaptiveScope.name)' -LocationType $($cfg.adaptiveScope.locationType) -FilterConditions <$($filterHash.Conditions.Count) condition(s), $($filterHash.Conjunction)>"
    Invoke-Scc -Describe $desc -Action { New-AdaptiveScope @scopeParams } | Out-Null
    Write-Host "  [scope] created '$($cfg.adaptiveScope.name)' - allow up to 5 days for membership to populate." -ForegroundColor Green
}

# --- 2. Adaptive-scope retention policy (New-RetentionCompliancePolicy) ---
$existingPolicy = Get-RetentionCompliancePolicy -Identity $cfg.policy.name -ErrorAction SilentlyContinue
if ($existingPolicy) {
    Write-Host "  [policy] exists '$($cfg.policy.name)'" -ForegroundColor DarkGreen
}
else {
    $polParams = @{
        Name                = $cfg.policy.name
        AdaptiveScopeLocation = $cfg.adaptiveScope.name
    }
    if ($null -ne $cfg.policy.enabled) { $polParams.Enabled = [bool]$cfg.policy.enabled }
    if ($cfg.policy.comment) { $polParams.Comment = $cfg.policy.comment }
    Invoke-Scc -Describe "New-RetentionCompliancePolicy -Name '$($cfg.policy.name)' -AdaptiveScopeLocation '$($cfg.adaptiveScope.name)'" `
        -Action { New-RetentionCompliancePolicy @polParams -Confirm:$false } | Out-Null
    Write-Host "  [policy] created '$($cfg.policy.name)'" -ForegroundColor Green
}

# --- 3. Retention rule (New-RetentionComplianceRule, Keep-only) ---
$existingRule = Get-RetentionComplianceRule -Policy $cfg.policy.name -ErrorAction SilentlyContinue | Select-Object -First 1
if ($existingRule) {
    Write-Host "  [rule] exists on policy '$($cfg.policy.name)' (one rule per policy - not modified)." -ForegroundColor DarkGreen
}
else {
    $ruleParams = @{
        Name                       = "$($cfg.policy.name) - Rule"
        Policy                     = $cfg.policy.name
        RetentionComplianceAction  = $cfg.rule.retentionComplianceAction
        ExpirationDateOption       = $cfg.rule.expirationDateOption
    }
    $dur = if ("$($cfg.rule.retentionDurationDays)" -eq 'Unlimited') { 'Unlimited' } else { [int]$cfg.rule.retentionDurationDays }
    $ruleParams.RetentionDuration = $dur
    Invoke-Scc -Describe "New-RetentionComplianceRule -Policy '$($cfg.policy.name)' -RetentionDuration $dur -RetentionComplianceAction $($cfg.rule.retentionComplianceAction) -ExpirationDateOption $($cfg.rule.expirationDateOption)" `
        -Action { New-RetentionComplianceRule @ruleParams -Confirm:$false } | Out-Null
    Write-Host "  [rule] created (Keep $dur days from $($cfg.rule.expirationDateOption))" -ForegroundColor Green
}

Write-Host "`nDone." -ForegroundColor Cyan
Write-Host "Adaptive scope membership and policy distribution can each take up to several days. Validate with validate/Test-AdaptiveScopeRetention.ps1 and confirm the actual scope membership (Get-AdaptiveScopeMembers) before relying on this operationally." -ForegroundColor Yellow
