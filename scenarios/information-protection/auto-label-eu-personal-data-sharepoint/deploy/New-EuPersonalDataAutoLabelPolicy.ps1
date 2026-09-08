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
