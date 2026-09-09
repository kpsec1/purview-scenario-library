#Requires -Version 7.0
<#
.SYNOPSIS
    Creates a PRIORITY CLEANUP retention label, policy, and rule for Exchange mailboxes - a
    Microsoft Purview Data Lifecycle Management control that PERMANENTLY DELETES matching mail
    content, overriding existing retention policies, litigation holds, eDiscovery holds, and even
    Preservation Lock (delete-only configurations) - using Security & Compliance PowerShell.

.DESCRIPTION
    Uses the same cmdlets as a normal auto-apply retention label deployment, but every one of them
    is called with the official -PriorityCleanup switch/parameter set:
      1. New-ComplianceTag             -> the label (-PriorityCleanup; RetentionAction Delete,
                                           RetentionDuration/RetentionType, -MultiStageReviewProperty)
      2. New-RetentionCompliancePolicy -> the policy (-PriorityCleanup -SkipPriorityCleanupConfirmation;
                                           -ExchangeLocation; -Enabled or -IsSimulation)
      3. New-RetentionComplianceRule   -> the rule (-PriorityCleanup -ApplyComplianceTag -ContentMatchQuery)

    !!! IRREVERSIBLE AND HOLD-OVERRIDING !!! Priority cleanup is designed to permanently delete
    content even when a retention policy, litigation hold, eDiscovery hold, or Preservation Lock
    (delete-only) would otherwise prevent it. Once all required approvals are complete, items "are
    permanently deleted and cannot be restored by users, by admins, or by Microsoft." Read
    README.md Sections 2 and 11 before running this for real. Microsoft's own guidance: "Priority
    cleanup is rolling out in preview and subject to change," and highly regulated organizations
    using Preservation Lock may prefer to leave the tenant-wide control OFF entirely.

    Idempotent: each object is located by name via Get-* (using the official -PriorityCleanup
    filter switch on Get-ComplianceTag / Get-RetentionCompliancePolicy / Get-RetentionComplianceRule)
    before create; if present it is reported, never silently mutated. Re-running is safe. -WhatIf is
    non-functional in Security & Compliance PowerShell, so this script implements its own -DryRun.

    This script does NOT approve pending priority-cleanup items - Microsoft publishes no PowerShell
    or Graph cmdlet for the "Pending cleanups" approval queue; approving deletions is a Microsoft
    Purview portal-only action (Data Lifecycle Management > Priority cleanup > Pending cleanups).
    See README.md Section 5/§8 and rollback.md.

    Connect first: Connect-IPPSSession (certificate app-only preferred - docs/automation-surface.md
    Section 3). This script does not open the session.

.PARAMETER ConfigPath
    Path to the JSON config. Defaults to 'config/priority-cleanup-exchange.sample.json'.

.PARAMETER Simulate
    Create the policy in simulation mode (-IsSimulation) instead of using config's policy.enabled
    value, then start the simulation (Set-RetentionCompliancePolicy -StartSimulation $true).
    Simulation is not required for Exchange priority cleanup (unlike SharePoint/OneDrive) but is
    Microsoft's documented recommendation - this scenario defaults to requiring an explicit choice
    (-Simulate or -Enabled) rather than silently going live. See README.md Section 5.

.PARAMETER Enabled
    Create/leave the policy enabled (skips simulation). Overrides config's policy.enabled value.
    Requires deliberate use - see the irreversibility warning above.

.PARAMETER EnforceSimulation
    For a policy already created with -Simulate: call
    Set-RetentionCompliancePolicy -EnforceSimulationPolicy $true to turn the reviewed simulation
    into a live, enforced priority cleanup policy. Run this only after a SECOND priority cleanup
    admin has reviewed the simulation results in the portal (Data Lifecycle Management > Priority
    cleanup > View simulation details) - this script cannot review or export simulation results;
    no documented API exists for that. See README.md Section 5.

.PARAMETER DryRun
    Print every mutating cmdlet that would run and invoke none (the working substitute for -WhatIf,
    which does not function in Security & Compliance PowerShell).

