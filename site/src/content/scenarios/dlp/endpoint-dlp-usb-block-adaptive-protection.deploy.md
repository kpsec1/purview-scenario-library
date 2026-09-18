---
part: "deploy"
parent: "dlp/endpoint-dlp-usb-block-adaptive-protection"
---
The scripts and configuration below deploy this scenario. Review them, then run in order — each is designed to be idempotent and has a matching rollback.


#### `New-AdaptiveProtectionDevicesDlpPolicy.ps1`

```powershell
#Requires -Modules @{ ModuleName = 'ExchangeOnlineManagement'; ModuleVersion = '3.2.0' }
<#
.SYNOPSIS
    Deploys the "Adaptive Protection - Devices Endpoint DLP (Custom)" DLP policy and its two
    risk-tiered rules - the Devices half of Adaptive Protection.

.DESCRIPTION
    Creates (or, if already present, leaves untouched and reports) one Microsoft Purview Endpoint
    DLP policy scoped to onboarded Windows/macOS devices, with two rules that key off a user's
    live Insider Risk Management insider risk level (the "Insider risk level for Adaptive
    Protection is" condition) - the device-channel companion to
    scenarios/adaptive-protection/dynamic-risk-dlp-enforcement's Exchange/Teams policy:
      0. AdaptiveProtection-Devices-Block-Elevated       - Elevated risk level: blocks copy to
                                                            clipboard, USB removable media, and
                                                            network share, and blocks printing.
      1. AdaptiveProtection-Devices-Audit-ModerateMinor  - Moderate/Minor risk level: audits the
                                                            same four activities, blocks nothing.

    This reproduces the four **confirmed, independently-grounded** restriction settings from
    Microsoft's documented Devices Quick Setup rule table (dlp-adaptive-protection-learn):
    RemovableMedia, CopyPaste, NetworkShare, and Print. Two further Quick Setup actions -
    "Access by restricted apps" and "Upload to a restricted cloud service domain or access from
    unallowed browsers" - are deliberately NOT scripted here. Microsoft's own New-/
    Set-DlpComplianceRule reference documents the -EndpointDlpRestrictions "UnallowedApps" Setting
    only as a mechanism to declare which app is restricted (Value = executable name, value2 =
    friendly name), never how to attach a Block/Audit action to that declaration at the rule
    level; no Setting name for the cloud/browser restriction is documented anywhere this build
    found. Fabricating either shape would violate this repo's grounding standard (AGENTS.md
    Section 4) - see README.md Section 11 and design.md Section 6 for the full finding, and the
    portal-only manual step this script's completion message and README.md Section 5 Step 6 point
    you to instead.

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
    Microsoft's own Quick Setup-generated policy name ("Adaptive Protection policy for Endpoint
    DLP") to avoid confusion if Quick Setup is also run in the same tenant.

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
    ./New-AdaptiveProtectionDevicesDlpPolicy.ps1 -AdminNotificationEmail 'soc@contoso.com' -WhatIf

    Dry-run: shows exactly what would be created, changes nothing.

.EXAMPLE
    ./New-AdaptiveProtectionDevicesDlpPolicy.ps1 -AdminNotificationEmail 'soc@contoso.com' -Mode TestWithNotifications

    Deploys in simulation mode: nothing is blocked yet - the same posture as Microsoft's own
    Quick Setup default.

.EXAMPLE
    ./New-AdaptiveProtectionDevicesDlpPolicy.ps1 -AdminNotificationEmail 'soc@contoso.com' -Mode Enable -Force

    Deploys (or updates) the policy in full enforcement mode. Only do this after confirming, via
    the pilot workflow in README.md Section 7, that risk levels are being assigned as expected,
    AND after confirming (README.md Section 3) that target devices are already onboarded to
    Microsoft Purview device management and Advanced classification scanning and protection is
    turned on (both portal-only prerequisites this script cannot create).

.NOTES
    PREREQUISITES (portal-only, not scripted here):
    1. Target devices already onboarded to Microsoft Purview device management (Settings > Device
       onboarding), the same prerequisite scenarios/dlp/endpoint-dlp-usb-block already documents.
    2. Advanced classification scanning and protection turned ON (Purview portal > Data loss
       prevention > Endpoint DLP settings). Microsoft's dlp-adaptive-protection-learn page states
       this (or an explicit "File Type is" condition) is required for Adaptive Protection to work
       on Devices at all. This script uses the Advanced-classification path rather than a
       File Type condition, because New-/Set-DlpComplianceRule's own -ContentFileTypeMatches
       parameter reference is unpublished placeholder text ("{{ Fill ContentFileTypeMatches
       Description }}") as of this writing - this repo does not fabricate the value syntax for an
       undocumented condition parameter (AGENTS.md Section 4). No PowerShell/Graph toggle for
       Advanced classification scanning and protection itself was found during this build either;
       it is a portal-only setting.
    3. Adaptive Protection turned on, insider risk levels defined, and a feeder Insider Risk
       Management policy in scope - identical prerequisite to the sibling
       scenarios/adaptive-protection/dynamic-risk-dlp-enforcement scenario; see that scenario's
       README.md Sections 3 and 5 Steps 1-3 (not repeated by this scenario's own deploy script).
    This script's rules will create successfully even if none of the above is met, but will never
    match any user until all three are true - Get-DlpComplianceRule will not surface that
    misconfiguration; only the manual checklist in
    validate/Test-AdaptiveProtectionDevicesDlpPolicy.ps1 and the Purview portal's Adaptive
    Protection > Data Loss Prevention tab can confirm it.

    The three -SharedByIRMUserRisk GUID values below are fixed, Microsoft-documented identifiers
    for the Elevated/Moderate/Minor insider risk levels - identical values to every other
    Adaptive-Protection-consuming scenario in this library. They are not tenant-specific and do
    not need to be looked up per tenant.

    ENDPOINTDLPRESTRICTIONS SETTINGS SCRIPTED: RemovableMedia, CopyPaste, NetworkShare, Print -
    all four independently confirmed on both the New-DlpComplianceRule and Set-DlpComplianceRule
    Microsoft Learn reference pages ("The available values for <Value> are: Audit, Block, Ignore,
    or Warn," with a worked RemovableMedia/Block example; the same pages also list Print,
    CopyPaste, ScreenCapture, NetworkShare, and UnallowedApps as supported Setting names).
    ScreenCapture is deliberately NOT included - Microsoft's documented Devices Quick Setup rule
    table for this exact policy does not list "Screen capture" among its restricted activities,
    so this script matches that reference table exactly rather than adding an extra restriction
    Microsoft's own reference configuration doesn't include.

    NOTIFYUSER TENSION (disclosed, not silently resolved either way): Microsoft's
    New-/Set-DlpComplianceRule reference states "When you use the values Block or Warn in this
    parameter, you also need to use the NotifyUser parameter" - yet the same Quick-Setup rule
    table this script otherwise reproduces exactly shows "User Notification: Off" for BOTH
    Devices rules, including the Block rule. These two statements are in tension. This script
    resolves the tension by supplying -NotifyUser on the block rule (Rule 0) to satisfy the
    documented cmdlet requirement for a Block value, while keeping the actual notification text
    generic and low-key (no policy-tip custom text is set, matching the "Off" posture as closely
    as a supplied-but-minimal NotifyUser value allows). VERIFY the resulting end-user experience
    (does a toast/notification actually appear despite Quick Setup showing "Off"?) against a pilot
    tenant before describing this rule's user-facing behavior to a customer - see README.md
    Section 11. The audit rule (Rule 1) uses Value=Audit throughout, which carries no documented
    NotifyUser requirement, so NotifyUser is omitted there, matching Quick Setup's "Off" exactly
    with no tension.

    INTERACTION WITH OTHER DEVICES-SCOPED DLP POLICIES: Microsoft's dlp-adaptive-protection-learn
    page states: "If a user is targeted by a default Adaptive Protection Device DLP policy and is
    targeted by an independent Device DLP policy, only the actions of the most restrictive policy
    will be applied." A tenant that has also deployed this library's
    scenarios/dlp/endpoint-dlp-usb-block (a separate, always-on Devices-scoped DLP policy) will
    have both policies active simultaneously for any user Adaptive Protection assigns a risk
    level to - by Microsoft's own documented behavior this is safe-by-default (most restrictive
    wins), not a silent downgrade, but confirm the combined behavior in a pilot tenant rather than
    assuming independently-reviewed policies compose exactly as expected once layered.

    Sources (Microsoft Learn, verify before production use):
    - Learn about Adaptive Protection in DLP (documented Devices Quick Setup rule shape this
      script reproduces, "most restrictive policy" interaction note, Advanced classification/File
      Type prerequisite): https://learn.microsoft.com/purview/dlp-adaptive-protection-learn
    - Help dynamically mitigate risks with Adaptive Protection (custom setup, permissions,
      36-hour propagation delay): https://learn.microsoft.com/purview/insider-risk-management-adaptive-protection
    - New-DlpComplianceRule / Set-DlpComplianceRule -SharedByIRMUserRisk and
      -EndpointDlpRestrictions parameters (GUID values; confirmed Setting names and Value enum;
      NotifyUser requirement for Block/Warn; UnallowedApps app-declaration-only shape):
      https://learn.microsoft.com/powershell/module/exchangepowershell/new-dlpcompliancerule
      https://learn.microsoft.com/powershell/module/exchangepowershell/set-dlpcompliancerule
    - New-DlpCompliancePolicy -EndpointDlpLocation parameter:
      https://learn.microsoft.com/powershell/module/exchangepowershell/new-dlpcompliancepolicy
    - Configure endpoint DLP settings (Advanced classification scanning and protection,
      Restricted apps and app groups, Browser and domain restrictions to sensitive data):
      https://learn.microsoft.com/purview/dlp-configure-endpoint-settings
    - scenarios/dlp/endpoint-dlp-usb-block/README.md Section 3 - device onboarding prerequisite
      this scenario reuses without repeating.
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$PolicyName = 'Adaptive Protection - Devices Endpoint DLP (Custom)',

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

$ruleNameBlockElevated = 'AdaptiveProtection-Devices-Block-Elevated'
$ruleNameAuditModerateMinor = 'AdaptiveProtection-Devices-Audit-ModerateMinor'

# The four confirmed EndpointDlpRestrictions Setting names this policy restricts, matching
# Microsoft's documented Devices Quick Setup rule table exactly (RemovableMedia = "Copy to
# removable USB device", CopyPaste = "Copy to clipboard", NetworkShare = "Copy to network share",
# Print = "Print").
$restrictedSettings = @('RemovableMedia', 'CopyPaste', 'NetworkShare', 'Print')

$existingPolicy = Get-DlpCompliancePolicy -Identity $PolicyName -ErrorAction SilentlyContinue

if ($existingPolicy -and -not $Force) {
    Write-Host "Policy '$PolicyName' already exists (Mode: $($existingPolicy.Mode)). No changes made. Pass -Force to reconcile rules to this script's definition." -ForegroundColor Yellow
    return
}

if (-not $existingPolicy) {
    if ($PSCmdlet.ShouldProcess($PolicyName, 'New-DlpCompliancePolicy (EndpointDlpLocation All)')) {
        New-DlpCompliancePolicy -Name $PolicyName `
            -EndpointDlpLocation 'All' `
            -Mode $Mode `
            -Comment 'Adaptive Protection control (Devices half): dynamically blocks/audits clipboard, USB, network-share, and print activity based on a user''s live Insider Risk Management insider risk level. Deployed by scenarios/dlp/endpoint-dlp-usb-block-adaptive-protection. Owner: Security & Compliance team.' `
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

# --- Rule 0: Elevated risk level - block clipboard/USB/network-share/print ---
# Mirrors Microsoft's documented "Adaptive Protection block rule for Endpoint DLP", minus the two
# undocumented-shape actions (restricted apps, cloud/browser egress) - see .NOTES.
$rule0 = Get-DlpComplianceRule -Identity $ruleNameBlockElevated -ErrorAction SilentlyContinue
$rule0Params = @{
    Name                     = $ruleNameBlockElevated
    Policy                   = $PolicyName
    Priority                 = 0
    SharedByIRMUserRisk      = @($riskLevelElevated)
    EndpointDlpRestrictions  = @($restrictedSettings | ForEach-Object { @{ Setting = $_; Value = 'Block' } })
    NotifyUser               = @('LastModifier')
    GenerateAlert            = $AdminNotificationEmail
    GenerateIncidentReport   = $AdminNotificationEmail
    ReportSeverityLevel      = 'Low'
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

# --- Rule 1: Moderate/Minor risk level - audit clipboard/USB/network-share/print, block nothing ---
# Mirrors Microsoft's documented "Adaptive Protection rule for Endpoint DLP" (the Moderate/Minor
# variant), minus the same two undocumented-shape actions.
$rule1 = Get-DlpComplianceRule -Identity $ruleNameAuditModerateMinor -ErrorAction SilentlyContinue
$rule1Params = @{
    Name                     = $ruleNameAuditModerateMinor
    Policy                   = $PolicyName
    Priority                 = 1
    SharedByIRMUserRisk      = @($riskLevelModerate, $riskLevelMinor)
    EndpointDlpRestrictions  = @($restrictedSettings | ForEach-Object { @{ Setting = $_; Value = 'Audit' } })
    GenerateAlert            = $AdminNotificationEmail
    GenerateIncidentReport   = $AdminNotificationEmail
    ReportSeverityLevel      = 'Low'
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

Write-Host "`nDone. Policy sync can take up to ~1 hour, and this policy will not match any user until: (1) target devices are onboarded to Microsoft Purview device management, (2) Advanced classification scanning and protection is turned on, and (3) Adaptive Protection is turned on and has assigned that user a risk level (up to 36 hours after Adaptive Protection is first enabled). This script also does NOT configure 'Access by restricted apps' or 'Upload to a restricted cloud service domain or access from unallowed browsers' - see README.md Section 5 Step 6 and Section 11 for the manual portal steps to add those two actions to match Microsoft's full Quick Setup rule shape. Run validate/Test-AdaptiveProtectionDevicesDlpPolicy.ps1 to verify the deployed configuration." -ForegroundColor Cyan
```

#### `Remove-AdaptiveProtectionDevicesDlpPolicy.ps1`

```powershell
#Requires -Modules @{ ModuleName = 'ExchangeOnlineManagement'; ModuleVersion = '3.2.0' }
<#
.SYNOPSIS
    Removes (or disables) the "Adaptive Protection - Devices Endpoint DLP (Custom)" DLP policy.

