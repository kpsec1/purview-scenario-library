#Requires -Modules @{ ModuleName = 'ExchangeOnlineManagement'; ModuleVersion = '3.2.0' }
<#
.SYNOPSIS
    Deploys the "Adaptive Protection - Teams and Exchange DLP (Custom)" DLP policy and its two
    risk-tiered rules.

.DESCRIPTION
    Creates (or, if already present, leaves untouched and reports) one Microsoft Purview DLP
    policy scoped to Exchange Online and Microsoft Teams, with two rules that key off a user's
    live Insider Risk Management insider risk level (the "Insider risk level for Adaptive
    Protection is" condition), reproducing Microsoft's own documented Quick Setup rule shape for
    this policy type via the custom-setup path instead:
      0. AdaptiveProtection-Block-Elevated        - Elevated risk level, external share, block
      1. AdaptiveProtection-Audit-ModerateMinor   - Moderate/Minor risk level, external share, audit

    This script does NOT enable Adaptive Protection, define insider risk levels, or create the
    feeder Insider Risk Management policy - all three are portal-only prerequisites documented in
    README.md Sections 3 and 5. It also does not create a Conditional Access or Data Lifecycle
    Management policy (see design.md Section 7, Non-goals).

    Idempotent: if a policy with the same -PolicyName already exists, the script reports its
    current state and takes no action, rather than erroring or creating a duplicate. Re-run with
    -Force to update rule properties on an existing policy to match this script's definition.

    Author-only reference code. This script never establishes its own connection to a tenant and
    never targets a live tenant by default (-Mode defaults to TestWithNotifications, matching
    Microsoft's own Quick Setup default of "run the policy in simulation mode"). Run
    Connect-IPPSSession yourself first (see docs/automation-surface.md Section 3 for the
    certificate app-only pattern), then call this script.

.PARAMETER PolicyName
    Name of the DLP policy. Policy names cannot be changed after creation (Microsoft Learn:
    dlp-create-policy-powerbi-cc-numbers) - choose deliberately. Defaults to a name distinct from
    Microsoft's own Quick Setup-generated policy name to avoid confusion if Quick Setup is also
    run in the same tenant (see README.md Section 11).

.PARAMETER AdminNotificationEmail
    One or more admin/SOC mailbox addresses to receive incident reports and alerts.

.PARAMETER Mode
    DLP policy mode: Enable, Disable, TestWithNotifications, or TestWithoutNotifications
    (Set-DlpCompliancePolicy -Mode; Microsoft Learn: set-dlpcompliancepolicy). Defaults to
    TestWithNotifications, matching every rule in Microsoft's own documented Quick Setup output
    for this policy, which ships in simulation mode.

.PARAMETER Force
    If the policy already exists, update its rules to match this script's definition instead of
    skipping. Rule updates go through Set-DlpComplianceRule -WhatIf when -WhatIf is passed.

.PARAMETER WhatIf
    Standard PowerShell ShouldProcess dry-run. Reports every New-/Set-Dlp* call that would be
    made without calling any mutating cmdlet.

.EXAMPLE
    Connect-IPPSSession -AppId $AppId -Certificate $Cert -Organization $TenantDomain
    ./New-AdaptiveProtectionDlpPolicy.ps1 -AdminNotificationEmail 'soc@contoso.com' -WhatIf

    Dry-run: shows exactly what would be created, changes nothing.

.EXAMPLE
    ./New-AdaptiveProtectionDlpPolicy.ps1 -AdminNotificationEmail 'soc@contoso.com' -Mode TestWithNotifications

    Deploys in simulation mode: policy tips and notifications fire, nothing is blocked yet - the
    same posture as Microsoft's own Quick Setup default.

.EXAMPLE
    ./New-AdaptiveProtectionDlpPolicy.ps1 -AdminNotificationEmail 'soc@contoso.com' -Mode Enable -Force

    Deploys (or updates) the policy in full enforcement mode. Only do this after confirming, via
    the pilot workflow in README.md Section 7, that risk levels are being assigned as expected.

.NOTES
    PREREQUISITE (portal-only, not scripted here): Adaptive Protection must already be turned on,
    with the Elevated/Moderate/Minor insider risk levels defined, and at least one Insider Risk
    Management policy in its scope - see README.md Section 5, Steps 1-3. This script's rules will
    create successfully even if that prerequisite isn't met, but will never match any user until
    it is - Get-DlpComplianceRule will not surface that misconfiguration; only the manual
    checklist in validate/Test-AdaptiveProtectionDlpPolicy.ps1 and the Purview portal's Adaptive
    Protection > Data Loss Prevention tab can confirm it.

    The three -SharedByIRMUserRisk GUID values below are fixed, Microsoft-documented identifiers
    for the Elevated/Moderate/Minor insider risk levels - they are not tenant-specific and do not
    need to be looked up per tenant.

    CONDITION SCOPING: this script represents the portal's compound "Content is shared from
    Microsoft 365 with people outside my organization" condition using -AccessScope
    NotInOrganization alone - the same, already-reviewed pattern used in
    scenarios/dlp/pci-teams-exfil-block. An earlier draft also added -ContentIsShared $true, but
    whether that separate boolean condition is required (or merely redundant) to fully replicate
    the portal's exact compound condition was not independently confirmed during this build, so
    it was removed rather than shipped unverified. VERIFY against a pilot tenant's portal-rendered
    rule conditions before assuming this AccessScope-only form is a byte-for-byte match.

    NOTIFICATION WORDING: policy-tip text deliberately does NOT tell the blocked/audited user
    they were flagged as an insider risk. Revealing that would tip off a genuinely malicious
    insider mid-investigation while providing no benefit to a false-positive'd innocent user (who
    is equally well served by a generic "contact Security" message) - see reviews.md, Red Team
    lens.

    Sources (Microsoft Learn, verify before production use):
    - New-DlpComplianceRule / Set-DlpComplianceRule -SharedByIRMUserRisk parameter and GUID values:
      https://learn.microsoft.com/powershell/module/exchangepowershell/new-dlpcompliancerule
      https://learn.microsoft.com/powershell/module/exchangepowershell/set-dlpcompliancerule
    - Learn about Adaptive Protection in DLP (documented Quick Setup rule shape this script
      reproduces): https://learn.microsoft.com/purview/dlp-adaptive-protection-learn
    - Help dynamically mitigate risks with Adaptive Protection (custom setup, permissions,
      36-hour propagation delay): https://learn.microsoft.com/purview/insider-risk-management-adaptive-protection
    - New-DlpCompliancePolicy / New-DlpComplianceRule reference:
      https://learn.microsoft.com/powershell/module/exchangepowershell/new-dlpcompliancepolicy
      https://learn.microsoft.com/powershell/module/exchangepowershell/new-dlpcompliancerule
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$PolicyName = 'Adaptive Protection - Teams and Exchange DLP (Custom)',

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string[]]$AdminNotificationEmail,

    [Parameter()]
    [ValidateSet('Enable', 'Disable', 'TestWithNotifications', 'TestWithoutNotifications')]
    [string]$Mode = 'TestWithNotifications',

    [Parameter()]
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

