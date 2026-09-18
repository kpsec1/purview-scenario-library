---
part: "deploy"
parent: "dlp/endpoint-dlp-usb-block"
---
The scripts and configuration below deploy this scenario. Review them, then run in order — each is designed to be idempotent and has a matching rollback.


#### `New-EndpointDlpUsbBlockPolicy.ps1`

```powershell
#Requires -Modules @{ ModuleName = 'ExchangeOnlineManagement'; ModuleVersion = '3.2.0' }
<#
.SYNOPSIS
    Deploys the "Endpoint DLP - Block USB Removable Media Exfiltration" DLP policy and its two rules.

.DESCRIPTION
    Creates (or, if already present, leaves untouched and reports) one Microsoft Purview Endpoint
    DLP policy scoped to onboarded Windows/macOS devices, with two rules:
      0. USB-Block-Sensitive-AllUsers      - everyone except IT Data Custodians, blocks copy to
                                              removable USB media when content matches SSN or
                                              Credit Card Number.
      1. USB-Audit-ITDataCustodians        - IT Data Custodians group only, restricts the same
                                              copy activity with -ITExceptionAction (Audit by
                                              default - the copy proceeds, logged only; or Warn -
                                              a user-facing justification prompt, still not a hard
                                              block) for the same content.

    Idempotent: if a policy with the same -PolicyName already exists, the script reports its
    current state and takes no action, rather than erroring or creating a duplicate. Re-run with
    -Force to update rule properties on an existing policy to match this script's definition.

    Author-only reference code. This script never establishes its own connection to a tenant and
    never targets a live tenant by default (-Mode defaults to TestWithNotifications, a
    non-blocking simulation mode). Run Connect-IPPSSession yourself first (see
    docs/automation-surface.md §3 for the certificate app-only pattern), then call this script.

    PREREQUISITE this script does not perform: target devices must already be onboarded to
    Microsoft Purview device management (Settings > Device onboarding > Devices) and reporting
    into Activity explorer. Onboarding is a package deployment (local script / Group Policy /
    Configuration Manager / Intune), not a Security & Compliance PowerShell object - see
    README.md §3 and design.md §5.

.PARAMETER PolicyName
    Name of the DLP policy. Policy names cannot be changed after creation (Microsoft Learn:
    dlp-create-policy-powerbi-cc-numbers) - choose deliberately.

.PARAMETER ITCustodiansGroupEmail
    SMTP address of the mail-enabled security group (or Microsoft 365 group) whose members get the
    audit-only (not blocked) path for legitimate backup/imaging work involving removable media.
    Must already exist in the tenant - this script does not create it.

.PARAMETER AdminNotificationEmail
    One or more admin/SOC mailbox addresses to receive incident reports and alerts.

.PARAMETER ITExceptionAction
    EndpointDlpRestrictions -Value applied to the IT Data Custodians rule (USB-Audit-
    ITDataCustodians): 'Audit' (default) logs the copy and alerts at Low severity with no
    user-facing prompt; 'Warn' additionally requires the user to acknowledge a policy-tip
    justification prompt before the copy proceeds - still not a hard block. Both are officially
    documented -Value strings for -EndpointDlpRestrictions (see .NOTES); this script defaults to
    'Audit' to keep behavior unchanged from prior versions, and only requires -NotifyUser (added
    automatically) when 'Warn' is selected, per Microsoft's own documented requirement that Block
    or Warn values must be paired with -NotifyUser.

.PARAMETER Mode
    DLP policy mode: Enable, Disable, TestWithNotifications, or TestWithoutNotifications
    (Set-DlpCompliancePolicy -Mode; Microsoft Learn: set-dlpcompliancepolicy). Defaults to
    TestWithNotifications so a first run never blocks live traffic.

.PARAMETER Force
    If the policy already exists, update its rules to match this script's definition instead of
    skipping. Rule updates go through Set-DlpComplianceRule -WhatIf when -WhatIf is passed.
    Note: switching -ITExceptionAction from Warn back to Audit with -Force reconciles the
    EndpointDlpRestrictions value, but Set-DlpComplianceRule is not documented to clear a
    previously-set NotifyUser/NotifyPolicyTipCustomText left off this call - if you switch away
    from Warn, confirm those properties on the live rule afterward (Get-DlpComplianceRule) rather
    than assuming -Force fully reverts every Warn-only property.

.PARAMETER WhatIf
    Standard PowerShell ShouldProcess dry-run. Reports every New-/Set-Dlp* call that would be made
    without calling any mutating cmdlet. Passed through to the underlying New-DlpCompliancePolicy /
    New-DlpComplianceRule calls as well, so no policy or rule object is created during a -WhatIf run.

.EXAMPLE
    Connect-IPPSSession -AppId $AppId -Certificate $Cert -Organization $TenantDomain
    ./New-EndpointDlpUsbBlockPolicy.ps1 -ITCustodiansGroupEmail 'it-custodians@contoso.com' `
        -AdminNotificationEmail 'soc@contoso.com' -WhatIf

    Dry-run: shows exactly what would be created, changes nothing.

