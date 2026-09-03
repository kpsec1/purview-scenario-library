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
      1. USB-Audit-ITDataCustodians        - IT Data Custodians group only, audits (does not
                                              block) the same copy activity for the same content.

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

.PARAMETER Mode
    DLP policy mode: Enable, Disable, TestWithNotifications, or TestWithoutNotifications
    (Set-DlpCompliancePolicy -Mode; Microsoft Learn: set-dlpcompliancepolicy). Defaults to
    TestWithNotifications so a first run never blocks live traffic.

.PARAMETER Force
    If the policy already exists, update its rules to match this script's definition instead of
    skipping. Rule updates go through Set-DlpComplianceRule -WhatIf when -WhatIf is passed.

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

.NOTES
    VERIFY before enforcing in production: the exact PowerShell -Value strings accepted inside an
    -EndpointDlpRestrictions hashtable are not enumerated in Microsoft's canonical
    New-DlpComplianceRule / Set-DlpComplianceRule parameter reference (the parameter is documented
    only as an opaque PswsHashtable[]). This script uses Setting = 'RemovableMedia' with
    Value = 'Block' / 'Value' = 'Audit', grounded in the portal's "Audit or restrict activities on
    devices" action naming (Microsoft Learn: dlp-policy-reference, dlp-configure-endpoint-settings)
    and in a Microsoft Security Blog PowerShell walkthrough ("Creating Endpoint DLP Rules using
    PowerShell - Part 1", Microsoft Tech Community) that shows this exact Setting/Value hashtable
    shape for removable-media and print restrictions. Confirm both strings against a pilot tenant
    (README.md §7, step 1) before relying on -Mode Enable in production - if a string is rejected,
    the cmdlet throws at policy/rule creation time rather than silently no-opping.

    Sources (Microsoft Learn, verify before production use):
    - New-DlpComplianceRule / Set-DlpComplianceRule -EndpointDlpRestrictions parameter (type only,
      no enumerated values): https://learn.microsoft.com/powershell/module/exchangepowershell/new-dlpcompliancerule
      https://learn.microsoft.com/powershell/module/exchangepowershell/set-dlpcompliancerule
    - New-DlpCompliancePolicy -EndpointDlpLocation parameter: https://learn.microsoft.com/powershell/module/exchangepowershell/new-dlpcompliancepolicy
    - DLP policy reference (Audit/Block with override/Block/Allow/Off action semantics, "Copy to a
      removable device" activity): https://learn.microsoft.com/purview/dlp-policy-reference
    - Configure endpoint DLP settings (Removable USB device groups, restricted-activity actions):
      https://learn.microsoft.com/purview/dlp-configure-endpoint-settings
    - Get started with Endpoint DLP: https://learn.microsoft.com/purview/endpoint-dlp-getting-started
    - Learn about Endpoint DLP: https://learn.microsoft.com/purview/endpoint-dlp-learn-about
    - Creating Endpoint DLP Rules using PowerShell - Part 1 (Microsoft Security Blog, Tech
      Community - EndpointDlpRestrictions Setting/Value hashtable example):
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
    EndpointDlpRestrictions              = @(@{ Setting = 'RemovableMedia'; Value = 'Audit' })
    GenerateAlert                        = $AdminNotificationEmail
    GenerateIncidentReport               = $AdminNotificationEmail
    ReportSeverityLevel                  = 'Low'
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
