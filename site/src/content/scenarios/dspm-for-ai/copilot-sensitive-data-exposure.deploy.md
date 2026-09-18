---
part: "deploy"
parent: "dspm-for-ai/copilot-sensitive-data-exposure"
---
The scripts and configuration below deploy this scenario. Review them, then run in order — each is designed to be idempotent and has a matching rollback.


#### `New-CopilotSensitiveDataProtectionPolicy.ps1`

```powershell
#Requires -Modules @{ ModuleName = 'ExchangeOnlineManagement'; ModuleVersion = '3.2.0' }
<#
.SYNOPSIS
    Deploys the "Copilot DLP - Sensitive Data Exposure Protection" DLP policy and its two rules.

.DESCRIPTION
    Creates (or, if already present, leaves untouched and reports) one Microsoft Purview DLP
    policy scoped to the Microsoft 365 Copilot and Copilot Chat location, with two rules:
      0. Copilot-Exclude-Labeled-Content              - excludes items carrying one of the
                                                          -SensitivityLabelName labels from Copilot
                                                          processing (content-processing block, not
                                                          an access control).
      1. Copilot-Restrict-WebGrounding-SensitivePrompts - blocks Copilot from using external web
                                                          search as a grounding source when a
                                                          prompt contains one of the configured
                                                          sensitive information types.

    Idempotent: if a policy with the same -PolicyName already exists, the script reports its
    current state and takes no action, rather than erroring or creating a duplicate. Re-run with
    -Force to update rule properties on an existing policy to match this script's definition.

    Author-only reference code. This script never establishes its own connection to a tenant and
    never targets a live tenant by default (-Mode defaults to TestWithNotifications, a
    non-blocking simulation mode). Run Connect-IPPSSession yourself first (see
    docs/automation-surface.md §3 for the certificate app-only pattern), then call this script.

    Does NOT deploy a third, related Copilot-location action - "Prevent Copilot from processing
    content > Processing prompts" (full response block on a sensitive-information-type match, not
    just a web-grounding restriction). That action is in preview and has no published Microsoft
    PowerShell worked example for this exact condition/action combination as of this writing; see
    README.md §5 and design.md §6. It is deployed by a separate, extending scenario instead -
    scenarios/dspm-for-ai/copilot-prompt-full-block/deploy/Add-CopilotPromptFullBlockRule.ps1 - which
    adds it as a third rule on this same policy and discloses the remaining grounding gap explicitly.

.PARAMETER PolicyName
    Name of the DLP policy. Policy names cannot be changed after creation (Microsoft Learn:
    dlp-create-policy-powerbi-cc-numbers) - choose deliberately. Defaults to a name distinct from
    DSPM for AI's one-click "DSPM for AI - Protect sensitive data from Copilot processing" default
    policy - see design.md §3a for why this scenario does not reuse that name.

.PARAMETER SensitivityLabelName
    One or more existing, published sensitivity label display names whose content should be
    excluded from Copilot processing (Rule 0). Each must already exist in the tenant (this script
    does not create labels) and must not be a parent label - see
    scenarios/information-protection/auto-label-confidential-sharepoint/README.md §3 for that
    constraint. Defaults to @('Confidential', 'Highly Confidential').

.PARAMETER SensitiveInformationTypeName
    One or more built-in or custom sensitive information type names whose presence in a Copilot
    prompt should restrict web-search grounding (Rule 1). Defaults to @('U.S. Social Security
    Number (SSN)', 'Credit Card Number').

.PARAMETER AdminNotificationEmail
    One or more admin/SOC mailbox addresses to receive incident reports and alerts.

.PARAMETER Mode
    DLP policy mode: Enable, Disable, TestWithNotifications, or TestWithoutNotifications
    (Set-DlpCompliancePolicy -Mode; Microsoft Learn: set-dlpcompliancepolicy). Defaults to
    TestWithNotifications so a first run never blocks live Copilot traffic. Simulation mode is
    documented as supported for the Copilot location (Microsoft Learn:
    dlp-microsoft365-copilot-location-learn-about, "Availability").

.PARAMETER Force
    If the policy already exists, update its rules to match this script's definition instead of
    skipping. Rule updates go through Set-DlpComplianceRule -WhatIf when -WhatIf is passed.

.PARAMETER WhatIf
    Standard PowerShell ShouldProcess dry-run. Reports every New-/Set-Dlp* call that would be made
    without calling any mutating cmdlet. Passed through to the underlying New-DlpCompliancePolicy /
    New-DlpComplianceRule calls as well, so no policy or rule object is created during a -WhatIf run.

.EXAMPLE
    Connect-IPPSSession -AppId $AppId -Certificate $Cert -Organization $TenantDomain
    ./New-CopilotSensitiveDataProtectionPolicy.ps1 -AdminNotificationEmail 'soc@contoso.com' -WhatIf

    Dry-run: shows exactly what would be created, changes nothing.

.EXAMPLE
    ./New-CopilotSensitiveDataProtectionPolicy.ps1 -AdminNotificationEmail 'soc@contoso.com'

    Deploys in simulation mode: alerts fire, nothing is blocked yet.

.EXAMPLE
    ./New-CopilotSensitiveDataProtectionPolicy.ps1 -AdminNotificationEmail 'soc@contoso.com' `
        -Mode Enable -Force

    Deploys (or updates) the policy in full enforcement mode.