.EXAMPLE
    Connect-IPPSSession -AppId $AppId -Certificate $Cert -Organization 'contoso.onmicrosoft.com'
    ./New-PriorityCleanupExchangePolicy.ps1 -Simulate -DryRun

.EXAMPLE
    Connect-IPPSSession -AppId $AppId -Certificate $Cert -Organization 'contoso.onmicrosoft.com'
    ./New-PriorityCleanupExchangePolicy.ps1 -Simulate
    # ... wait for simulation results, get a second priority cleanup admin to review them in the portal ...
    ./New-PriorityCleanupExchangePolicy.ps1 -EnforceSimulation

.NOTES
    Grounded in Microsoft Learn (verify before production use):
    - Expedite the permanent deletion of sensitive information from mailboxes (priority cleanup for
      Exchange; preview status; approver roles; KeyQL exclusions; audit operations):
      https://learn.microsoft.com/purview/priority-cleanup-exchange
    - New-ComplianceTag (-PriorityCleanup parameter set; -MultiStageReviewProperty JSON shape):
      https://learn.microsoft.com/powershell/module/exchangepowershell/new-compliancetag
    - New-RetentionCompliancePolicy (-PriorityCleanup; -SkipPriorityCleanupConfirmation; -IsSimulation):
      https://learn.microsoft.com/powershell/module/exchangepowershell/new-retentioncompliancepolicy
    - New-RetentionComplianceRule (-PriorityCleanup; -ApplyComplianceTag; -ContentMatchQuery):
      https://learn.microsoft.com/powershell/module/exchangepowershell/new-retentioncompliancerule
    - Set-RetentionCompliancePolicy (-StartSimulation; -EnforceSimulationPolicy):
      https://learn.microsoft.com/powershell/module/exchangepowershell/set-retentioncompliancepolicy
    - Get-ComplianceTag / Get-RetentionCompliancePolicy / Get-RetentionComplianceRule (-PriorityCleanup
      filter switch used by this script and by validate/Test-PriorityCleanupExchangePolicy.ps1):
      https://learn.microsoft.com/powershell/module/exchangepowershell/get-compliancetag
      https://learn.microsoft.com/powershell/module/exchangepowershell/get-retentioncompliancepolicy
      https://learn.microsoft.com/powershell/module/exchangepowershell/get-retentioncompliancerule
#>
[CmdletBinding()]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$ConfigPath = (Join-Path $PSScriptRoot 'config/priority-cleanup-exchange.sample.json'),

    [Parameter()]
    [switch]$Simulate,

    [Parameter()]
    [switch]$Enabled,

    [Parameter()]
    [switch]$EnforceSimulation,

    [Parameter()]
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

function Assert-SccConnected {
    if (-not (Get-Command Get-ComplianceTag -ErrorAction SilentlyContinue)) {
        throw "Retention cmdlets not found. Connect first: Connect-IPPSSession (Security & Compliance PowerShell). See docs/automation-surface.md Section 3."
    }
}
function Invoke-Scc {
    param([Parameter(Mandatory)][string]$Describe, [Parameter(Mandatory)][scriptblock]$Action)
    if ($DryRun) { Write-Host "  DRYRUN would run: $Describe" -ForegroundColor DarkYellow; return $null }
    Write-Host "  $Describe" -ForegroundColor Green
    return & $Action
}

Assert-SccConnected

if (-not (Test-Path -LiteralPath $ConfigPath)) { throw "Config file not found: $ConfigPath" }
$cfg = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
foreach ($k in 'label', 'policy', 'rule') { if (-not $cfg.$k) { throw "Config missing '$k' section." } }
if (-not $cfg.label.name) { throw "label.name is required." }
if (-not $cfg.policy.name) { throw "policy.name is required." }

