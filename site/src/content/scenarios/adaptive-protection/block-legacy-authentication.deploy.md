---
part: "deploy"
parent: "adaptive-protection/block-legacy-authentication"
---
The scripts and configuration below deploy this scenario. Review them, then run in order — each is designed to be idempotent and has a matching rollback.


#### `New-BlockLegacyAuthenticationPolicy.ps1`

```powershell
#Requires -Version 7.0
<#
.SYNOPSIS
    Checks for Microsoft's own auto-deployed "Block legacy authentication" Microsoft-managed
    Conditional Access policy, then - only if one isn't already covering the tenant, or
    -SkipManagedPolicyCheck is passed - creates or reconciles a custom Conditional Access policy
    that blocks (or, by default, reports on) sign-in attempts using legacy authentication client
    types, following Microsoft's documented "Block legacy authentication with Conditional Access"
    procedure exactly.

.DESCRIPTION
    Deferred from scenarios/adaptive-protection/conditional-access-insider-risk-block (reviews.md,
    Red Team finding: "legacy auth clients may not fully honor the Insider Risk condition") because
    it is a general Conditional Access hardening practice, not specific to that scenario or to
    Adaptive Protection - closes that follow-up as its own standalone scenario.

    IMPORTANT GROUNDING FINDING (design.md Section 3): as of this build, Microsoft auto-deploys a
    Microsoft-managed "Block legacy authentication" Conditional Access policy to eligible tenants
    (Microsoft Entra ID P2 or Microsoft 365 Business Premium) in Report-only state, and auto-enables
    it no less than 30 days later unless an admin acts first. This script does NOT assume a buyer
    needs a brand-new control - it checks for that Microsoft-managed policy first (best-effort, by
    the "Microsoft-managed:" displayName prefix Microsoft's own audit-log guidance documents - see
    .NOTES) and reports its state rather than silently deploying a duplicate. A custom policy
    remains a legitimate, Microsoft-endorsed choice when a buyer needs more control than a
    Microsoft-managed policy allows (narrower Users scope than "all eligible users", a tenant not
    yet eligible for the Microsoft-managed rollout, or wanting the control in place immediately
    rather than on Microsoft's own 30-day timeline) - Microsoft's own guidance explicitly suggests
    "duplicating" a Microsoft-managed policy for exactly this reason.

    What this script creates/reconciles when it proceeds, by fixed displayName lookup (identical
    identity strategy to every other Conditional-Access-based scenario in this library - see
    .NOTES):
      One conditionalAccessPolicy object matching Microsoft's documented procedure exactly:
        - conditions.applications.includeApplications = ["All"]     (Target resources: All resources)
        - conditions.users.includeUsers = ["All"], minus -ExcludeUserIds / -ExcludeGroupIds
        - conditions.clientAppTypes = ["exchangeActiveSync", "other"]  (portal: check ONLY
          "Exchange ActiveSync clients" and "Other clients" - NOT "Browser" or "Mobile apps and
          desktop clients", which are modern-auth client types this scenario deliberately does not
          restrict)
        - grantControls.operator = "OR", grantControls.builtInControls = ["block"]
        - state = -Mode ("ReportOnly" -> enabledForReportingButNotEnforced (default, matches
          Microsoft's own documented Report-only-first rollout), "Enabled" -> enabled,
          "Disabled" -> disabled)

    Idempotent: fetches all Conditional Access policies, matches by -DisplayName, and with -Force
    reconciles conditions/grantControls/state to this run's parameters. Without -Force, an
    already-matching policy is reported and left untouched; a policy found under the same name with
    DIFFERENT conditions/controls is reported as drifted and left untouched unless -Force is also
    passed (never silently overwritten).

.PARAMETER DisplayName
    Conditional Access policy display name. Defaults to 'Block Legacy Authentication (Custom)' -
    deliberately distinct from a Microsoft-managed policy's own "Microsoft-managed: ..." naming
    convention, so this script's own displayName lookup can never collide with (or be mistaken
    for) the policy Microsoft itself may have already deployed.

.PARAMETER ExcludeUserIds
    Object IDs (GUIDs) of emergency-access / break-glass accounts to exclude from this policy's
    Users condition. Also recommended for service accounts/service principals that still depend on
    legacy protocols and cannot yet be migrated (README.md Section 3 / Sources) - note that
    Conditional Access policies scoped to users never apply to service principal sign-ins in the
    first place (Sources), so this exclusion matters only for user accounts used as de-facto
    service accounts. Strongly recommended before -Mode Enabled. This script WARNS but does not
    refuse to proceed if both -ExcludeUserIds and -ExcludeGroupIds are empty, since a
    -Mode ReportOnly deployment (the default) does not block anyone yet.

.PARAMETER ExcludeGroupIds
    Object IDs (GUIDs) of groups to exclude (e.g. a dedicated 'EmergencyAccess' security group).
    Combined with -ExcludeUserIds; either or both may be supplied.

.PARAMETER Mode
    'ReportOnly' (default - maps to Graph state 'enabledForReportingButNotEnforced', evaluates and
    logs sign-in events against this policy without blocking anyone), 'Enabled' (maps to 'enabled'
    - actively blocks), or 'Disabled' (maps to 'disabled' - defined but never evaluated).

.PARAMETER SkipManagedPolicyCheck
    Skip the pre-check for an existing Microsoft-managed "Block legacy authentication" policy and
    proceed directly to creating/reconciling this scenario's own custom policy. Use this when you
    have already reviewed the Microsoft-managed policy (or confirmed the tenant isn't eligible for
    it) and have deliberately decided an independent custom policy is the right choice - see
    design.md Section 3.

.PARAMETER GraphBaseUri
    Graph base URI. Defaults to 'https://graph.microsoft.com/v1.0' - every property this script
    reads or writes (clientAppTypes, applications, users, grantControls, state) is a confirmed
    v1.0, non-beta property (Sources), so no beta endpoint dependency is needed.

.PARAMETER Force
    If a policy matching -DisplayName already exists with different conditions/grantControls/state
    than this run's parameters, reconcile it instead of leaving it untouched.

.PARAMETER WhatIf
    Standard PowerShell ShouldProcess dry-run. Reports the create/update that would be made without
    calling any mutating Graph endpoint.

.EXAMPLE
    Connect-MgGraph -ClientId $AppId -TenantId $TenantId -CertificateThumbprint $Thumbprint
    ./New-BlockLegacyAuthenticationPolicy.ps1 -ExcludeGroupIds '11111111-2222-3333-4444-555555555555' -WhatIf

.EXAMPLE
    # Deploy in Report-only mode (default) after confirming no Microsoft-managed equivalent exists.
    ./New-BlockLegacyAuthenticationPolicy.ps1 -ExcludeGroupIds '11111111-2222-3333-4444-555555555555'

.EXAMPLE
    # Deliberately deploy a custom policy alongside/instead of a Microsoft-managed one already
    # found (e.g. this tenant needs a narrower Users scope than the Microsoft-managed policy
    # supports) - see README.md Section 5 Step 3.
    ./New-BlockLegacyAuthenticationPolicy.ps1 -SkipManagedPolicyCheck -ExcludeGroupIds '11111111-2222-3333-4444-555555555555'

.EXAMPLE
    # Promote to enforcement after a validated Report-only pilot (README.md Section 5, Step 5).
    ./New-BlockLegacyAuthenticationPolicy.ps1 -ExcludeGroupIds '11111111-2222-3333-4444-555555555555' -Mode Enabled -Force

.NOTES
    MICROSOFT-MANAGED POLICY DETECTION IS BEST-EFFORT, NOT A CONFIRMED GRAPH FLAG: the v1.0
    conditionalAccessPolicy resource has no documented boolean property (e.g. "isMicrosoftManaged")
    this script could check directly - the "Created by: Microsoft" distinction is a portal-only
    rendering. The one confirmed, citable signal is Microsoft's own audit-log guidance: "Microsoft-
    managed policy names start with Microsoft-managed:" (Sources). This script therefore matches
    any existing policy whose DisplayName starts with 'Microsoft-managed:' (case-insensitive) AND
    contains 'legacy' (case-insensitive) - tolerant of the exact remainder of Microsoft's own
    display name not being independently confirmed word-for-word during this build (VERIFY,
    README.md Section 11). A tenant that has renamed or duplicated its Microsoft-managed policy
    will not be detected by this heuristic - the manual checklist in
    validate/Test-BlockLegacyAuthenticationPolicy.ps1 exists to catch that.

    IDENTITY BY DISPLAYNAME, NOT A FIXED GUID: same limitation as every other Conditional-Access-
    based scenario in this library (conditional-access-insider-risk-block, conditional-access-
    insider-risk-step-up-auth) - a conditionalAccessPolicy's own 'id' is assigned by Graph on
    creation and cannot be pre-chosen, so this script identifies "the policy this scenario manages"
    by an exact -DisplayName match. Renaming the policy in the portal breaks this script's
    idempotency detection - documented as a known limitation in README.md Section 11.

    Sources (Microsoft Learn, verify before production use):
    - Block legacy authentication with Conditional Access (portal procedure this script automates -
      Users/Target resources/Client apps/Grant/Report-only sequence, sign-in-log identification
      steps): https://learn.microsoft.com/entra/identity/conditional-access/policy-block-legacy-authentication
    - Microsoft-managed Conditional Access policies (auto-deployment, 30-day auto-enable, "Created
      by: Microsoft" and "Microsoft-managed:" naming convention, P2/Business Premium eligibility,
      "duplicate if you need more changes" guidance):
      https://learn.microsoft.com/entra/identity/conditional-access/managed-policies
    - Conditional Access: Conditions - Client apps (clientAppTypes portal categories: Browser,
      Mobile apps and desktop clients, Exchange ActiveSync clients, Other clients):
      https://learn.microsoft.com/entra/identity/conditional-access/concept-conditional-access-conditions
    - conditionalAccessConditionSet resource type (clientAppTypes property, Graph v1.0, values all/
      browser/mobileAppsAndDesktopClients/exchangeActiveSync/easSupported/other):
      https://learn.microsoft.com/graph/api/resources/conditionalaccessconditionset
    - conditionalAccessPolicy resource type (state property: enabled/disabled/
      enabledForReportingButNotEnforced):
      https://learn.microsoft.com/graph/api/resources/conditionalaccesspolicy
    - Create conditionalAccessPolicy (POST /identity/conditionalAccess/policies):
      https://learn.microsoft.com/graph/api/conditionalaccessroot-post-policies
    - Update conditionalAccessPolicy (PATCH, least-privileged permission
      Policy.ReadWrite.ConditionalAccess + Policy.Read.All):
      https://learn.microsoft.com/graph/api/conditionalaccesspolicy-update
    - What is Conditional Access? (License requirements - Microsoft Entra ID P1, not P2, for this
      scenario's non-risk-based condition):
      https://learn.microsoft.com/entra/identity/conditional-access/overview
    - New-/Update-/Get-MgIdentityConditionalAccessPolicy (Microsoft.Graph.Identity.SignIns module):
      https://learn.microsoft.com/powershell/module/microsoft.graph.identity.signins/new-mgidentityconditionalaccesspolicy
      https://learn.microsoft.com/powershell/module/microsoft.graph.identity.signins/update-mgidentityconditionalaccesspolicy
      https://learn.microsoft.com/powershell/module/microsoft.graph.identity.signins/get-mgidentityconditionalaccesspolicy
    - Manage emergency access (break-glass) accounts:
      https://learn.microsoft.com/entra/identity/role-based-access-control/security-emergency-access
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$DisplayName = 'Block Legacy Authentication (Custom)',

    [Parameter()]
    [string[]]$ExcludeUserIds = @(),

    [Parameter()]
    [string[]]$ExcludeGroupIds = @(),

    [Parameter()]
    [ValidateSet('ReportOnly', 'Enabled', 'Disabled')]
    [string]$Mode = 'ReportOnly',

    [Parameter()]
    [switch]$SkipManagedPolicyCheck,

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

Assert-MgConnected

$allPolicies = @(Get-MgIdentityConditionalAccessPolicy -All -ErrorAction Stop)

if (-not $SkipManagedPolicyCheck) {
    Write-Host 'Checking for an existing Microsoft-managed "Block legacy authentication" policy first (best-effort detection - see .NOTES)...' -ForegroundColor Cyan
    $managed = @($allPolicies | Where-Object {
            $_.DisplayName -and $_.DisplayName -imatch '^Microsoft-managed:' -and $_.DisplayName -imatch 'legacy'
        }) | Select-Object -First 1

    if ($managed) {
        Write-Host "  [found] Microsoft-managed policy '$($managed.DisplayName)' already exists (id $($managed.Id), state: $($managed.State))." -ForegroundColor Yellow
        Write-Host '  Microsoft auto-enables a Report-only Microsoft-managed policy no less than 30 days after it first appears, unless an admin acts sooner - see README.md Section 8.' -ForegroundColor Yellow
        Write-Host '  This script is NOT deploying a duplicate custom policy. To manage the Microsoft-managed policy itself (exclude break-glass accounts, change its state), use the Microsoft Entra admin center or PATCH it directly by its own id - out of scope for this script (design.md Section 7).' -ForegroundColor Yellow
        Write-Host '  If you deliberately need an independent custom policy anyway (narrower Users scope, or other changes the Microsoft-managed policy does not allow), re-run with -SkipManagedPolicyCheck.' -ForegroundColor Yellow
        Write-Host "`nDone. No change made (Microsoft-managed policy already covers this control)." -ForegroundColor Cyan
        return
    }
    else {
        Write-Host '  [not found] No Microsoft-managed "Block legacy authentication" policy detected (tenant may not be eligible yet, or none has been deployed) - proceeding to this scenario''s own custom policy.' -ForegroundColor Green
    }
}

