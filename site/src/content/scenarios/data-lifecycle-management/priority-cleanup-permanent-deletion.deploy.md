---
part: "deploy"
parent: "data-lifecycle-management/priority-cleanup-permanent-deletion"
---
The scripts and configuration below deploy this scenario. Review them, then run in order — each is designed to be idempotent and has a matching rollback.


#### `config/priority-cleanup-permanent-deletion.sample.json`

```json
{
  "_comment": "Config for deploy/New-PriorityCleanupPermanentDeletionPolicy.ps1. Author-only reference data - NOT applied to any tenant unless passed to the deploy script without -DryRun. Provisions the SAME underlying priority-cleanup label/policy/rule shape as the priority-cleanup-sharepoint-onedrive sibling scenario - that machinery is shared and confirmed. What this config/script does NOT do: select the 'Delete data permanently' content-disposition option itself. No confirmed PowerShell/Graph parameter exists for that step as of this build (README.md Section 11, design.md Section 4) - it is a portal-wizard-only choice on the 'Choose what to do with the content' page. Read README.md Sections 2, 5, and 11 before deploying.",
  "label": {
    "name": "Priority Cleanup - Permanent Deletion - Confirmed Exposure",
    "comment": "For content already confirmed as a data-exposure incident (e.g. a DSPM for AI oversharing finding - scenarios/dspm-for-ai/copilot-sensitive-data-exposure) where a Recycle Bin recovery window is an unacceptable residual risk. NOT for routine storage reclamation - use the priority-cleanup-sharepoint-onedrive sibling for that. Underlying mechanism per New-ComplianceTag -PriorityCleanup, identical parameter shape to the sibling scenario.",
    "retentionAction": "Delete",
    "retentionDurationDays": 0,
    "retentionType": "TaggedAgeInDays",
    "approvalStages": [
      { "stageName": "EDiscoveryAdmin", "reviewers": ["ediscovery-admin@contoso.com"] }
    ],
    "_labelNote": "Identical construction to the priority-cleanup-sharepoint-onedrive sibling's label, including its two open VERIFY items (RetentionDuration/RetentionType 'as soon as possible' mapping; whether -MultiStageReviewProperty also needs a PriorityCleanupAdmin stage entry) - see that sibling's config _labelNote and this scenario's design.md Section 7 for why the shape is deliberately reused rather than re-derived. This label alone does NOT make matched content permanently deleted instead of Recycle-Bin-bound - see _permanentDeletionNote below."
  },
  "policy": {
    "name": "Priority Cleanup - Permanent Deletion - Confirmed Exposure - SPO-OD",
    "comment": "Static scope, deliberately narrow (named sites/accounts only, no 'All') - unlike the sibling's continual/broad scope, this workload targets specific, already-identified exposed content per incident, not a standing tenant-wide sweep. Widen only with documented justification.",
    "oneDriveLocation": [],
    "oneDriveLocationException": [],
    "sharePointLocation": ["https://contoso.sharepoint.com/sites/finance-shared-reports"],
    "sharePointLocationException": [],
    "_policyNote": "Same -Simulate-only / no -Enabled-at-creation path as the sibling - simulation is mandatory for SharePoint/OneDrive priority cleanup regardless of content-disposition mode. Scope here is intentionally narrow and incident-specific (named site(s)/OneDrive account(s) identified by an upstream oversharing/DLP/eDiscovery finding), not the sibling's tenant-wide 'All' pattern - broadening this scope multiplies the blast radius of an irreversible action."
  },
  "rule": {
    "contentMatchQuery": "REPLACE_WITH_INCIDENT_SPECIFIC_QUERY",
    "_ruleNote": "UNLIKE the sibling scenario, there is no single Microsoft worked-example query for this use case - the driving scenario is an already-identified, incident-specific set of files (e.g. from a DSPM for AI oversharing assessment or a DLP alert), not a generic content-type pattern like 'ProgID:Media AND ProgID:Meeting'. Construct this query the same way an eDiscovery content search query is constructed (same underlying search index per README.md Section 4/6) - e.g. targeting a specific file path, author, or sensitivity-label match for the confirmed-exposed items. Test exhaustively in simulation mode before ever proceeding to the portal's permanent-deletion selection - there is no Recycle Bin recourse if this query is broader than intended (README.md Section 9/11)."
  },
  "_permanentDeletionNote": "After this script provisions the label/policy/rule above and starts simulation, an operator MUST complete the following in the Microsoft Purview portal before this policy actually performs a permanent (non-Recycle-Bin) deletion: open the policy > on the 'Choose what to do with the content' page, select 'Delete data permanently' (see README.md Section 5 Portal path, design.md Section 4). This script cannot perform that step - no confirmed PowerShell/Graph parameter exists for it as of this build. VERIFY (pilot tenant): whether a policy provisioned via this script is even a valid starting point for that portal step, or whether permanent-deletion policies must be created end-to-end through the portal wizard (design.md Section 4).",
  "schemaVersion": "1.0",
  "lastUpdated": "2026-09-09"
}
```

