---
part: "deploy"
parent: "adaptive-protection/conditional-access-insider-risk-step-up-auth"
---
The scripts and configuration below deploy this scenario. Review them, then run in order — each is designed to be idempotent and has a matching rollback.


#### `New-InsiderRiskStepUpPolicies.ps1`

```powershell
#Requires -Version 7.0
<#
.SYNOPSIS
    Creates or reconciles the two Conditional Access policies Microsoft's own "Adaptive Protection
    configuration guide" documents for Moderate and Minor insider risk levels: a Terms of Use
    requirement scoped to Microsoft Admin Portals (Moderate), and a permanently Report-only
    visibility policy (Minor).

.DESCRIPTION
    Companion to scenarios/adaptive-protection/conditional-access-insider-risk-block (the Elevated
    risk level's own block policy) - deferred from that scenario's design.md Section 6 because
    Conditional Access grant controls apply per-policy, not per-condition-value, so a graduated
    response needs independently-scoped policies. See design.md Section 3 for why this script does
    NOT use "require MFA / require compliant device" (an earlier, unverified guess) and instead
    reproduces Microsoft's own documented Moderate/Minor pairing exactly.

    What this script creates/reconciles, by fixed displayName lookup (same identity strategy as
    the Elevated sibling - Conditional Access has no client-chosen GUID on create):

    1. MODERATE policy (skippable with -SkipModeratePolicy; requires -AgreementId):
        - conditions.applications.includeApplications = ['MicrosoftAdminPortals']
        - conditions.users.includeUsers = ['All'], minus -ExcludeUserIds / -ExcludeGroupIds
        - conditions.insiderRiskLevels = -ModerateRiskLevels (default @('moderate'))
        - grantControls.operator = 'OR', grantControls.termsOfUse = [-AgreementId]
        - state = -ModerateMode ('ReportOnly' (default) / 'Enabled' / 'Disabled')

    2. MINOR policy (skippable with -SkipMinorPolicy):
        - conditions.applications.includeApplications = ['All']
        - conditions.users.includeUsers = ['All'], minus -ExcludeUserIds / -ExcludeGroupIds
        - conditions.insiderRiskLevels = -MinorRiskLevels (default @('minor'))
        - grantControls.operator = 'OR', grantControls.builtInControls = ['mfa'] (a payload
          container ONLY, deliberately NOT 'block' - see design.md Section 6 "Minor risk grant
          control" row: if this policy's state were ever changed to 'enabled' outside this
          scenario's own scripts (e.g. a manual portal edit), 'mfa' fails safe to "prompt for a
          second factor" rather than 'block''s "lock out every Minor-risk user tenant-wide." This
          policy's state can NEVER be 'Enabled' via this script - see -MinorMode below - but the
          container's own worst-case shape is still chosen defensively.)
        - state = -MinorMode ('ReportOnly' (default) / 'Disabled' - NO 'Enabled' value exists in
          this parameter's ValidateSet, a structural guard, not a warning)

    THIS SCRIPT DOES NOT CREATE THE TERMS OF USE AGREEMENT OBJECT. Microsoft's own "Create
    agreement" Graph reference lists delegated permissions only ("Application: Not supported") -
    this library's standard app-only certificate automation pattern cannot call that endpoint.
    Create the agreement first (Entra admin center > Conditional Access > Terms of use > New
    terms, or a one-time interactive delegated-auth Graph call) and pass its id as -AgreementId.
    See README.md Section 5 Step 4 and design.md Section 7.

    Idempotent per policy: fetches all Conditional Access policies, matches each by its own
    -DisplayName, and with -Force reconciles conditions/grantControls/state to this run's
    parameters. Without -Force, an already-matching policy is reported and left untouched; a
    policy found under the same name with DIFFERENT conditions/controls is reported as drifted and
    left untouched unless -Force is also passed.

.PARAMETER ModerateDisplayName
    Conditional Access policy display name for the Moderate-risk Terms of Use policy. Defaults to
    'Adaptive Protection - Require Terms of Use for Moderate Insider Risk (Custom)'.

.PARAMETER MinorDisplayName
    Conditional Access policy display name for the Minor-risk insights policy. Defaults to
    'Adaptive Protection - Insights for Minor Insider Risk (Custom)'.

.PARAMETER AgreementId
    The id (GUID) of an existing Microsoft Entra Terms of Use agreement object
    (identityGovernance/termsOfUse/agreements/{id}). Required unless -SkipModeratePolicy is
    passed - this script never creates an agreement (see .DESCRIPTION). Find an existing
    agreement's id with:
        Get-MgIdentityGovernanceTermsOfUseAgreement | Select-Object DisplayName, Id

.PARAMETER ModerateRiskLevels
    One or more of 'elevated', 'moderate', 'minor' (Graph's conditionalAccessInsiderRiskLevels
    enum values) for the Moderate/Terms-of-Use policy's condition. Defaults to @('moderate') only,
    matching Microsoft's own documented pairing. Overriding this is a tuning option (design.md
    Section 3) - this script does not validate that your chosen levels match Microsoft's
    recommendation.

.PARAMETER MinorRiskLevels
    Same enum, for the Minor/insights policy's condition. Defaults to @('minor') only.

.PARAMETER ExcludeUserIds
    Object IDs (GUIDs) of emergency-access / break-glass accounts to exclude from BOTH policies'
    Users condition. Lower stakes than the Elevated sibling's block (neither policy here can lock
    a user out of Microsoft 365 entirely), but still standard Conditional Access practice.

.PARAMETER ExcludeGroupIds
    Object IDs (GUIDs) of groups to exclude from BOTH policies. Combined with -ExcludeUserIds;
    either or both may be supplied.

.PARAMETER ModerateMode
    'ReportOnly' (default - maps to Graph state 'enabledForReportingButNotEnforced'), 'Enabled'
    (maps to 'enabled' - actively requires Terms of Use acceptance), or 'Disabled' (maps to
    'disabled'). Applies to the Moderate policy only.

.PARAMETER MinorMode
    'ReportOnly' (default - maps to 'enabledForReportingButNotEnforced') or 'Disabled' (maps to
    'disabled'). There is deliberately NO 'Enabled' value - see .DESCRIPTION and design.md Section
    6. Applies to the Minor policy only.

.PARAMETER SkipModeratePolicy
    Do not create/reconcile the Moderate (Terms of Use) policy this run - e.g. because no
    -AgreementId is available yet. The Minor policy, if not also skipped, is still processed.

.PARAMETER SkipMinorPolicy
    Do not create/reconcile the Minor (insights) policy this run.

.PARAMETER GraphBaseUri
    Graph base URI. Defaults to 'https://graph.microsoft.com/v1.0'. Present for symmetry with the
    Elevated sibling script; both conditions and grant controls used here (insiderRiskLevels,
    termsOfUse, block) are confirmed current, non-beta v1.0 properties - see README.md Section 12.

.PARAMETER Force
    If a policy matching a -DisplayName already exists with different conditions/grantControls/
    state than this run's parameters, reconcile it instead of leaving it untouched.

.PARAMETER WhatIf
    Standard PowerShell ShouldProcess dry-run. Reports the create/update(s) that would be made
    without calling any mutating Graph endpoint.

.EXAMPLE
    Connect-MgGraph -ClientId $AppId -TenantId $TenantId -CertificateThumbprint $Thumbprint
    ./New-InsiderRiskStepUpPolicies.ps1 -AgreementId '11111111-1111-1111-1111-111111111111' -ExcludeGroupIds '22222222-2222-2222-2222-222222222222' -WhatIf

.EXAMPLE
    # Deploy both policies in their default (Report-only / permanently-Report-only) posture.
    ./New-InsiderRiskStepUpPolicies.ps1 -AgreementId '11111111-1111-1111-1111-111111111111' -ExcludeGroupIds '22222222-2222-2222-2222-222222222222'

.EXAMPLE
    # No Terms of Use agreement created yet - deploy only the Minor insights policy this run.
    ./New-InsiderRiskStepUpPolicies.ps1 -SkipModeratePolicy -ExcludeGroupIds '22222222-2222-2222-2222-222222222222'

.EXAMPLE
    # Promote the Moderate policy to enforcement after a validated Report-only pilot. The Minor
    # policy has no 'Enabled' option and is left in Report-only.
    ./New-InsiderRiskStepUpPolicies.ps1 -AgreementId '11111111-1111-1111-1111-111111111111' -ExcludeGroupIds '22222222-2222-2222-2222-222222222222' -ModerateMode Enabled -Force

.NOTES
    IDENTITY BY DISPLAYNAME, NOT A FIXED GUID: same limitation as the Elevated sibling script -
    renaming a policy in the portal breaks this script's idempotency detection for that policy.
    Documented in README.md Section 11.

    MINOR POLICY GRANT CONTROL IS A DISCLOSED PAYLOAD CHOICE, NOT A MICROSOFT RECOMMENDATION:
    Microsoft's Adaptive Protection configuration guide names no specific grant control for Minor
    risk, only "a policy... in Report-Only mode" for visibility. This script sets
    grantControls.builtInControls = ['mfa'] purely as a payload container - it is never evaluated
    in a state that could enforce it (see -MinorMode). 'mfa' (not the Elevated sibling's 'block')
    was chosen specifically for its fail-safe profile: see design.md Section 6.

    Sources (Microsoft Learn, verify before production use):
    - Adaptive Protection configuration guide (the Elevated/Moderate/Minor Conditional Access
      pairing this script automates for Moderate and Minor):
      https://learn.microsoft.com/purview/insider-risk-management-adaptive-protection-guide
    - Require terms of use to be accepted before accessing Microsoft Admin Portals (the exact
      portal procedure this script's Moderate policy automates):
      https://learn.microsoft.com/entra/identity/conditional-access/require-tou
    - Set up Microsoft Entra terms of use with Conditional Access (Entra ID P1 minimum license for
      the Terms of Use feature itself; PDF-document prerequisite):
      https://learn.microsoft.com/entra/identity/conditional-access/terms-of-use
    - conditionalAccessGrantControls resource type (termsOfUse property; builtInControls enum
      including 'block'; operator AND/OR):
      https://learn.microsoft.com/graph/api/resources/conditionalaccessgrantcontrols
    - conditionalAccessApplications resource type ('MicrosoftAdminPortals' / 'All' special
      includeApplications values):
      https://learn.microsoft.com/graph/api/resources/conditionalaccessapplications
    - Conditional Access Target resources: Microsoft Admin Portals (the four app IDs the
      MicrosoftAdminPortals grouping expands to):
      https://learn.microsoft.com/entra/identity/conditional-access/concept-conditional-access-cloud-apps#microsoft-admin-portals
    - conditionalAccessConditionSet resource type (insiderRiskLevels property, v1.0, values
      minor/moderate/elevated/unknownFutureValue):
      https://learn.microsoft.com/graph/api/resources/conditionalaccessconditionset
    - conditionalAccessPolicy resource type (state property):
      https://learn.microsoft.com/graph/api/resources/conditionalaccesspolicy
    - Create / Update conditionalAccessPolicy (least-privileged permission
      Policy.ReadWrite.ConditionalAccess + Policy.Read.All - this endpoint DOES support
      application permissions, unlike agreement creation below):
      https://learn.microsoft.com/graph/api/conditionalaccessroot-post-policies
      https://learn.microsoft.com/graph/api/conditionalaccesspolicy-update
    - Create agreement (delegated-permission-only - "Application: Not supported" - why this
      script never creates the Terms of Use agreement object itself):
      https://learn.microsoft.com/graph/api/termsofusecontainer-post-agreements
    - agreement resource type / List agreements (Get-MgIdentityGovernanceTermsOfUseAgreement):
      https://learn.microsoft.com/graph/api/resources/agreement
      https://learn.microsoft.com/graph/api/termsofusecontainer-list-agreements
    - New- / Update- / Get-MgIdentityConditionalAccessPolicy (Microsoft.Graph.Identity.SignIns
      module, -BodyParameter hashtable pattern):
      https://learn.microsoft.com/powershell/module/microsoft.graph.identity.signins/new-mgidentityconditionalaccesspolicy
      https://learn.microsoft.com/powershell/module/microsoft.graph.identity.signins/update-mgidentityconditionalaccesspolicy
    - Manage emergency access (break-glass) accounts:
      https://learn.microsoft.com/entra/identity/role-based-access-control/security-emergency-access
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$ModerateDisplayName = 'Adaptive Protection - Require Terms of Use for Moderate Insider Risk (Custom)',

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$MinorDisplayName = 'Adaptive Protection - Insights for Minor Insider Risk (Custom)',

    [Parameter()]
    [string]$AgreementId,

    [Parameter()]
    [ValidateSet('elevated', 'moderate', 'minor')]
    [string[]]$ModerateRiskLevels = @('moderate'),

    [Parameter()]
    [ValidateSet('elevated', 'moderate', 'minor')]
    [string[]]$MinorRiskLevels = @('minor'),

    [Parameter()]
    [string[]]$ExcludeUserIds = @(),

    [Parameter()]
    [string[]]$ExcludeGroupIds = @(),

    [Parameter()]
    [ValidateSet('ReportOnly', 'Enabled', 'Disabled')]
    [string]$ModerateMode = 'ReportOnly',

    [Parameter()]
    [ValidateSet('ReportOnly', 'Disabled')]
    [string]$MinorMode = 'ReportOnly',

    [Parameter()]
    [switch]$SkipModeratePolicy,

    [Parameter()]
    [switch]$SkipMinorPolicy,

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

function Publish-CaPolicy {
    param(
        [Parameter(Mandatory)][string]$DisplayName,
        [Parameter(Mandatory)][hashtable]$DesiredBody,
        [Parameter(Mandatory)][string]$DesiredState,
        [Parameter(Mandatory)][string[]]$DesiredGrantCompareValues,
        [Parameter(Mandatory)][ValidateSet('termsOfUse', 'builtInControls')][string]$GrantControlKind
    )

    $existing = @(Get-MgIdentityConditionalAccessPolicy -All -ErrorAction Stop) | Where-Object { $_.DisplayName -eq $DisplayName } | Select-Object -First 1

    if ($existing) {
        $existingRiskLevels = @($existing.Conditions.InsiderRiskLevels)
        $existingIncludeApps = @($existing.Conditions.Applications.IncludeApplications)
        $existingIncludeUsers = @($existing.Conditions.Users.IncludeUsers)
        $existingExcludeUsers = @($existing.Conditions.Users.ExcludeUsers)
        $existingExcludeGroups = @($existing.Conditions.Users.ExcludeGroups)
        $existingOperator = $existing.GrantControls.Operator
        $existingState = $existing.State
        $existingGrant = if ($GrantControlKind -eq 'termsOfUse') { @($existing.GrantControls.TermsOfUse) } else { @($existing.GrantControls.BuiltInControls) }

        $matches = (Test-SameStringSet $existingRiskLevels $DesiredBody.conditions.insiderRiskLevels) `
            -and (Test-SameStringSet $existingIncludeApps $DesiredBody.conditions.applications.includeApplications) `
            -and (Test-SameStringSet $existingIncludeUsers @('All')) `
            -and (Test-SameStringSet $existingExcludeUsers $ExcludeUserIds) `
            -and (Test-SameStringSet $existingExcludeGroups $ExcludeGroupIds) `
            -and (Test-SameStringSet $existingGrant $DesiredGrantCompareValues) `
            -and ($existingOperator -eq 'OR') `
            -and ($existingState -eq $DesiredState)

        if ($matches -and -not $Force) {
            Write-Host "  [coverage] '$DisplayName' already matches this run's parameters (state: $existingState) - not modified. Pass -Force to reconcile anyway." -ForegroundColor Yellow
            return
        }
        if (-not $matches -and -not $Force) {
            Write-Host "  [drift] '$DisplayName' exists but its conditions/grantControls/state differ from this run's parameters (existing state: $existingState). Not modified - pass -Force to reconcile." -ForegroundColor Yellow
            return
        }

        if ($PSCmdlet.ShouldProcess($DisplayName, "Update Conditional Access policy $($existing.Id) (PATCH /identity/conditionalAccess/policies/$($existing.Id))")) {
            Update-MgIdentityConditionalAccessPolicy -ConditionalAccessPolicyId $existing.Id -BodyParameter $DesiredBody | Out-Null
            Write-Host "  [reconciled] '$DisplayName' updated (id $($existing.Id)) - state now $DesiredState." -ForegroundColor Green
        }
    }
    else {
        if ($PSCmdlet.ShouldProcess($DisplayName, 'Create Conditional Access policy (POST /identity/conditionalAccess/policies)')) {
            $created = New-MgIdentityConditionalAccessPolicy -BodyParameter $DesiredBody
            Write-Host "  [created] '$DisplayName' created (id $($created.Id)) - state $DesiredState." -ForegroundColor Green
        }
    }
}

