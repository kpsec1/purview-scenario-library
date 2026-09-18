---
part: "deploy"
parent: "information-protection/auto-label-eu-personal-data-exchange"
---
The scripts and configuration below deploy this scenario. Review them, then run in order — each is designed to be idempotent and has a matching rollback.


#### `New-EuPersonalDataAutoLabelExchangePolicy.ps1`

```powershell
#Requires -Modules @{ ModuleName = 'ExchangeOnlineManagement'; ModuleVersion = '3.2.0' }
<#
.SYNOPSIS
    Deploys the "Confidentiality - Auto-Label EU Personal Data in Exchange Email" auto-labeling
    policy and its one rule.

.DESCRIPTION
    Creates (or, if already present, leaves untouched and reports) one Microsoft Purview
    auto-labeling policy scoped to Exchange, with one rule:
      - AutoLabel-EuPersonalData-Exchange  - Workload Exchange
    Default SITs (see README.md §2/§4, design.md §4): 'EU national identification number',
    'EU Social Security Number (SSN) or Equivalent ID', 'EU debit card number' - the same EU-wide
    bundle set scenarios/information-protection/auto-label-eu-personal-data-sharepoint/ defaults
    to, applied to a different location.

    This scenario is the intersection of two already-built siblings, not a new pattern:
      - Location/exclusion/encryption mechanics: scenarios/information-protection/
        auto-label-confidential-exchange/ (the U.S.-SIT Exchange scenario) - sender-based
        exclusion (-ExchangeSenderException), -ExchangeLocation All, no -ExchangeLocationException
        parameter exists.
      - Sensitive information type set and localization mechanism:
        scenarios/information-protection/auto-label-eu-personal-data-sharepoint/ (the EU-SIT
        SharePoint/OneDrive scenario) - -SensitiveInfoTypeName, resolved against
        Get-DlpSensitiveInformationType at deploy time rather than trusted as a literal string.
    See design.md §3 for why this is a third, sibling scenario rather than a parameter on either
    of the other two.

    LOCALIZATION: -SensitiveInfoTypeName accepts any built-in or custom SIT name(s), not just the
    three EU-wide defaults. A buyer whose regulated population is limited to specific member
    states can pass just those countries' own SITs (e.g. -SensitiveInfoTypeName 'Germany Identity
    Card Number','France Social Security Number') for tighter false-positive control than the
    full EU-wide bundles - see README.md §6 and design.md §5.

    Every configured SIT name is resolved against Get-DlpSensitiveInformationType before any
    policy/rule is created or updated - the same defended-uncertainty pattern as the SharePoint/
    OneDrive sibling's deploy script, for the same unresolved byte-exact-casing VERIFY (design.md
    §4). An unresolved name fails the run immediately and lists the closest available SIT names
    from the tenant's own catalog rather than silently deploying a rule that matches nothing.

    Idempotent: if a policy with the same -PolicyName already exists, the script reports its
    current state and takes no action, rather than erroring or creating a duplicate. Re-run with
    -Force to update the rule's properties on an existing policy to match this script's
    definition.

    Author-only reference code. This script never establishes its own connection to a tenant and
    never targets a live tenant by default (-Mode defaults to TestWithNotifications, a
    non-blocking simulation mode). Run Connect-IPPSSession yourself first (see
    docs/automation-surface.md §3 for the certificate app-only pattern), then call this script.

    Prerequisite this script does NOT perform: confirming the target label's scope includes
    "Emails" (a different scope requirement than the EU/UK SharePoint sibling's "Files & other
    data assets" - see README.md §3/§11). This script only confirms the label resolves via
    Get-Label, not its scope.

.PARAMETER PolicyName
    Name of the auto-labeling policy. Policy names cannot be changed after creation.

.PARAMETER LabelName
    Name (or GUID) of an existing, published sensitivity label to auto-apply. Must already exist,
    have a label scope that includes "Emails", and must NOT be a parent label. This script does
    not create or validate the label beyond confirming it resolves via Get-Label.

.PARAMETER SensitiveInfoTypeName
    One or more sensitive information type names to match on (logical OR, mincount 1 each).
    Defaults to the EU-wide bundle set: 'EU national identification number', 'EU Social Security
    Number (SSN) or Equivalent ID', 'EU debit card number' (design.md §4). Override with a
    narrower, jurisdiction-specific list to localize further (design.md §5) - any name accepted
    by Get-DlpSensitiveInformationType in the connected tenant is valid, not just EU-region SITs.

.PARAMETER IncludeTravelDocumentSits
    Opt-in switch (not a new default - README.md §6, design.md §5). Appends 'EU passport number'
    and "EU driver's license number" to whatever -SensitiveInfoTypeName is in effect (the default
    three-SIT set, or a caller-supplied override), deduplicated, before name resolution. Ported
    from the SharePoint/OneDrive EU sibling's own switch of the same name for parity across both
    locations - same two real, confirmed EU-wide bundle SITs, same append-don't-replace semantics.

    GOTCHA (design.md §5, inherited from the SharePoint/OneDrive sibling's design.md §4): the "EU
    passport number" bundle's U.K. coverage is not a standalone U.K. entity the way the national-ID
    and driver's-license bundles have one - it is a single combined "U.S./U.K. passport number"
    entity. Turning on this switch for U.K.-only travel-document coverage also enables U.S.
    passport number detection as a side effect.

.PARAMETER ExcludedMailboxSmtpAddress
    Optional SMTP address(es) of mailbox(es) to exclude from this policy (e.g. a legal-hold
    mailbox). Maps to -ExchangeSenderException. Excludes that mailbox's OUTBOUND mail only - mail
    SENT TO an excluded mailbox by someone else is still evaluated (see README.md §11 for why this
    is asymmetric and not a drop-in replacement for the SharePoint/OneDrive sibling's site
    exclusion).

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
    ./New-EuPersonalDataAutoLabelExchangePolicy.ps1 -LabelName 'Confidential' `
        -ExcludedMailboxSmtpAddress 'legalhold@contoso.com' -WhatIf

    Dry-run with the default EU-wide SIT set: shows exactly what would be created, changes
    nothing.

