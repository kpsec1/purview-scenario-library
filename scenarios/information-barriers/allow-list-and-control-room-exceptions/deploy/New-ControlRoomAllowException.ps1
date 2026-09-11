#Requires -Version 7.0
<#
.SYNOPSIS
    Models allow-list information-barrier topologies - a control-room/compliance segment that must
    see both sides of an existing wall, plus a narrower asymmetric example - as ALLOW-type
    (-SegmentsAllowed) segments and policies, companion to segregate-trading-and-research's
    BLOCK-type wall.

.DESCRIPTION
    Uses the Information Barriers cmdlets in Security & Compliance PowerShell (automation surface 1
    per docs/automation-surface.md):
      1. New-OrganizationSegment      -> one segment per exception group, from an Entra attribute filter
      2. New-InformationBarrierPolicy -> one ALLOW policy per segment (-SegmentsAllowed, created
                                          -State Inactive), naming exactly which other segments it may
                                          reach
      3. (with -Activate) Set-InformationBarrierPolicy -State Active  +
         Start-InformationBarrierPoliciesApplication

    An Allow-type policy is default-deny for its assigned segment: the segment can talk ONLY to the
    segments named in -SegmentsAllowed. This script's sample config models two allow-list shapes:
      - ComplianceControlRoom -> allowed ["Trading","Research"]  (sees BOTH walled sides - the
        classic control-room/compliance exception)
      - Legal                 -> allowed ["Research"]            (a narrower, one-sided allow-list -
        Legal is not on Trading's or ComplianceControlRoom's radar at all)
    Microsoft's own Information Barriers walkthrough documents exactly this composition: a third
    segment (their example: HR) that stays "compatible" with two segments a Block policy keeps apart
    from each other - see README.md Section 11 for the caveat on this composition and reference 1.

    PREREQUISITE: this is a companion to segregate-trading-and-research, not a standalone wall. It
    does not create or touch the 'Trading'/'Research' segments or their block policies - it hard-fails
    if either configured prerequisite segment is missing.

    RECONCILIATION: if a segment/policy of the expected name already exists, the script compares the
    policy's live SegmentsAllowed set to the config's desired set. A drift triggers
    Set-InformationBarrierPolicy -SegmentsAllowed <full desired list> (Microsoft's own edit guidance
    is to set the policy Inactive before editing, then reactivate - this script does that
    automatically for an Active policy that needs a change, and warns because reactivation requires a
    fresh Start-InformationBarrierPoliciesApplication run to take effect - see README.md Section 11
    for the open VERIFY on whether -SegmentsAllowed replaces or merges the list).

    Safe by default: everything is created/updated but left INACTIVE and NOT applied until -Activate.
    -WhatIf is non-functional in Security & Compliance PowerShell, so this script implements its own
    -DryRun.

    Connect first: Connect-IPPSSession (certificate app-only preferred - docs/automation-surface.md
    Section 3). This script does not open the session.

.PARAMETER ConfigPath
    Path to the JSON config. Defaults to 'config/control-room-allow-exceptions.sample.json'.

.PARAMETER Activate
    After creating/reconciling segments and policies, set every policy this config manages Active and
    run Start-InformationBarrierPoliciesApplication to enforce them tenant-wide. Omit to stage
    everything for review first (strongly recommended for a first run, and required practice after
    any -SegmentsAllowed reconciliation).

.PARAMETER DryRun
    Print every mutating cmdlet that would run and invoke none (the working substitute for -WhatIf).

.EXAMPLE
    Connect-IPPSSession -AppId $AppId -Certificate $Cert -Organization 'contoso.onmicrosoft.com'
    ./New-ControlRoomAllowException.ps1 -DryRun

.EXAMPLE
    ./New-ControlRoomAllowException.ps1            # create/reconcile, INACTIVE (no user impact)
    ./New-ControlRoomAllowException.ps1 -Activate  # activate + apply

