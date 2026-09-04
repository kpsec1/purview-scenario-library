#Requires -Version 7.0
<#
.SYNOPSIS
    Deploys the "Confidentiality - Auto-Label PII in Exchange Email" auto-labeling policy and its
    single Exchange rule - using Security & Compliance PowerShell.

.DESCRIPTION
    Creates (or, if already present, reports and leaves untouched) one Microsoft Purview
    auto-labeling policy scoped to the EXCHANGE (email) location, plus one rule:
      - AutoLabel-Confidential-PII-Exchange  - Workload Exchange
    The rule applies an existing "Confidential" sensitivity label to email whose body or
    attachments contain a U.S. Social Security Number OR a Credit Card Number (min count 1 each,
    OR-combined). Optionally excludes email to trusted recipient domains.

    Automation surface 2 (Security & Compliance PowerShell / Connect-IPPSSession) per
    docs/automation-surface.md. Cmdlets: New-/Set-/Get-AutoSensitivityLabelPolicy and
    New-/Set-/Get-AutoSensitivityLabelRule.

    HOW EXCHANGE AUTO-LABELING DIFFERS FROM THE SHAREPOINT/ONEDRIVE SIBLING (grounded, README Sec 4/11):
      - Service-side, IN TRANSIT: it evaluates email as it is sent and received, not messages
        already stored in mailboxes. There is no client/app dependency and no file-at-rest scan.
      - One rule, one workload: email is a single Workload value (Exchange), so there is no
        per-workload rule split like the sibling's SharePoint + OneDrive pair.
      - No -ExchangeLocationException on New-AutoSensitivityLabelPolicy. Scope/exclude email via
        -ExchangeSenderMemberOf / -ExchangeSenderMemberOfException, or via the rule's recipient/
        sender-domain conditions - NOT a location-URL exclusion list.
      - Simulation for Exchange evaluates mail flowing DURING the run (results aren't repeatable
        unless the same messages are re-sent), and starts immediately (SPO/OneDrive wait ~25 days).

    Idempotent: if a policy with the same name exists, the script reports its state and makes no
    change (auto-labeling policies are high-consequence). Re-running is safe.

    -WhatIf is non-functional in Security & Compliance PowerShell, so this script implements its own
    -DryRun that prints the intended cmdlets and invokes none.

    Author-only reference code. It never opens its own session and defaults to -Mode
    TestWithNotifications (simulation - labels nothing). Run Connect-IPPSSession first (certificate
    app-only preferred - docs/automation-surface.md Section 3), then call this script.

    Prerequisite this script does NOT perform: publishing the "Confidential" sensitivity label with
    a scope that includes Emails (README.md Section 3). Unified audit logging must be on for
    simulation to produce results.

.PARAMETER ConfigPath
    Path to the JSON config. Defaults to 'config/auto-label-confidential-exchange.sample.json'.

.PARAMETER Mode
    Overrides policy.mode from the config. Enable | Disable | TestWithNotifications |
    TestWithoutNotifications (Microsoft Learn: set-autosensitivitylabelpolicy). Defaults to the
    config value (TestWithNotifications) so a first run never labels live mail.

.PARAMETER DryRun
    Print every mutating cmdlet that would run and invoke none (the working substitute for -WhatIf,
    which does not function in Security & Compliance PowerShell).

.EXAMPLE
    Connect-IPPSSession -AppId $AppId -Certificate $Cert -Organization 'contoso.onmicrosoft.com'
    ./New-ConfidentialExchangeAutoLabelPolicy.ps1 -DryRun

    Dry run: shows exactly what would be created, changes nothing.

.EXAMPLE
    Connect-IPPSSession -AppId $AppId -Certificate $Cert -Organization 'contoso.onmicrosoft.com'
    ./New-ConfidentialExchangeAutoLabelPolicy.ps1

    Deploys in simulation mode: mail in transit is evaluated and simulation results populate,
    nothing is labeled yet.

.EXAMPLE
    ./New-ConfidentialExchangeAutoLabelPolicy.ps1 -Mode Enable

    Deploys in full enforcement mode (deliberate, after a review window).