.DESCRIPTION
    Two rollback modes:
      -Disable (default, recommended first step): sets the policy Mode to Disable. Reversible in
       seconds via Set-DlpCompliancePolicy -Mode Enable. No history is lost.
      -Purge: permanently deletes the policy and its two rules via Remove-DlpCompliancePolicy.
       Removing the policy also removes its rules (Microsoft Learn: remove-dlpcompliancepolicy).
       This is NOT reversible - re-deploying requires re-running
       New-AdaptiveProtectionDevicesDlpPolicy.ps1.

    This script only rolls back the DLP policy this scenario deploys. It does not disable
    Adaptive Protection itself, the feeder Insider Risk Management policy, Advanced classification
    scanning and protection, or device onboarding - all outside this scenario's scope (design.md
    Section 7). It also has no effect on the sibling
    scenarios/adaptive-protection/dynamic-risk-dlp-enforcement policy (Exchange/Teams) or
    scenarios/dlp/endpoint-dlp-usb-block (a separate, always-on Devices policy) - each rolls back
    independently via its own script.

    Idempotent: if the policy does not exist, the script reports that and exits cleanly rather
    than erroring.

.PARAMETER PolicyName
    Name of the DLP policy to roll back. Must match the -PolicyName used at deploy time.

.PARAMETER Purge
    Permanently delete the policy instead of disabling it. See rollback.md for the recommended
    disable-first, purge-later sequence.

