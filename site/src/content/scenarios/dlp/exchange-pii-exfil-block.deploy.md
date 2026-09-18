---
part: "deploy"
parent: "dlp/exchange-pii-exfil-block"
---
The scripts and configuration below deploy this scenario. Review them, then run in order — each is designed to be idempotent and has a matching rollback.


#### `New-ExchangePiiDlpPolicy.ps1`

```powershell
#Requires -Modules @{ ModuleName = 'ExchangeOnlineManagement'; ModuleVersion = '3.2.0' }
<#
.SYNOPSIS
    Deploys the "PII DLP - Exchange External Send Control" DLP policy and its rules.

.DESCRIPTION
    Creates (or, if already present, leaves untouched and reports) one Microsoft Purview DLP
    policy scoped to Exchange Online mail flow, with content-based rules (SSN / Credit Card
    Number, not label-conditioned - see design.md §3) that act on outbound mail to external
    recipients:
      - PII-Exchange-Override-External  (Block mode + -ExceptionGroupEmail only) - nominated
        exception group, block-with-justification-override
      - PII-Exchange-Protect-External   - everyone else, external recipient: hard block
        (-Action Block) or forced encryption (-Action Encrypt)
      - PII-Exchange-Audit-Internal     - everyone, internal recipient: audit only

    Idempotent: if a policy with the same -PolicyName already exists, the script reports its
    current state and takes no action, rather than erroring or creating a duplicate. Re-run with
    -Force to update rule properties on an existing policy to match this script's definition.

    Author-only reference code. This script never establishes its own connection to a tenant and
    never targets a live tenant by default (-Mode defaults to TestWithNotifications, a
    non-blocking simulation mode). Run Connect-IPPSSession yourself first (see
    docs/automation-surface.md §3 for the certificate app-only pattern), then call this script.

.PARAMETER PolicyName
    Name of the DLP policy. Policy names cannot be changed after creation (Microsoft Learn:
    dlp-create-policy-powerbi-cc-numbers) - choose deliberately.

.PARAMETER Action
    'Block' (default) hard-blocks matching outbound mail to external recipients (BlockAccess,
    a halting action - the message is not delivered to that recipient). 'Encrypt' instead applies
    an RMS template (EncryptRMSTemplate, a non-halting action - the message is still delivered,
    protected). See design.md §6 for why the override mechanism (below) only applies in Block mode.

.PARAMETER EncryptTemplateName
    Only used when -Action Encrypt. Name of an existing RMS template (Get-RMSTemplate) to apply.
    Defaults to 'Encrypt-Only', Microsoft's documented ad-hoc template that is automatically
    available once Microsoft Purview Message Encryption is active in the tenant - VERIFY the exact
    Name property in your tenant (see README.md §11); this script checks it exists before using it
    rather than assuming.

.PARAMETER ExceptionGroupEmail
    Optional SMTP address of a mail-enabled security group (or Microsoft 365 group) with an
    approved, recurring business need to send this content externally. In Block mode, members get
    a block-with-justification-override path instead of a hard block. In Encrypt mode, members are
    excluded from the encrypt rule entirely (no override concept for a non-halting action - see
    design.md §6 and README.md §11 for the resulting silent-exception residual risk). Must already
    exist in the tenant - this script does not create it.

.PARAMETER AdminNotificationEmail
    One or more admin/SOC mailbox addresses to receive incident reports and alerts.

.PARAMETER Mode
    DLP policy mode: Enable, Disable, TestWithNotifications, or TestWithoutNotifications
    (Set-DlpCompliancePolicy -Mode; Microsoft Learn: set-dlpcompliancepolicy). Defaults to
    TestWithNotifications so a first run never blocks or encrypts live traffic.

.PARAMETER Force
    If the policy already exists, update its rules to match this script's definition instead of
    skipping. Rule updates go through Set-DlpComplianceRule -WhatIf when -WhatIf is passed.

.PARAMETER WhatIf
    Standard PowerShell ShouldProcess dry-run. Reports every New-/Set-Dlp* call that would be
    made without calling any mutating cmdlet, including the Encrypt-mode RMS template check.

.EXAMPLE
    Connect-IPPSSession -AppId $AppId -Certificate $Cert -Organization $TenantDomain
    ./New-ExchangePiiDlpPolicy.ps1 -AdminNotificationEmail 'soc@contoso.com' -WhatIf

    Dry-run: shows exactly what would be created, changes nothing.

.EXAMPLE
    ./New-ExchangePiiDlpPolicy.ps1 -AdminNotificationEmail 'soc@contoso.com' `
        -ExceptionGroupEmail 'hr-benefits-ops@contoso.com' -Mode TestWithNotifications

    Deploys in simulation mode with a business-exception group for HR/Payroll external mail.

