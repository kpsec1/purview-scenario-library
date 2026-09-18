---
part: "deploy"
parent: "data-lifecycle-management/priority-cleanup-sharepoint-onedrive"
---
The scripts and configuration below deploy this scenario. Review them, then run in order — each is designed to be idempotent and has a matching rollback.


#### `config/priority-cleanup-sharepoint-onedrive.sample.json`

```json
{
  "_comment": "Config for deploy/New-PriorityCleanupSharePointOneDrivePolicy.ps1. Author-only reference data - NOT applied to any tenant unless passed to the deploy script without -DryRun. Creates a PRIORITY CLEANUP retention label + policy + rule for OneDrive/SharePoint that overrides existing retention policies, litigation holds, eDiscovery holds, and Preservation Lock (delete-only configurations only) to move matching stale content into the second-stage Recycle Bin - NOT an instant permanent delete (that is the separate, still-public-preview permanent-deletion sub-feature, out of scope here). Read README.md Sections 2 and 11 before deploying.",
  "label": {
    "name": "Priority Cleanup - Stale Teams Recordings",
    "comment": "Continual cleanup of Teams meeting recordings/transcripts that Copilot recap no longer needs and that have little business value after 1-3 months, per Microsoft's own lead use case for this workload. Underlying mechanism per New-ComplianceTag -PriorityCleanup.",
    "retentionAction": "Delete",
    "retentionDurationDays": 0,
    "retentionType": "TaggedAgeInDays",
    "approvalStages": [
      { "stageName": "EDiscoveryAdmin", "reviewers": ["ediscovery-admin@contoso.com"] }
    ],
    "_labelNote": "retentionAction must be 'Delete' for priority cleanup per New-ComplianceTag's PriorityCleanup parameter set (RetentionAction/RetentionDuration/RetentionType/MultiStageReviewProperty are all mandatory once -PriorityCleanup is used - confirmed directly against the cmdlet's own PriorityCleanup parameter-set syntax). retentionDurationDays=0/TaggedAgeInDays is this scenario's best-effort mapping of the portal's 'delete matched items as soon as possible' choice, carried over from the Exchange sibling scenario's construction - VERIFY (README.md Section 11), same open gap. approvalStages here has ONE stage (EDiscoveryAdmin) because Microsoft's SharePoint/OneDrive-specific approver documentation names only the eDiscovery admin as a Pending-Cleanups review stage - unlike Exchange's 3-stage model, there is no separate 'retention manager' approver for SharePoint/OneDrive, and the required second Priority Cleanup Admin review happens PRE-turn-on (reviewing simulation results and turning the policy on), not as a Pending Cleanups approval stage. Whether -MultiStageReviewProperty must ALSO carry a PriorityCleanupAdmin stage entry for that pre-turn-on check to register correctly is not confirmed by any Microsoft worked example specific to priority cleanup for this workload - flagged as this scenario's own genuine construction gap, VERIFY before production reliance (README.md Section 11, design.md Section 4)."
  },
  "policy": {
    "name": "Priority Cleanup - Stale Teams Recordings - SPO-OD",
    "comment": "Static scope: OneDriveLocation 'All' (most recordings/transcripts save to OneDrive per Microsoft's own guidance) plus the specific SharePoint team sites hosting channel-meeting recordings. Widen/narrow per README.md Section 6.",
    "oneDriveLocation": ["All"],
    "oneDriveLocationException": [],
    "sharePointLocation": ["https://contoso.sharepoint.com/sites/engineering-channel-meetings"],
    "sharePointLocationException": [],
    "_policyNote": "This scenario's scripts NEVER support a direct -Enabled-at-creation path (unlike the Exchange sibling) - Microsoft states simulation is REQUIRED (not merely recommended) to initially set up priority cleanup for SharePoint/OneDrive locations, and again for any policy change other than the description. The only path is -Simulate (create) then -EnforceSimulation (turn on, after a SECOND Priority Cleanup Admin reviews simulation results in the portal). SharePoint sites can't be added to the policy until they've been indexed (New-RetentionCompliancePolicy's own -SharePointLocation parameter note) - if a newly created site isn't yet indexed, add it to the config and re-run the deploy script later rather than failing the whole deployment."
  },
  "rule": {
    "contentMatchQuery": "ProgID:Media AND ProgID:Meeting",
    "_ruleNote": "Verbatim Microsoft worked example for 'find Teams meeting recordings and transcripts' (priority-cleanup-onedrive-sharepoint#create-a-priority-cleanup-policy) - unlike the Exchange sibling's own hand-constructed query, this one needed no construction. For the Preservation Hold library / departed-user variant instead, Microsoft's own alternate worked example is 'ParentLink:PreservationHoldLibrary' - swap this value and retarget policy.oneDriveLocation to the specific departed user's OneDrive to reuse this same scenario for that use case (design.md Section 3). NOTE: this query has no relative-date operator ('older than 90 days') - KeyQL/eDiscovery search syntax documented for priority cleanup has no confirmed NOW()-style function, so a 'continual' stale-recordings policy as documented here matches ALL Teams recordings/transcripts, not just old ones. See README.md Section 8 for the operational workaround (periodic query review, not a scripted age filter) and the open VERIFY on whether Exchange's documented KeyQL exclusions (SenderAuthor/SubjectTitle/(c:c)/(c:s)) also apply to this workload's queries - Microsoft's SharePoint/OneDrive-specific page does not repeat that exclusion list, so this is not assumed either way (README.md Section 11)."
  },
  "schemaVersion": "1.0",
  "lastUpdated": "2026-09-09"
}
```