.EXAMPLE
    ./New-EndpointDlpUsbBlockPolicy.ps1 -ITCustodiansGroupEmail 'it-custodians@contoso.com' `
        -AdminNotificationEmail 'soc@contoso.com' -Mode TestWithNotifications

    Deploys in simulation mode: policy tips and notifications fire, nothing is blocked yet.

.EXAMPLE
    ./New-EndpointDlpUsbBlockPolicy.ps1 -ITCustodiansGroupEmail 'it-custodians@contoso.com' `
        -AdminNotificationEmail 'soc@contoso.com' -Mode Enable -Force

    Deploys (or updates) the policy in full enforcement mode.

.EXAMPLE
    ./New-EndpointDlpUsbBlockPolicy.ps1 -ITCustodiansGroupEmail 'it-custodians@contoso.com' `
        -AdminNotificationEmail 'soc@contoso.com' -ITExceptionAction Warn -Mode Enable -Force

    Deploys with the IT Data Custodians path justification-gated (Warn) instead of silently
    logged (Audit) - see .PARAMETER ITExceptionAction and README.md §11.

.NOTES
    EndpointDlpRestrictions Setting/Value strings are confirmed directly against Microsoft's
    official New-DlpComplianceRule and Set-DlpComplianceRule cmdlet reference pages (identical text
    on both, fetched and re-verified for this revision): "The available values for <Value> are:
    Audit, Block, Ignore, or Warn," with worked examples including
    @{"Setting"="RemovableMedia"; "Value"="Block";} - matching this script's Rule 0 exactly. The
    same pages also confirm Setting names Print, CopyPaste, ScreenCapture, NetworkShare, and
    UnallowedApps (not used by this scenario - see design.md §7). Both pages additionally state:
    "When you use the values Block or Warn in this parameter, you also need to use the NotifyUser
    parameter" - grouping Warn with the user-facing Block action rather than the silent Audit/
    Ignore pair. This is strong, but not literal, evidence that Warn is the enum value behind the
    portal's "Block with override" activity option; Microsoft's reference does not spell out that
    exact portal-name mapping, so confirm the on-screen prompt behavior in a pilot tenant before
    describing it to a customer as "Block with override" by name. Prior revisions of this script
    sourced the Setting/Value shape only from the Microsoft Security Blog Tech Community
    walkthrough listed below - that post is retained as a secondary, corroborating citation, not
    the primary one.

    Sources (Microsoft Learn):
    - New-DlpComplianceRule -EndpointDlpRestrictions parameter (confirmed Setting names and Value
      enum Audit/Block/Ignore/Warn, NotifyUser requirement for Block/Warn):
      https://learn.microsoft.com/powershell/module/exchangepowershell/new-dlpcompliancerule
    - Set-DlpComplianceRule -EndpointDlpRestrictions parameter (identical text, confirmed
      independently): https://learn.microsoft.com/powershell/module/exchangepowershell/set-dlpcompliancerule
    - New-DlpCompliancePolicy -EndpointDlpLocation parameter: https://learn.microsoft.com/powershell/module/exchangepowershell/new-dlpcompliancepolicy
    - DLP policy reference (Audit/Block with override/Block/Allow/Off action semantics, "Copy to a
      removable device" activity): https://learn.microsoft.com/purview/dlp-policy-reference
    - Configure endpoint DLP settings (Removable USB device groups, restricted-activity actions):
      https://learn.microsoft.com/purview/dlp-configure-endpoint-settings
    - Get started with Endpoint DLP: https://learn.microsoft.com/purview/endpoint-dlp-getting-started
    - Learn about Endpoint DLP: https://learn.microsoft.com/purview/endpoint-dlp-learn-about
    - Creating Endpoint DLP Rules using PowerShell - Part 1 (Microsoft Security Blog, Tech
      Community - secondary/corroborating EndpointDlpRestrictions Setting/Value hashtable example):
      https://techcommunity.microsoft.com/blog/microsoft-security-blog/creating-endpoint-dlp-rules-using-powershell---part-1/4286999
    - U.S. Social Security Number (SSN) / Credit Card Number sensitive information types: same
      SITs as scenarios/information-protection/auto-label-confidential-sharepoint.
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$PolicyName = 'Endpoint DLP - Block USB Removable Media Exfiltration',

    [Parameter(Mandatory)]
    [ValidatePattern('^[^@\s]+@[^@\s]+\.[^@\s]+$')]
    [string]$ITCustodiansGroupEmail,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string[]]$AdminNotificationEmail,

    [Parameter()]
    [ValidateSet('Audit', 'Warn')]
    [string]$ITExceptionAction = 'Audit',

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

$ruleNameBlock = 'USB-Block-Sensitive-AllUsers'
$ruleNameAudit = 'USB-Audit-ITDataCustodians'
$sensitiveContent = @(
    @{ Name = 'U.S. Social Security Number (SSN)' },
    @{ Name = 'Credit Card Number' }
)

$existingPolicy = Get-DlpCompliancePolicy -Identity $PolicyName -ErrorAction SilentlyContinue

if ($existingPolicy -and -not $Force) {
    Write-Host "Policy '$PolicyName' already exists (Mode: $($existingPolicy.Mode)). No changes made. Pass -Force to reconcile rules to this script's definition." -ForegroundColor Yellow
    return
}

if (-not $existingPolicy) {
    if ($PSCmdlet.ShouldProcess($PolicyName, 'New-DlpCompliancePolicy (EndpointDlpLocation All)')) {
        New-DlpCompliancePolicy -Name $PolicyName `
            -EndpointDlpLocation 'All' `
            -Mode $Mode `
            -Comment 'Blocks/audits copy of SSN or Credit Card Number content to USB removable storage on onboarded devices. Deployed by scenarios/dlp/endpoint-dlp-usb-block. Owner: Security & Compliance team.' `
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

# --- Rule 0: hard block for everyone except IT Data Custodians ---
$rule0 = Get-DlpComplianceRule -Identity $ruleNameBlock -ErrorAction SilentlyContinue
$rule0Params = @{
    Name                                 = $ruleNameBlock
    Policy                               = $PolicyName
    Priority                             = 0
    ExceptIfFromMemberOf                 = $ITCustodiansGroupEmail
    ContentContainsSensitiveInformation  = $sensitiveContent
    EndpointDlpRestrictions              = @(@{ Setting = 'RemovableMedia'; Value = 'Block' })
    NotifyUser                           = @('LastModifier') + $AdminNotificationEmail
    NotifyPolicyTipCustomText            = 'This file contains a Social Security Number or credit card number and cannot be copied to a USB drive or other removable storage. Contact the Security team if you have a legitimate business need.'
    GenerateAlert                        = $AdminNotificationEmail
    GenerateIncidentReport               = $AdminNotificationEmail
    ReportSeverityLevel                  = 'High'
    StopPolicyProcessing                 = $true
}
if (-not $rule0) {
    if ($PSCmdlet.ShouldProcess($ruleNameBlock, 'New-DlpComplianceRule')) {
        New-DlpComplianceRule @rule0Params -WhatIf:$WhatIfPreference | Out-Null
    }
    Write-Host "Created rule '$ruleNameBlock'." -ForegroundColor Green
}
elseif ($Force) {
    $rule0Params.Remove('Policy') | Out-Null
    $rule0Params.Remove('Name') | Out-Null
    if ($PSCmdlet.ShouldProcess($ruleNameBlock, 'Set-DlpComplianceRule')) {
        Set-DlpComplianceRule -Identity $ruleNameBlock @rule0Params -WhatIf:$WhatIfPreference
    }
    Write-Host "Updated rule '$ruleNameBlock'." -ForegroundColor Green
}

# --- Rule 1: audit-only for IT Data Custodians (legitimate backup/imaging workflow) ---
$rule1 = Get-DlpComplianceRule -Identity $ruleNameAudit -ErrorAction SilentlyContinue
$rule1Params = @{
    Name                                 = $ruleNameAudit
    Policy                               = $PolicyName
    Priority                             = 1
    FromMemberOf                         = $ITCustodiansGroupEmail
    ContentContainsSensitiveInformation  = $sensitiveContent
    EndpointDlpRestrictions              = @(@{ Setting = 'RemovableMedia'; Value = $ITExceptionAction })
    GenerateAlert                        = $AdminNotificationEmail
    GenerateIncidentReport               = $AdminNotificationEmail
    ReportSeverityLevel                  = 'Low'
}
if ($ITExceptionAction -eq 'Warn') {
    # Microsoft Learn (New-/Set-DlpComplianceRule): "When you use the values Block or Warn in this
    # parameter, you also need to use the NotifyUser parameter."
    $rule1Params['NotifyUser'] = @('LastModifier') + $AdminNotificationEmail
    $rule1Params['NotifyPolicyTipCustomText'] = 'This file contains a Social Security Number or credit card number. As a member of IT Data Custodians you may proceed, but this copy is logged and reviewed weekly - continue only for legitimate backup/imaging work.'
}
if (-not $rule1) {
    if ($PSCmdlet.ShouldProcess($ruleNameAudit, 'New-DlpComplianceRule')) {
        New-DlpComplianceRule @rule1Params -WhatIf:$WhatIfPreference | Out-Null
    }
    Write-Host "Created rule '$ruleNameAudit'." -ForegroundColor Green
}
elseif ($Force) {
    $rule1Params.Remove('Policy') | Out-Null
    $rule1Params.Remove('Name') | Out-Null
    if ($PSCmdlet.ShouldProcess($ruleNameAudit, 'Set-DlpComplianceRule')) {
        Set-DlpComplianceRule -Identity $ruleNameAudit @rule1Params -WhatIf:$WhatIfPreference
    }
    Write-Host "Updated rule '$ruleNameAudit'." -ForegroundColor Green
}

Write-Host "`nDone. Endpoint DLP policy sync to onboarded devices is not instantaneous - check Settings > Device onboarding > Devices for per-device 'Policy Sync status' before assuming enforcement is live (Microsoft Learn: dlp-edlp-tshoot-sync). Run validate/Test-EndpointDlpUsbBlockPolicy.ps1 to verify the deployed configuration." -ForegroundColor Cyan
```

#### `policy/endpoint-dlp-usb-block-policy.json`

```json
{
  "$comment": "Reference/documentation copy of the policy this scenario's deploy script creates via New-DlpCompliancePolicy / New-DlpComplianceRule. This file is NOT consumed by the deploy script (Security & Compliance PowerShell has no native 'apply this JSON' cmdlet for DLP policies outside AdvancedRule bodies) - it exists so the shape of the policy is reviewable in a diff without reading PowerShell. EndpointDlpRestrictions Value strings ('Block', 'Audit') are confirmed directly against Microsoft's official New-/Set-DlpComplianceRule cmdlet reference pages (full enum: Audit, Block, Ignore, Warn - see deploy/New-EndpointDlpUsbBlockPolicy.ps1 .NOTES). Rule USB-Audit-ITDataCustodians's value shown here ('Audit') is the deploy script's default; pass -ITExceptionAction Warn to justification-gate that path instead - see README.md §11.",
  "policyName": "Endpoint DLP - Block USB Removable Media Exfiltration",
  "locations": {
    "endpointDlpLocation": "All"
  },
  "mode": "TestWithNotifications",
  "rules": [
    {
      "name": "USB-Block-Sensitive-AllUsers",
      "priority": 0,
      "conditions": {
        "exceptIfFromMemberOf": "<ITCustodiansGroupEmail>",
        "contentContainsSensitiveInformation": [
          { "name": "U.S. Social Security Number (SSN)" },
          { "name": "Credit Card Number" }
        ]
      },
      "actions": {
        "endpointDlpRestrictions": [
          { "setting": "RemovableMedia", "value": "Block" }
        ],
        "notifyUser": ["LastModifier", "<AdminNotificationEmail>"],
        "generateAlert": ["<AdminNotificationEmail>"],
        "generateIncidentReport": ["<AdminNotificationEmail>"],
        "reportSeverityLevel": "High"
      },
      "stopPolicyProcessing": true
    },
    {
      "name": "USB-Audit-ITDataCustodians",
      "priority": 1,
      "conditions": {
        "fromMemberOf": "<ITCustodiansGroupEmail>",
        "contentContainsSensitiveInformation": [
          { "name": "U.S. Social Security Number (SSN)" },
          { "name": "Credit Card Number" }
        ]
      },
      "actions": {
        "endpointDlpRestrictions": [
          { "setting": "RemovableMedia", "value": "Audit" }
        ],
        "generateAlert": ["<AdminNotificationEmail>"],
        "generateIncidentReport": ["<AdminNotificationEmail>"],
        "reportSeverityLevel": "Low"
      },
      "stopPolicyProcessing": false
    }
  ]
}
```

#### `Remove-EndpointDlpUsbBlockPolicy.ps1`

```powershell
#Requires -Modules @{ ModuleName = 'ExchangeOnlineManagement'; ModuleVersion = '3.2.0' }
<#
.SYNOPSIS
    Removes (or disables) the "Endpoint DLP - Block USB Removable Media Exfiltration" DLP policy.