.EXAMPLE
    ./New-ExchangePiiDlpPolicy.ps1 -AdminNotificationEmail 'soc@contoso.com' `
        -Action Encrypt -Mode Enable -Force

    Deploys (or updates) the policy in full enforcement mode, encrypting rather than blocking
    outbound external mail matching the SIT conditions.

.NOTES
    VERIFY before enforcing in production: run the functional tests in README.md §7 to confirm
    the deployed rules behave as designed in this tenant - Microsoft's DLP policy reference
    confirms BlockAccess and EncryptRMSTemplate as the two supported Exchange actions for
    "Restrict access or encrypt the content in Microsoft 365 locations", but no worked example
    combines them with -AccessScope NotInOrganization specifically for this SIT pair.

    VERIFY the exact Name value Get-RMSTemplate returns for the auto-created "Encrypt-Only"
    template in your tenant before relying on -Action Encrypt's default -EncryptTemplateName -
    Microsoft's own documentation doesn't publish a canonical, byte-exact value. This script's
    pre-flight check (below) fails clearly, listing available templates, rather than silently
    creating a rule that references a nonexistent template.

    Sources (Microsoft Learn, verify before production use):
    - New-DlpCompliancePolicy / New-DlpComplianceRule reference:
      https://learn.microsoft.com/powershell/module/exchangepowershell/new-dlpcompliancepolicy
      https://learn.microsoft.com/powershell/module/exchangepowershell/new-dlpcompliancerule
    - Get-RMSTemplate reference: https://learn.microsoft.com/powershell/module/exchangepowershell/get-rmstemplate
    - Set-DlpCompliancePolicy -Mode values: https://learn.microsoft.com/powershell/module/exchangepowershell/set-dlpcompliancepolicy
    - Data loss prevention Exchange conditions and actions reference: https://learn.microsoft.com/purview/dlp-exchange-conditions-and-actions
    - Bifurcation (per-recipient forking, independent rule evaluation): https://learn.microsoft.com/exchange/reference/bifurcation
    - Credit Card Number SIT definition: https://learn.microsoft.com/purview/sit-defn-credit-card-number
    - U.S. Social Security Number (SSN) SIT definition: https://learn.microsoft.com/purview/sit-defn-us-social-security-number
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$PolicyName = 'PII DLP - Exchange External Send Control',

    [Parameter()]
    [ValidateSet('Block', 'Encrypt')]
    [string]$Action = 'Block',

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$EncryptTemplateName = 'Encrypt-Only',

    [Parameter()]
    [ValidatePattern('^[^@\s]+@[^@\s]+\.[^@\s]+$')]
    [string]$ExceptionGroupEmail,

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

if ($Action -eq 'Encrypt') {
    $rmsTemplate = Get-RMSTemplate -ResultSize Unlimited -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -eq $EncryptTemplateName }
    if (-not $rmsTemplate) {
        $available = (Get-RMSTemplate -ResultSize Unlimited -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name) -join ', '
        throw "RMS template '$EncryptTemplateName' was not found via Get-RMSTemplate. Available templates: $(if ($available) { $available } else { '(none - confirm Microsoft Purview Message Encryption / Azure Rights Management is active in this tenant)' }). Pass -EncryptTemplateName with an exact match, or use -Action Block instead."
    }
    Write-Host "Confirmed RMS template '$EncryptTemplateName' exists." -ForegroundColor Green
}

$ruleNameOverride = 'PII-Exchange-Override-External'
$ruleNameExternal = 'PII-Exchange-Protect-External'
$ruleNameAuditInternal = 'PII-Exchange-Audit-Internal'
$piiSits = @(
    @{ name = 'U.S. Social Security Number (SSN)'; mincount = '1' },
    @{ name = 'Credit Card Number'; mincount = '1' }
)

$existingPolicy = Get-DlpCompliancePolicy -Identity $PolicyName -ErrorAction SilentlyContinue

if ($existingPolicy -and -not $Force) {
    Write-Host "Policy '$PolicyName' already exists (Mode: $($existingPolicy.Mode)). No changes made. Pass -Force to reconcile rules to this script's definition." -ForegroundColor Yellow
    return
}

if (-not $existingPolicy) {
    if ($PSCmdlet.ShouldProcess($PolicyName, 'New-DlpCompliancePolicy (ExchangeLocation All)')) {
        New-DlpCompliancePolicy -Name $PolicyName `
            -ExchangeLocation 'All' `
            -Mode $Mode `
            -Comment "Content-based (not label-conditioned) PII control: $Action outbound Exchange mail to external recipients containing SSN or Credit Card Number. Deployed by scenarios/dlp/exchange-pii-exfil-block. Owner: Security & Compliance team." `
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

# --- Rule 0 (Block mode + exception group only): logged, justified override for the exception group ---
if ($Action -eq 'Block' -and $ExceptionGroupEmail) {
    $rule0 = Get-DlpComplianceRule -Identity $ruleNameOverride -ErrorAction SilentlyContinue
    $rule0Params = @{
        Name                                 = $ruleNameOverride
        Policy                               = $PolicyName
        Priority                             = 0
        FromMemberOf                         = $ExceptionGroupEmail
        AccessScope                          = 'NotInOrganization'
        ContentContainsSensitiveInformation  = $piiSits
        BlockAccess                          = $true
        NotifyAllowOverride                  = @('WithJustification')
        NotifyUser                           = @('LastModifier') + $AdminNotificationEmail
        NotifyPolicyTipCustomText            = 'This message contains an SSN or full card number and is going to someone outside the organization. As a nominated business-exception sender, you may override with a documented business justification; all overrides are logged and reviewed.'
        GenerateAlert                        = $AdminNotificationEmail
        GenerateIncidentReport               = $AdminNotificationEmail
        ReportSeverityLevel                  = 'High'
        StopPolicyProcessing                 = $true
    }
    if (-not $rule0) {
        if ($PSCmdlet.ShouldProcess($ruleNameOverride, 'New-DlpComplianceRule')) {
            New-DlpComplianceRule @rule0Params -WhatIf:$WhatIfPreference | Out-Null
        }
        Write-Host "Created rule '$ruleNameOverride'." -ForegroundColor Green
    }
    elseif ($Force) {
        $rule0Params.Remove('Policy') | Out-Null
        $rule0Params.Remove('Name') | Out-Null
        if ($PSCmdlet.ShouldProcess($ruleNameOverride, 'Set-DlpComplianceRule')) {
            Set-DlpComplianceRule -Identity $ruleNameOverride @rule0Params -WhatIf:$WhatIfPreference
        }
        Write-Host "Updated rule '$ruleNameOverride'." -ForegroundColor Green
    }
}
elseif ($Force) {
    # Action switched away from Block, or the exception group was removed: drop a stale override rule if one exists.
    $staleRule0 = Get-DlpComplianceRule -Identity $ruleNameOverride -ErrorAction SilentlyContinue
    if ($staleRule0) {
        if ($PSCmdlet.ShouldProcess($ruleNameOverride, 'Remove-DlpComplianceRule (no longer applicable)')) {
            Remove-DlpComplianceRule -Identity $ruleNameOverride -Confirm:$false -WhatIf:$WhatIfPreference
        }
        Write-Host "Removed rule '$ruleNameOverride' (Action is '$Action' or -ExceptionGroupEmail was not supplied)." -ForegroundColor Yellow
    }
}

# --- Rule 1: block or encrypt everyone else's external-recipient traffic ---
$rule1 = Get-DlpComplianceRule -Identity $ruleNameExternal -ErrorAction SilentlyContinue
$rule1Params = @{
    Name                                 = $ruleNameExternal
    Policy                               = $PolicyName
    Priority                             = 1
    AccessScope                          = 'NotInOrganization'
    ContentContainsSensitiveInformation  = $piiSits
    NotifyUser                           = @('LastModifier') + $AdminNotificationEmail
    GenerateAlert                        = $AdminNotificationEmail
    GenerateIncidentReport               = $AdminNotificationEmail
    ReportSeverityLevel                  = 'High'
    StopPolicyProcessing                 = $true
}
if ($ExceptionGroupEmail) {
    $rule1Params['ExceptIfFromMemberOf'] = $ExceptionGroupEmail
}
if ($Action -eq 'Block') {
    $rule1Params['BlockAccess'] = $true
    $rule1Params['NotifyPolicyTipCustomText'] = 'This message was blocked because it contains an SSN or full card number and was addressed to someone outside the organization. Contact the Security team if you have a legitimate business need.'
}
else {
    $rule1Params['EncryptRMSTemplate'] = $EncryptTemplateName
    $rule1Params['NotifyPolicyTipCustomText'] = 'This message contains an SSN or full card number and was addressed to someone outside the organization. It has been automatically encrypted before delivery.'
}
if (-not $rule1) {
    if ($PSCmdlet.ShouldProcess($ruleNameExternal, 'New-DlpComplianceRule')) {
        New-DlpComplianceRule @rule1Params -WhatIf:$WhatIfPreference | Out-Null
    }
    Write-Host "Created rule '$ruleNameExternal' (Action: $Action)." -ForegroundColor Green
}
elseif ($Force) {
    $rule1Params.Remove('Policy') | Out-Null
    $rule1Params.Remove('Name') | Out-Null
    # Reconciling Action requires clearing whichever action parameter is no longer in use.
    if ($Action -eq 'Block') {
        Set-DlpComplianceRule -Identity $ruleNameExternal -RemoveRMSTemplate $true -WhatIf:$WhatIfPreference -ErrorAction SilentlyContinue
    }
    else {
        Set-DlpComplianceRule -Identity $ruleNameExternal -BlockAccess $false -WhatIf:$WhatIfPreference -ErrorAction SilentlyContinue
    }
    if ($PSCmdlet.ShouldProcess($ruleNameExternal, 'Set-DlpComplianceRule')) {
        Set-DlpComplianceRule -Identity $ruleNameExternal @rule1Params -WhatIf:$WhatIfPreference
    }
    Write-Host "Updated rule '$ruleNameExternal' (Action: $Action)." -ForegroundColor Green
}

# --- Rule 2: audit-only for internal PII shares (the fork rules 0/1 never see - see design.md §5) ---
$rule2 = Get-DlpComplianceRule -Identity $ruleNameAuditInternal -ErrorAction SilentlyContinue
$rule2Params = @{
    Name                                 = $ruleNameAuditInternal
    Policy                               = $PolicyName
    Priority                             = 2
    AccessScope                          = 'InOrganization'
    ContentContainsSensitiveInformation  = $piiSits
    BlockAccess                          = $false
    GenerateAlert                        = $AdminNotificationEmail
    GenerateIncidentReport               = $AdminNotificationEmail
    ReportSeverityLevel                  = 'Low'
}
if (-not $rule2) {
    if ($PSCmdlet.ShouldProcess($ruleNameAuditInternal, 'New-DlpComplianceRule')) {
        New-DlpComplianceRule @rule2Params -WhatIf:$WhatIfPreference | Out-Null
    }
    Write-Host "Created rule '$ruleNameAuditInternal'." -ForegroundColor Green
}
elseif ($Force) {
    $rule2Params.Remove('Policy') | Out-Null
    $rule2Params.Remove('Name') | Out-Null
    if ($PSCmdlet.ShouldProcess($ruleNameAuditInternal, 'Set-DlpComplianceRule')) {
        Set-DlpComplianceRule -Identity $ruleNameAuditInternal @rule2Params -WhatIf:$WhatIfPreference
    }
    Write-Host "Updated rule '$ruleNameAuditInternal'." -ForegroundColor Green
}

Write-Host "`nDone. Run validate/Test-ExchangePiiDlpPolicy.ps1 to verify the deployed configuration." -ForegroundColor Cyan
```

#### `Remove-ExchangePiiDlpPolicy.ps1`

```powershell
#Requires -Modules @{ ModuleName = 'ExchangeOnlineManagement'; ModuleVersion = '3.2.0' }
<#
.SYNOPSIS
    Removes (or disables) the "PII DLP - Exchange External Send Control" DLP policy.

.DESCRIPTION
    Two rollback modes:
      -Disable (default, recommended first step): sets the policy Mode to Disable. Reversible in
       seconds via Set-DlpCompliancePolicy -Mode Enable. No history is lost.
      -Purge: permanently deletes the policy and all its rules via Remove-DlpCompliancePolicy.
       Removing the policy also removes its rules (Microsoft Learn: remove-dlpcompliancepolicy).
       This is NOT reversible - re-deploying requires re-running New-ExchangePiiDlpPolicy.ps1.

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
    ./Remove-ExchangePiiDlpPolicy.ps1 -WhatIf

.EXAMPLE
    ./Remove-ExchangePiiDlpPolicy.ps1
    # Disables the policy (soft rollback).

.EXAMPLE
    ./Remove-ExchangePiiDlpPolicy.ps1 -Purge
    # Permanently deletes the policy and its rules.

.NOTES
    Sources: https://learn.microsoft.com/powershell/module/exchangepowershell/set-dlpcompliancepolicy
             https://learn.microsoft.com/powershell/module/exchangepowershell/remove-dlpcompliancepolicy
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$PolicyName = 'PII DLP - Exchange External Send Control',

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