#### `New-PriorityCleanupSharePointOneDrivePolicy.ps1`

```powershell
#Requires -Version 7.0
<#
.SYNOPSIS
    Creates a PRIORITY CLEANUP retention label, policy, and rule for OneDrive and SharePoint - a
    Microsoft Purview Data Lifecycle Management control that overrides existing retention policies,
    eDiscovery holds, and Preservation Lock (delete-only configurations) to move matching stale
    content into the second-stage Recycle Bin - using Security & Compliance PowerShell.

.DESCRIPTION
    Same three-cmdlet shape as every other retention scenario in this repo, every one called with
    the official -PriorityCleanup switch/parameter set:
      1. New-ComplianceTag             -> the label (-PriorityCleanup; RetentionAction Delete,
                                           RetentionDuration/RetentionType, -MultiStageReviewProperty)
      2. New-RetentionCompliancePolicy -> the policy (-PriorityCleanup; -OneDriveLocation/
                                           -SharePointLocation; -IsSimulation - see below)
      3. New-RetentionComplianceRule   -> the rule (-PriorityCleanup -ApplyComplianceTag -ContentMatchQuery)

    UNLIKE the Exchange sibling scenario (priority-cleanup-exchange-data-spillage), simulation is
    NOT optional here: Microsoft states you MUST run simulation at least once to initially set up
    priority cleanup for SharePoint/OneDrive, and again for any policy change other than the
    description. This script therefore has NO -Enabled-at-creation path at all - only -Simulate
    (create) followed by a separate -EnforceSimulation run (turn on, after a SECOND Priority Cleanup
    Admin has reviewed the simulation results in the portal). Microsoft also notes "the last person
    to edit the policy can't also turn it on" - the operator running -EnforceSimulation must be a
    different admin from whoever last ran -Simulate against this same policy; this script cannot
    verify that itself (no documented API exposes "who last edited this policy").

    Deletion here moves matching items to the SECOND-STAGE RECYCLE BIN (bypassing the hold that
    would otherwise block that move) - it is NOT an instant permanent delete like the Exchange
    sibling. From the Recycle Bin, items follow the same SharePoint/OneDrive retention timers as any
    other deleted item. The separate, still-public-preview "permanent deletion" sub-feature (bypasses
    the Recycle Bin entirely) is explicitly out of scope for this fragment - see README.md Section 11
    and PROGRESS.md.

    Idempotent: each object is located by name via Get-* (using the official -PriorityCleanup filter
    switch) before create; if present it is reported, never silently mutated. Re-running is safe.
    -WhatIf is non-functional in Security & Compliance PowerShell, so this script implements its own
    -DryRun.

    This script does NOT approve pending priority-cleanup items - Microsoft publishes no PowerShell
    or Graph cmdlet for the "Pending cleanups" approval queue; approving disposals is a Microsoft
    Purview portal-only action (Data Lifecycle Management > Priority cleanup > Pending cleanups).
    See README.md Section 5/8 and rollback.md.

    Connect first: Connect-IPPSSession (certificate app-only preferred - docs/automation-surface.md
    Section 3). This script does not open the session.

.PARAMETER ConfigPath
    Path to the JSON config. Defaults to
    'config/priority-cleanup-sharepoint-onedrive.sample.json'.

.PARAMETER Simulate
    Create the policy in simulation mode (-IsSimulation), then start the simulation
    (Set-RetentionCompliancePolicy -StartSimulation $true). This is the ONLY supported way to
    create the policy - see the mandatory-simulation note above.

.PARAMETER EnforceSimulation
    For a policy already created with -Simulate: call
    Set-RetentionCompliancePolicy -EnforceSimulationPolicy $true to turn the reviewed simulation
    into a live, enforced priority cleanup policy. Run this only after a SECOND Priority Cleanup
    Admin (not whoever last edited the policy) has reviewed the simulation results in the portal
    (Data Lifecycle Management > Priority cleanup > View simulation details) - this script cannot
    review or export those results itself (no documented API). See README.md Section 5.

.PARAMETER DryRun
    Print every mutating cmdlet that would run and invoke none (the working substitute for -WhatIf,
    which does not function in Security & Compliance PowerShell).

.EXAMPLE
    Connect-IPPSSession -AppId $AppId -Certificate $Cert -Organization 'contoso.onmicrosoft.com'
    ./New-PriorityCleanupSharePointOneDrivePolicy.ps1 -Simulate -DryRun

.EXAMPLE
    Connect-IPPSSession -AppId $AppId -Certificate $Cert -Organization 'contoso.onmicrosoft.com'
    ./New-PriorityCleanupSharePointOneDrivePolicy.ps1 -Simulate
    # ... wait for simulation results (up to a couple of hours), get a SECOND priority cleanup
    #     admin to review them in the portal ...
    ./New-PriorityCleanupSharePointOneDrivePolicy.ps1 -EnforceSimulation

.NOTES
    Grounded in Microsoft Learn (verify before production use):
    - Override holds to clean up files for Copilot and reclaim storage (priority cleanup for
      SharePoint/OneDrive; approver model; mandatory simulation; audit operations; KeyQL worked
      examples for Teams recordings/Preservation Hold library):
      https://learn.microsoft.com/purview/priority-cleanup-onedrive-sharepoint
    - New-ComplianceTag (-PriorityCleanup parameter set; -MultiStageReviewProperty JSON shape):
      https://learn.microsoft.com/powershell/module/exchangepowershell/new-compliancetag
    - New-RetentionCompliancePolicy (-PriorityCleanup; -OneDriveLocation; -SharePointLocation;
      -IsSimulation):
      https://learn.microsoft.com/powershell/module/exchangepowershell/new-retentioncompliancepolicy
    - New-RetentionComplianceRule (-PriorityCleanup; -ApplyComplianceTag; -ContentMatchQuery):
      https://learn.microsoft.com/powershell/module/exchangepowershell/new-retentioncompliancerule
    - Set-RetentionCompliancePolicy (-StartSimulation; -EnforceSimulationPolicy):
      https://learn.microsoft.com/powershell/module/exchangepowershell/set-retentioncompliancepolicy
    - Get-ComplianceTag / Get-RetentionCompliancePolicy / Get-RetentionComplianceRule
      (-PriorityCleanup filter switch used by this script and by
      validate/Test-PriorityCleanupSharePointOneDrivePolicy.ps1):
      https://learn.microsoft.com/powershell/module/exchangepowershell/get-compliancetag
      https://learn.microsoft.com/powershell/module/exchangepowershell/get-retentioncompliancepolicy
      https://learn.microsoft.com/powershell/module/exchangepowershell/get-retentioncompliancerule
#>
[CmdletBinding()]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$ConfigPath = (Join-Path $PSScriptRoot 'config/priority-cleanup-sharepoint-onedrive.sample.json'),

    [Parameter()]
    [switch]$Simulate,

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
    Write-Host "Enforcing simulation for priority cleanup policy '$($cfg.policy.name)' - turning it ON." -ForegroundColor Red
    Write-Host "Confirm a SECOND Priority Cleanup Admin (not whoever last edited this policy) has reviewed the simulation results in the portal before proceeding (README.md Section 5)." -ForegroundColor Yellow
    Invoke-Scc -Describe "Set-RetentionCompliancePolicy -Identity '$($cfg.policy.name)' -EnforceSimulationPolicy `$true" `
        -Action { Set-RetentionCompliancePolicy -Identity $cfg.policy.name -EnforceSimulationPolicy $true -Confirm:$false } | Out-Null
    Write-Host "`nDone. Policy is now on. Matching items move to the second-stage Recycle Bin as approvals (where required) complete." -ForegroundColor Cyan
    return
}

