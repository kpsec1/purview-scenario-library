---
part: "deploy"
parent: "dlp/exchange-pii-exfil-block-part2-obfuscation-mitigation"
---
The scripts and configuration below deploy this scenario. Review them, then run in order — each is designed to be idempotent and has a matching rollback.


#### `New-ExchangePiiElevatedRiskBlock.ps1`

```powershell
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
```

#### `policy/irm-exchange-drip-exfiltration-config-manifest.json`

```json
{
  "_comment": "REFERENCE MANIFEST, NOT AN API PAYLOAD. Every field below is a portal-only configuration step (README.md Section 5, design.md Section 5) - no script in this scenario's deploy/ folder reads or applies this file. It is a structured, versioned source of truth for the person completing the portal steps, so the deployed configuration can be diffed against intent during review. Only deploy/New-ExchangePiiElevatedRiskBlock.ps1 (the DLP rule) is scripted.",
  "dlpAlertsIndicatorGlobalSetting": {
    "path": "Purview portal > Insider Risk Management > Settings > Policy indicators > Built-in Indicators tab > Data loss prevention (DLP) indicators > Add DLP policies",
    "policyToAdd": "PII DLP - Exchange External Send Control (scenarios/dlp/exchange-pii-exfil-block)",
    "note": "Exchange Online is a natively supported 'High Severity DLP Alert' indicator workload - unlike this fragment's Microsoft Teams sibling (pci-teams-exfil-block-part2-obfuscation-mitigation), no Communication Compliance detour is required. See design.md Section 3.",
    "requiredCheckbox": "Generating alerts from selected DLP policies (must be checked and Saved for the indicator to activate globally)"
  },
  "parentDlpPolicyPrerequisite": {
    "requirement": "At least one rule on the parent policy must have Incident reports set to High severity - this is the actual triggering threshold, not merely 'the policy exists'.",
    "confirmedAlreadyTrue": "scenarios/dlp/exchange-pii-exfil-block/deploy/New-ExchangePiiDlpPolicy.ps1 sets ReportSeverityLevel = High on both PII-Exchange-Override-External and PII-Exchange-Protect-External by default - no change needed to the parent scenario for this fragment to work.",
    "sourceCaveat": "PII-Exchange-Audit-Internal (internal-recipient traffic) is deliberately Low severity in the parent scenario and will NOT trigger this indicator - by design, since internal PII sharing is not the exfiltration signal this fragment cares about."
  },
  "feederInsiderRiskPolicy": {
    "name": "IRM-PII-Exchange-Drip-Exfiltration (buyer names as appropriate)",
    "template": "Data leaks",
    "scope": "Same user population as scenarios/dlp/exchange-pii-exfil-block (all mailboxes in ExchangeLocation scope, or a narrower population if the buyer scoped the parent policy down) - not limited to departing users, unlike scenarios/insider-risk/departing-employee-data-theft",
    "triggeringEvent": "User matches a data loss prevention (DLP) policy - select 'PII DLP - Exchange External Send Control' from the DLP policy dropdown on the policy workflow's Triggers page. Do NOT select 'User performs an exfiltration activity' instead - that built-in-indicators trigger is the correct choice for the Teams sibling fragment (where the DLP-alert trigger cannot see Teams), but here the direct DLP-policy trigger is both simpler and more precisely scoped to this exact control.",
    "policyIndicators": [
      "Built-in Office exfiltration indicators (defaults) - e.g. sending email with attachments to recipients outside the organization, downloading content from SharePoint/OneDrive",
      "No Communication Compliance indicator needed - see dlpAlertsIndicatorGlobalSetting above"
    ],
    "cumulativeExfiltrationDetection": "ON (default for the Data leaks template) - the specific ML-based feature Microsoft documents for detecting exfiltration activity that 'exceed[s] the normal amount performed by users in your organization... over multiple exfiltration activity types', including gradual/slow-drip patterns",
    "sequenceDetection": "Enabled with default sequences - optional, not the primary mechanism this fragment relies on",
    "priorityContent": "Sensitive information types: U.S. Social Security Number (SSN), Credit Card Number (increases risk score for any activity involving them)",
    "evaluationCadence": "High-severity DLP alerts are processed by the Data leaks trigger as they occur; Cumulative exfiltration detection itself is still evaluated ~daily - see README.md Section 11"
  },
  "adaptiveProtectionScope": {
    "action": "Add the new IRM-PII-Exchange-Drip-Exfiltration policy to Adaptive Protection's feeder-policy scope, in addition to (not instead of) any existing feeder policy such as scenarios/insider-risk/departing-employee-data-theft or the Teams sibling fragment's own feeder policy",
    "path": "Purview portal > Insider Risk Management > Adaptive protection > Insider risk levels",
    "note": "Insider risk levels are tenant-wide, computed from every feeder policy in scope - see scenarios/adaptive-protection/dynamic-risk-dlp-enforcement/README.md Section 11, an already-documented constraint this fragment inherits rather than re-derives."
  },
  "dlpRule": {
    "name": "PII-Exchange-ElevatedRisk-Block-AllExternal",
    "deployedBy": "deploy/New-ExchangePiiElevatedRiskBlock.ps1",
    "addedToPolicy": "PII DLP - Exchange External Send Control (scenarios/dlp/exchange-pii-exfil-block)",
    "priority": 0,
    "condition": "SharedByIRMUserRisk = Elevated AND AccessScope = NotInOrganization (no content/SIT condition)",
    "action": "Block, no override (even for the parent scenario's -ExceptionGroupEmail members), regardless of whether the parent policy is currently in -Action Block or -Action Encrypt mode"
  },
  "residualGap": "This configuration does NOT detect or block the first message of a perfectly-executed split-SSN/PAN attempt - no Microsoft capability performs cross-message content reconstruction as of this writing. See README.md Section 11 and design.md Section 1.",
  "schemaVersion": "1.0",
  "lastUpdated": "2026-09-09"
}
```

