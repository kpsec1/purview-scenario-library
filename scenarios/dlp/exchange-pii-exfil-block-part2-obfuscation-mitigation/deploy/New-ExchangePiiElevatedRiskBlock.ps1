#Requires -Modules @{ ModuleName = 'ExchangeOnlineManagement'; ModuleVersion = '3.2.0' }
<#
.SYNOPSIS
    Adds a new, highest-priority "Elevated insider risk -> hard block" rule to the existing
    "PII DLP - Exchange External Send Control" DLP policy from
    scenarios/dlp/exchange-pii-exfil-block/.

.DESCRIPTION
    Extends the parent scenario's Exchange DLP policy with one new rule,
    PII-Exchange-ElevatedRisk-Block-AllExternal, that blocks ANY outbound Exchange message an
    Elevated-insider-risk sender addresses to an external recipient - regardless of whether the
    message content matches the SSN/Credit Card Number sensitive information types the parent
    policy inspects for. This is the behavioral compensating control for the split/obfuscated-PII
    evasion gap documented in scenarios/dlp/exchange-pii-exfil-block/README.md §11 and
    reviews.md: single-message, content-based DLP pattern matching cannot see an SSN or PAN
    deliberately split across messages, but once a sender's other activity has driven their
    Insider Risk Management insider risk level to Elevated (see design.md §2-4 for how), this rule
    stops that sender from sending anything further externally over Exchange - closing the channel
    for continued attempts, not the first one.

    This script does NOT create the feeder Insider Risk Management policy or configure Adaptive
    Protection's scope - both are portal-only prerequisites documented in README.md §5 and
    design.md §5. Unlike this fragment's Microsoft Teams sibling
    (scenarios/dlp/pci-teams-exfil-block-part2-obfuscation-mitigation), no Communication
    Compliance detour is required here - Exchange Online is a natively supported "High Severity
    DLP Alert" indicator workload, so the feeder IRM policy can trigger directly off the parent
    scenario's own DLP policy (design.md §3). This script also does NOT modify
    scenarios/adaptive-protection/dynamic-risk-dlp-enforcement/'s own policy, or either of the
    parent scenario's own three (or four, if the Encrypt-mode audit companion is deployed) rules'
    conditions or actions - see design.md §7 (Non-goals).

    PREREQUISITE: scenarios/dlp/exchange-pii-exfil-block/deploy/New-ExchangePiiDlpPolicy.ps1 must
    already have been run successfully against the target -PolicyName - this script errors out
    (does not create a policy from scratch) if the named policy has no existing rules.

    PRIORITY HANDLING (generalized, not a hardcoded rule list - see design.md §6): the parent
    policy can carry two, three, or four rules by the time this script runs, depending on whether
    -ExceptionGroupEmail/-Action Block were used (scenarios/dlp/exchange-pii-exfil-block) and
    whether scenarios/dlp/exchange-pii-exfil-block-encrypt-mode-audit-companion was separately
    deployed. Rather than hardcode an expected rule-name list (as this fragment's Teams sibling
    does, where the parent policy's rule set is fixed at exactly three), this script reads
    whichever rules currently exist on the policy, preserves their *relative* priority order, and
    compacts them to start at priority 1 - leaving priority 0 free for the new rule. Re-running
    this script is idempotent: rules already compacted starting at 1 are left untouched.

    Idempotent: if the new rule already exists, the script reports its current state and takes no
    action unless -Force is passed, in which case it reconciles the rule's properties (and
    re-verifies the other rules' compaction) to this script's definition. Re-running with the same
    parameters never creates a duplicate rule.

    Author-only reference code. This script never establishes its own connection to a tenant.
    Run Connect-IPPSSession yourself first (see docs/automation-surface.md §3), then call this
    script.

.PARAMETER PolicyName
    Name of the existing DLP policy to extend. Must match the -PolicyName used when the parent
    scenario's New-ExchangePiiDlpPolicy.ps1 was run. Defaults to that scenario's own default name.

.PARAMETER AdminNotificationEmail
    One or more admin/SOC mailbox addresses to receive incident reports and alerts for the new
    rule - same audience the parent scenario's rules already notify.

.PARAMETER Force
    If the new rule already exists, update its properties to match this script's definition
    instead of skipping. Also re-verifies (and corrects, if drifted) the other rules' priority
    compaction - see .NOTES.

.PARAMETER WhatIf
    Standard PowerShell ShouldProcess dry-run. Reports every Set-/New-DlpComplianceRule call that
    would be made (including the priority-compaction calls) without calling any mutating cmdlet.

.EXAMPLE
    Connect-IPPSSession -AppId $AppId -Certificate $Cert -Organization $TenantDomain
    ./New-ExchangePiiElevatedRiskBlock.ps1 -AdminNotificationEmail 'soc@contoso.com' -WhatIf

    Dry-run: shows exactly what would change (priority compaction + new rule), changes nothing.

.EXAMPLE
    ./New-ExchangePiiElevatedRiskBlock.ps1 -AdminNotificationEmail 'soc@contoso.com'

    Adds the new rule. Because the rule's own action (BlockAccess = $true) is unconditional once
    the SharedByIRMUserRisk/AccessScope conditions match, there is no separate simulation mode for
    this one rule - it inherits the parent policy's existing Mode (Set-DlpCompliancePolicy -Mode,
    unchanged by this script). Confirm the parent policy is already in TestWithNotifications mode
    before running this against a production tenant for the first time.