Assert-MgConnected

if (-not $SkipModeratePolicy -and [string]::IsNullOrWhiteSpace($AgreementId)) {
    throw "-AgreementId is required to deploy the Moderate (Terms of Use) policy - this script never creates the agreement object itself (Application permissions are not supported for agreement creation, see .NOTES). Pass -SkipModeratePolicy to deploy only the Minor policy this run, or supply an existing agreement's id (Get-MgIdentityGovernanceTermsOfUseAgreement)."
}

if ($SkipModeratePolicy -and $SkipMinorPolicy) {
    throw '-SkipModeratePolicy and -SkipMinorPolicy were both passed - nothing to do.'
}

if (-not $SkipModeratePolicy) {
    Write-Host "Moderate insider risk Terms of Use policy: reconciling '$ModerateDisplayName' (Mode: $ModerateMode, RiskLevels: $($ModerateRiskLevels -join ', '))." -ForegroundColor Cyan

    $moderateState = $script:StateMap[$ModerateMode]
    $moderateUsers = [ordered]@{ includeUsers = @('All') }
    if ($ExcludeUserIds.Count -gt 0) { $moderateUsers.excludeUsers = @($ExcludeUserIds) }
    if ($ExcludeGroupIds.Count -gt 0) { $moderateUsers.excludeGroups = @($ExcludeGroupIds) }

    $moderateBody = [ordered]@{
        displayName   = $ModerateDisplayName
        state         = $moderateState
        conditions    = [ordered]@{
            applications      = [ordered]@{ includeApplications = @('MicrosoftAdminPortals') }
            users             = $moderateUsers
            insiderRiskLevels = @($ModerateRiskLevels | ForEach-Object { $_.ToString().ToLowerInvariant() })
        }
        grantControls = [ordered]@{
            operator   = 'OR'
            termsOfUse = @($AgreementId)
        }
    }

    Publish-CaPolicy -DisplayName $ModerateDisplayName -DesiredBody $moderateBody -DesiredState $moderateState `
        -DesiredGrantCompareValues @($AgreementId) -GrantControlKind termsOfUse
}
else {
    Write-Host "Skipping Moderate policy (-SkipModeratePolicy passed)." -ForegroundColor DarkYellow
}

if (-not $SkipMinorPolicy) {
    Write-Host "Minor insider risk insights policy: reconciling '$MinorDisplayName' (Mode: $MinorMode, RiskLevels: $($MinorRiskLevels -join ', '))." -ForegroundColor Cyan

    $minorState = $script:StateMap[$MinorMode]
    $minorUsers = [ordered]@{ includeUsers = @('All') }
    if ($ExcludeUserIds.Count -gt 0) { $minorUsers.excludeUsers = @($ExcludeUserIds) }
    if ($ExcludeGroupIds.Count -gt 0) { $minorUsers.excludeGroups = @($ExcludeGroupIds) }

    $minorBody = [ordered]@{
        displayName   = $MinorDisplayName
        state         = $minorState
        conditions    = [ordered]@{
            applications      = [ordered]@{ includeApplications = @('All') }
            users             = $minorUsers
            insiderRiskLevels = @($MinorRiskLevels | ForEach-Object { $_.ToString().ToLowerInvariant() })
        }
        grantControls = [ordered]@{
            operator        = 'OR'
            builtInControls = @('mfa')
        }
    }

    Publish-CaPolicy -DisplayName $MinorDisplayName -DesiredBody $minorBody -DesiredState $minorState `
        -DesiredGrantCompareValues @('mfa') -GrantControlKind builtInControls
}
else {
    Write-Host "Skipping Minor policy (-SkipMinorPolicy passed)." -ForegroundColor DarkYellow
}