.NOTES
    VERIFY before enforcing in production: the -Locations JSON this script constructs uses fully-
    quoted keys (standards-conformant JSON). Microsoft's own New-DlpCompliancePolicy reference
    Example 4 shows this same Copilot location value with UNQUOTED object keys
    ({Type:"Tenant", Identity:"All"}), which is not strictly valid JSON. This script emits the
    equivalent, valid JSON instead (matching the fully-quoted style Microsoft uses in its own
    New-FeatureConfiguration Example 1 for the same location pattern) - confirm in a pilot tenant
    that this is accepted identically to the portal-generated value before relying on it in
    production. See README.md §11 and design.md §6.

    VERIFY: the exact Get-DlpCompliancePolicy output property name for a policy created with the
    generic -Locations/-EnforcementPlanes parameter pair (as opposed to a strongly-typed location
    parameter like -TeamsLocation or -SharePointLocation) is not documented in Microsoft's cmdlet
    reference. validate/Test-CopilotSensitiveDataProtectionPolicy.ps1 therefore checks policy and
    rule existence and rule-level settings only, not a specific Locations output property - see
    that script's header for detail.

    Sources (Microsoft Learn, verify before production use):
    - New-DlpCompliancePolicy reference, Example 4 (Copilot location JSON, -EnforcementPlanes
      CopilotExperiences, -AdvancedRule label-condition JSON, -RestrictAccess
      ExcludeContentProcessing):
      https://learn.microsoft.com/powershell/module/exchangepowershell/new-dlpcompliancepolicy
    - New-DlpComplianceRule reference (-RestrictAccess, -RestrictWebGrounding,
      -ContentContainsSensitiveInformation parameters):
      https://learn.microsoft.com/powershell/module/exchangepowershell/new-dlpcompliancerule
    - Set-DlpCompliancePolicy -Mode values:
      https://learn.microsoft.com/powershell/module/exchangepowershell/set-dlpcompliancepolicy
    - Learn about using Microsoft Purview DLP to protect interactions with Microsoft 365 Copilot
      and Copilot Chat (locations, conditions/actions table, four-hour propagation):
      https://learn.microsoft.com/purview/dlp-microsoft365-copilot-location-learn-about
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$PolicyName = 'Copilot DLP - Sensitive Data Exposure Protection',

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string[]]$SensitivityLabelName = @('Confidential', 'Highly Confidential'),

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string[]]$SensitiveInformationTypeName = @('U.S. Social Security Number (SSN)', 'Credit Card Number'),

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string[]]$AdminNotificationEmail,

    [Parameter()]
    [ValidateSet('Enable', 'Disable', 'TestWithNotifications', 'TestWithoutNotifications')]
    [string]$Mode = 'TestWithNotifications',

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

# The Microsoft 365 Copilot Applications location - fixed GUID from Microsoft's own
# New-DlpCompliancePolicy reference Example 4. Not tenant-specific.
$copilotLocationGuid = '470f2276-e011-4e9d-a6ec-20768be3a4b0'
$ruleNameLabelExclusion = 'Copilot-Exclude-Labeled-Content'
$ruleNameWebGrounding = 'Copilot-Restrict-WebGrounding-SensitivePrompts'