.NOTES
    PRIORITY COMPACTION, NOT A FIXED RULE LIST: see .DESCRIPTION. Microsoft's New-DlpComplianceRule
    / Set-DlpComplianceRule reference documents the -Priority parameter's type (Int32) but does not
    document whether creating or updating a rule with a priority value that collides with an
    existing rule in the same policy automatically shifts the other rules down. Rather than rely on
    that undocumented behavior, this script explicitly reassigns every existing rule's priority
    (highest-current-priority first, to avoid any transient collision) before creating the new rule
    at priority 0. VERIFY against a pilot tenant that the resulting priority order matches what
    this script intends (see validate/Test-ExchangePiiElevatedRiskBlock.ps1) before relying on it
    in production - the same open VERIFY item already flagged in the Teams sibling fragment for the
    identical undocumented-auto-shift question.

    NO OVERRIDE BY DESIGN: this rule omits -NotifyAllowOverride entirely, so an Elevated-risk
    sender cannot self-override the block even if they are a member of the parent scenario's
    -ExceptionGroupEmail group - see design.md §6. This is a deliberate divergence from the parent
    scenario's own override rule, not an oversight, and matches the Teams sibling fragment's own
    no-override decision.

    HARD BLOCK REGARDLESS OF THE PARENT SCENARIO'S -Action MODE: the parent scenario's
    PII-Exchange-Protect-External rule can be deployed with -Action Block or -Action Encrypt. This
    new rule always hard-blocks (BlockAccess = $true), never encrypts, regardless of which -Action
    the parent scenario currently uses for its general population - an Elevated-risk sender gets
    the strictest available treatment, not the operator's chosen leniency level for everyone else.
    See design.md §6.

    SCOPE: this rule has NO content/sensitive-information-type condition - it fires on ANY Exchange
    message an Elevated-risk sender addresses to an external recipient, matching or not matching
    SSN/Credit Card Number. This is intentional (design.md §1) - the whole point is to stop
    continued drip-feed attempts regardless of per-message content, not to add a fourth
    content-pattern rule.

    The Elevated risk-level GUID below is the same fixed, Microsoft-documented identifier already
    used and independently grounded in
    scenarios/adaptive-protection/dynamic-risk-dlp-enforcement/deploy/New-AdaptiveProtectionDlpPolicy.ps1
    and scenarios/dlp/pci-teams-exfil-block-part2-obfuscation-mitigation/deploy/
    New-PciElevatedRiskTeamsBlock.ps1 - it is not tenant-specific and does not need to be looked up
    per tenant.

    Sources (Microsoft Learn, verify before production use):
    - New-DlpComplianceRule / Set-DlpComplianceRule -SharedByIRMUserRisk parameter and GUID values:
      https://learn.microsoft.com/powershell/module/exchangepowershell/new-dlpcompliancerule
      https://learn.microsoft.com/powershell/module/exchangepowershell/set-dlpcompliancerule
    - Configure policy indicators in Insider Risk Management (Exchange Online DLP-alert-indicator
      support, "Supported DLP workloads"):
      https://learn.microsoft.com/purview/insider-risk-management-settings-policy-indicators#data-loss-prevention-alerts-indicators
    - Learn about Insider Risk Management policy templates (Data leaks template DLP-alert
      triggering event, "Incident reports" High-severity requirement):
      https://learn.microsoft.com/purview/insider-risk-management-policy-templates#policy-template-prerequisites-and-triggering-events
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$PolicyName = 'PII DLP - Exchange External Send Control',

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
# (same value already grounded in dynamic-risk-dlp-enforcement and the Teams sibling fragment).
$riskLevelElevated = 'FCB9FA93-6269-4ACF-A756-832E79B36A2A'