if ($EnforceSimulation) {
    Write-Host "Enforcing simulation for priority cleanup policy '$($cfg.policy.name)' - turning it LIVE." -ForegroundColor Red
    Write-Host "Confirm a SECOND priority cleanup admin has reviewed the simulation results in the portal before proceeding (README.md Section 5)." -ForegroundColor Yellow
    Invoke-Scc -Describe "Set-RetentionCompliancePolicy -Identity '$($cfg.policy.name)' -EnforceSimulationPolicy `$true" `
        -Action { Set-RetentionCompliancePolicy -Identity $cfg.policy.name -EnforceSimulationPolicy $true -Confirm:$false } | Out-Null
    Write-Host "`nDone. Policy is now enforced (live). Approvals will begin as matching items are identified." -ForegroundColor Cyan
    return
}

if (-not $Simulate -and -not $Enabled -and -not $DryRun) {
    throw "Refusing to deploy without an explicit choice: pass -Simulate (recommended) or -Enabled (skips simulation), or -DryRun to preview. This scenario deliberately has no silent default - see README.md Section 5 and the irreversibility warning in this script's .DESCRIPTION."
}

Write-Host "Deploying Exchange priority cleanup: label '$($cfg.label.name)' + policy '$($cfg.policy.name)'." -ForegroundColor Cyan
Write-Host "WARNING: PRIORITY CLEANUP PERMANENTLY DELETES CONTENT, OVERRIDING RETENTION POLICIES, LITIGATION HOLDS, AND eDISCOVERY HOLDS. This cannot be undone by users, admins, or Microsoft. See README.md Sections 2/11." -ForegroundColor Red

# --- 1. Retention label (New-ComplianceTag -PriorityCleanup) ---
$existingLabel = Get-ComplianceTag -PriorityCleanup -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq $cfg.label.name }
if ($existingLabel) {
    Write-Host "  [label] exists '$($cfg.label.name)' (not modified - priority cleanup labels are high-consequence; edit deliberately with Set-ComplianceTag -PriorityCleanup)." -ForegroundColor DarkGreen
}
else {
    $stages = @()
    foreach ($stage in $cfg.label.approvalStages) {
        if (-not $stage.stageName -or -not $stage.reviewers -or @($stage.reviewers).Count -eq 0) {
            throw "Each label.approvalStages entry needs stageName and at least one reviewer."
        }
        $stages += @{ StageName = $stage.stageName; Reviewers = @($stage.reviewers) }
    }
    if ($stages.Count -eq 0) { throw "label.approvalStages must define at least one review stage (New-ComplianceTag -PriorityCleanup requires -MultiStageReviewProperty)." }
    $multiStageJson = ConvertTo-Json -Depth 5 -Compress @{ MultiStageReviewSettings = $stages }

    $tagParams = @{
        Name              = $cfg.label.name
        RetentionAction   = $cfg.label.retentionAction
        RetentionDuration = [int]$cfg.label.retentionDurationDays
        RetentionType     = $cfg.label.retentionType
        MultiStageReviewProperty = $multiStageJson
        PriorityCleanup   = $true
    }
    if ($cfg.label.comment) { $tagParams.Comment = $cfg.label.comment }

    $desc = "New-ComplianceTag -Name '$($cfg.label.name)' -RetentionAction $($cfg.label.retentionAction) -RetentionDuration $($cfg.label.retentionDurationDays) -RetentionType $($cfg.label.retentionType) -MultiStageReviewProperty <$($stages.Count)-stage JSON> -PriorityCleanup"
    Invoke-Scc -Describe $desc -Action { New-ComplianceTag @tagParams -Confirm:$false } | Out-Null
    Write-Host "  [label] created '$($cfg.label.name)' ($($stages.Count) approval stage(s))" -ForegroundColor Green
}