#### `Remove-ExchangePiiElevatedRiskBlock.ps1`

```powershell
#Requires -Modules @{ ModuleName = 'ExchangeOnlineManagement'; ModuleVersion = '3.2.0' }
<#
.SYNOPSIS
    Rolls back the PII-Exchange-ElevatedRisk-Block-AllExternal rule added by
    New-ExchangePiiElevatedRiskBlock.ps1, restoring the parent policy's other rules to their
    pre-Part-2 priority order.

.DESCRIPTION
    Two rollback modes:
      -Disable (default, recommended first step): sets the rule's action to audit-only
       (BlockAccess = $false) instead of removing it - reversible in seconds by re-running
       New-ExchangePiiElevatedRiskBlock.ps1 -Force, which restores BlockAccess = $true.
      -Purge: permanently removes the rule via Remove-DlpComplianceRule, then decompacts the
       parent policy's remaining rules back down by one priority slot each, preserving their
       relative order - the reverse of New-ExchangePiiElevatedRiskBlock.ps1's compaction (see that
       script's .NOTES and design.md §6). NOT reversible except by re-running
       New-ExchangePiiElevatedRiskBlock.ps1 from scratch.

    This script never touches the parent policy's other rules' conditions or actions - only their
    -Priority value (Purge mode only, to restore contiguous 0-based numbering).

    Idempotent: if the rule does not exist, the script reports that and exits cleanly.

.PARAMETER PolicyName
    Name of the parent DLP policy. Must match the -PolicyName used at deploy time.

.PARAMETER Purge
    Permanently delete the PII-Exchange-ElevatedRisk-Block-AllExternal rule and decompact the
    parent policy's remaining rules back to contiguous 0-based priorities, instead of disabling
    (audit-only) the rule's block action.

.PARAMETER WhatIf
    Standard PowerShell ShouldProcess dry-run.

.EXAMPLE
    Connect-IPPSSession -AppId $AppId -Certificate $Cert -Organization $TenantDomain
    ./Remove-ExchangePiiElevatedRiskBlock.ps1 -WhatIf

.EXAMPLE
    ./Remove-ExchangePiiElevatedRiskBlock.ps1
    # Switches the rule to audit-only (soft rollback) - keeps visibility, stops blocking.

.EXAMPLE
    ./Remove-ExchangePiiElevatedRiskBlock.ps1 -Purge
    # Permanently removes the rule and decompacts the parent policy's remaining rules back to
    # contiguous 0-based priorities in their original relative order.

.NOTES
    Sources: https://learn.microsoft.com/powershell/module/exchangepowershell/set-dlpcompliancerule
             https://learn.microsoft.com/powershell/module/exchangepowershell/remove-dlpcompliancerule
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$PolicyName = 'PII DLP - Exchange External Send Control',

    [Parameter()]
    [switch]$Purge
)

$ErrorActionPreference = 'Stop'

if (-not (Get-Command Get-DlpCompliancePolicy -ErrorAction SilentlyContinue)) {
    throw 'No Security & Compliance PowerShell session found. Run Connect-IPPSSession first (see docs/automation-surface.md).'
}

$newRuleName = 'PII-Exchange-ElevatedRisk-Block-AllExternal'
$rule = Get-DlpComplianceRule -Identity $newRuleName -ErrorAction SilentlyContinue

if (-not $rule) {
    Write-Host "Rule '$newRuleName' does not exist. Nothing to roll back." -ForegroundColor Yellow
    return
}

if ($Purge) {
    if ($PSCmdlet.ShouldProcess($newRuleName, 'Remove-DlpComplianceRule (permanent)')) {
        Remove-DlpComplianceRule -Identity $newRuleName -Confirm:$false -WhatIf:$WhatIfPreference
    }
    Write-Host "Permanently removed rule '$newRuleName'." -ForegroundColor Green

    # --- Decompact remaining rules: preserve their current relative order, reassign contiguous
    #     priorities starting at 0. Reverse of the compaction New-ExchangePiiElevatedRiskBlock.ps1
    #     performs. Applied lowest-target-priority-first (ascending) since removing the rule above
    #     already freed priority 0 - no collision risk restoring downward. -->
    $remainingRules = @(Get-DlpComplianceRule -Policy $PolicyName -ErrorAction SilentlyContinue)
    $orderedAscendingByCurrentPriority = $remainingRules | Sort-Object -Property Priority
    $targetPriority = 0
    $decompactionPlan = foreach ($r in $orderedAscendingByCurrentPriority) {
        [PSCustomObject]@{ Name = $r.Name; CurrentPriority = $r.Priority; TargetPriority = $targetPriority }
        $targetPriority++
    }

    foreach ($entry in ($decompactionPlan | Sort-Object -Property TargetPriority)) {
        if ($entry.CurrentPriority -ne $entry.TargetPriority) {
            if ($PSCmdlet.ShouldProcess($entry.Name, "Set-DlpComplianceRule -Priority $($entry.TargetPriority)")) {
                Set-DlpComplianceRule -Identity $entry.Name -Priority $entry.TargetPriority -WhatIf:$WhatIfPreference
            }
            Write-Host "Restored rule '$($entry.Name)' to priority $($entry.TargetPriority)." -ForegroundColor Green
        }
    }
}
else {
    if ($PSCmdlet.ShouldProcess($newRuleName, 'Set-DlpComplianceRule -BlockAccess $false (audit-only)')) {
        Set-DlpComplianceRule -Identity $newRuleName -BlockAccess $false -WhatIf:$WhatIfPreference
    }
    Write-Host "Rule '$newRuleName' switched to audit-only. Re-run New-ExchangePiiElevatedRiskBlock.ps1 -Force to restore blocking." -ForegroundColor Green
}
```