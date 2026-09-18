---
part: "deploy"
parent: "information-protection/auto-label-confidential-exchange"
---
The scripts and configuration below deploy this scenario. Review them, then run in order — each is designed to be idempotent and has a matching rollback.


#### `New-ConfidentialAutoLabelExchangePolicy.ps1`

```powershell
#Requires -Modules @{ ModuleName = 'ExchangeOnlineManagement'; ModuleVersion = '3.2.0' }
<#
.SYNOPSIS
    Deploys the "Confidentiality - Auto-Label PII in Exchange Email" auto-labeling policy and its
    one rule.

.DESCRIPTION
    Creates (or, if already present, leaves untouched and reports) one Microsoft Purview
    auto-labeling policy scoped to Exchange, with one rule:
      - AutoLabel-Confidential-PII-Exchange  - Workload Exchange
    The rule applies the same sensitive-information-type conditions as the sibling SharePoint/
    OneDrive scenario (U.S. Social Security Number OR Credit Card Number, minimum count 1).

    This is the Exchange-location companion to
    scenarios/information-protection/auto-label-confidential-sharepoint/ - a separate policy
    object, not a modification of that scenario's policy, because SharePoint/OneDrive and
    Exchange auto-labeling have materially different location, exclusion, and encryption
    semantics (see design.md).

    Idempotent: if a policy with the same -PolicyName already exists, the script reports its
    current state and takes no action, rather than erroring or creating a duplicate. Re-run with
    -Force to update the rule's properties on an existing policy to match this script's
    definition.

    Author-only reference code. This script never establishes its own connection to a tenant and
    never targets a live tenant by default (-Mode defaults to TestWithNotifications, a
    non-blocking simulation mode). Run Connect-IPPSSession yourself first (see
    docs/automation-surface.md §3 for the certificate app-only pattern), then call this script.

    Prerequisite this script does NOT perform: confirming the target label's scope includes
    "Emails" (a different scope requirement than the sibling scenario's "Files & other data
    assets" - see README.md §3/§11). This script only confirms the label resolves via Get-Label,
    not its scope.

.PARAMETER PolicyName
    Name of the auto-labeling policy. Policy names cannot be changed after creation.

.PARAMETER LabelName
    Name (or GUID) of an existing, published sensitivity label to auto-apply. Must already exist,
    have a label scope that includes "Emails", and must NOT be a parent label. This script does
    not create or validate the label beyond confirming it resolves via Get-Label.

.PARAMETER ExcludedMailboxSmtpAddress
    Optional SMTP address(es) of mailbox(es) to exclude from this policy (e.g. a legal-hold
    mailbox). Maps to -ExchangeSenderException. Excludes that mailbox's OUTBOUND mail only - mail
    SENT TO an excluded mailbox by someone else is still evaluated (see README.md §11 for why this
    is asymmetric and not a drop-in replacement for a SharePoint-style site exclusion).

.PARAMETER ExternalMailRightsManagementOwner
    Optional SMTP address of the Rights Management owner to use when this policy's label applies
    encryption to mail sent by an external sender. Without this, encryption is applied
    automatically for internal senders but NOT for external senders (Microsoft Learn:
    apply-sensitivity-label-automatically). Left unset by default - see README.md §6/§11.

.PARAMETER Mode
    Auto-labeling policy mode: Enable, Disable, TestWithNotifications, or
    TestWithoutNotifications (Set-AutoSensitivityLabelPolicy -Mode; Microsoft Learn:
    set-autosensitivitylabelpolicy). Defaults to TestWithNotifications so a first run never
    labels live mail. Remember: Exchange simulation only evaluates mail sent/received WHILE the
    policy is in a Test* mode - it does not scan mail already in mailboxes (README.md §5/§7).

.PARAMETER Force
    If the policy already exists, update its rule to match this script's definition instead of
    skipping.

.PARAMETER WhatIf
    Standard PowerShell ShouldProcess dry-run. Reports every New-/Set-AutoSensitivityLabel* call
    that would be made without calling any mutating cmdlet.

.EXAMPLE
    Connect-IPPSSession -AppId $AppId -Certificate $Cert -Organization $TenantDomain
    ./New-ConfidentialAutoLabelExchangePolicy.ps1 -LabelName 'Confidential' `
        -ExcludedMailboxSmtpAddress 'legalhold@contoso.com' -WhatIf

    Dry-run: shows exactly what would be created, changes nothing.

