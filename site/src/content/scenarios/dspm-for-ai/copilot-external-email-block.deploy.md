---
part: "deploy"
parent: "dspm-for-ai/copilot-external-email-block"
---
The scripts and configuration below deploy this scenario. Review them, then run in order — each is designed to be idempotent and has a matching rollback.


#### `Add-CopilotExternalEmailBlockRule.ps1`

```powershell
#Requires -Modules @{ ModuleName = 'ExchangeOnlineManagement'; ModuleVersion = '3.2.0' }
<#
.SYNOPSIS
    Adds the "Copilot-Exclude-ExternalEmail-Processing" rule to an existing Copilot-location DLP
    policy (by default, the one deployed by scenarios/dspm-for-ai/copilot-sensitive-data-exposure).

.DESCRIPTION
    Extends an existing Microsoft Purview DLP policy scoped to the Microsoft 365 Copilot and
    Copilot Chat location with a fourth rule that excludes email received from a sender outside the
    tenant's Exchange accepted domains from Copilot grounding, summarization, and citation -
    Microsoft's "Block external email from being processed" (preview) action. Unlike this policy's
    other three rules, this rule reacts to sender-domain metadata, not prompt or file/email content.

    Idempotent: if a rule with the same name already exists on the target policy, the script
    reports its current state and takes no action unless -Force is passed, in which case the rule's
    properties are reconciled to this script's definition via Set-DlpComplianceRule.

    Does NOT create the target policy - it must already exist (run
    scenarios/dspm-for-ai/copilot-sensitive-data-exposure/deploy/
    New-CopilotSensitiveDataProtectionPolicy.ps1 first). Does NOT change the policy's Mode; this
    rule inherits whatever Mode the policy is already in (see README.md Sec 8).

    Author-only reference code. This script never establishes its own connection to a tenant. Run
    Connect-IPPSSession yourself first (see docs/automation-surface.md Sec 3), then call this script.

    VERIFY before production reliance: the -FromScope condition parameter this script uses is
    confirmed to exist in New-DlpComplianceRule's parameter set (shared across every DLP location),
    and its two allowed values (InOrganization/NotInOrganization) are independently confirmed - but
    no Microsoft-published worked example combines -FromScope with the Microsoft 365 Copilot and
    Copilot Chat location specifically. See design.md Sec 4 for the full reasoning and README.md
    Sec 5 for the recommended portal-vs-script comparison step before production use. The
    -RestrictAccess action, by contrast, is the one combination Microsoft's own reference publishes
    a full worked example for on this location (design.md Sec 5) - the better-grounded half of this
    rule.

.PARAMETER PolicyName
    Name of the existing Copilot-location DLP policy to add this rule to. Must already exist -
    this script does not create policies. Defaults to the parent scenario's policy name.

.PARAMETER AdminNotificationEmail
    One or more admin/SOC mailbox addresses to receive incident reports and alerts.

.PARAMETER Priority
    Rule evaluation priority. Defaults to 3, placing this rule after the parent scenario's Rule 0
    (label exclusion, priority 0), Rule 1 (web-grounding restriction, priority 1), and the
    copilot-prompt-full-block sibling's Rule 2 (prompt full-block, priority 2). Change only if your
    policy's existing rules use a different numbering scheme.

.PARAMETER ReportSeverityLevel
    Severity level recorded on generated incident reports. Defaults to 'Low' - unlike this policy's
    other three rules, a match here is an expected, routine consequence of receiving any external
    email, not by itself an anomalous or high-risk event (see design.md Sec 6). Raise it if your
    environment wants this treated as a higher-assurance signal.

.PARAMETER Force
    If the rule already exists, update its properties to match this script's definition instead of
    skipping.

.PARAMETER WhatIf
    Standard PowerShell ShouldProcess dry-run. Reports the New-/Set-DlpComplianceRule call that
    would be made without calling any mutating cmdlet.

.EXAMPLE
    Connect-IPPSSession -AppId $AppId -Certificate $Cert -Organization $TenantDomain
    ./Add-CopilotExternalEmailBlockRule.ps1 -AdminNotificationEmail 'soc@contoso.com' -WhatIf

    Dry-run: shows exactly what would be created, changes nothing.

.EXAMPLE
    ./Add-CopilotExternalEmailBlockRule.ps1 -AdminNotificationEmail 'soc@contoso.com'

    Adds the rule to the default parent-scenario policy.

.EXAMPLE
    ./Add-CopilotExternalEmailBlockRule.ps1 -AdminNotificationEmail 'soc@contoso.com' `
        -ReportSeverityLevel 'Medium' -Force

    Adds (or reconciles, if already present) the rule with a raised default severity.

