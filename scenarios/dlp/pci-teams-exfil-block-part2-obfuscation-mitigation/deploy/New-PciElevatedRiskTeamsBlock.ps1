#Requires -Modules @{ ModuleName = 'ExchangeOnlineManagement'; ModuleVersion = '3.2.0' }
<#
.SYNOPSIS
    Adds a new, highest-priority "Elevated insider risk -> hard block" rule to the existing
    "PCI DSS - Teams Card Data Exfiltration Block" DLP policy from
    scenarios/dlp/pci-teams-exfil-block/.

.DESCRIPTION
    Extends Part 1's PCI Teams DLP policy with one new rule, PCI-ElevatedRisk-Block-AllExternal,
    that blocks ANY Teams chat/channel message an Elevated-insider-risk sender shares with people
    outside the organization - regardless of whether the message content matches the Credit Card
    Number sensitive information type. This is the behavioral compensating control for the
    split/obfuscated-PAN evasion gap documented in
    scenarios/dlp/pci-teams-exfil-block/reviews.md (Red Team, finding 1): per-message DLP pattern
    matching cannot see a PAN deliberately split across messages, but once a sender's other
    activity has driven their Insider Risk Management insider risk level to Elevated (see
    design.md Sections 3-6 for how), this rule stops that sender from sharing anything further
    externally over Teams - closing the channel for continued attempts, not the first one.

    This script does NOT create the feeder Insider Risk Management policy, enable the
    Communication Compliance SIT indicator, or configure Adaptive Protection - all three are
    portal-only prerequisites documented in README.md Section 5 and design.md Section 5. It also
    does NOT modify scenarios/adaptive-protection/dynamic-risk-dlp-enforcement/'s own policy - see
    design.md Section 7 (Non-goals).

    PREREQUISITE: scenarios/dlp/pci-teams-exfil-block/deploy/New-PciTeamsDlpPolicy.ps1 must
    already have been run successfully against the target -PolicyName - this script errors out
    (does not create a policy from scratch) if the named policy or its three expected Part 1
    rules are not found.

    Idempotent: if the new rule already exists, the script reports its current state and takes no
    action unless -Force is passed, in which case it reconciles the rule's properties to this
    script's definition. Re-running with the same parameters never creates a duplicate rule.

    Author-only reference code. This script never establishes its own connection to a tenant.
    Run Connect-IPPSSession yourself first (see docs/automation-surface.md Section 3), then call
    this script.

.PARAMETER PolicyName
    Name of the existing DLP policy to extend. Must match the -PolicyName used when Part 1's
    New-PciTeamsDlpPolicy.ps1 was run. Defaults to Part 1's own default name.

.PARAMETER AdminNotificationEmail
    One or more admin/SOC mailbox addresses to receive incident reports and alerts for the new
    rule - same audience Part 1's rules already notify.

.PARAMETER Force
    If the new rule already exists, update its properties to match this script's definition
    instead of skipping. Also required to proceed if Part 1's three expected rules are found but
    at priorities other than 0/1/2 (e.g., a prior manual edit) - see .NOTES.

.PARAMETER WhatIf
    Standard PowerShell ShouldProcess dry-run. Reports every Set-/New-DlpComplianceRule call that
    would be made (including the priority-reordering calls) without calling any mutating cmdlet.

.EXAMPLE
    Connect-IPPSSession -AppId $AppId -Certificate $Cert -Organization $TenantDomain
    ./New-PciElevatedRiskTeamsBlock.ps1 -AdminNotificationEmail 'soc@contoso.com' -WhatIf

    Dry-run: shows exactly what would change (priority reordering + new rule), changes nothing.

.EXAMPLE
    ./New-PciElevatedRiskTeamsBlock.ps1 -AdminNotificationEmail 'soc@contoso.com'

    Adds the new rule. Because the rule's own action (BlockAccess = $true) is unconditional once
    the SharedByIRMUserRisk/AccessScope conditions match, there is no separate simulation mode for
    this one rule - it inherits the parent policy's existing Mode (Set-DlpCompliancePolicy -Mode,
    unchanged by this script). Confirm the parent policy is already in TestWithNotifications mode
    before running this against a production tenant for the first time.