.EXAMPLE
    ./New-ConfidentialAutoLabelExchangePolicy.ps1 -LabelName 'Confidential' `
        -ExcludedMailboxSmtpAddress 'legalhold@contoso.com'

    Deploys in simulation mode. Send/receive representative test mail while simulation runs -
    Exchange simulation does not scan existing mailbox content.

.EXAMPLE
    ./New-ConfidentialAutoLabelExchangePolicy.ps1 -LabelName 'Confidential' -Mode Enable -Force

    Deploys (or updates) the policy in full enforcement mode.

.NOTES
    Sources (Microsoft Learn, verify before production use):
    - Automatically apply a sensitivity label to Microsoft 365 data (Exchange behavior,
      simulation semantics, external-sender encryption defaults):
      https://learn.microsoft.com/purview/apply-sensitivity-label-automatically
    - New-AutoSensitivityLabelPolicy reference (-ExchangeLocation, -ExchangeSenderException,
      -ExternalMailRightsManagementOwner - confirms no -ExchangeLocationException parameter
      exists, unlike -SharePointLocationException/-OneDriveLocationException):
      https://learn.microsoft.com/powershell/module/exchangepowershell/new-autosensitivitylabelpolicy
    - New-AutoSensitivityLabelRule reference (-Workload Exchange):
      https://learn.microsoft.com/powershell/module/exchangepowershell/new-autosensitivitylabelrule
    - Data Loss Prevention policy reference (Content contains: Any of these / All of these):
      https://learn.microsoft.com/purview/dlp-policy-reference#rules
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$PolicyName = 'Confidentiality - Auto-Label PII in Exchange Email',

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$LabelName = 'Confidential',

    [Parameter()]
    [string[]]$ExcludedMailboxSmtpAddress,

    [Parameter()]
    [string]$ExternalMailRightsManagementOwner,

    [Parameter()]
    [ValidateSet('Enable', 'Disable', 'TestWithNotifications', 'TestWithoutNotifications')]
    [string]$Mode = 'TestWithNotifications',

    [Parameter()]
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

function Assert-IppsSession {
    # Get-AutoSensitivityLabelPolicy is only exported after a successful Connect-IPPSSession; its absence means the caller never connected.
    if (-not (Get-Command Get-AutoSensitivityLabelPolicy -ErrorAction SilentlyContinue)) {
        throw 'No Security & Compliance PowerShell session found. Run Connect-IPPSSession first (see docs/automation-surface.md).'
    }
}

Assert-IppsSession

$label = Get-Label -Identity $LabelName -ErrorAction SilentlyContinue
if (-not $label) {
    throw "Label '$LabelName' was not found. This script requires an existing, published sensitivity label whose scope includes Emails - see README.md §3 (label authoring is a prerequisite, not deployed by this scenario)."
}

$ruleName = 'AutoLabel-Confidential-PII-Exchange'
$sitConditions = @(
    @{ name = 'U.S. Social Security Number (SSN)'; mincount = '1' },
    @{ name = 'Credit Card Number'; mincount = '1' }
)

$existingPolicy = Get-AutoSensitivityLabelPolicy -Identity $PolicyName -ErrorAction SilentlyContinue

if ($existingPolicy -and -not $Force) {
    Write-Host "Policy '$PolicyName' already exists (Mode: $($existingPolicy.Mode)). No changes made. Pass -Force to reconcile the rule to this script's definition." -ForegroundColor Yellow
    return
}

$policyParams = @{
    Name                  = $PolicyName
    ApplySensitivityLabel = $LabelName
    ExchangeLocation      = 'All'
    Mode                  = $Mode
    OverwriteLabel        = $true
    Comment               = 'Auto-labels Exchange email containing SSN or Credit Card Number as Confidential. Deployed by scenarios/information-protection/auto-label-confidential-exchange. Owner: Information Protection team.'
}
if ($ExcludedMailboxSmtpAddress) {
    $policyParams['ExchangeSenderException'] = $ExcludedMailboxSmtpAddress
}
if ($ExternalMailRightsManagementOwner) {
    $policyParams['ExternalMailRightsManagementOwner'] = $ExternalMailRightsManagementOwner
}

if (-not $existingPolicy) {
    if ($PSCmdlet.ShouldProcess($PolicyName, 'New-AutoSensitivityLabelPolicy (Exchange, All locations)')) {
        New-AutoSensitivityLabelPolicy @policyParams -WhatIf:$WhatIfPreference | Out-Null
    }
    Write-Host "Created auto-labeling policy '$PolicyName' (Mode: $Mode)." -ForegroundColor Green
}
else {
    # Conservative reconciliation: only -Mode is set here, matching the pattern in
    # scenarios/information-protection/auto-label-confidential-sharepoint/deploy/
    # New-ConfidentialAutoLabelPolicy.ps1. Sender-exception/label/external-RM-owner changes on an
    # existing policy are a deliberate re-provisioning decision, not something this script
    # silently reconciles on every -Force run.
    Write-Host "Policy '$PolicyName' exists - reconciling Mode only (-Force). To change the sender exception list, the applied label, or the external Rights Management owner, remove and re-create the policy." -ForegroundColor Yellow
    if ($PSCmdlet.ShouldProcess($PolicyName, "Set-AutoSensitivityLabelPolicy -Mode $Mode")) {
        Set-AutoSensitivityLabelPolicy -Identity $PolicyName -Mode $Mode -WhatIf:$WhatIfPreference
    }
}

# --- Rule: Exchange ---
$rule = Get-AutoSensitivityLabelRule -Identity $ruleName -ErrorAction SilentlyContinue
$ruleParams = @{
    Name                                = $ruleName
    Policy                              = $PolicyName
    Workload                            = 'Exchange'
    ContentContainsSensitiveInformation = $sitConditions
}
if (-not $rule) {
    if ($PSCmdlet.ShouldProcess($ruleName, 'New-AutoSensitivityLabelRule')) {
        New-AutoSensitivityLabelRule @ruleParams -WhatIf:$WhatIfPreference | Out-Null
    }
    Write-Host "Created rule '$ruleName'." -ForegroundColor Green
}
elseif ($Force) {
    $ruleParams.Remove('Policy') | Out-Null
    $ruleParams.Remove('Name') | Out-Null
    $ruleParams.Remove('Workload') | Out-Null
    if ($PSCmdlet.ShouldProcess($ruleName, 'Set-AutoSensitivityLabelRule')) {
        Set-AutoSensitivityLabelRule -Identity $ruleName @ruleParams -WhatIf:$WhatIfPreference
    }
    Write-Host "Updated rule '$ruleName'." -ForegroundColor Green
}

Write-Host "`nDone. Exchange auto-labeling evaluates mail in transit only - send/receive test messages while in simulation mode to see matches (README.md §5/§7). Confirm the '$LabelName' label's scope includes Emails before expecting matches. Run validate/Test-ConfidentialAutoLabelExchangePolicy.ps1 to verify the deployed configuration." -ForegroundColor Cyan
```

#### `Remove-ConfidentialAutoLabelExchangePolicy.ps1`

```powershell
#Requires -Modules @{ ModuleName = 'ExchangeOnlineManagement'; ModuleVersion = '3.2.0' }
<#
.SYNOPSIS
    Removes (or disables) the "Confidentiality - Auto-Label PII in Exchange Email" auto-labeling
    policy.