Write-Host "`nDone. Run validate/Test-InsiderRiskStepUpPolicies.ps1 to verify. Reminder: both policies only evaluate a user's insider risk level once Adaptive Protection is turned on and has had up to 36 hours to assign it - see README.md Section 11." -ForegroundColor Cyan
```

#### `Remove-InsiderRiskStepUpPolicies.ps1`

```powershell
#Requires -Version 7.0
<#
.SYNOPSIS
    Rolls back the Conditional Access policies created by New-InsiderRiskStepUpPolicies.ps1, in
    stages: disable (default, reversible in seconds), step back to Report-only, or permanently
    delete (-Purge). Operates on one or both policies via -Policy.

.DESCRIPTION
    Mirrors the staged rollback pattern conditional-access-insider-risk-block/deploy/
    Remove-InsiderRiskConditionalAccessPolicy.ps1 already uses. Neither policy this scenario
    deploys can lock a user out of Microsoft 365 entirely (unlike the Elevated sibling's block),
    but the same least-destructive-default discipline applies. See rollback.md for the full staged
    procedure and what rollback does NOT undo.

.PARAMETER Policy
    Which policy to roll back: 'Moderate', 'Minor', or 'Both' (default).

.PARAMETER ModerateDisplayName
    Must match the -ModerateDisplayName used at deploy time. Defaults to
    'Adaptive Protection - Require Terms of Use for Moderate Insider Risk (Custom)'.

.PARAMETER MinorDisplayName
    Must match the -MinorDisplayName used at deploy time. Defaults to
    'Adaptive Protection - Insights for Minor Insider Risk (Custom)'.

.PARAMETER ReportOnly
    Step back to Report-only (state = enabledForReportingButNotEnforced) instead of fully
    disabling. For the Minor policy this is a no-op-equivalent (it is already restricted to
    ReportOnly/Disabled and defaults to ReportOnly).

.PARAMETER Purge
    Permanently delete the selected policy object(s) (Remove-MgIdentityConditionalAccessPolicy).
    Not reversible - re-establishing the control means re-running
    New-InsiderRiskStepUpPolicies.ps1 from scratch.

.PARAMETER GraphBaseUri
    Present for symmetry with the deploy script; not used directly.

.PARAMETER WhatIf
    Standard PowerShell ShouldProcess dry-run.

.EXAMPLE
    Connect-MgGraph -ClientId $AppId -TenantId $TenantId -CertificateThumbprint $Thumbprint
    ./Remove-InsiderRiskStepUpPolicies.ps1 -WhatIf

.EXAMPLE
    # Stage 1 - disable both policies (reversible)
    ./Remove-InsiderRiskStepUpPolicies.ps1

.EXAMPLE
    # Roll back only the Moderate (Terms of Use) policy, stepping back to Report-only
    ./Remove-InsiderRiskStepUpPolicies.ps1 -Policy Moderate -ReportOnly

.EXAMPLE
    # Stage 3 - permanent removal of both
    ./Remove-InsiderRiskStepUpPolicies.ps1 -Purge

.NOTES
    Sources (Microsoft Learn, verify before production use):
    - Update conditionalAccessPolicy (state property PATCH):
      https://learn.microsoft.com/graph/api/conditionalaccesspolicy-update
    - Delete conditionalAccessPolicy:
      https://learn.microsoft.com/graph/api/conditionalaccesspolicy-delete
    - Remove-MgIdentityConditionalAccessPolicy (Microsoft.Graph.Identity.SignIns):
      https://learn.microsoft.com/powershell/module/microsoft.graph.identity.signins/remove-mgidentityconditionalaccesspolicy
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter()]
    [ValidateSet('Moderate', 'Minor', 'Both')]
    [string]$Policy = 'Both',

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$ModerateDisplayName = 'Adaptive Protection - Require Terms of Use for Moderate Insider Risk (Custom)',

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$MinorDisplayName = 'Adaptive Protection - Insights for Minor Insider Risk (Custom)',

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

