---
part: "deploy"
parent: "information-protection/auto-label-confidential-sharepoint"
---
The scripts and configuration below deploy this scenario. Review them, then run in order — each is designed to be idempotent and has a matching rollback.


#### `New-ConfidentialAutoLabelPolicy.ps1`

```powershell
#Requires -Modules @{ ModuleName = 'ExchangeOnlineManagement'; ModuleVersion = '3.2.0' }
<#
.SYNOPSIS
    Deploys the "Confidentiality - Auto-Label PII in SharePoint and OneDrive" auto-labeling
    policy and its two rules.

.DESCRIPTION
    Creates (or, if already present, leaves untouched and reports) one Microsoft Purview
    auto-labeling policy scoped to SharePoint and OneDrive, with two rules:
      - AutoLabel-Confidential-PII-SharePoint  - Workload SharePoint
      - AutoLabel-Confidential-PII-OneDrive    - Workload OneDriveForBusiness
    Both rules apply the same sensitive-information-type conditions (U.S. Social Security
    Number OR Credit Card Number, minimum count 1) and the same target label.

    Idempotent: if a policy with the same -PolicyName already exists, the script reports its
    current state and takes no action, rather than erroring or creating a duplicate. Re-run with
    -Force to update rule properties on an existing policy to match this script's definition.

    Author-only reference code. This script never establishes its own connection to a tenant and
    never targets a live tenant by default (-Mode defaults to TestWithNotifications, a
    non-blocking simulation mode). Run Connect-IPPSSession yourself first (see
    docs/automation-surface.md §3 for the certificate app-only pattern), then call this script.

    Prerequisite this script does NOT perform: the one-time SharePoint tenant toggle
    (Set-SPOTenant -EnableAIPIntegration $true), which requires the separate SharePoint Online
    Management Shell (Connect-SPOService) - see README.md §3 and §11. Confirm that toggle is set
    before relying on this policy; otherwise it will run and report success while never actually
    labeling anything.

.PARAMETER PolicyName
    Name of the auto-labeling policy. Policy names cannot be changed after creation, matching the
    behavior documented for the equivalent DLP cmdlet family - choose deliberately.

.PARAMETER LabelName
    Name (or GUID) of an existing, published sensitivity label to auto-apply. Must already exist,
    have a label scope that includes "Files & other data assets", and must NOT be a parent label
    (a label with sublabels) - a parent label causes the policy to run without ever labeling
    anything, with no error surfaced (Microsoft Learn: apply-sensitivity-label-automatically).
    This script does not create or validate the label beyond confirming it resolves via Get-Label.

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
    ./New-ConfidentialAutoLabelPolicy.ps1 -LabelName 'Confidential' `
        -ExcludedSharePointSiteUrl 'https://contoso.sharepoint.com/sites/LegalHold' -WhatIf

    Dry-run: shows exactly what would be created, changes nothing.

.EXAMPLE
    ./New-ConfidentialAutoLabelPolicy.ps1 -LabelName 'Confidential' `
        -ExcludedSharePointSiteUrl 'https://contoso.sharepoint.com/sites/LegalHold'

    Deploys in simulation mode: content is evaluated and simulation results populate, nothing is
    labeled yet.

.EXAMPLE
    ./New-ConfidentialAutoLabelPolicy.ps1 -LabelName 'Confidential' -Mode Enable -Force

    Deploys (or updates) the policy in full enforcement mode.

.NOTES
    Sources (Microsoft Learn, verify before production use):
    - Automatically apply a sensitivity label to Microsoft 365 data (prerequisites, override
      behavior, PDF/backlog limits): https://learn.microsoft.com/purview/apply-sensitivity-label-automatically
    - New-AutoSensitivityLabelPolicy / New-AutoSensitivityLabelRule reference:
      https://learn.microsoft.com/powershell/module/exchangepowershell/new-autosensitivitylabelpolicy
      https://learn.microsoft.com/powershell/module/exchangepowershell/new-autosensitivitylabelrule
    - Set-AutoSensitivityLabelPolicy -Mode values: https://learn.microsoft.com/powershell/module/exchangepowershell/set-autosensitivitylabelpolicy
    - Data Loss Prevention policy reference (Content contains: Any of these / All of these):
      https://learn.microsoft.com/purview/dlp-policy-reference#rules
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$PolicyName = 'Confidentiality - Auto-Label PII in SharePoint and OneDrive',

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$LabelName = 'Confidential',

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

Assert-IppsSession

$label = Get-Label -Identity $LabelName -ErrorAction SilentlyContinue
if (-not $label) {
    throw "Label '$LabelName' was not found. This script requires an existing, published sensitivity label - see README.md §3 (label authoring is a prerequisite, not deployed by this scenario)."
}

$ruleNameSharePoint = 'AutoLabel-Confidential-PII-SharePoint'
$ruleNameOneDrive = 'AutoLabel-Confidential-PII-OneDrive'
$sitConditions = @(
    @{ name = 'U.S. Social Security Number (SSN)'; mincount = '1' },
    @{ name = 'Credit Card Number'; mincount = '1' }
)

$existingPolicy = Get-AutoSensitivityLabelPolicy -Identity $PolicyName -ErrorAction SilentlyContinue

if ($existingPolicy -and -not $Force) {
    Write-Host "Policy '$PolicyName' already exists (Mode: $($existingPolicy.Mode)). No changes made. Pass -Force to reconcile rules to this script's definition." -ForegroundColor Yellow
    return
}

$policyParams = @{
    Name                = $PolicyName
    ApplySensitivityLabel = $LabelName
    SharePointLocation  = 'All'
    OneDriveLocation    = 'All'
    Mode                = $Mode
    OverwriteLabel      = $true
    Comment             = 'Auto-labels SharePoint/OneDrive content containing SSN or Credit Card Number as Confidential. Deployed by scenarios/information-protection/auto-label-confidential-sharepoint. Owner: Information Protection team.'
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
    # Conservative reconciliation: only -Mode is set here, matching the pattern in
    # scenarios/dlp/pci-teams-exfil-block/deploy/New-PciTeamsDlpPolicy.ps1. Location/label/
    # override changes on an existing policy are a deliberate re-provisioning decision, not
    # something this script silently reconciles on every -Force run.
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

Write-Host "`nDone. Auto-labeling runs on an ongoing scan cadence, not instantly on save - allow time before validating. Confirm Set-SPOTenant -EnableAIPIntegration is `$true (README.md §3) before expecting labels to appear. Run validate/Test-ConfidentialAutoLabelPolicy.ps1 to verify the deployed configuration." -ForegroundColor Cyan
```