.NOTES
    Grounded in Microsoft Learn (verify before production use):
    - New-AutoSensitivityLabelPolicy (-ExchangeLocation, -Mode, -ApplySensitivityLabel,
      -OverwriteLabel, -ExchangeSenderMemberOf(Exception), -ExternalMailRightsManagementOwner,
      -ApplySensitivityLabelOverwriteWorkloads):
      https://learn.microsoft.com/powershell/module/exchangepowershell/new-autosensitivitylabelpolicy
    - New-AutoSensitivityLabelRule (-Workload Exchange, -ContentContainsSensitiveInformation,
      -ExceptIfRecipientDomainIs):
      https://learn.microsoft.com/powershell/module/exchangepowershell/new-autosensitivitylabelrule
    - Set-AutoSensitivityLabelPolicy (-Mode accepted values):
      https://learn.microsoft.com/powershell/module/exchangepowershell/set-autosensitivitylabelpolicy
    - Auto-labeling concepts (Exchange in-transit behavior, simulation, override, encryption owner):
      https://learn.microsoft.com/purview/apply-sensitivity-label-automatically

    VERIFY (pilot tenant): the exact value/semantics of -ApplySensitivityLabelOverwriteWorkloads
    (the wizard's email-only override). The cmdlet reference types it as <Workload> but does not
    enumerate accepted values or spell out how it interacts with the boolean -OverwriteLabel. This
    script sets -OverwriteLabel (boolean, confirmed) and passes
    -ApplySensitivityLabelOverwriteWorkloads only when explicitly provided in the config, unmodified.
#>
[CmdletBinding()]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$ConfigPath = (Join-Path $PSScriptRoot 'config/auto-label-confidential-exchange.sample.json'),

    [Parameter()]
    [ValidateSet('Enable', 'Disable', 'TestWithNotifications', 'TestWithoutNotifications')]
    [string]$Mode,

    [Parameter()]
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

function Assert-SccConnected {
    # Get-AutoSensitivityLabelPolicy is only exported after a successful Connect-IPPSSession.
    if (-not (Get-Command Get-AutoSensitivityLabelPolicy -ErrorAction SilentlyContinue)) {
        throw "Auto-labeling cmdlets not found. Connect first: Connect-IPPSSession (Security & Compliance PowerShell). See docs/automation-surface.md Section 3."
    }
}
function Invoke-Scc {
    param([Parameter(Mandatory)][string]$Describe, [Parameter(Mandatory)][scriptblock]$Action)
    if ($DryRun) { Write-Host "  DRYRUN would run: $Describe" -ForegroundColor DarkYellow; return $null }
    Write-Host "  $Describe" -ForegroundColor Green
    return & $Action
}

if (-not (Test-Path -LiteralPath $ConfigPath)) { throw "Config file not found: $ConfigPath" }
$cfg = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
foreach ($k in 'policy', 'rule') { if (-not $cfg.$k) { throw "Config missing '$k' section." } }
if (-not $cfg.policy.name) { throw "policy.name is required." }
if (-not $cfg.policy.applySensitivityLabel) { throw "policy.applySensitivityLabel is required." }
if (-not $cfg.rule.name) { throw "rule.name is required." }
if (-not $cfg.rule.sensitiveInformationTypes -or @($cfg.rule.sensitiveInformationTypes).Count -eq 0) {
    throw "rule.sensitiveInformationTypes must list at least one sensitive information type."
}

$policyName = $cfg.policy.name
$labelName = $cfg.policy.applySensitivityLabel
$effectiveMode = if ($Mode) { $Mode } elseif ($cfg.policy.mode) { $cfg.policy.mode } else { 'TestWithNotifications' }
$exchangeLocation = if ($cfg.policy.exchangeLocation -and @($cfg.policy.exchangeLocation).Count -gt 0) { @($cfg.policy.exchangeLocation) } else { @('All') }

Assert-SccConnected

# The label is a prerequisite, not created here - fail early with a clear message if it's missing.
$label = Get-Label -Identity $labelName -ErrorAction SilentlyContinue
if (-not $label) {
    throw "Label '$labelName' was not found. This scenario requires an EXISTING, published sensitivity label whose scope includes Emails - see README.md Section 3 (label authoring is a prerequisite, not deployed here)."
}

Write-Host "Deploying Exchange email auto-labeling policy '$policyName' (label '$labelName', mode $effectiveMode)." -ForegroundColor Cyan
if (@($exchangeLocation) -notcontains 'All') {
    Write-Host "WARNING: exchangeLocation is not 'All'. When scoped to specific senders, email sent from OUTSIDE your organization is EXEMPT from this policy (documented behavior). Prefer 'All' + rule conditions to scope. See README.md Section 11." -ForegroundColor Yellow
}
if ($cfg.policy.externalMailRightsManagementOwner) {
    Write-Host "NOTE: externalMailRightsManagementOwner is set - only effective if '$labelName' applies encryption; it assigns a Rights Management owner for inbound external mail (must be a single user, not a group). See README.md Section 11." -ForegroundColor Yellow
}

# --- 1. Policy (New-AutoSensitivityLabelPolicy) ---
$existingPolicy = Get-AutoSensitivityLabelPolicy -Identity $policyName -ErrorAction SilentlyContinue
if ($existingPolicy) {
    Write-Host "  [policy] exists '$policyName' (Mode: $($existingPolicy.Mode)) - not modified. To change mode use Set-AutoSensitivityLabelPolicy or the Remove-* rollback script; to re-provision, remove and re-create." -ForegroundColor DarkGreen
}
else {
    $policyParams = @{
        Name                  = $policyName
        ApplySensitivityLabel = $labelName
        ExchangeLocation      = $exchangeLocation
        Mode                  = $effectiveMode
        OverwriteLabel        = [bool]$cfg.policy.overwriteLabel
    }
    if ($cfg.policy.comment) { $policyParams.Comment = $cfg.policy.comment }
    if ($cfg.policy.exchangeSenderMemberOf -and @($cfg.policy.exchangeSenderMemberOf).Count -gt 0) {
        $policyParams.ExchangeSenderMemberOf = @($cfg.policy.exchangeSenderMemberOf)
    }
    if ($cfg.policy.exchangeSenderMemberOfException -and @($cfg.policy.exchangeSenderMemberOfException).Count -gt 0) {
        $policyParams.ExchangeSenderMemberOfException = @($cfg.policy.exchangeSenderMemberOfException)
    }
    if ($cfg.policy.externalMailRightsManagementOwner) {
        $policyParams.ExternalMailRightsManagementOwner = $cfg.policy.externalMailRightsManagementOwner
    }
    # VERIFY (see .NOTES): pass the email-only override switch only when explicitly provided.
    if ($cfg.policy.applySensitivityLabelOverwriteWorkloads) {
        $policyParams.ApplySensitivityLabelOverwriteWorkloads = $cfg.policy.applySensitivityLabelOverwriteWorkloads
    }

    Invoke-Scc -Describe "New-AutoSensitivityLabelPolicy -Name '$policyName' -ApplySensitivityLabel '$labelName' -ExchangeLocation $($exchangeLocation -join ',') -Mode $effectiveMode -OverwriteLabel `$$([bool]$cfg.policy.overwriteLabel)" `
        -Action { New-AutoSensitivityLabelPolicy @policyParams -Confirm:$false } | Out-Null
    Write-Host "  [policy] created '$policyName' (Mode: $effectiveMode)" -ForegroundColor Green
}

# --- 2. Rule (New-AutoSensitivityLabelRule -Workload Exchange) ---
$sitConditions = @(
    foreach ($sit in $cfg.rule.sensitiveInformationTypes) {
        @{ name = $sit.name; mincount = "$($sit.mincount)" }
    }
)
$existingRule = Get-AutoSensitivityLabelRule -Identity $cfg.rule.name -ErrorAction SilentlyContinue
if ($existingRule) {
    Write-Host "  [rule] exists '$($cfg.rule.name)' - not modified." -ForegroundColor DarkGreen
}
else {
    $ruleParams = @{
        Name                                = $cfg.rule.name
        Policy                              = $policyName
        Workload                            = 'Exchange'
        ContentContainsSensitiveInformation = $sitConditions
    }
    if ($cfg.rule.exceptIfRecipientDomainIs -and @($cfg.rule.exceptIfRecipientDomainIs).Count -gt 0) {
        $ruleParams.ExceptIfRecipientDomainIs = @($cfg.rule.exceptIfRecipientDomainIs)
    }
    $sitNames = ($sitConditions | ForEach-Object { $_.name }) -join ' OR '
    Invoke-Scc -Describe "New-AutoSensitivityLabelRule -Name '$($cfg.rule.name)' -Policy '$policyName' -Workload Exchange -ContentContainsSensitiveInformation ($sitNames)" `
        -Action { New-AutoSensitivityLabelRule @ruleParams -Confirm:$false } | Out-Null
    Write-Host "  [rule] created '$($cfg.rule.name)' (Workload Exchange)" -ForegroundColor Green
}

Write-Host "`nDone." -ForegroundColor Cyan
Write-Host "Exchange auto-labeling evaluates mail IN TRANSIT (sent/received), not stored mailbox items - simulation only shows messages that flow while it runs (~12h to complete). Validate with validate/Test-ConfidentialExchangeAutoLabelPolicy.ps1 and review the Items to review tab in the Purview portal before enabling." -ForegroundColor Yellow
