---
part: "deploy"
parent: "data-lifecycle-management/priority-cleanup-exchange-data-spillage"
---
The scripts and configuration below deploy this scenario. Review them, then run in order — each is designed to be idempotent and has a matching rollback.


#### `config/priority-cleanup-exchange.sample.json`

```json
{
  "_comment": "Config for deploy/New-PriorityCleanupExchangePolicy.ps1. Author-only reference data - NOT applied to any tenant unless passed to the deploy script without -DryRun. Creates a PRIORITY CLEANUP retention label + policy + rule that PERMANENTLY DELETES matching mailbox content, overriding existing retention policies, litigation holds, eDiscovery holds, and even Preservation Lock. Read README.md Sections 2 and 11 before deploying - this is IRREVERSIBLE and bypasses the safeguards every other retention control in this repo relies on.",
  "label": {
    "name": "Priority Cleanup - Data Spillage",
    "comment": "Data-spillage priority cleanup label (2026 M&A-deck leak incident). Permanently deletes matched items regardless of hold status. Underlying mechanism per New-ComplianceTag -PriorityCleanup.",
    "retentionAction": "Delete",
    "retentionDurationDays": 0,
    "retentionType": "TaggedAgeInDays",
    "approvalStages": [
      { "stageName": "PriorityCleanupAdmin", "reviewers": ["priority-cleanup-admin2@contoso.com"] },
      { "stageName": "RetentionManager", "reviewers": ["retention-manager@contoso.com"] },
      { "stageName": "EDiscoveryAdmin", "reviewers": ["ediscovery-admin@contoso.com"] }
    ],
    "_labelNote": "retentionAction must be 'Delete' for priority cleanup per New-ComplianceTag's PriorityCleanup parameter set (RetentionAction/RetentionDuration/RetentionType/MultiStageReviewProperty are all mandatory once -PriorityCleanup is used). retentionDurationDays=0 is this scenario's best-effort mapping of the portal's 'delete matched items as soon as possible' choice - VERIFY (README.md Section 11): Microsoft's reference does not publish the literal duration value 'as soon as possible' maps to. retentionType=TaggedAgeInDays (clock starts when the priority-cleanup label is applied) is this scenario's choice, not a documented default - see design.md Section 4. approvalStages become the label's -MultiStageReviewProperty JSON (one stage per required approver: priority cleanup admin, retention manager, eDiscovery admin, per priority-cleanup-exchange#prerequisites-for-priority-cleanup). The stageName strings and stage ORDER shown here are this scenario's own construction, not values copied from a Microsoft worked example for priority cleanup specifically - VERIFY before relying on stage order to match the documented approval sequence (README.md Section 11)."
  },
  "policy": {
    "name": "Priority Cleanup - Data Spillage - Exchange",
    "comment": "Static scope: mailboxes confirmed to have received the leaked attachment. Switch to exchangeLocation 'All' only if the spread is unknown - see README.md Section 6.",
    "exchangeLocation": ["spillage-recipient1@contoso.com", "spillage-recipient2@contoso.com"],
    "exchangeLocationException": [],
    "enabled": false,
    "_policyNote": "enabled=false by default - this scenario requires a deliberate -Simulate or -Enabled run, never a default-on deploy (README.md Section 5). exchangeLocation accepts specific mailboxes (up to 100 confidently, per Microsoft's own sizing guidance) or the literal string 'All'. Group mailboxes are supported only via adaptive scopes (out of scope for this static-scope starter - see design.md Section 7)."
  },
  "rule": {
    "contentMatchQuery": "AttachmentNames:\"Q4-Acquisition-Targets.xlsx\" AND sent>=2026-08-15",
    "_ruleNote": "KeyQL query (-ContentMatchQuery), same search index as eDiscovery content search. NOTE: priority cleanup's KeyQL does NOT support SenderAuthor, SubjectTitle, (c:c), or (c:s) - confirmed limitation, do not use those properties here even though eDiscovery search otherwise allows them. Narrow this to the actual spillage signal; an over-broad query permanently destroys content that cannot be recovered - see README.md Section 11."
  },
  "schemaVersion": "1.0",
  "lastUpdated": "2026-09-09"
}
```