function Assert-IppsSession {
    # Get-DlpCompliancePolicy is only exported after a successful Connect-IPPSSession; its absence means the caller never connected.
    if (-not (Get-Command Get-DlpCompliancePolicy -ErrorAction SilentlyContinue)) {
        throw 'No Security & Compliance PowerShell session found. Run Connect-IPPSSession first (see docs/automation-surface.md).'
    }
}

Assert-IppsSession

# Fixed, Microsoft-documented GUIDs for the three Adaptive Protection insider risk levels.
# Source: New-DlpComplianceRule / Set-DlpComplianceRule -SharedByIRMUserRisk parameter reference.
$riskLevelElevated = 'FCB9FA93-6269-4ACF-A756-832E79B36A2A'
$riskLevelModerate = '797C4446-5C73-484F-8E58-0CCA08D6DF6C'
$riskLevelMinor = '75A4318B-94A2-4323-BA42-2CA6DB29AAFE'

$ruleNameBlockElevated = 'AdaptiveProtection-Block-Elevated'
$ruleNameAuditModerateMinor = 'AdaptiveProtection-Audit-ModerateMinor'

$existingPolicy = Get-DlpCompliancePolicy -Identity $PolicyName -ErrorAction SilentlyContinue

if ($existingPolicy -and -not $Force) {
    Write-Host "Policy '$PolicyName' already exists (Mode: $($existingPolicy.Mode)). No changes made. Pass -Force to reconcile rules to this script's definition." -ForegroundColor Yellow
    return
}