.NOTES
    PRIORITY REORDERING: Microsoft's New-DlpComplianceRule / Set-DlpComplianceRule reference
    documents the -Priority parameter's type (Int32) but does not document whether creating or
    updating a rule with a priority value that collides with an existing rule in the same policy
    automatically shifts the other rules down. Rather than rely on that undocumented behavior,
    this script explicitly re-prioritizes Part 1's three existing rules (2<-1, 1<-0... applied
    highest-target-priority-first to avoid any transient collision) before creating the new rule
    at priority 0. VERIFY against a pilot tenant that the resulting priority order matches what
    this script intends (see validate/Test-PciElevatedRiskTeamsBlock.ps1) before relying on it in
    production.

    NO OVERRIDE BY DESIGN: this rule omits -NotifyAllowOverride entirely (unlike Part 1's Rule 0),
    so an Elevated-risk sender cannot self-override the block even if they are a Card Operations
    group member - see design.md Section 6. This is a deliberate divergence from Part 1's Rule 0,
    not an oversight.

    SCOPE: this rule has NO content/sensitive-information-type condition - it fires on ANY Teams
    message an Elevated-risk sender shares externally, matching or not matching Credit Card
    Number. This is intentional (design.md Section 1) - the whole point is to stop continued
    drip-feed attempts regardless of per-message content, not to add a fourth content-pattern
    rule.

    The Elevated risk-level GUID below is the same fixed, Microsoft-documented identifier already
    used and independently grounded in
    scenarios/adaptive-protection/dynamic-risk-dlp-enforcement/deploy/New-AdaptiveProtectionDlpPolicy.ps1
    - it is not tenant-specific and does not need to be looked up per tenant.

    Sources (Microsoft Learn, verify before production use):
    - New-DlpComplianceRule / Set-DlpComplianceRule -SharedByIRMUserRisk parameter and GUID values:
      https://learn.microsoft.com/powershell/module/exchangepowershell/new-dlpcompliancerule
      https://learn.microsoft.com/powershell/module/exchangepowershell/set-dlpcompliancerule
    - Configure policy indicators in Insider Risk Management (Teams DLP-alert-indicator
      exclusion; Communication Compliance indicators integration):
      https://learn.microsoft.com/purview/insider-risk-management-settings-policy-indicators
    - Create and manage Insider Risk Management policies (cumulative exfiltration detection):
      https://learn.microsoft.com/purview/insider-risk-management-policies
    - Learn about Insider Risk Management policy templates (triggering events):
      https://learn.microsoft.com/purview/insider-risk-management-policy-templates
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$PolicyName = 'PCI DSS - Teams Card Data Exfiltration Block',

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string[]]$AdminNotificationEmail,

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

# Fixed, Microsoft-documented GUID for the Adaptive Protection "Elevated" insider risk level.
# Source: New-DlpComplianceRule / Set-DlpComplianceRule -SharedByIRMUserRisk parameter reference
# (same value already grounded in dynamic-risk-dlp-enforcement/deploy/New-AdaptiveProtectionDlpPolicy.ps1).
$riskLevelElevated = 'FCB9FA93-6269-4ACF-A756-832E79B36A2A'

$newRuleName = 'PCI-ElevatedRisk-Block-AllExternal'
$part1RuleNames = @(
    @{ Name = 'PCI-CardOps-Override-External'; TargetPriority = 1 }
    @{ Name = 'PCI-Block-External-AllUsers'; TargetPriority = 2 }
    @{ Name = 'PCI-Audit-Internal-AllUsers'; TargetPriority = 3 }
)

$policy = Get-DlpCompliancePolicy -Identity $PolicyName -ErrorAction SilentlyContinue
if (-not $policy) {
    throw "Policy '$PolicyName' not found. Run scenarios/dlp/pci-teams-exfil-block/deploy/New-PciTeamsDlpPolicy.ps1 first - this script only extends an already-deployed Part 1 policy, it does not create one."
}