.DESCRIPTION
    Two rollback modes:
      -Disable (default, recommended first step): sets the policy Mode to Disable. Reversible in
       seconds via Set-DlpCompliancePolicy -Mode Enable. No history is lost.
      -Purge: permanently deletes the policy and its two rules via Remove-DlpCompliancePolicy.
       Removing the policy also removes its rules (Microsoft Learn: remove-dlpcompliancepolicy).
       This is NOT reversible - re-deploying requires re-running New-EndpointDlpUsbBlockPolicy.ps1.

    Idempotent: if the policy does not exist, the script reports that and exits cleanly rather
    than erroring.

.PARAMETER PolicyName
    Name of the DLP policy to roll back. Must match the -PolicyName used at deploy time.

.PARAMETER Purge
    Permanently delete the policy instead of disabling it. See rollback.md for the recommended
    disable-first, purge-later sequence.

.PARAMETER WhatIf
    Standard PowerShell ShouldProcess dry-run - reports the disable/removal that would happen
    without calling Set-DlpCompliancePolicy / Remove-DlpCompliancePolicy.

.EXAMPLE
    Connect-IPPSSession -AppId $AppId -Certificate $Cert -Organization $TenantDomain
    ./Remove-EndpointDlpUsbBlockPolicy.ps1 -WhatIf