if (-not $existingPolicy) {
    if ($PSCmdlet.ShouldProcess($PolicyName, 'New-DlpCompliancePolicy (ExchangeLocation All, TeamsLocation All)')) {
        New-DlpCompliancePolicy -Name $PolicyName `
            -ExchangeLocation 'All' `
            -TeamsLocation 'All' `
            -Mode $Mode `
            -Comment 'Adaptive Protection control: dynamically blocks/audits external content sharing based on a user''s live Insider Risk Management insider risk level. Deployed by scenarios/adaptive-protection/dynamic-risk-dlp-enforcement. Owner: Security & Compliance team.' `
            -WhatIf:$WhatIfPreference | Out-Null
    }
    Write-Host "Created DLP policy '$PolicyName' (Mode: $Mode)." -ForegroundColor Green
}
else {
    Write-Host "Policy '$PolicyName' exists - reconciling rules (-Force)." -ForegroundColor Yellow
    if ($PSCmdlet.ShouldProcess($PolicyName, "Set-DlpCompliancePolicy -Mode $Mode")) {
        Set-DlpCompliancePolicy -Identity $PolicyName -Mode $Mode -WhatIf:$WhatIfPreference
    }
}

# --- Rule 0: Elevated risk level - block external share ---
# Mirrors Microsoft's documented "Adaptive Protection block rule for Teams and Exchange DLP".
$rule0 = Get-DlpComplianceRule -Identity $ruleNameBlockElevated -ErrorAction SilentlyContinue
$rule0Params = @{
    Name                = $ruleNameBlockElevated
    Policy              = $PolicyName
    Priority            = 0
    SharedByIRMUserRisk = @($riskLevelElevated)
    AccessScope         = 'NotInOrganization'
    BlockAccess         = $true
    NotifyUser          = @('LastModifier')
    NotifyPolicyTipCustomText = 'This content was blocked from being shared outside the organization by a Microsoft Purview data loss prevention policy. If you believe this is in error, contact the Security team.'
    GenerateAlert          = $AdminNotificationEmail
    GenerateIncidentReport = $AdminNotificationEmail
    ReportSeverityLevel    = 'Low'
}
if (-not $rule0) {
    if ($PSCmdlet.ShouldProcess($ruleNameBlockElevated, 'New-DlpComplianceRule')) {
        New-DlpComplianceRule @rule0Params -WhatIf:$WhatIfPreference | Out-Null
    }
    Write-Host "Created rule '$ruleNameBlockElevated'." -ForegroundColor Green
}
elseif ($Force) {
    $rule0Params.Remove('Policy') | Out-Null
    $rule0Params.Remove('Name') | Out-Null
    if ($PSCmdlet.ShouldProcess($ruleNameBlockElevated, 'Set-DlpComplianceRule')) {
        Set-DlpComplianceRule -Identity $ruleNameBlockElevated @rule0Params -WhatIf:$WhatIfPreference
    }
    Write-Host "Updated rule '$ruleNameBlockElevated'." -ForegroundColor Green
}

# --- Rule 1: Moderate/Minor risk level - audit only, no block ---
# Mirrors Microsoft's documented "Adaptive Protection audit rule for Teams and Exchange DLP".
$rule1 = Get-DlpComplianceRule -Identity $ruleNameAuditModerateMinor -ErrorAction SilentlyContinue
$rule1Params = @{
    Name                = $ruleNameAuditModerateMinor
    Policy              = $PolicyName
    Priority            = 1
    SharedByIRMUserRisk = @($riskLevelModerate, $riskLevelMinor)
    AccessScope         = 'NotInOrganization'
    BlockAccess         = $false
    NotifyUser          = @('LastModifier')
    NotifyPolicyTipCustomText = 'This content was shared outside the organization. This is an informational notice from a Microsoft Purview data loss prevention policy - nothing was blocked.'
    GenerateAlert          = $AdminNotificationEmail
    GenerateIncidentReport = $AdminNotificationEmail
    ReportSeverityLevel    = 'Low'
}
if (-not $rule1) {
    if ($PSCmdlet.ShouldProcess($ruleNameAuditModerateMinor, 'New-DlpComplianceRule')) {
        New-DlpComplianceRule @rule1Params -WhatIf:$WhatIfPreference | Out-Null
    }
    Write-Host "Created rule '$ruleNameAuditModerateMinor'." -ForegroundColor Green
}
elseif ($Force) {
    $rule1Params.Remove('Policy') | Out-Null
    $rule1Params.Remove('Name') | Out-Null
    if ($PSCmdlet.ShouldProcess($ruleNameAuditModerateMinor, 'Set-DlpComplianceRule')) {
        Set-DlpComplianceRule -Identity $ruleNameAuditModerateMinor @rule1Params -WhatIf:$WhatIfPreference
    }
    Write-Host "Updated rule '$ruleNameAuditModerateMinor'." -ForegroundColor Green
}

Write-Host "`nDone. Policy sync can take up to ~1 hour, and this policy will not match any user until Adaptive Protection is turned on and has assigned that user a risk level (up to 36 hours after Adaptive Protection is first enabled - see README.md Section 11). Run validate/Test-AdaptiveProtectionDlpPolicy.ps1 to verify the deployed configuration." -ForegroundColor Cyan
