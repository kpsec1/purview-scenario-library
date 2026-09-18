---
part: "deploy"
parent: "dspm-for-ai/copilot-prompt-full-block"
---
The scripts and configuration below deploy this scenario. Review them, then run in order — each is designed to be idempotent and has a matching rollback.


#### `Add-CopilotPromptFullBlockRule.ps1`

```powershell
#Requires -Modules @{ ModuleName = 'ExchangeOnlineManagement'; ModuleVersion = '3.2.0' }
<#
.SYNOPSIS
    Adds the "Copilot-Block-SensitivePrompts-FullResponse" rule to an existing Copilot-location DLP
    policy (by default, the one deployed by scenarios/dspm-for-ai/copilot-sensitive-data-exposure).

.DESCRIPTION
    Extends an existing Microsoft Purview DLP policy scoped to the Microsoft 365 Copilot and
    Copilot Chat location with a third rule that fully blocks a Copilot response when a prompt
    contains one of the configured sensitive information types (SITs) - Microsoft's "Prevent
    Copilot from processing content > Processing prompts" action. This is a stronger control than
    the parent scenario's Rule 1 (RestrictWebGrounding), which only blocks external web search and
    still lets Copilot answer from internal Microsoft 365 sources.

    Idempotent: if a rule with the same name already exists on the target policy, the script
    reports its current state and takes no action unless -Force is passed, in which case the rule's
    properties are reconciled to this script's definition via Set-DlpComplianceRule.

    Does NOT create the target policy - it must already exist (run
    scenarios/dspm-for-ai/copilot-sensitive-data-exposure/deploy/
    New-CopilotSensitiveDataProtectionPolicy.ps1 first). Does NOT change the policy's Mode; this
    rule inherits whatever Mode the policy is already in (see README.md Sec 8).

    Author-only reference code. This script never establishes its own connection to a tenant. Run
    Connect-IPPSSession yourself first (see docs/automation-surface.md Sec 3), then call this script.

    VERIFY before production reliance: the exact -RestrictAccess setting/value pair this script uses
    (ExcludeContentProcessing/Block) is confirmed by Microsoft's own reference for a DIFFERENT
    condition type (sensitivity label, not CCSI) on this same location. No published Microsoft
    worked example combines a CCSI condition with -RestrictAccess for this specific "Processing
    prompts" action. See design.md Sec 5 for the full reasoning behind still scripting this, and
    README.md Sec 5 for the recommended portal-vs-script comparison step before production use.

.PARAMETER PolicyName
    Name of the existing Copilot-location DLP policy to add this rule to. Must already exist -
    this script does not create policies. Defaults to the parent scenario's policy name.

.PARAMETER SensitiveInformationTypeName
    One or more built-in or custom sensitive information type names whose presence in a Copilot
    prompt should fully block a response. Defaults to Microsoft's own worked-example pair,
    @('Canada physical addresses', 'EU debit card numbers') - deliberately distinct from the parent
    scenario's Rule 1 SITs (SSN, Credit Card Number) to keep rule severity levels unambiguous; see
    design.md Sec 4.

.PARAMETER AdminNotificationEmail
    One or more admin/SOC mailbox addresses to receive incident reports and alerts.

.PARAMETER Priority
    Rule evaluation priority. Defaults to 2, placing this rule after the parent scenario's Rule 0
    (label exclusion, priority 0) and Rule 1 (web-grounding restriction, priority 1). Change only if
    your policy's existing rules use a different numbering scheme.

.PARAMETER Force
    If the rule already exists, update its properties to match this script's definition instead of
    skipping.

.PARAMETER WhatIf
    Standard PowerShell ShouldProcess dry-run. Reports the New-/Set-DlpComplianceRule call that
    would be made without calling any mutating cmdlet.

.EXAMPLE
    Connect-IPPSSession -AppId $AppId -Certificate $Cert -Organization $TenantDomain
    ./Add-CopilotPromptFullBlockRule.ps1 -AdminNotificationEmail 'soc@contoso.com' -WhatIf

    Dry-run: shows exactly what would be created, changes nothing.

.EXAMPLE
    ./Add-CopilotPromptFullBlockRule.ps1 -AdminNotificationEmail 'soc@contoso.com'

    Adds the rule to the default parent-scenario policy.

.EXAMPLE
    ./Add-CopilotPromptFullBlockRule.ps1 -AdminNotificationEmail 'soc@contoso.com' `
        -SensitiveInformationTypeName 'U.S. / U.K. Passport Number', 'U.S. Bank Account Number' `
        -Force

    Adds (or reconciles, if already present) the rule with a custom, buyer-specific SIT set.

.NOTES
    VERIFY (production reliance): see the .DESCRIPTION VERIFY block above and design.md Sec 5.
    Compare this script's output against a rule created once through the portal using
    Get-DlpComplianceRule -Identity 'Copilot-Block-SensitivePrompts-FullResponse' | Format-List RestrictAccess
    before enforcing in production.

    VERIFY (tenant rollout): the "Block sensitive information types in prompts" action is in
    preview and Microsoft's own guidance says to confirm rollout has reached your tenant before
    relying on it - if the underlying service hasn't received the feature yet, this script's
    New-DlpComplianceRule call may be rejected or silently no-op the RestrictAccess setting rather
    than erroring clearly. Confirm the action is selectable in the portal first (README.md Sec 5).

    Sources (Microsoft Learn, verify before production use):
    - Learn about using Microsoft Purview DLP to protect interactions with Microsoft 365 Copilot
      and Copilot Chat - "Block sensitive information types in prompts" section (preview status,
      use-case example, supported actions table):
      https://learn.microsoft.com/purview/dlp-microsoft365-copilot-location-learn-about#block-sensitive-information-types-in-prompts
    - New-DlpComplianceRule reference (-RestrictAccess, -ContentContainsSensitiveInformation
      parameters and shape):
      https://learn.microsoft.com/powershell/module/exchangepowershell/new-dlpcompliancerule
    - New-DlpCompliancePolicy reference, Example 4 (ExcludeContentProcessing/Block RestrictAccess
      pair, confirmed for a label condition on this same location):
      https://learn.microsoft.com/powershell/module/exchangepowershell/new-dlpcompliancepolicy
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$PolicyName = 'Copilot DLP - Sensitive Data Exposure Protection',

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string[]]$SensitiveInformationTypeName = @('Canada physical addresses', 'EU debit card numbers'),

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string[]]$AdminNotificationEmail,

    [Parameter()]
    [ValidateRange(0, 10000)]
    [int]$Priority = 2,

    [Parameter()]
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
$ruleName = 'Copilot-Block-SensitivePrompts-FullResponse'

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

# --- Build the CCSI condition and RestrictAccess action ---
$sitConditions = $SensitiveInformationTypeName | ForEach-Object { @{ name = $_; mincount = '1' } }

$ruleParams = @{
    Name                                 = $ruleName
    Policy                               = $PolicyName
    Priority                             = $Priority
    ContentContainsSensitiveInformation  = $sitConditions
    RestrictAccess                       = @(@{ setting = 'ExcludeContentProcessing'; value = 'Block' })
    NotifyUser                           = @('LastModifier') + $AdminNotificationEmail
    GenerateAlert                        = $AdminNotificationEmail
    GenerateIncidentReport               = $AdminNotificationEmail
    ReportSeverityLevel                  = 'High'
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

Write-Host "`nDone. Policy sync to the Copilot experience can take up to ~4 hours. Run validate/Test-CopilotPromptFullBlockRule.ps1 to verify the deployed configuration, and see README.md Sec 5 for the recommended portal-comparison step before production reliance." -ForegroundColor Cyan
```

#### `Remove-CopilotPromptFullBlockRule.ps1`

```powershell
#Requires -Modules @{ ModuleName = 'ExchangeOnlineManagement'; ModuleVersion = '3.2.0' }
<#
.SYNOPSIS
    Disables (default) or permanently removes (-Purge) the "Copilot-Block-SensitivePrompts-
    FullResponse" DLP rule only - never touches the parent policy or its other rules.