#### `New-PriorityCleanupPermanentDeletionPolicy.ps1`

```powershell
#Requires -Version 7.0
<#
.SYNOPSIS
    Provisions the shared Microsoft Purview Priority Cleanup label/policy/rule (Security &
    Compliance PowerShell) that underlies the SharePoint/OneDrive "permanent deletion" sub-feature -
    then STOPS and prints a mandatory manual step, because no confirmed PowerShell/Graph parameter
    selects "Delete data permanently" as of this build.

.DESCRIPTION
    Same three-cmdlet shape as the priority-cleanup-sharepoint-onedrive sibling scenario, because
    that part of the mechanism is genuinely shared ("under the covers, priority cleanup uses
    retention labels with auto-apply policies"):
      1. New-ComplianceTag             -> the label (-PriorityCleanup; RetentionAction Delete,
                                           RetentionDuration/RetentionType, -MultiStageReviewProperty)
      2. New-RetentionCompliancePolicy -> the policy (-PriorityCleanup; -OneDriveLocation/
                                           -SharePointLocation; -IsSimulation - mandatory, no
                                           -Enabled-at-creation path, same as the sibling)
      3. New-RetentionComplianceRule   -> the rule (-PriorityCleanup -ApplyComplianceTag -ContentMatchQuery)

    WHAT THIS SCRIPT DOES NOT DO, AND WHY: Microsoft's own "Configure permanent deletion" procedure
    describes selecting "Delete data permanently" on the policy wizard's "Choose what to do with the
    content" page as a PORTAL-ONLY step - no PowerShell/Graph example accompanies it anywhere in
    Microsoft's published documentation. This build directly confirmed New-ComplianceTag's
    -RetentionAction parameter accepts only Delete/Keep/KeepAndDelete (no "permanent" value exists)
    for both its Default and PriorityCleanup parameter sets. Rather than guess at an undocumented
    parameter, this script provisions the confirmed, shared object shape and then prints an explicit
    manual next step. See README.md Section 11 and design.md Section 4 for the two open readings of
    whether a PowerShell-provisioned policy is even a valid starting point for that portal step.

    Driving use case: THIS SCENARIO IS FOR CONFIRMED DATA-EXPOSURE INCIDENTS (e.g. a DSPM for AI
    oversharing finding - scenarios/dspm-for-ai/copilot-sensitive-data-exposure - or a DLP alert)
    where a Recycle Bin recovery window is an unacceptable residual risk - NOT routine storage
    reclamation. Use the priority-cleanup-sharepoint-onedrive sibling scenario for that instead.

    Idempotent: each object is located by name via Get-* (using the official -PriorityCleanup filter
    switch) before create; if present it is reported, never silently mutated. Re-running is safe.
    -WhatIf is non-functional in Security & Compliance PowerShell, so this script implements its own
    -DryRun.

    This script does NOT select "Delete data permanently", and does NOT approve pending priority-
    cleanup items - Microsoft publishes no PowerShell or Graph cmdlet for either. See README.md
    Section 5/8/11 and rollback.md.

    Connect first: Connect-IPPSSession (certificate app-only preferred - docs/automation-surface.md
    Section 3). This script does not open the session.

.PARAMETER ConfigPath
    Path to the JSON config. Defaults to
    'config/priority-cleanup-permanent-deletion.sample.json'.

.PARAMETER Simulate
    Create the policy in simulation mode (-IsSimulation), then start the simulation
    (Set-RetentionCompliancePolicy -StartSimulation $true). This is the ONLY supported way to create
    the policy - mandatory for SharePoint/OneDrive priority cleanup regardless of content-disposition
    mode.

.PARAMETER EnforceSimulation
    For a policy already created with -Simulate, AND after an operator has completed the portal-only
    "Delete data permanently" selection (see .DESCRIPTION): call
    Set-RetentionCompliancePolicy -EnforceSimulationPolicy $true to turn the reviewed simulation into
    a live, enforced policy. Run this only after a SECOND Priority Cleanup Admin (not whoever last
    edited the policy) has reviewed the simulation results in the portal. This script cannot verify
    either the portal-only content-disposition selection or the "different admin" requirement itself
    (no documented API for either).

.PARAMETER DryRun
    Print every mutating cmdlet that would run and invoke none (the working substitute for -WhatIf,
    which does not function in Security & Compliance PowerShell).

.EXAMPLE
    Connect-IPPSSession -AppId $AppId -Certificate $Cert -Organization 'contoso.onmicrosoft.com'
    ./New-PriorityCleanupPermanentDeletionPolicy.ps1 -Simulate -DryRun

.EXAMPLE
    Connect-IPPSSession -AppId $AppId -Certificate $Cert -Organization 'contoso.onmicrosoft.com'
    ./New-PriorityCleanupPermanentDeletionPolicy.ps1 -Simulate
    # ... complete the MANDATORY portal-only step this script prints: open the policy in the Purview
    #     portal and select "Delete data permanently" on the "Choose what to do with the content"
    #     page ... wait for simulation results ... get a SECOND priority cleanup admin to review
    #     them in the portal ...
    ./New-PriorityCleanupPermanentDeletionPolicy.ps1 -EnforceSimulation

.NOTES
    Grounded in Microsoft Learn (verify before production use):
    - Permanently delete files with Microsoft Purview Priority Cleanup (the permanent-deletion
      sub-feature; portal-only "Choose what to do with the content" step; public preview rollout
      begins 2026-08-24; PriorityCleanupFileDeleted audit operation):
      https://learn.microsoft.com/purview/priority-cleanup-permanent-deletion
    - Override holds to clean up files for Copilot and reclaim storage (shared base priority-cleanup
      mechanism, roles, approver model, mandatory simulation for SharePoint/OneDrive):
      https://learn.microsoft.com/purview/priority-cleanup-onedrive-sharepoint
    - New-ComplianceTag (-PriorityCleanup parameter set; -RetentionAction accepts only
      Delete/Keep/KeepAndDelete - no "permanent" value - confirmed directly against this reference
      during this build):
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
      validate/Test-PriorityCleanupPermanentDeletionPolicy.ps1):
      https://learn.microsoft.com/powershell/module/exchangepowershell/get-compliancetag
      https://learn.microsoft.com/powershell/module/exchangepowershell/get-retentioncompliancepolicy
      https://learn.microsoft.com/powershell/module/exchangepowershell/get-retentioncompliancerule
#>
[CmdletBinding()]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$ConfigPath = (Join-Path $PSScriptRoot 'config/priority-cleanup-permanent-deletion.sample.json'),

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
if ($cfg.rule.contentMatchQuery -eq 'REPLACE_WITH_INCIDENT_SPECIFIC_QUERY') {
    throw "rule.contentMatchQuery is still the sample placeholder - this scenario has no generic worked-example query (unlike the sibling scenario's 'ProgID:Media AND ProgID:Meeting'). Replace it with a query scoped to the confirmed, incident-specific exposed content before deploying. See config _ruleNote."
}

if ($EnforceSimulation) {
    Write-Host "Enforcing simulation for priority cleanup policy '$($cfg.policy.name)' - turning it ON." -ForegroundColor Red
    Write-Host "STOP: confirm BOTH of the following before proceeding, neither of which this script can verify:" -ForegroundColor Yellow
    Write-Host "  1. A SECOND Priority Cleanup Admin (not whoever last edited this policy) has reviewed the simulation results in the portal." -ForegroundColor Yellow
    Write-Host "  2. The portal-only 'Delete data permanently' option has been selected on this policy's 'Choose what to do with the content' page - otherwise turning this policy on moves matching items to the second-stage Recycle Bin (the SIBLING scenario's outcome), NOT a permanent deletion. This script cannot select or verify that choice (README.md Section 11, design.md Section 4)." -ForegroundColor Yellow
    Invoke-Scc -Describe "Set-RetentionCompliancePolicy -Identity '$($cfg.policy.name)' -EnforceSimulationPolicy `$true" `
        -Action { Set-RetentionCompliancePolicy -Identity $cfg.policy.name -EnforceSimulationPolicy $true -Confirm:$false } | Out-Null
    Write-Host "`nDone. Policy is now on. Verify actual behavior post-hoc via the audit log - see README.md Section 7 (PriorityCleanupFileDeleted vs PriorityCleanupFileRecycled)." -ForegroundColor Cyan
    return
}