.NOTES
    VERIFY (production reliance): see the .DESCRIPTION VERIFY block above and design.md Sec 4.
    Compare this script's output against a rule created once through the portal using
    Get-DlpComplianceRule -Identity 'Copilot-Exclude-ExternalEmail-Processing' | Format-List FromScope, RestrictAccess
    before enforcing in production.

    VERIFY (tenant rollout): the "Block external email from being processed" action is in preview
    with no documented fixed rollout date - if the underlying service hasn't received the feature
    yet, this script's New-DlpComplianceRule call may be rejected or silently no-op the FromScope
    condition rather than erroring clearly. Confirm the condition is selectable in the portal first
    (README.md Sec 5).

    Sources (Microsoft Learn, verify before production use):
    - Learn about using Microsoft Purview DLP to protect interactions with Microsoft 365 Copilot
      and Copilot Chat - "Block external email from being processed (preview)" section:
      https://learn.microsoft.com/purview/dlp-microsoft365-copilot-location-learn-about#block-external-email-from-being-processed-preview
    - New-DlpComplianceRule reference (-FromScope, -RestrictAccess parameters and shape):
      https://learn.microsoft.com/powershell/module/exchangepowershell/new-dlpcompliancerule
    - Data loss prevention Exchange conditions and actions reference (-FromScope/-ExceptIfFromScope,
      property type UserScopeFrom):
      https://learn.microsoft.com/purview/dlp-exchange-conditions-and-actions
    - New-DlpCompliancePolicy reference, Example 4 (ExcludeContentProcessing/Block RestrictAccess
      pair, confirmed for a label condition on this same location):
      https://learn.microsoft.com/powershell/module/exchangepowershell/new-dlpcompliancepolicy
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$PolicyName = 'Copilot DLP - Sensitive Data Exposure Protection',

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string[]]$AdminNotificationEmail,

    [Parameter()]
    [ValidateRange(0, 10000)]
    [int]$Priority = 3,

    [Parameter()]
    [ValidateSet('Low', 'Medium', 'High')]
    [string]$ReportSeverityLevel = 'Low',

    [Parameter()]
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
$ruleName = 'Copilot-Exclude-ExternalEmail-Processing'

function Assert-IppsSession {
    # Get-DlpCompliancePolicy is only exported after a successful Connect-IPPSSession; its absence means the caller never connected.
    if (-not (Get-Command Get-DlpCompliancePolicy -ErrorAction SilentlyContinue)) {
        throw 'No Security & Compliance PowerShell session found. Run Connect-IPPSSession first (see docs/automation-surface.md).'
    }
}

Assert-IppsSession

# --- The target policy must already exist; this script never creates it ---
$policy = Get-DlpCompliancePolicy -Identity $PolicyName -ErrorAction SilentlyContinue
if (-not $policy) {
    throw "Policy '$PolicyName' was not found. This scenario extends an existing Copilot-location DLP policy - run scenarios/dspm-for-ai/copilot-sensitive-data-exposure/deploy/New-CopilotSensitiveDataProtectionPolicy.ps1 first, or pass -PolicyName to target a different existing policy."
}

Write-Host "Target policy '$PolicyName' found (Mode: $($policy.Mode)). This rule will inherit that Mode - see README.md Sec 8." -ForegroundColor Cyan

# --- Build the FromScope condition and RestrictAccess action ---
# VERIFY: -FromScope is a confirmed New-DlpComplianceRule parameter with confirmed allowed values
# (InOrganization/NotInOrganization), but no Microsoft-published example combines it with the
# Microsoft 365 Copilot location specifically. See design.md Sec 4.
$ruleParams = @{
    Name           = $ruleName
    Policy         = $PolicyName
    Priority       = $Priority
    FromScope      = 'NotInOrganization'
    RestrictAccess = @(@{ setting = 'ExcludeContentProcessing'; value = 'Block' })
    NotifyUser     = @('LastModifier') + $AdminNotificationEmail
    GenerateAlert  = $AdminNotificationEmail
    GenerateIncidentReport = $AdminNotificationEmail
    ReportSeverityLevel    = $ReportSeverityLevel
}

$existingRule = Get-DlpComplianceRule -Identity $ruleName -ErrorAction SilentlyContinue