Write-Host "Conditional Access - Block legacy authentication: reconciling '$DisplayName' (Mode: $Mode)." -ForegroundColor Cyan

if ($ExcludeUserIds.Count -eq 0 -and $ExcludeGroupIds.Count -eq 0) {
    if ($Mode -eq 'Enabled') {
        Write-Warning 'No -ExcludeUserIds or -ExcludeGroupIds supplied while deploying in -Mode Enabled. A break-glass/emergency-access account, or a user account used as a de-facto service account still dependent on legacy auth, has no exclusion. Strongly recommended: exclude a dedicated emergency-access group before enforcing - see README.md Section 3 and Sources.'
    }
    else {
        Write-Host '  [note] No -ExcludeUserIds/-ExcludeGroupIds supplied. Not blocking yet in -Mode ReportOnly, but add an exclusion before promoting to -Mode Enabled.' -ForegroundColor DarkYellow
    }
}

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
        applications  = [ordered]@{ includeApplications = @('All') }
        users         = $desiredUsers
        clientAppTypes = @('exchangeActiveSync', 'other')
    }
    grantControls = [ordered]@{
        operator        = 'OR'
        builtInControls = @('block')
    }
}

# --- Locate an existing policy by exact displayName (Conditional Access has no client-chosen
#     GUID to key off - see .NOTES) ---
$existing = @($allPolicies) | Where-Object { $_.DisplayName -eq $DisplayName } | Select-Object -First 1

