---
part: "deploy"
parent: "information-protection/auto-label-eu-personal-data-sharepoint"
---
The scripts and configuration below deploy this scenario. Review them, then run in order — each is designed to be idempotent and has a matching rollback.


#### `New-EuPersonalDataAutoLabelPolicy.ps1`

```powershell
#Requires -Modules @{ ModuleName = 'ExchangeOnlineManagement'; ModuleVersion = '3.2.0' }
<#
.SYNOPSIS
    Deploys the "Confidentiality - Auto-Label EU Personal Data in SharePoint and OneDrive"
    auto-labeling policy and its two rules.

.DESCRIPTION
    Creates (or, if already present, leaves untouched and reports) one Microsoft Purview
    auto-labeling policy scoped to SharePoint and OneDrive, with two rules:
      - AutoLabel-EuPersonalData-SharePoint  - Workload SharePoint
      - AutoLabel-EuPersonalData-OneDrive    - Workload OneDriveForBusiness
    Both rules apply the same sensitive-information-type (SIT) conditions and the same target
    label. Default SITs (see README.md §2/§4, design.md §4): 'EU national identification number',
    'EU Social Security Number (SSN) or Equivalent ID', 'EU debit card number' - the EU/UK analog
    of the sibling scenario's U.S. SSN + Credit Card Number pair.

    This is the sibling of scenarios/information-protection/auto-label-confidential-sharepoint/ -
    same policy family and rollout model, different (and localizable) SIT set. See design.md §3
    for why this is a second scenario rather than a parameter on the original.

    LOCALIZATION: -SensitiveInfoTypeName accepts any built-in or custom SIT name(s), not just the
    three EU-wide defaults. A buyer whose regulated population is limited to specific member
    states can pass just those countries' own SITs (e.g. -SensitiveInfoTypeName 'Germany Identity
    Card Number','France Social Security Number') for tighter false-positive control than the
    full EU-wide bundles - see README.md §6 and design.md §5.

    Every configured SIT name is resolved against Get-DlpSensitiveInformationType before any
    policy/rule is created or updated. This is deliberate: this build could not confirm the
    byte-exact capitalization Microsoft's own SIT-catalog pages use for the EU-wide bundle names
    (design.md §4's VERIFY) with certainty, so rather than silently deploy a rule that might match
    zero real content on a case/punctuation mismatch, an unresolved name fails the run immediately
    and lists the closest available SIT names from the tenant's own catalog.

    Idempotent: if a policy with the same -PolicyName already exists, the script reports its
    current state and takes no action, rather than erroring or creating a duplicate. Re-run with
    -Force to update rule properties on an existing policy to match this script's definition.

    Author-only reference code. This script never establishes its own connection to a tenant and
    never targets a live tenant by default (-Mode defaults to TestWithNotifications, a
    non-blocking simulation mode). Run Connect-IPPSSession yourself first (see
    docs/automation-surface.md §3 for the certificate app-only pattern), then call this script.

    Prerequisite this script does NOT perform: the one-time SharePoint tenant toggle
    (Set-SPOTenant -EnableAIPIntegration $true), which requires the separate SharePoint Online
    Management Shell (Connect-SPOService) - see README.md §3 and §11 (same prerequisite as the
    sibling scenario). Confirm that toggle is set before relying on this policy.

.PARAMETER PolicyName
    Name of the auto-labeling policy. Policy names cannot be changed after creation - choose
    deliberately.

.PARAMETER LabelName
    Name (or GUID) of an existing, published sensitivity label to auto-apply. Must already exist,
    have a label scope that includes "Files & other data assets", and must NOT be a parent label -
    see README.md §3/§11 (identical requirement and identical failure mode as the sibling
    scenario). This script does not create or validate the label beyond confirming it resolves
    via Get-Label.

.PARAMETER SensitiveInfoTypeName
    One or more sensitive information type names to match on (logical OR, mincount 1 each).
    Defaults to the EU-wide bundle set: 'EU national identification number', 'EU Social Security
    Number (SSN) or Equivalent ID', 'EU debit card number' (design.md §4). Override with a
    narrower, jurisdiction-specific list to localize further (design.md §5) - any name accepted
    by Get-DlpSensitiveInformationType in the connected tenant is valid, not just EU-region SITs.

.PARAMETER IncludeTravelDocumentSits
    Opt-in switch (not a new default - README.md §6, design.md §4). Appends 'EU passport number'
    and "EU driver's license number" to whatever -SensitiveInfoTypeName is in effect (the default
    three-SIT set, or a caller-supplied override), deduplicated, before name resolution. Both are
    real, confirmed EU-wide bundle SITs - use this switch instead of retyping the full SIT list
    when a buyer's SharePoint/OneDrive estate is travel-document- or HR-record-heavy.

    GOTCHA (design.md §4): the "EU passport number" bundle's U.K. coverage is not a standalone
    U.K. entity the way the national-ID and driver's-license bundles have one - it is a single
    combined "U.S./U.K. passport number" entity. Turning on this switch for U.K.-only travel-
    document coverage also enables U.S. passport number detection as a side effect. The three
    EU-wide bundles this scenario can reference do not all cover the same set of member states
    either (passport: 25 states, no Luxembourg/Netherlands; driver's license: all 27 states;
    national ID: 26, no Poland/Sweden) - see design.md §4 for the full breakdown.

.PARAMETER ExcludedSharePointSiteUrl
    Optional SharePoint site URL(s) to exclude from the policy (e.g. a legal-hold/eDiscovery
    site). Maps to -SharePointLocationException on the policy.

.PARAMETER Mode
    Auto-labeling policy mode: Enable, Disable, TestWithNotifications, or
    TestWithoutNotifications (Set-AutoSensitivityLabelPolicy -Mode; Microsoft Learn:
    set-autosensitivitylabelpolicy). Defaults to TestWithNotifications so a first run never
    labels live content.

.PARAMETER Force
    If the policy already exists, update its rules to match this script's definition instead of
    skipping. Rule updates go through Set-AutoSensitivityLabelRule -WhatIf when -WhatIf is passed.

.PARAMETER WhatIf
    Standard PowerShell ShouldProcess dry-run. Reports every New-/Set-AutoSensitivityLabel* call
    that would be made without calling any mutating cmdlet.

.EXAMPLE
    Connect-IPPSSession -AppId $AppId -Certificate $Cert -Organization $TenantDomain
    ./New-EuPersonalDataAutoLabelPolicy.ps1 -LabelName 'Confidential' `
        -ExcludedSharePointSiteUrl 'https://contoso.sharepoint.com/sites/LegalHold' -WhatIf

    Dry-run with the default EU-wide SIT set: shows exactly what would be created, changes
    nothing.