$newRuleName = 'PII-Exchange-ElevatedRisk-Block-AllExternal'

$policy = Get-DlpCompliancePolicy -Identity $PolicyName -ErrorAction SilentlyContinue
if (-not $policy) {
    throw "Policy '$PolicyName' not found. Run scenarios/dlp/exchange-pii-exfil-block/deploy/New-ExchangePiiDlpPolicy.ps1 first - this script only extends an already-deployed policy, it does not create one."
}

$allRules = @(Get-DlpComplianceRule -Policy $PolicyName -ErrorAction SilentlyContinue)
$otherRules = @($allRules | Where-Object { $_.Name -ne $newRuleName })

if ($otherRules.Count -eq 0) {
    throw "Policy '$PolicyName' has no existing rules. Run scenarios/dlp/exchange-pii-exfil-block/deploy/New-ExchangePiiDlpPolicy.ps1 first - this script only extends a policy that already has at least one rule to compact around."
}

$newRule = Get-DlpComplianceRule -Identity $newRuleName -ErrorAction SilentlyContinue

if ($newRule -and -not $Force) {
    Write-Host "Rule '$newRuleName' already exists on policy '$PolicyName'. No changes made. Pass -Force to reconcile it (and re-verify the other rules' priority compaction) to this script's definition." -ForegroundColor Yellow
    return
}

# --- Compact every OTHER existing rule's priority to start at 1, preserving their current
#     relative order (design.md §6). Idempotent by construction: recomputing this on a policy
#     already compacted at 1..N yields the same target values, so no Set- calls fire on a repeat
#     run. Applied highest-target-priority-first so no two rules in the policy ever momentarily
#     share a priority value mid-script (see .NOTES: this behavior is not documented either way by
#     Microsoft, so this script does not rely on it). -->
$orderedAscendingByCurrentPriority = $otherRules | Sort-Object -Property Priority
$targetPriority = 1
$compactionPlan = foreach ($rule in $orderedAscendingByCurrentPriority) {
    [PSCustomObject]@{ Name = $rule.Name; CurrentPriority = $rule.Priority; TargetPriority = $targetPriority }
    $targetPriority++
}

foreach ($entry in ($compactionPlan | Sort-Object -Property TargetPriority -Descending)) {
    if ($entry.CurrentPriority -ne $entry.TargetPriority) {
        if ($PSCmdlet.ShouldProcess($entry.Name, "Set-DlpComplianceRule -Priority $($entry.TargetPriority)")) {
            Set-DlpComplianceRule -Identity $entry.Name -Priority $entry.TargetPriority -WhatIf:$WhatIfPreference
        }
        Write-Host "Compacted rule '$($entry.Name)' from priority $($entry.CurrentPriority) to $($entry.TargetPriority)." -ForegroundColor Green
    }
    else {
        Write-Host "Rule '$($entry.Name)' already at priority $($entry.TargetPriority) - no change." -ForegroundColor Gray
    }
}

# --- New rule: Elevated insider risk, any content, external recipient -> hard block, no override ---
$newRuleParams = @{
    Name                      = $newRuleName
    Policy                    = $PolicyName
    Priority                  = 0
    SharedByIRMUserRisk       = @($riskLevelElevated)
    AccessScope               = 'NotInOrganization'
    BlockAccess               = $true
    NotifyUser                = @('LastModifier') + $AdminNotificationEmail
    NotifyPolicyTipCustomText = 'This message was blocked from being sent outside the organization by a Microsoft Purview data loss prevention policy. If you believe this is in error, contact the Security team.'
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

Write-Host "`nDone. This rule alone does nothing until the portal-only prerequisites in README.md Section 5 are complete (feeder Insider Risk Management policy, Adaptive Protection scope) - Get-DlpComplianceRule will not surface that gap. Run validate/Test-ExchangePiiElevatedRiskBlock.ps1 to check what this script can verify, and see its printed manual checklist for the rest." -ForegroundColor Cyan