if (-not $Simulate -and -not $DryRun) {
    throw "Refusing to deploy without -Simulate (or -DryRun to preview). Simulation is mandatory for SharePoint/OneDrive priority cleanup regardless of content-disposition mode. See README.md Section 5 and this script's .DESCRIPTION."
}

Write-Host "Deploying priority cleanup base objects for PERMANENT DELETION: label '$($cfg.label.name)' + policy '$($cfg.policy.name)'." -ForegroundColor Cyan
Write-Host "WARNING: this is the base object shape only. It does NOT, by itself, configure permanent deletion - see .DESCRIPTION and the manual step printed at the end of this run." -ForegroundColor Red
Write-Host "WARNING: this feature's terminal state, once fully configured and approved, is IRREVERSIBLE - content is not recoverable, unlike the priority-cleanup-sharepoint-onedrive sibling's Recycle Bin outcome. See README.md Sections 2/9/11." -ForegroundColor Red

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
        Name            = $cfg.policy.name
        PriorityCleanup = $true
        IsSimulation    = $true
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
    $ruleParams = @{
        Policy             = $cfg.policy.name
        ApplyComplianceTag = $cfg.label.name
        ContentMatchQuery  = $cfg.rule.contentMatchQuery
        PriorityCleanup    = $true
    }
    Invoke-Scc -Describe "New-RetentionComplianceRule -Policy '$($cfg.policy.name)' -ApplyComplianceTag '$($cfg.label.name)' -ContentMatchQuery '<incident-specific query>' -PriorityCleanup" `
        -Action { New-RetentionComplianceRule @ruleParams -Confirm:$false } | Out-Null
    Write-Host "  [rule] created (priority cleanup applies '$($cfg.label.name)')" -ForegroundColor Green
}

Write-Host "`nStarting simulation..." -ForegroundColor Cyan
if (-not $DryRun) {
    Invoke-Scc -Describe "Set-RetentionCompliancePolicy -Identity '$($cfg.policy.name)' -StartSimulation `$true" `
        -Action { Set-RetentionCompliancePolicy -Identity $cfg.policy.name -StartSimulation $true -Confirm:$false } | Out-Null
}

Write-Host "`n=== MANDATORY MANUAL STEP (no CLI/Graph equivalent found) ===" -ForegroundColor Red
Write-Host "In the Microsoft Purview portal, open policy '$($cfg.policy.name)' (Data Lifecycle Management > Priority cleanup)" -ForegroundColor Yellow
Write-Host "and, on the 'Choose what to do with the content' page, select 'Delete data permanently'." -ForegroundColor Yellow
Write-Host "Without this step, this policy behaves like the priority-cleanup-sharepoint-onedrive sibling: matching items move to" -ForegroundColor Yellow
Write-Host "the second-stage Recycle Bin, NOT a permanent, unrecoverable deletion. See README.md Section 5/11 and design.md Section 4." -ForegroundColor Yellow
Write-Host "===============================================================`n" -ForegroundColor Red
Write-Host "Simulation started - results may take up to a couple of hours. Review sample matches in the portal, complete the manual step above, then have a SECOND Priority Cleanup Admin re-run this script with -EnforceSimulation." -ForegroundColor Yellow
```

#### `Remove-PriorityCleanupPermanentDeletionPolicy.ps1`

```powershell
#Requires -Version 7.0
<#
.SYNOPSIS
    Rolls back the priority-cleanup-permanent-deletion deployment: disables (and optionally deletes)
    the policy/rule. The priority cleanup LABEL itself is intentionally not force-removed.

.DESCRIPTION
    Uses Security & Compliance PowerShell. Staged, identical mechanism to the
    priority-cleanup-sharepoint-onedrive sibling's rollback script:
      Default    Disable the policy (Set-RetentionCompliancePolicy -Enabled $false) so it stops
                 identifying NEW items.
      -Delete    Additionally delete the policy (Remove-RetentionCompliancePolicy) and its rule.

    CRITICAL DIFFERENCE FROM THE SIBLING SCENARIO: if this policy was successfully configured for
    permanent deletion (the portal-only step neither this script nor the deploy script can perform
    or verify - see README.md Section 11) and an approval has already completed, disabling or
    deleting the policy does NOT undo that deletion. Unlike the sibling's Recycle-Bin outcome, there
    is NO recovery path once permanent deletion has occurred - this script can only stop the policy
    from identifying and disposing of FURTHER items going forward.

    -WhatIf is non-functional in Security & Compliance PowerShell, so this script implements -DryRun.
    Connect first with Connect-IPPSSession.

.PARAMETER ConfigPath
    Path to the same JSON config used to deploy. Defaults to
    'config/priority-cleanup-permanent-deletion.sample.json'. Only policy.name (and, with
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
    ./Remove-PriorityCleanupPermanentDeletionPolicy.ps1 -DryRun

.NOTES
    Grounded in Microsoft Learn: Set-/Remove-RetentionCompliancePolicy, Remove-ComplianceTag;
    permanent deletion's own irreversibility statement ("no longer discoverable... after deletion").
    https://learn.microsoft.com/purview/priority-cleanup-permanent-deletion
    https://learn.microsoft.com/purview/priority-cleanup-onedrive-sharepoint#prerequisites-for-priority-cleanup
#>
[CmdletBinding()]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$ConfigPath = (Join-Path $PSScriptRoot 'config/priority-cleanup-permanent-deletion.sample.json'),

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

Write-Host "CRITICAL: this policy's terminal state, if fully configured for permanent deletion, is IRREVERSIBLE." -ForegroundColor Red
Write-Host "Disabling/deleting the policy below stops it identifying and disposing of FURTHER items - it does NOT restore anything already permanently deleted. If items are currently pending eDiscovery-admin approval in the portal (Data Lifecycle Management > Priority cleanup > Pending cleanups), have the remaining approver decline (Relabel) them FIRST if they must not be deleted - disabling/deleting this policy does not reliably stop an in-flight approval from completing." -ForegroundColor Red

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
Write-Host "Search the audit log for 'PriorityCleanupFileDeleted' events under this policy's Cleanup ID to determine exactly what, if anything, was already permanently deleted before this rollback - see rollback.md." -ForegroundColor Yellow
```