if ($existing) {
    $existingClientAppTypes = @($existing.Conditions.ClientAppTypes)
    $existingIncludeApps = @($existing.Conditions.Applications.IncludeApplications)
    $existingIncludeUsers = @($existing.Conditions.Users.IncludeUsers)
    $existingExcludeUsers = @($existing.Conditions.Users.ExcludeUsers)
    $existingExcludeGroups = @($existing.Conditions.Users.ExcludeGroups)
    $existingBuiltInControls = @($existing.GrantControls.BuiltInControls)
    $existingOperator = $existing.GrantControls.Operator
    $existingState = $existing.State

    $matches = (Test-SameStringSet $existingClientAppTypes @('exchangeActiveSync', 'other')) `
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
        Write-Host "  [drift] '$DisplayName' exists but its conditions/grantControls/state differ from this run's parameters (existing state: $existingState, clientAppTypes: $($existingClientAppTypes -join ', ')). Not modified - pass -Force to reconcile to this run's parameters." -ForegroundColor Yellow
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

Write-Host "`nDone. Run validate/Test-BlockLegacyAuthenticationPolicy.ps1 to verify. Reminder: before promoting to -Mode Enabled, review the Sign-ins using legacy authentication workbook or filter sign-in logs by Client App to confirm the actual impact - see README.md Section 5 Step 2 and Section 7." -ForegroundColor Cyan
```

#### `Remove-BlockLegacyAuthenticationPolicy.ps1`

```powershell
#Requires -Version 7.0
<#
.SYNOPSIS
    Rolls back the custom Conditional Access policy created by
    New-BlockLegacyAuthenticationPolicy.ps1, in stages: disable (default, reversible in seconds),
    step back to Report-only, or permanently delete (-Purge).

.DESCRIPTION
    Mirrors the staged rollback pattern this library's other Conditional-Access-based scenarios use
    (scenarios/adaptive-protection/conditional-access-insider-risk-block/deploy/
    Remove-InsiderRiskConditionalAccessPolicy.ps1) - a live block control affects real users the
    moment it changes state, so this script defaults to the least-destructive action (disable)
    rather than deleting outright.

    THIS SCRIPT ONLY TOUCHES THE CUSTOM POLICY THIS SCENARIO CREATED (matched by -DisplayName). It
    never modifies, disables, or deletes a Microsoft-managed "Block legacy authentication" policy -
    Microsoft's own documentation states organizations can't rename or delete Microsoft-managed
    policies at all, and this scenario does not attempt to (design.md Section 7). If your tenant
    relies on the Microsoft-managed policy instead of this scenario's custom one, manage it directly
    in the Microsoft Entra admin center - see rollback.md.

.PARAMETER DisplayName
    Must match the -DisplayName used at deploy time. Defaults to
    'Block Legacy Authentication (Custom)'.

.PARAMETER ReportOnly
    Step back to Report-only (state = enabledForReportingButNotEnforced) instead of fully
    disabling. Keeps evaluation/sign-in-log visibility while removing the block.

.PARAMETER Purge
    Permanently delete the policy object (Remove-MgIdentityConditionalAccessPolicy). Not
    reversible - re-establishing the control means re-running
    New-BlockLegacyAuthenticationPolicy.ps1 from scratch.

.PARAMETER GraphBaseUri
    Present for symmetry with the deploy script; not used directly (all calls go through the
    Microsoft.Graph.Identity.SignIns cmdlets, which target whatever profile Connect-MgGraph
    established).

.PARAMETER WhatIf
    Standard PowerShell ShouldProcess dry-run.

.EXAMPLE
    Connect-MgGraph -ClientId $AppId -TenantId $TenantId -CertificateThumbprint $Thumbprint
    ./Remove-BlockLegacyAuthenticationPolicy.ps1 -WhatIf

.EXAMPLE
    # Stage 1 - disable (reversible)
    ./Remove-BlockLegacyAuthenticationPolicy.ps1

.EXAMPLE
    # Stage 2 - step back to Report-only instead of a full disable
    ./Remove-BlockLegacyAuthenticationPolicy.ps1 -ReportOnly

.EXAMPLE
    # Stage 3 - permanent removal
    ./Remove-BlockLegacyAuthenticationPolicy.ps1 -Purge

.NOTES
    Sources (Microsoft Learn, verify before production use):
    - Update conditionalAccessPolicy (state property PATCH):
      https://learn.microsoft.com/graph/api/conditionalaccesspolicy-update
    - Delete conditionalAccessPolicy:
      https://learn.microsoft.com/graph/api/conditionalaccesspolicy-delete
    - Remove-MgIdentityConditionalAccessPolicy (Microsoft.Graph.Identity.SignIns):
      https://learn.microsoft.com/powershell/module/microsoft.graph.identity.signins/remove-mgidentityconditionalaccesspolicy
    - Microsoft-managed Conditional Access policies (organizations can't rename or delete a
      Microsoft-managed policy):
      https://learn.microsoft.com/entra/identity/conditional-access/managed-policies
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$DisplayName = 'Block Legacy Authentication (Custom)',

    [Parameter()]
    [switch]$ReportOnly,

    [Parameter()]
    [switch]$Purge,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$GraphBaseUri = 'https://graph.microsoft.com/v1.0'
)