.NOTES
    Grounded in Microsoft Learn (verify before production use):
    - Get started with Information Barriers - Allow policies, one-policy-per-segment, and the
      HR/Sales/Research worked example of a segment compatible with two mutually-blocked segments:
      https://learn.microsoft.com/purview/information-barriers-policies
    - New-InformationBarrierPolicy -SegmentsAllowed (comma-separated list; cannot combine with
      -SegmentsBlocked): https://learn.microsoft.com/powershell/module/exchangepowershell/new-informationbarrierpolicy
    - Set-InformationBarrierPolicy -SegmentsAllowed/-SegmentsBlocked (editing an existing policy's
      segment list): https://learn.microsoft.com/powershell/module/exchangepowershell/set-informationbarrierpolicy
    - Manage Information Barriers policies - set a policy Inactive before editing it, then reactivate
      and re-apply; you cannot change a policy's type (Allow<->Block) in place:
      https://learn.microsoft.com/purview/information-barriers-edit-segments-policies
    - Use multi-segment support in Information Barriers - configuring ANY Block policy breaks
      MultiSegment mode; this scenario stays in SingleSegment mode (one segment per user) by design,
      so it never needs MultiSegment:
      https://learn.microsoft.com/purview/information-barriers-multi-segment
    - Get-PolicyConfig -InformationBarrierMode (Legacy/SingleSegment/MultiSegment) - in LEGACY mode
      specifically, an Allow policy hides non-IB users/groups from the assigned segment's members;
      SingleSegment and MultiSegment mode do not have this restriction. This script checks and warns
      - see the CAUTION below:
      https://learn.microsoft.com/powershell/module/exchangepowershell/get-policyconfig

    CAUTION (grounded, not a guess): in LEGACY IB mode, assigning an ALLOW policy to a segment hides
    every non-IB user/group from that segment's members (not just the segments left off the allow
    list) - a severe, easy-to-miss collateral impact for a control-room/Legal role that still needs
    to do ordinary work with non-segmented colleagues. SingleSegment and MultiSegment mode do not
    have this restriction. This script checks Get-PolicyConfig and warns loudly if the tenant is in
    Legacy mode; it does not hard-block, because remediation (moving out of Legacy mode) is a
    tenant-wide decision outside this script's scope. See README.md Section 11.

    VERIFY (pilot tenant): whether Set-InformationBarrierPolicy -SegmentsAllowed fully REPLACES the
    policy's allowed-segment list or merges with the existing one. Microsoft's own worked example
    (Set-InformationBarrierPolicy -SegmentsBlocked "HR") shows setting a single new value but does not
    state replace-vs-merge semantics explicitly. This script assumes REPLACE and always sends the
    complete desired list - confirm before relying on partial/incremental updates. See README.md
    Section 11.
#>
[CmdletBinding()]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$ConfigPath = (Join-Path $PSScriptRoot 'config/control-room-allow-exceptions.sample.json'),

    [Parameter()]
    [switch]$Activate,

    [Parameter()]
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

function Assert-SccConnected {
    if (-not (Get-Command Get-OrganizationSegment -ErrorAction SilentlyContinue)) {
        throw "Information Barriers cmdlets not found. Connect first: Connect-IPPSSession. See docs/automation-surface.md Section 3."
    }
}
function Invoke-Scc {
    param([Parameter(Mandatory)][string]$Describe, [Parameter(Mandatory)][scriptblock]$Action)
    if ($DryRun) { Write-Host "  DRYRUN would run: $Describe" -ForegroundColor DarkYellow; return $null }
    Write-Host "  $Describe" -ForegroundColor Green
    return & $Action
}
function Get-PolicyName {
    param([Parameter(Mandatory)][string]$AssignedSegment, [Parameter(Mandatory)][string[]]$Allows)
    return "$AssignedSegment-allow-$($Allows -join '-')"
}
function Compare-SegmentSet {
    # Order-independent, case-insensitive comparison of two segment-name lists.
    param([string[]]$Live, [string[]]$Desired)
    $liveSet = @($Live | ForEach-Object { "$_".Trim() } | Where-Object { $_ } | Sort-Object -Unique)
    $desiredSet = @($Desired | ForEach-Object { "$_".Trim() } | Where-Object { $_ } | Sort-Object -Unique)
    return -not (Compare-Object $liveSet $desiredSet -CaseSensitive:$false)
}

if (-not (Test-Path -LiteralPath $ConfigPath)) { throw "Config file not found: $ConfigPath" }
$cfg = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
if (-not $cfg.segments -or @($cfg.segments).Count -lt 1) { throw "Config needs at least one segment." }
if (-not $cfg.allowPolicies -or @($cfg.allowPolicies).Count -lt 1) { throw "Config needs at least one allowPolicy." }