# --- 2. Priority cleanup policy (New-RetentionCompliancePolicy -PriorityCleanup) ---
$existingPolicy = Get-RetentionCompliancePolicy -PriorityCleanup -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq $cfg.policy.name }
if ($existingPolicy) {
    Write-Host "  [policy] exists '$($cfg.policy.name)'" -ForegroundColor DarkGreen
}
else {
    if (-not $cfg.policy.exchangeLocation -or @($cfg.policy.exchangeLocation).Count -eq 0) {
        throw "policy.exchangeLocation is required (specific mailboxes, or the literal string 'All')."
    }
    $polParams = @{
        Name                          = $cfg.policy.name
        ExchangeLocation              = @($cfg.policy.exchangeLocation)
        PriorityCleanup               = $true
        SkipPriorityCleanupConfirmation = $true
    }
    if ($cfg.policy.exchangeLocationException -and @($cfg.policy.exchangeLocationException).Count -gt 0) {
        $polParams.ExchangeLocationException = @($cfg.policy.exchangeLocationException)
    }
    if ($cfg.policy.comment) { $polParams.Comment = $cfg.policy.comment }

    if ($Simulate) {
        $polParams.IsSimulation = $true
        $desc = "New-RetentionCompliancePolicy -Name '$($cfg.policy.name)' -ExchangeLocation <$(@($cfg.policy.exchangeLocation).Count) mailbox(es)> -PriorityCleanup -IsSimulation"
    }
    else {
        $polParams.Enabled = [bool]$Enabled -or [bool]$cfg.policy.enabled
        $desc = "New-RetentionCompliancePolicy -Name '$($cfg.policy.name)' -ExchangeLocation <$(@($cfg.policy.exchangeLocation).Count) mailbox(es)> -PriorityCleanup -Enabled `$$($polParams.Enabled)"
    }
    Invoke-Scc -Describe $desc -Action { New-RetentionCompliancePolicy @polParams -Confirm:$false } | Out-Null
    Write-Host "  [policy] created '$($cfg.policy.name)'$(if ($Simulate) { ' (SIMULATION MODE)' })" -ForegroundColor Green
}

# --- 3. Priority cleanup rule (New-RetentionComplianceRule -PriorityCleanup -ApplyComplianceTag) ---
$existingRule = Get-RetentionComplianceRule -PriorityCleanup -Policy $cfg.policy.name -ErrorAction SilentlyContinue | Select-Object -First 1
if ($existingRule) {
    Write-Host "  [rule] exists on policy '$($cfg.policy.name)' (one rule per policy - not modified)." -ForegroundColor DarkGreen
}
else {
    if ([string]::IsNullOrWhiteSpace($cfg.rule.contentMatchQuery)) { throw "rule.contentMatchQuery is required." }
    $ruleParams = @{
        Policy            = $cfg.policy.name
        ApplyComplianceTag = $cfg.label.name
        ContentMatchQuery = $cfg.rule.contentMatchQuery
        PriorityCleanup   = $true
    }
    Invoke-Scc -Describe "New-RetentionComplianceRule -Policy '$($cfg.policy.name)' -ApplyComplianceTag '$($cfg.label.name)' -ContentMatchQuery '<query>' -PriorityCleanup" `
        -Action { New-RetentionComplianceRule @ruleParams -Confirm:$false } | Out-Null
    Write-Host "  [rule] created (priority cleanup applies '$($cfg.label.name)')" -ForegroundColor Green
}

if ($Simulate -and -not $DryRun) {
    Write-Host "`nStarting simulation..." -ForegroundColor Cyan
    Invoke-Scc -Describe "Set-RetentionCompliancePolicy -Identity '$($cfg.policy.name)' -StartSimulation `$true" `
        -Action { Set-RetentionCompliancePolicy -Identity $cfg.policy.name -StartSimulation $true -Confirm:$false } | Out-Null
}

Write-Host "`nDone." -ForegroundColor Cyan
if ($Simulate) {
    Write-Host "Simulation started - results may take a couple of hours. Review sample matches in the portal (Data Lifecycle Management > Priority cleanup), then have a SECOND priority cleanup admin re-run this script with -EnforceSimulation." -ForegroundColor Yellow
}
else {
    Write-Host "Policy is live. Auto-apply can take up to 7 days. Approvals happen ONLY in the portal (Data Lifecycle Management > Priority cleanup > Pending cleanups) - no PowerShell/Graph approval cmdlet exists. Validate with validate/Test-PriorityCleanupExchangePolicy.ps1." -ForegroundColor Yellow
}