.DESCRIPTION
    Two rollback modes:
      -Disable (default, recommended first step): sets the policy Mode to Disable. Reversible in
       seconds via Set-AutoSensitivityLabelPolicy -Mode Enable. Mail already labeled/encrypted by
       this policy is not affected retroactively - Exchange auto-labeling only ever acted on mail
       already in transit at the time.
      -Purge: permanently deletes the policy and its rule via Remove-AutoSensitivityLabelPolicy.
       Removing the policy also removes its rule. This is NOT reversible - re-deploying requires
       re-running New-ConfidentialAutoLabelExchangePolicy.ps1.

    Idempotent: if the policy does not exist, the script reports that and exits cleanly rather
    than erroring.

.PARAMETER PolicyName
    Name of the auto-labeling policy to roll back. Must match the -PolicyName used at deploy time.

.PARAMETER Purge
    Permanently delete the policy instead of disabling it. See rollback.md for the recommended
    disable-first, purge-later sequence.

.PARAMETER WhatIf
    Standard PowerShell ShouldProcess dry-run - reports the disable/removal that would happen
    without calling Set-AutoSensitivityLabelPolicy / Remove-AutoSensitivityLabelPolicy.

.EXAMPLE
    Connect-IPPSSession -AppId $AppId -Certificate $Cert -Organization $TenantDomain
    ./Remove-ConfidentialAutoLabelExchangePolicy.ps1 -WhatIf