Assert-SccConnected

# --- Warn on Legacy IB mode: an Allow policy hides non-IB users/groups from the assigned segment's
#     members in Legacy mode only (not SingleSegment/MultiSegment) - a severe collateral impact for
#     a control-room/Legal role that still needs ordinary communication. Non-fatal: remediation is a
#     tenant-wide decision outside this script's scope.
try {
    $policyConfig = Get-PolicyConfig -ErrorAction Stop
    $ibMode = if ($policyConfig.PSObject.Properties['InformationBarrierMode']) { "$($policyConfig.InformationBarrierMode)" } else { $null }
    if ($ibMode -eq 'Legacy') {
        Write-Host "CAUTION: tenant IB mode is 'Legacy'. In Legacy mode, an ALLOW policy hides ALL non-IB users/groups from the assigned segment's members - not just segments left off the allow list. 'ComplianceControlRoom'/'Legal' members could lose the ability to reach ordinary, non-segmented colleagues once activated. Move to SingleSegment mode (Set-PolicyConfig -InformationBarrierMode SingleSegment) first, or confirm this is acceptable, before -Activate. See README.md Section 11." -ForegroundColor Red
    }
    elseif ($ibMode) {
        Write-Host "  [check] Tenant IB mode: $ibMode (Allow policies do not hide non-IB users/groups in this mode)." -ForegroundColor DarkGreen
    }
    else {
        Write-Host "  [WARN] Could not read InformationBarrierMode from Get-PolicyConfig output - confirm tenant IB mode manually before -Activate." -ForegroundColor Yellow
    }
}
catch {
    Write-Host "  [WARN] Get-PolicyConfig failed ($($_.Exception.Message)) - confirm tenant IB mode manually before -Activate." -ForegroundColor Yellow
}

Write-Host "Building allow-list information-barrier exceptions from '$ConfigPath'." -ForegroundColor Cyan
if (-not $Activate) {
    Write-Host "Segments/policies will be created or reconciled INACTIVE and NOT applied (no user impact). Re-run with -Activate to enforce." -ForegroundColor Yellow
}
else {
    Write-Host "WARNING: -Activate will restrict live Teams/SharePoint/OneDrive communication for each assigned segment to ONLY its allowed segments once application completes (~30 min to start, up to 24h for SharePoint). Review with -DryRun and Compliance/Legal first." -ForegroundColor Red
}

# --- 0. Prerequisite segments must already exist (this scenario does not create them) ---
$allSegments = Get-OrganizationSegment -ErrorAction SilentlyContinue
foreach ($reqName in @($cfg.prerequisiteSegments)) {
    $found = $allSegments | Where-Object { $_.Name -eq $reqName } | Select-Object -First 1
    if (-not $found) {
        throw "Prerequisite segment '$reqName' not found. This scenario is a companion to segregate-trading-and-research and expects it to be deployed first - see README.md Section 3."
    }
    Write-Host "  [prerequisite] segment '$reqName' exists." -ForegroundColor DarkGreen
}

# --- 1. Exception segments ---
foreach ($seg in @($cfg.segments)) {
    if (-not $seg.name -or -not $seg.userGroupFilter) { throw "Each segment needs name and userGroupFilter." }
    $existing = $allSegments | Where-Object { $_.Name -eq $seg.name } | Select-Object -First 1
    if ($existing) {
        Write-Host "  [segment] exists '$($seg.name)'" -ForegroundColor DarkGreen
    }
    else {
        Invoke-Scc -Describe "New-OrganizationSegment -Name '$($seg.name)' -UserGroupFilter `"$($seg.userGroupFilter)`"" `
            -Action { New-OrganizationSegment -Name $seg.name -UserGroupFilter $seg.userGroupFilter -Confirm:$false } | Out-Null
        Write-Host "  [segment] created '$($seg.name)'" -ForegroundColor Green
    }
}