.EXAMPLE
    ./New-EuPersonalDataAutoLabelPolicy.ps1 -LabelName 'Confidential' `
        -SensitiveInfoTypeName 'Germany Identity Card Number','France Social Security Number','EU debit card number'

    Deploys in simulation mode (default), localized to Germany + France national ID + the
    region-wide EU debit card SIT instead of the full 26-country default bundle.

.EXAMPLE
    ./New-EuPersonalDataAutoLabelPolicy.ps1 -LabelName 'Confidential' -Mode Enable -Force

    Deploys (or updates) the policy in full enforcement mode with the default EU-wide SIT set.

.EXAMPLE
    ./New-EuPersonalDataAutoLabelPolicy.ps1 -LabelName 'Confidential' -IncludeTravelDocumentSits

    Deploys in simulation mode (default) with the default EU-wide SIT set plus the opt-in
    passport/driver's-license bundle - see the IncludeTravelDocumentSits parameter description
    for the U.S./U.K. passport-entity gotcha before enabling this for a U.K.-only buyer.

.NOTES
    Sources (Microsoft Learn, verify before production use):
    - Automatically apply a sensitivity label to Microsoft 365 data (prerequisites, override
      behavior, PDF/backlog limits): https://learn.microsoft.com/purview/apply-sensitivity-label-automatically
    - New-AutoSensitivityLabelPolicy / New-AutoSensitivityLabelRule reference:
      https://learn.microsoft.com/powershell/module/exchangepowershell/new-autosensitivitylabelpolicy
      https://learn.microsoft.com/powershell/module/exchangepowershell/new-autosensitivitylabelrule
    - Get-DlpSensitiveInformationType reference (name resolution, -Identity lookup):
      https://learn.microsoft.com/powershell/module/exchangepowershell/get-dlpsensitiveinformationtype
    - EU national identification number / EU Social Security Number (SSN) or Equivalent ID / EU
      debit card number entity definitions:
      https://learn.microsoft.com/purview/sit-defn-eu-national-identification-number
      https://learn.microsoft.com/purview/sit-defn-eu-social-security-number-equivalent-identification
      https://learn.microsoft.com/purview/sit-defn-eu-debit-card-number
    - EU passport number bundle membership (25 EU states + one combined "U.S./U.K. passport
      number" entity - no standalone U.K. entity) and EU driver's license number bundle
      membership (all 27 EU states + a standalone U.K. entity), fetched directly 2026-09-09:
      https://learn.microsoft.com/purview/sit-defn-eu-passport-number
      https://learn.microsoft.com/purview/sit-defn-eu-drivers-license-number
    - VERIFY (pilot tenant): byte-exact SIT name capitalization - see design.md §4 and README.md §11.
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$PolicyName = 'Confidentiality - Auto-Label EU Personal Data in SharePoint and OneDrive',

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
    [string[]]$ExcludedSharePointSiteUrl,

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
    throw "Label '$LabelName' was not found. This script requires an existing, published sensitivity label - see README.md §3 (label authoring is a prerequisite, not deployed by this scenario)."
}

if ($IncludeTravelDocumentSits) {
    # Opt-in bundle, not a new default - README.md §6, design.md §4. Appended to whatever set is
    # already in effect (default or a caller-supplied override), not a replacement of it.
    $travelDocumentSits = @('EU passport number', "EU driver's license number")
    Write-Host "IncludeTravelDocumentSits: adding $($travelDocumentSits -join ', ') to the configured SIT set. Note: the EU passport number bundle's U.K. coverage is a combined 'U.S./U.K. passport number' entity, not standalone U.K.-only - see design.md §4." -ForegroundColor Cyan
    $SensitiveInfoTypeName = @($SensitiveInfoTypeName + $travelDocumentSits) | Select-Object -Unique
}

$resolvedSitNames = Resolve-SensitiveInfoTypeNames -Name $SensitiveInfoTypeName
Write-Host "Resolved sensitive information types: $($resolvedSitNames -join ', ')" -ForegroundColor Cyan

$ruleNameSharePoint = 'AutoLabel-EuPersonalData-SharePoint'
$ruleNameOneDrive = 'AutoLabel-EuPersonalData-OneDrive'
$sitConditions = $resolvedSitNames | ForEach-Object { @{ name = $_; mincount = '1' } }

$existingPolicy = Get-AutoSensitivityLabelPolicy -Identity $PolicyName -ErrorAction SilentlyContinue

if ($existingPolicy -and -not $Force) {
    Write-Host "Policy '$PolicyName' already exists (Mode: $($existingPolicy.Mode)). No changes made. Pass -Force to reconcile rules to this script's definition." -ForegroundColor Yellow
    return
}

$policyParams = @{
    Name                   = $PolicyName
    ApplySensitivityLabel  = $LabelName
    SharePointLocation     = 'All'
    OneDriveLocation       = 'All'
    Mode                   = $Mode
    OverwriteLabel         = $true
    Comment                = 'Auto-labels SharePoint/OneDrive content containing EU/UK personal identifiers as Confidential. Deployed by scenarios/information-protection/auto-label-eu-personal-data-sharepoint. Owner: Information Protection team.'
}
if ($ExcludedSharePointSiteUrl) {
    $policyParams['SharePointLocationException'] = $ExcludedSharePointSiteUrl
}

if (-not $existingPolicy) {
    if ($PSCmdlet.ShouldProcess($PolicyName, 'New-AutoSensitivityLabelPolicy (SharePoint + OneDrive, All locations)')) {
        New-AutoSensitivityLabelPolicy @policyParams -WhatIf:$WhatIfPreference | Out-Null
    }
    Write-Host "Created auto-labeling policy '$PolicyName' (Mode: $Mode)." -ForegroundColor Green
}
else {
    # Conservative reconciliation: only -Mode is set here, matching the pattern in the sibling
    # scenario's deploy script. Location/label/override/SIT changes on an existing policy are a
    # deliberate re-provisioning decision, not something this script silently reconciles.
    Write-Host "Policy '$PolicyName' exists - reconciling Mode only (-Force). To change locations, the applied label, or the exclusion list, remove and re-create the policy." -ForegroundColor Yellow
    if ($PSCmdlet.ShouldProcess($PolicyName, "Set-AutoSensitivityLabelPolicy -Mode $Mode")) {
        Set-AutoSensitivityLabelPolicy -Identity $PolicyName -Mode $Mode -WhatIf:$WhatIfPreference
    }
}

# --- Rule: SharePoint ---
$ruleSharePoint = Get-AutoSensitivityLabelRule -Identity $ruleNameSharePoint -ErrorAction SilentlyContinue
$ruleSharePointParams = @{
    Name                                 = $ruleNameSharePoint
    Policy                               = $PolicyName
    Workload                             = 'SharePoint'
    ContentContainsSensitiveInformation  = $sitConditions
}
if (-not $ruleSharePoint) {
    if ($PSCmdlet.ShouldProcess($ruleNameSharePoint, 'New-AutoSensitivityLabelRule')) {
        New-AutoSensitivityLabelRule @ruleSharePointParams -WhatIf:$WhatIfPreference | Out-Null
    }
    Write-Host "Created rule '$ruleNameSharePoint'." -ForegroundColor Green
}
elseif ($Force) {
    $ruleSharePointParams.Remove('Policy') | Out-Null
    $ruleSharePointParams.Remove('Name') | Out-Null
    $ruleSharePointParams.Remove('Workload') | Out-Null
    if ($PSCmdlet.ShouldProcess($ruleNameSharePoint, 'Set-AutoSensitivityLabelRule')) {
        Set-AutoSensitivityLabelRule -Identity $ruleNameSharePoint @ruleSharePointParams -WhatIf:$WhatIfPreference
    }
    Write-Host "Updated rule '$ruleNameSharePoint'." -ForegroundColor Green
}

# --- Rule: OneDrive ---
$ruleOneDrive = Get-AutoSensitivityLabelRule -Identity $ruleNameOneDrive -ErrorAction SilentlyContinue
$ruleOneDriveParams = @{
    Name                                 = $ruleNameOneDrive
    Policy                               = $PolicyName
    Workload                             = 'OneDriveForBusiness'
    ContentContainsSensitiveInformation  = $sitConditions
}
if (-not $ruleOneDrive) {
    if ($PSCmdlet.ShouldProcess($ruleNameOneDrive, 'New-AutoSensitivityLabelRule')) {
        New-AutoSensitivityLabelRule @ruleOneDriveParams -WhatIf:$WhatIfPreference | Out-Null
    }
    Write-Host "Created rule '$ruleNameOneDrive'." -ForegroundColor Green
}
elseif ($Force) {
    $ruleOneDriveParams.Remove('Policy') | Out-Null
    $ruleOneDriveParams.Remove('Name') | Out-Null
    $ruleOneDriveParams.Remove('Workload') | Out-Null
    if ($PSCmdlet.ShouldProcess($ruleNameOneDrive, 'Set-AutoSensitivityLabelRule')) {
        Set-AutoSensitivityLabelRule -Identity $ruleNameOneDrive @ruleOneDriveParams -WhatIf:$WhatIfPreference
    }
    Write-Host "Updated rule '$ruleNameOneDrive'." -ForegroundColor Green
}

Write-Host "`nDone. Auto-labeling runs on an ongoing scan cadence, not instantly on save - allow time before validating. Confirm Set-SPOTenant -EnableAIPIntegration is `$true (README.md §3) before expecting labels to appear. Run validate/Test-EuPersonalDataAutoLabelPolicy.ps1 to verify the deployed configuration." -ForegroundColor Cyan
```

