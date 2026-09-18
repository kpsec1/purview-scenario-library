---
part: "deploy"
parent: "data-lifecycle-management/adaptive-scope-retention"
---
The scripts and configuration below deploy this scenario. Review them, then run in order — each is designed to be idempotent and has a matching rollback.


#### `config/adaptive-scope-retention.sample.json`

```json
{
  "_comment": "Config for deploy/New-AdaptiveScopeRetention.ps1. Author-only reference data - NOT applied to any tenant unless passed to the deploy script without -DryRun. Models the documented Microsoft example (Learn 'Adaptive or static policy scopes for retention'): a longer retention period for executives, targeted by the Entra 'Title' attribute via an adaptive scope instead of a static distribution list that goes stale as people are promoted, hired, or leave.",
  "adaptiveScope": {
    "name": "Executives - US and Canada",
    "comment": "User-type adaptive scope: Title matches a defined set of executive titles. Re-evaluated daily against Entra ID; no group to maintain.",
    "locationType": "User",
    "administrativeUnit": "",
    "filterConditions": {
      "conjunction": "Or",
      "conditions": [
        { "name": "Title", "operator": "Equals", "value": "Chief Executive Officer" },
        { "name": "Title", "operator": "Equals", "value": "Chief Financial Officer" },
        { "name": "Title", "operator": "Equals", "value": "Chief Operating Officer" },
        { "name": "Title", "operator": "Equals", "value": "General Counsel" }
      ]
    },
    "_scopeNote": "locationType: User | Group | Site (New-AdaptiveScope -LocationType) - determines which attributes/properties are valid and which policy locations the scope can be used with (README.md Section 6). administrativeUnit: Entra administrative unit GUID to restrict scope membership to a delegated boundary; leave blank for Full directory. filterConditions maps to -FilterConditions (the simple-query-builder shape: a top-level Conditions array of {Name,Operator,Value} with a Conjunction of And/Or; Operator is one of Equals/NotEquals/StartsWith/NotStartsWith). For the advanced query builder instead (OPATH for User/Group, KeyQL for Site), use -RawQuery - not shown here; see README.md Section 6. Illustrative titles - set to your organization's real executive roster signal, validated by HR/Legal."
  },
  "policy": {
    "name": "Executive Communications Retention - Adaptive",
    "comment": "Retain-only (Keep) policy for executives' Exchange email and OneDrive content, scoped by the adaptive scope above instead of a static distribution list.",
    "enabled": true,
    "_policyNote": "Maps to New-RetentionCompliancePolicy -AdaptiveScopeLocation <adaptiveScope.name>. This parameter set has no separate -ExchangeLocation/-OneDriveLocation/-SharePointLocation toggles - unlike a static-scope policy, which User-type locations (Exchange mailboxes, OneDrive, Teams chats, Copilot experiences, etc.) the policy actually applies to is not exposed as a documented parameter here - see the VERIFY note in README.md Section 11 and design.md Section 4 before assuming Exchange+OneDrive-only in production."
  },
  "rule": {
    "retentionDurationDays": 3650,
    "retentionComplianceAction": "Keep",
    "expirationDateOption": "CreationAgeInDays",
    "_ruleNote": "Maps to New-RetentionComplianceRule -RetentionDuration -RetentionComplianceAction -ExpirationDateOption. retentionComplianceAction: Keep | Delete | KeepAndDelete. retentionDurationDays: 3650 (~10 years) is an illustrative litigation-readiness / corporate-governance baseline for executive communications - tune to your actual obligation. expirationDateOption: CreationAgeInDays | ModificationAgeInDays (SharePoint/OneDrive/Groups only) - when the clock starts. This is Keep-only (retain, do not delete) by default; no records/lock semantics are involved, unlike the sibling retention-labels-financial-records scenario."
  },
  "schemaVersion": "1.0",
  "lastUpdated": "2026-09-10"
}
```

#### `New-AdaptiveScopeRetention.ps1`

```powershell
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
```

#### `Remove-AdaptiveScopeRetention.ps1`

```powershell
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
```