function Remove-OnePolicy {
    param([Parameter(Mandatory)][string]$DisplayName)

    $existing = @(Get-MgIdentityConditionalAccessPolicy -All -ErrorAction Stop) | Where-Object { $_.DisplayName -eq $DisplayName } | Select-Object -First 1

    if (-not $existing) {
        Write-Host "'$DisplayName' not found - nothing to roll back." -ForegroundColor Yellow
        return
    }

    if ($Purge) {
        if ($PSCmdlet.ShouldProcess($DisplayName, "PERMANENTLY DELETE Conditional Access policy $($existing.Id)")) {
            Remove-MgIdentityConditionalAccessPolicy -ConditionalAccessPolicyId $existing.Id
            Write-Host "  [purged] '$DisplayName' (id $($existing.Id)) permanently deleted." -ForegroundColor Green
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
}

if ($Policy -in @('Moderate', 'Both')) { Remove-OnePolicy -DisplayName $ModerateDisplayName }
if ($Policy -in @('Minor', 'Both')) { Remove-OnePolicy -DisplayName $MinorDisplayName }

Write-Host "`nDone. This does not delete the Terms of Use agreement object, turn off Adaptive Protection, reset any user's current insider risk level, or affect the Elevated sibling's block policy - see rollback.md." -ForegroundColor Cyan
```