.PARAMETER WhatIf
    Standard PowerShell ShouldProcess dry-run - reports the disable/removal that would happen
    without calling Set-DlpCompliancePolicy / Remove-DlpCompliancePolicy.

.EXAMPLE
    Connect-IPPSSession -AppId $AppId -Certificate $Cert -Organization $TenantDomain
    ./Remove-AdaptiveProtectionDevicesDlpPolicy.ps1 -WhatIf

.EXAMPLE
    ./Remove-AdaptiveProtectionDevicesDlpPolicy.ps1
    # Disables the policy (soft rollback).

.EXAMPLE
    ./Remove-AdaptiveProtectionDevicesDlpPolicy.ps1 -Purge
    # Permanently deletes the policy and its rules.

.NOTES
    Sources: https://learn.microsoft.com/powershell/module/exchangepowershell/set-dlpcompliancepolicy
             https://learn.microsoft.com/powershell/module/exchangepowershell/remove-dlpcompliancepolicy
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$PolicyName = 'Adaptive Protection - Devices Endpoint DLP (Custom)',

    [Parameter()]
    [switch]$Purge
)

$ErrorActionPreference = 'Stop'

if (-not (Get-Command Get-DlpCompliancePolicy -ErrorAction SilentlyContinue)) {
    throw 'No Security & Compliance PowerShell session found. Run Connect-IPPSSession first (see docs/automation-surface.md).'
}

$policy = Get-DlpCompliancePolicy -Identity $PolicyName -ErrorAction SilentlyContinue

if (-not $policy) {
    Write-Host "Policy '$PolicyName' does not exist. Nothing to roll back." -ForegroundColor Yellow
    return
}

if ($Purge) {
    if ($PSCmdlet.ShouldProcess($PolicyName, 'Remove-DlpCompliancePolicy (permanent, also removes its rules)')) {
        Remove-DlpCompliancePolicy -Identity $PolicyName -Confirm:$false -WhatIf:$WhatIfPreference
    }
    Write-Host "Permanently removed policy '$PolicyName' and its rules." -ForegroundColor Green
}
else {
    if ($PSCmdlet.ShouldProcess($PolicyName, 'Set-DlpCompliancePolicy -Mode Disable')) {
        Set-DlpCompliancePolicy -Identity $PolicyName -Mode Disable -WhatIf:$WhatIfPreference
    }
    Write-Host "Disabled policy '$PolicyName'. Re-enable with: Set-DlpCompliancePolicy -Identity '$PolicyName' -Mode Enable" -ForegroundColor Green
}
```