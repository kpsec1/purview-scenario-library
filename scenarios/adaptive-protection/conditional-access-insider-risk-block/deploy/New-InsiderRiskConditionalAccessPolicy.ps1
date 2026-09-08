#Requires -Version 7.0
<#
.SYNOPSIS
    Creates or reconciles a Microsoft Entra Conditional Access policy that blocks (or, by
    default, reports on) access for users Microsoft Purview Adaptive Protection has assigned
    an insider risk level to, using the Microsoft Graph v1.0
    conditionalAccessConditionSet.insiderRiskLevels condition.

.DESCRIPTION
    Deferred from scenarios/adaptive-protection/dynamic-risk-dlp-enforcement (design.md Section 7)
    because it is a different admin surface entirely - Microsoft Entra Conditional Access, not
    Purview/Exchange Online - with its own license prerequisite (Microsoft Entra ID P2) that
    scenario's DLP-only design does not otherwise require. This fragment closes that follow-up.

    This scenario does NOT create or configure an Insider Risk Management policy, and does NOT
    turn on Adaptive Protection or define its insider risk level thresholds - both remain
    portal-only prerequisites owned by scenarios/insider-risk/departing-employee-data-theft (or
    Microsoft's built-in Data leaks template) and Purview portal > Insider Risk Management >
    Adaptive protection, exactly as documented for the sibling DLP scenario. This script only
    authors the Conditional Access side: a policy whose CONDITION references the live insider
    risk level Adaptive Protection assigns, and whose GRANT CONTROL blocks access when it matches.

    What this script creates/reconciles, by fixed displayName lookup (Conditional Access has no
    documented stable-GUID-on-create convention this library's other Graph-based scripts rely on,
    so identity here is by displayName - see .NOTES):
      One conditionalAccessPolicy object:
        - conditions.applications.includeApplications = ["All"]   (Target resources: All resources)
        - conditions.users.includeUsers = ["All"], minus -ExcludeUserIds / -ExcludeGroupIds
        - conditions.insiderRiskLevels = -RiskLevels (Graph v1.0 conditionalAccessConditionSet
          property - confirmed independently on Microsoft Learn; distinct from, and NOT the same
          parameter as, the Purview DLP sibling's -SharedByIRMUserRisk GUID-based condition - see
          design.md Section 4 for why the two surfaces use different value shapes for the same
          underlying risk level)
        - grantControls.operator = "OR", grantControls.builtInControls = ["block"]
        - state = -Mode ("ReportOnly" -> enabledForReportingButNotEnforced (default, matches
          Microsoft's own documented rollout recommendation), "Enabled" -> enabled,
          "Disabled" -> disabled)

    Idempotent: fetches all Conditional Access policies, matches by -DisplayName, and with -Force
    reconciles conditions/grantControls/state to this run's parameters. Without -Force, an
    already-matching policy is reported and left untouched; a policy found under the same name
    with DIFFERENT conditions/controls is reported as drifted and left untouched unless -Force is
    also passed (never silently overwritten).

.PARAMETER DisplayName
    Conditional Access policy display name. Defaults to
    'Adaptive Protection - Block Elevated Insider Risk (Custom)' - deliberately distinct from
    Microsoft's own Quick Setup wizard's auto-generated Conditional Access policy name (the exact
    auto-generated string was not independently confirmed during this build - VERIFY, see
    README.md Section 11 - so this script does not assert or compare against it).

.PARAMETER RiskLevels
    One or more of 'elevated', 'moderate', 'minor' (Graph's conditionalAccessInsiderRiskLevels
    enum values). Defaults to @('elevated') only, matching the single risk level Microsoft's own
    "Block access for users with elevated insider risk" guide documents end-to-end. Passing
    'moderate'/'minor' here means EVERY selected level gets the SAME grant control (block) - this
    script has no per-level differentiation (unlike the DLP sibling's two-rule
    block/audit split), because Conditional Access grant controls apply per-policy, not per
    condition value. To reproduce the DLP sibling's audit-only treatment of Moderate/Minor,
    deploy a second policy in this scenario's -Mode ReportOnly state scoped to those levels
    instead of adding them here - see README.md Section 6.

.PARAMETER ExcludeUserIds
    Object IDs (GUIDs) of emergency-access / break-glass accounts to exclude from this policy's
    Users condition. Strongly recommended before -Mode Enabled - a blocked break-glass account is
    a documented Microsoft Entra Conditional Access deployment risk independent of this scenario
    (see README.md Section 3 / .NOTES). This script WARNS but does not refuse to proceed if both
    -ExcludeUserIds and -ExcludeGroupIds are empty, since a -Mode ReportOnly deployment (the
    default) does not block anyone yet.

.PARAMETER ExcludeGroupIds
    Object IDs (GUIDs) of groups to exclude (e.g. a dedicated 'EmergencyAccess' security group per
    Microsoft's documented break-glass pattern - .NOTES). Combined with -ExcludeUserIds; either or
    both may be supplied.

.PARAMETER Mode
    'ReportOnly' (default - maps to Graph state 'enabledForReportingButNotEnforced', evaluates and
    logs sign-in events against this policy without blocking anyone), 'Enabled' (maps to 'enabled'
    - actively blocks), or 'Disabled' (maps to 'disabled' - defined but never evaluated).

.PARAMETER GraphBaseUri
    Graph base URI. Defaults to 'https://graph.microsoft.com/v1.0' (this script targets the
    v1.0 endpoint deliberately - conditionalAccessConditionSet.insiderRiskLevels is a confirmed
    v1.0, non-beta property, so no beta endpoint dependency is needed - see README.md Section 12).

.PARAMETER Force
    If a policy matching -DisplayName already exists with different conditions/grantControls/
    state than this run's parameters, reconcile it instead of leaving it untouched.

.PARAMETER WhatIf
    Standard PowerShell ShouldProcess dry-run. Reports the create/update that would be made
    without calling any mutating Graph endpoint.

.EXAMPLE
    Connect-MgGraph -ClientId $AppId -TenantId $TenantId -CertificateThumbprint $Thumbprint
    ./New-InsiderRiskConditionalAccessPolicy.ps1 -ExcludeGroupIds '11111111-2222-3333-4444-555555555555' -WhatIf

.EXAMPLE
    # Deploy in Report-only mode (default) - the same posture Microsoft recommends validating in
    # before enforcement, and the same default posture this library's sibling DLP scenario uses.
    ./New-InsiderRiskConditionalAccessPolicy.ps1 -ExcludeGroupIds '11111111-2222-3333-4444-555555555555'

.EXAMPLE
    # Promote to enforcement after a validated Report-only pilot (README.md Section 5, Step 6).
    ./New-InsiderRiskConditionalAccessPolicy.ps1 -ExcludeGroupIds '11111111-2222-3333-4444-555555555555' -Mode Enabled -Force

.NOTES
    IDENTITY BY DISPLAYNAME, NOT A FIXED GUID: unlike this library's other Graph-based device-
    control scripts (which own a fixed object GUID they mint themselves inside a JSON payload
    they control), a conditionalAccessPolicy's own 'id' is assigned by Graph on creation and
    cannot be pre-chosen - so this script, like Microsoft's own documented examples, identifies
    "the policy this scenario manages" by an exact -DisplayName match. A buyer who renames the
    policy in the portal breaks this script's idempotency detection - documented as a known
    limitation in README.md Section 11, not silently worked around.

    Sources (Microsoft Learn, verify before production use):
    - Block access for users with elevated insider risk (portal steps, Users/Target
      resources/Insider Risk condition/Grant/Report-only sequence this script automates):
      https://learn.microsoft.com/entra/identity/conditional-access/policy-risk-based-insider-block
    - conditionalAccessConditionSet resource type (insiderRiskLevels property, v1.0, values
      minor/moderate/elevated/unknownFutureValue):
      https://learn.microsoft.com/graph/api/resources/conditionalaccessconditionset
    - conditionalAccessPolicy resource type (state property: enabled/disabled/
      enabledForReportingButNotEnforced; conditions/grantControls properties):
      https://learn.microsoft.com/graph/api/resources/conditionalaccesspolicy
    - Create conditionalAccessPolicy (POST /identity/conditionalAccess/policies):
      https://learn.microsoft.com/graph/api/conditionalaccessroot-post-policies
    - Update conditionalAccessPolicy (PATCH, least-privileged permission
      Policy.ReadWrite.ConditionalAccess + Policy.Read.All):
      https://learn.microsoft.com/graph/api/conditionalaccesspolicy-update
    - New-MgIdentityConditionalAccessPolicy / Update-MgIdentityConditionalAccessPolicy /
      Get-MgIdentityConditionalAccessPolicy (Microsoft.Graph.Identity.SignIns module,
      -BodyParameter hashtable pattern):
      https://learn.microsoft.com/powershell/module/microsoft.graph.identity.signins/new-mgidentityconditionalaccesspolicy
      https://learn.microsoft.com/powershell/module/microsoft.graph.identity.signins/update-mgidentityconditionalaccesspolicy
      https://learn.microsoft.com/powershell/module/microsoft.graph.identity.signins/get-mgidentityconditionalaccesspolicy
    - Manage emergency access (break-glass) accounts (exclusion pattern this script's
      -ExcludeUserIds/-ExcludeGroupIds parameters implement):
      https://learn.microsoft.com/entra/identity/role-based-access-control/security-emergency-access
    - Protect your tenant with Insider Risk in Conditional Access (Entra ID P2 licensing
      requirement, Insider Risk Management/Insider Risk Management Admins + Conditional Access
      Administrator role prerequisites):
      https://learn.microsoft.com/entra/identity/monitoring-health/recommendation-insider-risk-condition
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$DisplayName = 'Adaptive Protection - Block Elevated Insider Risk (Custom)',

    [Parameter()]
    [ValidateSet('elevated', 'moderate', 'minor')]
    [string[]]$RiskLevels = @('elevated'),

    [Parameter()]
    [string[]]$ExcludeUserIds = @(),

    [Parameter()]
    [string[]]$ExcludeGroupIds = @(),

    [Parameter()]
    [ValidateSet('ReportOnly', 'Enabled', 'Disabled')]
    [string]$Mode = 'ReportOnly',

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$GraphBaseUri = 'https://graph.microsoft.com/v1.0',

    [Parameter()]
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

$script:StateMap = @{
    ReportOnly = 'enabledForReportingButNotEnforced'
    Enabled    = 'enabled'
    Disabled   = 'disabled'
}

function Assert-MgConnected {
    if (-not (Get-Command Get-MgIdentityConditionalAccessPolicy -ErrorAction SilentlyContinue)) {
        throw 'Microsoft Graph PowerShell SDK not found. Install Microsoft.Graph.Authentication and Microsoft.Graph.Identity.SignIns, then Connect-MgGraph.'
    }
    if (-not (Get-MgContext -ErrorAction SilentlyContinue)) {
        throw 'Not connected to Microsoft Graph. Run Connect-MgGraph (app-only certificate, Policy.ReadWrite.ConditionalAccess + Policy.Read.All - see docs/automation-surface.md Section 3 and README.md Section 3) first.'
    }
}

function ConvertTo-SortedLower {
    param([string[]]$Values)
    @($Values | ForEach-Object { $_.ToString().ToLowerInvariant() } | Sort-Object)
}

function Test-SameStringSet {
    param([string[]]$A, [string[]]$B)
    $sa = @(ConvertTo-SortedLower $A)
    $sb = @(ConvertTo-SortedLower $B)
    if ($sa.Count -ne $sb.Count) { return $false }
    for ($i = 0; $i -lt $sa.Count; $i++) { if ($sa[$i] -ne $sb[$i]) { return $false } }
    return $true
}

if ($ExcludeUserIds.Count -eq 0 -and $ExcludeGroupIds.Count -eq 0) {
    if ($Mode -eq 'Enabled') {
        Write-Warning 'No -ExcludeUserIds or -ExcludeGroupIds supplied while deploying in -Mode Enabled. A break-glass/emergency-access account with no exclusion could be blocked if it is ever assigned an insider risk level. Strongly recommended: exclude a dedicated emergency-access group before enforcing - see README.md Section 3 and Sources.'
    }
    else {
        Write-Host '  [note] No -ExcludeUserIds/-ExcludeGroupIds supplied. Not blocking yet in -Mode ReportOnly, but add an exclusion before promoting to -Mode Enabled.' -ForegroundColor DarkYellow
    }
}

Assert-MgConnected
Write-Host "Insider Risk Conditional Access policy: reconciling '$DisplayName' (Mode: $Mode, RiskLevels: $($RiskLevels -join ', '))." -ForegroundColor Cyan

$desiredState = $script:StateMap[$Mode]
$desiredUsers = [ordered]@{
    includeUsers = @('All')
}
if ($ExcludeUserIds.Count -gt 0) { $desiredUsers.excludeUsers = @($ExcludeUserIds) }
if ($ExcludeGroupIds.Count -gt 0) { $desiredUsers.excludeGroups = @($ExcludeGroupIds) }

$desiredBody = [ordered]@{
    displayName = $DisplayName
    state       = $desiredState
    conditions  = [ordered]@{
        applications      = [ordered]@{ includeApplications = @('All') }
        users             = $desiredUsers
        insiderRiskLevels = @($RiskLevels | ForEach-Object { $_.ToString().ToLowerInvariant() })
    }
    grantControls = [ordered]@{
        operator        = 'OR'
        builtInControls = @('block')
    }
}

# --- Locate an existing policy by exact displayName (Conditional Access has no client-chosen
#     GUID to key off - see .NOTES) ---
$existing = @(Get-MgIdentityConditionalAccessPolicy -All -ErrorAction Stop) | Where-Object { $_.DisplayName -eq $DisplayName } | Select-Object -First 1

if ($existing) {
    $existingRiskLevels = @($existing.Conditions.InsiderRiskLevels)
    $existingIncludeApps = @($existing.Conditions.Applications.IncludeApplications)
    $existingIncludeUsers = @($existing.Conditions.Users.IncludeUsers)
    $existingExcludeUsers = @($existing.Conditions.Users.ExcludeUsers)
    $existingExcludeGroups = @($existing.Conditions.Users.ExcludeGroups)
    $existingBuiltInControls = @($existing.GrantControls.BuiltInControls)
    $existingOperator = $existing.GrantControls.Operator
    $existingState = $existing.State

    $matches = (Test-SameStringSet $existingRiskLevels $desiredBody.conditions.insiderRiskLevels) `
        -and (Test-SameStringSet $existingIncludeApps @('All')) `
        -and (Test-SameStringSet $existingIncludeUsers @('All')) `
        -and (Test-SameStringSet $existingExcludeUsers $ExcludeUserIds) `
        -and (Test-SameStringSet $existingExcludeGroups $ExcludeGroupIds) `
        -and (Test-SameStringSet $existingBuiltInControls @('block')) `
        -and ($existingOperator -eq 'OR') `
        -and ($existingState -eq $desiredState)

    if ($matches -and -not $Force) {
        Write-Host "  [coverage] '$DisplayName' already matches this run's parameters (state: $existingState) - not modified. Pass -Force to reconcile anyway." -ForegroundColor Yellow
        Write-Host "`nDone. No change made." -ForegroundColor Cyan
        return
    }
    if (-not $matches -and -not $Force) {
        Write-Host "  [drift] '$DisplayName' exists but its conditions/grantControls/state differ from this run's parameters (existing state: $existingState, risk levels: $($existingRiskLevels -join ', ')). Not modified - pass -Force to reconcile to this run's parameters." -ForegroundColor Yellow
        Write-Host "`nDone. No change made (drift detected, -Force not passed)." -ForegroundColor Cyan
        return
    }

    if ($PSCmdlet.ShouldProcess($DisplayName, "Update Conditional Access policy $($existing.Id) (PATCH /identity/conditionalAccess/policies/$($existing.Id))")) {
        Update-MgIdentityConditionalAccessPolicy -ConditionalAccessPolicyId $existing.Id -BodyParameter $desiredBody | Out-Null
        Write-Host "  [reconciled] '$DisplayName' updated (id $($existing.Id)) - state now $desiredState." -ForegroundColor Green
    }
}
else {
    if ($PSCmdlet.ShouldProcess($DisplayName, 'Create Conditional Access policy (POST /identity/conditionalAccess/policies)')) {
        $created = New-MgIdentityConditionalAccessPolicy -BodyParameter $desiredBody
        Write-Host "  [created] '$DisplayName' created (id $($created.Id)) - state $desiredState." -ForegroundColor Green
    }
}

Write-Host "`nDone. Run validate/Test-InsiderRiskConditionalAccessPolicy.ps1 to verify. Reminder: this policy only evaluates a user's insider risk level once Adaptive Protection is turned on and has had up to 36 hours to assign it - see README.md Section 11 (same propagation delay the DLP sibling scenario documents)." -ForegroundColor Cyan
