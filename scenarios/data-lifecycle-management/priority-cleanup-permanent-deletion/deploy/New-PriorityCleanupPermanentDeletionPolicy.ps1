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