if (-not $existingRule) {
    if ($PSCmdlet.ShouldProcess($ruleName, "New-DlpComplianceRule on policy '$PolicyName'")) {
        New-DlpComplianceRule @ruleParams -WhatIf:$WhatIfPreference | Out-Null
    }
    Write-Host "Created rule '$ruleName' on policy '$PolicyName'." -ForegroundColor Green
}
elseif ($Force) {
    $ruleParams.Remove('Policy') | Out-Null
    $ruleParams.Remove('Name') | Out-Null
    if ($PSCmdlet.ShouldProcess($ruleName, 'Set-DlpComplianceRule')) {
        Set-DlpComplianceRule -Identity $ruleName @ruleParams -WhatIf:$WhatIfPreference
    }
    Write-Host "Updated rule '$ruleName'." -ForegroundColor Green
}
else {
    Write-Host "Rule '$ruleName' already exists. No changes made. Pass -Force to reconcile it to this script's definition." -ForegroundColor Yellow
}

Write-Host "`nDone. Policy sync to the Copilot experience can take up to ~4 hours. Run validate/Test-CopilotExternalEmailBlockRule.ps1 to verify the deployed configuration, and see README.md Sec 5 for the recommended portal-comparison step before production reliance." -ForegroundColor Cyan
```

#### `Remove-CopilotExternalEmailBlockRule.ps1`

```powershell
#Requires -Modules @{ ModuleName = 'ExchangeOnlineManagement'; ModuleVersion = '3.2.0' }
<#
.SYNOPSIS
    Disables (default) or permanently removes (-Purge) the "Copilot-Exclude-ExternalEmail-
    Processing" DLP rule only - never touches the parent policy or its other rules.

.DESCRIPTION
    Default behavior is reversible: sets the rule's Disabled property to $true, leaving it defined
    and re-enable-able (Set-DlpComplianceRule -Disabled $false). Pass -Purge to permanently delete
    the rule via Remove-DlpComplianceRule - not reversible; re-establishing it means re-running
    deploy/Add-CopilotExternalEmailBlockRule.ps1.

    Scoped to this one rule by design - the parent policy (scenarios/dspm-for-ai/
    copilot-sensitive-data-exposure) and its other rules (including the copilot-prompt-full-block
    sibling's Rule 2) are never modified by this script.

    Author-only reference code. Never runs against a live tenant without an explicit
    Connect-IPPSSession call made by the operator first.

.PARAMETER Purge
    Permanently deletes the rule instead of disabling it. Not reversible - see rollback.md.

.PARAMETER WhatIf
    Standard PowerShell ShouldProcess dry-run.

.EXAMPLE
    Connect-IPPSSession -AppId $AppId -Certificate $Cert -Organization $TenantDomain
    ./Remove-CopilotExternalEmailBlockRule.ps1 -WhatIf

.EXAMPLE
    ./Remove-CopilotExternalEmailBlockRule.ps1
    # Disables the rule (reversible)

.EXAMPLE
    ./Remove-CopilotExternalEmailBlockRule.ps1 -Purge
    # Permanently deletes the rule

.NOTES
    Sources (Microsoft Learn):
    - Set-DlpComplianceRule reference (-Disabled parameter):
      https://learn.microsoft.com/powershell/module/exchangepowershell/set-dlpcompliancerule
    - Remove-DlpComplianceRule reference:
      https://learn.microsoft.com/powershell/module/exchangepowershell/remove-dlpcompliancerule
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter()]
    [switch]$Purge
)

$ErrorActionPreference = 'Stop'
$ruleName = 'Copilot-Exclude-ExternalEmail-Processing'

if (-not (Get-Command Get-DlpComplianceRule -ErrorAction SilentlyContinue)) {
    throw 'No Security & Compliance PowerShell session found. Run Connect-IPPSSession first (see docs/automation-surface.md).'
}

$rule = Get-DlpComplianceRule -Identity $ruleName -ErrorAction SilentlyContinue
if (-not $rule) {
    Write-Host "Rule '$ruleName' not found. Nothing to do." -ForegroundColor Yellow
    return
}

if ($Purge) {
    if ($PSCmdlet.ShouldProcess($ruleName, 'Remove-DlpComplianceRule (permanent - this rule only)')) {
        Remove-DlpComplianceRule -Identity $ruleName -Confirm:$false -WhatIf:$WhatIfPreference
    }
    Write-Host "Permanently removed rule '$ruleName'. The parent policy and its other rules are unaffected." -ForegroundColor Red
}
else {
    if ($PSCmdlet.ShouldProcess($ruleName, 'Set-DlpComplianceRule -Disabled $true')) {
        Set-DlpComplianceRule -Identity $ruleName -Disabled $true -WhatIf:$WhatIfPreference
    }
    Write-Host "Disabled rule '$ruleName' (reversible - re-enable with Set-DlpComplianceRule -Identity '$ruleName' -Disabled `$false). The parent policy and its other rules are unaffected." -ForegroundColor Yellow
}
```