.EXAMPLE
    ./Remove-EndpointDlpUsbBlockPolicy.ps1
    # Disables the policy (soft rollback).

.EXAMPLE
    ./Remove-EndpointDlpUsbBlockPolicy.ps1 -Purge
    # Permanently deletes the policy and its rules.

.NOTES
    Sources: https://learn.microsoft.com/powershell/module/exchangepowershell/set-dlpcompliancepolicy
             https://learn.microsoft.com/powershell/module/exchangepowershell/remove-dlpcompliancepolicy
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$PolicyName = 'Endpoint DLP - Block USB Removable Media Exfiltration',

    [Parameter()]
    [switch]$Purge
)

$ErrorActionPreference = 'Stop'

if (-not (Get-Command Get-DlpCompliancePolicy -ErrorAction SilentlyContinue)) {
    throw 'No Security & Compliance PowerShell session found. Run Connect-IPPSSession first (see docs/automation-surface.md).'
}

$policy = Get-DlpCompliancePolicy -Identity $PolicyName -ErrorAction SilentlyContinue

if (-not $policy) {
    Write-Host "Policy '$PolicyName' does not exist. Nothing to roll back." -ForegroundColor Yellow
    return
}

if ($Purge) {
    if ($PSCmdlet.ShouldProcess($PolicyName, 'Remove-DlpCompliancePolicy (permanent, also removes its rules)')) {
        Remove-DlpCompliancePolicy -Identity $PolicyName -Confirm:$false -WhatIf:$WhatIfPreference
    }
    Write-Host "Permanently removed policy '$PolicyName' and its rules." -ForegroundColor Green
}
else {
    if ($PSCmdlet.ShouldProcess($PolicyName, 'Set-DlpCompliancePolicy -Mode Disable')) {
        Set-DlpCompliancePolicy -Identity $PolicyName -Mode Disable -WhatIf:$WhatIfPreference
    }
    Write-Host "Disabled policy '$PolicyName'. Re-enable with: Set-DlpCompliancePolicy -Identity '$PolicyName' -Mode Enable" -ForegroundColor Green
}
```