---
part: "deploy"
parent: "dlp/pci-teams-exfil-block-part2-obfuscation-mitigation"
---
The scripts and configuration below deploy this scenario. Review them, then run in order — each is designed to be idempotent and has a matching rollback.


#### `New-PciElevatedRiskTeamsBlock.ps1`

```powershell
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
```

#### `policy/irm-drip-exfiltration-config-manifest.json`

```json
{
  "_comment": "REFERENCE MANIFEST, NOT AN API PAYLOAD. Every field below is a portal-only configuration step (README.md Section 5, design.md Section 5) - no script in this scenario's deploy/ folder reads or applies this file. It is a structured, versioned source of truth for the person completing the portal steps, so the deployed configuration can be diffed against intent during review. Only deploy/New-PciElevatedRiskTeamsBlock.ps1 (the DLP rule) is scripted.",
  "communicationComplianceIndicator": {
    "path": "Purview portal > Insider Risk Management > Settings > Policy indicators > Communication Compliance indicators (preview) > Detect messages matching specific trainable classifiers (preview) > Create policy",
    "sitsToSelect": ["Credit Card Number"],
    "note": "This is the ONLY documented path that extends Insider Risk Management coverage to Microsoft Teams messages for this scenario. The 'Data loss prevention (DLP) alerts' indicator explicitly does NOT support Microsoft Teams as a workload - see design.md Section 3. Enabling this creates or resumes a Communication Compliance policy named 'Insider risk SIT indicator <timestamp>' that monitors Exchange Online, Microsoft Teams, Microsoft Viva Engage, and Microsoft 365 Copilot/Copilot Chat for the selected SITs.",
    "coversTeams": true,
    "sourceCaveat": "This indicator is still per-message SIT pattern matching under the hood - it has the SAME split-content blind spot as Part 1's own DLP rule for a truly, perfectly split PAN. Its value here is as one more input to Cumulative Exfiltration Detection (below), not as a content-correlation fix."
  },
  "feederInsiderRiskPolicy": {
    "name": "IRM-PCI-Card-Data-Drip-Exfiltration (buyer names as appropriate)",
    "template": "Data leaks",
    "scope": "Same user population as scenarios/dlp/pci-teams-exfil-block (Card Operations, Finance, and/or all users depending on tenant sizing) - not limited to departing users, unlike scenarios/insider-risk/departing-employee-data-theft",
    "triggeringEvent": "User performs an exfiltration activity (built-in Office exfiltration indicators) - NOT a DLP-policy-match trigger, because the DLP-alert trigger only supports Exchange Online/SharePoint Online/OneDrive for Business workloads and would silently exclude Teams (design.md Section 6)",
    "policyIndicators": [
      "Communication Compliance indicator: Credit Card Number SIT detected in a message",
      "Built-in Office exfiltration indicators (defaults) - e.g. sending email with attachments to recipients outside the organization, downloading content from Teams/SharePoint/OneDrive"
    ],
    "cumulativeExfiltrationDetection": "ON (default for the Data leaks template) - the specific ML-based feature Microsoft documents for detecting exfiltration activity that 'exceed[s] the normal amount performed by users in your organization... over multiple exfiltration activity types', including gradual/slow-drip patterns",
    "sequenceDetection": "Enabled with default sequences - optional, not the primary mechanism this fragment relies on",
    "priorityContent": "Sensitive information types: Credit Card Number (increases risk score for any activity involving it)",
    "evaluationCadence": "Cumulative exfiltration detection is evaluated ~daily, not real-time - see README.md Section 11"
  },
  "adaptiveProtectionScope": {
    "action": "Add the new IRM-PCI-Card-Data-Drip-Exfiltration policy to Adaptive Protection's feeder-policy scope, in addition to (not instead of) any existing feeder policy such as scenarios/insider-risk/departing-employee-data-theft",
    "path": "Purview portal > Insider Risk Management > Adaptive protection > Insider risk levels",
    "note": "Insider risk levels are tenant-wide, computed from every feeder policy in scope - see scenarios/adaptive-protection/dynamic-risk-dlp-enforcement/README.md Section 11, an already-documented constraint this fragment inherits rather than re-derives."
  },
  "dlpRule": {
    "name": "PCI-ElevatedRisk-Block-AllExternal",
    "deployedBy": "deploy/New-PciElevatedRiskTeamsBlock.ps1",
    "addedToPolicy": "PCI DSS - Teams Card Data Exfiltration Block (scenarios/dlp/pci-teams-exfil-block)",
    "priority": 0,
    "condition": "SharedByIRMUserRisk = Elevated AND AccessScope = NotInOrganization (no content/SIT condition)",
    "action": "Block, no override (even for Card Ops group members)"
  },
  "residualGap": "This configuration does NOT detect or block the first message of a perfectly-executed split-PAN attempt - no Microsoft capability performs cross-message content reconstruction as of this writing. See README.md Section 11 and design.md Section 1.",
  "schemaVersion": "1.0",
  "lastUpdated": "2026-09-04"
}
```