$existingRules = @{}
foreach ($entry in $part1RuleNames) {
    $rule = Get-DlpComplianceRule -Identity $entry.Name -ErrorAction SilentlyContinue
    if (-not $rule) {
        throw "Expected Part 1 rule '$($entry.Name)' not found on policy '$PolicyName'. This script only extends a policy already deployed by New-PciTeamsDlpPolicy.ps1 with its original three rules intact."
    }
    $existingRules[$entry.Name] = $rule
}

$newRule = Get-DlpComplianceRule -Identity $newRuleName -ErrorAction SilentlyContinue

if ($newRule -and -not $Force) {
    Write-Host "Rule '$newRuleName' already exists on policy '$PolicyName'. No changes made. Pass -Force to reconcile it (and re-check Part 1 rule priorities) to this script's definition." -ForegroundColor Yellow
    return
}

# --- Re-prioritize Part 1's three existing rules to make room for the new rule at priority 0. ---
# Applied highest-target-priority-first so no two rules in the policy ever momentarily share a
# priority value mid-script (see .NOTES: this behavior is not documented either way by Microsoft,
# so this script does not rely on it).
$orderedForReprioritize = $part1RuleNames | Sort-Object -Property TargetPriority -Descending
foreach ($entry in $orderedForReprioritize) {
    $rule = $existingRules[$entry.Name]
    if ($rule.Priority -ne $entry.TargetPriority) {
        if ($PSCmdlet.ShouldProcess($entry.Name, "Set-DlpComplianceRule -Priority $($entry.TargetPriority)")) {
            Set-DlpComplianceRule -Identity $entry.Name -Priority $entry.TargetPriority -WhatIf:$WhatIfPreference
        }
        Write-Host "Re-prioritized rule '$($entry.Name)' to priority $($entry.TargetPriority)." -ForegroundColor Green
    }
    else {
        Write-Host "Rule '$($entry.Name)' already at priority $($entry.TargetPriority) - no change." -ForegroundColor Gray
    }
}

# --- New rule: Elevated insider risk, any content, external share -> hard block, no override ---
$newRuleParams = @{
    Name                      = $newRuleName
    Policy                    = $PolicyName
    Priority                  = 0
    SharedByIRMUserRisk       = @($riskLevelElevated)
    AccessScope               = 'NotInOrganization'
    BlockAccess               = $true
    NotifyUser                = @('LastModifier')
    NotifyPolicyTipCustomText = 'This message was blocked from being shared outside the organization by a Microsoft Purview data loss prevention policy. If you believe this is in error, contact the Security team.'
    GenerateAlert             = $AdminNotificationEmail
    GenerateIncidentReport    = $AdminNotificationEmail
    ReportSeverityLevel       = 'High'
    StopPolicyProcessing      = $true
}

if (-not $newRule) {
    if ($PSCmdlet.ShouldProcess($newRuleName, 'New-DlpComplianceRule')) {
        New-DlpComplianceRule @newRuleParams -WhatIf:$WhatIfPreference | Out-Null
    }
    Write-Host "Created rule '$newRuleName' at priority 0 on policy '$PolicyName'." -ForegroundColor Green
}
else {
    $newRuleParams.Remove('Policy') | Out-Null
    $newRuleParams.Remove('Name') | Out-Null
    if ($PSCmdlet.ShouldProcess($newRuleName, 'Set-DlpComplianceRule')) {
        Set-DlpComplianceRule -Identity $newRuleName @newRuleParams -WhatIf:$WhatIfPreference
    }
    Write-Host "Updated rule '$newRuleName'." -ForegroundColor Green
}

Write-Host "`nDone. This rule alone does nothing until the portal-only prerequisites in README.md Section 5 are complete (feeder Insider Risk Management policy, Communication Compliance SIT indicator, Adaptive Protection scope) - Get-DlpComplianceRule will not surface that gap. Run validate/Test-PciElevatedRiskTeamsBlock.ps1 to check what this script can verify, and see its printed manual checklist for the rest." -ForegroundColor Cyan