#### `Remove-EuPersonalDataAutoLabelPolicy.ps1`

```powershell
#Requires -Modules @{ ModuleName = 'ExchangeOnlineManagement'; ModuleVersion = '3.2.0' }
<#
.SYNOPSIS
    Removes (or disables) the "Confidentiality - Auto-Label EU Personal Data in SharePoint and
    OneDrive" auto-labeling policy.

.DESCRIPTION
    Two rollback modes:
      -Disable (default, recommended first step): sets the policy Mode to Disable. Reversible in
       seconds via Set-AutoSensitivityLabelPolicy -Mode Enable. No history is lost, and labels
       already applied to files are not removed.
      -Purge: permanently deletes the policy and its two rules via
       Remove-AutoSensitivityLabelPolicy. Removing the policy also removes its rules. This is NOT
       reversible - re-deploying requires re-running New-EuPersonalDataAutoLabelPolicy.ps1. Labels
       already applied to files remain on those files; this does not remove labels retroactively.

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
    ./Remove-EuPersonalDataAutoLabelPolicy.ps1 -WhatIf

.EXAMPLE
    ./Remove-EuPersonalDataAutoLabelPolicy.ps1
    # Disables the policy (soft rollback).

.EXAMPLE
    ./Remove-EuPersonalDataAutoLabelPolicy.ps1 -Purge
    # Permanently deletes the policy and its rules.

.NOTES
    Sources: https://learn.microsoft.com/powershell/module/exchangepowershell/set-autosensitivitylabelpolicy
             https://learn.microsoft.com/powershell/module/exchangepowershell/remove-autosensitivitylabelpolicy
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$PolicyName = 'Confidentiality - Auto-Label EU Personal Data in SharePoint and OneDrive',

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
    if ($PSCmdlet.ShouldProcess($PolicyName, 'Remove-AutoSensitivityLabelPolicy (permanent, also removes its rules)')) {
        Remove-AutoSensitivityLabelPolicy -Identity $PolicyName -Confirm:$false -WhatIf:$WhatIfPreference
    }
    Write-Host "Permanently removed policy '$PolicyName' and its rules. Labels already applied to files are not removed." -ForegroundColor Green
}
else {
    if ($PSCmdlet.ShouldProcess($PolicyName, 'Set-AutoSensitivityLabelPolicy -Mode Disable')) {
        Set-AutoSensitivityLabelPolicy -Identity $PolicyName -Mode Disable -WhatIf:$WhatIfPreference
    }
    Write-Host "Disabled policy '$PolicyName'. Re-enable with: Set-AutoSensitivityLabelPolicy -Identity '$PolicyName' -Mode Enable" -ForegroundColor Green
}
```