#### `Remove-PciElevatedRiskTeamsBlock.ps1`

```powershell
#Requires -Modules @{ ModuleName = 'ExchangeOnlineManagement'; ModuleVersion = '3.2.0' }
<#
.SYNOPSIS
    Rolls back the PCI-ElevatedRisk-Block-AllExternal rule added by
    New-PciElevatedRiskTeamsBlock.ps1, restoring Part 1's policy to its original three-rule state.

.DESCRIPTION
    Two rollback modes:
      -Disable (default, recommended first step): sets the rule's action to audit-only
       (BlockAccess = $false) instead of removing it - reversible in seconds by re-running
       New-PciElevatedRiskTeamsBlock.ps1 -Force, which restores BlockAccess = $true.
      -Purge: permanently removes the rule via Remove-DlpComplianceRule, then re-prioritizes
       Part 1's three original rules back to 0/1/2. NOT reversible except by re-running
       New-PciElevatedRiskTeamsBlock.ps1 from scratch.

    This script never touches Part 1's own three rules' conditions or actions - only their
    -Priority value (Purge mode only, to restore the original 0/1/2 ordering).

    Idempotent: if the rule does not exist, the script reports that and exits cleanly.

.PARAMETER PolicyName
    Name of the parent DLP policy. Must match the -PolicyName used at deploy time.

.PARAMETER Purge
    Permanently delete the PCI-ElevatedRisk-Block-AllExternal rule and restore Part 1's original
    rule priorities, instead of disabling (audit-only) the rule's block action.

.PARAMETER WhatIf
    Standard PowerShell ShouldProcess dry-run.

.EXAMPLE
    Connect-IPPSSession -AppId $AppId -Certificate $Cert -Organization $TenantDomain
    ./Remove-PciElevatedRiskTeamsBlock.ps1 -WhatIf

.EXAMPLE
    ./Remove-PciElevatedRiskTeamsBlock.ps1
    # Switches the rule to audit-only (soft rollback) - keeps visibility, stops blocking.

.EXAMPLE
    ./Remove-PciElevatedRiskTeamsBlock.ps1 -Purge
    # Permanently removes the rule and restores Part 1's original 0/1/2 priority order.

.NOTES
    Sources: https://learn.microsoft.com/powershell/module/exchangepowershell/set-dlpcompliancerule
             https://learn.microsoft.com/powershell/module/exchangepowershell/remove-dlpcompliancerule
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$PolicyName = 'PCI DSS - Teams Card Data Exfiltration Block',

    [Parameter()]
    [switch]$Purge
)

$ErrorActionPreference = 'Stop'

if (-not (Get-Command Get-DlpCompliancePolicy -ErrorAction SilentlyContinue)) {
    throw 'No Security & Compliance PowerShell session found. Run Connect-IPPSSession first (see docs/automation-surface.md).'
}

$newRuleName = 'PCI-ElevatedRisk-Block-AllExternal'
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

    $originalPriorities = @(
        @{ Name = 'PCI-CardOps-Override-External'; TargetPriority = 0 }
        @{ Name = 'PCI-Block-External-AllUsers'; TargetPriority = 1 }
        @{ Name = 'PCI-Audit-Internal-AllUsers'; TargetPriority = 2 }
    )
    # Ascending order this time (lowest target first) since removing the new rule already freed
    # priority 0 - no collision risk restoring downward.
    foreach ($entry in ($originalPriorities | Sort-Object -Property TargetPriority)) {
        $existing = Get-DlpComplianceRule -Identity $entry.Name -ErrorAction SilentlyContinue
        if ($existing -and $existing.Priority -ne $entry.TargetPriority) {
            if ($PSCmdlet.ShouldProcess($entry.Name, "Set-DlpComplianceRule -Priority $($entry.TargetPriority)")) {
                Set-DlpComplianceRule -Identity $entry.Name -Priority $entry.TargetPriority -WhatIf:$WhatIfPreference
            }
            Write-Host "Restored rule '$($entry.Name)' to its original priority $($entry.TargetPriority)." -ForegroundColor Green
        }
    }
}
else {
    if ($PSCmdlet.ShouldProcess($newRuleName, 'Set-DlpComplianceRule -BlockAccess $false (audit-only)')) {
        Set-DlpComplianceRule -Identity $newRuleName -BlockAccess $false -WhatIf:$WhatIfPreference
    }
    Write-Host "Rule '$newRuleName' switched to audit-only. Re-run New-PciElevatedRiskTeamsBlock.ps1 -Force to restore blocking." -ForegroundColor Green
}
```