.EXAMPLE
    ./New-EuPersonalDataAutoLabelExchangePolicy.ps1 -LabelName 'Confidential' `
        -SensitiveInfoTypeName 'Germany Identity Card Number','France Social Security Number','EU debit card number'

    Deploys in simulation mode (default), localized to Germany + France national ID + the
    region-wide EU debit card SIT instead of the full 26-country default bundle. Send/receive test
    mail while simulation runs - Exchange simulation does not scan existing mailbox content.

.EXAMPLE
    ./New-EuPersonalDataAutoLabelExchangePolicy.ps1 -LabelName 'Confidential' -Mode Enable -Force

    Deploys (or updates) the policy in full enforcement mode with the default EU-wide SIT set.

.EXAMPLE
    ./New-EuPersonalDataAutoLabelExchangePolicy.ps1 -LabelName 'Confidential' -IncludeTravelDocumentSits

    Deploys in simulation mode (default) with the default EU-wide SIT set plus the opt-in
    passport/driver's-license bundle - see the IncludeTravelDocumentSits parameter description for
    the U.S./U.K. passport-entity gotcha before enabling this for a U.K.-only buyer.

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
    - Get-DlpSensitiveInformationType reference (name resolution, -Identity lookup):
      https://learn.microsoft.com/powershell/module/exchangepowershell/get-dlpsensitiveinformationtype
    - EU national identification number / EU Social Security Number (SSN) or Equivalent ID / EU
      debit card number entity definitions:
      https://learn.microsoft.com/purview/sit-defn-eu-national-identification-number
      https://learn.microsoft.com/purview/sit-defn-eu-social-security-number-equivalent-identification
      https://learn.microsoft.com/purview/sit-defn-eu-debit-card-number
    - EU passport number bundle membership (25 EU states + one combined "U.S./U.K. passport
      number" entity - no standalone U.K. entity) and EU driver's license number bundle membership
      (all 27 EU states + a standalone U.K. entity), re-fetched directly 2026-09-09:
      https://learn.microsoft.com/purview/sit-defn-eu-passport-number
      https://learn.microsoft.com/purview/sit-defn-eu-drivers-license-number
    - VERIFY (pilot tenant): byte-exact SIT name capitalization; whether a PDF attachment on an
      encrypting message is protected as part of the message envelope - see design.md §4/§6 and
      README.md §11.
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$PolicyName = 'Confidentiality - Auto-Label EU Personal Data in Exchange Email',

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$LabelName = 'Confidential',

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string[]]$SensitiveInfoTypeName = @(
        'EU national identification number',
        'EU Social Security Number (SSN) or Equivalent ID',
        'EU debit card number'
    ),

    [Parameter()]
    [switch]$IncludeTravelDocumentSits,

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

function Resolve-SensitiveInfoTypeNames {
    # Fails loudly and lists near-matches rather than silently deploying a rule that might match
    # zero real content on a case/punctuation mismatch - see .DESCRIPTION and design.md §4.
    param([string[]]$Name)

    $catalog = Get-DlpSensitiveInformationType -ErrorAction Stop
    $resolved = @()
    $unresolved = @()

    foreach ($n in $Name) {
        $match = $catalog | Where-Object { $_.Name -eq $n }
        if ($match) {
            $resolved += $match.Name
        }
        else {
            $unresolved += $n
        }
    }

    if ($unresolved.Count -gt 0) {
        $lines = foreach ($n in $unresolved) {
            $nearMatches = ($catalog | Where-Object { $_.Name -like "*$($n.Split(' ')[0])*" } | Select-Object -First 5 -ExpandProperty Name) -join ', '
            "  '$n' - not found in this tenant's SIT catalog. Closest names starting similarly: $nearMatches"
        }
        throw "One or more -SensitiveInfoTypeName values did not resolve via Get-DlpSensitiveInformationType:`n$($lines -join "`n")`nCorrect the name(s) and re-run - see README.md §11 (SIT-name VERIFY)."
    }

    return $resolved
}

Assert-IppsSession

$label = Get-Label -Identity $LabelName -ErrorAction SilentlyContinue
if (-not $label) {
    throw "Label '$LabelName' was not found. This script requires an existing, published sensitivity label whose scope includes Emails - see README.md §3 (label authoring is a prerequisite, not deployed by this scenario)."
}

if ($IncludeTravelDocumentSits) {
    # Opt-in bundle, not a new default - README.md §6, design.md §5. Appended to whatever set is
    # already in effect (default or a caller-supplied override), not a replacement of it. Same
    # switch name and behavior as the SharePoint/OneDrive EU sibling's own opt-in bundle.
    $travelDocumentSits = @('EU passport number', "EU driver's license number")
    Write-Host "IncludeTravelDocumentSits: adding $($travelDocumentSits -join ', ') to the configured SIT set. Note: the EU passport number bundle's U.K. coverage is a combined 'U.S./U.K. passport number' entity, not standalone U.K.-only - see design.md §5." -ForegroundColor Cyan
    $SensitiveInfoTypeName = @($SensitiveInfoTypeName + $travelDocumentSits) | Select-Object -Unique
}

$resolvedSitNames = Resolve-SensitiveInfoTypeNames -Name $SensitiveInfoTypeName
Write-Host "Resolved sensitive information types: $($resolvedSitNames -join ', ')" -ForegroundColor Cyan

$ruleName = 'AutoLabel-EuPersonalData-Exchange'
$sitConditions = $resolvedSitNames | ForEach-Object { @{ name = $_; mincount = '1' } }

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
    Comment               = 'Auto-labels Exchange email containing EU/UK personal identifiers as Confidential. Deployed by scenarios/information-protection/auto-label-eu-personal-data-exchange. Owner: Information Protection team.'
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
    # Conservative reconciliation: only -Mode is set here, matching the pattern in both sibling
    # scenarios' deploy scripts. Sender-exception/label/external-RM-owner/SIT changes on an
    # existing policy are a deliberate re-provisioning decision, not something this script
    # silently reconciles on every -Force run.
    Write-Host "Policy '$PolicyName' exists - reconciling Mode only (-Force). To change the sender exception list, the applied label, the external Rights Management owner, or the SIT set, remove and re-create the policy." -ForegroundColor Yellow
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

Write-Host "`nDone. Exchange auto-labeling evaluates mail in transit only - send/receive test messages while in simulation mode to see matches (README.md §5/§7). Confirm the '$LabelName' label's scope includes Emails before expecting matches. Run validate/Test-EuPersonalDataAutoLabelExchangePolicy.ps1 to verify the deployed configuration." -ForegroundColor Cyan
```

#### `Remove-EuPersonalDataAutoLabelExchangePolicy.ps1`

```powershell
#Requires -Modules @{ ModuleName = 'ExchangeOnlineManagement'; ModuleVersion = '3.2.0' }
<#
.SYNOPSIS
    Removes (or disables) the "Confidentiality - Auto-Label EU Personal Data in Exchange Email"
    auto-labeling policy.