# --- 2. Allow policies (create-or-reconcile) ---
$policyNames = [System.Collections.Generic.List[string]]::new()
$reconciled = [System.Collections.Generic.List[string]]::new()
foreach ($pair in @($cfg.allowPolicies)) {
    if (-not $pair.assignedSegment -or -not $pair.allows -or @($pair.allows).Count -lt 1) {
        throw "Each allowPolicy needs assignedSegment and at least one entry in allows."
    }
    $allows = @($pair.allows)
    $polName = Get-PolicyName -AssignedSegment $pair.assignedSegment -Allows $allows
    $policyNames.Add($polName)
    $existing = Get-InformationBarrierPolicy -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq $polName } | Select-Object -First 1

    if (-not $existing) {
        Invoke-Scc -Describe "New-InformationBarrierPolicy -Name '$polName' -AssignedSegment '$($pair.assignedSegment)' -SegmentsAllowed '$($allows -join ',')' -State Inactive" `
            -Action { New-InformationBarrierPolicy -Name $polName -AssignedSegment $pair.assignedSegment -SegmentsAllowed ($allows -join ',') -State Inactive -Confirm:$false } | Out-Null
        Write-Host "  [policy] created '$polName' (Inactive, allows: $($allows -join ', '))" -ForegroundColor Green
        continue
    }

    $liveAllowed = @($existing.SegmentsAllowed)
    if (Compare-SegmentSet -Live $liveAllowed -Desired $allows) {
        Write-Host "  [policy] exists '$polName' (state: $($existing.State); allows already matches config)" -ForegroundColor DarkGreen
        continue
    }

    Write-Host "  [policy] '$polName' allow-list drift: live=[$($liveAllowed -join ', ')] desired=[$($allows -join ', ')]" -ForegroundColor Yellow
    $wasActive = "$($existing.State)" -eq 'Active'
    if ($wasActive) {
        Invoke-Scc -Describe "Set-InformationBarrierPolicy -Identity $($existing.Guid) -State Inactive   # required before editing SegmentsAllowed" `
            -Action { Set-InformationBarrierPolicy -Identity $existing.Guid -State Inactive -Confirm:$false } | Out-Null
    }
    Invoke-Scc -Describe "Set-InformationBarrierPolicy -Identity $($existing.Guid) -SegmentsAllowed '$($allows -join ',')'" `
        -Action { Set-InformationBarrierPolicy -Identity $existing.Guid -SegmentsAllowed ($allows -join ',') -Confirm:$false } | Out-Null
    Write-Host "  [policy] '$polName' reconciled to allows: $($allows -join ', ')$(if ($wasActive) { ' (was Active - now Inactive; re-run with -Activate to reactivate + re-apply)' })" -ForegroundColor Yellow
    $reconciled.Add($polName)
}

# --- 3. (optional) Activate + apply ---
if ($Activate) {
    foreach ($polName in $policyNames) {
        $pol = Get-InformationBarrierPolicy -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq $polName } | Select-Object -First 1
        if ($pol -and "$($pol.State)" -ne 'Active') {
            Invoke-Scc -Describe "Set-InformationBarrierPolicy -Identity $($pol.Guid) -State Active" `
                -Action { Set-InformationBarrierPolicy -Identity $pol.Guid -State Active -Confirm:$false } | Out-Null
            Write-Host "  [activate] '$polName' set Active" -ForegroundColor Yellow
        }
    }
    Invoke-Scc -Describe "Start-InformationBarrierPoliciesApplication" -Action { Start-InformationBarrierPoliciesApplication -Confirm:$false } | Out-Null
    Write-Host "  [apply] tenant-wide application started (~30 min to begin, ~5,000 users/hour)." -ForegroundColor Cyan
}

Write-Host "`nDone." -ForegroundColor Cyan
if ($reconciled.Count -gt 0 -and -not $Activate) {
    Write-Host "$($reconciled.Count) polic$(if ($reconciled.Count -eq 1) { 'y was' } else { 'ies were' }) reconciled and left Inactive. Re-run with -Activate to reactivate and re-apply." -ForegroundColor Yellow
}
if (-not $Activate) {
    Write-Host "Nothing new is enforced yet. Review the segments/policies, then re-run with -Activate. Validate with validate/Test-ControlRoomAllowException.ps1." -ForegroundColor Yellow
}
else {
    Write-Host "Track application with Get-InformationBarrierPoliciesApplicationStatus. Allow up to 24h for SharePoint/OneDrive propagation." -ForegroundColor Yellow
}