if (-not $Simulate -and -not $DryRun) {
    throw "Refusing to deploy without -Simulate (or -DryRun to preview). Unlike the Exchange sibling scenario, there is NO -Enabled-at-creation path here - Microsoft requires simulation to initially set up priority cleanup for SharePoint/OneDrive. See README.md Section 5 and this script's .DESCRIPTION."
}

Write-Host "Deploying SharePoint/OneDrive priority cleanup: label '$($cfg.label.name)' + policy '$($cfg.policy.name)'." -ForegroundColor Cyan
Write-Host "WARNING: overrides existing retention policies and eDiscovery holds; overrides Preservation Lock only if the underlying retention setting is delete-only. Matching items move to the second-stage Recycle Bin (not an instant permanent delete). See README.md Sections 2/11." -ForegroundColor Red

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
        Name                     = $cfg.label.name
        RetentionAction          = $cfg.label.retentionAction
        RetentionDuration        = [int]$cfg.label.retentionDurationDays
        RetentionType            = $cfg.label.retentionType
        MultiStageReviewProperty = $multiStageJson
        PriorityCleanup          = $true
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
    $oneDrive = @($cfg.policy.oneDriveLocation)
    $sharePoint = @($cfg.policy.sharePointLocation)
    if ($oneDrive.Count -eq 0 -and $sharePoint.Count -eq 0) {
        throw "policy.oneDriveLocation and/or policy.sharePointLocation is required (at least one)."
    }
    $polParams = @{
        Name             = $cfg.policy.name
        PriorityCleanup  = $true
        IsSimulation     = $true
    }
    if ($oneDrive.Count -gt 0) { $polParams.OneDriveLocation = $oneDrive }
    if ($sharePoint.Count -gt 0) { $polParams.SharePointLocation = $sharePoint }
    if ($cfg.policy.oneDriveLocationException -and @($cfg.policy.oneDriveLocationException).Count -gt 0) {
        $polParams.OneDriveLocationException = @($cfg.policy.oneDriveLocationException)
    }
    if ($cfg.policy.sharePointLocationException -and @($cfg.policy.sharePointLocationException).Count -gt 0) {
        $polParams.SharePointLocationException = @($cfg.policy.sharePointLocationException)
    }
    if ($cfg.policy.comment) { $polParams.Comment = $cfg.policy.comment }

    $desc = "New-RetentionCompliancePolicy -Name '$($cfg.policy.name)' -OneDriveLocation <$($oneDrive.Count)> -SharePointLocation <$($sharePoint.Count)> -PriorityCleanup -IsSimulation"
    Invoke-Scc -Describe $desc -Action { New-RetentionCompliancePolicy @polParams -Confirm:$false } | Out-Null
    Write-Host "  [policy] created '$($cfg.policy.name)' (SIMULATION MODE - mandatory for this workload)" -ForegroundColor Green
}