$ErrorActionPreference = 'Stop'

if ($ReportOnly -and $Purge) {
    throw '-ReportOnly and -Purge are mutually exclusive - pick one rollback stage per run.'
}

if (-not (Get-Command Get-MgIdentityConditionalAccessPolicy -ErrorAction SilentlyContinue)) {
    throw 'Microsoft Graph PowerShell SDK not found. Install Microsoft.Graph.Authentication and Microsoft.Graph.Identity.SignIns, then Connect-MgGraph.'
}
if (-not (Get-MgContext -ErrorAction SilentlyContinue)) {
    throw 'Not connected to Microsoft Graph. Run Connect-MgGraph (app-only certificate, Policy.ReadWrite.ConditionalAccess + Policy.Read.All) first.'
}

$existing = @(Get-MgIdentityConditionalAccessPolicy -All -ErrorAction Stop) | Where-Object { $_.DisplayName -eq $DisplayName } | Select-Object -First 1

if (-not $existing) {
    Write-Host "'$DisplayName' not found - nothing to roll back." -ForegroundColor Yellow
    return
}

if ($Purge) {
    if ($PSCmdlet.ShouldProcess($DisplayName, "PERMANENTLY DELETE Conditional Access policy $($existing.Id)")) {
        Remove-MgIdentityConditionalAccessPolicy -ConditionalAccessPolicyId $existing.Id
        Write-Host "  [purged] '$DisplayName' (id $($existing.Id)) permanently deleted. Re-run deploy/New-BlockLegacyAuthenticationPolicy.ps1 to re-establish this control." -ForegroundColor Green
    }
    return
}

$targetState = if ($ReportOnly) { 'enabledForReportingButNotEnforced' } else { 'disabled' }
$body = @{ state = $targetState }

if ($existing.State -eq $targetState) {
    Write-Host "  [no-op] '$DisplayName' is already in state '$targetState'." -ForegroundColor Yellow
    return
}

if ($PSCmdlet.ShouldProcess($DisplayName, "PATCH state -> $targetState")) {
    Update-MgIdentityConditionalAccessPolicy -ConditionalAccessPolicyId $existing.Id -BodyParameter $body | Out-Null
    Write-Host "  [rolled back] '$DisplayName' (id $($existing.Id)) state changed: $($existing.State) -> $targetState." -ForegroundColor Green
}

Write-Host "`nDone. This does not affect any Microsoft-managed 'Block legacy authentication' policy the tenant may also have - see rollback.md." -ForegroundColor Cyan
```