#### `New-PriorityCleanupExchangePolicy.ps1`

```powershell
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
```

#### `Remove-PriorityCleanupExchangePolicy.ps1`

```powershell
#Requires -Version 7.0
<#
.SYNOPSIS
    Rolls back the Exchange priority cleanup deployment: disables (and optionally deletes) the
    policy/rule. The priority cleanup LABEL itself is intentionally not force-removed.

.DESCRIPTION
    Uses Security & Compliance PowerShell. Staged:
      Default    Disable the policy (Set-RetentionCompliancePolicy -Enabled $false) so it stops
                 identifying NEW items for deletion. Items already approved and deleted are gone -
                 disabling the policy cannot recover them. Items in the pending-approval queue that
                 have not yet completed all required approvals are NOT deleted by disabling the
                 policy, but Microsoft's own documentation states: "Although you can delete a
                 priority cleanup policy, if the approval process for it is complete, items might
                 still be permanently deleted" - disabling/deleting the POLICY does not reliably
                 stop an in-flight APPROVAL from completing. If items are already pending approval,
                 the only reliable stop is to have every remaining approver decline (Relabel) them
                 in the portal before disabling this policy.
      -Delete    Additionally delete the policy (Remove-RetentionCompliancePolicy) and its rule.

    The retention LABEL is NOT deleted by this script by default. Removing the label from content
    that was already deleted is meaningless (the content is gone); removing a label still applied
    to surviving content changes its retention state and should be a deliberate, reviewed action.

    -WhatIf is non-functional in Security & Compliance PowerShell, so this script implements -DryRun.
    Connect first with Connect-IPPSSession.

.PARAMETER ConfigPath
    Path to the same JSON config used to deploy. Defaults to
    'config/priority-cleanup-exchange.sample.json'. Only policy.name (and, with -TryRemoveLabel,
    label.name) are read here.

.PARAMETER Delete
    Delete the policy and its rule (not just disable).

.PARAMETER TryRemoveLabel
    Attempt to remove the retention label too (Remove-ComplianceTag). Reports rather than forces if
    the service refuses (e.g. the label is still applied to surviving content).

.PARAMETER DryRun
    Print the intended cmdlets and run none.

.EXAMPLE
    Connect-IPPSSession -AppId $AppId -Certificate $Cert -Organization 'contoso.onmicrosoft.com'
    ./Remove-PriorityCleanupExchangePolicy.ps1 -DryRun

.NOTES
    Grounded in Microsoft Learn: Set-/Remove-RetentionCompliancePolicy, Remove-ComplianceTag;
    priority cleanup approval-completion behavior.
    https://learn.microsoft.com/purview/priority-cleanup-exchange#limitations-of-priority-cleanup
#>
[CmdletBinding()]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$ConfigPath = (Join-Path $PSScriptRoot 'config/priority-cleanup-exchange.sample.json'),

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

Write-Host "IMPORTANT: if any items are currently pending approval in the portal (Data Lifecycle Management > Priority cleanup > Pending cleanups), disabling/deleting this policy does NOT reliably stop an in-flight approval from completing. Have remaining approvers decline (Relabel) pending items first if they must not be deleted. See this script's .DESCRIPTION." -ForegroundColor Red

$policy = Get-RetentionCompliancePolicy -PriorityCleanup -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq $cfg.policy.name }
if ($policy) {
    Invoke-Scc -Describe "Set-RetentionCompliancePolicy -Identity '$($cfg.policy.name)' -Enabled `$false" `
        -Action { Set-RetentionCompliancePolicy -Identity $cfg.policy.name -Enabled $false -Confirm:$false }
    Write-Host "  [disable] policy '$($cfg.policy.name)' disabled (stops identifying NEW items)." -ForegroundColor Yellow
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
            Write-Host "  [delete] label '$($cfg.label.name)' removed." -ForegroundColor Red
        }
        catch {
            Write-Warning "  Could not remove label '$($cfg.label.name)': $($_.Exception.Message). See rollback.md."
        }
    }
}

Write-Host "`nDone." -ForegroundColor Cyan
Write-Host "Content already permanently deleted by completed approvals cannot be recovered by this script, by any admin action, or by Microsoft - see rollback.md." -ForegroundColor Yellow
```