.DESCRIPTION
    Two rollback modes:
      -Disable (default, recommended first step): sets the policy Mode to Disable. Reversible in
       seconds via Set-AutoSensitivityLabelPolicy -Mode Enable. Mail already labeled/encrypted by
       this policy is not affected retroactively - Exchange auto-labeling only ever acted on mail
       already in transit at the time.
      -Purge: permanently deletes the policy and its rule via Remove-AutoSensitivityLabelPolicy.
       Removing the policy also removes its rule. This is NOT reversible - re-deploying requires
       re-running New-EuPersonalDataAutoLabelExchangePolicy.ps1.

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
    ./Remove-EuPersonalDataAutoLabelExchangePolicy.ps1 -WhatIf

.EXAMPLE
    ./Remove-EuPersonalDataAutoLabelExchangePolicy.ps1
    # Disables the policy (soft rollback).

.EXAMPLE
    ./Remove-EuPersonalDataAutoLabelExchangePolicy.ps1 -Purge
    # Permanently deletes the policy and its rule.

.NOTES
    Sources: https://learn.microsoft.com/powershell/module/exchangepowershell/set-autosensitivitylabelpolicy
             https://learn.microsoft.com/powershell/module/exchangepowershell/remove-autosensitivitylabelpolicy
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$PolicyName = 'Confidentiality - Auto-Label EU Personal Data in Exchange Email',

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