#### `policy/confidential-autolabel-policy.json`

```json
{
  "$comment": "Reference/documentation copy of the policy this scenario's deploy script creates via New-AutoSensitivityLabelPolicy / New-AutoSensitivityLabelRule. This file is NOT consumed by the deploy script (Security & Compliance PowerShell has no native 'apply this JSON' cmdlet for auto-labeling policies outside AdvancedRule bodies) - it exists so the shape of the policy is reviewable in a diff without reading PowerShell.",
  "policyName": "Confidentiality - Auto-Label PII in SharePoint and OneDrive",
  "applySensitivityLabel": "<LabelName>",
  "locations": {
    "sharePointLocation": "All",
    "sharePointLocationException": ["<ExcludedSharePointSiteUrl>"],
    "oneDriveLocation": "All"
  },
  "mode": "TestWithNotifications",
  "overwriteLabel": true,
  "rules": [
    {
      "name": "AutoLabel-Confidential-PII-SharePoint",
      "workload": "SharePoint",
      "conditions": {
        "contentContainsSensitiveInformation": {
          "operator": "Or",
          "sensitiveTypes": [
            { "name": "U.S. Social Security Number (SSN)", "mincount": 1 },
            { "name": "Credit Card Number", "mincount": 1 }
          ]
        }
      }
    },
    {
      "name": "AutoLabel-Confidential-PII-OneDrive",
      "workload": "OneDriveForBusiness",
      "conditions": {
        "contentContainsSensitiveInformation": {
          "operator": "Or",
          "sensitiveTypes": [
            { "name": "U.S. Social Security Number (SSN)", "mincount": 1 },
            { "name": "Credit Card Number", "mincount": 1 }
          ]
        }
      }
    }
  ]
}
```

#### `Remove-ConfidentialAutoLabelPolicy.ps1`

```powershell
#Requires -Modules @{ ModuleName = 'ExchangeOnlineManagement'; ModuleVersion = '3.2.0' }
<#
.SYNOPSIS
    Removes (or disables) the "Confidentiality - Auto-Label PII in SharePoint and OneDrive"
    auto-labeling policy.

.DESCRIPTION
    Two rollback modes:
      -Disable (default, recommended first step): sets the policy Mode to Disable. Reversible in
       seconds via Set-AutoSensitivityLabelPolicy -Mode Enable. No history is lost, and labels
       already applied to files are not removed.
      -Purge: permanently deletes the policy and its two rules via
       Remove-AutoSensitivityLabelPolicy. Removing the policy also removes its rules. This is NOT
       reversible - re-deploying requires re-running New-ConfidentialAutoLabelPolicy.ps1. Labels
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
    ./Remove-ConfidentialAutoLabelPolicy.ps1 -WhatIf

.EXAMPLE
    ./Remove-ConfidentialAutoLabelPolicy.ps1
    # Disables the policy (soft rollback).

.EXAMPLE
    ./Remove-ConfidentialAutoLabelPolicy.ps1 -Purge
    # Permanently deletes the policy and its rules.

.NOTES
    Sources: https://learn.microsoft.com/powershell/module/exchangepowershell/set-autosensitivitylabelpolicy
             https://learn.microsoft.com/powershell/module/exchangepowershell/remove-autosensitivitylabelpolicy
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$PolicyName = 'Confidentiality - Auto-Label PII in SharePoint and OneDrive',

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