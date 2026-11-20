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

    NOT CONFIRMED TO WORK (closed 2026-11-20): Microsoft's "Data loss prevention Exchange conditions
    and actions reference" documents the -FromScope/-ExceptIfFromScope condition as usable only in
    "DLP policies that are scoped only to Exchange." The target policy here is scoped to the
    Microsoft Copilot, Copilot Chat, and Copilot Cowork location, not Exchange, so this condition is
    documented as unsupported for this rule - expect New-DlpComplianceRule to reject it or to
    silently not take effect. See design.md Sec 4 for the full correction and README.md Sec 5 for
    why the portal path, not this script, is the recommended way to create this rule until
    Microsoft publishes a working PowerShell/AdvancedRule mechanism for this exact condition/
    location pairing. The -RestrictAccess action is unaffected by this finding: it remains the one
    combination Microsoft's own reference publishes a full worked example for on this location
    (design.md Sec 5).

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
    NOT CONFIRMED TO WORK: -FromScope is documented by Microsoft as restricted to DLP policies
    scoped only to Exchange (see .DESCRIPTION above and design.md Sec 4) - this policy is scoped to
    the Copilot location, not Exchange. Use the portal path (README.md Sec 5) to create this rule.
    If you still run this script, compare its output against a portal-created rule using
    Get-DlpComplianceRule -Identity 'Copilot-Exclude-ExternalEmail-Processing' | Format-List FromScope, RestrictAccess
    to see what property the portal actually persisted - it is unlikely to be FromScope.

    VERIFY (tenant rollout, still open): the "Block external email from being processed" action is
    in preview with no documented fixed rollout date - confirm the condition is selectable in the
    portal first (README.md Sec 5).

    Sources (Microsoft Learn, verify before production use):
    - Learn about using Microsoft Purview DLP to protect interactions with Microsoft 365 Copilot
      and Copilot Chat - "Block external email from being processed (preview)" section:
      https://learn.microsoft.com/purview/dlp-microsoft365-copilot-location-learn-about#block-external-email-from-being-processed-preview
    - New-DlpComplianceRule reference (-FromScope, -RestrictAccess parameters and shape):
      https://learn.microsoft.com/powershell/module/exchangepowershell/new-dlpcompliancerule
    - Data loss prevention Exchange conditions and actions reference: -FromScope/-ExceptIfFromScope,
      property type UserScopeFrom, documented as usable only in DLP policies scoped only to
      Exchange - the basis for the correction above:
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
Write-Warning "Microsoft documents -FromScope as usable only in DLP policies scoped only to Exchange (see .NOTES / README.md Sec 5). This policy is scoped to the Copilot location, not Exchange, so this call is expected to be rejected or to silently not take effect. Prefer creating this rule through the portal."

# --- Build the FromScope condition and RestrictAccess action ---
# NOT CONFIRMED TO WORK (closed 2026-11-20): Microsoft documents -FromScope/-ExceptIfFromScope as
# usable only in DLP policies scoped only to Exchange (dlp-exchange-conditions-and-actions
# reference). This policy is scoped to the Microsoft Copilot, Copilot Chat, and Copilot Cowork
# location, not Exchange - so this condition is documented as unsupported here, not merely
# unconfirmed. See design.md Sec 4 and README.md Sec 5/11.
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