.DESCRIPTION
    Default behavior is reversible: sets the rule's Disabled property to $true, leaving it defined
    and re-enable-able (Set-DlpComplianceRule -Disabled $false). Pass -Purge to permanently delete
    the rule via Remove-DlpComplianceRule - not reversible; re-establishing it means re-running
    deploy/Add-CopilotPromptFullBlockRule.ps1.

    Scoped to this one rule by design - the parent policy (scenarios/dspm-for-ai/
    copilot-sensitive-data-exposure) and its own Rule 0/Rule 1 are never modified by this script.

    Author-only reference code. Never runs against a live tenant without an explicit
    Connect-IPPSSession call made by the operator first.

.PARAMETER Purge
    Permanently deletes the rule instead of disabling it. Not reversible - see rollback.md.

.PARAMETER WhatIf
    Standard PowerShell ShouldProcess dry-run.

.EXAMPLE
    Connect-IPPSSession -AppId $AppId -Certificate $Cert -Organization $TenantDomain
    ./Remove-CopilotPromptFullBlockRule.ps1 -WhatIf

.EXAMPLE
    ./Remove-CopilotPromptFullBlockRule.ps1
    # Disables the rule (reversible)

.EXAMPLE
    ./Remove-CopilotPromptFullBlockRule.ps1 -Purge
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
$ruleName = 'Copilot-Block-SensitivePrompts-FullResponse'

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