# --- Resolve sensitivity label GUIDs (read-only; safe to run under -WhatIf) ---
$labelGuids = foreach ($labelName in $SensitivityLabelName) {
    $label = Get-Label -Identity $labelName -ErrorAction SilentlyContinue
    if (-not $label) {
        throw "Sensitivity label '$labelName' was not found. Create it first (see scenarios/information-protection/auto-label-confidential-sharepoint/) or pass -SensitivityLabelName with an existing label."
    }
    $label.Guid
}

# --- Build the -Locations JSON for the Copilot location (fully-quoted; see .NOTES VERIFY) ---
$locationsJson = @"
[{"Workload":"Applications","Location":"$copilotLocationGuid","Inclusions":[{"Type":"Tenant","Identity":"All"}]}]
"@

$existingPolicy = Get-DlpCompliancePolicy -Identity $PolicyName -ErrorAction SilentlyContinue

if ($existingPolicy -and -not $Force) {
    Write-Host "Policy '$PolicyName' already exists (Mode: $($existingPolicy.Mode)). No changes made. Pass -Force to reconcile rules to this script's definition." -ForegroundColor Yellow
    return
}

if (-not $existingPolicy) {
    if ($PSCmdlet.ShouldProcess($PolicyName, 'New-DlpCompliancePolicy (Copilot location)')) {
        New-DlpCompliancePolicy -Name $PolicyName `
            -Locations $locationsJson `
            -EnforcementPlanes @('CopilotExperiences') `
            -Mode $Mode `
            -Comment 'Excludes labeled confidential content from Microsoft 365 Copilot processing and restricts web-search grounding for sensitive prompts. Deployed by scenarios/dspm-for-ai/copilot-sensitive-data-exposure. Owner: Security & Compliance team.' `
            -WhatIf:$WhatIfPreference | Out-Null
    }
    Write-Host "Created DLP policy '$PolicyName' (Mode: $Mode)." -ForegroundColor Green
}
else {
    Write-Host "Policy '$PolicyName' exists - reconciling rules (-Force)." -ForegroundColor Yellow
    if ($PSCmdlet.ShouldProcess($PolicyName, "Set-DlpCompliancePolicy -Mode $Mode")) {
        Set-DlpCompliancePolicy -Identity $PolicyName -Mode $Mode -WhatIf:$WhatIfPreference
    }
}

# --- Rule 0: exclude labeled confidential content from Copilot processing ---
# AdvancedRule form reproduced from New-DlpCompliancePolicy reference Example 4, extended to
# support more than one label GUID (repeat entries under the same "Or" group).
$labelEntries = $labelGuids | ForEach-Object { @{ name = $_; type = 'Sensitivity' } }
$advancedRuleObject = @{
    Version   = '1.0'
    Condition = @{
        Operator      = 'And'
        SubConditions = @(
            @{
                ConditionName = 'ContentContainsSensitiveInformation'
                Value          = @(
                    @{
                        groups = @(
                            @{
                                Operator = 'Or'
                                labels   = @($labelEntries)
                                name     = 'Default'
                            }
                        )
                    }
                )
            }
        )
    }
}
$advancedRuleJson = $advancedRuleObject | ConvertTo-Json -Depth 100 -Compress

$rule0 = Get-DlpComplianceRule -Identity $ruleNameLabelExclusion -ErrorAction SilentlyContinue
$rule0Params = @{
    Name           = $ruleNameLabelExclusion
    Policy         = $PolicyName
    Priority       = 0
    AdvancedRule   = $advancedRuleJson
    RestrictAccess = @(@{ setting = 'ExcludeContentProcessing'; value = 'Block' })
    NotifyUser     = @('LastModifier') + $AdminNotificationEmail
    GenerateAlert  = $AdminNotificationEmail
    GenerateIncidentReport = $AdminNotificationEmail
    ReportSeverityLevel    = 'High'
}
if (-not $rule0) {
    if ($PSCmdlet.ShouldProcess($ruleNameLabelExclusion, 'New-DlpComplianceRule')) {
        New-DlpComplianceRule @rule0Params -WhatIf:$WhatIfPreference | Out-Null
    }
    Write-Host "Created rule '$ruleNameLabelExclusion'." -ForegroundColor Green
}
elseif ($Force) {
    $rule0Params.Remove('Policy') | Out-Null
    $rule0Params.Remove('Name') | Out-Null
    if ($PSCmdlet.ShouldProcess($ruleNameLabelExclusion, 'Set-DlpComplianceRule')) {
        Set-DlpComplianceRule -Identity $ruleNameLabelExclusion @rule0Params -WhatIf:$WhatIfPreference
    }
    Write-Host "Updated rule '$ruleNameLabelExclusion'." -ForegroundColor Green
}

# --- Rule 1: restrict web-search grounding when a prompt contains a configured SIT ---
$sitConditions = $SensitiveInformationTypeName | ForEach-Object { @{ name = $_; mincount = '1' } }

$rule1 = Get-DlpComplianceRule -Identity $ruleNameWebGrounding -ErrorAction SilentlyContinue
$rule1Params = @{
    Name                                 = $ruleNameWebGrounding
    Policy                               = $PolicyName
    Priority                             = 1
    ContentContainsSensitiveInformation  = $sitConditions
    RestrictWebGrounding                 = $true
    NotifyUser                           = @('LastModifier') + $AdminNotificationEmail
    GenerateAlert                        = $AdminNotificationEmail
    GenerateIncidentReport               = $AdminNotificationEmail
    ReportSeverityLevel                  = 'Medium'
}
if (-not $rule1) {
    if ($PSCmdlet.ShouldProcess($ruleNameWebGrounding, 'New-DlpComplianceRule')) {
        New-DlpComplianceRule @rule1Params -WhatIf:$WhatIfPreference | Out-Null
    }
    Write-Host "Created rule '$ruleNameWebGrounding'." -ForegroundColor Green
}
elseif ($Force) {
    $rule1Params.Remove('Policy') | Out-Null
    $rule1Params.Remove('Name') | Out-Null
    if ($PSCmdlet.ShouldProcess($ruleNameWebGrounding, 'Set-DlpComplianceRule')) {
        Set-DlpComplianceRule -Identity $ruleNameWebGrounding @rule1Params -WhatIf:$WhatIfPreference
    }
    Write-Host "Updated rule '$ruleNameWebGrounding'." -ForegroundColor Green
}

Write-Host "`nDone. Policy sync to the Copilot experience can take up to ~4 hours (Microsoft Learn: dlp-microsoft365-copilot-location-learn-about). Run validate/Test-CopilotSensitiveDataProtectionPolicy.ps1 to verify the deployed configuration. Remember: this policy does not remediate unlabeled oversharing - review the DSPM for AI data risk assessment (README.md §5, §8) separately." -ForegroundColor Cyan
```

#### `policy/copilot-dspm-dlp-policy.json`

```json
{
  "$comment": "Reference/documentation copy of the policy this scenario's deploy script creates via New-DlpCompliancePolicy / New-DlpComplianceRule. Not consumed by the deploy script - exists so the shape of the policy is reviewable in a diff without reading PowerShell. See deploy/New-CopilotSensitiveDataProtectionPolicy.ps1 for the executable form and citations.",
  "policyName": "Copilot DLP - Sensitive Data Exposure Protection",
  "locations": {
    "workload": "Applications",
    "location": "470f2276-e011-4e9d-a6ec-20768be3a4b0",
    "locationDisplayName": "Microsoft 365 Copilot and Copilot Chat",
    "inclusions": [{ "type": "Tenant", "identity": "All" }]
  },
  "enforcementPlanes": ["CopilotExperiences"],
  "mode": "TestWithNotifications",
  "rules": [
    {
      "name": "Copilot-Exclude-Labeled-Content",
      "priority": 0,
      "conditions": {
        "advancedRule": {
          "note": "Sensitivity-label condition - no simple named parameter exists for this condition on the Copilot location; see New-DlpCompliancePolicy reference Example 4.",
          "labels": ["<Confidential label GUID>", "<Highly Confidential label GUID>"]
        }
      },
      "actions": {
        "restrictAccess": [{ "setting": "ExcludeContentProcessing", "value": "Block" }]
      },
      "stopPolicyProcessing": false
    },
    {
      "name": "Copilot-Restrict-WebGrounding-SensitivePrompts",
      "priority": 1,
      "conditions": {
        "contentContainsSensitiveInformation": [
          { "name": "U.S. Social Security Number (SSN)", "mincount": "1" },
          { "name": "Credit Card Number", "mincount": "1" }
        ]
      },
      "actions": {
        "restrictWebGrounding": true
      },
      "stopPolicyProcessing": false
    }
  ],
  "notInScope": [
    "Prevent Copilot from processing content > Processing prompts (full response block on SIT match) - preview, no published PowerShell worked example as of this build, portal-only. See README.md §5.",
    "Block external email from being processed (preview) - different condition type, out of scope per design.md §7.",
    "Third-party generative AI site DLP (Edge/Chrome/Firefox) - different policy location/enforcement plane, out of scope per design.md §7."
  ]
}
```

#### `Remove-CopilotSensitiveDataProtectionPolicy.ps1`

```powershell
#Requires -Modules @{ ModuleName = 'ExchangeOnlineManagement'; ModuleVersion = '3.2.0' }
<#
.SYNOPSIS
    Disables (default) or permanently removes (-Purge) the "Copilot DLP - Sensitive Data Exposure
    Protection" DLP policy.

.DESCRIPTION
    Default behavior is reversible: sets the policy Mode to Disable, leaving the policy and its
    two rules intact and re-enable-able (Set-DlpCompliancePolicy -Mode Enable). Pass -Purge to
    permanently delete the policy and its rules via Remove-DlpCompliancePolicy - not reversible.

    Author-only reference code. Never runs against a live tenant without an explicit
    Connect-IPPSSession call made by the operator first.

.PARAMETER PolicyName
    Name of the DLP policy to disable or remove. Must match the -PolicyName used at deploy time.

.PARAMETER Purge
    Permanently deletes the policy and its rules instead of disabling. Not reversible - see
    rollback.md.

.PARAMETER WhatIf
    Standard PowerShell ShouldProcess dry-run.

.EXAMPLE
    Connect-IPPSSession -AppId $AppId -Certificate $Cert -Organization $TenantDomain
    ./Remove-CopilotSensitiveDataProtectionPolicy.ps1 -WhatIf

.EXAMPLE
    ./Remove-CopilotSensitiveDataProtectionPolicy.ps1
    # Disables (reversible)

.EXAMPLE
    ./Remove-CopilotSensitiveDataProtectionPolicy.ps1 -Purge
    # Permanently deletes the policy and its rules

.NOTES
    Sources (Microsoft Learn):
    - Set-DlpCompliancePolicy -Mode Disable: https://learn.microsoft.com/powershell/module/exchangepowershell/set-dlpcompliancepolicy
    - Remove-DlpCompliancePolicy reference: https://learn.microsoft.com/powershell/module/exchangepowershell/remove-dlpcompliancepolicy
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$PolicyName = 'Copilot DLP - Sensitive Data Exposure Protection',

    [Parameter()]
    [switch]$Purge
)

$ErrorActionPreference = 'Stop'

if (-not (Get-Command Get-DlpCompliancePolicy -ErrorAction SilentlyContinue)) {
    throw 'No Security & Compliance PowerShell session found. Run Connect-IPPSSession first (see docs/automation-surface.md).'
}

$policy = Get-DlpCompliancePolicy -Identity $PolicyName -ErrorAction SilentlyContinue
if (-not $policy) {
    Write-Host "Policy '$PolicyName' not found. Nothing to do." -ForegroundColor Yellow
    return
}

if ($Purge) {
    if ($PSCmdlet.ShouldProcess($PolicyName, 'Remove-DlpCompliancePolicy (permanent - removes the policy and its rules)')) {
        Remove-DlpCompliancePolicy -Identity $PolicyName -Confirm:$false -WhatIf:$WhatIfPreference
    }
    Write-Host "Permanently removed policy '$PolicyName' and its rules." -ForegroundColor Red
}
else {
    if ($PSCmdlet.ShouldProcess($PolicyName, 'Set-DlpCompliancePolicy -Mode Disable')) {
        Set-DlpCompliancePolicy -Identity $PolicyName -Mode Disable -WhatIf:$WhatIfPreference
    }
    Write-Host "Disabled policy '$PolicyName' (reversible - re-enable with Set-DlpCompliancePolicy -Identity '$PolicyName' -Mode Enable)." -ForegroundColor Yellow
}
```