# --- 3. Priority cleanup rule (New-RetentionComplianceRule -PriorityCleanup -ApplyComplianceTag) ---
$existingRule = Get-RetentionComplianceRule -PriorityCleanup -Policy $cfg.policy.name -ErrorAction SilentlyContinue | Select-Object -First 1
if ($existingRule) {
    Write-Host "  [rule] exists on policy '$($cfg.policy.name)' (one rule per policy - not modified)." -ForegroundColor DarkGreen
}
else {
    if ([string]::IsNullOrWhiteSpace($cfg.rule.contentMatchQuery)) { throw "rule.contentMatchQuery is required." }
    $ruleParams = @{
        Policy             = $cfg.policy.name
        ApplyComplianceTag = $cfg.label.name
        ContentMatchQuery  = $cfg.rule.contentMatchQuery
        PriorityCleanup    = $true
    }
    Invoke-Scc -Describe "New-RetentionComplianceRule -Policy '$($cfg.policy.name)' -ApplyComplianceTag '$($cfg.label.name)' -ContentMatchQuery '<query>' -PriorityCleanup" `
        -Action { New-RetentionComplianceRule @ruleParams -Confirm:$false } | Out-Null
    Write-Host "  [rule] created (priority cleanup applies '$($cfg.label.name)')" -ForegroundColor Green
}

Write-Host "`nStarting simulation..." -ForegroundColor Cyan
if (-not $DryRun) {
    Invoke-Scc -Describe "Set-RetentionCompliancePolicy -Identity '$($cfg.policy.name)' -StartSimulation `$true" `
        -Action { Set-RetentionCompliancePolicy -Identity $cfg.policy.name -StartSimulation $true -Confirm:$false } | Out-Null
}

Write-Host "`nDone." -ForegroundColor Cyan
Write-Host "Simulation started - results may take up to a couple of hours. Review sample matches in the portal (Data Lifecycle Management > Priority cleanup), then have a SECOND Priority Cleanup Admin re-run this script with -EnforceSimulation. A simulation-mode policy can run for up to 7 days before it must be restarted." -ForegroundColor Yellow
```

#### `Remove-PriorityCleanupSharePointOneDrivePolicy.ps1`

```powershell
#Requires -Version 7.0
<#
.SYNOPSIS
    Rolls back the SharePoint/OneDrive priority cleanup deployment: disables (and optionally
    deletes) the policy/rule. The priority cleanup LABEL itself is intentionally not force-removed.

.DESCRIPTION
    Uses Security & Compliance PowerShell. Staged:
      Default    Disable the policy (Set-RetentionCompliancePolicy -Enabled $false) so it stops
                 identifying NEW items. Items already moved to the second-stage Recycle Bin are
                 unaffected by disabling this policy - from there they follow ordinary
                 SharePoint/OneDrive Recycle Bin retention timers, the same as any other deleted
                 item (this scenario does not use the separate permanent-deletion sub-feature).
                 Items in the pending-approval queue that have not yet completed a required
                 eDiscovery-admin approval are NOT moved by disabling the policy, but Microsoft's
                 own documentation states: "Although you can delete a priority cleanup policy, if
                 the approval process for it is complete, items might still be deleted" - disabling/
                 deleting the POLICY does not reliably stop an in-flight APPROVAL from completing.
                 If items are pending and must not be moved, have every remaining approver decline
                 (Relabel) them in the portal first.
      -Delete    Additionally delete the policy (Remove-RetentionCompliancePolicy) and its rule.

    The retention LABEL is NOT deleted by this script by default - removing a label still applied
    to surviving content changes its retention state and should be a deliberate, reviewed action.

    -WhatIf is non-functional in Security & Compliance PowerShell, so this script implements -DryRun.
    Connect first with Connect-IPPSSession.

.PARAMETER ConfigPath
    Path to the same JSON config used to deploy. Defaults to
    'config/priority-cleanup-sharepoint-onedrive.sample.json'. Only policy.name (and, with
    -TryRemoveLabel, label.name) are read here.

.PARAMETER Delete
    Delete the policy and its rule (not just disable).

.PARAMETER TryRemoveLabel
    Attempt to remove the retention label too (Remove-ComplianceTag). Reports rather than forces if
    the service refuses (e.g. the label is still applied to surviving content).

.PARAMETER DryRun
    Print the intended cmdlets and run none.

.EXAMPLE
    Connect-IPPSSession -AppId $AppId -Certificate $Cert -Organization 'contoso.onmicrosoft.com'
    ./Remove-PriorityCleanupSharePointOneDrivePolicy.ps1 -DryRun

.NOTES
    Grounded in Microsoft Learn: Set-/Remove-RetentionCompliancePolicy, Remove-ComplianceTag;
    priority cleanup approval-completion behavior.
    https://learn.microsoft.com/purview/priority-cleanup-onedrive-sharepoint#limitations-of-priority-cleanup
#>
[CmdletBinding()]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$ConfigPath = (Join-Path $PSScriptRoot 'config/priority-cleanup-sharepoint-onedrive.sample.json'),

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

Write-Host "IMPORTANT: if any items are currently pending eDiscovery-admin approval in the portal (Data Lifecycle Management > Priority cleanup > Pending cleanups), disabling/deleting this policy does NOT reliably stop an in-flight approval from completing. Have the remaining approver decline (Relabel) pending items first if they must not move to the Recycle Bin. See this script's .DESCRIPTION." -ForegroundColor Red

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
Write-Host "Items already moved to the second-stage Recycle Bin by a completed disposal are not restored by this script - recover them from the Recycle Bin (within its retention window) if needed, per rollback.md." -ForegroundColor Yellow
```