.EXAMPLE
    ./Remove-ConfidentialAutoLabelExchangePolicy.ps1
    # Disables the policy (soft rollback).

.EXAMPLE
    ./Remove-ConfidentialAutoLabelExchangePolicy.ps1 -Purge
    # Permanently deletes the policy and its rule.

.NOTES
    Sources: https://learn.microsoft.com/powershell/module/exchangepowershell/set-autosensitivitylabelpolicy
             https://learn.microsoft.com/powershell/module/exchangepowershell/remove-autosensitivitylabelpolicy
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$PolicyName = 'Confidentiality - Auto-Label PII in Exchange Email',

    [Parameter()]
    [switch]$Purge
)

$ErrorActionPreference = 'Stop'

if (-not (Get-Command Get-AutoSensitivityLabelPolicy -ErrorAction SilentlyContinue)) {
    throw 'No Security & Compliance PowerShell session found. Run Connect-IPPSSession first (see docs/automation-surface.md).'
}

$policy = Get-AutoSensitivityLabelPolicy -Identity $PolicyName -ErrorAction SilentlyContinue

if (-not $policy) {
    Write-Host "Policy '$PolicyName' does not exist. Nothing to roll back." -ForegroundColor Yellow
    return
}

if ($Purge) {
    if ($PSCmdlet.ShouldProcess($PolicyName, 'Remove-AutoSensitivityLabelPolicy (permanent, also removes its rule)')) {
        Remove-AutoSensitivityLabelPolicy -Identity $PolicyName -Confirm:$false -WhatIf:$WhatIfPreference
    }
    Write-Host "Permanently removed policy '$PolicyName' and its rule. Mail already labeled/encrypted by this policy while it was active is not affected." -ForegroundColor Green
}
else {
    if ($PSCmdlet.ShouldProcess($PolicyName, 'Set-AutoSensitivityLabelPolicy -Mode Disable')) {
        Set-AutoSensitivityLabelPolicy -Identity $PolicyName -Mode Disable -WhatIf:$WhatIfPreference
    }
    Write-Host "Disabled policy '$PolicyName'. Re-enable with: Set-AutoSensitivityLabelPolicy -Identity '$PolicyName' -Mode Enable" -ForegroundColor Green
}
```